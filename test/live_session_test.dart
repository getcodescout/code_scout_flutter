import 'dart:convert';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Live streaming is the one thing in this SDK that talks to the server over
/// something other than an HTTP request, so the tests run a real socket server
/// rather than a mock: the pairing frame the server reads is the contract, and
/// a mock would only prove the SDK agrees with itself.
void main() {
  group('the socket URL', () {
    // The base link is an http URL because everything else the SDK does is
    // HTTP. Deriving the socket URL from it is the one place a mistake would
    // silently downgrade a TLS instance to a plaintext socket.
    test('http becomes ws and https becomes wss', () {
      expect(socketUrlFor('http://localhost:24275/'), 'ws://localhost:24275/api/live/socket');
      expect(socketUrlFor('https://scout.team.dev/'), 'wss://scout.team.dev/api/live/socket');
    });

    test('a subpath is kept', () {
      expect(
        socketUrlFor('https://team.dev/code-scout/'),
        'wss://team.dev/code-scout/api/live/socket',
      );
    });

    test('a port is kept', () {
      expect(socketUrlFor('https://team.dev:8443/'), 'wss://team.dev:8443/api/live/socket');
    });
  });

  group('pairing', () {
    late HttpServer server;
    late String link;

    // The publish tests drive the real logging path, which writes to SQLite on
    // the way past. Its own databases directory: test files run in parallel
    // and the service always opens code_scout.db by that one name, so sharing
    // the default path lets one file delete a database another is using.
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory
          .setDatabasesPath(Directory.systemTemp.createTempSync('cs-live').path);
    });
    // What the server was told, so the test can assert on the real frame
    // rather than on what the client thinks it sent.
    Map<String, dynamic>? hello;
    List<Map<String, dynamic>> frames = [];
    bool accept = true;

    // Lets a test push a frame *to* the device, which is what the hub does when
    // a dashboard asks a question. Set once the socket is up.
    void Function(String)? serverSend;

    setUp(() async {
      hello = null;
      frames = [];
      accept = true;
      serverSend = null;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      link = 'http://127.0.0.1:${server.port}/';

      server.listen((request) async {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        // The credentials are checked before the code is ever read, exactly as
        // the real server does it.
        if (request.headers.value('X-Project-ID') == null) {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }

        final socket = await WebSocketTransformer.upgrade(request);
        serverSend = socket.add;
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          if (hello == null) {
            hello = message;
            socket.add(jsonEncode(accept
                ? {'ok': true, 'session_id': 'live-session-1'}
                : {'ok': false, 'error': 'that code is not valid'}));
            if (!accept) socket.close();
            return;
          }
          frames.add(message);
        });
      });
    });

    tearDown(() async {
      await LiveSessionClient.i.stop();
      await server.close(force: true);
    });

    CodeScoutConfiguration configured() => CodeScoutConfiguration(
          projectCredentials: ProjectCredentials(
            link: link,
            projectID: 'project-1',
            projectSecret: 'secret-1',
          ),
        );

    Future<bool> start(String code) => LiveSessionClient.i.start(
          code: code,
          configuration: configured(),
          currentSessionId: 'launch-1',
          session: SessionRecord(
            id: 'launch-1',
            installationId: 'install-1',
            deviceModel: 'Pixel 7',
            osName: 'Android',
            osVersion: '14',
            appVersion: '3.11.2',
            buildNumber: '418',
            startedAt: DateTime.now().toUtc(),
            lastSeenAt: DateTime.now().toUtc(),
          ),
        );

    test('the code and the device go up in the first frame', () async {
      expect(await start('4K7Q2P'), isTrue);

      expect(hello, isNotNull);
      expect(hello!['code'], '4K7Q2P');

      // Snake case, matching the server's LiveDevice. Camel case here would be
      // silently dropped and every device would render as "Unknown device".
      final device = hello!['device'] as Map<String, dynamic>;
      expect(device['session_id'], 'launch-1');
      expect(device['installation_id'], 'install-1');
      expect(device['device_model'], 'Pixel 7');
      expect(device['os_name'], 'Android');
      expect(device['os_version'], '14');
      expect(device['app_version'], '3.11.2');
      expect(device['build_number'], '418');
    });

    test('the client goes live once the server accepts', () async {
      expect(await start('4K7Q2P'), isTrue);
      expect(LiveSessionClient.i.state, LiveSessionState.live);
      expect(LiveSessionClient.i.isLive, isTrue);
      expect(LiveSessionClient.i.sessionId, 'live-session-1');
      expect(LiveSessionClient.i.error, isNull);
    });

    // A refusal is the common case — codes are typed by hand and expire — so
    // it has to end somewhere a person can act on, not in an exception.
    test('a refused code fails with the reason and never throws', () async {
      accept = false;

      expect(await start('ZZZZZZ'), isFalse);
      expect(LiveSessionClient.i.isLive, isFalse);
      expect(LiveSessionClient.i.error, 'that code is not valid');
      expect(LiveSessionClient.i.state, LiveSessionState.ended);
    });

    test('a server that is not there fails rather than hanging', () async {
      // Port 1 is reserved and nothing listens on it.
      final ok = await LiveSessionClient.i.start(
        code: '4K7Q2P',
        configuration: CodeScoutConfiguration(
          projectCredentials: ProjectCredentials(
            link: 'http://127.0.0.1:1/',
            projectID: 'p',
            projectSecret: 's',
          ),
        ),
        currentSessionId: 'launch-1',
      );

      expect(ok, isFalse);
      expect(LiveSessionClient.i.error, isNotNull);
    });

    test('with no credentials it refuses and says why', () async {
      final ok = await LiveSessionClient.i.start(
        code: '4K7Q2P',
        configuration: CodeScoutConfiguration(),
        currentSessionId: 'launch-1',
      );

      expect(ok, isFalse);
      expect(LiveSessionClient.i.error, contains('credentials'));
    });

    // The wire shape a watcher renders. The upload format is deliberately not
    // reused, so this is the only thing pinning it.
    test('a published log arrives in the shape the dashboard reads', () async {
      expect(await start('4K7Q2P'), isTrue);

      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'payment declined',
      );

      await _until(() => frames.any((f) => (f['logs'] as List).isNotEmpty));

      final logs = frames
          .expand((f) => (f['logs'] as List).cast<Map<String, dynamic>>())
          .toList();
      expect(logs, isNotEmpty);
      expect(logs.first['level'], 'error');
      expect(logs.first['message'], 'payment declined');
      expect(logs.first['timestamp'], isA<String>());
      // Parseable as ISO-8601, or every row renders with a blank time.
      expect(DateTime.tryParse(logs.first['timestamp'] as String), isNotNull);
    });

    test('a network call carries what the live inspector renders', () async {
      // Live frames never pass through ingest, so the promotion ingest does —
      // method, url, status_code out of the metadata — has to happen at the
      // socket. Without it every network row on the live screen has a phase
      // and nothing else to show.
      expect(await start('4K7Q2P'), isTrue);

      final id = NetworkRequestData.newRequestID();
      LiveSessionClient.i.publish(LogEntry(
        level: LogLevel.debug,
        message: 'Network Response',
        sessionID: 'launch-1',
        isNetworkCall: true,
        requestId: id,
        callPhase: NetworkCallPhase.response,
        metadata: {
          'method': 'POST',
          'url': 'https://api.shop.dev/v2/pay',
          'status_code': 402,
          'body': {'error': 'card_declined'},
        },
      ));

      await _until(() => frames.any((f) => (f['logs'] as List?)?.isNotEmpty ?? false));
      final log = frames
          .expand((f) => (f['logs'] as List? ?? const []).cast<Map<String, dynamic>>())
          .single;

      expect(log['is_network_call'], isTrue);
      expect(log['request_id'], id);
      expect(log['call_phase'], 'response');
      expect(log['method'], 'POST');
      expect(log['url'], 'https://api.shop.dev/v2/pay');
      expect(log['status_code'], 402);
      // The whole metadata rides along for the inspector's bodies and headers.
      expect((log['metadata'] as Map)['body'], {'error': 'card_declined'});
    });

    // The dashboard's live Network pane pairs frames by request id, but only
    // frames marked is_network_call. A log the app wrote about a call must
    // carry the id and nothing that would make the browser read it as a phase.
    test('a log about a call carries its id and nothing network shaped', () async {
      expect(await start('4K7Q2P'), isTrue);

      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        error: "type 'int' is not a subtype of type 'double' in type cast",
        // What an app describing its call might write. Promoted onto the
        // frame, these would be a phase's method, url and status.
        metadata: {
          'field': 'tax_rate',
          'method': 'GET',
          'url': 'https://api.shop.dev/v2/cart',
          'status_code': 200,
        },
        requestId: '3B8E0C51-7F2D-4A9E-B1C4-92D05E6A1F37',
      );

      await _until(() => frames.any((f) => (f['logs'] as List?)?.isNotEmpty ?? false));
      final log = frames
          .expand((f) => (f['logs'] as List? ?? const []).cast<Map<String, dynamic>>())
          .single;

      expect(log['request_id'], '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37',
          reason: 'lowercased, as the phases are, or the two never pair');
      expect(log['message'], 'Could not read GET /v2/cart');
      expect(log['error'], contains("'int' is not a subtype"));
      expect(log.containsKey('is_network_call'), isFalse);
      expect(log.containsKey('call_phase'), isFalse);
      expect(log.containsKey('method'), isFalse);
      expect(log.containsKey('url'), isFalse);
      expect(log.containsKey('status_code'), isFalse);
      expect(log.containsKey('metadata'), isFalse);
    });

    // Only the upload needs a UUID. A live frame never reaches the database,
    // so a custom interceptor's own id still pairs its call there.
    test("an interceptor's own id still pairs a call in a live session", () async {
      expect(await start('4K7Q2P'), isTrue);

      LiveSessionClient.i.publish(LogEntry(
        level: LogLevel.debug,
        message: 'Network Request',
        sessionID: 'launch-1',
        isNetworkCall: true,
        requestId: 'req-42',
        callPhase: NetworkCallPhase.request,
        metadata: {'method': 'GET', 'url': 'https://api.shop.dev/v2/cart'},
      ));

      await _until(() => frames.any((f) => (f['logs'] as List?)?.isNotEmpty ?? false));
      final log = frames
          .expand((f) => (f['logs'] as List? ?? const []).cast<Map<String, dynamic>>())
          .single;

      expect(log['request_id'], 'req-42');
      expect(log['call_phase'], 'request');
    });

    test('an ordinary log does not drag its metadata onto the wire', () async {
      expect(await start('4K7Q2P'), isTrue);

      LiveSessionClient.i.publish(LogEntry(
        level: LogLevel.info,
        message: 'cart viewed',
        sessionID: 'launch-1',
        metadata: {'items': 3},
      ));

      await _until(() => frames.any((f) => (f['logs'] as List?)?.isNotEmpty ?? false));
      final log = frames
          .expand((f) => (f['logs'] as List? ?? const []).cast<Map<String, dynamic>>())
          .single;

      // Nothing on the logs pane reads it, and a chatty app's metadata would
      // be pure frame weight on every single row.
      expect(log.containsKey('metadata'), isFalse);
      expect(log.containsKey('method'), isFalse);
    });

    test('nothing is sent once the session is stopped', () async {
      expect(await start('4K7Q2P'), isTrue);
      await LiveSessionClient.i.stop();

      expect(LiveSessionClient.i.isLive, isFalse);
      final before = frames.length;

      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'after the session ended',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(frames.length, before,
          reason: 'a stopped session must not keep streaming');
    });

    // publish() is called on every log, so it has to be free when nobody is
    // watching. This is the guard against the live path ever throwing into the
    group('the server can ask about databases', () {
      late Database appDb;

      setUp(() async {
        appDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await appDb.execute('CREATE TABLE flags (key TEXT NOT NULL, enabled INTEGER)');
        await appDb.insert('flags', {'key': 'checkout_v2', 'enabled': 0});
      });

      tearDown(() async {
        DatabaseRegistry.i.clear();
        await appDb.close();
      });

      /// Sends a question down the socket the way the hub does, and waits for
      /// the frame that comes back carrying the same request id.
      Future<Map<String, dynamic>> ask(String op, Map<String, dynamic> args) async {
        final before = frames.length;
        serverSend!(jsonEncode({'req': 'r1', 'op': op, 'args': args}));
        await _until(() => frames.length > before);
        return frames.last;
      }

      test('a question is answered under the same request id', () async {
        DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(appDb));
        expect(await start('4K7Q2P'), isTrue);

        final reply = await ask('sources', {});

        // The id is what lets the hub match this to the dashboard that asked.
        // Without it the answer is delivered to nobody and the request times out.
        expect(reply['req'], 'r1');
        expect(reply['ok'], isTrue);
        expect((reply['sources'] as List).single['name'], 'shop.db');
      });

      test('a page of rows comes back over the wire', () async {
        DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(appDb));
        expect(await start('4K7Q2P'), isTrue);

        final reply = await ask('rows', {'db': 'shop.db', 'namespace': 'flags'});

        expect(reply['ok'], isTrue);
        final page = reply['page'] as Map<String, dynamic>;
        expect(page['rows'], hasLength(1));
      });

      test('a question the device cannot answer still gets a reply', () async {
        expect(await start('4K7Q2P'), isTrue);

        final reply = await ask('rows', {'db': 'never-registered', 'namespace': 'flags'});

        // Silence would leave the dashboard waiting out its whole timeout and
        // unable to tell a bad query from a phone that went to sleep.
        expect(reply['req'], 'r1');
        expect(reply['ok'], isFalse);
      });

      test('a log frame is still a log frame', () async {
        // The req branch sits in front of the pairing branch, so this is the
        // check that it did not swallow the traffic the socket already carried.
        DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(appDb));
        expect(await start('4K7Q2P'), isTrue);

        await CodeScout.instance.logMessage(level: LogLevel.info, message: 'still streaming');
        await _until(() => frames.any((f) => f['logs'] != null));

        expect(frames.any((f) => (f['logs'] as List?)?.isNotEmpty ?? false), isTrue);
      });
    });

    // logging path.
    test('publishing with no session is a no-op', () async {
      expect(LiveSessionClient.i.isLive, isFalse);
      await CodeScout.instance.logMessage(
        level: LogLevel.info,
        message: 'nobody is watching',
      );
      expect(LiveSessionClient.i.state, LiveSessionState.idle);
    });
  });
}

/// Polls until [ready] or gives up, so a test never hangs on a frame that is
/// never coming.
Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
