/// The single-window home screen: a stepped, collapsible walkthrough plus a
/// floating activity-log button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/app_controller.dart';
import '../util/platform_env.dart';
import 'theme.dart';
import 'widgets/convert_bar.dart';
import 'widgets/dependency_card.dart';
import 'widgets/file_picker_card.dart';
import 'widgets/log_console.dart';
import 'widgets/options_panel.dart';
import 'widgets/progress_view.dart';

/// Top-level screen. Shows the five steps as an accordion (one expanded at a
/// time, auto-advancing as the workflow progresses) and a bottom-right log FAB.
class HomeScreen extends StatefulWidget {
  final AppController controller;
  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get _c => widget.controller;

  /// Currently expanded step (0 = none).
  late int _expanded = _c.currentStep;
  int _lastStep = 0;

  bool _logOpen = false;
  int _unread = 0;
  StreamSubscription? _logSub;

  @override
  void initState() {
    super.initState();
    _lastStep = _c.currentStep;
    _logSub = _c.log.lines.listen((_) {
      if (!_logOpen && mounted) setState(() => _unread++);
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }

  void _toggle(int step) =>
      setState(() => _expanded = _expanded == step ? 0 : step);

  /// Opens the platform share sheet for the finished audiobook (mobile only,
  /// where output lives in app-scoped storage).
  Future<void> _shareOutput() async {
    final path = _c.options?.outputPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: _c.book?.title ?? 'Audiobook'),
    );
  }

  void _toggleLog() => setState(() {
        _logOpen = !_logOpen;
        if (_logOpen) _unread = 0;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          // Auto-advance the open step as the workflow progresses.
          final current = _c.currentStep;
          if (current != _lastStep) {
            _lastStep = current;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _expanded = current);
            });
          }

          // A step = its card plus, when expanded, a Continue button that
          // advances to the next step (enabled once the step is satisfied).
          Widget step(
            int n,
            Widget Function(bool expanded, VoidCallback toggle) build, {
            bool canContinue = false,
            String continueLabel = 'Continue',
          }) {
            // Steps 1–3 get a Continue button; step 4's Convert action advances
            // to step 5 itself, and step 5 is terminal.
            final showContinue = _expanded == n && n < 4;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  build(_expanded == n, () => _toggle(n)),
                  if (showContinue)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed:
                              canContinue ? () => setState(() => _expanded = n + 1) : null,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: Text(continueLabel),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 96),
                      children: [
                        const _Header(),
                        const SizedBox(height: 24),
                        step(
                          1,
                          (e, t) => DependencyCard(
                              controller: _c,
                              expanded: e,
                              onToggle: t,
                              done: current > 1),
                          canContinue: _c.coreToolsReady,
                        ),
                        step(
                          2,
                          (e, t) => FilePickerCard(
                              controller: _c,
                              expanded: e,
                              onToggle: t,
                              done: current > 2),
                          canContinue: _c.book != null,
                        ),
                        step(
                          3,
                          (e, t) => OptionsPanel(
                              controller: _c,
                              expanded: e,
                              onToggle: t,
                              done: current > 3),
                          canContinue: _c.canConvert,
                          continueLabel: 'Continue to convert',
                        ),
                        step(
                            4,
                            (e, t) => ConvertBar(
                                controller: _c,
                                expanded: e,
                                onToggle: t,
                                done: current > 4)),
                        step(
                            5,
                            (e, t) => ProgressView(
                                progress: _c.progress,
                                expanded: e,
                                onToggle: t,
                                onShare: isMobilePlatform ? _shareOutput : null)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_logOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _toggleLog,
                    child: Container(color: Colors.black.withValues(alpha: 0.35)),
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom: 88,
                  child: _LogPanel(controller: _c),
                ),
              ],
              Positioned(
                right: 24,
                bottom: 24,
                child: _LogFab(unread: _unread, open: _logOpen, onTap: _toggleLog),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The bottom-right activity-log button with an unread badge.
class _LogFab extends StatelessWidget {
  final int unread;
  final bool open;
  final VoidCallback onTap;
  const _LogFab({required this.unread, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton(
          onPressed: onTap,
          backgroundColor: open ? AppTokens.surfaceHigh : AppTokens.amber,
          foregroundColor: open ? AppTokens.cream : AppTokens.ink,
          child: Icon(open ? Icons.close_rounded : Icons.terminal_rounded),
        ),
        if (unread > 0 && !open)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTokens.rust,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTokens.ink, width: 2),
              ),
              constraints: const BoxConstraints(minWidth: 20),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTokens.cream,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

/// The floating log panel shown when the FAB is open.
class _LogPanel extends StatelessWidget {
  final AppController controller;
  const _LogPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: AppTokens.line),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 10)),
          ],
        ),
        child: LogConsole(log: controller.log),
      ),
    );
  }
}

/// The wordmark header with a subtle amber glow.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTokens.amber.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset('assets/logo.png', width: 52, height: 52),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audiobook Studio', style: text.displaySmall),
            Text('Turn any EPUB into a chaptered audiobook',
                style: text.bodySmall),
          ],
        ),
      ],
    );
  }
}
