import 'dart:convert';
import 'dart:developer';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_printer.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

class LogEntry {
  final String id;
  final String sessionID;
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final Set<String>? tags;
  final DateTime? timestamp;
  final bool isNetworkCall;

  /// The HTTP call this log belongs to, or null. A UUID is kept lowercase.
  ///
  /// The server stores this column as a UUID, and one value that does not
  /// parse fails the whole upload, which the sync worker then retries forever
  /// with every later log queued behind it. So [toJson] writes nothing but a
  /// UUID in the standard 8-4-4-4-12 form. An app's own log drops anything
  /// else when it is built, so a backend's `X-Request-Id` or a ULID never gets
  /// that far. A network phase keeps the id its interceptor minted, because
  /// that id is what pairs its call in the panel and in a live session.
  final String? requestId;
  final NetworkCallPhase? callPhase;

  List<String>? _formattedStackTrace;

  List<String>? get formattedStackTrace => _formattedStackTrace;

  List<StackCallDetails>? _stackCallDetails;

  List<StackCallDetails>? get stackCallDetails => _stackCallDetails;

  LogEntry({
    required this.level,
    required this.message,
    required this.sessionID,
    this.error,
    this.stackTrace,
    Map<String, dynamic>? metadata,
    this.tags = const {},
    this.isNetworkCall = false,
    String? requestId,
    this.callPhase,
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now().toUtc(),
        requestId = _canonicalRequestId(requestId, isNetworkCall: isNetworkCall),
        // Redacted here, at capture, rather than only on the way to JSON.
        //
        // toJson() stripped it, so SQLite and the upload were clean and the
        // dashboard showed [redacted] — which is exactly what made this hard
        // to notice. Everything that reads the entry directly still had the
        // real value: the overlay's detail screen, the console printer, and
        // the copy button whose output people paste into bug reports.
        //
        // Network metadata was already redacted when it was built, so it is
        // left alone; walking it twice would be harmless but says something
        // untrue about where the responsibility sits.
        metadata = isNetworkCall ? metadata : Redactor.metadata(metadata) {
    final includeCurrentStackTrace =
        CodeScout.instance.configuration.logging.includeCurrentStackTrace;

    if ((!includeCurrentStackTrace && stackTrace == null) || isNetworkCall) {
      return;
    }

    StackTraceParser parser = StackTraceParser(
      stackTrace: stackTrace == null && includeCurrentStackTrace
          ? StackTrace.current
          : stackTrace,
      methodCount: 10,
    );

    parser.parse();

    _formattedStackTrace = parser.formattedTrace;
    _stackCallDetails = parser.stackCallDetails;
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static bool _warnedAboutRequestId = false;

  /// Where the warning about a dropped request id is written. Replaceable so a
  /// test can read what was said.
  @visibleForTesting
  static void Function(String message) requestIdWarning = (message) => log(message);

  /// The warning is said once per process, so a test that wants to see it
  /// again has to put it back.
  @visibleForTesting
  static void resetRequestIdWarning() => _warnedAboutRequestId = false;

  /// Lowercased, because the live frame carries the id as a string and the
  /// dashboard pairs phases by comparing strings.
  ///
  /// The dropped value is never repeated in the warning. An app that passes
  /// the wrong header here may be passing a token.
  static String? _canonicalRequestId(String? raw, {required bool isNetworkCall}) {
    if (raw == null) return null;
    if (_uuid.hasMatch(raw)) return raw.toLowerCase();
    if (!_warnedAboutRequestId) {
      _warnedAboutRequestId = true;
      requestIdWarning(
        'CodeScout: dropped a request id that is not a UUID, which the server '
        'could not store. Pass the codeScoutRequestId that code_scout_dio or '
        'code_scout_http put on the response, or mint ids with '
        'NetworkRequestData.newRequestID() in your own interceptor. Said once '
        'per launch.',
      );
    }
    return isNetworkCall ? raw : null;
  }

  /// Null unless the id is a UUID in the standard form.
  static String? _uploadableRequestId(String? id) =>
      id != null && _uuid.hasMatch(id) ? id : null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionID,
      'level': level.name,
      'message': message,
      'error': error?.toString(),
      'stack_trace': jsonEncode(
        _stackCallDetails?.map((e) => e.toJson()).toList() ?? [],
      ),
      // Already redacted: network metadata when it was built, everything else
      // in the constructor. Kept as a second pass rather than dropped because
      // it is idempotent — a value that is already the placeholder walks to the
      // placeholder — and this is the last point before the wire.
      'metadata': jsonEncode(
        isNetworkCall ? (metadata ?? {}) : (Redactor.metadata(metadata) ?? {}),
      ),
      'tags': jsonEncode(tags?.toList() ?? []),
      'timestamp': timestamp?.toIso8601String(),
      'is_network_call': isNetworkCall ? 1 : 0,
      'request_id': _uploadableRequestId(requestId),
      'call_phase': callPhase?.name,
    };
  }

  /// Runs one log through the pipeline.
  ///
  /// [rethrowErrors] is what separates the fire-and-forget shorthand from
  /// [CodeScout.logMessage]. A logging call must never be able to fail the app
  /// that made it, so everything here is caught by default. Somebody who
  /// deliberately awaited the call and wants to know whether the write happened
  /// asks for the exception instead.
  Future<void> processLogEntry({
    NetworkData? networkData,
    bool rethrowErrors = false,
  }) async {
    try {
      CodeScoutConfiguration cfg = CodeScout.instance.configuration;
      if (!cfg.logging.shouldLog(this)) {
        return;
      }

      // Honoured, rather than declared and ignored. This was set from
      // kDebugMode and never read, so every release build printed every log to
      // the platform console whatever the app asked for.
      if (cfg.logging.printToConsole) {
        CSxPrinter printer = CSxPrinter(this);
        printer.printToConsole(networkData: networkData);
      }

      // The on-device overlay reads this, not the table: rows are deleted from
      // SQLite as soon as they upload, so the overlay would empty out behind
      // you with a server configured.
      LogBuffer.i.add(this);

      // Live streaming sits above the sampling gate on purpose. Somebody is
      // watching this device right now, having deliberately paired with it —
      // showing them a sampled-down subset of what their app is doing would
      // make the feature useless exactly when it is being used.
      LiveSessionClient.i.publish(this);

      // Sampling gates the write and nothing above it. A sampled-out launch
      // still prints to the console and still fills the overlay, because those
      // are free and are what you are looking at while you work — what
      // sampling is there to reduce is rows on the server.
      //
      // System logs are exempt, for the same reason they are exempt from the
      // level gate. They are the SDK's own record of something it did to this
      // device — a dashboard edit to a local database — not app volume, and
      // there is no volume to control: they happen when a person presses Save.
      // Sampling one out means the row changed and nothing anywhere says who
      // changed it, which is the one question the record exists to answer.
      if (level != LogLevel.system && !CodeScout.instance.isSessionSampledIn) return;

      // Nothing to upload to means nothing to write. SQLite here is the sync
      // worker's queue, not a store anyone reads back: the on-device panel is
      // served by LogBuffer's capped ring, and no code path ever selects a row
      // for display. Rows are deleted when their batch uploads, so with no
      // uploader configured — no credentials, or no LogSyncBehavior — every
      // log an app ever writes stays on the user's phone for good.
      //
      // Local mode is a documented way to run rather than a degraded one, and
      // leaving out the sync block is the most common setup mistake there is,
      // so those two are exactly the configurations that must not fill a disk.
      if (!LogSyncWorker.i.canUpload) return;

      await LogPersistenceService.i.saveLogEntry(this);
    } catch (e, st) {
      log('CodeScout: Failed to process log entry: $e', stackTrace: st);
      if (rethrowErrors) rethrow;
    }
  }
}
