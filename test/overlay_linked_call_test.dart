import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 200 whose body no longer matches the app's model. HTTP worked and the app
/// did not, so the call stays a green 200 and the evidence is the app's own
/// log, linked by request id. These pin that the panel puts the two one tap
/// apart, and says so plainly when the call is not there to open.
void main() {
  const failure = 'Could not read GET /v2/cart';
  const why = "type 'int' is not a subtype of type 'double' in type cast";

  setUp(LogBuffer.i.clear);
  tearDown(() {
    LogBuffer.i.clear();
    CodeScout.instance.configuration = CodeScoutConfiguration();
  });

  void seedCall(String id, {bool answered = true}) {
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Request',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.request,
      metadata: const {'method': 'GET', 'url': 'https://api.shop.dev/v2/cart'},
    ));
    if (!answered) return;
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Response',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.response,
      metadata: const {
        'status_code': 200,
        'headers': {'content-type': 'application/json'},
        'body': {'subtotal_cents': 4999, 'tax_rate': 0},
      },
    ));
  }

  void seedFailure(String id) {
    LogBuffer.i.add(LogEntry(
      level: LogLevel.error,
      message: failure,
      error: why,
      sessionID: 'session',
      requestId: id,
    ));
  }

  CodeScoutConfiguration uploading() => CodeScoutConfiguration(
        projectCredentials: ProjectCredentials(
          link: 'https://scout.example.dev/',
          projectID: 'a3f2c7d1-4e88-4b21-9f60-1c2d3e4f9c41',
          projectSecret: 'secret',
        ),
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );

  Future<void> pumpSheet(WidgetTester tester, OverlayTab tab) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CSxInterface(initialTab: tab)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openCallResponse(WidgetTester tester) async {
    await pumpSheet(tester, OverlayTab.network);
    await tap(tester, find.text('/v2/cart'));
    await tap(tester, find.text('Response'));
  }

  String? Function() watchClipboard(WidgetTester tester) {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return () => copied;
  }

  group('a call opened from the Network tab', () {
    testWidgets('lists what the app logged about it, above the body', (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedCall(id);
      seedFailure(id);

      await openCallResponse(tester);

      expect(find.text('LOGGED BY THE APP'), findsOneWidget);
      expect(find.text(failure), findsOneWidget);
      expect(find.text(why), findsOneWidget, reason: 'the reason reads without opening the log');
      expect(
        tester.getTopLeft(find.text('LOGGED BY THE APP')).dy,
        lessThan(tester.getTopLeft(find.text('BODY')).dy),
        reason: 'the error reads directly over the body it could not read',
      );
      // Still a 200. The app's failure is not the call's.
      expect(find.text('GET  200'), findsOneWidget);
    });

    testWidgets('has no such section when the app logged nothing about it', (tester) async {
      seedCall(NetworkRequestData.newRequestID());
      seedFailure(NetworkRequestData.newRequestID());

      await openCallResponse(tester);

      expect(find.text('BODY'), findsOneWidget);
      expect(find.text('LOGGED BY THE APP'), findsNothing,
          reason: 'a log about a different call must not be listed here');
      expect(find.text(failure), findsNothing);
    });

    // Opening the log replaces this screen on the sheet's stack. Coming back
    // must land on the Response pane the log was opened from, not on Request.
    testWidgets('opens the log, and back returns to the response', (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedCall(id);
      seedFailure(id);

      await openCallResponse(tester);
      await tap(tester, find.text(failure));

      expect(find.text('LOGGED BY THE APP'), findsNothing);
      expect(find.text(why), findsOneWidget, reason: 'the log detail is open');

      await tap(tester, find.byTooltip('Back'));

      expect(find.text('LOGGED BY THE APP'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
    });
  });

  // A copied call is pasted into a bug report, where nobody can tap through to
  // the log. The parse failure has to travel with the body it is about.
  group('Copy call', () {
    Future<void> copyCall(WidgetTester tester) async {
      await pumpSheet(tester, OverlayTab.network);
      await tap(tester, find.text('/v2/cart'));
      await tap(tester, find.byTooltip('Copy call'));
    }

    testWidgets('carries what the app logged, where the Response pane lists it', (tester) async {
      final copied = watchClipboard(tester);
      final id = NetworkRequestData.newRequestID();
      seedCall(id);
      seedFailure(id);

      await copyCall(tester);

      final text = copied()!;
      final lines = text.split('\n');
      final at = lines.indexOf(failure);
      expect(at, greaterThan(0), reason: 'the message the Response pane shows');
      expect(lines[at - 1], matches(RegExp(r'^error \d\d:\d\d:\d\d\.\d{3}$')),
          reason: 'its level and time, as on the row');
      expect(lines[at + 1], why, reason: 'the error the row shows under the message');
      expect(lines, contains('[logged by the app]'));
      expect(text.indexOf('[request]'), lessThan(text.indexOf(failure)));
      expect(text.indexOf(why), lessThan(text.indexOf('[response]')),
          reason: 'above the response, as on the Response pane');
    });

    testWidgets('of a call the app logged nothing about is what it always was', (tester) async {
      final copied = watchClipboard(tester);
      final id = NetworkRequestData.newRequestID();
      seedCall(id);
      seedFailure(NetworkRequestData.newRequestID());

      await copyCall(tester);

      final ms = LogBuffer.i.callById(id)!.duration!.inMilliseconds;
      expect(copied(), '''
GET https://api.shop.dev/v2/cart
status 200
duration $ms ms

[request]
{
  "method": "GET",
  "url": "https://api.shop.dev/v2/cart"
}

[response]
{
  "status_code": 200,
  "headers": {
    "content-type": "application/json"
  },
  "body": {
    "subtotal_cents": 4999,
    "tax_rate": 0
  }
}''');
    });
  });

  group('a log about a call, opened', () {
    testWidgets('has a Call section that opens the call on its response', (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedCall(id);
      seedFailure(id);

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));

      expect(find.text('CALL'), findsOneWidget);
      expect(find.text('GET'), findsOneWidget);
      expect(find.text('/v2/cart'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text(id), findsNothing, reason: 'the call is here, so it is a link, not an id');

      await tap(tester, find.text('/v2/cart'));

      expect(find.text('GET  200'), findsOneWidget);
      expect(find.text('LOGGED BY THE APP'), findsOneWidget,
          reason: 'it opens on Response, where the body the log is about is');
      expect(find.text('BODY'), findsOneWidget);
    });

    // What a call looks like once the SDK stopped holding its request: the
    // request is in the buffer and the late response was dropped, while the
    // app still logged about the body it got.
    testWidgets('whose response was never recorded says why, without blaming the buffer',
        (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedCall(id, answered: false);
      seedFailure(id);

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));
      await tap(tester, find.text('/v2/cart'));

      expect(find.text('LOGGED BY THE APP'), findsOneWidget);
      expect(find.text('No response recorded'), findsOneWidget);
      expect(find.textContaining('two minutes'), findsOneWidget);
      expect(find.textContaining('fall off the back'), findsNothing);
    });

    // The usual case at the default minimumLevel of info: a 200's phases are
    // debug logs and never reach the buffer. It is also what happens once the
    // call falls off the back, since the app's log is written after it.
    testWidgets('whose call is not in the panel shows the full id to copy', (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedFailure(id);
      final copied = watchClipboard(tester);

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));

      expect(find.text('CALL'), findsOneWidget);
      expect(find.text(id), findsOneWidget, reason: 'in full: a shortened id finds nothing');
      expect(find.textContaining('This call is not in the panel'), findsOneWidget);
      expect(find.textContaining('minimumLevel info'), findsOneWidget);
      expect(find.text('/v2/cart'), findsNothing);

      final callCopy = find.descendant(
        of: find.ancestor(of: find.text('CALL'), matching: find.byType(Row)),
        matching: find.text('Copy'),
      );
      await tap(tester, callCopy);
      expect(copied(), id);
    });

    // In local mode nothing is uploaded, so there is nothing on a dashboard
    // to search for.
    testWidgets('points at the dashboard only when something is uploaded', (tester) async {
      final id = NetworkRequestData.newRequestID();
      seedFailure(id);

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));
      expect(find.textContaining('on the dashboard'), findsNothing);

      CodeScout.instance.configuration = uploading();
      // A fresh sheet, not the same one with the log still pushed on it.
      await tester.pumpWidget(const SizedBox());
      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));
      expect(find.textContaining('request: and this id on the dashboard'), findsOneWidget);
    });

    // Sampling decides once per launch, and a launch it left out uploads
    // nothing, so the dashboard has neither the log nor the call.
    testWidgets('does not point at the dashboard from a launch sampling left out',
        (tester) async {
      seedFailure(NetworkRequestData.newRequestID());
      CodeScout.instance.configuration = uploading();
      CodeScout.instance.isSessionSampledIn = false;
      addTearDown(() => CodeScout.instance.isSessionSampledIn = true);

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text(failure));

      expect(find.textContaining('This call is not in the panel'), findsOneWidget);
      expect(find.textContaining('on the dashboard'), findsNothing);
    });

    // A phase carries the same id and is the call itself, so a Call section on
    // it would only link the call to itself.
    testWidgets('a network phase has no Call section', (tester) async {
      seedCall(NetworkRequestData.newRequestID());

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text('Network Request'));

      expect(find.text('METADATA'), findsOneWidget, reason: 'the phase detail is open');
      expect(find.text('CALL'), findsNothing);
    });

    testWidgets('a log with no request id has no Call section', (tester) async {
      LogBuffer.i.add(LogEntry(
        level: LogLevel.error,
        message: 'Payment declined',
        sessionID: 'session',
      ));

      await pumpSheet(tester, OverlayTab.logs);
      await tap(tester, find.text('Payment declined'));

      expect(find.text('CALL'), findsNothing);
    });
  });
}
