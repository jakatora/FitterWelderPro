// „Moje stawki i firma": szablon nowych wycen (stawki, ceny, VAT, dane
// firmy do nagłówka oferty, warunki). Nie zmienia wycen już zapisanych.

import 'package:flutter/material.dart';

import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import 'hourly_rate_page.dart';
import 'quote_widgets.dart';

class QuoteSettingsPage extends StatefulWidget {
  final QuoteSettings settings;
  final QuoteSettingsStore store;

  const QuoteSettingsPage({
    super.key,
    required this.settings,
    this.store = const QuoteSettingsStore(),
  });

  @override
  State<QuoteSettingsPage> createState() => _QuoteSettingsPageState();
}

class _QuoteSettingsPageState extends State<QuoteSettingsPage> {
  late QuoteSettings _s = widget.settings;
  late final _name = TextEditingController(text: _s.company.name);
  late final _nip = TextEditingController(text: _s.company.taxId);
  late final _addr = TextEditingController(text: _s.company.address);
  late final _phone = TextEditingController(text: _s.company.phone);
  late final _email = TextEditingController(text: _s.company.email);
  late final _person = TextEditingController(text: _s.company.person);
  late final _terms = TextEditingController(text: _s.terms);
  bool _dirty = false;

  /// Zmieniany, gdy stawka przychodzi z kalkulatora — pola dostają nowe
  /// klucze i pokazują nową wartość.
  int _gen = 0;

  @override
  void dispose() {
    for (final c in [_name, _nip, _addr, _phone, _email, _person, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  QuoteRates get _r => _s.baseRates;

  void _set(QuoteSettings s) => setState(() {
        _s = s;
        _dirty = true;
      });

  void _rates(QuoteRates r) => _set(_s.copyWith(baseRates: r));

  Future<void> _save() async {
    final s = _s.copyWith(
      company: QuoteCompany(
        name: _name.text.trim(),
        taxId: _nip.text.trim(),
        address: _addr.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        person: _person.text.trim(),
      ),
      terms: _terms.text.trim(),
    );
    await widget.store.save(s);
    Haptic.saved();
    if (!mounted) return;
    Navigator.of(context).pop(s);
  }

  Widget _text(TextEditingController c, String label,
          {TextInputType? type, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: type,
          minLines: 1,
          maxLines: maxLines,
          onChanged: (_) => _dirty = true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _num(String id, String label, double value, ValueChanged<double> set,
          {String? unit, double max = 1e9}) =>
      QuoteNumberField(
        key: ValueKey('set-$id-$_gen'),
        label: label,
        value: value,
        unit: unit,
        validate: (v) => v != null && (v < 0 || v > max)
            ? context.tr(pl: 'Poza zakresem', en: 'Out of range')
            : null,
        onChanged: (v) {
          if (v != null && v >= 0 && v <= max) set(v);
        },
      );

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(
                context.tr(pl: 'Nie zapisano zmian', en: 'Unsaved changes')),
            content: Text(context.tr(
                pl: 'Wyjść bez zapisywania?', en: 'Leave without saving?')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: Text(context.tr(pl: 'Zostań', en: 'Stay'))),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: Text(context.tr(pl: 'Wyjdź', en: 'Leave'))),
            ],
          ),
        );
        if (discard == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(
              pl: 'Moje stawki i firma', en: 'My rates and company')),
          actions: [
            TextButton(
              key: const ValueKey('settings-save'),
              onPressed: _save,
              child: Text(context.tr(pl: 'Zapisz', en: 'Save'),
                  style: const TextStyle(
                      color: kArc, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            Text(
              context.tr(
                  pl: 'To szablon NOWYCH wycen. Zapisane wyceny mają własną kopię stawek.',
                  en: 'This is the template for NEW quotes. Saved quotes keep their own copy of the rates.'),
              style: const TextStyle(fontSize: 12.5, color: kTextSec),
            ),
            const SizedBox(height: 12),
            QuoteSection(
              title: context.tr(
                  pl: 'Firma (nagłówek oferty)', en: 'Company (quote header)'),
              children: [
                _text(_name, context.tr(pl: 'Nazwa firmy', en: 'Company name')),
                _text(_nip, context.tr(pl: 'NIP', en: 'VAT ID')),
                _text(_addr, context.tr(pl: 'Adres', en: 'Address'),
                    maxLines: 2),
                _text(_phone, context.tr(pl: 'Telefon', en: 'Phone'),
                    type: TextInputType.phone),
                _text(_email, 'E-mail', type: TextInputType.emailAddress),
                _text(
                    _person,
                    context.tr(
                        pl: 'Osoba kontaktowa / wystawił',
                        en: 'Contact / issued by')),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Robocizna', en: 'Labour'),
              children: [
                FieldPair(
                  left: _num('welder', context.tr(pl: 'Spawacz', en: 'Welder'),
                      _r.welderRate, (v) => _rates(_r.copyWith(welderRate: v)),
                      unit: 'zł/h'),
                  right: _num('fitter', context.tr(pl: 'Monter', en: 'Fitter'),
                      _r.fitterRate, (v) => _rates(_r.copyWith(fitterRate: v)),
                      unit: 'zł/h'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                    onPressed: () async {
                      final rate = await Navigator.of(context).push<double>(
                        MaterialPageRoute(
                            builder: (_) =>
                                const HourlyRatePage(pickMode: true)),
                      );
                      if (rate == null || !mounted) return;
                      _gen++;
                      _rates(_r.copyWith(welderRate: rate));
                    },
                    icon: const Icon(Icons.calculate_outlined, size: 18),
                    label: Text(context.tr(
                        pl: 'Policz, ile brać za godzinę',
                        en: 'Work out what to charge per hour')),
                  ),
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Gazy i energia', en: 'Gases and power'),
              children: [
                FieldPair(
                  left: _num('argon', 'Argon', _r.argonPrice,
                      (v) => _rates(_r.copyWith(argonPrice: v)),
                      unit: 'zł/m³'),
                  right: _num('mix', 'M21 / CO₂', _r.mixPrice,
                      (v) => _rates(_r.copyWith(mixPrice: v)),
                      unit: 'zł/m³'),
                ),
                const SizedBox(height: 10),
                FieldPair(
                  left: _num(
                      'purge',
                      context.tr(pl: 'Gaz formujący', en: 'Purge gas'),
                      _r.purgeGasPrice,
                      (v) => _rates(_r.copyWith(purgeGasPrice: v)),
                      unit: 'zł/m³'),
                  right: _num(
                      'kwh',
                      context.tr(pl: 'Energia', en: 'Electricity'),
                      _r.electricityPrice,
                      (v) => _rates(_r.copyWith(electricityPrice: v)),
                      unit: 'zł/kWh'),
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(
                  pl: 'Ceny spoiw (zł/kg netto)',
                  en: 'Filler prices (net per kg)'),
              children: [
                for (final m in QuoteMaterial.values)
                  ExpansionTile(
                    key: ValueKey('filler-${m.code}'),
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(en ? m.labelEn : m.labelPl),
                    children: [
                      for (final p in QuoteProcess.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _num(
                            'filler-${m.code}-${p.code}',
                            p.label,
                            _s.ratesFor(m).fillerPriceOf(p),
                            (v) => _set(_s.withFillerPrices(m, {
                              ..._s.ratesFor(m).fillerPrices,
                              p: v,
                            })),
                            unit: 'zł/kg',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            QuoteSection(
              title: context.tr(
                  pl: 'Narzut, zysk, VAT', en: 'Overhead, profit, VAT'),
              children: [
                FieldPair(
                  left: _num(
                      'overhead',
                      context.tr(pl: 'Koszty ogólne', en: 'Overhead'),
                      _r.overheadPct,
                      (v) => _rates(_r.copyWith(overheadPct: v)),
                      unit: '%',
                      max: 300),
                  right: _num('margin', context.tr(pl: 'Zysk', en: 'Profit'),
                      _r.marginPct, (v) => _rates(_r.copyWith(marginPct: v)),
                      unit: '%', max: 300),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in QuoteVat.values)
                      ChoiceChip(
                        label: Text('VAT ${v.label}'),
                        selected: _r.vat == v,
                        onSelected: (_) => _rates(_r.copyWith(vat: v)),
                      ),
                  ],
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(
                  pl: 'Domyślnie w nowej wycenie',
                  en: 'Defaults for a new quote'),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in QuoteMaterial.values)
                      ChoiceChip(
                        label: Text(en ? m.labelEn : m.labelPl),
                        selected: _s.material == m,
                        onSelected: (_) => _set(_s.copyWith(material: m)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sc in kCommonSchemes)
                      ChoiceChip(
                        label: Text(sc.label),
                        selected: _s.scheme == sc,
                        onSelected: (_) => _set(_s.copyWith(scheme: sc)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final st in QuoteSite.values)
                      ChoiceChip(
                        label: Text(en ? st.labelEn : st.labelPl),
                        selected: _s.site == st,
                        onSelected: (_) => _set(_s.copyWith(site: st)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                QuoteNumberField(
                  key: const ValueKey('set-validity'),
                  label: context.tr(pl: 'Ważność oferty', en: 'Quote validity'),
                  unit: context.tr(pl: 'dni', en: 'days'),
                  value: _s.validityDays.toDouble(),
                  decimal: false,
                  decimals: 0,
                  onChanged: (v) {
                    if (v != null && v >= 1) {
                      _set(_s.copyWith(validityDays: v.round()));
                    }
                  },
                ),
              ],
            ),
            QuoteSection(
              title: context.tr(
                  pl: 'Warunki na ofercie', en: 'Terms on the quote'),
              children: [
                _text(
                  _terms,
                  context.tr(
                      pl: 'Np. płatność 14 dni od faktury; zaliczka 30%; materiał po stronie zamawiającego',
                      en: 'E.g. payment 14 days from invoice; 30% advance; material supplied by the client'),
                  maxLines: 6,
                ),
              ],
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(context.tr(pl: 'Zapisz', en: 'Save'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
