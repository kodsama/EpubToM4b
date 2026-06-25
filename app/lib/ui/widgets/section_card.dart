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

  /// Whether the body is shown. When false, only the header renders and a
  /// chevron points right; tapping the header calls [onToggle].
  final bool expanded;

  /// Called when the header is tapped (to expand/collapse). Null = not tappable.
  final VoidCallback? onToggle;

  /// Whether this step is already completed (shows a check on the chip).
  final bool done;

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
    this.expanded = true,
    this.onToggle,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StepChip(step, done: done),
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
        if (onToggle != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.chevron_right_rounded,
                  color: AppTokens.muted),
            ),
          ),
      ],
    );

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
                onToggle == null
                    ? header
                    : InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(8),
                        child: header,
                      ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: child,
                  ),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
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
  final bool done;
  const _StepChip(this.step, {this.done = false});

  @override
  Widget build(BuildContext context) {
    final color = done ? AppTokens.sage : AppTokens.amber;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 16, color: AppTokens.sage)
          : Text(
              '$step',
              style: TextStyle(
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

  /// Accent color (defaults to the success/sage tone when null).
  final Color? color;

  /// Optional leading icon.
  final IconData? icon;

  const StatusPill(
    this.label, {
    super.key,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTokens.sage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
