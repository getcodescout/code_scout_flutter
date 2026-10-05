## 1.6.0

### Added

- **A log can name the HTTP call it is about.** `logMessage`, `log` and the
  shorthands `v`, `d`, `i`, `w`, `e` and `f` take an optional `requestId`. When
  a response body no longer matches your model and `fromJson` throws, pass the
  call's id with the error:

  ```dart
  scout.e('Could not read GET /v2/cart',
      error: e, stackTrace: st, requestId: response.codeScoutRequestId);
  ```

  `codeScoutRequestId` comes from `code_scout_dio` 1.1.0 and `code_scout_http`
  1.1.0. On the dashboard, `request:<id>` finds the call and the log together.
  The log stays an ordinary app log: it is not a network log, so it never
  changes the call's status, duration or the Network tab's counts. A call that
  answered 200 is still a 200.
- **The in-app panel puts the two side by side.** A call's Response pane lists
  what the app logged about it, above the body, and **Copy call** includes
  those logs. A log about a call gets a
  **Call** section that opens it. When the call is not in the panel, the
  section shows the full id with a Copy button instead. At the default
  `minimumLevel` of info that is the usual case, because network logs are
  written at debug; set `minimumLevel: LogLevel.debug` to keep the call and
  its body.
- The console prints the request id on any log that has one, not only on
  network logs. Copying a log includes a `request <id>` line, in full, and the
  Logs tab's search finds a request id from its first eight characters or
  more, so a short search such as a status code does not match inside one.

### Changed

- **A request id that is not a UUID never reaches the server.** The server
  stores request ids as UUIDs, and one value that did not parse failed the
  whole upload, which was then retried forever with every later log queued
  behind it. A log given a backend's own `X-Request-Id`, a ULID or an empty
  string now keeps everything except the id. A custom interceptor that mints
  its own ids for `NetworkRequestData` keeps them on the device, so its calls
  still pair in the panel and in a live session, but an id that is not a UUID
  is uploaded as null, and the dashboard cannot pair those phases. Use
  `NetworkRequestData.newRequestID()`. Either way the SDK says once, through
  `dart:developer`, that it dropped an id. The value itself is never printed.
- A request id that is a UUID is kept lowercase, so an id copied in uppercase
  still matches the call's own.

### Fixed

- A call with a request and no response no longer says its response fell out
  of the panel. The panel drops its oldest logs first, so a response cannot go
  before its request. The Response pane now says the call may still be
  running, and that the SDK holds a request for two minutes and can drop a
  response that arrives later.

## 1.5.3

### Fixed

- **Every console line carried a malformed elapsed time**, reading
  `(+-0:00:00.000115)`. The subtraction ran the wrong way round, so the duration
  was always negative and the format prepended its own plus sign. The timestamp
  is now just the time.
- **Three of the seven log levels printed as `LogLevel.verbose`** and friends,
  because `verbose`, `fatal` and `system` fell through to the enum's own
  `toString`. They have labels of their own now.
- **Console output is actually colour coded.** `AnsiColor` had been in this
  package unused while six places in the docs and on the website promised
  colour, so the claim is now true rather than withdrawn. One colour per level.
- The in-app panel's Info screen told a local-mode user how to add a dashboard
  with a snippet that had no `sync:` block, so following it exactly still
  uploaded nothing.
- The dartdoc on `CodeScoutSqflite` awaited `registerDatabase`, which returns
  void, so the snippet did not compile.
- The README said logs are "written to the device and never uploaded" without
  `sync:`. They are not written either: the SQLite table is the uploader's
  queue, so it is skipped when there is no uploader.

### Fixed

- The README linked `http://localhost:24275` as a link rather than as text, which
  pub.dev counts as an insecure link and docks the package for. It is the address
  a local dashboard really does answer on, so it is written as code now instead of
  being pointed somewhere it is not.

## 1.5.2

### Changed

- **The readme now shows the in-app panel.** Until this release every screenshot
  anywhere was of the dashboard, which is the half you get after standing up a
  Postgres. The half you get in two minutes, the Logs, Network and Errors tabs
  inside your own app, had no picture on pub.dev, on the website or in any
  readme. There are three now, generated from a widget test rather than captured
  by hand so they cannot quietly go out of date.

No code changed in this release.

## 1.5.1

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true. The package requires Dart 3.10 through its dependencies, and
  Dart 3.10 first shipped in Flutter 3.38, so every release before that resolved with an error
  rather than a message explaining why. Nothing about the code changed and nothing you have
  working will stop working; pub.dev now just describes the requirement honestly.

## 1.5.0

### Fixed

- **Network requests that never got an answer are now dropped.** A request is held from the moment it goes out until its response or error arrives, so the three phases can be stitched back into one call. Almost all of them arrive; the ones that do not are real, like an app killed mid-flight or a socket that dies without either callback running. There was a two minute eviction for exactly this and nothing ever started it, so it had never once run and the map only ever grew. It is a sweep on insert now, which needs no timer running in your app and looks at the moment the map can actually grow.

### Deprecated

- `NetworkManager.startCleanupTimer()` and `stopCleanupTimer()` do nothing and will be removed. Eviction is automatic. Nothing in this package ever called them, so nothing was ever running the timer they started.

## 1.4.0

### Added

- **Sessions now report which version of this package sent them.** The dashboard shows it on the Sessions list and on the session itself, and `sdk_version:` filters on it, so "which apps are still on a build without that fix?" is a question you can answer without asking anyone. It is stamped at upload from a constant rather than stored, so there is no database change on the device, and an app that upgrades mid-session reports the version it is running now.

## 1.3.1

### Changed

- **The package description now leads with the dashboard.** It opened with the on-device viewer, which is the part every other logging package in this space also does, and left the self-hosted dashboard as a closing aside. In a pub.dev search result that one line is the whole pitch. It also read "an on-device viewer that need no server". No code changed.

## 1.3.0

### Fixed

- **A server that does not answer at startup no longer stops the app uploading for the whole launch.** The sync worker was started only if `GET /api/validate` succeeded in the moment `init()` ran, and a failed validation was cached for the life of the process, so an app that started a second before its server did collected logs to disk and never sent them until it was restarted. Validation still runs, because its answer carries the project's sampling rate, but it no longer decides whether uploading happens. A failing upload is the sync cycle's problem, and it already knows how to wait and try again.
- **Repeated upload failures now pause rather than stop.** Five failures in a row used to stop the worker for the rest of the launch, so a server down for a minute cost every log until the app was restarted, silently. It now goes quiet for five minutes and picks up on its own when the server comes back.
- **A database that will not open no longer reports an unhandled async error.** Every caller inside the SDK already handled this: the session is skipped, the log is dropped, the app carries on. A second copy of the error was also being delivered to a future nobody awaited, which Dart reports as an unhandled error, so a problem the SDK absorbed still surfaced as a crash report with CodeScout's name on it.
- **`init()` no longer throws when there is no widget tree yet.** `freshContextFetcher` is optional, so calling `init()` early in `main()` before `runApp` is a reasonable thing to do, and it is where you want logging to start. The overlay tried to insert itself anyway, one turn of the event loop later, and threw where nothing could catch it. It now waits for a context instead. Nothing else in the SDK was affected.

### Changed

- **The overlay's Session tab now says what is actually happening.** It showed one number labelled "Logs held", which was the size of the in-memory buffer the Logs tab draws from, a display ring that never drains, so a launch whose logs had all uploaded still read as a queue going nowhere. It now shows **In this view** (the buffer) and **Waiting to upload** (the real count on disk) separately, and the Sync line reports whether the uploader is running, paused, or has no server configured, instead of only whether credentials were set.

### Added

- **`CodeScout.instance.flush()`** uploads whatever is waiting now, and completes when it has landed or failed, instead of waiting for the next scheduled cycle. Worth calling when the app is about to stop being able to: going to the background, or signing a user out. Everything the scheduled cycle does still applies, so a call while one is already running is not a second upload, and nothing is deleted locally until the server has taken it.

## 1.2.0

The release that makes CodeScout usable in production: sessions, identity,
redaction, sampling, server backoff, and watching a device live while somebody
reproduces a bug in front of you.

### Upgrading from 1.1.x

Nothing you already wrote needs to change. Two things are worth knowing before
you ship it:

- **Your app starts collecting more about the device.** `captureDeviceInfo` and
  `captureAppContext` have always defaulted to `true` and always been ignored.
  They now work, so device model, OS name and version, your app's version and
  build number begin reaching your server, along with a random installation id
  that is stable for the life of the install. Set either to `false` to opt out.
  No identity is collected either way; that stays opt-in through `setUser()`.
- **Two new dependencies:** `device_info_plus` and `package_info_plus`, for
  exactly those fields. `provider` is no longer a dependency.

### Live sessions

- **New: live sessions.** Open the overlay, tap **Live**, and type the six
  character code the dashboard shows under Live devices. From then on every log
  this launch produces arrives on the dashboard as it happens. Tap **Stop
  streaming**, close the app, or lose the network and the session ends. None
  of it is stored on the server unless somebody turns on Persist.
- Streaming is additional, never a replacement. Logs keep going to the console,
  the overlay and SQLite whether or not anyone is watching, and a live session
  that drops takes nothing with it.
- Live streaming ignores session sampling on purpose: somebody has deliberately
  paired with this device and is watching it right now, so showing them a
  sampled subset would make the feature useless exactly when it is in use.
- `CodeScout.instance.startLiveSession(code)` and `stopLiveSession()` are
  available directly if you would rather drive it from your own UI than from the
  overlay.
- Still no new dependencies: the socket is `dart:io`'s `WebSocket`.

### Session sampling

- **New: session sampling.** `LoggingBehavior(sessionSampleRate: 0.1)` records
  one launch in ten instead of all of them. Whole sessions, not individual
  logs, so a session you keep keeps its whole timeline rather than showing
  gaps. The draw happens once at `init()`, so a launch that is left out costs
  nothing afterwards.
- **New:** the rate can also be set per project on the server, which the SDK
  picks up from the call it already makes to `/api/validate` at startup. The
  lower of the two wins, so a server can ask a noisy app to send less but can
  never make it send more than you asked for.
- Sampling gates what is stored and uploaded, never what you see while you
  work: the console and the in-app overlay show every log either way.

### Server backoff

- **New: the SDK honours server backoff.** A `429` (or a `503` from a proxy) is
  now read as an instruction rather than a failure: the worker goes quiet for
  the `Retry-After` the server asked for and does not count it toward the
  five-failure auto-stop. Previously every non-200 was one untyped throw, so a
  server correctly saying "you are over your allowance" stopped logging for the
  rest of the process with no way back.
- **New:** a `413` halves the batch size and retries rather than failing, growing
  back toward the configured size on success.

### Redaction and body caps

- **New: redaction, opt-in.** Name headers or body keys in `RedactionBehavior`
  and they are replaced at capture, before anything reaches SQLite or an upload.
  Nothing is redacted unless you ask. This is a debugging tool, and a token is
  sometimes the reason a request is failing. Body keys match at any depth
  including inside lists, ignoring case and separators, so one `access_token`
  entry covers `accessToken` too. `RedactionBehavior.commonHeaders` and
  `commonBodyKeys` hold the usual suspects, and `RedactionBehavior.recommended()`
  switches them all on.
- **New:** bodies over `maxBodyBytes` (32 KB by default) are truncated with a
  note saying how much was dropped, so one large response cannot turn into a
  large upload on someone's mobile connection.

### The in-app overlay

- **New:** the in-app overlay is now a real log viewer. Tapping the floating
  button opens a sheet with **Logs**, **Network** and **Session** tabs: level
  and tag filters, rows that expand to their error, stack trace and metadata,
  network phases paired into one row per call, and the session details you get
  asked for in a bug report. It reads an in-memory buffer of the current launch,
  so it works identically with no server configured.
- **Removed:** the overlay's raw IP/port/identifier socket form, and with it the
  `provider` dependency. It was superseded by the pairing-code flow that comes
  with live streaming, and nothing referenced it any more.

### Sessions and identity

- **New:** every app launch is now recorded as a session, carrying the device
  model, OS name and version, your app's version and build number, and a random
  installation id that is stable for the life of the install. The dashboard uses
  these for its Sessions and Devices screens.
- **New:** `CodeScout.instance.setUser(id, traits: {...})` names the person using
  the app. Identity is opt-in and never inferred. A session is anonymous until
  you call it. Pass `null` on sign out. Safe to call at any point in a launch.
- **Behaviour change:** `captureDeviceInfo` and `captureAppContext` now do
  something. Both have always defaulted to `true` and been ignored; they now
  control whether those fields are collected. See **Upgrading** above.
- Uploads now carry a second `sessions.json` entry alongside `data.json`. Older
  servers read entries by name and skip what they do not recognise, so an
  upgraded app keeps working against a server that has not been updated.

## 1.1.1

- **Fix:** logging or network capture before `CodeScout.instance.init()` no longer
  throws `LateInitializationError` into the caller. Configuration and session id
  now have safe defaults, and `NetworkManager` capture is a no-op until init.
- **Fix:** network error logs now carry the `network` tag, matching the request and
  response phases. Previously `enabledTags: {'network'}` silently dropped them.
- **Behaviour change:** narrowing `enabledTags` no longer discards untagged logs.
  The allowlist now narrows tagged logs only; set `allowUntagged: false` for the
  previous behaviour. Use `minimumLevel` to control overall volume.

## 1.1.0

* Added level-specific shorthand methods (`.v()`, `.d()`, `.i()`, `.w()`, `.e()`, `.f()`)
* Changed `message` parameter type from `dynamic` to `String` for a cleaner API contract
* Added companion packages for network interception: `code_scout_dio` and `code_scout_http`

## 1.0.0

* Initial release
* Structured logging with 8 levels (all, system, verbose, debug, info, warning, error, fatal)
* Tag-based and level-based log filtering
* SQLite local persistence with WAL mode
* Automatic batch sync to self-hosted CodeScout server (tar.gz compression)
* Background isolate compression to avoid UI jank
* Network request/response/error interception with request ID correlation
* Atomic sync pipeline with retry and automatic backoff
* Floating overlay button for development controls
* Socket connection scaffolding for real-time streaming
* Zero third-party HTTP dependencies. All server communication via dart:io
