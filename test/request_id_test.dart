import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/log/log_compressor.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A log can name the HTTP call it is about, so a body that broke the app's
/// model can be read next to the error it caused.
///
/// The server stores request_id as a UUID and decodes a whole upload at once,
/// so one id that does not parse fails the batch, and the sync worker retries
/// that batch forever with every later log queued behind it. Everything here
/// is about keeping that from happening while the link still works.
void main() {
  const upper = '3B8E0C51-7F2D-4A9E-B1C4-92D05E6A1F37';
  const lower = '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37';

  LogEntry linked(String? id, {Map<String, dynamic>? metadata}) => LogEntry(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        sessionID: 's-1',
        requestId: id,
        metadata: metadata,
      );

  // What NetworkManager does with a call an interceptor reports, without the
  // init check in front of it.
  Future<void> interceptCall(String id) async {
    final request = NetworkRequestData(
      method: 'GET',
      url: Uri.parse('https://api.shop.dev/v2/cart'),
      requestID: id,
    );
    await request.logEntry.processLogEntry(networkData: request);
    final response = NetworkResponseData(statusCode: 200, body: {'tax_rate': 0})
      ..attachNetworkRequest(request);
    await response.logEntry.processLogEntry(networkData: request);
  }

  group('LogEntry keeps only a UUID', () {
    late List<String> warnings;

    setUp(() {
      warnings = [];
      LogEntry.requestIdWarning = warnings.add;
      LogEntry.resetRequestIdWarning();
    });

    tearDown(() {
      LogEntry.requestIdWarning = (message) {};
      LogEntry.resetRequestIdWarning();
    });

    // The live frame carries the id as a string and the dashboard pairs by
    // comparing strings, while the phases a companion package mints are
    // lowercase. An uppercase copy would never meet them.
    test('an uppercase id is lowercased', () {
      final entry = linked(upper);
      expect(entry.requestId, lower);
      expect(entry.toJson()['request_id'], lower);
      expect(warnings, isEmpty);
    });

    test('what is not a UUID becomes null', () {
      const rejected = [
        'req_123',
        '',
        // A ULID, which is what many backends put in X-Request-Id.
        '01ARZ3NDEKTSV4RRFFQ69G5FAV',
        // 32 hex digits with no dashes, like nginx's $request_id.
        '3b8e0c517f2d4a9eb1c492d05e6a1f37',
        '{3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37}',
        'urn:uuid:3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37',
        ' 3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37',
        '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f3g',
      ];
      for (final id in rejected) {
        final entry = linked(id);
        expect(entry.requestId, isNull, reason: '"$id" should have been dropped');
        expect(entry.toJson()['request_id'], isNull, reason: '"$id" reached toJson');
      }
    });

    // Said once, and never with the value in it: an app that passes the wrong
    // header here may be passing its bearer token.
    test('a dropped id is reported once, without the value', () {
      linked('Bearer sk_live_9f21b');
      linked('req_123');
      linked(lower);

      expect(warnings, hasLength(1));
      expect(warnings.single, isNot(contains('sk_live_9f21b')));
      expect(warnings.single, isNot(contains('Bearer')));
      expect(warnings.single, contains('not a UUID'));
    });
  });

  // A phase's id is minted by an interceptor, not passed in by the app, and it
  // is what pairs the call's phases on the device. Only the server needs it to
  // be a UUID.
  group('a network phase', () {
    late List<String> warnings;

    setUp(() {
      LogBuffer.i.clear();
      warnings = [];
      LogEntry.requestIdWarning = warnings.add;
      LogEntry.resetRequestIdWarning();
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
      );
    });

    tearDown(() {
      LogBuffer.i.clear();
      LogEntry.requestIdWarning = (message) {};
      LogEntry.resetRequestIdWarning();
      CodeScout.instance.configuration = CodeScoutConfiguration();
    });

    test("keeps an interceptor's own id, so its call still pairs on the device", () async {
      await interceptCall('req-42');

      final calls = LogBuffer.i.calls();
      expect(calls, hasLength(1), reason: 'the call is gone from the Network tab');
      expect(calls.single.requestId, 'req-42');
      expect(calls.single.phases, hasLength(2));
      final request = calls.single.phase(NetworkCallPhase.request)!;
      expect(NetworkRequestData.fromLogEntry(request).requestID, 'req-42');
      expect(warnings, hasLength(1), reason: 'the interceptor is told once');
      expect(warnings.single, isNot(contains('req-42')));
    });

    test("an uppercase UUID is lowercased, so the app's log about it pairs", () async {
      await interceptCall(upper);
      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        requestId: upper,
      );

      final call = LogBuffer.i.calls().single;
      expect(call.requestId, lower);
      expect(call.logs.map((e) => e.message), ['Could not read GET /v2/cart']);
      expect(warnings, isEmpty);
    });
  });

  // The public API, not the constructor: these pin that every entry point
  // actually hands the id to the entry it builds.
  group('the logging API', () {
    setUp(() {
      LogBuffer.i.clear();
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
        redaction: const RedactionBehavior(bodyKeys: {'password'}),
      );
    });

    tearDown(() {
      LogBuffer.i.clear();
      CodeScout.instance.configuration = CodeScoutConfiguration();
    });

    test('logMessage links the log and keeps it an ordinary log', () async {
      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        error: "type 'int' is not a subtype of type 'double' in type cast",
        stackTrace: StackTrace.current,
        metadata: {'field': 'tax_rate', 'password': 'hunter2'},
        requestId: upper,
      );

      final entry = LogBuffer.i.entries.single;
      expect(entry.requestId, lower);
      expect(entry.isNetworkCall, isFalse);
      expect(entry.callPhase, isNull);
      // A network entry skips both of these, which is why the link must never
      // be made by marking the log as network.
      expect(entry.metadata!['password'], Redactor.placeholder);
      expect(entry.metadata!['field'], 'tax_rate');
      expect(entry.stackCallDetails, isNotEmpty);
    });

    test('log and every shorthand pass it through', () async {
      final scout = CodeScout.instance;
      final calls = <String, void Function(String)>{
        'log': (id) => scout.log(level: LogLevel.info, message: 'log', requestId: id),
        'v': (id) => scout.v('v', requestId: id),
        'd': (id) => scout.d('d', requestId: id),
        'i': (id) => scout.i('i', requestId: id),
        'w': (id) => scout.w('w', requestId: id),
        'e': (id) => scout.e('e', requestId: id),
        'f': (id) => scout.f('f', requestId: id),
      };

      for (final MapEntry(key: name, value: call) in calls.entries) {
        final id = NetworkRequestData.newRequestID();
        call(id);
        await pumpEventQueue();
        final entry = LogBuffer.i.entries.firstWhere((e) => e.message == name);
        expect(entry.requestId, id, reason: '$name dropped the request id');
        expect(entry.isNetworkCall, isFalse, reason: name);
      }
    });
  });

  // The upload reads rows back out of SQLite and archives them, so this runs
  // the real write and the real archive rather than trusting toJson alone.
  group('the upload payload', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      // Its own directory: test files run in parallel and the service always
      // opens code_scout.db by that one name.
      await databaseFactory
          .setDatabasesPath(Directory.systemTemp.createTempSync('cs-request-id').path);
    });

    setUp(() async {
      await LogPersistenceService.i.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/code_scout.db');
      LogBuffer.i.clear();
      LogEntry.requestIdWarning = (message) {};
      CodeScout.instance.isSessionSampledIn = true;
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
        projectCredentials: ProjectCredentials(
          link: 'https://scout.example.dev/',
          projectID: 'a3f2c7d1-4e88-4b21-9f60-1c2d3e4f9c41',
          projectSecret: 'secret',
        ),
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );
    });

    tearDown(() async {
      await LogPersistenceService.i.close();
      LogBuffer.i.clear();
      LogEntry.resetRequestIdWarning();
      CodeScout.instance.configuration = CodeScoutConfiguration();
    });

    Future<Map<String, Map<String, dynamic>>> uploaded() async {
      final rows = await LogPersistenceService.i.getLogEntries();
      final archive = TarDecoder()
          .decodeBytes(GZipDecoder().decodeBytes(LogCompressor.archiveBytes(rows, const [])));
      final data = archive.files.firstWhere((f) => f.name == 'data.json');
      final logs = (jsonDecode(utf8.decode(data.content as List<int>)) as List)
          .cast<Map<String, dynamic>>();
      return {for (final log in logs) log['message'] as String: log};
    }

    test('an id the server could not parse goes up as null', () async {
      for (final (message, id) in [('underscored', 'req_123'), ('empty', '')]) {
        await CodeScout.instance.logMessage(
          level: LogLevel.error,
          message: message,
          requestId: id,
        );
      }

      final logs = await uploaded();
      expect(logs.keys, containsAll(['underscored', 'empty']),
          reason: 'the log itself must still be written');
      expect(logs['underscored']!['request_id'], isNull);
      expect(logs['empty']!['request_id'], isNull);
    });

    test('a valid id goes up lowercased, on a log that is not a phase', () async {
      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        requestId: upper,
      );

      final log = (await uploaded())['Could not read GET /v2/cart']!;
      expect(log['request_id'], lower);
      expect(log['is_network_call'], 0);
      expect(log['call_phase'], isNull);
    });

    // The device keeps an interceptor's own id to pair the call, but this is
    // the column the server parses, and one bad row fails the whole batch.
    test("an interceptor's id that is not a UUID goes up as null", () async {
      await interceptCall('req-42');

      final logs = await uploaded();
      for (final (message, phase) in [
        ('Network Request', 'request'),
        ('Network Response', 'response'),
      ]) {
        final log = logs[message];
        expect(log, isNotNull, reason: '$message must still be written');
        expect(log!['request_id'], isNull, reason: '$message carried an id the server cannot parse');
        expect(log['is_network_call'], 1);
        expect(log['call_phase'], phase);
      }
    });
  });
}
