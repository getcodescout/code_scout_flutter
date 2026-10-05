import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/log_clipboard.dart';
import 'package:code_scout/src/csx_interface/log_detail.dart';
import 'package:code_scout/src/csx_interface/logs_tab.dart' show formatClock;
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/csx_interface/search_field.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:flutter/material.dart';

/// What broke, which is the reason the overlay gets opened.
///
/// Flat and counted by exact message and error text, not by the server's
/// fingerprint. `internal/domain/fingerprint.go` blanks the varying parts of a
/// message so two "User N not found" are one problem, and porting that here
/// would put one algorithm in two repos to drift apart. On device there are at
/// most 500 logs from one launch, and exact-message counting catches the case
/// that matters, which is the same failure firing over and over.
class ErrorsTab extends StatefulWidget {
  const ErrorsTab({super.key});

  @override
  State<ErrorsTab> createState() => _ErrorsTabState();
}

class _ErrorsTabState extends State<ErrorsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LogBuffer.i,
      builder: (context, _) {
        final all = LogBuffer.i.errorGroups();
        final needle = _query.toLowerCase();
        final groups = needle.isEmpty
            ? all
            : all.where((g) => g.message.toLowerCase().contains(needle)).toList();

        return Column(
          children: [
            if (all.isNotEmpty)
              CSxSearchField(
                hint: 'Search errors',
                value: _query,
                onChanged: (q) => setState(() => _query = q),
                actions: [
                  CSxIconButton(
                    icon: Icons.copy_all_outlined,
                    tooltip: 'Copy all',
                    onPressed: () => copyAndTell(
                      context,
                      all.map((g) => formatLogForClipboard(
                            g.latest,
                            session: CodeScout.instance.currentSession,
                            sessionId: CodeScout.instance.currentSessionId,
                          )).join('\n\n---\n\n'),
                      '${all.length} ${all.length == 1 ? 'error' : 'errors'}',
                    ),
                  ),
                ],
              ),
            Expanded(
              child: groups.isEmpty
                  ? _empty(all.isEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: groups.length,
                      itemBuilder: (context, i) => _ErrorRow(group: groups[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(bool nothingAtAll) {
    if (!nothingAtAll) {
      return CSxEmpty(
        title: 'Nothing matches',
        detail: 'No error message contains that.',
        action: CSxButton(label: 'Clear search', onPressed: () => setState(() => _query = '')),
      );
    }
    // The one empty state that is good news, and the one a healthy app shows
    // permanently. It must not read like "nothing logged yet", so it says the
    // log count too.
    final total = LogBuffer.i.length;
    return CSxEmpty(
      mark: true,
      title: 'No errors this launch',
      detail: '$total ${total == 1 ? 'log' : 'logs'} and nothing at error or above. '
          'The floating button counts them while you are elsewhere in the app.',
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.group});

  final ErrorGroup group;

  @override
  Widget build(BuildContext context) {
    final colour = levelColor(group.level.name);
    final frame = group.appFrame;
    final subtitle = group.isNetwork ? _networkLine(group.latest) : _frameLine(frame);

    return InkWell(
      onTap: () => OverlayNavigator.of(context).push(LogDetail(entry: group.latest)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CSxColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CSxBadge(text: group.level.name, colour: colour),
                const SizedBox(width: 8),
                Text('×${group.count}',
                    style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5)),
                const Spacer(),
                Text(formatClock(group.latest.timestamp),
                    style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              group.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CSxColors.error, fontSize: 12.5),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _frameLine(StackCallDetails? frame) {
    if (frame == null) return null;
    final path = frame.path ?? '';
    final file = path.contains('/') ? path.split('/').last : path;
    return '${frame.method ?? '?'} · $file:${frame.line ?? 0}';
  }

  /// A network failure's message is the literal string "Network Error" for
  /// every one the SDK reports, so the call is what identifies it.
  static String? _networkLine(LogEntry entry) {
    final meta = entry.metadata ?? const {};
    final nested = meta['request'];
    final request = nested is Map ? nested : meta;
    final method = request['method'] as String?;
    final url = request['url'] as String?;
    final status = meta['status_code'];
    final parts = <String>[
      ?method,
      if (url != null) _path(url),
      if (status != null) '$status',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _path(String url) {
    final scheme = url.indexOf('://');
    if (scheme < 0) return url;
    final rest = url.substring(scheme + 3);
    final slash = rest.indexOf('/');
    return slash < 0 ? '/' : rest.substring(slash);
  }
}
