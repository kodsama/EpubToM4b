/// The single-window home screen composing the stepped conversion flow.
library;

import 'package:flutter/material.dart';

import '../logic/app_controller.dart';
import 'theme.dart';
import 'widgets/convert_bar.dart';
import 'widgets/dependency_card.dart';
import 'widgets/file_picker_card.dart';
import 'widgets/log_console.dart';
import 'widgets/options_panel.dart';
import 'widgets/progress_view.dart';
import 'widgets/section_card.dart';

/// Top-level screen. Rebuilds reactively from [AppController] and lays the
/// steps out in a centered, scrollable column.
class HomeScreen extends StatelessWidget {
  final AppController controller;
  const HomeScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 36),
                children: [
                  const _Header(),
                  const SizedBox(height: 28),
                  DependencyCard(controller: controller),
                  const SizedBox(height: 16),
                  FilePickerCard(controller: controller),
                  const SizedBox(height: 16),
                  OptionsPanel(controller: controller),
                  const SizedBox(height: 16),
                  ConvertBar(controller: controller),
                  const SizedBox(height: 16),
                  ProgressView(progress: controller.progress),
                  const SizedBox(height: 16),
                  SectionCard(
                    step: 6,
                    title: 'Activity log',
                    child: LogConsole(log: controller.log),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTokens.amberBright, AppTokens.amber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTokens.amber.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_stories_rounded,
                  color: AppTokens.ink, size: 26),
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
        ),
      ],
    );
  }
}
