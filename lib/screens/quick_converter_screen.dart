import 'package:flutter/material.dart';
import '../assistant/core/tool_bridge.dart';
import '../domain/fitter/unit_conversion.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../utils/decimal_input_text.dart';
import '../utils/haptic.dart';
import '../widgets/calculation_guide.dart';
import '../widgets/number_field.dart';

/// Offline conversions; all four original categories remain available.
class QuickConverterScreen extends StatefulWidget {
  const QuickConverterScreen({super.key});
  @override
  State<QuickConverterScreen> createState() => _QuickConverterScreenState();
}

class _QuickConverterScreenState extends State<QuickConverterScreen>
    with SingleTickerProviderStateMixin, ToolHandleHost<QuickConverterScreen>
    implements InputToolHandle {
  late final _tabs = TabController(length: 4, vsync: this);
  final _tabKeys = {
    for (final kind in _Kind.values) kind: GlobalKey<_ConversionTabState>()
  };
  @override
  Map<String, Object?> get inputFields {
    final kind = _Kind.values[_tabs.index];
    return Map.unmodifiable(
        _tabKeys[kind]!.currentState?.inputFields ?? {'kind': kind.name});
  }

  int _revision = 0;
  final _inputs = <_Kind, ({double value, String from, int revision})>{};
  @override
  String get toolId => 'unit_converter';
  @override
  Set<String> get supportedFields => const {'kind', 'value', 'from'};
  @override
  void initState() {
    super.initState();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    final kind =
        _Kind.values.where((k) => k.name == fields['kind']).firstOrNull;
    final value = fields['value'];
    final from = fields['from'];
    if (kind == null) return {'kind'};
    if (value is! num || !value.isFinite) return {'value'};
    if (from is! String) return {'from'};
    final table = conversionBySymbol(kind.name, value.toDouble(), from);
    if (table == null) return {'from'};
    if (!table.ok) return {'value'};
    if (!mounted) return fields.keys.toSet();
    setState(() {
      _inputs[kind] =
          (value: value.toDouble(), from: from, revision: ++_revision);
      _tabs.index = kind.index;
    });
    return {};
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title:
              Text(context.tr(pl: 'Konwerter jednostek', en: 'Unit converter')),
          bottom: TabBar(controller: _tabs, isScrollable: true, tabs: [
            Tab(text: context.tr(pl: 'Długość', en: 'Length')),
            Tab(text: context.tr(pl: 'Temperatura', en: 'Temperature')),
            Tab(text: context.tr(pl: 'Ciśnienie', en: 'Pressure')),
            Tab(text: context.tr(pl: 'Przepływ gazu', en: 'Gas flow')),
          ]),
        ),
        body: SafeArea(
            top: false,
            child: TabBarView(controller: _tabs, children: [
              for (final kind in _Kind.values)
                _ConversionTab(
                    key: _tabKeys[kind], kind: kind, input: _inputs[kind]),
            ])),
      );
}

enum _Kind { length, temperature, pressure, flow }

// Units, factors (NIST SP 811 App. B) and the conversions themselves live in
// lib/domain/fitter/unit_conversion.dart; this screen only parses, formats
// and explains. Units are kept as their screen symbols ('mm', 'in', '°C'…).
final _decimal = RegExp(r'^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$');

double? _parse(String text) {
  final value = text.trim();
  if (!_decimal.hasMatch(value)) return null;
  // The shape was validated above, so the shared parser can only refuse it
  // as non-finite — a 300-digit paste. Keep that as infinity so the screen
  // says "out of range" rather than "not a number".
  return parseDecimal(value) ?? double.infinity;
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
  const _ConversionTab({super.key, required this.kind, this.input});
  final ({double value, String from, int revision})? input;
  final _Kind kind;
  @override
  State<_ConversionTab> createState() => _ConversionTabState();
}

class _ConversionTabState extends State<_ConversionTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, Object?> get inputFields {
    final value = _parse(_ctrl.text);
    return {
      'kind': widget.kind.name,
      'value': value != null && value.isFinite ? value : null,
      'from': _src
    };
  }

  final _ctrl = TextEditingController();
  late String _src = _units.first;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _acceptInput();
  }

  @override
  void didUpdateWidget(covariant _ConversionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input != widget.input) _acceptInput();
  }

  void _acceptInput() {
    final input = widget.input;
    if (input == null) return;
    _ctrl.text = decimalInputText(input.value);
    _src = input.from;
  }

  List<MeasureUnit> get _unitValues {
    switch (widget.kind) {
      case _Kind.length:
        return LengthUnit.values;
      case _Kind.temperature:
        return TemperatureUnit.values;
      case _Kind.pressure:
        return PressureUnit.values;
      case _Kind.flow:
        return FlowUnit.values;
    }
  }

  List<String> get _units => [for (final unit in _unitValues) unit.symbol];

  void _clear() {
    Haptic.tap();
    setState(() {
      _ctrl.clear();
      _src = _units.first;
    });
  }

  /// [value] in the selected unit → every unit of this tab (or the reason it
  /// is refused), from the domain conversion.
  ConversionTable<MeasureUnit> _convert(double value) {
    switch (widget.kind) {
      case _Kind.length:
        return convertLengthAll(value, LengthUnit.fromSymbol(_src)!);
      case _Kind.temperature:
        return convertTemperatureAll(value, TemperatureUnit.fromSymbol(_src)!);
      case _Kind.pressure:
        return convertPressureAll(value, PressureUnit.fromSymbol(_src)!);
      case _Kind.flow:
        return convertFlowAll(value, FlowUnit.fromSymbol(_src)!);
    }
  }

  static Map<String, double> _bySymbol(ConversionTable<MeasureUnit> table) =>
      {for (final e in table.values.entries) e.key.symbol: e.value};

  // Actual and standardized flow are different quantities: see FlowUnit.
  bool get _srcIsStandardFlow => FlowUnit.fromSymbol(_src)!.standard;

  String? _error(double? value, ConversionIssue? issue) {
    if (_ctrl.text.trim().isEmpty) return null;
    if (value == null) {
      return context.tr(
          pl: 'Wpisz liczbę z jednym przecinkiem lub kropką, bez jednostki.',
          en: 'Enter a number with one decimal separator, without a unit.');
    }
    switch (issue) {
      case null:
        return null;
      case ConversionIssue.outOfRange:
        return context.tr(
            pl: 'Wartość poza zakresem. Sprawdź liczbę i jednostkę.',
            en: 'Value out of range. Check the number and unit.');
      case ConversionIssue.belowAbsoluteZero:
        final floor = TemperatureUnit.fromSymbol(_src)!.absoluteZero;
        return context.tr(
            pl: 'Temperatura nie może być niższa niż $floor $_src (zero absolutne).',
            en: 'Temperature cannot be below $floor $_src (absolute zero).');
      case ConversionIssue.negative:
        return context.tr(
            pl: 'Ten przelicznik obsługuje wartości od 0. Sprawdź znak.',
            en: 'This converter accepts values from 0. Check the sign.');
    }
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
    final conversion = value == null ? null : _convert(value);
    final error = _error(value, conversion?.issue);
    final valid = value != null && error == null;
    final results = valid ? _bySymbol(conversion!) : const <String, double>{};
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
      // Never filter a pasted '-10' into a different, valid number '10':
      // the minus key is only on the temperature keyboard, but every tab
      // ACCEPTS '-' so a pasted negative stays visible and gets its error.
      // The shared formatter refuses (never trims) any other stray
      // character, so '1e5' cannot turn into '15' either.
      keyboardType: numberKeyboard(signed: widget.kind == _Kind.temperature),
      inputFormatters: numberInputFormatters(signed: true),
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
    final converted = results ?? _bySymbol(_convert(sample));
    final input = guideNumber(sample);
    late String inputs;
    late String caution;
    late List<String> steps;
    switch (widget.kind) {
      case _Kind.length:
        final factor = guideNumber(LengthUnit.fromSymbol(_src)!.toMm);
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
        final factor = guideNumber(PressureUnit.fromSymbol(_src)!.toBar);
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
        final litreUnit = _srcIsStandardFlow ? 'slpm' : 'l/min';
        final feetUnit = _srcIsStandardFlow ? 'scfh' : 'cfh';
        final factor = guideNumber(FlowUnit.fromSymbol(_src)!.toLpm);
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
