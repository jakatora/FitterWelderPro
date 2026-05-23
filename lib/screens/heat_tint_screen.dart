import 'package:flutter/material.dart';

import '../data/heat_tint.dart';
import '../i18n/app_language.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kGreen  = Color(0xFF2ECC71);
const _kBlue   = Color(0xFF4A9EFF);
const _kOrange = Color(0xFFF5A623);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Weld discoloration chart — the welder reads the inside bead colour against
/// the chart and gets a pass/fail verdict for food vs pharma acceptance.
class HeatTintScreen extends StatelessWidget {
  const HeatTintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Przebarwienia spoiny', en: 'Weld discoloration')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            14, 14, 14, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(
            context.tr(
              pl: 'Porównaj kolor spoiny od WEWNĄTRZ rury z wzorcem. '
                  'Kolor zależy od tlenu w gazie formującym — im ciemniej, tym więcej O₂.',
              en: 'Compare the colour of the weld bead INSIDE the tube with the '
                  'chart. Colour is driven by oxygen in the backing gas — darker means more O₂.',
            ),
            style: const TextStyle(color: _kSec, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 14),
          ...kHeatTintLevels.map((l) => _LevelTile(level: l)),
          const SizedBox(height: 14),
          _LegendCard(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: _kOrange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Wartości O₂ są orientacyjne (model AWS D18.1/D18.2). '
                          'Wiążący poziom akceptacji zawsze podaje specyfikacja projektu / WPS.',
                      en: 'O₂ values are indicative (AWS D18.1/D18.2 model). '
                          'The binding acceptance level is always set by the project spec / WPS.',
                    ),
                    style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _verdictColor(HeatTintVerdict v) {
  switch (v) {
    case HeatTintVerdict.pharma:   return _kGreen;
    case HeatTintVerdict.food:     return _kBlue;
    case HeatTintVerdict.marginal: return _kOrange;
    case HeatTintVerdict.reject:   return _kRed;
  }
}

String _verdictLabel(BuildContext context, HeatTintVerdict v) {
  switch (v) {
    case HeatTintVerdict.pharma:
      return context.tr(pl: 'OK pharma', en: 'OK pharma');
    case HeatTintVerdict.food:
      return context.tr(pl: 'OK spożywczy', en: 'OK food');
    case HeatTintVerdict.marginal:
      return context.tr(pl: 'Graniczne', en: 'Marginal');
    case HeatTintVerdict.reject:
      return context.tr(pl: 'Odrzut', en: 'Reject');
  }
}

class _LevelTile extends StatelessWidget {
  final HeatTintLevel level;
  const _LevelTile({required this.level});

  @override
  Widget build(BuildContext context) {
    final vc = _verdictColor(level.verdict);
    final isPl = context.language == AppLanguage.pl;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // Colour swatch with the level number.
          Container(
            width: 64,
            height: 64,
            color: level.swatch,
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${level.level}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPl ? level.namePl : level.nameEn,
                    style: const TextStyle(
                        color: Color(0xFFE8ECF0),
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('O₂ ≈ ${level.approxO2}',
                    style: const TextStyle(color: _kMuted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: vc.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: vc.withValues(alpha: 0.4)),
            ),
            child: Text(_verdictLabel(context, level.verdict),
                style: TextStyle(
                    color: vc, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget chip(HeatTintVerdict v) {
      final c = _verdictColor(v);
      return Padding(
        padding: const EdgeInsets.only(right: 14, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(_verdictLabel(context, v),
                style: const TextStyle(color: _kSec, fontSize: 12)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                pl: 'Typowa akceptacja (orientacyjnie)',
                en: 'Typical acceptance (indicative)'),
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Wrap(children: [
            chip(HeatTintVerdict.pharma),
            chip(HeatTintVerdict.food),
            chip(HeatTintVerdict.marginal),
            chip(HeatTintVerdict.reject),
          ]),
          Text(
            context.tr(
              pl: 'Pharma zwykle do poz. 2–3, spożywczy do poz. 3–4. '
                  'Graniczne → konsultuj z kontrolą jakości.',
              en: 'Pharma typically up to level 2–3, food up to 3–4. '
                  'Marginal → check with QC.',
            ),
            style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
