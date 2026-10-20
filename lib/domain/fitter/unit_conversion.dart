// Pure unit conversions behind "Konwerter jednostek"
// (lib/screens/quick_converter_screen.dart). No Flutter imports — the screen
// and the voice assistant both get their numbers from here; pinned by
// test/domain/fitter/unit_conversion_test.dart.
//
// Factors retained from the original converter. Reference:
// https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8

/// A unit shown on the converter: [symbol] is the exact text of the screen's
/// unit picker and result rows.
abstract interface class MeasureUnit {
  String get symbol;
}

/// Length units in screen order; [toMm] = millimetres per one unit.
enum LengthUnit implements MeasureUnit {
  mm('mm', 1.0),
  cm('cm', 10.0),
  m('m', 1000.0),
  inch('in', 25.4),
  ft('ft', 304.8);

  const LengthUnit(this.symbol, this.toMm);
  @override
  final String symbol;
  final double toMm;

  static LengthUnit? fromSymbol(String symbol) => _bySymbol(values, symbol);
}

/// Temperature scales in screen order; [absoluteZero] in this scale.
enum TemperatureUnit implements MeasureUnit {
  celsius('°C', -273.15),
  fahrenheit('°F', -459.67),
  kelvin('K', 0.0);

  const TemperatureUnit(this.symbol, this.absoluteZero);
  @override
  final String symbol;
  final double absoluteZero;

  static TemperatureUnit? fromSymbol(String symbol) =>
      _bySymbol(values, symbol);
}

/// Pressure units in screen order; [toBar] = bar per one unit.
enum PressureUnit implements MeasureUnit {
  bar('bar', 1.0),
  mpa('MPa', 10.0),
  kpa('kPa', 0.01),
  psi('psi', 0.0689476),
  atm('atm', 1.01325),
  // Old gauges / gas tests. NIST SP 811 App. B: kgf/cm² = 9.80665 × 10⁴ Pa
  // (exact, standard gravity) = 0.980665 bar; mbar = 10⁻³ bar.
  kgfPerCm2('kgf/cm²', 0.980665),
  mbar('mbar', 0.001);

  const PressureUnit(this.symbol, this.toBar);
  @override
  final String symbol;
  final double toBar;

  static PressureUnit? fromSymbol(String symbol) => _bySymbol(values, symbol);
}

/// Gas-flow units in screen order; [toLpm] = l/min (or slpm) per one unit.
///
/// Actual and standardized flow are different quantities: [standard] units
/// (slpm, scfh) convert only among themselves. No implicit l/min == slpm
/// conversion without gas, pressure, temperature and reference data.
/// https://www.alicat.com/support/what-is-mass-flow/
enum FlowUnit implements MeasureUnit {
  lpm('l/min', 1.0, standard: false),
  slpm('slpm', 1.0, standard: true),
  cfh('cfh', 0.4719474, standard: false),
  scfh('scfh', 0.4719474, standard: true);

  const FlowUnit(this.symbol, this.toLpm, {required this.standard});
  @override
  final String symbol;
  final double toLpm;
  final bool standard;

  static FlowUnit? fromSymbol(String symbol) => _bySymbol(values, symbol);
}

U? _bySymbol<U extends MeasureUnit>(List<U> units, String symbol) {
  for (final u in units) {
    if (u.symbol == symbol) return u;
  }
  return null;
}

/// Why a value was refused. Checked in this order (as on the screen):
/// [outOfRange] (value or any result not finite), then [belowAbsoluteZero]
/// (temperature) or [negative] (every other quantity).
enum ConversionIssue { outOfRange, belowAbsoluteZero, negative }

/// A value converted into every unit of its quantity, or the reason it was
/// refused.
class ConversionTable<U extends MeasureUnit> {
  const ConversionTable._(this.values, this.issue);

  /// Value in each unit, in enum (= screen) order. For flow only the units of
  /// the same kind (actual or standard) as the source. Empty when [issue] is
  /// not null.
  final Map<U, double> values;
  final ConversionIssue? issue;

  bool get ok => issue == null;
}

ConversionTable<U> _table<U extends MeasureUnit>(
  double value,
  Map<U, double> Function() convert, {
  required bool belowFloor,
  required bool negativeAllowed,
}) {
  ConversionTable<U> refused(ConversionIssue issue) =>
      ConversionTable._(Map<U, double>.unmodifiable({}), issue);
  if (!value.isFinite) return refused(ConversionIssue.outOfRange);
  final values = convert();
  if (values.values.any((v) => !v.isFinite)) {
    return refused(ConversionIssue.outOfRange);
  }
  if (belowFloor) return refused(ConversionIssue.belowAbsoluteZero);
  if (!negativeAllowed && value < 0) return refused(ConversionIssue.negative);
  return ConversionTable._(Map<U, double>.unmodifiable(values), null);
}

/// [value] in [from] → every length unit. Refuses negatives; 0 is valid.
ConversionTable<LengthUnit> convertLengthAll(double value, LengthUnit from) =>
    _table(value, () {
      final base = value * from.toMm;
      return {for (final u in LengthUnit.values) u: base / u.toMm};
    }, belowFloor: false, negativeAllowed: false);

/// [value] in [from] → every temperature scale. Converts a temperature, not
/// a difference between temperatures; refuses values below absolute zero.
ConversionTable<TemperatureUnit> convertTemperatureAll(
        double value, TemperatureUnit from) =>
    _table(value, () {
      // Source-scale floor avoids a negative rounding artifact at -459.67 F.
      final kelvin = switch (from) {
        TemperatureUnit.celsius => value + 273.15,
        TemperatureUnit.fahrenheit => (value + 459.67) / 1.8,
        TemperatureUnit.kelvin => value,
      };
      return {
        TemperatureUnit.celsius: kelvin - 273.15,
        TemperatureUnit.fahrenheit: kelvin * 1.8 - 459.67,
        TemperatureUnit.kelvin: kelvin,
      };
    }, belowFloor: value < from.absoluteZero, negativeAllowed: true);

/// [value] in [from] → every pressure unit. Only the unit changes, not the
/// reference (gauge stays gauge). Refuses negatives; 0 is valid.
ConversionTable<PressureUnit> convertPressureAll(
        double value, PressureUnit from) =>
    _table(value, () {
      final base = value * from.toBar;
      return {for (final u in PressureUnit.values) u: base / u.toBar};
    }, belowFloor: false, negativeAllowed: false);

/// [value] in [from] → every flow unit of the same kind (l/min ↔ cfh or
/// slpm ↔ scfh). Refuses negatives; 0 is valid.
ConversionTable<FlowUnit> convertFlowAll(double value, FlowUnit from) =>
    _table(value, () {
      final base = value * from.toLpm;
      return {
        for (final u in FlowUnit.values)
          if (u.standard == from.standard) u: base / u.toLpm
      };
    }, belowFloor: false, negativeAllowed: false);

/// [value] in [from] expressed in [to]; `null` for a refused value (NaN,
/// infinite, negative, result out of range).
double? convertLength(double value, LengthUnit from, LengthUnit to) =>
    convertLengthAll(value, from).values[to];

/// [value] in [from] expressed in [to]; `null` below absolute zero, for NaN,
/// infinity or a result out of range.
double? convertTemperature(
        double value, TemperatureUnit from, TemperatureUnit to) =>
    convertTemperatureAll(value, from).values[to];

/// [value] in [from] expressed in [to]; `null` for a refused value.
double? convertPressure(double value, PressureUnit from, PressureUnit to) =>
    convertPressureAll(value, from).values[to];

/// [value] in [from] expressed in [to]; `null` for a refused value and when
/// [from] and [to] are not the same kind (actual vs standard flow).
double? convertFlow(double value, FlowUnit from, FlowUnit to) =>
    convertFlowAll(value, from).values[to];

/// Validates the wire format used to fill the converter screen.
/// Unknown categories or source symbols are refused before any UI mutation.
ConversionTable<MeasureUnit>? conversionBySymbol(
    String kind, double value, String from) {
  switch (kind) {
    case 'length':
      final unit = LengthUnit.fromSymbol(from);
      return unit == null ? null : convertLengthAll(value, unit);
    case 'temperature':
      final unit = TemperatureUnit.fromSymbol(from);
      return unit == null ? null : convertTemperatureAll(value, unit);
    case 'pressure':
      final unit = PressureUnit.fromSymbol(from);
      return unit == null ? null : convertPressureAll(value, unit);
    case 'flow':
      final unit = FlowUnit.fromSymbol(from);
      return unit == null ? null : convertFlowAll(value, unit);
    default:
      return null;
  }
}
