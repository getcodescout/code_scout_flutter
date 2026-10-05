import 'dart:convert';

import 'package:code_scout/code_scout.dart';

/// What lands on the clipboard when somebody copies a log.
///
/// Plain text, not JSON, because it is going into a chat window rather than
/// into a parser. The session id and the device ride along because they are the
/// two things whoever reads the report asks for next, and reading a UUID off a
/// screen out loud is how bug reports end up attached to the wrong session.
String formatLogForClipboard(LogEntry entry, {SessionRecord? session, String? sessionId}) {
  final out = StringBuffer()
    ..writeln('[${entry.level.name}] ${_stamp(entry.timestamp)}')
    ..writeln(entry.message);

  if (entry.error != null) {
    out
      ..writeln()
      ..writeln(entry.error.toString());
  }

  final frames = entry.stackCallDetails ?? const [];
  if (frames.isNotEmpty) {
    out.writeln();
    for (final frame in frames) {
      out.writeln('  ${frame.method ?? '?'}');
      if (frame.path != null) {
        out.writeln('  ${frame.path}:${frame.line ?? 0}:${frame.column ?? 0}');
      }
    }
  }

  final metadata = entry.metadata;
  if (metadata != null && metadata.isNotEmpty) {
    out
      ..writeln()
      // Encoded rather than toString()'d: a Dart map prints as
      // {a: 1, b: 2}, which is not JSON and does not paste into anything.
      ..writeln(_encode(metadata));
  }

  final tags = entry.tags;
  if (tags != null && tags.isNotEmpty) {
    out
      ..writeln()
      ..writeln('tags: ${tags.join(', ')}');
  }

  // In full, never shortened like the session id below: it is what the
  // dashboard's request: search takes, and a shortened id finds nothing.
  final trailer = [
    if (entry.requestId != null) 'request ${entry.requestId}',
    _trailer(session: session, sessionId: sessionId),
  ].where((line) => line.isNotEmpty).join('\n');
  if (trailer.isNotEmpty) {
    out
      ..writeln()
      ..write(trailer);
  }

  return out.toString().trimRight();
}

String _trailer({SessionRecord? session, String? sessionId}) {
  final lines = <String>[];

  final id = sessionId ?? session?.id;
  final parts = <String>[
    if (id != null) 'session ${_short(id)}',
    if (session?.deviceModel != null) session!.deviceModel!,
    if (session?.osName != null)
      [session!.osName, session.osVersion].where((p) => p != null && p.isNotEmpty).join(' '),
  ];
  if (parts.isNotEmpty) lines.add(parts.join(' · '));

  final app = <String>[
    if (session?.appVersion != null)
      'app ${session!.appVersion}${session.buildNumber == null ? '' : '+${session.buildNumber}'}',
    // From the constant, not the record. sdk_version is wire-only: it is added
    // in toJson() and never stored on the row, because a key added for the
    // server that also lands in the SQLite INSERT fails every session write.
    'sdk $codeScoutSdkVersion',
  ];
  if (app.isNotEmpty) lines.add(app.join(' · '));

  return lines.join('\n');
}

/// Enough of a uuid to identify a session in a chat message, and short enough
/// that nobody retypes it wrong.
String _short(String id) => id.length <= 12 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

String _stamp(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = local.millisecond.toString().padLeft(3, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$ms';
}

/// Never throws. A metadata map can hold anything the app put in it, including
/// a value with no JSON encoding, and losing the whole copy over one field
/// would be worse than printing that field's toString().
String _encode(Object? value) {
  try {
    // toEncodable catches the single unencodable field rather than losing the
    // whole map to it.
    return JsonEncoder.withIndent('  ', (o) => o.toString()).convert(value);
  } catch (_) {
    return value.toString();
  }
}
