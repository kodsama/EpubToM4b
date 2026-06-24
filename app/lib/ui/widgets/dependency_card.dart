/// Step 1: verify every library the engines need, with one-click install.
library;

import 'package:flutter/material.dart';

import '../../domain/dependency.dart';
import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Shows the status of *all* known dependencies (across every engine), marking
/// required vs optional, and offers to install missing system packages.
class DependencyCard extends StatelessWidget {
  final AppController controller;
  const DependencyCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
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
      trailing: !controller.depsChecked
          ? null
          : !coreReady
              ? StatusPill('${missingRequired.length} required missing',
                  color: AppTokens.rust, icon: Icons.error_outline_rounded)
              : engineReady
                  ? const StatusPill('Ready', icon: Icons.check_rounded)
                  : const StatusPill('No TTS engine yet',
                      color: AppTokens.amber, icon: Icons.mic_off_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.depsChecked)
            const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTokens.amber)),
              SizedBox(width: 10),
              Text('Checking your system…',
                  style: TextStyle(color: AppTokens.muted)),
            ])
          else
            ...deps.map((d) => _DepRow(d)),
          if (controller.depsChecked) ...[
            const SizedBox(height: 12),
            Text(
              !coreReady
                  ? 'Install the required tools (red) to continue.'
                  : engineReady
                      ? "Ready — choose a book below."
                      : 'Core tools are ready, but no TTS engine is set up yet. '
                          'Choose a book, then in step 3 download Piper or Kokoro, '
                          'or pick a cloud engine and add its API key.',
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
                      ? const SizedBox(
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
