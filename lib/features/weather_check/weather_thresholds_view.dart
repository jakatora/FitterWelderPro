// Ustawienia progów „Warunków do spawania”: wartości z norm (domyślne,
// konserwatywne) albo ze specyfikacji projektu. Zwraca nowe progi przez
// Navigator.pop; zapis robi ekran główny.
//
// Zasady:
//  • pole pokazuje wartość z pełną precyzją (do 4 miejsc, bez zbędnych zer),
//    a NIEEDYTOWANE pole oddaje dokładnie tę samą liczbę, którą dostało —
//    otwarcie i „Zapisz” niczego nie zaokrąglają (2,26 nie staje się 2,3);
//  • walidacja zakresu i krzyżowa (podgrzanie ≥ próg „zimnej” stali,
//    minimum materiału ≥ minimum przy złączu, silny wiatr ≥ limit gazowy)
//    blokuje zapis z błędem przy polu;
//  • próg łagodniejszy od domyślnego (z norm) dostaje ostrzeżenie przy polu.

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

WeatherBasis _basis(String field) => switch (field) {
      ThresholdField.minAmbientC => kBasisAwsAmbient,
      ThresholdField.coldBaseMetalC ||
      ThresholdField.coldPreheatC =>
        kBasisAwsColdPreheat,
      ThresholdField.minMaterialC => kBasisB313MinTemp,
      ThresholdField.dewMarginK => kBasisIso8502,
      ThresholdField.maxWindGasMs => kBasisAwsWindGas,
      _ => kBasisHighWind,
    };

bool _signed(String field) => thresholdUnit(field) == '°C';

class _WeatherThresholdsViewState extends State<WeatherThresholdsView> {
  /// Wartości progów (dokładne double). Pole edytowane nadpisuje swoją
  /// wartość; nieedytowane zostają bit w bit takie jak [WeatherThresholdsView.initial].
  late final Map<String, double?> _values = {
    for (final f in ThresholdField.all) f: widget.initial.valueOf(f),
  };

  late final Map<String, TextEditingController> _c = {
    for (final f in ThresholdField.all)
      f: TextEditingController(text: _text(widget.initial.valueOf(f))),
  };

  bool get _en => context.language == AppLanguage.en;

  /// Pełna precyzja (do 4 miejsc) bez zbędnych zer.
  static String _text(double v) => weatherNumAuto(v,
      maxDecimals: 4, english: AppLanguageController.isEnglish);

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Progi z bieżących wartości (null, gdy któreś pole puste / nie liczba).
  WeatherThresholds? get _composed {
    if (_values.values.any((v) => v == null)) return null;
    return WeatherThresholds.defaults
        .withValues({for (final e in _values.entries) e.key: e.value!});
  }

  Map<String, ThresholdIssue> get _issues {
    final t = _composed;
    return t == null ? const {} : validateWeatherThresholds(t);
  }

  WeatherThresholds? get _result {
    final t = _composed;
    if (t == null || validateWeatherThresholds(t).isNotEmpty) return null;
    return t;
  }

  void _edited(String field) {
    setState(() => _values[field] = parseDecimal(_c[field]!.text));
  }

  void _restore() {
    setState(() {
      for (final f in ThresholdField.all) {
        final d = WeatherThresholds.defaults.valueOf(f);
        _values[f] = d;
        _c[f]!.text = _text(d);
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
    final issues = _issues;
    final looser =
        _composed == null ? const <String>[] : looserThanDefaults(_composed!);
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
                    'różnią się od domyślnych, a progi łagodniejsze od norm '
                    'dają przy werdykcie twarde ostrzeżenie.',
                en: 'The defaults are the strictest values from the codes '
                    'quoted under each field. Change them if the project '
                    'specification or WPS says otherwise — every saved check '
                    'and PDF will show that the thresholds differ from the '
                    'defaults, and thresholds looser than the codes put a hard '
                    'warning on the verdict.'),
          ),
          for (final f in ThresholdField.all)
            _field(f, issues[f], looser.contains(f)),
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

  String _issueText(ThresholdIssue i) => switch (i) {
        ThresholdIssue.outOfRange =>
          context.tr(pl: 'Wartość spoza zakresu', en: 'Out of range'),
        ThresholdIssue.preheatBelowColdThreshold => context.tr(
            pl: 'Nie niżej niż próg „zimnej” stali',
            en: 'Not below the “cold” steel threshold'),
        ThresholdIssue.materialBelowAmbient => context.tr(
            pl: 'Nie niżej niż min. temperatura przy złączu',
            en: 'Not below the min. temperature at the joint'),
        ThresholdIssue.strongWindBelowGas => context.tr(
            pl: 'Nie mniej niż limit dla procesów gazowych',
            en: 'Not below the gas-shielded limit'),
      };

  Widget _field(String f, ThresholdIssue? issue, bool looser) {
    final c = _c[f]!;
    final raw = c.text.trim();
    final v = _values[f];
    final error = raw.isEmpty
        ? context.tr(pl: 'Wpisz wartość', en: 'Enter a value')
        : v == null
            ? context.tr(pl: 'Wpisz liczbę', en: 'Enter a number')
            : issue != null
                ? _issueText(issue)
                : null;
    final def = WeatherThresholds.defaults.valueOf(f);
    final unit = thresholdUnit(f);
    final kmh = unit == 'm/s'
        ? ' ≈ ${weatherNumAuto(floorTo(msToKmh(v ?? def), 1), maxDecimals: 1, english: _en)} km/h'
        : '';
    final looserNote = looser
        ? context.tr(
            pl: ' · ŁAGODNIEJ niż norma!', en: ' · LOOSER than the code!')
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: ValueKey('wx-th-$f'),
        controller: c,
        keyboardType: numberKeyboard(signed: _signed(f)),
        inputFormatters: numberInputFormatters(signed: _signed(f)),
        onChanged: (_) => _edited(f),
        decoration: InputDecoration(
          labelText: thresholdLabel(f, english: _en),
          suffixText: unit,
          errorText: error,
          errorMaxLines: 3,
          helperText: '${context.tr(pl: 'Domyślnie', en: 'Default')} '
              '${weatherNumAuto(def, english: _en)} $unit$kmh$looserNote · '
              '${_basis(f).text(_en)}',
          helperMaxLines: 7,
          helperStyle:
              TextStyle(fontSize: 12, color: looser ? kFail : kTextMut),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
