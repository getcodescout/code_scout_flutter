## 1.1.0

### Added

- **`codeScoutRequestId` names the call a response came from.** It is on any
  `http.BaseResponse` this client returns, `Response` and `StreamedResponse`
  alike, and on a `BaseRequest` you send through it. Pass it as `requestId`
  when you log something about the call, such as a body your model could not
  read, and CodeScout shows the log with the call: in the in-app panel, and on
  the dashboard, where `request:<id>` finds both.

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

  The `requestId` argument arrived in `code_scout` 1.6.0. The error you log is
  not redacted, and a `FormatException` from `jsonDecode` quotes the part of
  the body where parsing stopped, so the example logs only its message.

### Changed

- **`response.request` is the request you sent through this client.** It used
  to be whatever the wrapped client reported, which is nothing from
  `MockClient` and a copy from `RetryClient`, and neither of those could be
  traced back to the call.

### Fixed

- **A failed call no longer records the error's own text.** That text is not
  redacted, and dart:io's can quote the request: a header value it rejects, such
  as an `Authorization` token that ends in a newline, and the bytes of a
  streamed body longer than its `contentLength`. Both reached the call's error
  even with `RedactionBehavior.recommended()` set. A socket failure still says
  why, such as `Connection refused`, because those words carry nothing of the
  request but its host. Any other error is named by its type alone.

## 1.0.4

### Added

- An example showing the client wrapper in an app, including closing it.

## 1.0.3

### Changed

- **The name reads CodeScout, one word.** The description published with 1.0.2
  still said "Code Scout", because the rename landed after that version went out
  and pub.dev only takes a new listing with a new version.
- **The readme says what the rest of CodeScout does.** It used to end at the
  licence, so somebody who installed this for package:http capture had no way to learn
  that live device streaming, the database browser and the agent tools exist.

No code changed in this release.

## 1.0.2

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true, so pub.dev advertised compatibility with releases that could
  not resolve the package. Nothing about the code changed.

## 1.0.1

- **Fix:** `CodeScoutHttpClient` returned an already-drained response stream,
  breaking every request made through it (`Stream has already been listened to`).
  The body is now buffered and an equivalent response is returned to the caller.
- **Fix:** capture is wrapped defensively. A CodeScout failure can no longer
  fail the underlying HTTP request (e.g. when used before `CodeScout.init()`).

## 1.0.0

* Initial release.
* HTTP client wrapper that automatically captures network requests, responses, and errors for CodeScout.
