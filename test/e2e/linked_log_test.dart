// A log about a real HTTP call, from the app to the dashboard.
//
// sdk_to_dashboard_test.dart reports its call to NetworkManager by hand, under
// an id it minted itself. That proves the server keeps the link, but not that
// the id an app can actually get hold of is the one its call was stored under.
// Here the call goes through CodeScoutDioInterceptor to a real socket, the app
// reads the id off the response, and the dashboard is asked whether the two
// meet.
//
// Skipped unless CS_E2E_BASE points at a running server. `make test-sdk-e2e` in
// the code_scout repo starts a throwaway server and database and sets it.

import 'dart:convert';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout_dio/code_scout_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dashboard.dart';

const _cartFailure = 'Could not read GET /v2/cart';

/// The app's model of a cart, from before the backend started sending the
/// total as a whole number.
class _Cart {
  _Cart.fromJson(Map<String, dynamic> json) : total = json['total'] as double;

  final double total;
}

void main() {
  final env = Dashboard.baseFromEnvironment;
  if (env == null) {
    test('a log linked to its call', () {},
        skip: 'needs a running dashboard: set CS_E2E_BASE, '
            'or run `make test-sdk-e2e` in the code_scout repo');
    return;
  }

  final dash = Dashboard(env);
  HttpServer? backend;
  Dio? dio;
  late String requestID;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding answers every request with 400 without opening a socket,
    // which would fail the call this test is about as well as the upload.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Its own directory: the e2e files run in parallel and the persistence
    // service always opens code_scout.db under the same name.
    final scratch = Directory.systemTemp.createTempSync('cs-linked-e2e');
    await databaseFactory.setDatabasesPath(scratch.path);
    installScratchPaths(scratch.path);

    final server = backend =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'total': 12, 'items': <Object>[]}))
        ..close();
    });

    await dash.signIn();
    await dash
        .createProject('linked-e2e-${DateTime.now().millisecondsSinceEpoch}');

    await CodeScout.instance.init(
      configuration: CodeScoutConfiguration(
        // The interceptor writes a call's request and response at debug. At
        // the default of info the app's log would be stored and its call not.
        logging: LoggingBehavior(minimumLevel: LogLevel.debug),
        projectCredentials: ProjectCredentials(
          link: dash.base,
          projectID: dash.projectID,
          projectSecret: dash.projectSecret,
        ),
        // An hour, so the timer never fires and flush() is the only upload.
        sync: LogSyncBehavior(syncInterval: const Duration(hours: 1)),
      ),
    );
    expect(await CodeScout.instance.configuration.projectCredentials!.valid,
        isTrue,
        reason: 'the SDK could not validate against ${dash.base}');

    final client = dio = Dio(
        BaseOptions(baseUrl: 'http://${server.address.address}:${server.port}'))
      ..interceptors.add(CodeScoutDioInterceptor());

    final response = await client.get<Map<String, dynamic>>('/v2/cart');
    Object? failure;
    try {
      _Cart.fromJson(response.data!);
    } catch (e, st) {
      failure = e;
      CodeScout.instance.e(_cartFailure,
          error: e, stackTrace: st, requestId: response.codeScoutRequestId);
    }
    expect(failure, isA<TypeError>(),
        reason: 'the model read the body, so there was nothing to log');
    expect(response.codeScoutRequestId, isNotNull,
        reason: 'the interceptor never gave the call an id');
    requestID = response.codeScoutRequestId!;

    // None of the three is written behind an await the test can hold. The app's
    // log is waited for by its message, not its id, so an id the device dropped
    // fails an assertion below instead of this wait.
    await _awaitStored(
        (row) => row['request_id'] == requestID && row['is_network_call'] == 1,
        2);
    await _awaitStored((row) => row['message'] == _cartFailure, 1);
    await CodeScout.instance.flush();
  });

  tearDownAll(() async {
    dio?.close(force: true);
    await backend?.close(force: true);
    await CodeScout.instance.dispose();
  });

  test('the app log carries the id its call was stored under', () async {
    final found = await dash.exportLogs(query: 'request:$requestID');

    final phases = found.where((l) => l['is_network_call'] == true).toList();
    expect(phases.map((l) => l['call_phase']).toSet(), {'request', 'response'},
        reason: 'the call never reached the dashboard: $found');
    final response = phases.singleWhere((l) => l['call_phase'] == 'response');
    expect((response['metadata'] as Map)['body'], {'total': 12, 'items': []},
        reason: 'the body the model could not read is not stored with the call');

    final log = found.singleWhere((l) => l['message'] == _cartFailure,
        orElse: () => throw StateError(
            'the app log is not under request:$requestID: $found'));
    expect(log['request_id'], response['request_id']);
    expect(log['is_network_call'], isFalse);
    expect(log['call_phase'], isNull);
    expect(log['level'], 'error');
    expect(log['error'], contains("'int' is not a subtype of type 'double'"));
  });

  test('the call page lists it under Logged by the app', () async {
    final res = await dash.project('network/$requestID');
    expect(res.status, 200);

    final section = RegExp(r'<section[^>]*\bdata-linked-logs\b[\s\S]*?</section>')
        .firstMatch(res.body)
        ?.group(0);
    expect(section, isNotNull,
        reason: 'the call page has no section for the app log');
    expect(section, contains('Logged by the app'));
    expect(section, contains(_cartFailure));
    // The page escapes the quotes around the type names.
    expect(section, contains('is not a subtype of type'));

    // The call's two phases are its tabs, and the app's log is not a third.
    expect(res.body, isNot(contains('data-call-not-captured')));
    expect(RegExp('data-target="tab-').allMatches(res.body), hasLength(2),
        reason: 'the call page does not have one tab per phase');
  });

  // A backend's own X-Request-Id is the id most likely to be passed by
  // mistake. The server decodes request_id as a UUID and an upload as a whole,
  // and the worker always sends the oldest logs first, so one id it cannot
  // parse would fail every upload after it.
  test('an id that is not a UUID does not hold up the logs behind it',
      () async {
    const dropped = 'e2e logged with a backend id';
    const after = 'e2e logged after it';

    CodeScout.instance.e(dropped, requestId: 'req_123');
    await _awaitStored((row) => row['message'] == dropped, 1);
    await CodeScout.instance.flush();

    CodeScout.instance.i(after);
    await _awaitStored((row) => row['message'] == after, 1);
    await CodeScout.instance.flush();

    final logs = await dash.exportLogs();
    expect(logs.map((l) => l['message']), contains(after),
        reason: 'a log written after the bad id never arrived');
    final arrived = logs.singleWhere((l) => l['message'] == dropped);
    expect(arrived['request_id'], isNull);

    final db = await LogPersistenceService.i.database;
    expect(await db.query('logs'), isEmpty,
        reason: 'the device is still holding logs the server refused');
  });
}

/// Polls rather than sleeping, so a slow machine does not fail and a fast one
/// does not wait.
Future<void> _awaitStored(
    bool Function(Map<String, Object?> row) match, int count) async {
  final db = await LogPersistenceService.i.database;
  for (var i = 0; i < 100; i++) {
    if ((await db.query('logs')).where(match).length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final have = (await db.query('logs')).where(match).length;
  fail('only $have of $count logs reached SQLite');
}
