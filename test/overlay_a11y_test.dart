import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay is a debug tool, which is not a reason for it to be unusable.
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

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: CSxInterface()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('touch targets', () {
    // The platform minimum. The tab row used to be 35px and the filter chips
    // 24px, and chips are the most-tapped control in the sheet.
    testWidgets('every tab and header control clears 44px', (tester) async {
      add('one log', tags: {'checkout'});
      await pumpSheet(tester);

      for (final label in ['Logs', 'Network', 'Errors']) {
        final size = tester.getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        ).first);
        expect(size.height, greaterThanOrEqualTo(GlobalVars.minTouchTarget),
            reason: 'the $label tab is only ${size.height}px tall');
      }

      for (final icon in [Icons.info_outline, Icons.close]) {
        final size = tester.getSize(find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(InkWell),
        ).first);
        expect(size.height, greaterThanOrEqualTo(GlobalVars.minTouchTarget));
        expect(size.width, greaterThanOrEqualTo(GlobalVars.minTouchTarget));
      }
    });

    // The whole row opens the call, so the whole row is the target.
    testWidgets("a log's Call link clears 44px", (tester) async {
      final id = NetworkRequestData.newRequestID();
      LogBuffer.i.add(LogEntry(
        level: LogLevel.debug,
        message: 'Network Request',
        sessionID: 'session',
        isNetworkCall: true,
        requestId: id,
        callPhase: NetworkCallPhase.request,
        metadata: const {'method': 'GET', 'url': 'https://api.shop.dev/v2/cart'},
      ));
      LogBuffer.i.add(LogEntry(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        sessionID: 'session',
        requestId: id,
      ));
      await pumpSheet(tester);
      await tester.tap(find.text('Could not read GET /v2/cart'));
      await tester.pumpAndSettle();

      final link = tester.getSize(find.ancestor(
        of: find.text('/v2/cart'),
        matching: find.byType(InkWell),
      ).first);
      expect(link.height, greaterThanOrEqualTo(GlobalVars.minTouchTarget),
          reason: 'the Call link is only ${link.height}px tall');
    });

    // Visible ink can be smaller than the target: padding does the reach, which
    // is what keeps a dense debug tool dense.
    testWidgets('a filter chip is tappable across the whole row height', (tester) async {
      add('one log');
      await pumpSheet(tester);

      final row = tester.getSize(find.ancestor(
        of: find.text('Error'),
        matching: find.byType(SizedBox),
      ).last);
      expect(row.height, greaterThanOrEqualTo(GlobalVars.minTouchTarget));
    });
  });

  group('text scaling', () {
    // 3.0, not 2.5. At 2.5 the scrollable tab row absorbs it on its own, so a
    // test at that scale passed with the cap removed and proved nothing. 3.0 is
    // where the sheet actually overflows without it.
    testWidgets('a large system text scale does not overflow the sheet', (tester) async {
      for (var i = 0; i < 12; i++) {
        add('a reasonably long log message number $i', tags: {'checkout', 'analytics'});
      }
      add('it broke', level: LogLevel.error);

      await pumpSheet(tester, textScale: 3);

      // Any overflow is reported as an exception by the test binding.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cap still lets text grow', (tester) async {
      add('measure me');
      await pumpSheet(tester);
      final small = tester.getSize(find.text('measure me')).height;

      await pumpSheet(tester, textScale: 2.5);
      final large = tester.getSize(find.text('measure me')).height;

      expect(large, greaterThan(small),
          reason: 'capping is not the same as ignoring the setting');
    });
  });

  group('a short viewport', () {
    // Two chip rows plus a search bar is 148px of chrome above the list. On a
    // landscape phone that leaves about two rows, which is not a log viewer.
    testWidgets('the filter rows collapse into one control', (tester) async {
      for (var i = 0; i < 20; i++) {
        add('log number $i', tags: {'checkout'});
      }

      await pumpSheet(tester, size: const Size(844, 390));

      expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget,
          reason: 'the chips move behind one control');
      // The chips themselves are gone from the list, not merely scrolled.
      expect(find.text('Fatal'), findsNothing);
    });

    testWidgets('and the collapsed control still filters', (tester) async {
      add('a debug line', level: LogLevel.debug);
      add('an info line');

      await pumpSheet(tester, size: const Size(844, 390));
      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Debug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('a debug line'), findsNothing);
      expect(find.text('an info line'), findsOneWidget);
    });

    testWidgets('a tall viewport keeps the chips where they are', (tester) async {
      add('one log');
      await pumpSheet(tester);

      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
      expect(find.text('Fatal'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('a chip says what it is and what state it is in', (tester) async {
      add('one log');
      await pumpSheet(tester);

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Error, shown')),
        findsOneWidget,
        reason: 'state must reach a screen reader, not only the colour',
      );
      handle.dispose();
    });
  });
}
