import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/support_spacing.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Pipe support configuration — spacing calculator + reference + support
/// types + placement rules. The "must-have" knowledge fitters carry between
/// projects so they don't re-derive it on every site.
class SupportConfigScreen extends StatelessWidget {
  const SupportConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(
              pl: 'Konfiguracja podpór', en: 'Support configuration')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'Kalkulator', en: 'Calculator')),
              Tab(text: context.tr(pl: 'Tabela MSS', en: 'MSS table')),
              Tab(text: context.tr(pl: 'Typy', en: 'Types')),
              Tab(text: context.tr(pl: 'Zasady', en: 'Rules')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CalcTab(),
            _TableTab(),
            _TypesTab(),
            _RulesTab(),
          ],
        ),
      ),
    );
  }
}

// ─── CALCULATOR ─────────────────────────────────────────────────────────────

class _CalcTab extends StatefulWidget {
  const _CalcTab();
  @override
  State<_CalcTab> createState() => _CalcTabState();
}

class _CalcTabState extends State<_CalcTab> {
  int _dn = 50;
  bool _waterFilled = true;
  bool _insulated = false;
  final _length = TextEditingController();

  @override
  void dispose() {
    _length.dispose();
    super.dispose();
  }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  Widget build(BuildContext context) {
    final span = closestSpanByDn(_dn);
    int spacingMm = _waterFilled ? span.waterMm : span.vaporMm;
    // Insulation reduces allowable spacing by 12 % (mid of 10–15 % rule).
    if (_insulated) spacingMm = (spacingMm * 0.88).round();
    final lengthM =
        double.tryParse(_length.text.replaceAll(',', '.')) ?? 0;
    // Sanity cap: longest realistic straight pipe run is ~500 m. Larger values
    // almost always mean a unit slip (mm typed as m) — surface it, don't
    // silently emit a count of thousands of supports.
    final lengthErr = _length.text.isEmpty
        ? null
        : (lengthM <= 0
            ? _tr('Wpisz > 0', 'Enter > 0')
            : (lengthM > 500
                ? _tr('Maks. 500 m (sprawdź jednostki)',
                    'Max 500 m (check units)')
                : null));
    final lengthMm = lengthM * 1000;
    final supportCount = (lengthMm > 0 && lengthErr == null)
        ? (lengthMm / spacingMm).ceil() + 1
        : null;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        // ── DN selector ───────────────────────────────────────────────────
        Text(_tr('ŚREDNICA NOMINALNA', 'NOMINAL DIAMETER'),
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _dn,
          items: kSupportSpans
              .map((s) => DropdownMenuItem(
                    value: s.dn,
                    child: Text('DN${s.dn}  (NPS ${s.nps}")'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _dn = v ?? 50),
        ),
        const SizedBox(height: 14),

        // ── Service ───────────────────────────────────────────────────────
        Text(_tr('CZYNNIK', 'SERVICE'),
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Choice(
                label: _tr('Ciecz / pełna', 'Liquid / full'),
                selected: _waterFilled,
                onTap: () => setState(() => _waterFilled = true),
                color: _kBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Choice(
                label: _tr('Gaz / para', 'Gas / vapor'),
                selected: !_waterFilled,
                onTap: () => setState(() => _waterFilled = false),
                color: _kOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _insulated,
          onChanged: (v) => setState(() => _insulated = v),
          title: Text(
            _tr('Izolacja ≥ 50 mm', 'Insulation ≥ 50 mm'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            _tr('Zmniejsza rozstaw o 12 %', 'Reduces spacing by 12 %'),
            style: const TextStyle(fontSize: 11, color: _kMuted),
          ),
        ),
        const SizedBox(height: 14),

        // ── Optional length ───────────────────────────────────────────────
        Text(_tr('DŁUGOŚĆ LINII (opcjonalnie)', 'LINE LENGTH (optional)'),
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        TextField(
          controller: _length,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          ],
          decoration: InputDecoration(
            labelText: _tr('Długość prostego odcinka', 'Straight run length'),
            suffixText: 'm',
            errorText: lengthErr,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),

        // ── RESULT ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(_tr('Maks. rozstaw', 'Max. spacing'),
                      style: const TextStyle(color: _kSec, fontSize: 13)),
                  const Spacer(),
                  _CopyValue(
                    value: spacingMm.toString(),
                    label: 'DN$_dn ${_waterFilled ? "water" : "vapor"}',
                    suffix: ' mm',
                    color: _kOrange,
                    big: true,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _tr(
                  '≈ ${(spacingMm / 1000).toStringAsFixed(1)} m',
                  '≈ ${(spacingMm / 1000).toStringAsFixed(1)} m',
                ),
                style: const TextStyle(color: _kMuted, fontSize: 12),
              ),
              if (supportCount != null) ...[
                const Divider(height: 18, color: _kBorder),
                Row(
                  children: [
                    Text(_tr('Liczba podpór na linii', 'Supports on the run'),
                        style: const TextStyle(color: _kSec, fontSize: 13)),
                    const Spacer(),
                    _CopyValue(
                      value: supportCount.toString(),
                      label: 'supports',
                      suffix: ' szt.',
                      color: _kGreen,
                      big: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(
                      '${lengthM.toStringAsFixed(1)} m ÷ '
                          '${(spacingMm / 1000).toStringAsFixed(1)} m + 1 (pierwsza)',
                      '${lengthM.toStringAsFixed(1)} m ÷ '
                          '${(spacingMm / 1000).toStringAsFixed(1)} m + 1 (start)'),
                  style: const TextStyle(color: _kMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: _kBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr(
                    'Wartości referencyjne MSS SP-69 dla rury stalowej. '
                    'Wiążący rozstaw projektowy podaje stress engineer.',
                    'Reference values per MSS SP-69 for steel pipe. The binding '
                    'spacing is set by the project stress engineer.',
                  ),
                  style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : _kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? color : _kSec,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CopyValue extends StatelessWidget {
  final String value;
  final String label;
  final String suffix;
  final Color color;
  final bool big;
  const _CopyValue({
    required this.value,
    required this.label,
    required this.suffix,
    required this.color,
    this.big = false,
  });
  @override
  Widget build(BuildContext context) {
    return CopyOnLongPress(
      value: value,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: big ? 22 : 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3)),
          Text(suffix,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── TABLE ──────────────────────────────────────────────────────────────────

class _TableTab extends StatelessWidget {
  const _TableTab();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              const SizedBox(width: 70,
                  child: Text('DN / NPS',
                      style: TextStyle(
                          color: _kMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800))),
              Expanded(
                child: Text('GAZ / PARA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              Expanded(
                child: Text('CIECZ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            itemCount: kSupportSpans.length,
            itemBuilder: (_, i) {
              final s = kSupportSpans[i];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DN${s.dn}',
                              style: const TextStyle(
                                  color: Color(0xFFE8ECF0),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          Text('${s.nps}"',
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    _Cell(value: s.vaporMm, color: _kOrange,
                        label: 'DN${s.dn} vapor'),
                    _Cell(value: s.waterMm, color: _kBlue,
                        label: 'DN${s.dn} water'),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final int value;
  final Color color;
  final String label;
  const _Cell({required this.value, required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CopyOnLongPress(
        value: value.toString(),
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text('$value mm',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Text('${(value / 1000).toStringAsFixed(1)} m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _kSec, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── TYPES ──────────────────────────────────────────────────────────────────

class _TypesTab extends StatelessWidget {
  const _TypesTab();
  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: kSupportTypes.map((t) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kOrange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_iconFor(t.role), size: 20, color: _kOrange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isPl ? t.namePl : t.nameEn,
                      style: const TextStyle(
                          color: Color(0xFFE8ECF0),
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isPl ? t.descPl : t.descEn,
                style: const TextStyle(color: _kSec, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 14, color: _kBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isPl ? t.wherePl : t.whereEn,
                      style: const TextStyle(
                          color: _kMuted, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _iconFor(SupportRole r) {
    switch (r) {
      case SupportRole.anchor: return Icons.anchor;
      case SupportRole.guide:  return Icons.swap_horiz;
      case SupportRole.rest:   return Icons.crop_landscape;
      case SupportRole.hanger: return Icons.vertical_align_top;
      case SupportRole.spring: return Icons.expand;
      case SupportRole.uBolt:  return Icons.u_turn_left;
    }
  }
}

// ─── RULES ──────────────────────────────────────────────────────────────────

class _RulesTab extends StatelessWidget {
  const _RulesTab();
  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Text(
          context.tr(
            pl: 'Zasady umieszczania podpór, na które patrzy odbiorca:',
            en: 'Support placement rules a QA inspector looks for:',
          ),
          style: const TextStyle(color: _kSec, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        ...kPlacementRules.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24, height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: _kOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isPl ? r.pl : r.en,
                    style: const TextStyle(
                        color: Color(0xFFE8ECF0),
                        fontSize: 13,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kRed.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(
                    pl: 'Te zasady to dobre praktyki — wiążący rozkład podpór '
                        'jest na rysunku konstrukcyjnym podpór (support drawing) '
                        'i w raporcie ze stress analizy.',
                    en: 'These are best-practice rules — the binding support '
                        'layout is on the support drawing and in the stress-analysis '
                        'report.',
                  ),
                  style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
