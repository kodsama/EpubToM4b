/// A live, monospaced log console fed by the [LogController] stream.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/log_controller.dart';
import '../theme.dart';

/// Streams log lines into a scrolling, copyable console. Auto-scrolls to the
/// newest line and color-codes by severity.
class LogConsole extends StatefulWidget {
  final LogController log;
  const LogConsole({super.key, required this.log});

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final ScrollController _scroll = ScrollController();
  late final List<LogLine> _lines = [...widget.log.history];

  @override
  void initState() {
    super.initState();
    widget.log.lines.listen((line) {
      if (!mounted) return;
      setState(() => _lines.add(line));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(LogLevel l) => switch (l) {
        LogLevel.error => AppTokens.rust,
        LogLevel.warn => AppTokens.amberBright,
        LogLevel.info => AppTokens.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.terminal_rounded, size: 16, color: AppTokens.muted),
            const SizedBox(width: 8),
            Text('Logs', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Copy logs',
              iconSize: 18,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.log.dump())),
              icon: Icon(Icons.copy_rounded, color: AppTokens.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF120E0A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTokens.line),
          ),
          child: _lines.isEmpty
              ? Text('No activity yet.',
                  style: TextStyle(color: AppTokens.muted, fontFamily: 'monospace'))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _lines.length,
                  itemBuilder: (context, i) {
                    final l = _lines[i];
                    return Text(
                      l.format(),
                      style: TextStyle(
                        color: _color(l.level),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
