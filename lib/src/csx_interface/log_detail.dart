import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/log_clipboard.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/network_detail.dart';
import 'package:code_scout/src/csx_interface/network_tab.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:flutter/material.dart';

/// One log, opened.
///
/// What shipped before printed `metadata.toString()`, a raw Dart map on one
/// unwrapped line, and the stack trace as a single joined string. Both are
/// structured here, and every section copies on its own.
class LogDetail extends StatelessWidget {
  const LogDetail({super.key, required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colour = levelColor(entry.level.name);
    final metadata = entry.metadata;
    final frames = entry.stackCallDetails ?? const <StackCallDetails>[];
    final tags = entry.tags ?? const <String>{};

    return Column(
      children: [
        PushedHeader(
          title: _title(entry.level.name),
          actions: [
            CSxIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Copy everything',
              onPressed: () => copyAndTell(
                context,
                formatLogForClipboard(
                  entry,
                  session: CodeScout.instance.currentSession,
                  sessionId: CodeScout.instance.currentSessionId,
                ),
                _title(entry.level.name),
              ),
            ),
            CSxIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CSxBadge(text: entry.level.name, colour: colour),
                        const SizedBox(width: 8),
                        Text(
                          _stamp(entry.timestamp),
                          style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      entry.message,
                      style: TextStyle(
                        color: entry.level.value >= LogLevel.error.value
                            ? CSxColors.error
                            : CSxColors.white,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.error != null) ...[
                CSxSectionHeader(
                  title: 'Error',
                  trailing: CSxSmallButton(
                    label: 'Copy',
                    onTap: () => copyAndTell(context, entry.error.toString(), 'Error'),
                  ),
                ),
                CSxCode(text: entry.error.toString()),
              ],
              // A network phase is its own call. This is for a log the app
              // wrote about one.
              if (!entry.isNetworkCall && entry.requestId != null)
                ..._callSection(context, entry.requestId!),
              if (frames.isNotEmpty) ...[
                CSxSectionHeader(
                  title: 'Stack trace',
                  trailing: CSxSmallButton(
                    label: 'Copy',
                    onTap: () => copyAndTell(
                      context,
                      (entry.formattedStackTrace ?? const []).join('\n'),
                      'Stack trace',
                    ),
                  ),
                ),
                _Frames(frames: frames),
              ],
              if (metadata != null && metadata.isNotEmpty) ...[
                CSxSectionHeader(
                  title: 'Metadata',
                  trailing: CSxSmallButton(
                    label: isFlatMap(metadata) ? 'Copy' : 'Copy JSON',
                    onTap: () => copyAndTell(context, prettyJson(metadata), 'Metadata'),
                  ),
                ),
                // Rows when every value is a scalar, indented JSON otherwise.
                if (isFlatMap(metadata))
                  CSxKeyValue(
                    rows: [
                      for (final e in metadata.entries)
                        (e.key, _scalar(e.value), _scalarColour(e.value)),
                    ],
                  )
                else
                  CSxCode(text: prettyJson(metadata)),
              ],
              if (tags.isNotEmpty) ...[
                const CSxSectionHeader(title: 'Tags'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in tags)
                        CSxChip(label: tag, state: ChipState.neutral, onTap: () {}),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The call this log is about, one tap from the body it describes.
  ///
  /// Found by id among the calls in the buffer. When it is not there, the id
  /// is shown in full with a Copy: at the default minimumLevel of info a 200's
  /// phases are debug logs and never reach the buffer, and past that the
  /// buffer drops its oldest first while the app's log is written after its
  /// call, so the log can outlive it.
  List<Widget> _callSection(BuildContext context, String requestId) {
    final call = LogBuffer.i.callById(requestId);
    if (call != null) {
      return [
        const CSxSectionHeader(title: 'Call'),
        _CallLink(call: call),
      ];
    }
    // A launch that sampling left out uploads nothing, so the dashboard has
    // neither this log nor its call.
    final uploaded = LogSyncWorker.i.canUpload && CodeScout.instance.isSessionSampledIn;
    return [
      CSxSectionHeader(
        title: 'Call',
        trailing: CSxSmallButton(
          label: 'Copy',
          onTap: () => copyAndTell(context, requestId, 'Request id'),
        ),
      ),
      CSxKeyValue(rows: [('request', requestId, null)]),
      CSxHint(
        child: Text(
          'This call is not in the panel. The panel keeps the newest '
          '${LogBuffer.maxEntries} logs of this launch, and network logs are '
          'written at debug, which an app at minimumLevel info never keeps.'
          '${uploaded ? ' Search request: and this id on the dashboard to see what was uploaded.' : ''}',
        ),
      ),
    ];
  }

  static String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _scalar(Object? v) => v == null
      ? 'null'
      : v is String
          ? '"$v"'
          : '$v';

  static Color? _scalarColour(Object? v) => v == null
      ? CSxColors.muted
      : v is num
          ? CSxColors.info
          : v is String
              ? CSxColors.debug
              : null;

  static String _stamp(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$ms';
  }
}

/// One row that opens the call: method, path and status. The whole row is
/// the target, so it takes the full touch height.
class _CallLink extends StatelessWidget {
  const _CallLink({required this.call});

  final OverlayCall call;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: CSxColors.card,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: CSxColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => OverlayNavigator.of(context).push(
            NetworkDetail(call: call, initialPane: NetworkPane.response),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: GlobalVars.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                CallMethod(call.method),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    call.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(color: CSxColors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 7),
                CSxBadge(text: call.status, colour: callColour(call)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: CSxColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frames, with the app's own tinted and listed first.
///
/// The one you want is never the top one: four frames in five in a Flutter
/// trace are the framework. Tinting is not the only cue, since the app frames
/// are also the ones with a path you recognise.
class _Frames extends StatelessWidget {
  const _Frames({required this.frames});

  final List<StackCallDetails> frames;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CSxColors.card,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < frames.length; i++) _frame(frames[i], last: i == frames.length - 1),
        ],
      ),
    );
  }

  Widget _frame(StackCallDetails frame, {required bool last}) {
    final path = frame.path ?? '';
    // Paths arrive with `package:` already stripped by the parser, and a
    // `dart:` frame never matches its regex, so Flutter's own prefix is the
    // only one left to recognise.
    final isApp = path.isNotEmpty && !path.startsWith('flutter/');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isApp ? CSxColors.primary.withValues(alpha: 0.07) : null,
        border: last ? null : const Border(bottom: BorderSide(color: CSxColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            frame.method ?? '?',
            style: mono.copyWith(
              color: CSxColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (path.isNotEmpty)
            Text(
              '$path:${frame.line ?? 0}:${frame.column ?? 0}',
              style: mono.copyWith(color: CSxColors.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
