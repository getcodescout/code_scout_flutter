import 'dart:convert';
import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/ansi_color.dart';

class CSxPrinter {
  final LogEntry logEntry;

  CSxPrinter(this.logEntry);

  void printToConsole({NetworkData? networkData}) {
    final buffer = StringBuffer();

    // Print a divider to clearly separate logs
    buffer.writeln('\n${_createDivider()}');

    // Print timestamp and log level with colored formatting
    buffer.writeln(
      '[${getTime(logEntry.timestamp!.toLocal())}] [${_formatLogLevel(logEntry.level)}] ${stringifyMessage(logEntry.message)}',
    );

    // Handle network-specific logs
    if (logEntry.isNetworkCall == true) {
      _formatNetworkLog(buffer, networkData);
    }
    // Handle regular logs
    else {
      // An app log carries one when it is about a call, such as a body that
      // failed to parse. It is the key that finds that call's phases.
      if (logEntry.requestId != null) {
        buffer.writeln('🆔 Request ID: ${logEntry.requestId}');
      }

      if (logEntry.metadata != null) {
        buffer.writeln('📋 Metadata: ${_formatMetadata(logEntry.metadata!)}');
      }

      if (logEntry.error != null) {
        buffer.writeln('❌ Error: ${logEntry.error.toString()}');
      }

      if (logEntry.tags != null && logEntry.tags!.isNotEmpty) {
        buffer.writeln('🏷️ Tags: ${logEntry.tags!.join(', ')}');
      }
    }

    // Print stack trace for both network and regular logs if available
    if (logEntry.formattedStackTrace != null) {
      buffer.writeln(
        '📚 Stack Trace:\n${logEntry.formattedStackTrace?.join('\n')}',
      );
    }

    buffer.writeln(_createDivider());

    // The one deliberate print in the package. This is the console printer —
    // printing is what it is for, and dart:developer's log() is not a
    // substitute: it drops the ANSI colour and the multi-line framing that make
    // a log readable in a terminal. Scoped to this line so the lint keeps
    // working everywhere else.
    // ignore: avoid_print
    print(buffer.toString());
  }

  void _formatNetworkLog(StringBuffer buffer, NetworkData? networkData) {
    buffer.writeln(
      '📡 Network Call - ${_getNetworkPhaseEmoji(logEntry.callPhase)}',
    );

    if (logEntry.requestId != null) {
      buffer.writeln('🆔 Request ID: ${logEntry.requestId}');
    }

    if (logEntry.metadata != null) {
      final metadata = logEntry.metadata!;

      // Format request details
      if (metadata.containsKey('method') && metadata.containsKey('url')) {
        buffer.writeln('🌐 ${metadata['method']} ${metadata['url']}');
      }

      // Format response details
      if (metadata.containsKey('status_code')) {
        buffer.writeln('📊 Status Code: ${metadata['status_code']}');
      }

      // Format headers
      if (metadata.containsKey('headers') && metadata['headers'] != null) {
        buffer.writeln('📝 Headers: ${_formatMetadata(metadata['headers'])}');
      }

      // Format request/response body
      if (metadata.containsKey('body') && metadata['body'] != null) {
        buffer.writeln('📦 Body: ${stringifyMessage(metadata['body'])}');
      }

      // Format error details
      if (metadata.containsKey('type') && metadata.containsKey('message')) {
        buffer.writeln('❌ Error Type: ${metadata['type']}');
        buffer.writeln('❌ Error Message: ${metadata['message']}');
      }

      // For network response, show original request
      if (logEntry.callPhase == NetworkCallPhase.response ||
          logEntry.callPhase == NetworkCallPhase.error) {
        if (metadata.containsKey('request') && metadata['request'] != null) {
          buffer.writeln(
            '🔍 Original Request: ${_formatMetadata(metadata['request'])}',
          );
        }
      }
    }
  }

  /// The colour each level is printed in, as a 256-colour ANSI foreground.
  ///
  /// `AnsiColor` sat unused in this package while six places in the docs and on
  /// the website promised colour coded console output, so this is the claim
  /// being made true rather than withdrawn.
  static const _levelColours = <LogLevel, AnsiColor>{
    LogLevel.verbose: AnsiColor.fg(244), // grey
    LogLevel.debug: AnsiColor.fg(39), // blue
    LogLevel.info: AnsiColor.fg(35), // green
    LogLevel.warning: AnsiColor.fg(214), // amber
    LogLevel.error: AnsiColor.fg(196), // red
    LogLevel.fatal: AnsiColor.fg(199), // magenta
    LogLevel.system: AnsiColor.fg(141), // violet
  };

  /// Every level gets its own label. `default` used to catch verbose, fatal and
  /// system and print them as `LogLevel.verbose`, which is the enum's own
  /// `toString` leaking into what a developer reads all day.
  static const _levelLabels = <LogLevel, String>{
    LogLevel.verbose: '🔍 VERBOSE',
    LogLevel.debug: '🐛 DEBUG',
    LogLevel.info: 'ℹ️ INFO',
    LogLevel.warning: '⚠️ WARNING',
    LogLevel.error: '❌ ERROR',
    LogLevel.fatal: '💀 FATAL',
    LogLevel.system: '⚙️ SYSTEM',
  };

  String _formatLogLevel(LogLevel level) {
    final label = _levelLabels[level] ?? level.name.toUpperCase();
    final colour = _levelColours[level];
    return colour == null ? label : colour(label);
  }

  String _getNetworkPhaseEmoji(NetworkCallPhase? phase) {
    switch (phase) {
      case NetworkCallPhase.request:
        return '↗️ Request';
      case NetworkCallPhase.response:
        return '↙️ Response';
      case NetworkCallPhase.error:
        return '❌ Error';
      default:
        return 'Unknown';
    }
  }

  String _createDivider() {
    return '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  }

  String _formatMetadata(Map<String, dynamic> metadata) {
    return const JsonEncoder.withIndent('  ').convert(metadata);
  }

  String stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      var encoder = JsonEncoder.withIndent('  ', toEncodableFallback);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }

  // Handles any object that is causing JsonEncoder() problems
  Object toEncodableFallback(dynamic object) {
    return object.toString();
  }

  String getTime(DateTime time) {
    String threeDigits(int n) {
      if (n >= 100) return '$n';
      if (n >= 10) return '0$n';
      return '00$n';
    }

    String twoDigits(int n) {
      if (n >= 10) return '$n';
      return '0$n';
    }

    var now = time;
    var h = twoDigits(now.hour);
    var min = twoDigits(now.minute);
    var sec = twoDigits(now.second);
    var ms = threeDigits(now.millisecond);
    return '$h:$min:$sec.$ms';
  }
}
