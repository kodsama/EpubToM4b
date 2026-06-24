/// Step 5: live global + per-chapter conversion progress.
library;

import 'package:flutter/material.dart';

import '../../domain/progress.dart';
import '../theme.dart';
import 'section_card.dart';

/// Renders the character-weighted global progress bar plus one row per chapter
/// with its own mini bar and status icon.
class ProgressView extends StatelessWidget {
  final ConversionProgress progress;
  final bool expanded;
  final VoidCallback? onToggle;

  /// When set (mobile), a "Share audiobook" button appears once the run is done,
  /// since the file lives in app-scoped storage and is delivered via the share
  /// sheet rather than written to a user-chosen folder.
  final VoidCallback? onShare;
  const ProgressView({
    super.key,
    required this.progress,
    this.expanded = true,
    this.onToggle,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pct = (progress.globalFraction * 100).round();
    return SectionCard(
      step: 5,
      title: 'Conversion progress',
      subtitle: progress.message,
      expanded: expanded,
      onToggle: onToggle,
      trailing: _phasePill(progress.phase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress.phase == ConvPhase.error) ...[
            _ErrorBanner(message: progress.message ?? 'Conversion failed'),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(child: _Bar(value: progress.globalFraction, height: 12)),
              const SizedBox(width: 12),
              Text('$pct%',
                  style: text.titleMedium?.copyWith(color: AppTokens.amberBright)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: AppTokens.ink,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTokens.line),
            ),
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: progress.chapters.length,
              itemBuilder: (context, i) => _ChapterRow(progress.chapters[i]),
            ),
          ),
          if (onShare != null && progress.phase == ConvPhase.done) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share audiobook'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phasePill(ConvPhase phase) => switch (phase) {
        ConvPhase.done =>
          const StatusPill('Done', icon: Icons.celebration_rounded),
        ConvPhase.error =>
          const StatusPill('Error', color: AppTokens.rust, icon: Icons.error_outline),
        ConvPhase.assembling =>
          const StatusPill('Assembling', color: AppTokens.amber, icon: Icons.library_music_outlined),
        ConvPhase.synthesizing =>
          const StatusPill('Narrating', color: AppTokens.amber, icon: Icons.graphic_eq_rounded),
        _ => const StatusPill('Idle', color: AppTokens.muted),
      };
}

/// A red banner shown at the top of the progress view when a run fails.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.rust.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.rust.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppTokens.rust),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppTokens.rust, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final ChapterProgress ch;
  const _ChapterRow(this.ch);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          _statusIcon(ch.status),
          const SizedBox(width: 10),
          SizedBox(
            width: 200,
            child: Text(ch.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Expanded(child: _Bar(value: ch.fraction, height: 6)),
        ],
      ),
    );
  }

  Widget _statusIcon(ChapterStatus s) => switch (s) {
        ChapterStatus.done =>
          const Icon(Icons.check_circle_rounded, size: 16, color: AppTokens.sage),
        ChapterStatus.error =>
          const Icon(Icons.error_rounded, size: 16, color: AppTokens.rust),
        ChapterStatus.synthesizing => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.amber)),
        ChapterStatus.assembling =>
          const Icon(Icons.merge_rounded, size: 16, color: AppTokens.amber),
        ChapterStatus.skipped =>
          const Icon(Icons.remove_circle_outline, size: 16, color: AppTokens.muted),
        ChapterStatus.pending =>
          const Icon(Icons.circle_outlined, size: 16, color: AppTokens.muted),
      };
}

/// A rounded amber progress bar with a soft track.
class _Bar extends StatelessWidget {
  final double value;
  final double height;
  const _Bar({required this.value, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: AppTokens.surfaceHigh,
        valueColor: const AlwaysStoppedAnimation(AppTokens.amber),
      ),
    );
  }
}
