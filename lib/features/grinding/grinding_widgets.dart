// Drobne widżety modułu „Tarcze i szlifierki”: baner werdyktu, wiersz
// wyniku, pytanie tak/nie (bez odpowiedzi = „nie wiem”), próbka paska
// barwnego.

import 'package:flutter/material.dart';

import '../../domain/grinding/grinding_check.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

Color grindingVerdictColor(GrindingVerdict v) => switch (v) {
      GrindingVerdict.stop => kFail,
      GrindingVerdict.noVerdict => kTextSec,
      GrindingVerdict.caution => kWarn,
      GrindingVerdict.ok => kPass,
    };

IconData _verdictIcon(GrindingVerdict v) => switch (v) {
      GrindingVerdict.stop => Icons.dangerous_outlined,
      GrindingVerdict.noVerdict => Icons.help_outline,
      GrindingVerdict.caution => Icons.warning_amber_rounded,
      GrindingVerdict.ok => Icons.verified_outlined,
    };

Color findingLevelColor(FindingLevel l) => switch (l) {
      FindingLevel.stop => kFail,
      FindingLevel.missing => kTextSec,
      FindingLevel.warn => kWarn,
      FindingLevel.ok => kPass,
    };

IconData findingLevelIcon(FindingLevel l) => switch (l) {
      FindingLevel.stop => Icons.block,
      FindingLevel.missing => Icons.help_outline,
      FindingLevel.warn => Icons.warning_amber_rounded,
      FindingLevel.ok => Icons.check_circle_outline,
    };

String findingLevelLabel(FindingLevel l, {required bool en}) => switch (l) {
      FindingLevel.stop => 'STOP',
      FindingLevel.missing => en ? 'No data' : 'Brak danych',
      FindingLevel.warn => en ? 'Warning' : 'Uwaga',
      FindingLevel.ok => 'OK',
    };

/// Werdykt zestawu na górze zakładki „Sprawdź”.
class GrindingVerdictBanner extends StatelessWidget {
  final GrindingEvaluation evaluation;

  /// Zaznaczone / wszystkie punkty listy kontrolnej przed pracą.
  final int checklistChecked;
  final int checklistTotal;

  const GrindingVerdictBanner({
    super.key,
    required this.evaluation,
    required this.checklistChecked,
    required this.checklistTotal,
  });

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final v = evaluation.verdict;
    final color = grindingVerdictColor(v);
    final stops = evaluation.count(FindingLevel.stop);
    final missing = evaluation.count(FindingLevel.missing);
    final warns = evaluation.count(FindingLevel.warn);
    final listDone = checklistChecked == checklistTotal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_verdictIcon(v), color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.label(en: en),
                  key: const ValueKey('gr-verdict'),
                  style: TextStyle(
                      color: color, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                      pl: 'STOP: $stops · brak danych: $missing · '
                          'ostrzeżenia: $warns',
                      en: 'STOP: $stops · missing data: $missing · '
                          'warnings: $warns'),
                  key: const ValueKey('gr-verdict-counts'),
                  style: const TextStyle(fontSize: 12.5, color: kTextSec),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                      pl: 'Przed pracą — lista kontrolna: '
                          '$checklistChecked/$checklistTotal'
                          '${listDone ? '' : ' (niezaznaczone ≠ OK)'}',
                      en: 'Before work — checklist: '
                          '$checklistChecked/$checklistTotal'
                          '${listDone ? '' : ' (unticked ≠ OK)'}'),
                  key: const ValueKey('gr-verdict-checklist'),
                  style: TextStyle(
                      fontSize: 12.5,
                      color: listDone ? kPass : kWarn,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jeden wynik sprawdzenia: ikona poziomu, tekst, źródło.
class GrindingFindingTile extends StatelessWidget {
  final GrindingFinding finding;

  const GrindingFindingTile({super.key, required this.finding});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final color = findingLevelColor(finding.level);
    final source = finding.sourceLabel(en: en);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(findingLevelIcon(finding.level), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  findingLevelLabel(finding.level, en: en),
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  finding.text(en: en),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: finding.level == FindingLevel.stop ? kFail : kText,
                    fontWeight: finding.level == FindingLevel.stop
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (source != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(source,
                        style: const TextStyle(
                            fontSize: 11.5, color: kTextMut, height: 1.3)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pytanie tak/nie. Brak wyboru = „nie wiem” (i to NIE jest „tak”).
/// Ponowne dotknięcie wybranej odpowiedzi ją cofa.
class YesNoChips extends StatelessWidget {
  final String keyPrefix;
  final String question;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const YesNoChips({
    super.key,
    required this.keyPrefix,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question,
              style: const TextStyle(
                  fontSize: 13.5, color: kText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: ValueKey('$keyPrefix-yes'),
                label: Text(context.tr(pl: 'Tak', en: 'Yes')),
                selected: value == true,
                onSelected: (s) => onChanged(s ? true : null),
              ),
              ChoiceChip(
                key: ValueKey('$keyPrefix-no'),
                label: Text(context.tr(pl: 'Nie', en: 'No')),
                selected: value == false,
                onSelected: (s) => onChanged(s ? false : null),
              ),
              if (value == null)
                Text(context.tr(pl: 'nie wiem', en: 'not known'),
                    style: const TextStyle(fontSize: 12, color: kTextMut)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Próbka paska barwnego (jeden albo dwa kolory).
class StripeSwatch extends StatelessWidget {
  final SpeedStripe stripe;
  const StripeSwatch({super.key, required this.stripe});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 18,
        height: 12,
        child: Column(
          children: [
            for (final c in stripe.argb)
              Expanded(child: ColoredBox(color: Color(c))),
          ],
        ),
      ),
    );
  }
}
