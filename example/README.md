# CodeScout example

A small app that exercises the SDK: the six log levels you call by hand, tags
and metadata, errors with real stack traces, redaction, identity, and network
capture through the Dio and http companion packages. There is a third companion
for Talker which this example does not install; if you use Talker, add
`code_scout_talker` and one `CodeScoutTalkerObserver` and capture works the
same way.

## Run it

```bash
flutter run
```

No configuration, and nothing is uploaded. Logs go to the console and to the
floating button, which opens the on-device viewer. They are not written to the
SDK's SQLite database, which only holds logs waiting to upload. This is a real
way to use CodeScout, not a limited trial of it.

The viewer has three tabs. Logs is everything the app has written, with a
search box, a toggle per level showing how many of each are buffered, tag chips
and a follow toggle for when the list moves faster than you can read. Network
is the calls. Errors collapses errors and fatals by exact message and error
text, so twenty copies of one failure are one row, and the floating button
carries a badge counting the ones you have not looked at. Two more screens sit
behind icons in the sheet header: Data browses the storage this app registered,
and Info tells you whether the connection works and what is being captured.
The pill next to the logo is where you pair with a dashboard for live
streaming.

## Point it at a dashboard

If you do not have an instance yet, the server is the sibling repository:
`make dev-setup` and then `make run` in `code_scout/` serve a dashboard on
`http://localhost:24275/`, which is the address already filled into
`local.example.json`.

Create a project and copy the id and secret from the last step of the wizard.
Then:

```bash
cp local.example.json local.json    # fill in the two values
flutter run --dart-define-from-file=local.json
```

`local.json` is gitignored, so nothing here ever has to hold a secret.

**`CS_URL` is the setting people get wrong.** `localhost` means the device, not
your machine, so it is right on the iOS simulator and on desktop and wrong
everywhere else. The Android emulator reaches your machine at `10.0.2.2`, and a
real phone needs your machine's LAN address. Android blocks plain HTTP from
API 28 on, so a real Android phone needs
`android:usesCleartextTraffic="true"` on the `<application>` tag in
`android/app/src/main/AndroidManifest.xml`, and a real iPhone pointed at
`http://<LAN IP>:24275/` is blocked the same way by App Transport Security
unless `ios/Runner/Info.plist` makes an exception. Neither file in this example
sets those, because the simulators do not need them.

The bar under the app title tells you which mode you are in. If you filled in
`local.json` and nothing arrives, open the overlay's Info screen, the second
icon in the sheet header, and press **Test connection**. It runs four checks in
order and stops at the one that failed, so it tells you whether credentials are
configured, whether anything answered, whether what answered was a CodeScout,
and whether it accepted the secret. It also names the project it reached, which
catches "connected to the wrong project" too.

This example uploads every 15 seconds, because waiting is tedious in a demo.
That is a setting here, not the default: `LogSyncBehavior(syncInterval:)`
defaults to five minutes, which is the number you want in a real app, since
each cycle is a compress and an upload paid for by whoever is holding the
phone.

**Upload now** on the app's Logs tab calls `flush()` and waits for the batch to
land or fail, which beats waiting for the timer when you are checking that the
connection works. One caveat: while the SDK is backing off, because five
uploads in a row failed or the server asked for a pause with `Retry-After`,
`flush()` returns at once without sending anything. The overlay's Info screen
shows the pause and can override it: while one is running, its upload button
reads "Try now, do not wait" and clears the backoff first.

## What each screen shows

The Logs tab is the SDK with no network involved. The six shorthand methods
each have a button, so you can see what `v`, `d`, `i`, `w`, `e` and `f` look
like once they land. One button logs with tags and metadata attached, which is
how you group logs in the dashboard and carry context along with them. Another
throws a `StateError` and catches it, so the stack trace is genuine and the
dashboard can take it apart frame by frame rather than showing you a string.
The redaction button logs a map holding an `authorization` value and a
`password`; `RedactionBehavior.recommended()` replaces both with `[redacted]`
at capture, before SQLite and before any upload, and keeps the rest of the map.
The last one calls `setUser`, which attributes the entire launch to that
person, including everything logged before you pressed it.

The Network tab makes the same requests twice, once with Dio and once with
`package:http`, so you can see that the choice of client changes nothing about
what reaches the dashboard. Neither package asks you to touch a call site:
`CodeScoutDioInterceptor` goes on the Dio you already have, and
`CodeScoutHttpClient` wraps the client you already have, each one line where
the client is built. Every call is captured in three phases correlated by one
request id, and the dashboard pairs them back into a single row. The buttons
call `jsonplaceholder.typicode.com`, so this tab needs a route to the
internet; the last button calls a host that does not resolve, so you can see
the error phase next to the successes.

The Data tab is everything this app keeps on the phone, with buttons that
change it. There are three stores, not one, and that is the point: a real
SQLite database the example opens for itself and hands over with
`registerDatabase` and `CodeScoutSqflite`, the `shared_preferences` map, and
two Hive boxes. The last two go through the same `CodeScoutKeyValue` adapter,
which takes closures rather than naming either package, which is why neither
one is a dependency of the SDK.

The screen lists the feature flags, the cart and the two key-value stores. The
database also holds an `account` row with an `auth_token` in it, which the
screen deliberately does not draw: open that table in a browser instead,
either the overlay's own Data screen, which needs no server at all and is read
only, or the dashboard's Database tab, and you will see `[redacted]` where the
token should be. `RedactionBehavior.recommended()` names `auth_token`, and
column names are matched the same way body keys are, so the value never leaves
the phone. There is also a view called `open_orders`, which a browser can show
but not edit.

For the dashboard route: start a live session on the dashboard, tap the
floating button, then tap the pill marked **Go live** at the top of the sheet
and type the six character code from the dashboard into it. Once the pill says
**Live**, the Database tab on the dashboard is browsing this phone, and you can
edit a cell, because this registration passes `writable: kDebugMode`.

Then come back to this screen. **Nothing you changed will have moved until you
press Reload**, and that is the point of the screen: the app read those rows
into memory when it built the view and has no idea the file changed underneath
it. Every app behaves this way, which is why the dashboard says so after a
write. Watching it once explains it better than the warning does.

## Testing an app that uses CodeScout

`test/widget_test.dart` boots the whole example under `flutter_test`. Run it
with `flutter test` from this directory; the same command at the repo root runs
the SDK's own suite instead. Two things are worth copying:

- Pump until the tree settles, with `pumpAndSettle()`, rather than pumping a
  single frame. `init()` runs in a post-frame callback and the overlay places
  itself a turn of the event loop later, so one `pump()` leaves a timer pending
  and the test fails on that instead of on anything real.
- Nothing is mocked. With no credentials the SDK never opens a socket, and a
  database it cannot open is handled rather than thrown, so the app under test
  behaves exactly as it does on a device.
