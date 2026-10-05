import 'dart:collection';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:flutter/foundation.dart';

/// What the on-device overlay reads.
///
/// Deliberately not the SQLite table. Logs are deleted from there the moment
/// they upload, so with a server configured the overlay would show an emptying
/// list — and the newest log, the one you opened the overlay to look at, would
/// be the first to go. This is a capped in-memory ring of what this launch has
/// logged, which is what someone holding the phone actually wants, and it works
/// identically whether or not a server is configured.
class LogBuffer extends ChangeNotifier {
  static final LogBuffer i = LogBuffer._();

  LogBuffer._();

  /// Enough to scroll back through a bug, few enough that a chatty app cannot
  /// grow the heap without bound. Old entries fall off the back.
  static const int maxEntries = 500;

  final Queue<LogEntry> _entries = Queue<LogEntry>();

  /// Newest first, which is the order the overlay lists them in.
  List<LogEntry> get entries => _entries.toList(growable: false);

  int get length => _entries.length;

  int _unseenErrors = 0;

  /// Errors and fatals since the Errors tab was last opened.
  ///
  /// One counter behind two indicators: the number on the floating button,
  /// which is the only thing on screen, and the dot on the Errors tab, where
  /// the count is already one tap away. Levels below error are deliberately not
  /// counted — a badge that counts every log is a number that is always large
  /// and never means anything.
  int get unseenErrors => _unseenErrors;

  /// Opening the Errors tab is what clears it, not opening the sheet. A glance
  /// at Logs should not silently discard the signal.
  void markErrorsSeen() {
    if (_unseenErrors == 0) return;
    _unseenErrors = 0;
    if (hasListeners) notifyListeners();
  }

  void add(LogEntry entry) {
    _entries.addFirst(entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    if (entry.level.value >= LogLevel.error.value && entry.level != LogLevel.off) {
      _unseenErrors++;
    }
    // Only when the overlay is open. A chatty app would otherwise schedule a
    // rebuild per log for a widget tree nobody is looking at.
    if (hasListeners) notifyListeners();
  }

  /// The errors and fatals in the buffer, newest first, collapsed by exact
  /// message and error text so the same failure firing eight times is one row
  /// that counts.
  ///
  /// Deliberately not the server's fingerprint. `internal/domain/fingerprint.go`
  /// blanks the varying parts of a message, and porting it here would put one
  /// algorithm in two repos to drift apart. The two are answering different
  /// questions anyway: this counts a launch, the dashboard counts a project.
  List<ErrorGroup> errorGroups() {
    final byKey = <String, List<LogEntry>>{};
    final order = <String>[];

    for (final entry in _entries) {
      if (entry.level.value < LogLevel.error.value) continue;
      if (entry.level == LogLevel.off) continue;
      // A network failure's message is the literal string "Network Error" for
      // every one the SDK reports, so collapsing on it alone would make a
      // single meaningless row. The request id keeps the calls apart.
      final key = entry.isNetworkCall
          ? 'net:${entry.message}:${entry.requestId ?? ''}'
          : 'log:${entry.message}:${entry.error ?? ''}';
      if (!byKey.containsKey(key)) {
        byKey[key] = [];
        order.add(key);
      }
      byKey[key]!.add(entry);
    }

    return order.map((k) => ErrorGroup(byKey[k]!)).toList(growable: false);
  }

  void clear() {
    _entries.clear();
    _unseenErrors = 0;
    if (hasListeners) notifyListeners();
  }

  /// Every tag in the buffer, most used first, so the chips are the ones worth
  /// having rather than an alphabetical list of everything ever emitted.
  List<String> tags() {
    final counts = <String, int>{};
    for (final entry in _entries) {
      for (final tag in entry.tags ?? const <String>{}) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList();
    tags.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return tags;
  }

  /// The network calls in the buffer, phases paired by request id, newest
  /// first. The same collapsing the dashboard does, on the same data.
  ///
  /// A log the app wrote about a call carries the call's request id and is
  /// not a network log. It is attached to [OverlayCall.logs] and never to the
  /// phases, where its metadata could be read as the request and its level as
  /// a failure. Only a network phase makes a row: a linked log whose call has
  /// left the buffer, or was never captured, makes none.
  List<OverlayCall> calls() {
    final byRequest = <String, List<LogEntry>>{};
    final linked = <String, List<LogEntry>>{};
    final order = <String>[];

    for (final entry in _entries) {
      final id = entry.requestId;
      if (id == null) continue;
      if (!entry.isNetworkCall) {
        (linked[id] ??= []).add(entry);
        continue;
      }
      if (!byRequest.containsKey(id)) {
        byRequest[id] = [];
        order.add(id);
      }
      byRequest[id]!.add(entry);
    }

    return order
        .map((id) => OverlayCall(id, byRequest[id]!, logs: linked[id] ?? const []))
        .toList();
  }

  /// The call with this request id, or null when none of its phases are in
  /// the buffer.
  OverlayCall? callById(String requestId) {
    for (final call in calls()) {
      if (call.requestId == requestId) return call;
    }
    return null;
  }
}

/// One error, and the times it happened this launch.
class ErrorGroup {
  ErrorGroup(this.occurrences);

  /// Newest first, because that is the order they came out of the buffer.
  final List<LogEntry> occurrences;

  LogEntry get latest => occurrences.first;

  int get count => occurrences.length;

  String get message => latest.message;

  LogLevel get level => latest.level;

  bool get isNetwork => latest.isNetworkCall;

  /// The first frame that is not framework noise, which is the one worth
  /// putting under the message. The one you want is never the top one.
  ///
  /// [StackCallDetails] paths arrive with `package:` already stripped by the
  /// parser's regex, and a `dart:` frame never matches that regex at all, so
  /// the only prefix left to skip is Flutter's own.
  StackCallDetails? get appFrame {
    for (final frame in latest.stackCallDetails ?? const <StackCallDetails>[]) {
      final path = frame.path ?? '';
      if (path.isEmpty || path.startsWith('flutter/')) continue;
      return frame;
    }
    return null;
  }
}

/// One network call: its phases, and the answers the list needs from them.
class OverlayCall {
  OverlayCall(this.requestId, this.phases, {this.logs = const []});

  final String requestId;

  /// Newest first, because that is the order they came out of the buffer.
  final List<LogEntry> phases;

  /// What the app itself logged about this call, such as a body its model
  /// could not read. Newest first. Nothing below reads these: a call that
  /// answered 200 stays a 200 however badly the app took the body.
  final List<LogEntry> logs;

  LogEntry? phase(NetworkCallPhase want) {
    for (final entry in phases) {
      if (entry.callPhase == want) return entry;
    }
    return null;
  }

  bool get hasRequest => phase(NetworkCallPhase.request) != null;
  bool get hasResponse => phase(NetworkCallPhase.response) != null;
  bool get hasError => phase(NetworkCallPhase.error) != null;

  Map<String, dynamic> get _requestMeta {
    final direct = phase(NetworkCallPhase.request)?.metadata;
    if (direct != null) return direct;
    // The response and error phases nest the request they belong to, so a call
    // whose request phase fell off the back of the buffer still has a method
    // and a path to show.
    for (final entry in phases) {
      final nested = entry.metadata?['request'];
      if (nested is Map<String, dynamic>) return nested;
    }
    return const {};
  }

  String get method => (_requestMeta['method'] as String?) ?? '—';

  String get path {
    final url = _requestMeta['url'] as String?;
    if (url == null || url.isEmpty) return '—';
    var s = url;
    final scheme = s.indexOf('://');
    if (scheme >= 0) {
      s = s.substring(scheme + 3);
      final slash = s.indexOf('/');
      s = slash >= 0 ? s.substring(slash) : '/';
    }
    return s.isEmpty ? '/' : s;
  }

  /// The status code, from whichever phase carried one.
  ///
  /// The error phase has to be checked too: dio rejects 4xx and 5xx, so for a
  /// dio app the only place a 401's code exists is the error phase. Reading the
  /// response phase alone left every failed dio call showing no code at all.
  int? get statusCode {
    final fromResponse = phase(NetworkCallPhase.response)?.metadata?['status_code'];
    if (fromResponse is int) return fromResponse;
    final fromError = phase(NetworkCallPhase.error)?.metadata?['status_code'];
    return fromError is int ? fromError : null;
  }

  /// The same four states the dashboard distinguishes.
  String get status {
    // A code first, even on a failure: "401" says more than "error", and the
    // row is already coloured by [failed].
    if (statusCode != null) return '$statusCode';
    if (hasError) return 'error';
    if (hasResponse) return 'done';
    return 'pending';
  }

  bool get failed => hasError || (statusCode != null && statusCode! >= 400);

  /// The response's size on the wire, or null when nobody recorded one.
  ///
  /// Deliberately not `body.length`. By the time a body reaches the buffer,
  /// redaction has replaced values with a ten-character marker and truncation
  /// has cut anything over 32 KB, so measuring it would report a number that is
  /// not the size of anything. Until the companion packages carry a byte count
  /// taken before both, this is null and the row shows a dash.
  int? get responseBytes {
    final value = phase(NetworkCallPhase.response)?.metadata?['byte_length'];
    return value is int ? value : null;
  }

  /// Request to response, or null while a call is still in flight — timing an
  /// unfinished call against now would grow every time the list rebuilt.
  Duration? get duration {
    if (!hasRequest || (!hasResponse && !hasError)) return null;
    final start = phase(NetworkCallPhase.request)?.timestamp;
    final end = (phase(NetworkCallPhase.response) ?? phase(NetworkCallPhase.error))?.timestamp;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  DateTime? get startedAt => phase(NetworkCallPhase.request)?.timestamp ?? phases.last.timestamp;
}
