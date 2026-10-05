import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/network_detail.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/csx_interface/search_field.dart';
import 'package:flutter/material.dart';

/// How a call can be filtered. Four states the dashboard also distinguishes.
enum _CallFilter { all, failed, slow, pending }

/// Anything at or over this is worth calling out without reading the number.
const Duration kSlowCall = Duration(seconds: 1);

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  String _query = '';
  _CallFilter _filter = _CallFilter.all;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LogBuffer.i,
      builder: (context, _) {
        final all = LogBuffer.i.calls();
        final visible = all.where(_matches).toList(growable: false);

        // The bar is the dashboard's waterfall, one row wide: offset from the
        // first call, length by duration. Both need the window every call sits
        // in, which is the whole list rather than the filtered one, or the
        // bars would move every time a chip was tapped.
        final window = CallWindow.of(all);

        return Column(
          children: [
            if (all.isNotEmpty)
              CSxSearchField(
                hint: 'Search path',
                value: _query,
                onChanged: (q) => setState(() => _query = q),
              ),
            if (all.isNotEmpty)
              CSxChipRow(
                children: [
                  for (final f in _CallFilter.values)
                    CSxChip(
                      label: _label(f),
                      count: all.where((c) => _passesFilter(c, f)).length,
                      state: _filter == f ? ChipState.on : ChipState.neutral,
                      onTap: () => setState(() => _filter = f),
                    ),
                ],
              ),
            const Divider(height: 1, color: CSxColors.border),
            Expanded(
              child: visible.isEmpty
                  ? _empty(all.isEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => CallRow(call: visible[i], window: window),
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _matches(OverlayCall call) {
    if (!_passesFilter(call, _filter)) return false;
    if (_query.isEmpty) return true;
    return call.path.toLowerCase().contains(_query.toLowerCase());
  }

  static bool _passesFilter(OverlayCall call, _CallFilter filter) => switch (filter) {
        _CallFilter.all => true,
        _CallFilter.failed => call.failed,
        _CallFilter.slow => (call.duration ?? Duration.zero) >= kSlowCall,
        _CallFilter.pending => call.duration == null && !call.failed,
      };

  static String _label(_CallFilter f) => switch (f) {
        _CallFilter.all => 'All',
        _CallFilter.failed => 'Failed',
        _CallFilter.slow => 'Slow',
        _CallFilter.pending => 'Pending',
      };

  Widget _empty(bool nothingAtAll) {
    if (!nothingAtAll) {
      return CSxEmpty(
        title: 'Nothing matches',
        detail: 'No call matches that path and filter.',
        action: CSxButton(
          label: 'Clear filters',
          onPressed: () => setState(() {
            _query = '';
            _filter = _CallFilter.all;
          }),
        ),
      );
    }
    // Two different absences, and the developer needs to know which. Whether an
    // interceptor is even installed is answered on Info, so this points there
    // rather than guessing.
    return const CSxEmpty(
      mark: true,
      title: 'No network calls',
      detail: 'Calls are captured by a companion package, not by the core. '
          'Info lists which interceptors are installed.',
    );
  }
}

/// The span every bar is drawn against.
class CallWindow {
  const CallWindow(this.start, this.span);

  final DateTime? start;
  final Duration span;

  static CallWindow of(List<OverlayCall> calls) {
    DateTime? earliest;
    DateTime? latest;
    for (final call in calls) {
      final began = call.startedAt;
      if (began == null) continue;
      if (earliest == null || began.isBefore(earliest)) earliest = began;
      final ended = began.add(call.duration ?? Duration.zero);
      if (latest == null || ended.isAfter(latest)) latest = ended;
    }
    if (earliest == null || latest == null) return const CallWindow(null, Duration.zero);
    return CallWindow(earliest, latest.difference(earliest));
  }

  /// Where a call starts and ends as fractions of the window, clamped so a bar
  /// is always visible even when a call is far shorter than the whole span.
  (double, double) placeOf(OverlayCall call) {
    final began = call.startedAt;
    if (began == null || start == null || span.inMicroseconds <= 0) return (0, 1);
    final offset = began.difference(start!).inMicroseconds / span.inMicroseconds;
    final length = (call.duration ?? Duration.zero).inMicroseconds / span.inMicroseconds;
    final left = offset.clamp(0.0, 1.0);
    return (left, (length.clamp(0.0, 1.0 - left)).clamp(0.02, 1.0));
  }
}

/// A call's colour wherever it is drawn: failed, still in flight, or done.
Color callColour(OverlayCall call) {
  if (call.failed) return CSxColors.error;
  if (call.duration == null) return CSxColors.warning;
  return CSxColors.debug;
}

class CallRow extends StatelessWidget {
  const CallRow({super.key, required this.call, required this.window});

  final OverlayCall call;
  final CallWindow window;

  @override
  Widget build(BuildContext context) {
    final pending = call.duration == null && !call.failed;
    final colour = callColour(call);
    final (left, width) = window.placeOf(call);

    return InkWell(
      onTap: () => OverlayNavigator.of(context).push(NetworkDetail(call: call)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CSxColors.border)),
        ),
        child: Column(
          children: [
            Row(
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
                CSxBadge(text: call.status, colour: colour),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(
                    pending ? 'in flight' : _duration(call.duration),
                    style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
                  ),
                ),
                Expanded(
                  child: _Bar(left: left, width: width, colour: colour, pending: pending),
                ),
                const SizedBox(width: 8),
                Text(
                  // Only what is known. No byte count is recorded today, so
                  // this stays a dash rather than measuring a body that has
                  // already been redacted and truncated.
                  call.responseBytes == null ? '—' : _bytes(call.responseBytes!),
                  style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(Duration? d) {
    if (d == null) return '—';
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  static String _bytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class CallMethod extends StatelessWidget {
  const CallMethod(this.method, {super.key});

  final String method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: CSxColors.card,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: mono.copyWith(
          color: CSxColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.left,
    required this.width,
    required this.colour,
    required this.pending,
  });

  final double left;
  final double width;
  final Color colour;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = constraints.maxWidth;
        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: CSxColors.muted.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            children: [
              Positioned(
                left: left * track,
                // A pending call has no end, so its bar runs to the edge.
                width: pending ? (1 - left) * track : width * track,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: pending ? 0.55 : 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
