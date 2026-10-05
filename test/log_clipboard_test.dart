import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// A copied log is pasted into a bug report and read by somebody at the
/// dashboard, so whatever they need to find it again has to survive the copy.
void main() {
  const id = '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37';

  // The session id is shortened on purpose, for reading aloud. The request id
  // is what `request:` on the dashboard takes, and a shortened one finds
  // nothing, so it goes in whole on a line of its own.
  test('a log about a call carries the full request id', () {
    final text = formatLogForClipboard(
      LogEntry(
        level: LogLevel.error,
        message: 'Could not read GET /v2/cart',
        sessionID: 's',
        requestId: id,
      ),
      sessionId: 'c0ffee00-1111-4222-8333-444455556666',
    );

    expect(text.split('\n'), contains('request $id'));
  });

  test('a log with no request id has no request line', () {
    final text = formatLogForClipboard(
      LogEntry(level: LogLevel.info, message: 'cart viewed', sessionID: 's'),
      sessionId: 'c0ffee00-1111-4222-8333-444455556666',
    );

    expect(text, isNot(contains('request ')));
  });
}
