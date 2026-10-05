// The SDK against a real dashboard, end to end.
//
// Every other test in this repo proves one half on its own: the archive has the
// right entries, the session SQL is right, the redactor strips what it was told
// to. None of them prove the two halves still agree, because both sides assert
// against a shape that is written down twice — once here and once in Go. Two
// copies of a contract drift, and nothing fails when they do.
//
// This test writes it down nowhere. It logs through the public API, lets the
// worker compress and upload, and reads the rows back out of the dashboard. If
// a field is renamed on either side, this is what goes red.
//
// Skipped unless CS_E2E_BASE points at a running server, the same way the Go
// integration tests skip without CS_TEST_DB. `make test-sdk-e2e` in the
// code_scout repo starts a throwaway server and database and sets it.

import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'dashboard.dart';

const _appVersion = '9.9.9';
const _buildNumber = '4242';
const _userID = 'sdk-e2e-user';

void main() {
  final env = Dashboard.baseFromEnvironment;
  if (env == null) {
    test('SDK to dashboard', () {},
        skip: 'needs a running dashboard: set CS_E2E_BASE, '
            'or run `make test-sdk-e2e` in the code_scout repo');
    return;
  }

  final dash = Dashboard(env);
  final requestID = const Uuid().v4();
  // Captured in setUpAll so the assertions below can say which session they
  // expected, rather than only that they found nothing.
  SessionRecord? launched;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding installs an HttpOverrides that answers every request with 400
    // and never opens a socket, which is the right default for a widget test
    // and fatal here — the SDK's uploader would "fail" without leaving the
    // process. Clearing it gives both sides a real network again.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Its own directory, like the other test files: they run in parallel and
    // the service always opens code_scout.db by the same name.
    final scratch = Directory.systemTemp.createTempSync('cs-sdk-e2e');
    await databaseFactory.setDatabasesPath(scratch.path);
    installScratchPaths(scratch.path);

    // The app version and build come from a platform channel that nothing
    // answers in a host test. Mocking them is what turns the app_version:
    // assertion below into a real check rather than a check for null.
    PackageInfo.setMockInitialValues(
      appName: 'CodeScout E2E',
      packageName: 'tech.codescout.e2e',
      version: _appVersion,
      buildNumber: _buildNumber,
      buildSignature: '',
    );

    await dash.signIn();
    await dash.createProject(
        'sdk-e2e-${DateTime.now().millisecondsSinceEpoch}');

    await CodeScout.instance.init(
      configuration: CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
        projectCredentials: ProjectCredentials(
          link: dash.base,
          projectID: dash.projectID,
          projectSecret: dash.projectSecret,
        ),
        // An hour, so the timer never fires. flush() is the only thing that
        // uploads here, which keeps the test from racing a cycle it did not
        // ask for.
        sync: LogSyncBehavior(syncInterval: const Duration(hours: 1)),
      ),
    );

    // init() swallows a bad credential quietly, because an app must start
    // whether or not its logging server is reachable. Here that would surface
    // as an empty dashboard several assertions later, so check it now.
    expect(await CodeScout.instance.configuration.projectCredentials!.valid,
        isTrue,
        reason: 'the SDK could not validate against ${dash.base}');

    await CodeScout.instance.logMessage(
      level: LogLevel.info,
      message: 'e2e hello',
      tags: {'e2e', 'greeting'},
      metadata: {'run': 'sdk'},
    );
    await CodeScout.instance.logMessage(
      level: LogLevel.error,
      message: 'e2e boom',
      error: 'something broke',
    );

    // A network call as the companion packages report it: three phases, one
    // request id. Only two of them here, since a call cannot both answer and
    // fail.
    NetworkManager.i.processNetworkRequest(NetworkRequestData(
      method: 'POST',
      url: Uri.parse('https://api.example.com/v2/pay'),
      requestID: requestID,
      body: {'amount': 100},
    ));
    NetworkManager.i.processNetworkResponse(
        NetworkResponseData(statusCode: 201, body: {'ok': true}), requestID);

    // What an app writes when the body it got no longer fits its model. The
    // request id is the only link to the call.
    await CodeScout.instance.logMessage(
      level: LogLevel.error,
      message: 'e2e could not read the body',
      error: "type 'int' is not a subtype of type 'double' in type cast",
      requestId: requestID,
    );

    // Identity is opt-in and lands mid-launch, which is the interesting case:
    // the logs above were already written before anyone had a name.
    await CodeScout.instance.setUser(_userID, traits: {'plan': 'free'});

    // The network pair is fire-and-forget — the manager does not await the
    // SQLite write — so wait for the rows rather than guessing at a delay.
    launched = CodeScout.instance.currentSession;

    await _awaitStored(5);
    await LogSyncWorker.i.flush();
  });

  tearDownAll(() async {
    await CodeScout.instance.dispose();
  });

  test('a successful upload clears the local queue', () async {
    final db = await LogPersistenceService.i.database;
    expect((await db.query('logs')), isEmpty,
        reason: 'logs the server accepted must not be kept and sent twice');
  });

  test('the logs arrive with their level, tags and metadata intact', () async {
    final logs = await dash.exportLogs();

    final hello = logs.firstWhere((l) => l['message'] == 'e2e hello',
        orElse: () => throw StateError('e2e hello never arrived: $logs'));
    expect(hello['level'], 'info');
    expect((hello['tags'] as List).toSet(), {'e2e', 'greeting'});
    expect(hello['metadata'], containsPair('run', 'sdk'));

    final boom = logs.firstWhere((l) => l['message'] == 'e2e boom',
        orElse: () => throw StateError('e2e boom never arrived: $logs'));
    expect(boom['level'], 'error');
    expect(boom['error'], contains('something broke'));
  });

  test('a network call arrives as two correlated phases', () async {
    final calls = (await dash.exportLogs())
        .where((l) => l['is_network_call'] == true)
        .toList();

    expect(calls, hasLength(2));
    expect(calls.map((c) => c['request_id']).toSet(), {requestID},
        reason: 'both phases belong to one call, or the dashboard cannot pair '
            'them back into a row');
    expect(calls.map((c) => c['call_phase']).toSet(), {'request', 'response'});
  });

  // The log the app wrote about that call must land as an ordinary log that
  // request: finds next to the call, or the link exists only on the device.
  test('a log about a call arrives linked to it, as an app log', () async {
    final found = await dash.exportLogs(query: 'request:$requestID');

    expect(found.map((l) => l['message']).toSet(),
        {'Network Request', 'Network Response', 'e2e could not read the body'},
        reason: 'request: should find the call and the log about it together');
    final log = found.firstWhere((l) => l['message'] == 'e2e could not read the body');
    expect(log['request_id'], requestID);
    expect(log['is_network_call'], isFalse);
    expect(log['call_phase'], isNull);
    expect(log['error'], contains("'int' is not a subtype"));
  });

  // Runs before the three that filter on session fields, because it separates
  // "the session never arrived" from "it arrived without this field". Both look
  // identical from a query that returns nothing.
  test('the launch itself reaches the dashboard', () async {
    expect(launched, isNotNull, reason: 'the SDK never recorded a session locally');
    expect(launched!.installationId, isNotNull,
        reason: 'no installation id, so DeviceProfile or the meta table failed');

    // Local first, then remote. The two together say which side lost it: a row
    // here and nothing on the dashboard means the upload or the server dropped
    // it; nothing here means the SDK never had one to send. A successful sync
    // keeps the running launch's row, so it is still expected to be present.
    final local = await LogPersistenceService.i.getSessionsByIds([launched!.id]);
    expect(local, isNotEmpty,
        reason: 'the SDK has no session row for this launch, so sessions.json '
            'was never in the archive. Session it built: ${launched!.toJson()}');

    final byInstall =
        await dash.exportLogs(query: 'installation:${launched!.installationId}');
    expect(byInstall, isNotEmpty,
        reason: 'no session reached the dashboard at all — sessions.json is '
            'missing from the upload, or was rejected. Session on the device: '
            '${launched!.toJson()}');
  });

  test('the session is attributed to the user set after the fact', () async {
    final logs = await dash.exportLogs(query: 'user:$_userID');
    expect(logs.map((l) => l['message']), contains('e2e hello'),
        reason: 'setUser() attributes the whole launch, including the logs '
            'written before it was called. Session on the device: '
            '${launched?.toJson()}');
  });

  test('a different user matches nothing', () async {
    expect(await dash.exportLogs(query: 'user:somebody-else'), isEmpty,
        reason: 'without this, a filter that is silently ignored would pass '
            'the test above');
  });

  test('the app version reaches the dashboard', () async {
    expect(await dash.exportLogs(query: 'app_version:$_appVersion'), isNotEmpty,
        reason: 'session on the device: ${launched?.toJson()}');
    expect(await dash.exportLogs(query: 'app_version:0.0.1'), isEmpty);
  });

  // The one assertion in the suite that proves both repositories agree about
  // sdk_version. The Go tests build sessions.json by hand, so they prove the
  // server reads that shape and not that the SDK still sends it; the Flutter
  // tests write it to SQLite with no server on the other end. Only this crosses
  // the gap, and it is the gap a half-committed fix once slipped through.
  test('the SDK version reaches the dashboard', () async {
    expect(await dash.exportLogs(query: 'sdk_version:$codeScoutSdkVersion'),
        isNotEmpty,
        reason: 'the dashboard has no session on SDK $codeScoutSdkVersion, so '
            'sdk_version was dropped somewhere between toJson and the column. '
            'Session on the device: ${launched?.toJson()}');

    // Without this, a filter the server silently ignores would pass the line
    // above by matching every session.
    expect(await dash.exportLogs(query: 'sdk_version:0.0.1'), isEmpty,
        reason: 'sdk_version: matched a version nothing is running, so the '
            'term is being ignored rather than applied');
  });

  test('the platform the SDK ran on reaches the dashboard', () async {
    // Whatever the test host is. The point is that DeviceProfile put something
    // real on the session, not which machine ran the suite.
    final os = Platform.operatingSystem;
    expect(await dash.exportLogs(query: 'os:$os'), isNotEmpty,
        reason: 'session on the device: ${launched?.toJson()}');
  });
}

/// Waits for the SDK's own SQLite write, which several capture paths do not
/// await. Polls rather than sleeping so a slow machine does not fail and a fast
/// one does not wait.
Future<void> _awaitStored(int count) async {
  final db = await LogPersistenceService.i.database;
  for (var i = 0; i < 100; i++) {
    if ((await db.query('logs')).length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final have = (await db.query('logs')).length;
  fail('only $have of $count logs reached SQLite');
}
