// Odbiór wizualny spoin — obliczanie limitów EN ISO 5817:2014 (tablica 1)
// dla wpisanych wymiarów i ocena zmierzonej wartości. Czysty Dart.
//
// Dane (reguły każdej pozycji, źródła): iso5817_table.dart.
//
// Zasady obliczeń:
//  • zakres grubości (EN ISO 5817:2014, rozdz. 1 i tablica 1): t < 0,5 mm —
//    poza zakresem normy; 0,5 ≤ t ≤ 3 mm — kolumna „0,5 to 3”; t > 3 mm —
//    kolumna „> 3”;
//  • limit = stała + współczynnik · wymiar, a gdy norma podaje „but max.” —
//    nie więcej niż maksimum;
//  • wynik w mm zaokrąglamy W DÓŁ do 0,01 mm (po stronie bezpiecznej) i tę
//    samą liczbę porównujemy z pomiarem — to, co widzi kontroler, jest tym,
//    co liczy aplikacja;
//  • „short imperfections” — limit obowiązuje tylko dla niezgodności krótkiej
//    (rozdz. 3.3/3.4); niezgodność długa na takim poziomie jest
//    niedopuszczalna.
//
// Brak danych ≠ niezgodność: bez t, b, a albo pomiaru wynik to „uzupełnij”,
// nigdy fałszywe „mieści się” ani „niedopuszczalne”.

import 'iso5817_table.dart';

/// Najmniejsza grubość objęta normą (EN ISO 5817:2014, rozdz. 1).
const double kIso5817MinThicknessMm = 0.5;

/// Górna granica zakresu „0,5 to 3” w tablicy 1.
const double kIso5817ThinMaxMm = 3.0;

/// Wydanie normy, z którego pochodzą liczby.
const String kIso5817Edition = 'EN ISO 5817:2014';

/// Wymiary złącza wpisane przez kontrolera (mm). Wszystko opcjonalne.
class Iso5817Input {
  /// Grubość ścianki / blachy (przy różnych grubościach — cieńsza).
  final double? t;

  /// Szerokość lica.
  final double? b;

  /// Szerokość grani (poz. 1.11).
  final double? bRoot;

  /// Nominalna grubość spoiny pachwinowej.
  final double? a;

  const Iso5817Input({this.t, this.b, this.bRoot, this.a});

  /// Wartość wymiaru albo null, gdy nie podano (albo ≤ 0).
  double? valueOf(Iso5817Dim dim) {
    final v = switch (dim) {
      Iso5817Dim.t => t,
      // EN ISO 5817:2014 obejmuje spoiny czołowe z pełnym przetopem
      // (rozdz. 1) — wtedy nominalna grubość spoiny s = t.
      Iso5817Dim.s => t,
      Iso5817Dim.b => b,
      Iso5817Dim.bRoot => bRoot,
      Iso5817Dim.a => a,
    };
    return v == null || v <= 0 ? null : v;
  }
}

enum Iso5817Range { thin, thick }

/// Zakres grubości tablicy 1; null, gdy t brak albo t < 0,5 mm.
Iso5817Range? iso5817Range(double? t) {
  if (t == null || t < kIso5817MinThicknessMm) return null;
  return t <= kIso5817ThinMaxMm ? Iso5817Range.thin : Iso5817Range.thick;
}

/// Reguła tablicy 1 dla pozycji, poziomu i zakresu grubości.
Iso5817Rule iso5817RuleFor(
        Iso5817Item item, Iso5817Level level, Iso5817Range range) =>
    (range == Iso5817Range.thin ? item.thin : item.thick)[level]!;

enum Iso5817LimitStatus {
  /// Limit liczbowy ([Iso5817Limit.value]).
  value,
  notPermitted,
  unlimited,
  qualitative,

  /// Brak grubości t.
  needsThickness,

  /// t < 0,5 mm — poza zakresem normy.
  outOfScope,

  /// Brak wymiaru potrzebnego do wzoru ([Iso5817Limit.missingDim]).
  needsDimension,
}

/// Wyliczony limit jednej pozycji na jednym poziomie.
class Iso5817Limit {
  final Iso5817Level level;
  final Iso5817LimitStatus status;
  final Iso5817Rule? rule;

  /// mm (zaokrąglone w dół do 0,01) albo kąt minimalny w °.
  final double? value;

  /// Wynik wzoru przed „maks.” i przed zaokrągleniem.
  final double? rawValue;

  /// Zadziałało „but max.”.
  final bool capped;
  final Iso5817Dim? missingDim;

  const Iso5817Limit({
    required this.level,
    required this.status,
    this.rule,
    this.value,
    this.rawValue,
    this.capped = false,
    this.missingDim,
  });

  bool get isAngle => rule?.kind == Iso5817RuleKind.minAngle;
  bool get shortOnly => rule?.shortOnly ?? false;
}

/// Zaokrąglenie w dół do 0,01 mm (ε chroni 0,1·3 = 0,30000000000000004
/// i 1 + 0,15·12 = 2,8 przed zjechaniem o setną).
double _floorHundredth(double v) => (v * 100 + 1e-6).floorToDouble() / 100;

/// Limit pozycji [item] na poziomie [level] dla wymiarów [input].
Iso5817Limit iso5817Limit(
    Iso5817Item item, Iso5817Level level, Iso5817Input input) {
  final t = input.t;
  if (t == null || t <= 0) {
    return Iso5817Limit(
        level: level, status: Iso5817LimitStatus.needsThickness);
  }
  final range = iso5817Range(t);
  if (range == null) {
    return Iso5817Limit(level: level, status: Iso5817LimitStatus.outOfScope);
  }
  final rule = iso5817RuleFor(item, level, range);
  switch (rule.kind) {
    case Iso5817RuleKind.notPermitted:
      return Iso5817Limit(
          level: level, status: Iso5817LimitStatus.notPermitted, rule: rule);
    case Iso5817RuleKind.unlimited:
      return Iso5817Limit(
          level: level, status: Iso5817LimitStatus.unlimited, rule: rule);
    case Iso5817RuleKind.qualitative:
      return Iso5817Limit(
          level: level, status: Iso5817LimitStatus.qualitative, rule: rule);
    case Iso5817RuleKind.minAngle:
      return Iso5817Limit(
          level: level,
          status: Iso5817LimitStatus.value,
          rule: rule,
          value: rule.minAngleDeg,
          rawValue: rule.minAngleDeg);
    case Iso5817RuleKind.formula:
      var x = 0.0;
      if (rule.factor != 0) {
        final v = input.valueOf(rule.dim!);
        if (v == null) {
          return Iso5817Limit(
              level: level,
              status: Iso5817LimitStatus.needsDimension,
              rule: rule,
              missingDim: rule.dim);
        }
        x = v;
      }
      final raw = rule.constantMm + rule.factor * x;
      final max = rule.maxMm;
      final capped = max != null && raw > max;
      return Iso5817Limit(
        level: level,
        status: Iso5817LimitStatus.value,
        rule: rule,
        value: _floorHundredth(capped ? max : raw),
        rawValue: raw,
        capped: capped,
      );
  }
}

/// Limity na wszystkich trzech poziomach.
Map<Iso5817Level, Iso5817Limit> iso5817Limits(
        Iso5817Item item, Iso5817Input input) =>
    {
      for (final level in Iso5817Level.values)
        level: iso5817Limit(item, level, input),
    };

// ── Ocena pomiaru ───────────────────────────────────────────────────────────

enum Iso5817Outcome {
  /// Mieści się w wymaganym poziomie.
  pass,

  /// Przekracza wymagany poziom, ale mieści się w łagodniejszym (albo jest
  /// tam dopuszczalna warunkowo — [Iso5817Assessment.acceptedConditionally]).
  below,

  /// Niedopuszczalne na każdym poziomie.
  fail,

  /// Na wymaganym poziomie decyduje opis słowny (np. rozprysk — zależy od
  /// zastosowania) — rozstrzyga specyfikacja.
  conditional,

  /// Brak danych (t, b, a albo pomiaru) albo t poza zakresem normy.
  incomplete,
}

class Iso5817Assessment {
  final Iso5817Item item;
  final Iso5817Level required;

  /// Zmierzona wartość (mm albo °); null dla pozycji „obecność”.
  final double? measured;

  /// Niezgodność krótka w rozumieniu rozdz. 3.3/3.4.
  final bool isShort;
  final Map<Iso5817Level, Iso5817Limit> limits;

  /// Czy pomiar mieści się na danym poziomie; null — nie da się ocenić.
  final Map<Iso5817Level, bool?> meets;
  final Iso5817Outcome outcome;

  /// Dla [Iso5817Outcome.below] — najostrzejszy łagodniejszy poziom,
  /// w którym pomiar się mieści.
  final Iso5817Level? acceptedAt;

  /// [acceptedAt] tylko warunkowo (opis słowny normy).
  final bool acceptedConditionally;

  /// Najostrzejszy poziom spełniony bezwarunkowo (może być ostrzejszy od
  /// wymaganego).
  final Iso5817Level? strictestMet;

  /// Wymagany poziom odpada TYLKO dlatego, że niezgodność jest długa.
  final bool failedOnLength;

  const Iso5817Assessment({
    required this.item,
    required this.required,
    required this.measured,
    required this.isShort,
    required this.limits,
    required this.meets,
    required this.outcome,
    this.acceptedAt,
    this.acceptedConditionally = false,
    this.strictestMet,
    this.failedOnLength = false,
  });

  Iso5817Limit get requiredLimit => limits[required]!;

  /// Czy dla bieżących wymiarów któraś reguła dotyczy tylko niezgodności
  /// krótkich (wtedy pytamy o długość).
  bool get anyShortOnly => limits.values.any((l) => l.shortOnly);
}

bool _withinValue(Iso5817Limit limit, double measured) {
  final v = limit.value!;
  if (limit.isAngle) return measured >= v - 1e-9;
  return measured <= v + 1e-9;
}

bool? _meetsLevel(Iso5817Limit limit, Iso5817Measure measure,
    double? measured, bool isShort) {
  final present = measure == Iso5817Measure.presence;
  switch (limit.status) {
    case Iso5817LimitStatus.needsThickness:
    case Iso5817LimitStatus.outOfScope:
    case Iso5817LimitStatus.needsDimension:
    case Iso5817LimitStatus.qualitative:
      return null;
    case Iso5817LimitStatus.unlimited:
      return present || measured != null ? true : null;
    case Iso5817LimitStatus.notPermitted:
      if (present) return false;
      if (measured == null) return null;
      // 0 = brak niezgodności.
      return measured <= 0;
    case Iso5817LimitStatus.value:
      if (measured == null) return null;
      if (limit.shortOnly && !isShort && measured > 0) return false;
      return _withinValue(limit, measured);
  }
}

/// Ocena zmierzonej wartości [measured] pozycji [item] względem wymaganego
/// poziomu [required]. Dla pozycji „obecność” [measured] jest ignorowany —
/// wybranie pozycji znaczy, że niezgodność stwierdzono.
Iso5817Assessment assessIso5817({
  required Iso5817Item item,
  required Iso5817Level required,
  required Iso5817Input input,
  double? measured,
  bool isShort = true,
}) {
  final m = item.measure == Iso5817Measure.presence ? null : measured;
  final limits = iso5817Limits(item, input);
  final meets = {
    for (final level in Iso5817Level.values)
      level: _meetsLevel(limits[level]!, item.measure, m, isShort),
  };

  Iso5817Level? strictestMet;
  for (final level in Iso5817Level.values) {
    if (meets[level] == true) {
      strictestMet = level;
      break;
    }
  }

  final requiredLimit = limits[required]!;
  final looser = Iso5817Level.values
      .where((l) => l.strictness > required.strictness)
      .toList();

  var outcome = Iso5817Outcome.incomplete;
  Iso5817Level? acceptedAt;
  var conditionally = false;
  var failedOnLength = false;

  switch (meets[required]) {
    case true:
      outcome = Iso5817Outcome.pass;
    case false:
      for (final l in looser) {
        if (meets[l] == true) {
          acceptedAt = l;
          break;
        }
        if (limits[l]!.status == Iso5817LimitStatus.qualitative) {
          acceptedAt = l;
          conditionally = true;
          break;
        }
      }
      outcome =
          acceptedAt == null ? Iso5817Outcome.fail : Iso5817Outcome.below;
      failedOnLength = m != null &&
          requiredLimit.status == Iso5817LimitStatus.value &&
          requiredLimit.shortOnly &&
          !isShort &&
          _withinValue(requiredLimit, m);
    case null:
      outcome = requiredLimit.status == Iso5817LimitStatus.qualitative
          ? Iso5817Outcome.conditional
          : Iso5817Outcome.incomplete;
  }

  return Iso5817Assessment(
    item: item,
    required: required,
    measured: m,
    isShort: isShort,
    limits: limits,
    meets: meets,
    outcome: outcome,
    acceptedAt: acceptedAt,
    acceptedConditionally: conditionally,
    strictestMet: strictestMet,
    failedOnLength: failedOnLength,
  );
}

// ── Teksty (PL / EN) ────────────────────────────────────────────────────────

/// `0.5` → „0,5” (PL) / „0.5” (EN); do 2 miejsc, bez zbędnych zer.
String iso5817Num(double v, {required bool en}) {
  final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return en ? s : s.replaceAll('.', ',');
}

String _tr(bool en, String pl, String enText) => en ? enText : pl;

/// Nazwa wymiaru do komunikatu „podaj …”.
String iso5817DimName(Iso5817Dim dim, {required bool en}) => switch (dim) {
      Iso5817Dim.t || Iso5817Dim.s => _tr(en, 'grubość t', 'thickness t'),
      Iso5817Dim.b => _tr(en, 'szerokość lica b', 'face width b'),
      Iso5817Dim.bRoot => _tr(en, 'szerokość grani b', 'root width b'),
      Iso5817Dim.a => _tr(en, 'grubość spoiny a', 'throat thickness a'),
    };

String _dimSymbol(Iso5817Dim dim) => switch (dim) {
      Iso5817Dim.t => 't',
      Iso5817Dim.s => 's',
      Iso5817Dim.b || Iso5817Dim.bRoot => 'b',
      Iso5817Dim.a => 'a',
    };

String _unit(Iso5817Item item) =>
    item.measure == Iso5817Measure.angleDeg ? '°' : ' mm';

/// Reguła tak, jak stoi w normie, np. „h ≤ 1 mm + 0,1·b, maks. 5 mm”.
String iso5817RuleText(Iso5817Rule rule,
    {required bool en, String symbol = 'h'}) {
  switch (rule.kind) {
    case Iso5817RuleKind.notPermitted:
      return _tr(en, 'Niedopuszczalne', 'Not permitted');
    case Iso5817RuleKind.unlimited:
      return _tr(en, 'Dopuszczalne (bez limitu)', 'Permitted (no limit)');
    case Iso5817RuleKind.qualitative:
      return en ? rule.textEn : rule.textPl;
    case Iso5817RuleKind.minAngle:
      return '$symbol ≥ ${iso5817Num(rule.minAngleDeg, en: en)}°';
    case Iso5817RuleKind.formula:
      final parts = <String>[
        if (rule.constantMm != 0) '${iso5817Num(rule.constantMm, en: en)} mm',
        if (rule.factor != 0)
          '${iso5817Num(rule.factor, en: en)}·${_dimSymbol(rule.dim!)}',
      ];
      final max = rule.maxMm;
      final body = '$symbol ≤ ${parts.join(' + ')}'
          '${max == null ? '' : _tr(en, ', maks. ', ', max. ')}'
          '${max == null ? '' : '${iso5817Num(max, en: en)} mm'}';
      return rule.shortOnly
          ? _tr(en, 'krótkie: $body', 'short: $body')
          : body;
  }
}

/// Krótka wartość limitu do listy, np. „≤ 0,5 mm”, „≥ 110°”, „niedopuszczalne”.
String iso5817LimitValueText(Iso5817Limit limit, {required bool en}) {
  switch (limit.status) {
    case Iso5817LimitStatus.value:
      final v = iso5817Num(limit.value!, en: en);
      return limit.isAngle ? '≥ $v°' : '≤ $v mm';
    case Iso5817LimitStatus.notPermitted:
      return _tr(en, 'niedopuszczalne', 'not permitted');
    case Iso5817LimitStatus.unlimited:
      return _tr(en, 'bez limitu', 'no limit');
    case Iso5817LimitStatus.qualitative:
      return _tr(en, 'wg zastosowania', 'per application');
    case Iso5817LimitStatus.needsThickness:
      return _tr(en, 'podaj t', 'enter t');
    case Iso5817LimitStatus.outOfScope:
      return _tr(en, 't < 0,5 mm', 't < 0.5 mm');
    case Iso5817LimitStatus.needsDimension:
      return _tr(en, 'podaj ${_dimSymbol(limit.missingDim!)}',
          'enter ${_dimSymbol(limit.missingDim!)}');
  }
}

/// Podstawienie do wzoru, np. „1 mm + 0,15·12 mm = 2,8 mm → maks. 7 mm”.
/// Pusty, gdy nie ma czego liczyć.
String iso5817LimitCalc(Iso5817Limit limit, Iso5817Input input,
    {required bool en}) {
  final rule = limit.rule;
  if (rule == null ||
      rule.kind != Iso5817RuleKind.formula ||
      limit.status != Iso5817LimitStatus.value ||
      rule.factor == 0) {
    return '';
  }
  final x = input.valueOf(rule.dim!)!;
  final parts = <String>[
    if (rule.constantMm != 0) '${iso5817Num(rule.constantMm, en: en)} mm',
    '${iso5817Num(rule.factor, en: en)}·${iso5817Num(x, en: en)} mm',
  ];
  final raw = iso5817Num(_floorHundredth(limit.rawValue!), en: en);
  final capped = limit.capped
      ? '${_tr(en, ' → maks. ', ' → max. ')}'
          '${iso5817Num(rule.maxMm!, en: en)} mm'
      : '';
  return '${parts.join(' + ')} = $raw mm$capped';
}

String _limitInBrackets(Iso5817Item item, Iso5817Limit limit,
    {required bool en}) {
  switch (limit.status) {
    case Iso5817LimitStatus.value:
      final v = iso5817Num(limit.value!, en: en);
      return limit.isAngle
          ? _tr(en, 'min. $v°', 'min. $v°')
          : _tr(en, 'limit $v${_unit(item)}', 'limit $v${_unit(item)}');
    case Iso5817LimitStatus.unlimited:
      return _tr(en, 'bez limitu', 'no limit');
    default:
      return iso5817LimitValueText(limit, en: en);
  }
}

/// Opis słowny w środku zdania — od małej litery.
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// „Przekracza C (limit 0,5 mm)” dla wymiaru, „Nie spełnia C (min. 110°)”
/// dla kąta.
String _misses(Iso5817Item item, Iso5817Level level, Iso5817Limit limit,
    {required bool en}) {
  final l = level.letter;
  final lim = _limitInBrackets(item, limit, en: en);
  return limit.isAngle
      ? _tr(en, 'Nie spełnia $l ($lim)', 'Does not meet $l ($lim)')
      : _tr(en, 'Przekracza $l ($lim)', 'Exceeds $l ($lim)');
}

/// Pomiar mieści się w liczbie limitu, ale limit dotyczy tylko niezgodności
/// krótkich, a ta jest długa.
bool _onlyLengthFails(Iso5817Assessment a, Iso5817Limit limit) {
  final m = a.measured;
  return m != null &&
      !a.isShort &&
      limit.status == Iso5817LimitStatus.value &&
      limit.shortOnly &&
      _withinValue(limit, m);
}

/// Główny werdykt jednym zdaniem.
String iso5817Headline(Iso5817Assessment a, {required bool en}) {
  final req = a.required.letter;
  final reqLimit = a.requiredLimit;
  switch (a.outcome) {
    case Iso5817Outcome.pass:
      if (reqLimit.status == Iso5817LimitStatus.notPermitted) {
        return _tr(en, 'Brak niezgodności — mieści się w $req',
            'No imperfection — within $req');
      }
      final lim = _limitInBrackets(a.item, reqLimit, en: en);
      return _tr(en, 'Mieści się w $req ($lim)', 'Within $req ($lim)');
    case Iso5817Outcome.below:
      final at = a.acceptedAt!;
      final atLimit = a.limits[at]!;
      final first = reqLimit.status == Iso5817LimitStatus.notPermitted
          ? _tr(en, 'Niedopuszczalne w $req', 'Not permitted in $req')
          : a.failedOnLength
              ? _tr(en, 'Przekracza $req (dopuszcza tylko niezgodność krótką)',
                  'Exceeds $req (short imperfections only)')
              : _misses(a.item, a.required, reqLimit, en: en);
      if (a.acceptedConditionally) {
        final rule = atLimit.rule!;
        final text = _lowerFirst(en ? rule.textEn : rule.textPl);
        return _tr(en, '$first; w ${at.letter} warunkowo: $text',
            '$first; in ${at.letter} conditionally: $text');
      }
      final atText = _limitInBrackets(a.item, atLimit, en: en);
      return _tr(en, '$first, mieści się w ${at.letter} ($atText)',
          '$first, within ${at.letter} ($atText)');
    case Iso5817Outcome.fail:
      final d = a.limits[Iso5817Level.d]!;
      final allNotPermitted = a.limits.values
          .every((l) => l.status == Iso5817LimitStatus.notPermitted);
      if (allNotPermitted) {
        return _tr(en, 'Niedopuszczalne na każdym poziomie (B, C, D)',
            'Not permitted at any level (B, C, D)');
      }
      if (_onlyLengthFails(a, d)) {
        return _tr(
            en,
            'Niedopuszczalne — niezgodność długa, a limity dotyczą tylko '
                'krótkich',
            'Not acceptable — a long imperfection; the limits cover short '
                'ones only');
      }
      if (d.status == Iso5817LimitStatus.value) {
        final dText = _limitInBrackets(a.item, d, en: en);
        return d.isAngle
            ? _tr(en, 'Niedopuszczalne — nie spełnia też D ($dText)',
                'Not acceptable — does not meet D either ($dText)')
            : _tr(en, 'Niedopuszczalne — przekracza też D ($dText)',
                'Not acceptable — exceeds D as well ($dText)');
      }
      return _tr(en, 'Niedopuszczalne', 'Not acceptable');
    case Iso5817Outcome.conditional:
      final rule = reqLimit.rule!;
      final text = _lowerFirst(en ? rule.textEn : rule.textPl);
      return _tr(en, 'W $req: $text — rozstrzyga specyfikacja',
          'In $req: $text — the specification decides');
    case Iso5817Outcome.incomplete:
      switch (reqLimit.status) {
        case Iso5817LimitStatus.needsThickness:
          return _tr(en, 'Podaj grubość t', 'Enter thickness t');
        case Iso5817LimitStatus.outOfScope:
          return _tr(en, 't < 0,5 mm — poza zakresem EN ISO 5817',
              't < 0.5 mm — outside the scope of EN ISO 5817');
        case Iso5817LimitStatus.needsDimension:
          return _tr(en, 'Podaj ${iso5817DimName(reqLimit.missingDim!, en: en)}',
              'Enter ${iso5817DimName(reqLimit.missingDim!, en: en)}');
        default:
          return a.item.measure == Iso5817Measure.angleDeg
              ? _tr(en, 'Wpisz zmierzony kąt', 'Enter the measured angle')
              : _tr(en, 'Wpisz zmierzoną wartość', 'Enter the measured value');
      }
  }
}

/// Zdanie uzupełniające (albo pusty): ostrzejszy spełniony poziom.
String iso5817Subline(Iso5817Assessment a, {required bool en}) {
  if (a.outcome != Iso5817Outcome.pass) return '';
  final s = a.strictestMet;
  if (s == null || s.strictness >= a.required.strictness) return '';
  final lim = a.limits[s]!;
  if (lim.status != Iso5817LimitStatus.value) {
    return _tr(en, 'Spełnia również ${s.letter}', 'Also meets ${s.letter}');
  }
  final text = _limitInBrackets(a.item, lim, en: en);
  return _tr(en, 'Spełnia również ${s.letter} ($text)',
      'Also meets ${s.letter} ($text)');
}

/// Zastrzeżenie — na ekranie i w każdym udostępnionym wyniku.
String iso5817Disclaimer({required bool en}) => _tr(
      en,
      'Wiążące są wymagania projektu / specyfikacji i aktualne wydanie '
          'normy. Wartości wg EN ISO 5817:2014, tablica 1; wydanie '
          'EN ISO 5817:2023 zastąpiło je i w kilku pozycjach różni się. '
          'Norma dotyczy t ≥ 0,5 mm i nie ocenia metalurgii (np. wielkość '
          'ziarna, twardość). Niezgodności systematyczne dopuszcza tylko '
          'poziom D.',
      'The project requirements / specification and the current edition of '
          'the standard are binding. Values per EN ISO 5817:2014, Table 1; '
          'EN ISO 5817:2023 superseded it and differs in a few items. The '
          'standard covers t ≥ 0.5 mm and does not assess metallurgy '
          '(e.g. grain size, hardness). Systematic imperfections are '
          'permitted in level D only.',
    );

String _kindText(Iso5817WeldKind kind, {required bool en}) => switch (kind) {
      Iso5817WeldKind.butt => _tr(en, 'Spoina czołowa', 'Butt weld'),
      Iso5817WeldKind.fillet => _tr(en, 'Spoina pachwinowa', 'Fillet weld'),
    };

/// Tekst do protokołu (udostępnianie).
String buildIso5817Report({
  required Iso5817Assessment assessment,
  required Iso5817WeldKind kind,
  required Iso5817Input input,
  required bool en,
  DateTime? date,
}) {
  final a = assessment;
  final item = a.item;
  String n(double v) => iso5817Num(v, en: en);
  final dims = <String>[
    _kindText(kind, en: en),
    if (input.t != null) 't = ${n(input.t!)} mm',
    if (input.b != null) _tr(en, 'b lica = ${n(input.b!)} mm',
        'face b = ${n(input.b!)} mm'),
    if (kind == Iso5817WeldKind.butt && input.bRoot != null)
      _tr(en, 'b grani = ${n(input.bRoot!)} mm',
          'root b = ${n(input.bRoot!)} mm'),
    if (kind == Iso5817WeldKind.fillet && input.a != null)
      'a = ${n(input.a!)} mm',
  ];
  final name = en ? item.nameEn : item.namePl;
  final lengthNote = !a.anyShortOnly
      ? ''
      : a.isShort
          ? _tr(en, ' (niezgodność krótka)', ' (short imperfection)')
          : _tr(en, ' (niezgodność długa)', ' (long imperfection)');
  final measuredLine = switch (item.measure) {
    Iso5817Measure.presence => _tr(en, 'Stwierdzono: tak', 'Found: yes'),
    _ when a.measured == null => _tr(en, 'Pomiar: —', 'Measurement: —'),
    _ => '${_tr(en, 'Pomiar', 'Measurement')}: '
        '${item.symbol} = ${n(a.measured!)}${_unit(item)}$lengthNote',
  };
  final limits = [
    for (final level in Iso5817Level.values)
      '${level.letter} ${iso5817LimitValueText(a.limits[level]!, en: en)}',
  ].join(' · ');
  final reqLimit = a.requiredLimit;
  final rule = reqLimit.rule;
  final calc = iso5817LimitCalc(reqLimit, input, en: en);
  final subline = iso5817Subline(a, en: en);
  final req = a.required.letter;
  final d = date;
  String two(int v) => v.toString().padLeft(2, '0');
  return [
    _tr(en, 'Odbiór wizualny spoiny (VT) — $kIso5817Edition, tablica 1',
        'Visual weld inspection (VT) — $kIso5817Edition, Table 1'),
    if (d != null)
      '${_tr(en, 'Data', 'Date')}: '
          '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}',
    dims.join(' · '),
    _tr(en, 'Wymagany poziom jakości: $req', 'Required quality level: $req'),
    '${_tr(en, 'Niezgodność', 'Imperfection')}: '
        '${item.no} $name (ISO 6520-1: ${item.codes.join(', ')})',
    measuredLine,
    '${_tr(en, 'Limity', 'Limits')}: $limits',
    if (rule != null)
      '${_tr(en, 'Wzór', 'Rule')} ($req): '
          '${iso5817RuleText(rule, en: en, symbol: item.symbol)}'
          '${calc.isEmpty ? '' : ' → $calc'}',
    '${_tr(en, 'Wynik', 'Result')}: ${iso5817Headline(a, en: en)}'
        '${subline.isEmpty ? '' : '. $subline'}',
    iso5817Disclaimer(en: en),
  ].join('\n');
}
