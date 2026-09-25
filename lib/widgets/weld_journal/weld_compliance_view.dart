/// Znaczki „poza WPS" / „spawacz bez ważnych uprawnień" — na karcie spoiny
/// i na liście dziennika — oraz ostrzeżenie przed zapisem.
library;

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_compliance.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Badge(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      );
}

/// Znaczki spoiny; pusty widżet, gdy nie ma czego pokazać.
class WeldComplianceBadges extends StatelessWidget {
  final WeldCompliance compliance;
  const WeldComplianceBadges({super.key, required this.compliance});

  static bool hasAny(WeldCompliance c) =>
      c.outsideWps || c.wpsNeedsReview || c.welderNotQualified;

  @override
  Widget build(BuildContext context) {
    final c = compliance;
    if (!hasAny(c)) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (c.outsideWps)
          _Badge(context.tr(pl: 'poza WPS', en: 'outside WPS'),
              Icons.rule_outlined, kFail)
        else if (c.wpsNeedsReview)
          _Badge(context.tr(pl: 'WPS do wyjaśnienia', en: 'WPS: to clarify'),
              Icons.help_outline, kWarn),
        if (c.welderNotQualified)
          _Badge(
              context.tr(
                  pl: 'spawacz bez ważnych uprawnień w dniu spawania',
                  en: 'welder not qualified on the weld date'),
              Icons.badge_outlined,
              kFail),
      ],
    );
  }
}

/// Panel na karcie spoiny: znaczki, punkty niezgodności i łagodne
/// informacje (czego nie sprawdzono).
class WeldCompliancePanel extends StatelessWidget {
  final WeldCompliance compliance;
  const WeldCompliancePanel({super.key, required this.compliance});

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    final c = compliance;
    final warnings = c.warningLines(en: en);
    final infos = c.cardInfoLines(en: en);
    if (warnings.isEmpty && infos.isEmpty) return const SizedBox.shrink();
    final color = c.outsideWps || c.welderNotQualified ? kFail : kWarn;
    return Container(
      key: const ValueKey('weld-compliance-panel'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (warnings.isEmpty ? kTextMut : color).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: warnings.isEmpty ? kBorder : color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeldComplianceBadges(compliance: c),
          if (warnings.isNotEmpty) const SizedBox(height: 6),
          for (final l in warnings)
            Text(l.startsWith('  ') ? l : '• $l',
                style: const TextStyle(fontSize: 12, color: kText)),
          if (warnings.isNotEmpty && infos.isNotEmpty)
            const SizedBox(height: 6),
          for (final l in infos)
            Text(l, style: const TextStyle(fontSize: 12, color: kTextMut)),
        ],
      ),
    );
  }
}

/// Ostrzeżenie przed zapisem: `true` = „Zapisz mimo to", `false` = „Popraw".
Future<bool> confirmWeldCompliance(
    BuildContext context, WeldCompliance compliance) async {
  final en = AppLanguageController.isEnglish;
  final warnings = compliance.warningLines(en: en);
  final infos = compliance.infoLines(en: en);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr(
          pl: 'Spoina poza WPS / uprawnieniami',
          en: 'Weld outside WPS / qualification')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l.startsWith('  ') ? l : '• $l',
                    style: const TextStyle(fontSize: 13)),
              ),
            for (final l in infos)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l,
                    style: const TextStyle(fontSize: 12, color: kTextMut)),
              ),
            const SizedBox(height: 8),
            Text(
              ctx.tr(
                  pl: 'Zapis nie jest blokowany — ostrzeżenie trafi do '
                      'historii spoiny.',
                  en: 'Saving is not blocked — the warning goes to the '
                      "weld's history."),
              style: const TextStyle(fontSize: 12, color: kTextSec),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr(pl: 'Popraw', en: 'Fix')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr(pl: 'Zapisz mimo to', en: 'Save anyway')),
        ),
      ],
    ),
  );
  return ok ?? false;
}
