// Drobne widżety modułu odbioru kołnierzy: pigułka werdyktu, baner
// protokołu, karta kryterium, karta historii, tabela zał. D.

import 'package:flutter/material.dart';

import '../../domain/flange/flange_check.dart';
import '../../domain/flange/flange_labels.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

Color checkVerdictColor(CheckVerdict v) => switch (v) {
      CheckVerdict.ok => kPass,
      CheckVerdict.fail => kFail,
      CheckVerdict.missing => kTextMut,
    };

Color protocolVerdictColor(ProtocolVerdict v) => switch (v) {
      ProtocolVerdict.accepted => kPass,
      ProtocolVerdict.rejected => kFail,
      ProtocolVerdict.incomplete => kWarn,
    };

IconData _protocolIcon(ProtocolVerdict v) => switch (v) {
      ProtocolVerdict.accepted => Icons.verified_outlined,
      ProtocolVerdict.rejected => Icons.cancel_outlined,
      ProtocolVerdict.incomplete => Icons.pending_outlined,
    };

/// „OK” / „Poza tolerancją” / „Brak pomiaru” w kolorze werdyktu.
class VerdictPill extends StatelessWidget {
  final CheckVerdict verdict;
  const VerdictPill({super.key, required this.verdict});

  @override
  Widget build(BuildContext context) {
    final color = checkVerdictColor(verdict);
    final en = context.language == AppLanguage.en;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        checkVerdictLabel(verdict, en: en),
        textAlign: TextAlign.center,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Werdykt całego protokołu na górze ekranu.
class FlangeVerdictBanner extends StatelessWidget {
  final FlangeEvaluation evaluation;
  const FlangeVerdictBanner({super.key, required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final v = evaluation.verdict;
    final color = protocolVerdictColor(v);
    final ok = evaluation.count(CheckVerdict.ok);
    final total = evaluation.criteria.length;
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
          Icon(_protocolIcon(v), color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  protocolVerdictLabel(v, en: en),
                  key: const ValueKey('flange-verdict'),
                  style: TextStyle(
                      color: color, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                      pl: 'Pomiary OK: $ok/$total · lista: '
                          '${evaluation.checkedCount}/${evaluation.checklistTotal}',
                      en: 'Measurements OK: $ok/$total · list: '
                          '${evaluation.checkedCount}/${evaluation.checklistTotal}'),
                  style: const TextStyle(fontSize: 12.5, color: kTextSec),
                ),
                if (v == ProtocolVerdict.incomplete)
                  Text(missingSummary(evaluation, en: en),
                      style: const TextStyle(fontSize: 12, color: kTextMut)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jedno kryterium osiowania: tytuł + werdykt, pole (opcjonalnie), wartość
/// względem granicy i podpowiedź, jak mierzyć.
class CriterionTile extends StatelessWidget {
  final CriterionResult result;
  final String valueLine;
  final Widget? input;

  const CriterionTile({
    super.key,
    required this.result,
    required this.valueLine,
    this.input,
  });

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final c = result.criterion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(criterionTitle(c, en: en),
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kText)),
              ),
              const SizedBox(width: 8),
              // Flexible: przy dużej czcionce na wąskim ekranie pigułka
              // zawija tekst zamiast wypychać tytuł poza ekran.
              Flexible(
                flex: 2,
                child: VerdictPill(
                    key: ValueKey('flange-v-${c.name}'),
                    verdict: result.verdict),
              ),
            ],
          ),
          if (input != null) ...[
            const SizedBox(height: 8),
            input!,
          ],
          const SizedBox(height: 6),
          Text(valueLine,
              key: ValueKey('flange-line-${c.name}'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: result.verdict == CheckVerdict.fail ? kFail : kText,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(criterionHint(c, en: en),
              style:
                  const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
        ],
      ),
    );
  }
}

/// Wiersz wyboru jak radio — ListTile, więc tekst się zawija (chip z długą
/// etykietą na wąskim ekranie by się nie zmieścił), a cel dotyku ≥ 48 dp.
class ChoiceRow extends StatelessWidget {
  final bool selected;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ChoiceRow({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.color = kArc,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: kMinTapTarget,
      selected: selected,
      onTap: onTap,
      leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? color : kTextSec),
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              color: selected ? color : kText,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
    );
  }
}

/// PCC-1 zał. D tab. D-2: dopuszczalna głębokość uszkodzenia powierzchni.
class DefectDepthTable extends StatelessWidget {
  const DefectDepthTable({super.key});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    String mm(double? v) => v == null
        ? context.tr(pl: 'niedop.', en: 'not allowed')
        : '< ${fmtNum(v, en: en)}';
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
          children: [
            for (final c in cells)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                child: Text(c,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: head ? FontWeight.w800 : FontWeight.w600,
                        color: head ? kTextSec : kText)),
              ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          border: const TableBorder(
              horizontalInside: BorderSide(color: kBorder, width: 1)),
          children: [
            row([
              context.tr(pl: 'Zasięg rysy', en: 'Defect reach'),
              context.tr(pl: 'twarda, mm', en: 'hard, mm'),
              context.tr(pl: 'miękka, mm', en: 'soft, mm'),
            ], head: true),
            for (final l in kPcc1DefectDepth)
              row([l.reach, mm(l.hardMm), mm(l.softMm)]),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
              pl: 'w — szerokość osadzenia uszczelki, rd — jak daleko rysa sięga '
                  'w poprzek niej. Twarde: spiralne, kammprofile, metalowe; '
                  'miękkie: płaskie niemetalowe, PTFE. Głębokość od wierzchołków '
                  'chropowatości; nie szlifować miejscowo. Płaskość (tab. D-1): '
                  'twarde < ${fmtNum(kPcc1FlatnessHardMm, en: en)} mm, miękkie '
                  '< ${fmtNum(kPcc1FlatnessSoftMm, en: en)} mm.',
              en: 'w — gasket seating width, rd — how far the defect reaches '
                  'across it. Hard: spiral-wound, kammprofile, metallic; soft: '
                  'non-metallic sheet, PTFE. Depth from the surface-finish '
                  'peaks; do not grind locally. Flatness (Table D-1): hard '
                  '< ${fmtNum(kPcc1FlatnessHardMm, en: en)} mm, soft '
                  '< ${fmtNum(kPcc1FlatnessSoftMm, en: en)} mm.'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.35),
        ),
      ],
    );
  }
}

/// Zapisany protokół na liście historii.
class FlangeHistoryCard extends StatelessWidget {
  final FlangeCheck check;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onShareText;
  final VoidCallback onSharePdf;
  final VoidCallback onDelete;

  const FlangeHistoryCard({
    super.key,
    required this.check,
    required this.onOpen,
    required this.onDuplicate,
    required this.onShareText,
    required this.onSharePdf,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final v = check.evaluate().verdict;
    final color = protocolVerdictColor(v);
    final j = check.joint;
    final meta = [
      if (j.dn != null) flangeSizeLabel(j.dn!),
      if (j.rating.trim().isNotEmpty) j.rating.trim(),
      if (j.date.isNotEmpty) j.date,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: v == ProtocolVerdict.rejected
                  ? kFail.withValues(alpha: 0.6)
                  : kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 44,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          j.tag.trim().isEmpty
                              ? context.tr(
                                  pl: '(bez oznaczenia)', en: '(no tag)')
                              : j.tag.trim(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      if (meta.isNotEmpty)
                        Text(meta,
                            style: const TextStyle(
                                fontSize: 12.5, color: kTextSec)),
                      Text(protocolVerdictLabel(v, en: en),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: color,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('flange-h-dup-${check.id}'),
                  tooltip: context.tr(
                      pl: 'Duplikuj (jak ten)', en: 'Duplicate (like this)'),
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: onDuplicate,
                ),
                PopupMenuButton<String>(
                  key: ValueKey('flange-h-menu-${check.id}'),
                  tooltip: context.tr(pl: 'Więcej', en: 'More'),
                  onSelected: (s) => switch (s) {
                    'text' => onShareText(),
                    'pdf' => onSharePdf(),
                    'del' => onDelete(),
                    'dup' => onDuplicate(),
                    _ => onOpen(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'open',
                        child: Text(context.tr(pl: 'Otwórz', en: 'Open'))),
                    PopupMenuItem(
                        value: 'dup',
                        child: Text(context.tr(
                            pl: 'Duplikuj (jak ten)',
                            en: 'Duplicate (like this)'))),
                    PopupMenuItem(
                        value: 'text',
                        child: Text(context.tr(
                            pl: 'Udostępnij tekst', en: 'Share as text'))),
                    PopupMenuItem(
                        value: 'pdf',
                        child: Text(
                            context.tr(pl: 'Udostępnij PDF', en: 'Share PDF'))),
                    PopupMenuItem(
                        value: 'del',
                        child: Text(context.tr(pl: 'Usuń', en: 'Delete'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
