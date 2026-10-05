<p align="center">
  <img src="assets/pim_code_scout.svg" alt="CodeScout" width="320" />
</p>

<p align="center">
  See what your Flutter app is doing, on your machine or on somebody else's phone.
</p>

<p align="center">
  <a href="https://pub.dev/packages/code_scout"><img src="https://img.shields.io/pub/v/code_scout.svg" alt="pub.dev"></a>
  <a href="https://pub.dev/packages/code_scout_dio"><img src="https://img.shields.io/pub/v/code_scout_dio.svg?label=code_scout_dio" alt="code_scout_dio"></a>
  <a href="https://pub.dev/packages/code_scout_http"><img src="https://img.shields.io/pub/v/code_scout_http.svg?label=code_scout_http" alt="code_scout_http"></a>
</p>

<p align="center">
  <a href="https://codescout.tech">Website</a> &middot;
  <a href="https://pub.dev/packages/code_scout">pub.dev</a> &middot;
  <a href="https://github.com/getcodescout/code_scout_flutter">GitHub</a> &middot;
  <a href="https://github.com/getcodescout/code_scout">Server</a>
</p>

---

`print()` works until the bug is on a phone you are not holding. This is what you reach for after
that: structured logs and every HTTP call, kept on the device, and searchable in a dashboard you
run yourself when you want one.

This is not a crash reporter. Crashlytics tells you the app crashed. CodeScout shows you what it
was doing for the five minutes before. Plenty of teams run both.

It is not a replacement for DevTools either. DevTools is better than this at everything you can do
while the device is plugged into your machine. CodeScout is for after that: a build in QA, on a UAT
device, or in the hands of somebody who cannot tell you what the network did.

**You do not need a server to start.** Add the package, tap the floating button, and read your logs
and network calls on the phone. That is a real way to use it, not a trial version. Add credentials
later, when you want them somewhere you can search.

```dart
CodeScout.instance.i('User signed in', tags: {'auth'});
CodeScout.instance.e('Payment declined', error: e, stackTrace: s);
```

## What you get

**Straight away, with no server.** Colour-coded console output, and a panel inside your own app,
opened from a floating button. Nothing leaves the phone.

| Logs | Network | Errors |
|---|---|---|
| <img src="https://raw.githubusercontent.com/getcodescout/code_scout_flutter/main/.github/assets/screenshots/overlay-logs.png" alt="The Logs tab of the in-app CodeScout panel" width="240" /> | <img src="https://raw.githubusercontent.com/getcodescout/code_scout_flutter/main/.github/assets/screenshots/overlay-network.png" alt="The Network tab of the in-app CodeScout panel" width="240" /> | <img src="https://raw.githubusercontent.com/getcodescout/code_scout_flutter/main/.github/assets/screenshots/overlay-errors.png" alt="The Errors tab of the in-app CodeScout panel" width="240" /> |
| Everything this launch wrote, with the levels and tags as filters. | One row per call with its status and duration, both bodies a tap away. | The failures on their own, already counted. |

Two more screens sit behind icons in the header. **Data** reads your app's own SQLite tables,
`shared_preferences` and Hive boxes on the device. **Info** runs a connection test and tells you
which step failed, which answers "why is nothing arriving" more often than anything else.

**Once you point it at a dashboard.** Everything above, from every device, searchable.

<p align="center">
  <img src="https://raw.githubusercontent.com/getcodescout/code_scout/main/.github/assets/screenshots/logs.png" alt="The CodeScout log viewer, showing logs from a Flutter app with level toggles and tag filters" width="880" />
</p>

| | |
|---|---|
| **Search it the way you think** | `level:error tag:checkout last:24h`, or `user:ada@example.com` for everything one person hit. Filters live in the URL, so a search is a link you can paste to somebody. |
| **One bug is one row** | Twenty-six copies of the same failure collapse into a single line with a count, so this morning's new bug is not buried under last week's. |
| **Replay one launch** | Every log and network call from one run of the app, in order, with the time since launch beside each row. |
| **Watch a phone live** | Pair a phone with a short code and its logs arrive in your browser as they tap. No install, no TestFlight round trip, no account for them. |
| **Read the phone's own database** | While paired, browse the app's SQLite tables, `shared_preferences` and Hive boxes, and change one value at a time. |
| **Hand it to a coding agent** | The dashboard speaks MCP, so your agent can read a session timeline itself instead of you pasting stack traces into a chat. |

## How it behaves

- **A bad network costs a delay, not your logs.** Everything is written to SQLite first and
  uploaded in batches. Tunnel, aeroplane, dead server: they wait and retry. After five consecutive
  failures it goes quiet for five minutes, then tries again. It pauses, it never gives up.
- **It backs off when told to.** A `429` or `503` is honoured with its `Retry-After` rather than
  retried into the ground, and a `413` halves the batch.
- **Nothing is hidden unless you name it.** Redaction is opt-in, because the token is sometimes the
  bug. Name your auth headers and password fields and they are stripped on the phone, before
  anything is written to disk.
- **It never infers who the user is.** Sessions record the device, the OS and the build. A person
  is attached only when you call `setUser()`.
- **Adding it does not add an HTTP client.** The core talks to your server with `dart:io`, so
  installing this never drags Dio or `package:http` into an app that does not already use them.
- **Compression runs in an isolate**, so a large batch never janks a frame.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [code_scout](https://pub.dev/packages/code_scout) | Core logging SDK | [![pub.dev](https://img.shields.io/pub/v/code_scout.svg)](https://pub.dev/packages/code_scout) |
| [code_scout_dio](https://pub.dev/packages/code_scout_dio) | Dio interceptor | [![pub.dev](https://img.shields.io/pub/v/code_scout_dio.svg)](https://pub.dev/packages/code_scout_dio) |
| [code_scout_http](https://pub.dev/packages/code_scout_http) | HTTP client wrapper | [![pub.dev](https://img.shields.io/pub/v/code_scout_http.svg)](https://pub.dev/packages/code_scout_http) |
| [code_scout_talker](https://pub.dev/packages/code_scout_talker) | Talker observer | [![pub.dev](https://img.shields.io/pub/v/code_scout_talker.svg)](https://pub.dev/packages/code_scout_talker) |

## Getting Started

Install the core package:

```bash
flutter pub add code_scout
```

For network interception, add the companion package for your HTTP client:

```bash
# For Dio users
flutter pub add code_scout_dio

# For http users
flutter pub add code_scout_http
```

Already using [Talker](https://pub.dev/packages/talker)? Keep it. One observer
sends everything it already logs to the dashboard as well, and none of your
logging code changes:

```bash
flutter pub add code_scout_talker
```

```dart
final talker = Talker(observer: CodeScoutTalkerObserver());
```

## Usage

### Initialize

CodeScout needs a `BuildContext` to place its floating button into your widget tree, so `init()`
runs from a widget inside your `MaterialApp`, after the first frame, rather than at the top of
`main()`. The button goes into the `Overlay` that `MaterialApp` builds, so a context from above it
has nothing to insert into. That is where the `context` in the sample below comes from.

```dart
import 'package:code_scout/code_scout.dart';
import 'package:flutter/material.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Home());
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await CodeScout.instance.init(
        // How the panel finds a live context again after you navigate away.
        freshContextFetcher: () => context,
        configuration: CodeScoutConfiguration(
          logging: LoggingBehavior(minimumLevel: LogLevel.all),
          projectCredentials: ProjectCredentials(
            link: 'http://192.168.1.24:24275/',
            projectID: 'your-project-id',
            projectSecret: 'your-project-secret',
          ),
          sync: LogSyncBehavior(
            syncInterval: Duration(seconds: 30),
            maxBatchSize: 100,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Hello')));
}
```

Leave `freshContextFetcher` out and everything still works, you simply do not get the floating
button.

Three things in there are worth knowing before they cost you an afternoon.

`minimumLevel` defaults to `LogLevel.info`, and that check runs before the console printer, so at
the default `scout.d()` and `scout.v()` produce nothing at all. Use `LogLevel.all` while you are
developing.

The `sync:` block has no default, and leaving it out does not queue anything for later: the
SQLite write is the uploader's queue, so it is skipped when there is no uploader. Logs still
print to the console and fill the in-app panel for this launch, then go. The only complaint is a
single line in the debug console.

The `link` is a real address on your network, not `localhost`. On a physical device `localhost`
means the phone itself. It must start with `http://` or `https://`, contain a host, and end with
a trailing slash, and `ProjectCredentials` throws immediately if it does not. Android also blocks
plain HTTP by default, so use `https` or allow cleartext for that host while developing.

### Log messages

Use the shorthand methods for quick logging:

```dart
final scout = CodeScout.instance;

scout.d('Fetching user profile');                       // debug
scout.i('User signed in', tags: {'auth'});              // info
scout.w('Cache miss', metadata: {'key': 'user_prefs'}); // warning
scout.e('Payment failed', error: e, stackTrace: st);    // error
scout.f('Unrecoverable state');                          // fatal
scout.v('Detailed trace data');                          // verbose
```

You can also use the full form when you need to specify the level dynamically:

```dart
CodeScout.instance.log(
  level: LogLevel.info,
  message: 'User signed in',
  tags: {'auth'},
  metadata: {'userId': '123'},
);

// Awaitable (if you need to confirm persistence)
await CodeScout.instance.logMessage(
  level: LogLevel.error,
  message: 'Payment failed',
  error: exception,
  stackTrace: stackTrace,
);
```

### Capture network calls

Network interception lives in separate companion packages, so installing CodeScout never adds
Dio or `package:http` to an app that does not already use one. Each package takes a single line
to set up.

#### Dio

Add `code_scout_dio` to your dependencies, then attach the interceptor:

```dart
import 'package:dio/dio.dart';
import 'package:code_scout_dio/code_scout_dio.dart';

final dio = Dio();
dio.interceptors.add(CodeScoutDioInterceptor());
```

Every request and every response or error flowing through this Dio instance is captured from
then on. Note that dio treats a 4xx or 5xx as an error rather than a response, so those arrive
through the error path and are logged at error level.

#### http

Add `code_scout_http` to your dependencies, then wrap your client:

```dart
import 'package:code_scout_http/code_scout_http.dart';
import 'package:http/http.dart' as http;

final client = CodeScoutHttpClient(client: http.Client());

// Use it like a normal http.Client
final response = await client.get(Uri.parse('https://api.example.com/data'));
```

`CodeScoutHttpClient` extends `http.BaseClient`, so it is a drop-in replacement anywhere you
already use an `http.Client`. Pass your existing client in as shown above. If you leave the
`client:` argument out, the wrapper builds a plain new client instead, and any base headers,
proxy or timeout you had configured are quietly lost.

#### How it works

Each call writes one log when the request goes out and at most one more, a response or an error
but never both. They share a request id, which is how the panel and the dashboard know to show them
as a single row. A call whose answer was never recorded keeps only its request log and shows as
pending. [Network inspection](https://codescout.tech/docs/guides/network/#up-to-two-logs-per-call)
lists when that happens.

If your Network tab stays empty, open the panel and tap the info icon. Every companion package
announces itself to the SDK when you construct it, so the Info screen can tell you whether an
interceptor is genuinely missing or is simply installed and has not seen a call yet.

#### When a response stops matching your model

Every logging call takes an optional `requestId`. Pass the call's id when you log the failure, and
the error is shown with the call that returned the body. `code_scout_dio` and `code_scout_http` put
the id on the response as `codeScoutRequestId`:

```dart
final response = await dio.get<Map<String, dynamic>>('/v2/cart');
try {
  return Cart.fromJson(response.data!);
} catch (e, st) {
  CodeScout.instance.e('Could not read GET /v2/cart',
      error: e, stackTrace: st, requestId: response.codeScoutRequestId);
  rethrow;
}
```

The panel lists the error on the call's Response pane, above the body, and the dashboard lists it
above the call's tabs, so the exception and the JSON that caused it are read together. The dashboard
does this from version 1.2.0. An older one stores the log and finds it with `request:`, but does not
show it with the call. The log stays an ordinary log, so a call that answered 200 is still a 200.
Network logs are written at debug, so `minimumLevel` has to be `LogLevel.debug` or lower, or the
call will not have been kept. The getter needs `code_scout_dio` or `code_scout_http` 1.1.0. The
whole workflow is in [When the API changes under you](https://codescout.tech/docs/guides/api-changes/).

### Name the person using the app

Every app launch is a session. By default a session is anonymous, and CodeScout never guesses who someone is. Call `setUser` when you know:

```dart
await CodeScout.instance.setUser('u_8812');

// With traits, which are stored against this session
await CodeScout.instance.setUser('u_8812', traits: {'plan': 'free'});

// On sign out
await CodeScout.instance.setUser(null);
```

The id is stored and never parsed, so hash it first if you would rather CodeScout never held the real one. Traits sit on the session rather than on the person, because what matters while debugging is what was true when it broke, not what is true now.

You can call this at any point in a launch. The session record is re-sent with every upload, so a call made ten minutes in reaches the dashboard on the next sync.

### What a session records

Alongside the id and the user, each session carries the device it ran on and the build of your app it was:

| Field | Where it comes from |
|-------|---------------------|
| Device model | `device_info_plus`, for example "Pixel 7", "iPhone 15 Pro" |
| OS name and version | "Android 14", "iOS 17.4" |
| App version and build | `package_info_plus`, for example "3.11.2+418" |
| Installation id | A random value written once and kept for the life of the install |

The installation id is what lets the dashboard group launches by phone. It is generated locally, carries nothing personal, and goes away when the app is uninstalled. Set `captureDeviceInfo: false` or `captureAppContext: false` on `LoggingBehavior` to leave either group out.

### Redaction

Redaction is **opt-in**. Out of the box CodeScout records what your app sent, unchanged, because this is a debugging tool, and the token is sometimes the exact reason a request is failing.

Name what you want stripped and it is replaced at capture, before the log reaches SQLite, so it is never written to disk or uploaded:

```dart
CodeScoutConfiguration(
  redaction: RedactionBehavior(
    headers: {'authorization', 'cookie'},
    bodyKeys: {'password', 'card_number'},
  ),
)
```

In the dashboard that reads as a deliberate absence rather than a missing field:

```
authorization  ••••••  redacted on the device
content-type   application/json
```

There are two lists of the usual suspects, `RedactionBehavior.commonHeaders` and `RedactionBehavior.commonBodyKeys`, so you do not have to type them. They do nothing until you ask for them:

```dart
// The common lists, plus your own
RedactionBehavior.recommended(bodyKeys: {'order_signature'})

// The common lists, minus the header you are debugging today
RedactionBehavior(
  headers: RedactionBehavior.commonHeaders.difference({'authorization'}),
  bodyKeys: RedactionBehavior.commonBodyKeys,
)
```

Body keys match at any depth, including inside lists, ignoring case and separators, so one `access_token` entry covers `accessToken` and `Access-Token` too. Header names match case-insensitively.

**Body size caps are separate**, and on by default at 32 KB. That is not about secrets: a single response can be megabytes, and uploading it from a phone is a cost the person holding it pays. Oversized bodies are truncated with a note saying how much was dropped. Set `maxBodyBytes: 0` to keep everything.

### Sending less from production

A busy app can generate hundreds of logs per session, and you rarely need all of them from all of your users. Session sampling records a share of launches instead of every one:

```dart
LoggingBehavior(sessionSampleRate: 0.05)   // one launch in twenty
```

It samples **whole sessions, not individual logs**. A launch is either recorded or it is not, decided once when `init()` runs. That is deliberate: sampling individual logs would leave holes in a timeline, and a timeline with holes reads as your app doing nothing when really you just were not told. One in twenty complete stories is far more useful than one in twenty of every story's sentences.

The rate can also be set per project in the dashboard, under project settings. The SDK reads it from the call it already makes at startup and **uses whichever rate is lower**. So you can turn the volume down from the server without shipping a release, but the server can never make your app send more than you asked for. If the server cannot be reached, your own setting stands.

Sampling only affects what is stored and uploaded. The console and the in-app overlay show every log either way, so a sampled-out launch is not a launch you cannot debug on the device in front of you.

### The in-app panel

A floating button draws over your app, and it tells you two things before you even open it. It
carries a count of errors you have not looked at yet, and it shows a ring while a live session
is running so the person holding the phone knows they are being watched.

Tapping it opens a sheet with three tabs.

**Logs** shows everything this launch has written, newest first. You can search it, switch
individual levels on and off, filter by tag, and pause the list when it is arriving faster than
you can read. Tap any row to see its error, stack trace and metadata laid out properly rather
than printed as one long line.

**Network** shows one row per call with its status, how long it took, and everything it sent and
received, split into request, response and timing. Anything your app logged about a call with its
request id is listed at the top of the response.

**Errors** shows errors and fatals on their own and counts them, so the same failure happening
fifty times is a single line instead of the whole screen.

Two more screens sit behind icons in the sheet header. **Data** browses your app's own SQLite
tables, `shared_preferences` and Hive boxes, read only, on the device. It only appears once you
have called `registerDatabase`. **Info** tells you whether anything is reaching a dashboard, what
is currently being captured, and what state the uploads are in. If you are wondering why nothing
has arrived, that is the screen to open, because it runs a connection test and names the step
that failed.

The panel reads an in-memory buffer of the current launch rather than the server, so **it works
with no server configured at all**. It holds the last 500 logs and starts empty again when the
app restarts. Drop the package in, tap the button, read your logs.

```dart
CodeScout.instance.showIcon();   // Show floating button
CodeScout.instance.hideIcon();   // Hide it
CodeScout.instance.toggleIcon(); // Toggle
```

### Watch a device live

When you need to see what a phone is doing *right now*, usually QA on one desk
and a developer on another, pair the two:

1. On the dashboard, open the project's **Live devices** and press **New session**.
   It shows a six character code.
2. On the phone, open the CodeScout panel and tap the **Go live** pill in the header.
   Type the code and press Connect. The pill reads Pairing while it connects and then
   Live for as long as the session lasts.

Every log that launch produces now arrives on the dashboard as it happens, with
the same level filters the log viewer has. Filter to a tag, tap through a flow,
and watch the events confirm.

The session ends when you stop it, when the app closes, or when the network
drops. Nothing streamed is written to your server at all, so this is safe to
point at a build you would not want in your stored logs.

You can drive it from code instead of using the panel:

```dart
final started = await CodeScout.instance.startLiveSession('4K7Q2P');
// ...
await CodeScout.instance.stopLiveSession();
```

`startLiveSession` never throws. A mistyped or expired code comes back as
`false`. Sampling does not apply to a live session: if somebody is watching,
they see everything.

### Cleanup

```dart
await CodeScout.instance.dispose();
```

## How It Works

```
Flutter App                                CodeScout Server
┌─────────────────────────┐               ┌─────────────────────────┐
│ CodeScout.log()         │               │                         │
│ NetworkManager          │               │  POST /api/logs/dump    │
│         |               │               │    (multipart tar.gz)   │
│ LogPersistenceService   │  periodic     │         |               │
│   (SQLite)              │──sync───────> │  Log ingestion          │
│         |               │  tar.gz       │         |               │
│ LogSyncWorker           │  X-Project-ID │  Postgres storage       │
│ LogCompressor (isolate) │               │         |               │
└─────────────────────────┘               │  Web Dashboard          │
                                          └─────────────────────────┘
```

1. Logs are written to a local SQLite database
2. A periodic timer picks up unsync'd logs, marks them as syncing, compresses them in a background isolate, and uploads via `dart:io`
3. On success, logs are deleted locally. On failure, they're rolled back and retried next cycle
4. After 5 failures in a row the worker waits five minutes before trying again. It pauses, it
   does not stop: the counter resets and uploads resume on their own, so a server that was down
   for a minute does not cost you every log until somebody restarts the app
5. A `429` or `503` is not counted as a failure at all. The worker reads `Retry-After`, goes
   quiet for exactly that long, and resumes, so a server protecting itself can never silence an
   SDK for longer than it asked for
6. A `413` halves the batch and retries, growing back on success

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `LoggingBehavior.minimumLevel` | `LogLevel.info` | Minimum level to capture |
| `LoggingBehavior.enabledTags` | `{'*'}` | Tags to capture (`*` = all) |
| `LoggingBehavior.printToConsole` | `true` in debug | Print logs to console |
| `LoggingBehavior.includeCurrentStackTrace` | `false` | Attach stack trace to every log |
| `LoggingBehavior.captureDeviceInfo` | `true` | Record the device model, OS name and version |
| `LoggingBehavior.captureAppContext` | `true` | Record your app's version and build number |
| `LoggingBehavior.sessionSampleRate` | `1.0` | Share of launches recorded. The project's server-side rate can lower this, never raise it |
| `RedactionBehavior.headers` | `{}` | Header names to redact. Nothing by default |
| `RedactionBehavior.bodyKeys` | `{}` | Body and metadata keys to redact. Nothing by default |
| `RedactionBehavior.maxBodyBytes` | 32 KB | Bodies larger than this are truncated |
| `LogSyncBehavior.syncInterval` | 5 minutes | How often to sync |
| `LogSyncBehavior.maxBatchSize` | 100 | Max logs per upload |

## Setting up a server

Only needed if you want a dashboard. Without one the SDK still prints to the console and fills the
on-device viewer.

```bash
git clone https://github.com/getcodescout/code_scout.git
cd code_scout
docker compose up
```

Open `http://localhost:24275`, register the first account, and create a project. The project ID and
secret appear on the last step of the wizard, and you can read the secret again later under
**Settings → SDK setup**. Put both into `ProjectCredentials`.

Full instructions: [codescout.tech/docs](https://codescout.tech/docs/) and the
[dashboard repository](https://github.com/getcodescout/code_scout).

## Contributing

Pull requests are welcome. Small ones are the easiest to accept, and for anything large please open
an issue first so we can check it fits.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get set up, how to run the tests across all four
packages, and the two analyzer traps that catch everyone the first time.

Every change ships with a test, and the honest way to check one is to undo the fix and watch the
test fail.

## Security

Please report vulnerabilities privately rather than as an issue. See [SECURITY.md](SECURITY.md),
which also explains the things that look like bugs but are deliberate, such as nothing being
redacted unless your app asks.

## License

MIT. See [LICENSE](LICENSE).
