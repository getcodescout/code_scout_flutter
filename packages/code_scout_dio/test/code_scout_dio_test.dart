import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_scout/code_scout.dart';
// LogBuffer is what the in-app panel reads, and the one place a captured phase
// can be read back without a server. The core does not export it.
// ignore: implementation_imports
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout_dio/code_scout_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a canned response without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.body = '{"ok":true}'});

  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'network down',
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<DioException> _caught(Future<Object?> call) async {
  try {
    await call;
  } on DioException catch (e) {
    return e;
  }
  fail('the call succeeded, and it was meant to fail');
}

/// Network logs are written at debug, and the default level drops them before
/// the buffer, which would leave no phase to compare against.
Future<void> _initCapturingEverything({
  RedactionBehavior redaction = const RedactionBehavior(),
}) async {
  await CodeScout.instance.init(
    configuration: CodeScoutConfiguration(
      logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
      redaction: redaction,
    ),
  );
  addTearDown(CodeScout.instance.dispose);
  LogBuffer.i.clear();
  addTearDown(LogBuffer.i.clear);
}

/// The interceptor runs inside the caller's request chain, so anything it throws
/// fails the HTTP request rather than merely losing a log line. These cover the
/// uninitialized case, which used to throw a LateInitializationError.
void main() {
  Dio dioWith(HttpClientAdapter adapter) => Dio()
    ..httpClientAdapter = adapter
    ..interceptors.add(CodeScoutDioInterceptor());

  test('a request succeeds when CodeScout was never initialized', () async {
    final response = await dioWith(
      _FakeAdapter(),
    ).get<dynamic>('https://example.com/thing');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
  });

  test('an error status still surfaces to the caller', () async {
    expect(
      () => dioWith(
        _FakeAdapter(status: 500, body: '{}'),
      ).get<dynamic>('https://example.com/thing'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });

  test('a transport error propagates unchanged', () async {
    expect(
      () => dioWith(_ThrowingAdapter()).get<dynamic>('https://example.com/x'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionError,
        ),
      ),
    );
  });

  test('a correlation id is stamped on the request', () async {
    final dio = dioWith(_FakeAdapter());

    final response = await dio.get<dynamic>('https://example.com/thing');

    expect(
      response.requestOptions.extra['codescout_request_id'],
      isA<String>(),
    );
  });

  _requestIdTests(dioWith);
  _undecodableBodyTests(dioWith);
  _errorMessageTests(dioWith);
}

typedef _DioWith = Dio Function(HttpClientAdapter adapter);

/// An app links its own log to a call by passing this id, so it has to be the
/// id the call's phases were captured under, or the two never meet.
void _requestIdTests(_DioWith dioWith) {
  group('codeScoutRequestId names the captured call', () {
    setUp(_initCapturingEverything);

    test('on a response', () async {
      final response = await dioWith(
        _FakeAdapter(),
      ).get<dynamic>('https://example.com/thing');

      final call = LogBuffer.i.calls().single;
      expect(call.hasResponse, isTrue);
      expect(response.codeScoutRequestId, call.requestId);
    });

    test('on the exception for an error status', () async {
      final error = await _caught(dioWith(
        _FakeAdapter(status: 500, body: '{}'),
      ).get<dynamic>('https://example.com/thing'));

      final call = LogBuffer.i.calls().single;
      expect(call.statusCode, 500);
      expect(error.codeScoutRequestId, call.requestId);
    });

    test('on the exception for a transport failure', () async {
      final error = await _caught(
        dioWith(_ThrowingAdapter()).get<dynamic>('https://example.com/x'),
      );

      final call = LogBuffer.i.calls().single;
      expect(call.hasError, isTrue);
      expect(error.codeScoutRequestId, call.requestId);
    });

    // The failure this feature is for. dio casts the body to the type asked for
    // after every interceptor has run, so the call was captured as an answered
    // 200 and only the app ever sees the cast fail.
    test('on the exception for a body that does not fit the type asked for',
        () async {
      final error = await _caught(dioWith(
        _FakeAdapter(body: '[1, 2, 3]'),
      ).get<Map<String, dynamic>>('https://example.com/cart'));

      expect(error.error, isA<TypeError>());
      final call = LogBuffer.i.calls().single;
      expect(call.status, '200');
      expect(call.hasError, isFalse);
      expect(error.codeScoutRequestId, call.requestId);
    });
  });

  // extra is a map every interceptor can write to, and the getter is called
  // from an app's own error handling, where a throw would bury the real error.
  test('a value under the key that is not a string reads as null', () {
    final options = RequestOptions(extra: {codeScoutRequestIdKey: 42});

    expect(options.codeScoutRequestId, isNull);
  });
}

/// dio wraps the FormatException from its JSON transformer with no message of
/// its own, which left the call's error phase saying nothing at all.
void _undecodableBodyTests(_DioWith dioWith) {
  group('a body that is not JSON', () {
    test('is named in the error phase', () async {
      await _initCapturingEverything();

      final error = await _caught(dioWith(
        _FakeAdapter(body: '<html>Bad gateway</html>'),
      ).get<dynamic>('https://example.com/cart'));

      final call = LogBuffer.i.calls().single;
      final phase = call.phase(NetworkCallPhase.error)!;
      expect(phase.metadata!['message'], 'FormatException');
      expect(error.codeScoutRequestId, call.requestId);
    });

    // BackgroundTransformer hands the parser a String, and then the exception's
    // toString() appends the line of the body it stopped on. The message is not
    // redacted, so that line would carry a key the app asked to strip.
    test('never puts the body in the error phase', () async {
      await _initCapturingEverything(
        redaction: const RedactionBehavior(bodyKeys: {'token'}),
      );
      final dio = dioWith(_FakeAdapter(body: '{"cart": {"token": "sk_live_9f21b"'))
        ..transformer = BackgroundTransformer();

      await _caught(dio.get<dynamic>('https://example.com/cart'));

      final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
      expect(phase.metadata!['message'], 'FormatException');
      expect(jsonEncode(phase.metadata), isNot(contains('sk_live_9f21b')));
    });
  });
}

void _errorMessageTests(_DioWith dioWith) {
  group('the error phase message', () {
    // An error phase is the only one the default level keeps, and a bad status
    // or a dropped connection is what most of them are.
    test("is dio's own when dio wrote one", () async {
      await _initCapturingEverything();

      final failures = [
        await _caught(dioWith(
          _FakeAdapter(status: 500, body: '{}'),
        ).get<dynamic>('https://example.com/status')),
        await _caught(
          dioWith(_ThrowingAdapter()).get<dynamic>('https://example.com/transport'),
        ),
      ];

      for (final failure in failures) {
        final call = LogBuffer.i.calls().singleWhere(
              (c) => c.requestId == failure.codeScoutRequestId,
            );
        expect(failure.message, isNotEmpty);
        expect(call.phase(NetworkCallPhase.error)!.metadata!['message'],
            failure.message);
      }
    });

    // dart:io quotes what it rejects, and nothing redacts this message, so a
    // real socket is the only honest way to see what reaches it.
    group('for an error dart:io describes with the request in it', () {
      late Dio dio;

      setUp(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));
        await _initCapturingEverything(
          redaction: RedactionBehavior.recommended(),
        );
        dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'))
          ..interceptors.add(CodeScoutDioInterceptor());
        addTearDown(() => dio.close(force: true));
      });

      // A token read from a file or an environment variable can end in a
      // newline, which no header value may contain.
      test('never quotes a header value the app redacted', () async {
        await _caught(dio.get<dynamic>(
          '/cart',
          options: Options(headers: {'Authorization': 'Bearer sk_live_9f21b\n'}),
        ));

        final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
        expect(phase.metadata!['message'], 'FormatException');
        expect('${phase.metadata}', isNot(contains('sk_live_9f21b')));
      });

      test('never quotes the request body', () async {
        await _caught(dio.post<dynamic>(
          '/cart',
          data: Stream.value(utf8.encode('{"password":"hunter2_9f21b"}')),
          options: Options(headers: {Headers.contentLengthHeader: 5}),
        ));

        final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
        expect(phase.metadata!['message'], 'HttpException');
        expect('${phase.metadata}', isNot(contains('hunter2_9f21b')));
      });
    });
  });
}
