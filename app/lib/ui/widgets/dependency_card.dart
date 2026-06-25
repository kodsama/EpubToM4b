/// Step 1: verify every library the engines need, with one-click install.
library;

import 'package:flutter/material.dart';

import '../../data/tts/sherpa_catalog.dart';
import '../../domain/dependency.dart';
import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Shows the status of *all* known dependencies (across every engine), marking
/// required vs optional, and offers to install missing system packages.
class DependencyCard extends StatelessWidget {
  final AppController controller;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool done;
  const DependencyCard({
    super.key,
    required this.controller,
    this.expanded = true,
    this.onToggle,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deps = controller.deps;
    final missingRequired = controller.missingRequired;
    final coreReady = controller.coreToolsReady;
    final engineReady = controller.anyEngineReady;
    // Anything missing that the OS package manager can install.
    final installable =
        deps.where((d) => !d.found && d.kind.isSystemPackage).toList();

    return SectionCard(
      step: 1,
      title: 'Check your toolkit',
      subtitle: 'Required tools must be installed; optional ones can be skipped',
      expanded: expanded,
      onToggle: onToggle,
      done: done,
      trailing: !controller.depsChecked
          ? null
          : !coreReady
              ? StatusPill('${missingRequired.length} required missing',
                  color: AppTokens.rust, icon: Icons.error_outline_rounded)
              : engineReady
                  ? const StatusPill('Ready', icon: Icons.check_rounded)
                  : StatusPill('No TTS engine yet',
                      color: AppTokens.amber, icon: Icons.mic_off_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.depsChecked)
            Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTokens.amber)),
              const SizedBox(width: 10),
              Text('Checking your system…',
                  style: TextStyle(color: AppTokens.muted)),
            ])
          else
            ...deps.map((d) => _DepRow(d)),
          if (controller.depsChecked) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Local voices', style: text.titleMedium),
                const SizedBox(width: 8),
                StatusPill('only one needed', color: AppTokens.muted),
              ],
            ),
            const SizedBox(height: 8),
            ...kSherpaModels.map((m) => _ModelRow(controller: controller, model: m)),
            const SizedBox(height: 10),
            Text(
              !coreReady
                  ? 'Install the required tools (red) to continue.'
                  : engineReady
                      ? "Ready — choose a book below."
                      : 'Core tools are ready. Install any one voice above (or pick a '
                          'cloud engine and add its API key in step 3) to convert.',
              style: TextStyle(
                  color: !coreReady
                      ? AppTokens.rust
                      : engineReady
                          ? AppTokens.sage
                          : AppTokens.amber),
            ),
          ],
          if (installable.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  onPressed:
                      controller.installing ? null : controller.installMissing,
                  icon: controller.installing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTokens.ink))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(controller.installing
                      ? 'Installing…'
                      : 'Install ${installable.map((d) => d.kind.label).join(', ')}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Runs your system package manager. Watch the log below.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A local engine row: status, label, language tags, size, blurb, recommended
/// badge, and a Download button (installs all of the engine's languages).
class _ModelRow extends StatelessWidget {
  final AppController controller;
  final SherpaModel model;
  const _ModelRow({required this.controller, required this.model});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final installed = controller.isModelInstalled(model);
    final downloading = controller.downloadingModelId == model.id;
    final busy = controller.downloadingModelId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              installed
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: installed ? AppTokens.sage : AppTokens.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(model.label,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    for (final l in model.languages) ...[
                      _LangTag(l),
                      const SizedBox(width: 4),
                    ],
                    if (model.recommended) ...[
                      const SizedBox(width: 4),
                      StatusPill('Recommended',
                          color: AppTokens.amber, icon: Icons.star_rounded),
                    ],
                    const SizedBox(width: 6),
                    Text('~${model.sizeMb} MB', style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 2),
                Text(model.blurb, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (installed)
            const StatusPill('installed', icon: Icons.check_rounded)
          else if (downloading)
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(controller.downloadProgress * 100).round()}%',
                      style: text.bodySmall
                          ?.copyWith(color: AppTokens.amberBright)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: controller.downloadProgress > 0
                          ? controller.downloadProgress
                          : null,
                      minHeight: 6,
                      backgroundColor: AppTokens.surfaceHigh,
                      valueColor:
                          AlwaysStoppedAnimation(AppTokens.amber),
                    ),
                  ),
                ],
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: busy ? null : () => controller.downloadModel(model),
              icon: const Icon(Icons.download_rounded, size: 15),
              label: const Text('Install'),
            ),
        ],
      ),
    );
  }
}

/// A tiny language code chip.
class _LangTag extends StatelessWidget {
  final String code;
  const _LangTag(this.code);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTokens.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTokens.line),
      ),
      child: Text(code.toUpperCase(),
          style: TextStyle(
              color: AppTokens.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// One dependency row: status icon, name, a required/optional tag, and details.
class _DepRow extends StatelessWidget {
  final DependencyStatus dep;
  const _DepRow(this.dep);

  @override
  Widget build(BuildContext context) {
    final ok = dep.found;
    final required = dep.kind.isRequired;
    // Found → green. Missing & required → red (blocks). Missing & optional →
    // amber (skippable: only needed for its engine).
    final (icon, color) = ok
        ? (Icons.check_circle_rounded, AppTokens.sage)
        : required
            ? (Icons.cancel_rounded, AppTokens.rust)
            : (Icons.schedule_rounded, AppTokens.amber);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(dep.kind.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          _TagChip(required ? 'required' : 'optional · ${dep.kind.neededFor}',
              required: required),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? (dep.version ?? dep.location ?? 'found')
                  : (dep.installHint ?? 'missing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small required/optional tag.
class _TagChip extends StatelessWidget {
  final String label;
  final bool required;
  const _TagChip(this.label, {required this.required});

  @override
  Widget build(BuildContext context) {
    final color = required ? AppTokens.muted : AppTokens.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
