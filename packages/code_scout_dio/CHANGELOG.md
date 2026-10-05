## 1.1.0

### Added

- **`codeScoutRequestId` names the call a response came from.** It is on
  `Response`, `DioException` and `RequestOptions`. Pass it as `requestId` when
  you log something about the call, such as a body your model could not read,
  and CodeScout shows the log with the call: in the in-app panel, and on the
  dashboard, where `request:<id>` finds both.

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

  The `requestId` argument arrived in `code_scout` 1.6.0. A body that does not
  fit the type you asked for, such as a list from `get<Map<String, dynamic>>`,
  reaches you as a `DioException` whose `codeScoutRequestId` names the call too.
- `codeScoutRequestIdKey`, the key the interceptor keeps the id under in
  `RequestOptions.extra`.

### Fixed

- **A body that is not JSON no longer fails with an empty message.** dio wraps
  the `FormatException` from its JSON transformer without a message of its own,
  so the call's error was recorded blank. It now reads `FormatException`, and
  any other error dio wraps that way is named by its type too. Only the type is
  kept, never the error's text. That text is not redacted, and it can quote the
  request: dart:io puts a header value it rejects into it, such as an
  `Authorization` token that ends in a newline, and the body it was sending
  when that body is longer than its `Content-Length`. Both would have got past
  `RedactionBehavior.recommended()`.

## 1.0.4

### Fixed

- **The declared dio range was wrong.** It claimed `>=5.0.0`, but the interceptor
  uses `DioException` and `DioExceptionType`, which do not exist before dio 5.2.0.
  Anyone on an earlier 5.x got seven compile errors on install. The lower bound is
  5.2.0 now, found by bisecting: 5.1.2 fails and 5.2.0 passes.

### Added

- An example showing the interceptor wired into an app.

## 1.0.3

### Changed

- **The name reads CodeScout, one word.** The description published with 1.0.2
  still said "Code Scout", because the rename landed after that version went out
  and pub.dev only takes a new listing with a new version.
- **The readme says what the rest of CodeScout does.** It used to end at the
  licence, so somebody who installed this for Dio capture had no way to learn
  that live device streaming, the database browser and the agent tools exist.

No code changed in this release.

## 1.0.2

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true, so pub.dev advertised compatibility with releases that could
  not resolve the package. Nothing about the code changed.

## 1.0.1

- **Fix:** capture is wrapped defensively. A CodeScout failure can no longer
  fail the underlying request (previously a request made before
  `CodeScout.init()` surfaced as a `DioException` for a request that was never
  attempted). A null `statusCode` no longer throws in `onResponse`.

## 1.0.0

* Initial release.
* Dio interceptor that automatically captures network requests, responses, and errors for CodeScout.
