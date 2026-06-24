/// A titled, numbered step card used to structure the home screen flow.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A card with a leading step number, a serif title, optional trailing widget,
/// and a body. Gives the home screen its calm, stepped rhythm.
class SectionCard extends StatelessWidget {
  /// 1-based step number shown in the amber chip.
  final int step;

  /// Section title.
  final String title;

  /// Optional short subtitle under the title.
  final String? subtitle;

  /// Optional trailing widget (status chip, action).
  final Widget? trailing;

  /// Whether the step is visually de-emphasized (not yet reachable).
  final bool dimmed;

  /// Card body.
  final Widget child;

  const SectionCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: dimmed,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepChip(step),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.titleLarge),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitle!, style: text.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final int step;
  const _StepChip(this.step);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTokens.amber.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: AppTokens.amber.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$step',
        style: const TextStyle(
          color: AppTokens.amberBright,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// A small rounded status pill (e.g. "Ready", "3 missing").
class StatusPill extends StatelessWidget {
  /// Pill text.
  final String label;

  /// Accent color.
  final Color color;

  /// Optional leading icon.
  final IconData? icon;

  const StatusPill(
    this.label, {
    super.key,
    this.color = AppTokens.sage,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
