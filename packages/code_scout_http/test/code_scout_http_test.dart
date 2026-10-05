import 'dart:convert';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
// LogBuffer is what the in-app panel reads, and the one place a captured phase
// can be read back without a server. The core does not export it.
// ignore: implementation_imports
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout_http/code_scout_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:http/testing.dart';

void main() {
  _closeTests();

  // Regression tests for the two 1.0.0 release-breaking bugs:
  // 1. The wrapper returned an already-drained body stream, so every read of
  //    the response threw "Stream has already been listened to".
  // 2. Capture before CodeScout.instance.init() threw LateInitializationError
  //    into the caller's request. Note init() is deliberately NOT called here.
  test('caller can read the response body and capture never fails the request',
      () async {
    final client = CodeScoutHttpClient(
      client: MockClient(
        (request) async => http.Response('{"ok":true}', 200),
      ),
    );

    final res = await client.get(Uri.parse('https://example.com/data'));

    expect(res.statusCode, 200);
    expect(res.body, '{"ok":true}');
  });

  test('errors from the inner client are rethrown untouched', () async {
    final client = CodeScoutHttpClient(
      client: MockClient((request) async => throw http.ClientException('boom')),
    );

    expect(
      () => client.get(Uri.parse('https://example.com/data')),
      throwsA(isA<http.ClientException>()),
    );
  });

  _requestIdTests();
  _errorMessageTests();
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

/// Closing the wrapper has to close what it wraps.
///
/// `BaseClient.close()` is a no-op, so a caller doing the documented thing —
/// a client per unit of work, closed in a finally — kept every pooled socket
/// the inner client held. Wrapping a client silently changed what closing it
/// meant.
class _ClosableSpy extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 200);

  @override
  void close() => closed = true;
}

void _closeTests() {
  test('close() closes the wrapped client', () {
    final inner = _ClosableSpy();

    CodeScoutHttpClient(client: inner).close();

    expect(inner.closed, isTrue,
        reason: 'the inner client kept its whole connection pool');
  });
}

/// An app links its own log to a call by passing this id, so it has to be the
/// id the call's phases were captured under, or the two never meet.
void _requestIdTests() {
  group('codeScoutRequestId names the captured call', () {
    setUp(_initCapturingEverything);

    // The handler's Response carries no request, and MockClient passes that
    // along, so the response has to be given the request this client was sent.
    test('on a response from a client that names no request', () async {
      final client = CodeScoutHttpClient(
        client: MockClient(
          (request) async => http.Response('{"ok":true}', 200),
        ),
      );

      final response = await client.get(Uri.parse('https://example.com/data'));

      final call = LogBuffer.i.calls().single;
      expect(call.hasResponse, isTrue);
      expect(response.codeScoutRequestId, call.requestId);
    });

    // RetryClient sends a copy of each request, so the response that comes back
    // through it names the copy rather than the request this client was sent.
    test('on a response through a RetryClient', () async {
      final client = CodeScoutHttpClient(client: RetryClient(_EchoClient()));

      final response = await client.get(Uri.parse('https://example.com/data'));

      expect(response.codeScoutRequestId, LogBuffer.i.calls().single.requestId);
    });

    // A failure leaves no response to read the id from, so the request has to
    // carry it from before it goes out.
    test('on a request that failed before any response', () async {
      final client = CodeScoutHttpClient(
        client: MockClient((request) async => throw http.ClientException('boom')),
      );
      final request = http.Request('GET', Uri.parse('https://example.com/data'));

      await expectLater(client.send(request), throwsA(isA<http.ClientException>()));

      final call = LogBuffer.i.calls().single;
      expect(call.hasError, isTrue);
      expect(request.codeScoutRequestId, call.requestId);
    });
  });

  // The getter is read from an app's own error handling, where a throw would
  // bury the real error. A response built by hand, or by MockClient, carries no
  // request at all.
  test('a response that did not come through this client reads as null',
      () async {
    final unwrapped = await _EchoClient().get(Uri.parse('https://example.com/data'));

    expect(http.Response('{"ok":true}', 200).codeScoutRequestId, isNull);
    expect(unwrapped.codeScoutRequestId, isNull);
  });
}

void _errorMessageTests() {
  // dart:io quotes what it rejects, and nothing redacts this message, so a real
  // socket is the only honest way to see what reaches it.
  group('the error phase message', () {
    late HttpServer server;
    late CodeScoutHttpClient client;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      await _initCapturingEverything(redaction: RedactionBehavior.recommended());
      client = CodeScoutHttpClient(client: http.Client());
      addTearDown(client.close);
    });

    Uri cart() => Uri.parse('http://127.0.0.1:${server.port}/cart');

    // A token read from a file or an environment variable can end in a newline,
    // which no header value may contain.
    test('never quotes a header value the app redacted', () async {
      await expectLater(
        client.get(cart(), headers: {'Authorization': 'Bearer sk_live_9f21b\n'}),
        throwsA(isA<FormatException>()),
      );

      final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
      expect(phase.metadata!['message'], '');
      expect('${phase.metadata}', isNot(contains('sk_live_9f21b')));
    });

    test('never quotes the request body', () async {
      final request = http.StreamedRequest('POST', cart())..contentLength = 5;
      request.sink
        ..add(utf8.encode('{"password":"hunter2_9f21b"}'))
        ..close();

      await expectLater(
        client.send(request),
        throwsA(isA<http.ClientException>()),
      );

      final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
      expect(phase.metadata!['message'], '');
      expect('${phase.metadata}', isNot(contains('hunter2_9f21b')));
    });

    test('keeps what a socket failure says', () async {
      final refused = cart();
      await server.close(force: true);

      SocketException? failure;
      try {
        await client.get(refused);
      } on SocketException catch (e) {
        failure = e;
      }

      final phase = LogBuffer.i.calls().single.phase(NetworkCallPhase.error)!;
      expect(failure?.message, isNotEmpty);
      expect(phase.metadata!['message'], failure!.message);
    });
  });
}

/// Answers with the request it was sent, as IOClient does.
class _EchoClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
    );
  }
}
