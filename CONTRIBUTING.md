# Contributing to the CodeScout Flutter SDK

Thanks for looking. Pull requests are genuinely welcome.

## Before you start something big

Open an issue first. A short note saying what you want to do usually gets an answer the same day,
and it saves you building something that does not fit. Small fixes need no ceremony.

## What lives here

Five packages, each with its own pubspec. That is worth noticing early, because most of the
commands below have to be run once per package rather than once at the root.

| Path | Package |
|------|---------|
| `.` | `code_scout`, the SDK itself |
| `packages/code_scout_dio` | the Dio interceptor |
| `packages/code_scout_http` | the `package:http` client wrapper |
| `packages/code_scout_talker` | the Talker observer |
| `example` | a runnable app using the core plus the Dio and http companions |

The three companion packages live in this repository on purpose rather than in their own. They call
the core's `NetworkManager` API, so they change with it, and splitting them would turn one commit
into a coordinated release across four repositories with a window where they disagree. The Talker
observer is the one the example app does not use; its own package tests are what cover it.

## Getting set up

You need Dart 3.10 or newer, which means Flutter 3.38 or newer; every pubspec here sets
`sdk: ^3.10.0` and `flutter: '>=3.38.0'`. The floor comes from the plus plugins rather than from
our own code, which still analyses clean at Dart 3.8.

Resolve every package before anything else. The root `flutter pub get` covers the SDK itself and
nothing more, and each of the other four has a pubspec that pub will not resolve on your behalf:

```bash
flutter pub get
(cd packages/code_scout_dio && flutter pub get)
(cd packages/code_scout_http && flutter pub get)
(cd packages/code_scout_talker && flutter pub get)
(cd example && flutter pub get)
```

### How the companions find the core

Each companion's pubspec declares a hosted dependency on `code_scout` at the version in this tree,
which is often a version pub.dev does not have yet. They resolve anyway because each one carries a
`pubspec_overrides.yaml` pointing `code_scout` at `../../`. That file is what lets a companion use
a core API in the same commit that adds it. pub never publishes it, so nobody installing from
pub.dev is affected; the hosted constraint in `pubspec.yaml` is what they get. Delete it and
`flutter pub get` in that package stops with "code_scout ^1.5.0 which doesn't match any versions",
which reads like a broken repository rather than a missing file.

Two consequences worth knowing. The core has to be published before any companion that needs its
new API can be. And `flutter pub publish --dry-run` in a companion prints the hint "Non-dev
dependencies are overridden in pubspec_overrides.yaml", which is expected, not a failure.

The example does the same job with a `dependency_overrides` block in its own pubspec, so the
companions inside it resolve the local core too.

### Running the example

```bash
cd example && flutter run
```

It starts with no configuration at all. Logs go to the console and to the floating overlay on the
device, and nothing is uploaded anywhere. That is a real way to use CodeScout rather than a
degraded one, which is why it is the default here.

To point it at a dashboard, copy `example/local.example.json` to `example/local.json`, fill in all
three values (`CS_URL`, `CS_PROJECT_ID` and `CS_PROJECT_SECRET`), and run, from inside `example/`:

```bash
flutter run --dart-define-from-file=local.json
```

All three have to be set. With any one of them blank the SDK stays on the device and says nothing
about why. `local.json` is gitignored, so your project secret cannot end up in a commit. The URL in
the template points at a dashboard on localhost, which works from the iOS simulator and desktop;
the Android emulator reaches your machine as `http://10.0.2.2:24275/`, and a real phone needs your
machine's LAN IP.

## Running the tests

```bash
flutter analyze          # must exit 0, including info level lints
flutter test
```

`flutter test` only runs the suite of the package you are in. The root run never touches the
companions' tests, so run it in each package you changed, or in all five the way CI does. CI runs
`flutter analyze` and `flutter test` for all five packages on every push and pull request, plus
`flutter pub publish --dry-run` for the four publishable ones.

Three things to know, because each has caught someone out:

**`flutter analyze` at the root also analyses `packages/`.** Without a `flutter pub get` in each
package first you get a screen of "undefined" errors about code that is perfectly fine, which is
why the setup section starts with five of them.

**`flutter analyze` fails on info level lints too.** If you genuinely need to break one, use a
scoped `// ignore:` with a comment saying why, rather than switching the rule off for everyone.

**Do not run `dart format` across the tree.** Formatting is not checked in CI and the tree is not
format-clean, so a whole-tree reformat buries your three line fix in a diff across most of the
repository. Format the lines you touched and leave the rest.

### If your new test silently does nothing

Two things about the test host fail without a word. `TestWidgetsFlutterBinding` installs an
`HttpOverrides` that answers every request with 400 without ever opening a socket, so a test that
needs the real network has to set `HttpOverrides.global = null`; it takes out the live WebSocket as
well as the uploader. And `getTemporaryDirectory()` is a platform channel with nothing behind it on
a test host, so left alone the compressor throws inside the sync worker's own catch, which reports
through `dart:developer` where the test runner never shows it. Both fixes are already written down
in `test/e2e/`, including `installScratchPaths` in `test/e2e/dashboard.dart`.

### The end to end test

`test/e2e/` runs this SDK against a real dashboard and skips unless `CS_E2E_BASE` is set. Start it
from the server repository, which owns the throwaway database and port:

```bash
cd ../code_scout && make test-sdk-e2e
```

The target assumes the two repositories sit side by side; pass
`sdk_dir=/path/to/code_scout_flutter` if yours do not. It needs a local Postgres and the server
repo's configuration in place (`make dev-setup` over there writes it), and it then builds the
server, runs it on its own port with its own database, and drops both again afterwards. On Linux
you also need the SQLite library itself (`libsqlite3-dev` on Debian and Ubuntu), because the tests
open SQLite through `dart:ffi`.

This is the only test anywhere that proves the SDK and the dashboard still agree. Everything else
checks each side against its own copy of the contract, and two copies drift without anything going
red. There are three files. `test/e2e/sdk_to_dashboard_test.dart` logs through the public API and
reads the rows back out of the dashboard's export endpoint. `test/e2e/db_browser_test.dart` pairs a
real live session over a real socket and drives the dashboard's own `/live/{sid}/db*` routes
against a real SQLite file. `test/e2e/linked_log_test.dart` makes a real call through the dio
interceptor and checks that a log the app wrote about it, with the id from `codeScoutRequestId`,
is linked to that call on the dashboard. Worth running locally if you touch the wire format, the
compressor, the sync worker, the live socket, the database browser or the request id, and it runs
in CI on every pull request anyway, so a break there fails your PR whether or not you got to it
first.

## What a good pull request looks like

**It comes with a test, and the test fails without the fix.** Undo your change and watch it go red.
If it stays green the test is not testing what you think, which is better to find out now.

**It explains why, not what.** The comments people are grateful for are the ones explaining why
something surprising is written the way it is.

The pull request template repeats both as a checklist, so you do not need to memorise them.

### If you bump a version

`pubspec.yaml` is not the whole job. The version also lives as a constant in `lib/src/version.dart`,
because Dart cannot read its own pubspec at runtime, and it goes on the wire as `sdk_version` on
every session. `test/version_test.dart` compares the two and fails when they drift, so bump both in
the same commit. That test reads `pubspec.yaml` by relative path, so it only passes when
`flutter test` runs from the package root. Each publishable package also has its own
`CHANGELOG.md`; the entry goes in the changelog of the package whose behaviour changed.

## House rules worth knowing

**An observability library must never break the app it observes.** The fire-and-forget calls,
`log()` and the `.v() .d() .i() .w() .e() .f()` shorthand, are caught all the way down and can
never throw into your caller. There is exactly one deliberate exception: `logMessage()` passes
`rethrowErrors: true` into `processLogEntry`, because somebody who awaited the call is asking
whether the write actually happened, and a silent success is a lie. If you add a path that can
throw out of the fire-and-forget side, that is a bug even if the feature works.

**Nothing is redacted unless the app asks.** Redaction is opt in, because the token is often exactly
why a request is failing. What the app names is stripped at capture, before SQLite and before any
upload.

**No third party HTTP dependencies in the core.** Everything talks to the server through `dart:io`
`HttpClient`. That is what keeps the core package light and free of version conflicts with whatever
the host app already uses.

**Compression happens on a background isolate.** A batch can be thousands of logs, and gzipping
that on the UI thread would drop frames inside somebody else's app while they were trying to debug
it. `LogCompressor` hands the work to `compute`, so anything you add to the upload path has to
survive that boundary: the entry point must be a top level or static function, and the payload must
be plain sendable data. A closure or a live database handle compiles and then fails at runtime,
inside the sync worker's own catch, where the message goes to `dart:developer` and you will not
see it.

## Reporting a bug

Open an issue and the bug report form will ask for the package and version, the platform, your
`init()` call with the secret removed, and the console output. The console output is the field
worth extra care: the SDK reports its own failures through `dart:developer` rather than throwing,
so any line beginning `CodeScout:` is the SDK saying what went wrong, and it is often the whole
answer. If the dashboard is involved, the server's own log around the same moment says more than
anything the phone can see.

Anything that turns out to be the server or the web dashboard rather than the SDK belongs in the
[`getcodescout/code_scout`](https://github.com/getcodescout/code_scout/issues) repository, and the
issue chooser will offer you that link.

For security issues, see [SECURITY.md](SECURITY.md) and please do not open a public issue.

## Licence

By contributing you agree that your contribution is licensed under the MIT licence, the same as the
rest of the project.
