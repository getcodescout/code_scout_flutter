import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/logs_tab.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/network_tab.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:flutter/material.dart';

/// One network call: Request, Response and Timing.
///
/// What shipped before was three boxes of `metadata.toString()`. Headers are
/// rows here and bodies are JSON, and both copy on their own.
class NetworkDetail extends StatefulWidget {
  const NetworkDetail({super.key, required this.call, this.initialPane = NetworkPane.request});

  final OverlayCall call;

  /// Response when arriving from a log about this call, since the body that
  /// log is about is there.
  final NetworkPane initialPane;

  @override
  State<NetworkDetail> createState() => _NetworkDetailState();
}

enum NetworkPane { request, response, timing }

class _NetworkDetailState extends State<NetworkDetail> {
  /// The pane each open screen was left on. Opening a linked log replaces
  /// this screen on the sheet's stack, so coming back builds a new state, and
  /// without this it would reset to Request, away from the section the log
  /// was opened from. Keyed weakly on the widget, which the stack holds.
  static final Expando<NetworkPane> _leftOn = Expando();

  late NetworkPane _pane = _leftOn[widget] ?? widget.initialPane;

  void _show(NetworkPane pane) {
    _leftOn[widget] = pane;
    setState(() => _pane = pane);
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final colour = callColour(call);

    return Column(
      children: [
        PushedHeader(
          title: '${call.method}  ${call.status}',
          actions: [
            CSxIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Copy call',
              onPressed: () => copyAndTell(context, _asText(call), 'Call'),
            ),
            CSxIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              CSxBadge(text: call.status, colour: colour),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  _url(call) ?? call.path,
                  style: mono.copyWith(color: CSxColors.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CSxColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final pane in NetworkPane.values)
                InkWell(
                  onTap: () => _show(pane),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _pane == pane ? CSxColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      switch (pane) {
                        NetworkPane.request => 'Request',
                        NetworkPane.response => 'Response',
                        NetworkPane.timing => 'Timing',
                      },
                      style: TextStyle(
                        color: _pane == pane ? CSxColors.white : CSxColors.muted,
                        fontSize: 13,
                        fontWeight: _pane == pane ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: switch (_pane) {
              NetworkPane.request => _phase(context, call, NetworkCallPhase.request),
              NetworkPane.response => [
                  ..._linked(call),
                  ..._responsePane(context, call),
                ],
              NetworkPane.timing => _timing(context, call),
            },
          ),
        ),
      ],
    );
  }

  /// The app's own logs about this call, above the body they are about, so a
  /// parse failure reads directly over the JSON that caused it. Each opens
  /// the log.
  List<Widget> _linked(OverlayCall call) {
    if (call.logs.isEmpty) return const [];
    return [
      const CSxSectionHeader(title: 'Logged by the app'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // Material, not a decorated box: the rows are InkWells and paint on
        // the nearest Material.
        child: Material(
          color: CSxColors.card,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: CSxColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < call.logs.length; i++)
                LogRow(
                  entry: call.logs[i],
                  showError: true,
                  divider: i != call.logs.length - 1,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _responsePane(BuildContext context, OverlayCall call) {
    if (call.hasError && !call.hasResponse) {
      final meta = call.phase(NetworkCallPhase.error)?.metadata ?? const {};
      return [
        const CSxSectionHeader(title: 'Error'),
        CSxCode(text: prettyJson(meta)),
        const CSxHint(
          child: Text(
            'The call failed before a response arrived, so there is nothing to show here. '
            'A transport failure has no status code.',
          ),
        ),
      ];
    }
    return _phase(context, call, NetworkCallPhase.response);
  }

  List<Widget> _phase(BuildContext context, OverlayCall call, NetworkCallPhase phase) {
    final meta = call.phase(phase)?.metadata;
    if (meta == null || meta.isEmpty) {
      return [
        // The buffer drops its oldest first, so a response cannot fall off
        // before its request. With the request here, it never reached the
        // buffer.
        if (phase == NetworkCallPhase.response && call.hasRequest && !call.hasResponse)
          const CSxEmpty(
            title: 'No response recorded',
            detail: 'The call may still be running. The SDK holds a request for two '
                'minutes, and a response that arrives after that can be dropped.',
          )
        else
          CSxEmpty(
            title: 'Nothing recorded',
            detail: 'This call has no ${phase.name} phase in the buffer. '
                'A phase can fall off the back once the buffer fills.',
          ),
      ];
    }

    // The request phase nests its own map inside a response or error phase, so
    // unwrap it before looking for headers and a body.
    final source = phase == NetworkCallPhase.request && meta['request'] is Map
        ? Map<String, dynamic>.from(meta['request'] as Map)
        : meta;

    final headers = source['headers'];
    final body = source['body'] ?? source['data'];

    return [
      if (headers is Map && headers.isNotEmpty) ...[
        CSxSectionHeader(
          title: 'Headers',
          trailing: CSxSmallButton(
            label: 'Copy',
            onTap: () => copyAndTell(context, prettyJson(headers), 'Headers'),
          ),
        ),
        CSxKeyValue(
          rows: [
            for (final e in headers.entries)
              (
                '${e.key}',
                '${e.value}',
                // [redacted] is a contract: the SDK writes that exact string
                // and it renders as a marker, never as though it were the
                // header's value.
                '${e.value}' == Redactor.placeholder ? CSxColors.warning : null,
              ),
          ],
        ),
      ],
      if (body != null) ...[
        CSxSectionHeader(
          title: 'Body',
          trailing: CSxSmallButton(
            label: 'Copy',
            onTap: () => copyAndTell(context, prettyJson(body), 'Body'),
          ),
        ),
        CSxCode(text: prettyJson(body)),
      ],
      if ((headers is! Map || headers.isEmpty) && body == null)
        CSxCode(text: prettyJson(source)),
    ];
  }

  List<Widget> _timing(BuildContext context, OverlayCall call) {
    final began = call.startedAt;
    final duration = call.duration;

    return [
      const CSxSectionHeader(title: 'This call'),
      CSxKeyValue(
        rows: [
          ('started', began == null ? '—' : _stamp(began), null),
          (
            'finished',
            began == null || duration == null ? '—' : _stamp(began.add(duration)),
            null
          ),
          (
            'duration',
            duration == null ? 'still running' : '${duration.inMilliseconds} ms',
            duration == null ? CSxColors.warning : CSxColors.info
          ),
          (
            'response',
            call.responseBytes == null ? 'not recorded' : '${call.responseBytes} bytes',
            call.responseBytes == null ? CSxColors.muted : CSxColors.info
          ),
        ],
      ),
      const CSxHint(
        child: Text(
          'The SDK cannot see DNS, TLS or time to first byte. An interceptor only sees the call '
          'start and the call end, so a five segment waterfall would be a chart of numbers '
          'nothing measured.',
        ),
      ),
    ];
  }

  static String? _url(OverlayCall call) {
    final meta = call.phase(NetworkCallPhase.request)?.metadata;
    final direct = meta?['url'];
    if (direct is String) return direct;
    for (final entry in call.phases) {
      final nested = entry.metadata?['request'];
      if (nested is Map && nested['url'] is String) return nested['url'] as String;
    }
    return null;
  }

  static String _asText(OverlayCall call) {
    final out = StringBuffer()
      ..writeln('${call.method} ${_url(call) ?? call.path}')
      ..writeln('status ${call.status}');
    if (call.duration != null) out.writeln('duration ${call.duration!.inMilliseconds} ms');
    for (final phase in NetworkCallPhase.values) {
      final entry = call.phase(phase);
      if (entry != null) {
        out
          ..writeln()
          ..writeln('[${phase.name}]')
          ..writeln(prettyJson(entry.metadata));
      }
      // Where the Response pane lists them: above the response or error.
      if (phase == NetworkCallPhase.request) _linkedAsText(out, call.logs);
    }
    return out.toString().trimRight();
  }

  /// Each log as its row shows it: level, time, message and error.
  static void _linkedAsText(StringBuffer out, List<LogEntry> logs) {
    if (logs.isEmpty) return;
    out
      ..writeln()
      ..writeln('[logged by the app]');
    for (var i = 0; i < logs.length; i++) {
      final entry = logs[i];
      final at = entry.timestamp;
      final error = entry.error?.toString().trimRight();
      if (i > 0) out.writeln();
      out
        ..writeln(at == null ? entry.level.name : '${entry.level.name} ${_stamp(at)}')
        ..writeln(entry.message);
      if (error != null && error.isNotEmpty) out.writeln(error);
    }
  }

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$ms';
  }
}
