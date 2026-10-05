// Regenerates the screenshots of the in-app overlay.
//
// The overlay is the half of CodeScout that needs no server, and until now it
// appeared in no screenshot anywhere: the website, the docs and every README
// described it in prose and showed the dashboard instead. Somebody deciding
// whether to try this could see the thing they get after standing up Postgres
// and not the thing they get in two minutes.
//
// A test rather than a tool, because `CSxInterface` takes an `initialTab` and
// `LogBuffer` is seedable, so each tab renders directly with no navigation and
// no device. It skips unless CS_SHOTS_OUT names a directory, the same way the
// e2e suites skip without CS_E2E_BASE, so a normal `flutter test` never writes
// anything.
//
//   CS_SHOTS_OUT=.github/assets/screenshots flutter test test/overlay_shots_test.dart
//
// The story is deliberately the same one the dashboard captures use over in
// the server repo: a checkout that fails after a token refresh comes back 401.
// The two sets sit next to each other on the website, and telling one story
// twice is what makes them read as one product rather than two screenshots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone, in logical pixels, captured at 3x so the type survives being put
/// on a web page next to a 2x dashboard capture.
const _size = Size(390, 844);
const _scale = 3.0;

final _out = Platform.environment['CS_SHOTS_OUT'];

void main() {
  final out = _out;
  if (out == null || out.isEmpty) {
    // Not a failure. Nobody running the suite wants PNGs written into their
    // working tree.
    return;
  }

  setUpAll(_loadRealFonts);
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  Future<void> shoot(
    WidgetTester tester,
    OverlayTab tab,
    String name, {
    Future<void> Function()? then,
  }) async {
    tester.view.physicalSize = _size * _scale;
    tester.view.devicePixelRatio = _scale;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: CSxInterface(initialTab: tab)),
      ),
    ));
    await tester.pumpAndSettle();
    if (then != null) {
      await then();
      await tester.pumpAndSettle();
    }

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    // runAsync, and not for tidiness: rasterising is real asynchronous work on
    // a thread the test's fake clock does not drive. Called directly the image
    // does come back and the PNG is correct, and then the test never finishes —
    // no error, no timeout, just a `flutter test` that sits there. It cost an
    // hour to find, so it is written down rather than left as a spare await.
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _scale);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      final file = File('$out/overlay-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());

      // ignore: avoid_print
      print('  overlay-$name.png');
    });
  }

  testWidgets('logs', (tester) async {
    await _seedStory(tester);
    await shoot(tester, OverlayTab.logs, 'logs');
  });

  testWidgets('network', (tester) async {
    await _seedStory(tester);
    await shoot(tester, OverlayTab.network, 'network');
  });

  testWidgets('errors', (tester) async {
    await _seedStory(tester);
    await shoot(tester, OverlayTab.errors, 'errors');
  });

  // A 200 whose body no longer matches the app's model, opened on its
  // Response pane, with the app's own log about it above the body.
  testWidgets('network detail with a linked parse failure', (tester) async {
    await _seedStory(tester, cartParseFailure: true);
    await shoot(
      tester,
      OverlayTab.network,
      'network-linked-log',
      then: () async {
        await tester.tap(find.text('/v2/cart'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Response'));
      },
    );
  });
}

/// The cart call's id, fixed so the parse failure can name it. Every id is a
/// UUID because the SDK drops any request id that is not one.
const _cartCall = '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37';

/// Without this every glyph is a box.
///
/// `flutter test` renders with a font collection that has no real faces in it,
/// so text measures and paints as Ahem. Roboto and the Material icon font both
/// ship inside the Flutter SDK, which is where these come from — no new asset
/// and nothing to keep in step.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError(
      'FLUTTER_ROOT is not set, so the real fonts cannot be found and every '
      'glyph would render as a box. Run this through `flutter test`.',
    );
  }

  final dir = Directory('$root/bin/cache/artifacts/material_fonts');

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final name in files) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);

  await _loadMonospace();
}

/// The overlay sets `fontFamily: 'monospace'` with Menlo and Courier behind it,
/// and the Flutter SDK ships no monospace face. Left unloaded, every timestamp
/// down the left of the log list renders as a row of Ahem boxes — which is
/// exactly what the first capture came out looking like.
///
/// Taken from the host rather than vendored, because the point of these images
/// is to show what the overlay looks like on a phone, and the host's system
/// mono is the closest thing available to what the phone would pick. If none of
/// these exist the capture still succeeds and the timestamps fall back to
/// Roboto, so a Linux box gets a slightly wrong screenshot rather than no
/// screenshot and a confusing failure.
Future<void> _loadMonospace() async {
  const candidates = [
    '/System/Library/Fonts/SFNSMono.ttf',
    '/System/Library/Fonts/Supplemental/Andale Mono.ttf',
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
  ];

  String? path;
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      path = candidate;
      break;
    }
  }
  if (path == null) {
    // ignore: avoid_print
    print('  no monospace face found; timestamps will use the default');
    return;
  }

  final bytes = ByteData.sublistView(File(path).readAsBytesSync());

  // Both names: 'monospace' is what the style asks for and 'Menlo' is the
  // first fallback, and which one wins is not worth depending on.
  for (final family in ['monospace', 'Menlo']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
}

/// One launch of a shop app, ending badly.
///
/// Seeded in real time, with actual pauses between the entries.
///
/// `LogEntry` stamps itself with `DateTime.now()` in its constructor and takes
/// no timestamp, which is the right design for the SDK and means a story cannot
/// simply be dated. Written back to back, every row came out reading the same
/// second and every network call came out at 0ms, which is a screenshot quietly
/// claiming the product cannot measure a duration. The waits sit inside
/// `runAsync` because the test's own clock is fake and would skip them.
Future<void> _seedStory(WidgetTester tester, {bool cartParseFailure = false}) async {
  Future<void> pause(int ms) =>
      tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

  Future<void> log(
    LogLevel level,
    String message, {
    Set<String> tags = const {},
    Map<String, dynamic>? metadata,
    String? error,
    String? requestId,
    int after = 40,
  }) async {
    LogBuffer.i.add(LogEntry(
      level: level,
      message: message,
      sessionID: 'session',
      tags: tags,
      metadata: metadata,
      error: error,
      requestId: requestId,
    ));
    await pause(after);
  }

  /// One call, as the two entries the SDK actually writes. The wait between
  /// them is what both the overlay and the dashboard read as its duration.
  Future<void> call(
    String id,
    String method,
    String url, {
    int? status,
    String? failure,
    Map<String, dynamic>? headers,
    Object? body,
    int took = 120,
  }) async {
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Request',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: NetworkCallPhase.request,
      metadata: {'method': method, 'url': url},
    ));
    await pause(took);
    LogBuffer.i.add(LogEntry(
      level: failure == null ? LogLevel.debug : LogLevel.error,
      message: failure == null ? 'Network Response' : 'Network Error',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: id,
      callPhase: failure == null ? NetworkCallPhase.response : NetworkCallPhase.error,
      metadata: {
        'method': method,
        'url': url,
        'status_code': ?status,
        'message': ?failure,
        'headers': ?headers,
        'body': ?body,
      },
    ));
    await pause(40);
  }

  await log(LogLevel.info, 'App launched', tags: {'lifecycle'});
  await log(LogLevel.info, 'User signed in', tags: {'auth'}, metadata: {'method': 'oauth'});
  await call(
    _cartCall,
    'GET',
    'https://api.shop.dev/v2/cart',
    status: 200,
    took: 96,
    headers: cartParseFailure ? const {'content-type': 'application/json'} : null,
    body: cartParseFailure
        ? const {
            'items': [
              {'sku': 'mug-01', 'qty': 1, 'price_cents': 1899},
              {'sku': 'tee-02', 'qty': 1, 'price_cents': 2400},
              {'sku': 'pin-03', 'qty': 2, 'price_cents': 350},
            ],
            'subtotal_cents': 4999,
            'tax_rate': 0,
          }
        : null,
  );
  if (cartParseFailure) {
    // tax_rate came back as 0, an int, and the model casts it to a double.
    await log(
      LogLevel.error,
      'Could not read GET /v2/cart',
      tags: {'cart'},
      error: "type 'int' is not a subtype of type 'double' in type cast",
      requestId: _cartCall,
    );
  }
  await log(LogLevel.info, 'Checkout started', tags: {'checkout'});
  await log(LogLevel.warning, 'Token expired, refreshing', tags: {'auth'});
  await call('0e7d2f4a-5b1c-4f8e-9a3d-6c2b1e0f7a95', 'POST', 'https://api.shop.dev/v2/auth/refresh', status: 401, took: 210);
  // 401 rather than a timeout: the retry reused the token the refresh had just
  // failed to replace. The dashboard's seed tells the same story, and a film
  // that says 401 beside a screenshot saying "error" is worse than no film.
  await call('c4a9e1b7-2d6f-4e3a-8b5c-1f0d9e7a6b24', 'POST', 'https://api.shop.dev/v2/pay', status: 401, took: 380);
  await log(
    LogLevel.error,
    'Payment declined',
    tags: {'checkout', 'payments'},
    error: 'PaymentException: card_declined',
    metadata: {'order': 'ord_8812f', 'total': 49.99},
  );
  await log(
    LogLevel.error,
    'Payment declined',
    tags: {'checkout', 'payments'},
    error: 'PaymentException: card_declined',
    metadata: {'order': 'ord_9a41c', 'total': 18.50},
  );
  await log(LogLevel.warning, 'Checkout abandoned', tags: {'checkout'});
}
