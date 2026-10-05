import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay is the only part of CodeScout someone uses without a server,
/// so its filters have to work on their own.
///
/// The Session tab's two tests moved out with the tab. What they covered —
/// that the sync line says what the uploader is actually doing, and that the
/// buffer's size is not presented as an upload queue — belongs to the Info
/// screen and lands with it.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  void add(String message, {LogLevel level = LogLevel.info, Set<String> tags = const {}}) {
    LogBuffer.i.add(LogEntry(
      level: level,
      message: message,
      sessionID: 'session',
      tags: tags,
    ));
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CSxInterface()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('logs list newest first', (tester) async {
    add('older');
    add('newer');

    await pumpSheet(tester);

    expect(find.text('older'), findsOneWidget);
    expect(find.text('newer'), findsOneWidget);

    final newer = tester.getTopLeft(find.text('newer')).dy;
    final older = tester.getTopLeft(find.text('older')).dy;
    expect(newer, lessThan(older), reason: 'the newest log should be at the top');
  });

  testWidgets('a tag chip narrows, then hides, then clears', (tester) async {
    add('checkout log', tags: {'checkout'});
    add('heartbeat log', tags: {'heartbeat'});
    add('untagged log');

    await pumpSheet(tester);
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsOneWidget);

    // First tap: only this tag.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsNothing);
    expect(find.text('untagged log'), findsNothing);

    // Second tap: hide this tag. The untagged log comes back — it does not
    // carry the tag, so excluding it must not take the log with it.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsNothing);
    expect(find.text('heartbeat log'), findsOneWidget);
    expect(find.text('untagged log'), findsOneWidget);

    // Third tap: back to neutral.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsOneWidget);
    expect(find.text('untagged log'), findsOneWidget);
  });

  // The whole reason the minimum-level threshold was replaced. A threshold
  // cannot express "errors and info, not debug": asking for warnings took the
  // info line with it, and there was no way to get it back without also taking
  // debug. Independent toggles can, and this is the case that proves it.
  testWidgets('level toggles are independent, not a floor', (tester) async {
    add('a debug line', level: LogLevel.debug);
    add('an info line');
    add('it broke', level: LogLevel.error);

    await pumpSheet(tester);
    expect(find.text('a debug line'), findsOneWidget);

    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();

    expect(find.text('a debug line'), findsNothing, reason: 'debug was switched off');
    expect(find.text('an info line'), findsOneWidget,
        reason: 'info is quieter than error and must survive turning debug off');
    expect(find.text('it broke'), findsOneWidget);

    // And back on again.
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    expect(find.text('a debug line'), findsOneWidget);
  });

  testWidgets('a level chip carries its count from this launch', (tester) async {
    add('one', level: LogLevel.error);
    add('two', level: LogLevel.error);
    add('three');

    await pumpSheet(tester);

    // Scoped to the chip so it cannot match a log message that happens to be
    // the same digit.
    expect(
      find.descendant(of: find.byType(CSxChip), matching: find.text('2')),
      findsWidgets,
      reason: 'the Error chip should count the two errors',
    );
  });

  testWidgets('search filters, and turns follow off', (tester) async {
    add('payment_sheet_shown');
    add('cart_restored');

    await pumpSheet(tester);
    expect(find.byIcon(Icons.vertical_align_bottom), findsOneWidget,
        reason: 'follow starts on');

    await tester.enterText(find.byType(TextField).first, 'payment');
    await tester.pumpAndSettle();

    expect(find.text('payment_sheet_shown'), findsOneWidget);
    expect(find.text('cart_restored'), findsNothing);
    // You are reading, not watching.
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: 'searching pauses follow');
  });

  testWidgets('search reads the error and the tags, not only the message', (tester) async {
    add('nothing useful in this message', tags: {'checkout'});

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField).first, 'checkout');
    await tester.pumpAndSettle();

    expect(find.text('nothing useful in this message'), findsOneWidget);
  });

  // An id pasted from the dashboard or a bug report finds the call's phases
  // and the app's own log about it together.
  testWidgets('search finds a request id', (tester) async {
    final id = NetworkRequestData.newRequestID();
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Response',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.response,
      metadata: const {'status_code': 200},
    ));
    LogBuffer.i.add(LogEntry(
      level: LogLevel.error,
      message: 'Could not read GET /v2/cart',
      sessionID: 'session',
      requestId: id,
    ));
    add('an unrelated log');

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField).first, id);
    await tester.pumpAndSettle();

    expect(find.text('Network Response'), findsOneWidget);
    expect(find.text('Could not read GET /v2/cart'), findsOneWidget);
    expect(find.text('an unrelated log'), findsNothing);

    await tester.enterText(find.byType(TextField).first, id.substring(0, 8));
    await tester.pumpAndSettle();

    expect(find.text('Network Response'), findsOneWidget,
        reason: 'the first block of the id is what a shortened copy keeps');
    expect(find.text('Could not read GET /v2/cart'), findsOneWidget);
  });

  // A random UUID contains any given three digits often enough that a search
  // for a status code would list calls that have nothing to do with it.
  testWidgets('a short search does not match a request id', (tester) async {
    void phase(String message, String id) => LogBuffer.i.add(LogEntry(
          level: LogLevel.debug,
          message: message,
          sessionID: 'session',
          isNetworkCall: true,
          requestId: id,
          callPhase: NetworkCallPhase.request,
          metadata: const {'method': 'GET', 'url': 'https://api.shop.dev/v2/cart'},
        ));
    phase('Network Request, id starts with it', '4042c1f7-9b3e-4d2a-8e6f-1a2b3c4d5e6f');
    phase('Network Request, id contains it', '7c1f4042-9b3e-4d2a-8e6f-1a2b3c4d5e6f');
    add('Profile returned 404');

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField).first, '404');
    await tester.pumpAndSettle();

    expect(find.text('Profile returned 404'), findsOneWidget);
    expect(find.text('Network Request, id starts with it'), findsNothing);
    expect(find.text('Network Request, id contains it'), findsNothing);
  });

  // Two empty states, never one. "Nothing logged yet" is false the moment a
  // filter is what emptied the list, and it points a developer at their own
  // logging calls instead of at the control they set.
  testWidgets('an empty list says which kind of empty it is', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);

    LogBuffer.i.add(LogEntry(level: LogLevel.info, message: 'hello', sessionID: 's'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('Nothing logged yet'), findsNothing,
        reason: 'a filter emptied the list, not the app');
    expect(find.text('Nothing matches these filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('the network tab shows calls, not phases', (tester) async {
    final id = NetworkRequestData.newRequestID();
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Request',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.request,
      metadata: const {'method': 'POST', 'url': 'https://api.test/v2/pay'},
    ));
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Response',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.response,
      metadata: const {'status_code': 201},
    ));

    await pumpSheet(tester);
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();

    // One row for the call, not one per phase.
    expect(find.text('/v2/pay'), findsOneWidget);
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
  });

  testWidgets('errors are counted by message, not listed one per occurrence', (tester) async {
    add('Payment declined', level: LogLevel.error);
    add('Payment declined', level: LogLevel.error);
    add('Something else', level: LogLevel.error);

    await pumpSheet(tester);
    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();

    expect(find.text('Payment declined'), findsOneWidget,
        reason: 'two occurrences are one row');
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('Something else'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });

  // The one empty state that is good news, and the one a healthy app shows
  // permanently. It must not read like "nothing logged yet".
  testWidgets('no errors is good news, and says the log count', (tester) async {
    add('one');
    add('two');

    await pumpSheet(tester);
    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();

    expect(find.text('No errors this launch'), findsOneWidget);
    expect(find.textContaining('2 logs'), findsOneWidget,
        reason: 'so it cannot be mistaken for the SDK being switched off');
  });

  // Opening the sheet does not clear the unseen count; opening Errors does. A
  // glance at Logs should not silently discard the signal.
  testWidgets('only the Errors tab clears the unseen count', (tester) async {
    add('it broke', level: LogLevel.error);
    expect(LogBuffer.i.unseenErrors, 1);

    await pumpSheet(tester);
    expect(LogBuffer.i.unseenErrors, 1, reason: 'opening the sheet is not looking at errors');

    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(LogBuffer.i.unseenErrors, 1, reason: 'nor is any other tab');

    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();
    expect(LogBuffer.i.unseenErrors, 0);
  });

  testWidgets('the sheet keeps its height across tabs', (tester) async {
    add('one log');
    await pumpSheet(tester);

    double height() => tester.getSize(find.byType(CSxInterface)).height;
    final onLogs = height();

    for (final tab in ['Network', 'Errors', 'Logs']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(height(), onLogs, reason: 'the sheet resized on the $tab tab');
    }
  });

  testWidgets('the live pill is reachable from every tab', (tester) async {
    add('one log');
    await pumpSheet(tester);

    for (final tab in ['Logs', 'Network', 'Errors']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text('Go live'), findsOneWidget,
          reason: 'pairing is a connection control, not a tab, so it shows on $tab');
    }
  });
}
