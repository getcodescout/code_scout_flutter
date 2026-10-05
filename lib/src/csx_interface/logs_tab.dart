import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/log_detail.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/csx_interface/search_field.dart';
import 'package:flutter/material.dart';

/// The levels worth offering as toggles. `off` is a threshold that would hide
/// everything, and `all` is not a level anything is logged at.
const List<LogLevel> kFilterLevels = [
  LogLevel.fatal,
  LogLevel.error,
  LogLevel.warning,
  LogLevel.info,
  LogLevel.debug,
  LogLevel.verbose,
];

class LogsTab extends StatefulWidget {
  const LogsTab({super.key});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  /// Independent toggles, as on the dashboard, rather than the single minimum
  /// threshold that shipped. A threshold cannot express "errors and info, not
  /// debug", and it taught a second mental model for one product.
  final Set<LogLevel> _hidden = {};

  /// Tri-state per tag: neutral, only this, hide this.
  final Set<String> _included = {};
  final Set<String> _excluded = {};

  String _query = '';

  /// Follow keeps the newest log in view. Searching turns it off, because you
  /// are reading rather than watching.
  bool _follow = true;

  bool get _filtered =>
      _query.isNotEmpty || _hidden.isNotEmpty || _included.isNotEmpty || _excluded.isNotEmpty;

  void _clearFilters() => setState(() {
        _hidden.clear();
        _included.clear();
        _excluded.clear();
        _query = '';
      });

  void _toggleLevel(LogLevel level) {
    setState(() {
      if (!_hidden.remove(level)) _hidden.add(level);
    });
  }

  /// The same chips, in a sheet, for a viewport too short to stack them.
  Future<void> _openFilters(
    BuildContext context,
    Map<LogLevel, int> counts,
    List<String> tags,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CSxColors.background,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          void refresh(VoidCallback change) {
            change();
            // Both, because the sheet and the list behind it each hold their
            // own element tree and neither rebuilds the other.
            setSheet(() {});
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CSxSectionHeader(title: 'Levels'),
                _LevelRow(
                  counts: counts,
                  hidden: _hidden,
                  onTap: (l) => refresh(() => _toggleLevel(l)),
                ),
                if (tags.isNotEmpty) ...[
                  const CSxSectionHeader(title: 'Tags'),
                  _TagRow(
                    tags: tags,
                    included: _included,
                    excluded: _excluded,
                    onTap: (t) => refresh(() => _cycleTag(t)),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CSxButton(
                    label: 'Done',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _cycleTag(String tag) {
    setState(() {
      if (_included.remove(tag)) {
        _excluded.add(tag);
      } else if (!_excluded.remove(tag)) {
        _included.add(tag);
      }
    });
  }

  bool _matches(LogEntry entry) {
    if (_hidden.contains(entry.level)) return false;

    final tags = entry.tags ?? const <String>{};
    if (_excluded.isNotEmpty && tags.any(_excluded.contains)) return false;
    // Included tags are an OR, which is what a row of chips reads like: tap
    // two and you expect both, not only the logs carrying both at once.
    if (_included.isNotEmpty && !tags.any(_included.contains)) return false;

    if (_query.isNotEmpty) {
      final needle = _query.toLowerCase();
      final haystack = [
        entry.message,
        entry.error?.toString() ?? '',
        tags.join(' '),
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle) && !_startsRequestId(entry.requestId, needle)) {
        return false;
      }
    }
    return true;
  }

  /// An id pasted from the dashboard or a bug report finds the call's phases
  /// and the app's logs about it together. Matched from the start and on at
  /// least eight characters, the first block of a UUID, because a short query
  /// such as a status code turns up somewhere inside unrelated random ids.
  static bool _startsRequestId(String? id, String needle) =>
      id != null && needle.length >= 8 && id.toLowerCase().startsWith(needle);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LogBuffer.i,
      builder: (context, _) {
        final all = LogBuffer.i.entries;
        final visible = all.where(_matches).toList(growable: false);
        final counts = <LogLevel, int>{};
        for (final entry in all) {
          counts[entry.level] = (counts[entry.level] ?? 0) + 1;
        }

        final tags = LogBuffer.i.tags();

        return LayoutBuilder(
          builder: (context, constraints) {
            // Two chip rows plus a search bar is 148px of chrome above the
            // list. On a landscape phone that leaves about two rows, which is
            // not a log viewer, so under a short viewport the filters collapse
            // into one control that opens them in a sheet.
            final compact = constraints.maxHeight < 320;
            final active = _hidden.length + _included.length + _excluded.length;

            return Column(
              children: [
                CSxSearchField(
                  hint: 'Search messages',
                  value: _query,
                  // Searching pauses follow automatically.
                  onChanged: (q) => setState(() {
                    _query = q;
                    if (q.isNotEmpty) _follow = false;
                  }),
                  actions: [
                    if (compact)
                      CSxIconButton(
                        icon: Icons.filter_alt_outlined,
                        tooltip: active == 0 ? 'Filters' : 'Filters ($active)',
                        active: active > 0,
                        onPressed: () => _openFilters(context, counts, tags),
                      ),
                    CSxIconButton(
                      icon: _follow ? Icons.vertical_align_bottom : Icons.pause,
                      tooltip: _follow ? 'Following' : 'Paused',
                      active: _follow,
                      onPressed: () => setState(() => _follow = !_follow),
                    ),
                    CSxIconButton(
                      icon: Icons.backspace_outlined,
                      tooltip: 'Clear',
                      onPressed: all.isEmpty ? null : LogBuffer.i.clear,
                    ),
                  ],
                ),
                if (!compact) ...[
                  _LevelRow(counts: counts, hidden: _hidden, onTap: _toggleLevel),
                  _TagRow(
                    tags: tags,
                    included: _included,
                    excluded: _excluded,
                    onTap: _cycleTag,
                  ),
                ],
                const Divider(height: 1, color: CSxColors.border),
                Expanded(
                  child: visible.isEmpty
                      ? _empty(all.length)
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          // The buffer is newest first, so following the newest
                          // log means staying at the top rather than pinning to
                          // the bottom. Paused simply stops rebuilding.
                          itemCount: visible.length,
                          itemBuilder: (context, i) => LogRow(entry: visible[i]),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Two empty states, never one. "Nothing logged yet" is false the moment a
  /// filter is what emptied the list, and it points a developer at their own
  /// logging calls instead of at the control they set.
  Widget _empty(int total) {
    if (_filtered) {
      return CSxEmpty(
        title: 'Nothing matches these filters',
        detail: '$total ${total == 1 ? 'log' : 'logs'} this launch.',
        action: CSxButton(label: 'Clear filters', onPressed: _clearFilters),
      );
    }
    return const CSxEmpty(
      mark: true,
      title: 'Nothing logged yet',
      detail: 'Logs from this launch appear here as they happen, '
          'whether or not a server is configured.',
    );
  }

}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.counts, required this.hidden, required this.onTap});

  final Map<LogLevel, int> counts;
  final Set<LogLevel> hidden;
  final ValueChanged<LogLevel> onTap;

  @override
  Widget build(BuildContext context) {
    return CSxChipRow(
      children: [
        for (final level in kFilterLevels)
          CSxChip(
            label: level.name[0].toUpperCase() + level.name.substring(1),
            // Counts from this launch, so an empty list explains itself: the
            // level is off, not the app quiet.
            count: counts[level] ?? 0,
            dot: levelColor(level.name),
            state: hidden.contains(level) ? ChipState.off : ChipState.on,
            onTap: () => onTap(level),
          ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tags,
    required this.included,
    required this.excluded,
    required this.onTap,
  });

  final List<String> tags;
  final Set<String> included;
  final Set<String> excluded;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return CSxChipRow(
      children: [
        for (final tag in tags)
          CSxChip(
            label: tag,
            state: included.contains(tag)
                ? ChipState.include
                : excluded.contains(tag)
                    ? ChipState.exclude
                    : ChipState.neutral,
            onTap: () => onTap(tag),
          ),
      ],
    );
  }
}

/// One log. Two lines: the level and the time, then the message.
class LogRow extends StatelessWidget {
  const LogRow({
    super.key,
    required this.entry,
    this.showError = false,
    this.divider = true,
  });

  final LogEntry entry;

  /// A third line with the error, for a list short enough that the reason is
  /// worth reading without opening the log.
  final bool showError;

  /// Off for the last row inside a bordered card, whose own edge closes it.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colour = levelColor(entry.level.name);
    final isError = entry.level.value >= LogLevel.error.value;
    final error = showError ? entry.error?.toString() : null;

    return InkWell(
      onTap: () => OverlayNavigator.of(context).push(LogDetail(entry: entry)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: CSxColors.border)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CSxBadge(text: entry.level.name, colour: colour),
                const SizedBox(width: 8),
                Text(
                  formatClock(entry.timestamp),
                  // --muted, never --faint: the shipped #6E7681 is 4.08:1 at
                  // this size, and every row carries one.
                  style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              entry.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isError ? CSxColors.error : CSxColors.white,
                fontSize: 12.5,
              ),
            ),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatClock(DateTime? at) {
  if (at == null) return '--:--:--';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
