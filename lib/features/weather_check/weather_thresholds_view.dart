// Ustawienia progów „Warunków do spawania”: wartości z norm (domyślne,
// konserwatywne) albo ze specyfikacji projektu. Zwraca nowe progi przez
// Navigator.pop; zapis robi ekran główny.

import 'package:flutter/material.dart';

import '../../domain/welding/weather_conditions.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart';

class WeatherThresholdsView extends StatefulWidget {
  const WeatherThresholdsView({super.key, required this.initial});

  final WeatherThresholds initial;

  @override
  State<WeatherThresholdsView> createState() => _WeatherThresholdsViewState();
}

/// Opis jednego pola progu.
class _Spec {
  const _Spec({
    required this.id,
    required this.labelPl,
    required this.labelEn,
    required this.unit,
    required this.def,
    required this.get,
    required this.basis,
    required this.valid,
    this.signed = false,
  });

  final String id;
  final String labelPl;
  final String labelEn;
  final String unit;
  final double def;
  final double Function(WeatherThresholds) get;
  final WeatherBasis basis;
  final bool Function(double) valid;
  final bool signed;
}

bool _temp(double v) => v >= -60 && v <= 400;
bool _wind(double v) => v > 0 && v <= 60;

final List<_Spec> _specs = [
  _Spec(
    id: 'minAmbientC',
    labelPl: 'Min. temperatura przy złączu',
    labelEn: 'Min. temperature at the joint',
    unit: '°C',
    def: WeatherThresholds.kDefaultMinAmbientC,
    get: (t) => t.minAmbientC,
    basis: kBasisAwsAmbient,
    valid: _temp,
    signed: true,
  ),
  _Spec(
    id: 'coldBaseMetalC',
    labelPl: 'Stal węglowa: „zimna” poniżej',
    labelEn: 'Carbon steel: “cold” below',
    unit: '°C',
    def: WeatherThresholds.kDefaultColdBaseMetalC,
    get: (t) => t.coldBaseMetalC,
    basis: kBasisAwsColdPreheat,
    valid: _temp,
    signed: true,
  ),
  _Spec(
    id: 'coldPreheatC',
    labelPl: 'Zimną stal węglową podgrzać do',
    labelEn: 'Preheat cold carbon steel to',
    unit: '°C',
    def: WeatherThresholds.kDefaultColdPreheatC,
    get: (t) => t.coldPreheatC,
    basis: kBasisAwsColdPreheat,
    valid: _temp,
    signed: true,
  ),
  _Spec(
    id: 'minMaterialC',
    labelPl: 'Min. temperatura materiału (każdy)',
    labelEn: 'Min. base metal temperature (any)',
    unit: '°C',
    def: WeatherThresholds.kDefaultMinMaterialC,
    get: (t) => t.minMaterialC,
    basis: kBasisB313MinTemp,
    valid: _temp,
    signed: true,
  ),
  _Spec(
    id: 'dewMarginK',
    labelPl: 'Zapas nad punktem rosy',
    labelEn: 'Margin above dew point',
    unit: 'K',
    def: WeatherThresholds.kDefaultDewMarginK,
    get: (t) => t.dewMarginK,
    basis: kBasisIso8502,
    valid: (v) => v >= 0 && v <= 30,
  ),
  _Spec(
    id: 'maxWindGasMs',
    labelPl: 'Maks. wiatr — procesy gazowe',
    labelEn: 'Max. wind — gas-shielded processes',
    unit: 'm/s',
    def: WeatherThresholds.kDefaultMaxWindGasMs,
    get: (t) => t.maxWindGasMs,
    basis: kBasisAwsWindGas,
    valid: _wind,
  ),
  _Spec(
    id: 'maxWindAnyMs',
    labelPl: 'Silny wiatr — każdy proces',
    labelEn: 'Strong wind — any process',
    unit: 'm/s',
    def: WeatherThresholds.kDefaultMaxWindAnyMs,
    get: (t) => t.maxWindAnyMs,
    basis: kBasisHighWind,
    valid: _wind,
  ),
];

class _WeatherThresholdsViewState extends State<WeatherThresholdsView> {
  late final Map<String, TextEditingController> _c = {
    for (final s in _specs)
      s.id: TextEditingController(text: _text(s.get(widget.initial))),
  };

  bool get _en => context.language == AppLanguage.en;

  String _text(double v) {
    var s =
        weatherNum(v, decimals: 1, english: AppLanguageController.isEnglish);
    if (s.endsWith(',0') || s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _value(_Spec s) {
    final v = parseDecimal(_c[s.id]!.text);
    return v != null && s.valid(v) ? v : null;
  }

  WeatherThresholds? get _result {
    final v = {for (final s in _specs) s.id: _value(s)};
    if (v.values.any((x) => x == null)) return null;
    return WeatherThresholds(
      minAmbientC: v['minAmbientC']!,
      coldBaseMetalC: v['coldBaseMetalC']!,
      coldPreheatC: v['coldPreheatC']!,
      minMaterialC: v['minMaterialC']!,
      dewMarginK: v['dewMarginK']!,
      maxWindGasMs: v['maxWindGasMs']!,
      maxWindAnyMs: v['maxWindAnyMs']!,
    );
  }

  void _restore() {
    setState(() {
      for (final s in _specs) {
        _c[s.id]!.text = _text(s.def);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
          pl: 'Przywrócono wartości domyślne — zapisz, żeby zastosować.',
          en: 'Defaults restored — save to apply.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Ustawienia progów', en: 'Thresholds')),
      ),
      body: ListView(
        key: const ValueKey('wx-th-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteNotice(
            text: context.tr(
                pl: 'Domyślne progi to najostrzejsze wartości z norm opisanych '
                    'przy polach. Zmień je, jeśli specyfikacja projektu lub '
                    'WPS mówi inaczej — każdy zapis i PDF pokaże, że progi '
                    'różnią się od domyślnych.',
                en: 'The defaults are the strictest values from the codes '
                    'quoted under each field. Change them if the project '
                    'specification or WPS says otherwise — every saved check '
                    'and PDF will show that the thresholds differ from the '
                    'defaults.'),
          ),
          for (final s in _specs) _field(s),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('wx-th-restore'),
                onPressed: _restore,
                icon: const Icon(Icons.restart_alt),
                label: Text(context.tr(
                    pl: 'Przywróć domyślne', en: 'Restore defaults')),
              ),
              ElevatedButton.icon(
                key: const ValueKey('wx-th-save'),
                onPressed: result == null
                    ? null
                    : () => Navigator.of(context).pop(result),
                icon: const Icon(Icons.check),
                label: Text(context.tr(pl: 'Zapisz', en: 'Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(_Spec s) {
    final c = _c[s.id]!;
    final raw = c.text.trim();
    final v = parseDecimal(raw);
    final error = raw.isEmpty
        ? context.tr(pl: 'Wpisz wartość', en: 'Enter a value')
        : v == null
            ? context.tr(pl: 'Wpisz liczbę', en: 'Enter a number')
            : !s.valid(v)
                ? context.tr(pl: 'Wartość spoza zakresu', en: 'Out of range')
                : null;
    final extra = s.id == 'maxWindGasMs' || s.id == 'maxWindAnyMs'
        ? (v == null
            ? ''
            : ' = ${weatherNum(msToKmh(v), decimals: 0, english: _en)} km/h')
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: ValueKey('wx-th-${s.id}'),
        controller: c,
        keyboardType: numberKeyboard(signed: s.signed),
        inputFormatters: numberInputFormatters(signed: s.signed),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: _en ? s.labelEn : s.labelPl,
          suffixText: s.unit,
          errorText: error,
          helperText: '${context.tr(pl: 'Domyślnie', en: 'Default')} '
              '${weatherNum(s.def, decimals: s.def == s.def.roundToDouble() ? 0 : 1, english: _en)} '
              '${s.unit}$extra · ${s.basis.text(_en)}',
          helperMaxLines: 6,
          helperStyle: const TextStyle(fontSize: 12, color: kTextMut),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
