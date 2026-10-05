# code_scout_http

[![pub.dev](https://img.shields.io/pub/v/code_scout_http.svg)](https://pub.dev/packages/code_scout_http)

Captures every HTTP call your app makes through `package:http` and shows it to you, either on the
phone itself or on a [CodeScout](https://codescout.tech) dashboard you run.

This is the `package:http` half of CodeScout. The core package,
[`code_scout`](https://pub.dev/packages/code_scout), does the logging and has no HTTP dependency
of its own, which is why network capture lives out here.

## Getting started

```bash
flutter pub add code_scout_http
```

Wrap the client you already have:

```dart
import 'package:http/http.dart' as http;
import 'package:code_scout_http/code_scout_http.dart';

final client = CodeScoutHttpClient(client: myExistingClient);

// Use it exactly like an http.Client. It extends http.BaseClient,
// so it goes anywhere one already goes.
final response = await client.get(Uri.parse('https://api.example.com/data'));
```

Pass your existing client in through `client:`. If you leave that argument out, the wrapper
builds a plain new `http.Client` instead, and any base headers, proxy or timeout you had
configured on yours are quietly lost.

CodeScout itself still needs `init()` called somewhere, which is covered in the
[core package's readme](https://pub.dev/packages/code_scout).

## What you get

Every call writes one log when the request goes out, and normally a second when it comes back or
fails. The two share a request id, so the in-app panel and the dashboard show them as one row
rather than two unrelated entries, with the status, the duration, and the headers and bodies on
both sides.

A call can keep only its request log and show as pending. That happens when the app was killed
before the answer came, when the answer took more than two minutes, or when the response body broke
off part way through. In that last case your code gets the exception, but no error is recorded.

Unlike Dio, `package:http` does not treat a 4xx or 5xx as an error, so those arrive as ordinary
responses and keep their status code. Only a genuine transport failure, such as a refused
connection or a DNS problem, is recorded as an error.

You can read all of this on the device with no server configured at all. Tap the floating button
and open the Network tab.

## Tying a log to its call

When a response body stops matching your model, `fromJson` throws, and that error on its own does
not say which call sent the body. Pass the call's id with it:

```dart
final response = await client.get(Uri.parse('https://api.example.com/v2/cart'));
try {
  return Cart.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
} catch (e, st) {
  CodeScout.instance.e(
    'Could not read GET /v2/cart',
    error: e is FormatException ? 'FormatException: ${e.message}' : e,
    stackTrace: st,
    requestId: response.codeScoutRequestId,
  );
  rethrow;
}
```

The log is then shown with the call: in the in-app panel, and on the dashboard, where
`request:<id>` finds both. It stays an ordinary log, so a call that answered 200 is still a 200.
A request you build and pass to `send` has the same getter, so you can name a call that failed
before any response came back. `client.get` and the other shorthands build their request inside
the client, so a failure from one of them cannot be named, though it is still recorded as the
call's error. When a `RetryClient` wraps this client, the getter on the request you built returns
null, because `RetryClient` sends a copy, but the response it returns still names the call. The
`requestId` argument needs `code_scout` 1.6.0 or later.

The error you log is stored as its text, and redaction never looks inside it. A `FormatException`
from `jsonDecode` quotes the part of the body where parsing stopped, so the example logs only its
`message`. Any other error is logged as it is.

Network logs are written at debug level, apart from a transport failure, which is logged as an
error. At the default `minimumLevel` of info a call that got a response is not recorded, so your
log would carry the id of a call nobody kept. Set `minimumLevel` to `LogLevel.debug` to keep the
request and response beside it.

## Two things worth knowing

The response body is read into memory so it can be recorded. An `http.StreamedResponse` is
single subscription, meaning it can only be read once, so the wrapper reads the bytes and then
hands your code a fresh stream containing the same bytes. Your code sees no difference, but a
very large download is buffered rather than streamed straight through.

Nothing is redacted unless you ask for it. Out of the box the `Authorization` header and every
request body are recorded as sent, which is deliberate, since the token is sometimes the bug you
are chasing. Before you point this at real users, set `RedactionBehavior.recommended()` in your
CodeScout configuration.

## Checking it is working

If the Network tab stays empty, open the panel and tap the info icon. The wrapper announces
itself to CodeScout the moment you construct it, so the Info screen can tell you whether it is
genuinely missing or simply installed and has not seen a call yet.

## The rest of CodeScout

Network capture is one part of it. If you point the SDK at a dashboard you run yourself, the same
calls end up here, next to the logs the app wrote around them:

<p align="center">
  <img src="https://raw.githubusercontent.com/getcodescout/code_scout/main/.github/assets/screenshots/network.png" alt="The CodeScout network screen: a waterfall of HTTP calls beside a split-pane inspector" width="800" />
</p>

And a few things that are harder to get anywhere else:

- **Watch a device live.** Read somebody a six character code and their calls arrive in your
  browser as they tap. No install and no account for them.
- **Read the phone's own database.** While paired, browse the app's SQLite tables,
  `shared_preferences` and Hive boxes.
- **Hand a bug to your coding agent.** The dashboard speaks MCP, so an agent can read a whole
  session timeline itself.

[Take the tour](https://codescout.tech/docs/tour/) if you want to see it before installing
anything.

## License

MIT. See [LICENSE](LICENSE).
