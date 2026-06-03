import 'package:flutter/material.dart';

/// Shared empty-state widget for list screens. Chat, Jobs, Projects, AI Chat
/// and Help previously each rolled their own version with subtly different
/// paddings (24/32 px), icon sizes (40/56/96 px) and text styles. Funneling
/// them through one widget keeps the visual rhythm consistent and means a
/// future tweak to the empty-state look touches one file instead of five.
///
/// Usage:
/// ```dart
/// EmptyState(
///   icon: Icons.forum_outlined,
///   title: context.tr(pl: 'Brak wiadomości', en: 'No messages yet'),
///   subtitle: context.tr(pl: 'Bądź pierwszy!', en: 'Be the first!'),
///   onAction: () => _send(),
///   actionLabel: context.tr(pl: 'Napisz', en: 'Write'),
/// )
/// ```
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onAction;
  final String? actionLabel;
  final IconData? actionIcon;
  final Color? accent;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onAction,
    this.actionLabel,
    this.actionIcon,
    this.accent,
  }) : assert(
          (onAction == null) == (actionLabel == null),
          'Provide both onAction and actionLabel together, or neither.',
        );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = accent ?? cs.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tinted circular badge with the screen-defining icon — same
            // size everywhere (56 px) so the visual centre of gravity stays
            // consistent between Chat, Jobs, Projects, etc.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ac.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: ac, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.add),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(backgroundColor: ac),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
