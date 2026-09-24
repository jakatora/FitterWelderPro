import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/calculation_guide.dart';

/// Offline conversions; all four original categories remain available.
class QuickConverterScreen extends StatelessWidget {
  const QuickConverterScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
                context.tr(pl: 'Konwerter jednostek', en: 'Unit converter')),
            bottom: TabBar(isScrollable: true, tabs: [
              Tab(text: context.tr(pl: 'Długość', en: 'Length')),
              Tab(text: context.tr(pl: 'Temperatura', en: 'Temperature')),
              Tab(text: context.tr(pl: 'Ciśnienie', en: 'Pressure')),
              Tab(text: context.tr(pl: 'Przepływ gazu', en: 'Gas flow')),
            ]),
          ),
          body: const SafeArea(
              top: false,
              child: TabBarView(children: [
                _ConversionTab(kind: _Kind.length),
                _ConversionTab(kind: _Kind.temperature),
                _ConversionTab(kind: _Kind.pressure),
                _ConversionTab(kind: _Kind.flow),
              ])),
        ),
      );
}

enum _Kind { length, temperature, pressure, flow }

// Factors retained from the original converter. Reference:
// https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8
const _lengthFactors = {
  'mm': 1.0,
  'cm': 10.0,
  'm': 1000.0,
  'in': 25.4,
  'ft': 304.8
};
const _pressureFactors = {
  'bar': 1.0,
  'MPa': 10.0,
  'kPa': 0.01,
  'psi': 0.0689476,
  'atm': 1.01325
};
const _flowFactors = {
  'l/min': 1.0,
  'slpm': 1.0,
  'cfh': 0.4719474,
  'scfh': 0.4719474
};
const _temperatureFloors = {'°C': -273.15, '°F': -459.67, 'K': 0.0};
final _decimal = RegExp(r'^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$');

double? _parse(String text) {
  final value = text.trim();
  if (!_decimal.hasMatch(value)) return null;
  return double.tryParse(value.replaceAll(',', '.'));
}

String _fmt(double value) {
  // Preserve useful fractions at large dimensions and don't display a
  // small but nonzero measurement as zero.
  if (value != 0 && (value.abs() < .001 || value.abs() >= 1e9)) {
    return value.toStringAsExponential(6);
  }
  if (value.abs() < 1 && value != 0) {
    var formatted = value.toStringAsFixed(6);
    while (formatted.endsWith('0') &&
        formatted.length - formatted.indexOf('.') > 4) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }
  return (value == 0 ? 0.0 : value).toStringAsFixed(3);
}

String _label(String unit) => unit == 'in' ? 'in (")' : unit;

class _ConversionTab extends StatefulWidget {
  const _ConversionTab({required this.kind});
  final _Kind kind;
  @override
  State<_ConversionTab> createState() => _ConversionTabState();
}

class _ConversionTabState extends State<_ConversionTab>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  late String _src = _units.first;
  @override
  bool get wantKeepAlive => true;

  List<String> get _units => switch (widget.kind) {
        _Kind.length => _lengthFactors.keys.toList(),
        _Kind.temperature => _temperatureFloors.keys.toList(),
        _Kind.pressure => _pressureFactors.keys.toList(),
        _Kind.flow => _flowFactors.keys.toList(),
      };

  void _clear() {
    Haptic.tap();
    setState(() {
      _ctrl.clear();
      _src = _units.first;
    });
  }

  Map<String, double> _convert(double value) {
    if (widget.kind == _Kind.temperature) {
      // Source-scale floor avoids a negative rounding artifact at -459.67 F.
      // Converts temperatures, not differences between temperatures.
      final kelvin = switch (_src) {
        '°C' => value + 273.15,
        '°F' => (value + 459.67) / 1.8,
        _ => value,
      };
      return {'°C': kelvin - 273.15, '°F': kelvin * 1.8 - 459.67, 'K': kelvin};
    }
    final factors = switch (widget.kind) {
      _Kind.length => _lengthFactors,
      _Kind.pressure => _pressureFactors,
      _ => _flowFactors,
    };
    final base = value * factors[_src]!;
    return {
      for (final unit in factors.keys)
        if (widget.kind != _Kind.flow || _isStandard(unit) == _isStandard(_src))
          unit: base / factors[unit]!
    };
  }

  // Actual and standardized flow are different quantities. No implicit
  // l/min == slpm conversion without gas, pressure, temperature and reference data.
  // https://www.alicat.com/support/what-is-mass-flow/
  bool _isStandard(String unit) => unit == 'slpm' || unit == 'scfh';

  String? _error(double? value, Map<String, double> results) {
    if (_ctrl.text.trim().isEmpty) return null;
    if (value == null) {
      return context.tr(
          pl: 'Wpisz liczbę z jednym przecinkiem lub kropką, bez jednostki.',
          en: 'Enter a number with one decimal separator, without a unit.');
    }
    if (!value.isFinite || results.values.any((v) => !v.isFinite)) {
      return context.tr(
          pl: 'Wartość poza zakresem. Sprawdź liczbę i jednostkę.',
          en: 'Value out of range. Check the number and unit.');
    }
    if (widget.kind == _Kind.temperature) {
      if (value < _temperatureFloors[_src]!) {
        return context.tr(
            pl: 'Temperatura nie może być niższa niż ${_temperatureFloors[_src]} $_src (zero absolutne).',
            en: 'Temperature cannot be below ${_temperatureFloors[_src]} $_src (absolute zero).');
      }
    } else if (value < 0) {
      return context.tr(
          pl: 'Ten przelicznik obsługuje wartości od 0. Sprawdź znak.',
          en: 'This converter accepts values from 0. Check the sign.');
    }
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final value = _parse(_ctrl.text);
    final results =
        value != null && value.isFinite ? _convert(value) : <String, double>{};
    final error = _error(value, results);
    final valid = value != null && error == null;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              context.tr(
                  pl: 'Wpisz wartość i wybierz jej jednostkę. Wyniki przeliczają się od razu.',
                  en: 'Enter a value and select its unit. Results update immediately.'),
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          _input(error),
          const SizedBox(height: 24),
          if (valid) ...[
            Text(context.tr(pl: 'Wyniki', en: 'Results'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (final entry in results.entries)
                      _ResultRow(
                          unit: _label(entry.key), value: _fmt(entry.value))
                  ]),
                )),
            const SizedBox(height: 8),
            Text(
                context.tr(
                    pl: 'Wyniki są zaokrąglone. Dotknij ikony kopiowania lub przytrzymaj liczbę.',
                    en: 'Results are rounded. Tap the copy icon or hold a number.'),
                style: theme.textTheme.bodySmall),
          ] else if (error == null)
            Text(
                context.tr(
                    pl: 'Tutaj pojawią się przeliczone wartości.',
                    en: 'Converted values will appear here.'),
                style: theme.textTheme.bodyMedium),
          if (widget.kind == _Kind.flow) ...[
            const SizedBox(height: 16),
            Text(
                context.tr(
                    pl: 'Przeliczamy osobno l/min ↔ cfh i slpm ↔ scfh. Przejście między przepływem rzeczywistym i standardowym wymaga danych o gazie, ciśnieniu, temperaturze i warunkach odniesienia urządzenia.',
                    en: 'l/min ↔ cfh and slpm ↔ scfh are converted separately. Converting actual to standard flow requires gas, pressure, temperature and instrument reference conditions.'),
                style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          _guide(valid ? value : null, valid ? results : null),
        ]),
      )),
    );
  }

  Widget _input(String? error) {
    final valueField = TextField(
      controller: _ctrl,
      // Never filter a pasted '-10' into a different, valid number '10'.
      keyboardType: TextInputType.numberWithOptions(
          decimal: true, signed: widget.kind == _Kind.temperature),
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
          labelText: context.tr(pl: 'Wartość', en: 'Value'),
          errorText: error,
          errorMaxLines: 4,
          border: const OutlineInputBorder()),
    );
    final unitField = DropdownButtonFormField<String>(
      key: ValueKey(_src),
      initialValue: _src,
      isExpanded: true,
      decoration: InputDecoration(
          labelText: context.tr(pl: 'Jednostka wejściowa', en: 'Input unit'),
          border: const OutlineInputBorder()),
      items: [
        for (final unit in _units)
          DropdownMenuItem(value: unit, child: Text(unit))
      ],
      onChanged: (unit) {
        if (unit == null) return;
        Haptic.tap();
        setState(() => _src = unit);
      },
    );
    final reset = IconButton(
        tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
        icon: const Icon(Icons.refresh),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: _clear);
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(16) > 24;
      if (stacked) {
        return Column(children: [
          valueField,
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: unitField),
            const SizedBox(width: 8),
            reset
          ])
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: valueField),
        const SizedBox(width: 16),
        Expanded(child: unitField),
        const SizedBox(width: 8),
        reset
      ]);
    });
  }

  Widget _guide(double? value, Map<String, double>? results) {
    final hasResult = value != null;
    final sample = value ??
        switch (widget.kind) {
          _Kind.length => 25.4,
          _Kind.temperature => 100.0,
          _Kind.pressure => 2.0,
          _Kind.flow => 10.0,
        };
    final converted = results ?? _convert(sample);
    final input = guideNumber(sample);
    late String inputs;
    late String caution;
    late List<String> steps;
    switch (widget.kind) {
      case _Kind.length:
        final factor = guideNumber(_lengthFactors[_src]!);
        final mm = _fmt(converted['mm']!);
        inputs = context.tr(
            pl: 'Wybierz jednostkę odczytaną z rysunku. 1 cal (in) = 25,4 mm; 1 stopa (ft) = 304,8 mm.',
            en: 'Select the unit used on the drawing. 1 inch (in) = 25.4 mm; 1 foot (ft) = 304.8 mm.');
        steps = [
          '$input $_src × $factor mm/$_src = $mm mm',
          '${guideNumber(converted['mm']!)} / 25.4 = ${_fmt(converted['in']!)} in'
        ];
        caution = context.tr(
            pl: 'DN jest oznaczeniem nominalnym, nie zmierzoną średnicą. Nie przeliczaj DN jak długości w mm.',
            en: 'DN is a nominal designation, not a measured diameter. Do not convert DN as a length in mm.');
      case _Kind.temperature:
        final formula = switch (_src) {
          '°C' => '$input + 273.15',
          '°F' => '($input + 459.67) / 1.8',
          _ => input
        };
        final kelvin = _fmt(converted['K']!);
        inputs = context.tr(
            pl: 'Wybierz skalę podaną w dokumentacji. Przeliczamy temperaturę, nie różnicę temperatur.',
            en: 'Select the scale used in the documentation. This converts a temperature, not a temperature difference.');
        steps = [
          '$formula = $kelvin K',
          '$kelvin − 273.15 = ${_fmt(converted['°C']!)} °C'
        ];
        caution = context.tr(
            pl: 'Zero absolutne to 0 K = −273,15 °C = −459,67 °F. Konwerter nie dobiera temperatury podgrzewania — sprawdź WPS.',
            en: 'Absolute zero is 0 K = −273.15 °C = −459.67 °F. The converter does not select a preheat temperature — check the WPS.');
      case _Kind.pressure:
        final factor = guideNumber(_pressureFactors[_src]!);
        final bar = _fmt(converted['bar']!);
        inputs = context.tr(
            pl: 'Wybierz jednostkę odczytaną z dokumentacji lub manometru. 1 MPa = 10 bar; 1 bar = 100 kPa.',
            en: 'Select the unit from the documentation or pressure gauge. 1 MPa = 10 bar; 1 bar = 100 kPa.');
        steps = [
          '$input $_src × $factor bar/$_src = $bar bar',
          '$bar / 10 = ${_fmt(converted['MPa']!)} MPa'
        ];
        caution = context.tr(
            pl: 'Przeliczamy tylko jednostkę, nie punkt odniesienia: ciśnienie względne nie staje się absolutnym. Wartości nieujemne. Ciśnienie próby określa dokumentacja.',
            en: 'Only the unit changes, not the reference: gauge pressure does not become absolute pressure. Non-negative values only. Test pressure comes from the documentation.');
      case _Kind.flow:
        final litreUnit = _isStandard(_src) ? 'slpm' : 'l/min';
        final feetUnit = _isStandard(_src) ? 'scfh' : 'cfh';
        final factor = guideNumber(_flowFactors[_src]!);
        final lpm = _fmt(converted[litreUnit]!);
        inputs = context.tr(
            pl: 'Przepisz dokładną jednostkę z przepływomierza. Litera „s” oznacza przepływ sprowadzony do warunków standardowych urządzenia.',
            en: 'Use the exact unit on the flow meter. The letter “s” means flow referenced to the instrument’s standard conditions.');
        steps = [
          '$input $_src × $factor $litreUnit/$_src = $lpm $litreUnit',
          '$lpm / 0.4719474 = ${_fmt(converted[feetUnit]!)} $feetUnit'
        ];
        caution = context.tr(
            pl: 'Przeliczenie slpm ↔ scfh zakłada te same warunki odniesienia. Sprawdź gaz i kalibrację urządzenia. Dobór przepływu osłonowego wynika z WPS, nie z konwertera.',
            en: 'slpm ↔ scfh assumes identical reference conditions. Check the gas and instrument calibration. Shielding flow selection comes from the WPS, not this converter.');
    }
    return CalculationGuide(
        inputs: inputs, steps: steps, caution: caution, hasResult: hasResult);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.unit, required this.value});
  final String unit;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(unit,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                CopyOnLongPress(
                    value: value,
                    label: unit,
                    child: Text(value,
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]))),
              ])),
          const SizedBox(width: 8),
          IconButton(
              tooltip: context.tr(pl: 'Kopiuj $unit', en: 'Copy $unit'),
              icon: const Icon(Icons.content_copy_outlined),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => copyToClipboard(context, value, label: unit)),
        ]));
  }
}
