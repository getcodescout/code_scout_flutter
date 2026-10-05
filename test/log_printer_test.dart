import 'dart:async';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/ansi_color.dart';
import 'package:code_scout/src/log/log_printer.dart';
import 'package:flutter_test/flutter_test.dart';

// The console is the first thing anybody sees of this SDK, and two things had
// been wrong for as long as it has been published: every line carried a
// malformed elapsed time reading `(+-0:00:00.000115)`, and three of the seven
// levels printed the enum's own toString. Six places in the docs and on the
// website also promised colour that was never emitted.
//
// These capture what is actually printed rather than calling the formatter,
// because the formatter is private and because what matters is the line a
// developer reads, not the function that helped build it.
void main() {
  String printed(LogLevel level) {
    final out = StringBuffer();
    runZoned(
      () => CSxPrinter(
        LogEntry(level: level, message: 'hello', sessionID: 's'),
      ).printToConsole(),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => out.writeln(line),
      ),
    );
    return out.toString();
  }

  // It was printed inside the network branch only, so a developer reading the
  // console had no way to tell which call an app's parse failure was about.
  test('a log about a call prints the call\'s request id', () {
    const id = '3b8e0c51-7f2d-4a9e-b1c4-92d05e6a1f37';
    final out = StringBuffer();
    runZoned(
      () => CSxPrinter(
        LogEntry(
          level: LogLevel.error,
          message: 'Could not read GET /v2/cart',
          sessionID: 's',
          requestId: id,
        ),
      ).printToConsole(),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => out.writeln(line),
      ),
    );

    expect(out.toString(), contains('Request ID: $id'));
    expect(printed(LogLevel.error), isNot(contains('Request ID')),
        reason: 'a log with no id says nothing about one');
  });

  group('the timestamp', () {
    test('has no elapsed-time suffix', () {
      // It read `(+-0:00:00.000115)`: the subtraction ran the wrong way, so the
      // duration was negative and the format prepended its own plus sign.
      final line = printed(LogLevel.info);
      expect(line, isNot(contains('(+')));
    });

    test('is a plain clock time', () {
      expect(printed(LogLevel.info), matches(RegExp(r'\[\d{2}:\d{2}:\d{2}\.\d{3}\]')));
    });
  });

  group('the level', () {
    const levels = [
      LogLevel.verbose,
      LogLevel.debug,
      LogLevel.info,
      LogLevel.warning,
      LogLevel.error,
      LogLevel.fatal,
      LogLevel.system,
    ];

    test('every level has a label of its own', () {
      for (final level in levels) {
        final line = printed(level);
        expect(line, isNot(contains('LogLevel.')),
            reason: '$level fell through to the enum toString');
        expect(line.toUpperCase(), contains(level.name.toUpperCase()),
            reason: '$level is not named in its own line');
      }
    });

    test('is colourised, which the docs have always claimed', () {
      final line = printed(LogLevel.error);
      expect(line, contains(AnsiColor.ansiEsc));
      expect(line, contains(AnsiColor.ansiDefault));
    });

    test('two levels do not share a colour', () {
      String seq(String s) {
        final i = s.indexOf(AnsiColor.ansiEsc);
        return s.substring(i, s.indexOf('m', i) + 1);
      }

      expect(seq(printed(LogLevel.error)), isNot(equals(seq(printed(LogLevel.info)))));
    });
  });
}
