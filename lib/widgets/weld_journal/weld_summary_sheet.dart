/// NDT summary of the visible welds: % examined by RT/UT per project, line
/// and welder, repair rate per welder, and the ASME B31.3 §341.3.4 counter.
library;

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_stats.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

String _pct(double v) => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}%';

/// One-line summary for the journal screen, e.g.
/// `RT/UT 12/40 (30%) · naprawy 2 · do dobadania 4`.
String weldStatsLine(BuildContext context, WeldJournalStats s) {
  final t = s.total;
  final toExamine =
      s.byWelder.fold<int>(0, (sum, g) => sum + g.toExamine);
  return [
    'RT/UT ${t.volumetricExamined}/${t.welds} (${_pct(t.volumetricPct)})',
    '${context.tr(pl: 'naprawy', en: 'repairs')} ${t.repairs}',
    if (toExamine > 0)
      '${context.tr(pl: 'do dobadania', en: 'to examine')} $toExamine',
  ].join(' · ');
}

Future<void> showWeldSummarySheet(
  BuildContext context, {
  required WeldJournalStats stats,
  required String scopeDescription,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: _WeldSummary(stats: stats, scope: scopeDescription),
        ),
      ),
    );

class _WeldSummary extends StatelessWidget {
  final WeldJournalStats stats;
  final String scope;
  const _WeldSummary({required this.stats, required this.scope});

  @override
  Widget build(BuildContext context) {
    final t = stats.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(pl: 'Podsumowanie NDT', en: 'NDT summary'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kText),
          ),
          if (scope.isNotEmpty)
            Text(scope,
                style: const TextStyle(fontSize: 12, color: kTextMut)),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr(
                      pl: 'Spoiny: ${t.welds} · zbadane RT: ${t.rtExamined}, '
                          'UT: ${t.utExamined} · RT lub UT: '
                          '${t.volumetricExamined} (${_pct(t.volumetricPct)}) '
                          '· naprawiane: ${t.repairedWelds}',
                      en: 'Welds: ${t.welds} · RT examined: ${t.rtExamined}, '
                          'UT: ${t.utExamined} · RT or UT: '
                          '${t.volumetricExamined} (${_pct(t.volumetricPct)}) '
                          '· repaired: ${t.repairedWelds}',
                    ),
                    style: const TextStyle(fontSize: 13, color: kText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      pl: 'Wymagany % badań wynika ze specyfikacji projektu '
                          '(ustaw go w „Ustawienia projektu”). Aplikacja '
                          'niczego nie zakłada.',
                      en: 'The required % comes from the project '
                          'specification (set it in "Project settings"). The '
                          'app assumes nothing.',
                    ),
                    style: const TextStyle(fontSize: 12, color: kTextMut),
                  ),
                  _header(context,
                      context.tr(pl: 'Projekty', en: 'Projects')),
                  for (final g in stats.byProject) _volumetricRow(context, g),
                  _header(context,
                      context.tr(pl: 'Linie', en: 'Lines')),
                  for (final g in stats.byLine) _volumetricRow(context, g),
                  _header(context,
                      context.tr(pl: 'Spawacze', en: 'Welders')),
                  for (final g in stats.byWelder) _welderRow(context, g),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorder),
                    ),
                    child: Text(
                      context.tr(
                        pl: 'ASME B31.3 §341.3.4: za każdą spoinę odrzuconą w '
                            'badaniu wyrywkowym trzeba zbadać dwie dodatkowe '
                            'spoiny tego samego spawacza, tą samą metodą. '
                            '„Do dobadania” = 2 × odrzucone − spoiny '
                            'oznaczone jako „dodatkowa §341.3.4”. Wyboru '
                            'spoin dokonuje inspektor — aplikacja tylko liczy.',
                        en: 'ASME B31.3 §341.3.4: for each weld rejected in a '
                            'random/spot examination, two additional welds by '
                            'the same welder must be examined by the same '
                            'method. "To examine" = 2 × rejected − welds '
                            'marked "additional §341.3.4". The inspector '
                            'picks the welds — the app only counts.',
                      ),
                      style: const TextStyle(fontSize: 12, color: kTextSec),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr(pl: 'Zamknij', en: 'Close')),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kArc)),
      );

  Widget _volumetricRow(BuildContext context, WeldGroupStats g) {
    final target = g.targetPct;
    final targetText = target == null
        ? context.tr(pl: 'cel: nie ustawiono', en: 'target: not set')
        : '${context.tr(pl: 'cel', en: 'target')} ${_pct(target)}';
    return _row(
      g.key,
      'RT/UT ${g.volumetricExamined}/${g.welds} '
          '(${_pct(g.volumetricPct)}) · $targetText',
      warn: g.belowTarget,
    );
  }

  Widget _welderRow(BuildContext context, WeldGroupStats g) => _row(
        g.key,
        [
          'RT/UT ${g.volumetricExamined}/${g.welds} (${_pct(g.volumetricPct)})',
          '${context.tr(pl: 'naprawy', en: 'repairs')} '
              '${g.repairedWelds}/${g.welds} (${_pct(g.repairRatePct)})',
          '${context.tr(pl: 'odrzucone', en: 'rejected')} ${g.rejects}',
          '${context.tr(pl: 'do dobadania', en: 'to examine')} '
              '${g.toExamine}',
        ].join(' · '),
        warn: g.toExamine > 0,
      );

  Widget _row(String title, String body, {bool warn = false}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: warn ? kWarn : kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
            Text(body,
                style: TextStyle(
                    fontSize: 12, color: warn ? kWarn : kTextSec)),
          ],
        ),
      );
}
