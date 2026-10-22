import 'package:flutter/material.dart';

import '../assistant/core/tool_bridge.dart';
import '../data/heat_tint.dart';
import '../i18n/app_language.dart';
import '../theme/app_theme.dart' show kTextMut;

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)

/// Weld discoloration chart — the welder reads the inside bead colour against
/// the chart and gets a pass/fail verdict for food vs pharma acceptance, plus
/// the project's own acceptance limit (the coupon log warns above it).
class HeatTintScreen extends StatefulWidget {
  const HeatTintScreen({super.key});

  @override
  State<HeatTintScreen> createState() => _HeatTintScreenState();
}

class _HeatTintScreenState extends State<HeatTintScreen>
    with ToolHandleHost<HeatTintScreen>
    implements InputToolHandle {
  int _limit = kDefaultHeatTintLimit;

  /// Poziom wskazany przez asystenta (wyróżniony kafel); null — brak.
  int? _highlight;
  final _tileKeys = {for (final l in kHeatTintLevels) l.level: GlobalKey()};

  @override
  String get toolId => 'heat_tint';
  @override
  Set<String> get supportedFields => const {'level'};
  @override
  Map<String, Object?> get inputFields =>
      Map.unmodifiable({'level': _highlight, 'limit': _limit});

  /// Asystent wskazuje poziom wzorca: kafel dostaje ramkę i przewija się
  /// na ekran. Limit projektu zostaje bez zmian.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final level = fields['level'];
    if (!mounted ||
        fields.keys.any((k) => !supportedFields.contains(k)) ||
        level is! num ||
        level != level.roundToDouble() ||
        level < 1 ||
        level > 10) {
      return fields.keys.toSet();
    }
    setState(() => _highlight = level.toInt());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[_highlight]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: .3, duration: const Duration(milliseconds: 250));
      }
    });
    return {};
  }

  @override
  void initState() {
    super.initState();
    loadHeatTintLimit().then((v) {
      if (mounted) setState(() => _limit = v);
    });
    markReady();
  }

  Future<void> _setLimit(int v) async {
    setState(() => _limit = v);
    await saveHeatTintLimit(v);
  }

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
          _LimitCard(limit: _limit, onChanged: _setLimit),
          const SizedBox(height: 12),
          ...kHeatTintLevels.map((l) => KeyedSubtree(
              key: _tileKeys[l.level],
              child: _LevelTile(
                  level: l,
                  aboveLimit: l.level > _limit,
                  highlighted: l.level == _highlight))),
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
                      pl: 'Wartości O₂ są orientacyjne — to tlen w gazie formującym, przy którym '
                          'wykonano wzorce AWS D18.2. Na kolor wpływają też wilgoć, zanieczyszczenia '
                          'i wykończenie powierzchni, więc oceniaj po numerze wzorca, nie po ppm. '
                          'Wiążący poziom akceptacji zawsze podaje specyfikacja projektu / WPS.',
                      en: 'O₂ values are indicative — they are the backing-gas O₂ used for the '
                          'AWS D18.2 samples. Moisture, surface contamination and finish also '
                          'change the colour, so judge by sample number, not ppm. '
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

Color _verdictColor(HeatTintVerdict v) => heatTintVerdictColor(v);

// A data row may ship the O₂ band as a "PL / EN" slash-pair. Split it so each
// locale sees only its half (plain "~ 100 ppm" rows pass through unchanged).
String _localizedO2(BuildContext context, String raw) {
  final i = raw.indexOf(' / ');
  if (i < 0) return raw;
  final pl = raw.substring(0, i);
  final en = raw.substring(i + 3);
  return context.tr(pl: pl, en: en);
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

  /// Poziom ponad limitem akceptacji projektu.
  final bool aboveLimit;

  /// Kafel wskazany przez asystenta.
  final bool highlighted;
  const _LevelTile(
      {required this.level, this.aboveLimit = false, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final vc = _verdictColor(level.verdict);
    final isPl = context.language == AppLanguage.pl;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: highlighted
            ? Border.all(color: _kOrange, width: 3)
            : Border.all(color: _kBorder),
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
                        color: Color(0xFFE7ECF3),
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('O₂ ≈ ${_localizedO2(context, level.approxO2)}',
                    style: const TextStyle(
                        color: _kSec,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                if (aboveLimit)
                  Text(
                    context.tr(
                        pl: 'ponad limit projektu',
                        en: 'above the project limit'),
                    style: const TextStyle(
                        color: _kRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: vc.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: vc.withValues(alpha: 0.4)),
            ),
            child: Text(_verdictLabel(context, level.verdict),
                style: TextStyle(
                    color: vc,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2)),
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
              pl: 'Pharma zwykle do poz. $kPharmaTypicalMaxLevel, spożywczy '
                  'do poz. $kFoodTypicalMaxLevel (tak jak na kaflach). '
                  'Graniczne → konsultuj z kontrolą jakości. Kolor na '
                  'ekranie jest orientacyjny — porównuj z fizycznym '
                  'wzornikiem AWS D18.2.',
              en: 'Pharma typically up to level $kPharmaTypicalMaxLevel, food '
                  'up to $kFoodTypicalMaxLevel (as on the tiles). Marginal → '
                  'check with QC. Screen colour is indicative — compare with '
                  'the physical AWS D18.2 chart.',
            ),
            style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Limit akceptacji projektu — wiążący wg specyfikacji; log kuponów
/// ostrzega przy wyniku OK ponad nim.
class _LimitCard extends StatelessWidget {
  final int limit;
  final ValueChanged<int> onChanged;
  const _LimitCard({required this.limit, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
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
                pl: 'Limit akceptacji projektu: poziom ≤ $limit',
                en: 'Project acceptance limit: level ≤ $limit'),
            style: const TextStyle(
                color: Color(0xFFE7ECF3),
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Ustaw wg specyfikacji projektu (BPE, 3-A, klient). Log '
                    'kuponów ostrzega, gdy kupon ponad limitem ma wynik OK.',
                en: 'Set per the project specification (BPE, 3-A, client). '
                    'The coupon log warns when a coupon above the limit is '
                    'marked OK.'),
            style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in HeatTintLimitPreset.values)
              ChoiceChip(
                label: Text(en ? p.labelEn : p.labelPl),
                selected: limit == p.maxLevel,
                onSelected: (_) => onChanged(p.maxLevel),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text(context.tr(pl: 'Własny:', en: 'Custom:'),
                style: const TextStyle(color: _kSec, fontSize: 13)),
            Expanded(
              child: Slider(
                value: limit.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$limit',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
