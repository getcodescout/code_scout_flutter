# CodeScout Flutter Package

This file provides guidance to AI coding agents when working with the `code_scout` Flutter package.

## Package Overview

`code_scout` is a Flutter SDK that captures application logs and network requests, stores them locally in SQLite, and periodically syncs them to a remote CodeScout server via compressed tar.gz uploads.

**Package name:** `code_scout`
**Version:** 1.6.0 in `pubspec.yaml`. pub.dev had 1.5.3 when last checked, on 2026-10-06.
**Dart SDK:** ^3.10.0 | **Flutter:** >=3.38.0

**Both numbers are derived, not chosen, and neither is arbitrary.** The Flutter one follows the
Dart one: Dart 3.10.0 first shipped in Flutter 3.38.0, so anything older cannot resolve
`sdk: ^3.10.0`. It said `>=3.0.0` until 2026-08-12, which had pub.dev advertising compatibility
with three years of releases that fail at resolution with no useful message.

The Dart floor is set by the plus plugins, not by our own code. `device_info_plus`,
`package_info_plus` and `path_provider` all require Dart >= 3.10. Our source only needs **3.8**,
and exactly three things stand between it and lower: null-aware elements (`?x` inside a collection
literal) in `errors_tab.dart` and `overlay_widgets.dart`, which need 3.8, and a `_` reused twice in
one scope in `overlay_widgets.dart`, which needs 3.7. All three are conveniences and could be
rewritten in minutes if the floor ever needs to drop further.

**To check this rather than guess:** lower `sdk:` in `pubspec.yaml` and run `flutter analyze`. The
analyzer enforces the declared language version and names the feature and the version it wants.
What that does *not* prove is dependency resolution, because pub resolves against the SDK you have
installed, not the one you declared. Going below 3.10 therefore needs a real old toolchain to see
which plugin versions actually get picked.
**Published:** [pub.dev/packages/code_scout](https://pub.dev/packages/code_scout)

### Companion Packages

Network interception is provided via separate companion packages to keep the core SDK dependency-free:

| Package | Purpose | pub.dev |
|---------|---------|---------|
| `code_scout_dio` | Dio interceptor — `CodeScoutDioInterceptor` | [pub.dev/packages/code_scout_dio](https://pub.dev/packages/code_scout_dio) |
| `code_scout_http` | HTTP client wrapper — `CodeScoutHttpClient` | [pub.dev/packages/code_scout_http](https://pub.dev/packages/code_scout_http) |
| `code_scout_talker` | Talker observer — `CodeScoutTalkerObserver` | [pub.dev/packages/code_scout_talker](https://pub.dev/packages/code_scout_talker) |

These live under `packages/` in this repo. A companion package exists when an integration needs a
third-party dependency the core should not carry — `dio`, `http`, `talker`. That rule is why the
database browser is *not* one: it needs nothing the core does not already have, since sqflite backs
the log store and the key-value adapter takes closures rather than naming `shared_preferences`. Their pubspecs depend on `code_scout: ^1.5.0` (hosted). The floor stays at 1.5.0 for `code_scout_dio` and `code_scout_http` 1.1.0, because their `codeScoutRequestId` getters use nothing newer. Passing that id to `requestId:` needs core 1.6.0, so core 1.6.0 has to reach pub.dev before those two. The example app uses `dependency_overrides` to resolve the path dep for local development.

## Commands

```bash
flutter pub get                          # Install dependencies
cd example && flutter run                # Run example app
flutter test                             # Run tests
flutter analyze                          # Static analysis
```

CI runs `analyze` and `test` for all four packages here — the SDK, both
companions and the example — plus `pub publish --dry-run` for the three
publishable ones, and the cross-repo SDK e2e against a real dashboard.
`flutter analyze` must exit 0: it fails on info-level lints too, so a lint you
mean to break needs an `// ignore:` with a reason rather than a repo-wide
exception.

`test/e2e/` runs this SDK against a real dashboard and skips unless
`CS_E2E_BASE` points at one. Start it from the server repo, which owns the
throwaway database and port:

```bash
cd ../code_scout && make test-sdk-e2e
```

It is the only place the wire contract is not written down on both sides. Three
files:

- `sdk_to_dashboard_test.dart` logs through the public API and reads the rows
  back out of the dashboard's export endpoint.
- `db_browser_test.dart` pairs a real live session over a real WebSocket,
  registers a real SQLite database and a key-value store, then drives the
  dashboard's own `/live/{sid}/db*` routes. It is what covers the database
  browser, where the dashboard's Playwright tests only ever talk to a stub
  device.
- `linked_log_test.dart` makes a real call through `CodeScoutDioInterceptor` to
  a server the test starts, logs the failure to read its body with the id from
  `response.codeScoutRequestId`, and checks that the dashboard links the two:
  in the export, and under "Logged by the app" on the call's page. It also
  checks that an id which is not a UUID is dropped rather than failing every
  upload after it. This test is why `dio` and `code_scout_dio` are dev
  dependencies of the core. A dev dependency never reaches an app.

`dashboard.dart` is the shared client for all three: signing in, making a
project, minting a pairing code, posting a form. One account for every file,
because registration only happens on a fresh instance and a second email would
have nobody to log in as.

Two things about the host are worth knowing, since both failed silently the
first time. `TestWidgetsFlutterBinding` installs an `HttpOverrides` that answers
every request with 400 without opening a socket, so every file clears it; it
takes out the live WebSocket, the uploader and a dio call alike. And
`getTemporaryDirectory()` is a platform channel with nothing behind it here, so
`installScratchPaths` replaces it. Left alone, the compressor throws inside the
sync worker's own catch, which reports through `dart:developer` where the test
runner never shows it.

## Architecture

```
lib/
├── code_scout.dart                      # Public barrel export
└── src/
    ├── code_scout.dart                  # Main singleton (CodeScout.instance)
    ├── code_scout_comms.dart            # Socket command/payload protocol
    ├── config/
    │   ├── config.dart                  # CodeScoutConfiguration
    │   ├── logging_behaviour.dart       # LoggingBehavior (levels, tags, console)
    │   ├── sync_behaviour.dart          # LogSyncBehavior (interval, batch size)
    │   ├── real_time.dart               # RealTimeConfig
    │   └── project_creds.dart           # ProjectCredentials (auth headers)
    ├── log/
    │   ├── log_entry.dart               # LogEntry model + processLogEntry()
    │   ├── log_level.dart               # LogLevel enum (all→off, 10 levels)
    │   ├── log_printer.dart             # CSxPrinter — console output formatting
    │   ├── ansi_color.dart              # ANSI color codes for console
    │   ├── log_persistence_service.dart # SQLite storage (code_scout.db)
    │   ├── log_sync_worker.dart         # Periodic sync timer + dart:io upload
    │   └── log_compressor.dart          # JSON → tar.gz compression (via isolate)
    ├── network/
    │   ├── network_manager.dart         # NetworkManager.i singleton (TTL-based cleanup)
    │   ├── network_request.dart         # NetworkRequestData model
    │   ├── network_response.dart        # NetworkResponseData model
    │   ├── network_error_data.dart      # NetworkErrorData model
    │   └── network_data.dart            # NetworkData union type
    ├── csx_interface/
    │   ├── overlay_manager.dart         # Floating button overlay
    │   ├── menu.dart                    # CSxInterface sheet — Logs/Network/Errors tabs, with
    │   │                                #   Data and Info behind header icons
    │   ├── live_pane.dart               # The Live tab — pairing code entry and session state
    │   ├── log_buffer.dart              # LogBuffer — capped in-memory ring the overlay reads
    │   └── overlay_theme.dart           # The dashboard's palette, for the overlay
    ├── live/
    │   └── live_session_client.dart     # dart:io WebSocket to the dashboard, pairing + streaming
    ├── db/                              # Browsing local storage from the dashboard
    │   ├── db_source.dart               # CodeScoutSource + request/result types
    │   ├── sqflite_source.dart          # SQLite: schema, rows, the fixed UPDATE template
    │   ├── key_value_source.dart        # prefs, Hive, anything with a key and a value
    │   ├── db_value.dart                # affinity, coercion, cell encoding, the wire budget
    │   ├── db_registry.dart             # registration, and where `writable` is enforced
    │   └── db_dispatcher.dart           # the five ops the socket answers
    ├── session/
    │   ├── session_record.dart      # SessionRecord — one launch, wire + row shapes
    │   └── device_profile.dart      # Device model, OS, app version via the plus plugins
    ├── utils/
    │   ├── redactor.dart               # Strips credentials at capture
    │   ├── draggable_widget.dart        # DraggableFloatingWindow
    │   └── stack_trace_parser.dart      # StackTraceParser + StackCallDetails
    └── const/
        └── global_vars.dart             # Global variables

packages/
├── code_scout_dio/
│   └── lib/code_scout_dio.dart          # CodeScoutDioInterceptor (single file)
├── code_scout_http/
│   └── lib/code_scout_http.dart         # CodeScoutHttpClient (single file)
└── code_scout_talker/
    └── lib/code_scout_talker.dart       # CodeScoutTalkerObserver (single file)
```

## Key Patterns

- **Singletons everywhere:** `CodeScout.instance`, `NetworkManager.i`, `LogPersistenceService.i`, `OverlayManager.i`, `LogSyncWorker.i`
- **Log data flow:** `CodeScout.d()` / `.log()` / `.logMessage()` → `LogEntry.processLogEntry()` → `CSxPrinter` (console) + `LogPersistenceService` (SQLite) → `LogSyncWorker` (periodic) → `LogCompressor` (tar.gz in isolate) → `dart:io` HTTP POST to server
- **Network interception:** Companion packages (`code_scout_dio`, `code_scout_http`) call `NetworkManager.i.processNetworkRequest/Response/Error()`. Each network call gets a unique `requestId` to correlate request→response→error phases. Stale requests are evicted after 2 minutes.
- **Configuration:** All behavior controlled via `CodeScoutConfiguration` passed to `CodeScout.instance.init()`. Includes `LoggingBehavior` (filtering), `LogSyncBehavior` (timing), `ProjectCredentials` (server auth), `RealTimeConfig`.
- **Zero HTTP dependency:** All server communication uses `dart:io` `HttpClient` directly, and the core's `dependencies` have no `http` or `dio`. `dio` and `code_scout_dio` are dev dependencies only, for `test/e2e/linked_log_test.dart`, and a dev dependency never reaches an app.
- **Sync atomicity:** Logs are marked `sync_status=1` before upload, rolled back on failure, deleted on success. Concurrent syncs are prevented via a `_syncing` guard.
- **The package version is a constant** in `lib/src/version.dart`, because Dart cannot read its own pubspec at runtime. Bump it in the same commit as `pubspec.yaml`; a test compares the two and fails when they drift. It goes on the wire as `sdk_version` on every session, so the dashboard can show which build an app is running.
- **`SessionRecord.toRow()` is the base shape and `toJson()` builds on it, never the reverse.** It used to be the other way round, which made the wire shape unextendable: any key added for the server also landed in the SQLite INSERT, hit a column that does not exist, and failed *every* session write on the device. `sdk_version` is wire-only and is what would have triggered it.

## Public API Surface

### Initialization
```dart
await CodeScout.instance.init(
  freshContextFetcher: () => context,
  configuration: CodeScoutConfiguration(
    logging: LoggingBehavior(minimumLevel: LogLevel.all),
    projectCredentials: ProjectCredentials(
      link: 'http://localhost:24275/',
      projectID: 'uuid',
      projectSecret: 'secret',
    ),
    sync: LogSyncBehavior(syncInterval: Duration(seconds: 10)),
  ),
);
```

### Logging
```dart
// Level-specific shorthand methods (fire-and-forget, never throws)
final scout = CodeScout.instance;
scout.v('Verbose trace data');
scout.d('Debug info');
scout.i('User signed in', tags: {'auth'});
scout.w('Cache miss', metadata: {'key': 'prefs'});
scout.e('Payment failed', error: e, stackTrace: st);
scout.f('Unrecoverable state');

// Full form (when level is dynamic)
CodeScout.instance.log(
  level: LogLevel.info,
  message: 'Something happened',
  tags: {'network', 'auth'},
  metadata: {'userId': '123'},
);

// Awaitable (propagates errors)
await CodeScout.instance.logMessage(
  level: LogLevel.error,
  message: 'Critical failure',
);

// Any of them takes requestId: to tie the log to one captured HTTP call, with
// the id from the companion package's codeScoutRequestId (below). The log
// stays an ordinary log. See Linked logs.
scout.e('Could not read GET /v2/cart',
    error: e, stackTrace: st, requestId: response.codeScoutRequestId);
```

### Network Interception
```dart
// Dio — install code_scout_dio package
import 'package:code_scout_dio/code_scout_dio.dart';
dio.interceptors.add(CodeScoutDioInterceptor());

// HTTP — install code_scout_http package
import 'package:code_scout_http/code_scout_http.dart';
final client = CodeScoutHttpClient(client: http.Client());

// The id each package gave a call, to pass as requestId: (both 1.1.0). Null
// when the call did not go through the interceptor or the wrapper.
response.codeScoutRequestId;   // dio Response, http BaseResponse
exception.codeScoutRequestId;  // dio DioException
request.codeScoutRequestId;    // dio RequestOptions, http BaseRequest
```

### Linked logs

A log written with `requestId:` is about one call and stays an ordinary log: `is_network_call` 0
and `call_phase` null on the wire. These rules are what keep it from changing the call it names:

- **`LogBuffer.calls()` pairs only `isNetworkCall` entries.** A linked log goes into
  `OverlayCall.logs`, never into `phases`, and one whose call is not in the buffer makes no row.
  Do not loosen the check to `requestId != null`. Once a call's request phase has left the buffer,
  `_requestMeta` reads the method and path from the newest phase with a `request` map, and an app
  log is newer than its call, so its own `metadata['request']` would name the call. A log whose
  call was never kept would become a phantom pending row with no method or path.
- **An app log never sets `isNetworkCall`.** `logMessage`, which `log` and the shorthands call,
  builds its `LogEntry` with the default `false`. A network entry skips the metadata redaction an
  app log gets, because `NetworkRequestData` and its two siblings redact as they build it, and it
  keeps no stack trace.
- **Only a UUID request id is uploaded.** `LogEntry` keeps an 8-4-4-4-12 UUID, in any case, and
  lowercases it. An app log drops anything else when it is built. A network phase keeps a non-UUID
  id its interceptor minted, so its call still pairs in the panel and in a live session, and
  `toJson` writes `request_id` as null for it. Either way the SDK warns once per launch through
  `dart:developer` and never prints the value, since an app passing the wrong header may be passing
  a token.
- **The reason is the server.** It decodes `request_id` as a UUID, and one value that does not
  parse fails the whole batch with a 500. The sync worker rolls the batch back and sends it again,
  oldest logs first, forever: five failures in a row buy a five-minute pause, never a drop, so every
  later log on the device queues behind the bad one.

### Overlay Controls
```dart
CodeScout.instance.showIcon();
CodeScout.instance.hideIcon();
CodeScout.instance.toggleIcon();
```

### Sync and cleanup
```dart
// Upload what is waiting now, instead of at the next scheduled cycle.
// Worth calling when the app is about to background, or on sign-out.
await CodeScout.instance.flush();

await CodeScout.instance.dispose();
```

### Browsing local storage from the dashboard

```dart
// SQLite, through the connection the app already has.
CodeScout.instance.registerDatabase('shop.db', CodeScoutSqflite(db),
    writable: kDebugMode);

// shared_preferences, Hive, get_storage — anything with a key and a value.
// Closures rather than the package's types, so none of them becomes a
// dependency of the SDK for a debug-only feature.
CodeScout.instance.registerDatabase('prefs', CodeScoutKeyValue(
  keys: () async => prefs.getKeys(),
  readKey: (k) async => prefs.get(k),
  writeKey: (k, v) async => v == null ? prefs.remove(k) : prefs.setString(k, '$v'),
), writable: kDebugMode);
```

Reachable only while the device is in a live session, because the data is on the phone and nowhere
else. Nothing on the server is written. The rules that hold the feature together:

- **Nothing is browsable until the app names it.** No scanning for `*.db` — that finds the SDK's own
  log store and eventually an encrypted file it cannot open. This is the inverse of redaction, which
  hides nothing unless you name it, and the inversion is deliberate.
- **The dashboard never sends SQL.** Five structured ops (`sources`, `namespaces`, `schema`, `rows`,
  `update`); the device builds every statement from its own schema, with identifiers checked for
  membership rather than escaped. **Adding an op that takes a statement ends the safety argument.**
- **`writable` is enforced in `DatabaseRegistry`**, not in the source, so an op cannot route round
  it. Registration is ignored in release builds unless `allowInRelease`.
- **The dashboard may only edit what it actually saw.** A blob, a truncated string and a redacted
  value are all read-only for one reason: the update carries the old value to catch a conflict, and
  a value nobody was shown cannot be compared against anything.
- **A successful write logs itself** at `system` level, which is exempt from both the level gate and
  the sampling gate — it is the SDK's own record of something it did to the device, not app volume.

## SQLite Schema (logs table)

```sql
CREATE TABLE logs (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  level TEXT NOT NULL,
  message TEXT,
  error TEXT,
  stack_trace TEXT,          -- JSON array of StackCallDetails
  metadata TEXT,             -- JSON map
  tags TEXT,                 -- JSON array
  timestamp TEXT,            -- ISO-8601
  is_network_call INTEGER NOT NULL DEFAULT 0,
  request_id TEXT,
  call_phase TEXT,           -- request|response|error
  sync_status INTEGER NOT NULL DEFAULT 0  -- 0=pending, 1=syncing
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,       -- the launch's session id
  installation_id TEXT,      -- stable for the life of the install
  user_id TEXT,              -- only ever set by setUser()
  device_model TEXT,
  os_name TEXT,
  os_version TEXT,
  app_version TEXT,
  build_number TEXT,
  metadata TEXT,             -- JSON map of traits
  started_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE meta (          -- key/value; holds installation_id
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

Schema version is **2**. A database created by 1.1.x has only `logs`; `onUpgrade` adds the other two.

Sessions outlive their logs by one step: a batch sends the session records its logs reference (not only the current launch, since a launch killed before syncing leaves logs behind), and `pruneSessions` drops the ones nothing refers to any more, always keeping the live one.

## Server Communication

- **Auth headers:** `X-Project-ID` and `X-Project-Secret` on every request
- **Credential validation:** `GET {link}api/validate`
- **Log upload:** `POST {link}api/logs/dump` — multipart form with `file` field containing `data.tar.gz`
- **Compression:** JSON → tar archive → gzip → `data.tar.gz` (runs in background isolate). Two entries: `data.json` holds the logs, `sessions.json` holds the sessions those logs belong to. The server reads entries by name, so `sessions.json` is omitted when there are none.
- **All HTTP via `dart:io`** — no third-party HTTP packages in core

## What's Implemented vs TODO

### Working
- Full logging pipeline (capture → console → SQLite → sync)
- Level-specific shorthand methods (`.v()`, `.d()`, `.i()`, `.w()`, `.e()`, `.f()`)
- Network request/response/error capture with request ID correlation
- Dio interceptor (`code_scout_dio` package) and HTTP client wrapper (`code_scout_http` package)
- Tag-based and level-based log filtering
- Batch compression and upload (with retry and backoff)
- Sessions: every launch recorded with device model, OS, app version/build, and a stable installation id
- `setUser(id, traits:)` — opt-in identity, re-sent with every batch so a mid-session call still lands
- Device and app context capture (`captureDeviceInfo` / `captureAppContext` are honoured)
- In-app overlay: Logs, Network and Session tabs, reading a capped in-memory buffer so it works with no server configured
- Opt-in redaction (`RedactionBehavior`) and body size caps (32 KB)
- Server backoff: 429/503 read `Retry-After` and pause without counting toward the failure counter; 413 halves the batch. `lib/src/log/sync_backoff.dart`. Five consecutive real failures buy a 5 minute pause, not a stop, and the counter resets after it
- Session sampling: `LoggingBehavior.sessionSampleRate`, lowered further by the project's server-side rate from `/api/validate`, drawn once per launch in `init()`. The gate is in `processLogEntry`, above the SQLite write and below the console and overlay
- Live sessions: `lib/src/live/live_session_client.dart`, a `dart:io` WebSocket to `{link}api/live/socket`. Pairs with a six character code typed into the overlay's Live tab, then streams every log as it happens. `publish()` sits **above** the sampling gate in `processLogEntry` — somebody watching deliberately should see everything
- Linked logs: `requestId:` on every logging call ties an app log to one captured call, with the id from `codeScoutRequestId` on a dio or http response. The panel lists the log on the call's Response pane above the body, and Copy call carries it in the same place. The log's own detail has a Call section that opens the call, the console prints the id, copying the log adds a `request <id>` line, and the Logs search finds an id from its first eight characters. The call's status, duration and counts never change. The rules are under Linked logs above

### Incomplete / TODO
- Nothing outstanding for 1.0 in the SDK.

### Publishing

**Everything here is published**, so it is all released and in people's apps. Checked against the
pub.dev API on 2026-10-06, not remembered: `code_scout` 1.5.3, `code_scout_dio` 1.0.4,
`code_scout_http` 1.0.4, `code_scout_talker` 1.0.3. Notes in this file have twice claimed a
package was unpublished when it was not, so **ask pub.dev rather than trusting a line like this
one**.

The wire format is a published contract: a tar with `data.json`, and `sessions.json` alongside it
since 1.2.0. Entries are read by name at the server, which is what lets an older SDK that sends
only `data.json` keep working.
