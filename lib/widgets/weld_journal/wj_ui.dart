/// Small shared pieces of the weld-journal UI: status colours and labels,
/// a glove-sized choice chip and a collapsible form section.
///
/// Every tappable element here is at least [kMinTapTarget] (48 dp) tall. The
/// old status and filter chips were ~30 dp — a welder in gloves hit the
/// neighbour as often as the chip he meant.
library;

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_entry.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

Color weldStatusColor(String status) => switch (status) {
      WeldStatus.ok => kPass,
      WeldStatus.nok => kFail,
      WeldStatus.pending => kArc,
      _ => kTextSec,
    };

IconData weldStatusIcon(String status) => switch (status) {
      WeldStatus.ok => Icons.check_circle_outline,
      WeldStatus.nok => Icons.cancel_outlined,
      WeldStatus.pending => Icons.pending_outlined,
      _ => Icons.help_outline,
    };

String weldStatusLabel(BuildContext context, String status) =>
    switch (status) {
      WeldStatus.ok => context.tr(pl: 'OK — przyjęta', en: 'OK — accepted'),
      WeldStatus.nok => context.tr(pl: 'NOK — odrzucona', en: 'NOK — rejected'),
      WeldStatus.pending => context.tr(pl: 'Oczekuje', en: 'Pending'),
      _ => status,
    };

/// Short status label for chips (`OK`, `NOK`, `Oczekuje`).
String weldStatusShort(BuildContext context, String status) =>
    status == WeldStatus.pending
        ? context.tr(pl: 'Oczekuje', en: 'Pending')
        : status;

/// Choice chip at least 48 dp tall, with button semantics.
class WjChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;

  const WjChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = kArc,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? color : kTextSec;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(
              minHeight: kMinTapTarget, minWidth: kMinTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : kCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: selected ? color : kBorder, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible section of the weld editor.
class WjSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// Short state shown on the collapsed header ("RT: wybrane", "2 zmiany").
  final String? badge;

  const WjSection({
    super.key,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: kArc),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kText),
                  ),
                ),
                if (badge != null && badge!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      badge!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: kTextSec),
                    ),
                  ),
                ],
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: kTextSec),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          ...children,
        ],
      ],
    );
  }
}

/// Two fields side by side with the usual gap.
class WjRow extends StatelessWidget {
  final List<Widget> children;
  const WjRow(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}
