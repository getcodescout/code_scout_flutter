import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay reads this and nothing else, so what it holds is what someone
/// holding the phone sees.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  LogEntry entry(
    String message, {
    LogLevel level = LogLevel.info,
    Set<String> tags = const {},
    bool network = false,
    String? requestId,
    NetworkCallPhase? phase,
    Map<String, dynamic>? metadata,
  }) {
    return LogEntry(
      level: level,
      message: message,
      sessionID: 'session',
      tags: tags,
      isNetworkCall: network,
      requestId: requestId,
      callPhase: phase,
      metadata: metadata,
    );
  }

  test('newest first, which is the order the overlay lists them', () {
    LogBuffer.i.add(entry('first'));
    LogBuffer.i.add(entry('second'));

    expect(LogBuffer.i.entries.map((e) => e.message), ['second', 'first']);
  });

  // A chatty app must not grow the heap without bound, and the entry that
  // falls off has to be the oldest — losing the newest would drop the one you
  // opened the overlay to look at.
  test('the buffer is capped, and drops the oldest', () {
    for (var i = 0; i < LogBuffer.maxEntries + 20; i++) {
      LogBuffer.i.add(entry('log $i'));
    }

    expect(LogBuffer.i.length, LogBuffer.maxEntries);
    expect(LogBuffer.i.entries.first.message, 'log ${LogBuffer.maxEntries + 19}');
    expect(LogBuffer.i.entries.last.message, 'log 20');
  });

  test('tags are ranked by use, so the chips are the ones worth having', () {
    LogBuffer.i.add(entry('a', tags: {'network', 'checkout'}));
    LogBuffer.i.add(entry('b', tags: {'network'}));
    LogBuffer.i.add(entry('c', tags: {'network'}));
    LogBuffer.i.add(entry('d', tags: {'checkout'}));
    LogBuffer.i.add(entry('e', tags: {'rare'}));

    expect(LogBuffer.i.tags(), ['network', 'checkout', 'rare']);
  });

  test('a log with no tags contributes none', () {
    LogBuffer.i.add(entry('plain'));
    expect(LogBuffer.i.tags(), isEmpty);
  });

  // One message can wrap different failures, and a row keyed on the message
  // alone would count the second as the first and never show it.
  test('errors are collapsed by message and error text together', () {
    const message = 'Could not read GET /v2/cart';
    const intForDouble = "type 'int' is not a subtype of type 'double' in type cast";
    const nullForString = "type 'Null' is not a subtype of type 'String' in type cast";
    LogEntry failure(String error) =>
        LogEntry(level: LogLevel.error, message: message, error: error, sessionID: 'session');

    LogBuffer.i
      ..add(failure(intForDouble))
      ..add(failure(intForDouble))
      ..add(failure(nullForString));

    expect(
      LogBuffer.i.errorGroups().map((g) => (g.latest.error, g.count)),
      [(nullForString, 1), (intForDouble, 2)],
    );
  });

  group('network calls', () {
    void seedCall(String id, {int? status, bool error = false}) {
      LogBuffer.i.add(entry(
        'Network Request',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.request,
        metadata: {'method': 'POST', 'url': 'https://api.test/v2/pay'},
      ));
      if (status != null) {
        LogBuffer.i.add(entry(
          'Network Response',
          network: true,
          requestId: id,
          phase: NetworkCallPhase.response,
          metadata: {'status_code': status},
        ));
      }
      if (error) {
        LogBuffer.i.add(entry(
          'Network Error',
          level: LogLevel.error,
          network: true,
          requestId: id,
          phase: NetworkCallPhase.error,
          metadata: {'type': 'DioExceptionType.receiveTimeout'},
        ));
      }
    }

    test('phases pair into one call', () {
      seedCall(NetworkRequestData.newRequestID(), status: 200);
      LogBuffer.i.add(entry('not a network log'));

      final calls = LogBuffer.i.calls();
      expect(calls, hasLength(1));
      expect(calls.first.method, 'POST');
      expect(calls.first.path, '/v2/pay');
      expect(calls.first.statusCode, 200);
      expect(calls.first.status, '200');
      expect(calls.first.failed, isFalse);
    });

    test('a bad status and a transport error both read as failed', () {
      seedCall(NetworkRequestData.newRequestID(), status: 401);
      seedCall(NetworkRequestData.newRequestID(), error: true);

      final byStatus = {for (final c in LogBuffer.i.calls()) c.status: c};
      expect(byStatus['401']!.failed, isTrue);
      expect(byStatus['error']!.failed, isTrue);
      expect(byStatus['error']!.hasError, isTrue);
    });

    test('a call with only a request is pending, and has no duration', () {
      seedCall(NetworkRequestData.newRequestID());

      final call = LogBuffer.i.calls().single;
      expect(call.status, 'pending');
      // Timing an unfinished call against now would grow on every rebuild.
      expect(call.duration, isNull);
    });

    // The request phase falls off the back of the buffer long before the
    // response does on a chatty app. The response nests the request it belongs
    // to, so the row still knows what it called.
    test('a call whose request scrolled away still has a method and path', () {
      LogBuffer.i.add(entry(
        'Network Response',
        network: true,
        requestId: NetworkRequestData.newRequestID(),
        phase: NetworkCallPhase.response,
        metadata: {
          'status_code': 204,
          'request': {'method': 'DELETE', 'url': 'https://api.test/v2/cart/items/9f21'},
        },
      ));

      final call = LogBuffer.i.calls().single;
      expect(call.method, 'DELETE');
      expect(call.path, '/v2/cart/items/9f21');
      expect(call.hasRequest, isFalse);
    });

    test('a network log with no request id is not a call', () {
      LogBuffer.i.add(entry('Network Request', network: true));
      expect(LogBuffer.i.calls(), isEmpty);
    });
  });

  // A log the app writes about a call, such as a body its model could not
  // read, carries the call's request id and is not a network log. It must
  // ride along with the call and never be read as one of its phases.
  group('a log about a call', () {
    LogEntry parseFailure(String id, {Map<String, dynamic>? metadata}) => entry(
          'Could not read GET /v2/cart',
          level: LogLevel.error,
          requestId: id,
          metadata: metadata,
        );

    int pending(List<OverlayCall> calls) =>
        calls.where((c) => c.duration == null && !c.failed).length;

    test('rides along with its call and changes nothing about it', () async {
      final id = NetworkRequestData.newRequestID();
      LogBuffer.i.add(entry(
        'Network Request',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.request,
        metadata: {'method': 'GET', 'url': 'https://api.test/v2/cart'},
      ));
      LogBuffer.i.add(entry(
        'Network Response',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.response,
        metadata: {'status_code': 200},
      ));
      final before = pending(LogBuffer.i.calls());
      final took = LogBuffer.i.calls().single.duration;
      expect(took, isNotNull);

      // An app's log about a body is written after the call has ended, so as
      // a phase it would move the call's end to its own timestamp.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final failure = parseFailure(id);
      LogBuffer.i.add(failure);

      final calls = LogBuffer.i.calls();
      expect(calls, hasLength(1), reason: 'still one call, not a second row for the log');
      final call = calls.single;
      expect(call.status, '200');
      expect(call.statusCode, 200);
      expect(call.failed, isFalse, reason: 'HTTP worked; the app did not');
      expect(call.duration, took, reason: 'the call ends at its response');
      expect(pending(calls), before, reason: 'the Pending chip must not move');
      expect(call.phases, hasLength(2));
      expect(call.phases, isNot(contains(failure)));
      expect(call.logs, [failure]);
    });

    // The Errors tab keys an app log on its message and error, never on the
    // request id, so the same parse failure on two calls is one row that
    // counts. Keyed as a network error it would be two rows.
    test('is an ordinary error on the Errors tab', () {
      LogBuffer.i.add(parseFailure(NetworkRequestData.newRequestID()));
      LogBuffer.i.add(parseFailure(NetworkRequestData.newRequestID()));

      final groups = LogBuffer.i.errorGroups();
      expect(groups, hasLength(1));
      expect(groups.single.count, 2);
      expect(groups.single.isNetwork, isFalse);
    });

    // The app's log is written after its call, and the buffer drops the
    // oldest first, so the log routinely outlives the call. At the default
    // minimumLevel of info the call was never in the buffer at all.
    test('whose call is not in the buffer makes no row', () {
      final id = NetworkRequestData.newRequestID();
      LogBuffer.i.add(parseFailure(id));

      expect(LogBuffer.i.calls(), isEmpty,
          reason: 'a row here would be a phantom pending call with no method or path');
      expect(LogBuffer.i.callById(id), isNull);
    });

    // _requestMeta falls back to the newest entry whose metadata has a
    // 'request' map. An app log is newer than its call, so if it were a phase
    // its own metadata would name the call.
    test('cannot supply the method and path of its call', () {
      final id = NetworkRequestData.newRequestID();
      LogBuffer.i.add(entry(
        'Network Response',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.response,
        metadata: {
          'status_code': 200,
          'request': {'method': 'DELETE', 'url': 'https://api.test/v2/cart/items/9f21'},
        },
      ));
      LogBuffer.i.add(parseFailure(id, metadata: {
        'request': {'method': 'POST', 'url': 'https://elsewhere.test/v9/wrong'},
      }));

      final call = LogBuffer.i.calls().single;
      expect(call.method, 'DELETE');
      expect(call.path, '/v2/cart/items/9f21');
    });

    test('is found by its id', () {
      final id = NetworkRequestData.newRequestID();
      LogBuffer.i.add(entry(
        'Network Request',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.request,
        metadata: {'method': 'GET', 'url': 'https://api.test/v2/cart'},
      ));

      expect(LogBuffer.i.callById(id)?.requestId, id);
      expect(LogBuffer.i.callById(NetworkRequestData.newRequestID()), isNull);
    });
  });

  // The overlay is rebuilt from this, so a listener that never fires is a
  // sheet that stops updating while you watch it.
  test('adding notifies whoever is watching', () {
    var notifications = 0;
    void listener() => notifications++;

    LogBuffer.i.addListener(listener);
    addTearDown(() => LogBuffer.i.removeListener(listener));

    LogBuffer.i.add(entry('one'));
    LogBuffer.i.add(entry('two'));

    expect(notifications, 2);
  });
}
