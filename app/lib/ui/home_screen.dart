/// The single-window home screen: a stepped, collapsible walkthrough plus a
/// floating activity-log button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/tts/sherpa_catalog.dart';
import '../logic/app_controller.dart';
import '../logic/theme_controller.dart';
import '../util/platform_env.dart';
import 'licenses.dart';
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
  final ThemeController theme;
  const HomeScreen({super.key, required this.controller, required this.theme});

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
          // Don't auto-collapse the step the user is on: let them advance via
          // the Continue button or by tapping a section header. The one
          // exception is jumping to the live progress when a run starts.
          final current = _c.currentStep;
          if (current != _lastStep) {
            _lastStep = current;
            if (current == 5) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _expanded = 5);
              });
            }
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
                        _Header(controller: _c, theme: widget.theme),
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
                style: TextStyle(
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

/// The wordmark header with a subtle amber glow and the app menu (top-right).
class _Header extends StatelessWidget {
  final AppController controller;
  final ThemeController theme;
  const _Header({required this.controller, required this.theme});

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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audiobook Studio', style: text.displaySmall),
              Text('Turn any EPUB into a chaptered audiobook',
                  style: text.bodySmall),
            ],
          ),
        ),
        _AppMenu(controller: controller, theme: theme),
      ],
    );
  }
}

/// Top-right overflow menu: theme toggle, voice management, and licenses.
class _AppMenu extends StatelessWidget {
  final AppController controller;
  final ThemeController theme;
  const _AppMenu({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded),
      position: PopupMenuPosition.under,
      onSelected: (v) {
        switch (v) {
          case 'theme':
            theme.toggle();
          case 'voices':
            _showManageVoices(context, controller);
          case 'licenses':
            showAppLicenses(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            title: Text(theme.isDark ? 'Light mode' : 'Dark mode'),
          ),
        ),
        const PopupMenuItem(
          value: 'voices',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.record_voice_over_rounded),
            title: Text('Manage voices…'),
          ),
        ),
        const PopupMenuItem(
          value: 'licenses',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.gavel_rounded),
            title: Text('Licenses'),
          ),
        ),
      ],
    );
  }
}

/// Dialog listing installed local voices with a one-tap remove (uninstall).
void _showManageVoices(BuildContext context, AppController controller) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Installed voices'),
      content: SizedBox(
        width: 420,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final installed = controller.installedModels;
            if (installed.isEmpty) {
              return const Text(
                  'No offline voices installed. Install one from the toolkit step.');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in installed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.label),
                    subtitle: Text(
                        '${m.languages.map((l) => l.toUpperCase()).join('/')} · ~${m.sizeMb} MB'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _confirmRemove(context, controller, m),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _confirmRemove(
    BuildContext context, AppController controller, SherpaModel model) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${model.label}?'),
      content: Text('Deletes ~${model.sizeMb} MB. You can re-download it later.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove')),
      ],
    ),
  );
  if (ok == true) await controller.uninstallModel(model);
}
