// Zakładka „Koszty": stawki, ceny materiałów i mediów, NDT, narzut, zysk,
// VAT i założenia procesów — wszystko zapisane w TEJ wycenie.

import 'package:flutter/material.dart';

import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../services/quote_export.dart' show processesUsed;
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import 'hourly_rate_page.dart';
import 'quote_edit_page.dart' show QuoteChanged;
import 'quote_widgets.dart';

class QuoteCostsTab extends StatefulWidget {
  final WeldQuote quote;
  final QuoteSettings settings;
  final QuoteChanged onChanged;
  final ValueChanged<QuoteSettings> onSettingsChanged;

  /// Do testów.
  final QuoteSettingsStore store;

  const QuoteCostsTab({
    super.key,
    required this.quote,
    required this.settings,
    required this.onChanged,
    required this.onSettingsChanged,
    this.store = const QuoteSettingsStore(),
  });

  @override
  State<QuoteCostsTab> createState() => _QuoteCostsTabState();
}

class _QuoteCostsTabState extends State<QuoteCostsTab>
    with AutomaticKeepAliveClientMixin {
  /// Zmieniany przy podmianie stawek z zewnątrz — pola dostają nowe klucze
  /// i pokazują nowe wartości.
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  WeldQuote get q => widget.quote;
  QuoteRates get r => widget.quote.rates;

  void _rates(QuoteRates next) => widget.onChanged(q.copyWith(rates: next));

  Key _k(String id) => ValueKey('cost-$id-$_gen');

  String? _nonNegative(double? v) => v != null && v < 0
      ? context.tr(pl: 'Nie może być ujemna', en: 'Cannot be negative')
      : null;

  Widget _money(String id, String label, double value, ValueChanged<double> set,
          {String unit = 'zł'}) =>
      QuoteNumberField(
        key: _k(id),
        label: label,
        value: value,
        unit: unit,
        validate: _nonNegative,
        onChanged: (v) {
          if (v != null && v >= 0) set(v);
        },
      );

  Future<void> _pickHourlyRate() async {
    final rate = await Navigator.of(context).push<double>(
      MaterialPageRoute(builder: (_) => const HourlyRatePage(pickMode: true)),
    );
    if (rate == null || !mounted) return;
    setState(() => _gen++);
    _rates(r.copyWith(welderRate: rate));
  }

  Future<void> _saveAsMine() async {
    final next = widget.settings
        .copyWith(baseRates: r.copyWith(fillerPrices: const {}))
        .withFillerPrices(q.material, r.fillerPrices);
    await widget.store.save(next);
    widget.onSettingsChanged(next);
    Haptic.saved();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Zapamiętano — nowe wyceny wystartują z tymi stawkami.',
            en: 'Saved — new quotes will start with these rates.')),
      ));
  }

  Future<void> _loadMine() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title:
            Text(context.tr(pl: 'Wczytać moje stawki?', en: 'Load my rates?')),
        content: Text(context.tr(
            pl: 'Stawki, ceny, NDT, narzut, zysk i VAT tej wyceny zostaną '
                'zastąpione zapamiętanymi. Spoiny zostają.',
            en: 'Rates, prices, NDT, overhead, profit and VAT of this quote '
                'will be replaced with your saved ones. The welds stay.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(context.tr(pl: 'Wczytaj', en: 'Load'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _gen++);
    _rates(widget.settings.ratesFor(q.material));
  }

  Widget _profileEditor(QuoteProcess p) {
    final prof = r.profileOf(p);
    final def = kDefaultProcessProfiles[p]!;
    void set(ProcessProfile next) {
      if (!next.isValid) return;
      _rates(r.copyWith(profiles: {...r.profiles, p: next}));
    }

    String? range(double? v, double min, double max) =>
        v == null || v < min || v > max
            ? context.tr(
                pl: 'Zakres ${numText(min)}–${numText(max)}',
                en: 'Range ${numText(min)}–${numText(max)}')
            : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: kText)),
              ),
              if (prof != def)
                TextButton(
                  key: ValueKey('reset-${p.code}'),
                  onPressed: () {
                    setState(() => _gen++);
                    _rates(r.copyWith(profiles: {...r.profiles}..remove(p)));
                  },
                  child: Text(context.tr(pl: 'Typowe', en: 'Typical')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FieldPair(
            left: QuoteNumberField(
              key: _k('dep-${p.code}'),
              label:
                  context.tr(pl: 'Wydajność stapiania', en: 'Deposition rate'),
              unit: 'kg/h',
              value: prof.depositionKgH,
              validate: (v) => range(v, 0.05, 30),
              onChanged: (v) {
                if (v != null && v >= 0.05 && v <= 30) {
                  set(prof.copyWith(depositionKgH: v));
                }
              },
            ),
            right: QuoteNumberField(
              key: _k('eff-${p.code}'),
              label: context.tr(pl: 'Uzysk spoiwa', en: 'Filler efficiency'),
              unit: '%',
              value: prof.efficiency * 100,
              decimals: 0,
              validate: (v) => range(v, 30, 100),
              onChanged: (v) {
                if (v != null && v >= 30 && v <= 100) {
                  set(prof.copyWith(efficiency: v / 100));
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          FieldPair(
            left: QuoteNumberField(
              key: _k('duty-${p.code}'),
              label: context.tr(pl: 'Jarzenie łuku', en: 'Arc duty'),
              unit: '%',
              value: prof.dutyCycle * 100,
              decimals: 0,
              helper: context.tr(
                  pl: 'Część czasu spawania z łukiem',
                  en: 'Share of welding time with the arc on'),
              validate: (v) => range(v, 5, 100),
              onChanged: (v) {
                if (v != null && v >= 5 && v <= 100) {
                  set(prof.copyWith(dutyCycle: v / 100));
                }
              },
            ),
            right: p.gasKind == QuoteGasKind.none
                ? QuoteNumberField(
                    key: _k('kw-${p.code}'),
                    label: context.tr(pl: 'Moc łuku', en: 'Arc power'),
                    unit: 'kW',
                    value: prof.arcKw,
                    validate: (v) => range(v, 0, 100),
                    onChanged: (v) {
                      if (v != null && v >= 0 && v <= 100) {
                        set(prof.copyWith(arcKw: v));
                      }
                    },
                  )
                : QuoteNumberField(
                    key: _k('gas-${p.code}'),
                    label: context.tr(pl: 'Gaz osłonowy', en: 'Shielding gas'),
                    unit: 'L/min',
                    value: prof.gasLpm,
                    validate: (v) => range(v, 0, 60),
                    onChanged: (v) {
                      if (v != null && v >= 0 && v <= 60) {
                        set(prof.copyWith(gasLpm: v));
                      }
                    },
                  ),
          ),
          if (p.gasKind != QuoteGasKind.none) ...[
            const SizedBox(height: 10),
            QuoteNumberField(
              key: _k('kw-${p.code}'),
              label: context.tr(pl: 'Moc łuku U·I', en: 'Arc power U·I'),
              unit: 'kW',
              value: prof.arcKw,
              validate: (v) => range(v, 0, 100),
              onChanged: (v) {
                if (v != null && v >= 0 && v <= 100) {
                  set(prof.copyWith(arcKw: v));
                }
              },
            ),
          ],
          if (p == QuoteProcess.saw) ...[
            const SizedBox(height: 10),
            QuoteNumberField(
              key: _k('flux-${p.code}'),
              label:
                  context.tr(pl: 'Topnik na kg drutu', en: 'Flux per kg wire'),
              unit: 'kg/kg',
              value: prof.fluxRatio,
              validate: (v) => range(v, 0, 5),
              onChanged: (v) {
                if (v != null && v >= 0 && v <= 5) {
                  set(prof.copyWith(fluxRatio: v));
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final en = context.language == AppLanguage.en;
    final used = processesUsed(q).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final usesArgon = used.any((p) => p.gasKind == QuoteGasKind.argon);
    final usesMix = used.any((p) => p.gasKind == QuoteGasKind.mix);
    final usesSaw = used.contains(QuoteProcess.saw);

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        QuoteSection(
          title: context.tr(pl: 'Robocizna', en: 'Labour'),
          children: [
            FieldPair(
              left: _money(
                  'welder',
                  context.tr(pl: 'Stawka spawacza', en: 'Welder rate'),
                  r.welderRate,
                  (v) => _rates(r.copyWith(welderRate: v)),
                  unit: 'zł/h'),
              right: _money(
                  'fitter',
                  context.tr(pl: 'Stawka montera', en: 'Fitter rate'),
                  r.fitterRate,
                  (v) => _rates(r.copyWith(fitterRate: v)),
                  unit: 'zł/h'),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                  pl: 'Spawacz: czas spawania. Monter: fazowanie, ustawienie, sczepianie.',
                  en: 'Welder: welding time. Fitter: bevelling, fit-up, tacking.'),
              style: const TextStyle(fontSize: 11.5, color: kTextMut),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('calc-hourly-rate'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                onPressed: _pickHourlyRate,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: Text(context.tr(
                    pl: 'Policz, ile brać za godzinę',
                    en: 'Work out what to charge per hour')),
              ),
            ),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Spoiwo', en: 'Filler metal'),
          subtitle: context.tr(
              pl: 'Ceny netto za kg dla: ${en ? q.material.labelEn : q.material.labelPl}.',
              en: 'Net price per kg for: ${q.material.labelEn}.'),
          children: [
            for (final p in used) ...[
              _money(
                  'filler-${p.code}',
                  p.label,
                  r.fillerPriceOf(p),
                  (v) => _rates(
                      r.copyWith(fillerPrices: {...r.fillerPrices, p: v})),
                  unit: 'zł/kg'),
              const SizedBox(height: 10),
            ],
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Gazy i energia', en: 'Gases and power'),
          children: [
            if (usesArgon) ...[
              _money(
                  'argon',
                  context.tr(pl: 'Argon (TIG, MIG)', en: 'Argon (TIG, MIG)'),
                  r.argonPrice,
                  (v) => _rates(r.copyWith(argonPrice: v)),
                  unit: 'zł/m³'),
              const SizedBox(height: 10),
            ],
            if (usesMix) ...[
              _money(
                  'mix',
                  context.tr(
                      pl: 'Mieszanka M21 / CO₂ (MAG, FCAW)',
                      en: 'M21 mix / CO₂ (MAG, FCAW)'),
                  r.mixPrice,
                  (v) => _rates(r.copyWith(mixPrice: v)),
                  unit: 'zł/m³'),
              const SizedBox(height: 10),
            ],
            if (q.purge) ...[
              _money('purge', context.tr(pl: 'Gaz formujący', en: 'Purge gas'),
                  r.purgeGasPrice, (v) => _rates(r.copyWith(purgeGasPrice: v)),
                  unit: 'zł/m³'),
              const SizedBox(height: 10),
              FieldPair(
                left: QuoteNumberField(
                  key: _k('purge-len'),
                  label: context.tr(
                      pl: 'Odcinek między przegrodami',
                      en: 'Length between dams'),
                  unit: 'mm',
                  value: r.purgeLengthMm,
                  decimals: 0,
                  validate: _nonNegative,
                  onChanged: (v) {
                    if (v != null && v >= 0) {
                      _rates(r.copyWith(purgeLengthMm: v));
                    }
                  },
                ),
                right: QuoteNumberField(
                  key: _k('purge-ppm'),
                  label: context.tr(pl: 'Docelowe O₂', en: 'Target O₂'),
                  unit: 'ppm',
                  value: r.purgeTargetPpm,
                  decimals: 0,
                  validate: (v) => v != null && v <= 0
                      ? context.tr(pl: 'Więcej niż 0', en: 'Above 0')
                      : null,
                  onChanged: (v) {
                    if (v != null && v > 0) {
                      _rates(r.copyWith(purgeTargetPpm: v));
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (usesSaw) ...[
              _money('flux', context.tr(pl: 'Topnik SAW', en: 'SAW flux'),
                  r.fluxPrice, (v) => _rates(r.copyWith(fluxPrice: v)),
                  unit: 'zł/kg'),
              const SizedBox(height: 10),
            ],
            FieldPair(
              left: _money(
                  'kwh',
                  context.tr(pl: 'Energia', en: 'Electricity'),
                  r.electricityPrice,
                  (v) => _rates(r.copyWith(electricityPrice: v)),
                  unit: 'zł/kWh'),
              right: QuoteNumberField(
                key: _k('cyl'),
                label: context.tr(pl: 'Gaz w butli', en: 'Gas per cylinder'),
                unit: 'm³',
                value: r.cylinderM3,
                helper: context.tr(
                    pl: '50 L × 200 bar ≈ 10 m³', en: '50 L × 200 bar ≈ 10 m³'),
                validate: (v) => v != null && v <= 0
                    ? context.tr(pl: 'Więcej niż 0', en: 'Above 0')
                    : null,
                onChanged: (v) {
                  if (v != null && v > 0) _rates(r.copyWith(cylinderM3: v));
                },
              ),
            ),
          ],
        ),
        QuoteSection(
          title: context.tr(
              pl: 'Badania nieniszczące', en: 'Non-destructive testing'),
          subtitle: context.tr(
              pl: 'Procent złączy do badania (zaokrąglany w górę) i cena za złącze.',
              en: 'Share of joints tested (rounded up) and price per joint.'),
          children: [
            for (final m in NdtMethod.values) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(m.code,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: kText)),
                    ),
                  ),
                  Expanded(
                    child: QuoteNumberField(
                      key: _k('ndt-pct-${m.code}'),
                      label: en ? m.labelEn : m.labelPl,
                      unit: '%',
                      value: r.ndtOf(m).percent,
                      decimals: 1,
                      validate: (v) =>
                          v != null && (v < 0 || v > 100) ? '0–100' : null,
                      onChanged: (v) {
                        if (v != null && v >= 0 && v <= 100) {
                          _rates(r.copyWith(ndt: {
                            ...r.ndt,
                            m: r.ndtOf(m).copyWith(percent: v),
                          }));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: QuoteNumberField(
                      key: _k('ndt-price-${m.code}'),
                      label: context.tr(pl: 'za złącze', en: 'per joint'),
                      unit: 'zł',
                      value: r.ndtOf(m).pricePerJoint,
                      validate: _nonNegative,
                      onChanged: (v) {
                        if (v != null && v >= 0) {
                          _rates(r.copyWith(ndt: {
                            ...r.ndt,
                            m: r.ndtOf(m).copyWith(pricePerJoint: v),
                          }));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
        QuoteSection(
          title:
              context.tr(pl: 'Narzut, zysk, VAT', en: 'Overhead, profit, VAT'),
          children: [
            FieldPair(
              left: QuoteNumberField(
                key: _k('overhead'),
                label: context.tr(pl: 'Koszty ogólne', en: 'Overhead'),
                unit: '%',
                value: r.overheadPct,
                decimals: 1,
                helper: context.tr(
                    pl: 'Od kosztów bezpośrednich: ZUS, auto, sprzęt, biuro',
                    en: 'On direct costs: insurance, van, equipment, office'),
                validate: (v) =>
                    v != null && (v < 0 || v > 300) ? '0–300' : null,
                onChanged: (v) {
                  if (v != null && v >= 0 && v <= 300) {
                    _rates(r.copyWith(overheadPct: v));
                  }
                },
              ),
              right: QuoteNumberField(
                key: _k('margin'),
                label: context.tr(pl: 'Zysk', en: 'Profit'),
                unit: '%',
                value: r.marginPct,
                decimals: 1,
                helper: context.tr(
                    pl: 'Od kosztów z kosztami ogólnymi',
                    en: 'On costs including overhead'),
                validate: (v) =>
                    v != null && (v < 0 || v > 300) ? '0–300' : null,
                onChanged: (v) {
                  if (v != null && v >= 0 && v <= 300) {
                    _rates(r.copyWith(marginPct: v));
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in QuoteVat.values)
                  ChoiceChip(
                    key: ValueKey('vat-${v.code}'),
                    label: Text('VAT ${v.label}'),
                    selected: r.vat == v,
                    onSelected: (_) => _rates(r.copyWith(vat: v)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                  pl: '„np." — usługa dla firmy z innego kraju UE (odwrotne '
                      'obciążenie u nabywcy); „zw." — zwolnienie podmiotowe. '
                      'Stawkę potwierdź z księgowością.',
                  en: '"np." — service for a business in another EU country '
                      '(reverse charge); "zw." — small-business exemption. '
                      'Confirm the rate with your accountant.'),
              style: const TextStyle(fontSize: 11.5, color: kTextMut),
            ),
            const SizedBox(height: 12),
            QuoteNumberField(
              key: _k('di-rate'),
              allowEmpty: true,
              label: context.tr(
                  pl: 'Rynkowa stawka za cal-średnicę (opcjonalnie)',
                  en: 'Market rate per dia-inch (optional)'),
              unit: 'zł/DI',
              value: r.marketDiRate == 0 ? null : r.marketDiRate,
              helper: context.tr(
                  pl: 'Do porównania w zakładce Wynik — nie zmienia ceny.',
                  en: 'For comparison on the Result tab — does not change the price.'),
              validate: _nonNegative,
              onChanged: (v) {
                if (v == null || v >= 0) {
                  _rates(r.copyWith(marketDiRate: v ?? 0));
                }
              },
            ),
          ],
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: const ValueKey('profiles'),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              context.tr(pl: 'Założenia procesów', en: 'Process assumptions'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              context.tr(
                  pl: 'Wydajność, uzysk, jarzenie łuku. Skalibruj na swojej brygadzie.',
                  en: 'Deposition, efficiency, arc duty. Calibrate on your crew.'),
              style: const TextStyle(fontSize: 12, color: kTextMut),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            children: [for (final p in used) _profileEditor(p)],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('load-my-rates'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget)),
                onPressed: _loadMine,
                icon: const Icon(Icons.download_outlined),
                label: Text(context.tr(pl: 'Wczytaj moje', en: 'Load mine')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const ValueKey('save-my-rates'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget)),
                onPressed: _saveAsMine,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(
                    context.tr(pl: 'Zapamiętaj jako moje', en: 'Save as mine')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
