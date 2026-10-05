# code_scout_dio

[![pub.dev](https://img.shields.io/pub/v/code_scout_dio.svg)](https://pub.dev/packages/code_scout_dio)

Captures every HTTP call your Dio client makes and shows it to you, either on the phone itself or
on a [CodeScout](https://codescout.tech) dashboard you run.

This is the Dio half of CodeScout. The core package,
[`code_scout`](https://pub.dev/packages/code_scout), does the logging and has no HTTP dependency
of its own, which is why network capture lives out here. Installing CodeScout never drags Dio
into an app that does not already use it.

## Getting started

```bash
flutter pub add code_scout_dio
```

Then attach the interceptor to the client you already have:

```dart
import 'package:dio/dio.dart';
import 'package:code_scout_dio/code_scout_dio.dart';

final dio = Dio();
dio.interceptors.add(CodeScoutDioInterceptor());
```

That is the whole setup. CodeScout itself still needs `init()` called somewhere, which is
covered in the [core package's readme](https://pub.dev/packages/code_scout).

## What you get

Every call writes one log when the request goes out, and normally a second when it comes back or
fails. The two share a request id, so the in-app panel and the dashboard show them as one row
rather than two unrelated entries, with the status, the duration, and the headers and bodies on
both sides.

A call can keep only its request log and show as pending. That happens when the app was killed
before the answer came, when the answer took more than two minutes, or when another interceptor
rejected the call after this one saw the request and before it saw the response. A call that
another interceptor rejects before this one sees the request is not recorded at all.

You can read all of this on the device with no server configured at all. Tap the floating button
and open the Network tab.

## Tying a log to its call

When a response body stops matching your model, `fromJson` throws, and that error on its own does
not say which call sent the body. Pass the call's id with it:

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

The log is then shown with the call: in the in-app panel, and on the dashboard, where
`request:<id>` finds both. It stays an ordinary log, so a call that answered 200 is still a 200.
A `DioException` has the same getter, so you can name a failed call from a `catch` too, including
a body that does not fit the type you asked for. The `requestId` argument needs `code_scout` 1.6.0
or later.

Network logs are written at debug level, apart from a failure, which is logged as an error. At the
default `minimumLevel` of info a call that succeeded is not recorded, so your log would carry the
id of a call nobody kept. Set `minimumLevel` to `LogLevel.debug` to keep the request and response
beside it.

## Two things worth knowing

Dio treats a 4xx or 5xx as an error rather than a response, because that is what its default
`validateStatus` does. Those calls therefore arrive through the error path and are logged at
error level, which is usually what you want, but it does mean a plain 404 shows up under Errors
as well as under Network.

Nothing is redacted unless you ask for it. Out of the box the `Authorization` header and every
request body are recorded as sent, which is deliberate, since the token is sometimes the bug you
are chasing. Before you point this at real users, set `RedactionBehavior.recommended()` in your
CodeScout configuration.

## Checking it is working

If the Network tab stays empty, open the panel and tap the info icon. The interceptor announces
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
