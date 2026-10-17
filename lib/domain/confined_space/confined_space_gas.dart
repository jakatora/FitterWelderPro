/// Gazy, jednostki, progi i pomiary atmosfery w przestrzeni zamkniętej.
///
/// Zasady zapisane w kodzie (i w testach):
/// * wartość pomiaru i progu przechowuje się TAK, JAK JĄ WPISANO (liczba
///   + jednostka) i tak się ją wyświetla; ocenia się ją w jednostce
///   kanonicznej: O₂ — % obj., palne — % DGW, CO i H₂S — ppm (mg/m³ →
///   ppm przez objętość molową 24,05 dm³/mol przy 20 °C i 101,3 kPa,
///   warunkach odniesienia NDS);
/// * progi domyślne są twardymi granicami (przepis albo przyjęta
///   praktyka, zob. confined_space_sources.dart) i wolno je zmieniać TYLKO
///   w bezpieczną stronę: dolny próg tlenu w górę, górny tlenu, % DGW, CO
///   i H₂S — w dół;
/// * „nieprzekraczający” — wynik równy progowi przechodzi, większy nie
///   (dolny próg tlenu: równy przechodzi, mniejszy nie);
/// * wpisane liczby zaokrągla się do 0,001 — to, co widać, jest dokładnie
///   tym, co się ocenia.
///
/// Czysty Dart.
library;

import 'confined_space_sources.dart';

/// Tolerancja porównań — tylko szum liczb zmiennoprzecinkowych.
const double kCsEps = 1e-9;

/// Liczba zaokrąglona do 0,001 (wartość wpisana = wartość oceniana).
double csRound(double v) => (v * 1000).roundToDouble() / 1000;

/// `0.5` → „0,5” (PL) / „0.5” (EN); do 3 miejsc, bez zbędnych zer — wynik
/// 19,495 nie może wyglądać jak 19,5.
String formatCsNumber(double v, {required bool en}) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// Jednostki odczytu.
enum CsUnit {
  pctVol('% obj.', '% vol'),
  pctLel('% DGW', '% LEL'),
  ppm('ppm', 'ppm'),
  mgM3('mg/m³', 'mg/m³');

  const CsUnit(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;

  static CsUnit? byName(Object? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// Mierzone gazy — w kolejności pomiaru (tlen, palne, toksyczne;
/// OSHA 1910.146(d)(5)).
enum CsGas {
  o2('O₂', 'O₂', CsUnit.pctVol, [CsUnit.pctVol]),
  lel('Gazy palne', 'Flammables', CsUnit.pctLel, [CsUnit.pctLel]),
  co('CO', 'CO', CsUnit.ppm, [CsUnit.ppm, CsUnit.mgM3]),
  h2s('H₂S', 'H₂S', CsUnit.ppm, [CsUnit.ppm, CsUnit.mgM3]);

  const CsGas(this.labelPl, this.labelEn, this.canonical, this.units);
  final String labelPl;
  final String labelEn;

  /// Jednostka, w której gaz się ocenia.
  final CsUnit canonical;

  /// Jednostki, w których wolno wpisać odczyt / próg.
  final List<CsUnit> units;

  String label({required bool en}) => en ? labelEn : labelPl;

  /// Krótko w wierszu pomiaru: „O₂”, „DGW” / „LEL”, „CO”, „H₂S”.
  String short({required bool en}) => switch (this) {
        CsGas.lel => en ? 'LEL' : 'DGW',
        _ => label(en: en),
      };

  /// Gaz zawsze wymagany (tlen i palne) — nie da się go odznaczyć.
  bool get alwaysRequired => this == CsGas.o2 || this == CsGas.lel;

  /// Masa molowa (g/mol) do przeliczenia mg/m³ → ppm; `null` dla O₂ i DGW.
  double? get molarMass => switch (this) {
        CsGas.co => kCsCoMolarMass,
        CsGas.h2s => kCsH2sMolarMass,
        _ => null,
      };

  static CsGas? byName(Object? name) {
    for (final g in values) {
      if (g.name == name) return g;
    }
    return null;
  }
}

/// Wartość tak, jak ją wpisano: liczba (zaokr. 0,001) i jednostka.
class CsQty {
  final double value;
  final CsUnit unit;
  const CsQty(this.value, this.unit);

  Map<String, Object?> toJson() => {'v': value, 'u': unit.name};

  /// `null` dla złej liczby (ujemna, nieskończona) albo jednostki spoza
  /// [CsGas.units].
  static CsQty? fromJson(Object? raw, CsGas gas) {
    if (raw is! Map) return null;
    final v = raw['v'];
    final u = CsUnit.byName(raw['u']);
    if (v is! num || u == null || !gas.units.contains(u)) return null;
    final q = CsQty(csRound(v.toDouble()), u);
    return csQtyInRange(gas, q) ? q : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CsQty && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);
}

/// Wartość w jednostce kanonicznej gazu.
double csCanonical(CsGas gas, CsQty q) {
  if (q.unit == CsUnit.mgM3) {
    return q.value * kCsMolarVolume / gas.molarMass!;
  }
  return q.value;
}

/// Zakres odczytu, który aplikacja przyjmuje: O₂ i DGW 0–100 %; CO, H₂S
/// 0–1 000 000 (100 % obj. = 1 000 000 ppm). Więcej to literówka.
bool csQtyInRange(CsGas gas, CsQty q) {
  if (!gas.units.contains(q.unit)) return false;
  final v = q.value;
  if (!v.isFinite || v < 0) return false;
  return switch (gas) {
    CsGas.o2 || CsGas.lel => v <= 100,
    _ => v <= 1000000,
  };
}

/// „20,9 %”, „0 % DGW”, „23 mg/m³” — tak, jak wpisano.
String formatCsQty(CsGas gas, CsQty q, {required bool en}) {
  final n = formatCsNumber(q.value, en: en);
  return switch (q.unit) {
    CsUnit.pctVol => '$n %',
    CsUnit.pctLel => '$n % ${en ? 'LEL' : 'DGW'}',
    CsUnit.ppm => '$n ppm',
    CsUnit.mgM3 => '$n mg/m³',
  };
}

// ── Progi ───────────────────────────────────────────────────────────────────

/// Którą granicę gazu opisuje próg.
enum CsBound {
  o2Min,
  o2Max,
  lelMax,
  coMax,
  h2sMax;

  CsGas get gas => switch (this) {
        CsBound.o2Min || CsBound.o2Max => CsGas.o2,
        CsBound.lelMax => CsGas.lel,
        CsBound.coMax => CsGas.co,
        CsBound.h2sMax => CsGas.h2s,
      };

  /// Dolna granica (wynik nie może być mniejszy) — tylko tlen.
  bool get isMin => this == CsBound.o2Min;

  /// Twarda granica = wartość domyślna (przepis albo przyjęta praktyka).
  CsQty get hardLimit => switch (this) {
        CsBound.o2Min => const CsQty(kCsO2MinPct, CsUnit.pctVol),
        CsBound.o2Max => const CsQty(kCsO2MaxPct, CsUnit.pctVol),
        CsBound.lelMax => const CsQty(kCsLelMaxPct, CsUnit.pctLel),
        CsBound.coMax => const CsQty(kCsCoNdsPpm, CsUnit.ppm),
        CsBound.h2sMax => const CsQty(kCsH2sNdsMgM3, CsUnit.mgM3),
      };

  static CsBound? byName(Object? name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// Próg [q] dla granicy [b] jest dozwolony: nie łagodniejszy niż twarda
/// granica i sensowny (granice tlenu obejmują czyste powietrze 20,9 %).
bool csLimitValid(CsBound b, CsQty q) {
  final gas = b.gas;
  if (!csQtyInRange(gas, q)) return false;
  final v = csCanonical(gas, q);
  final hard = csCanonical(gas, b.hardLimit);
  return switch (b) {
    CsBound.o2Min => v >= hard - kCsEps && v <= kCsO2AirPct + kCsEps,
    CsBound.o2Max => v <= hard + kCsEps && v >= kCsO2AirPct - kCsEps,
    _ => v <= hard + kCsEps,
  };
}

/// Progi z pozwolenia (tak, jak wpisano); `null` = nie wpisano — gazu nie
/// da się wtedy ocenić.
class CsLimits {
  final Map<CsBound, CsQty> values;
  const CsLimits(this.values);

  /// Twarde granice — domyślne progi nowego protokołu.
  static final CsLimits defaults =
      CsLimits({for (final b in CsBound.values) b: b.hardLimit});

  CsQty? operator [](CsBound b) => values[b];

  /// Kopia z nowym progiem; `null` usuwa próg. Próg spoza dozwolonego
  /// zakresu NIE jest przyjmowany — zostaje poprzedni.
  CsLimits withLimit(CsBound b, CsQty? q) {
    if (q != null && !csLimitValid(b, q)) return this;
    final m = {...values};
    if (q == null) {
      m.remove(b);
    } else {
      m[b] = q;
    }
    return CsLimits(m);
  }

  bool get isDefault =>
      values.length == CsBound.values.length &&
      CsBound.values.every((b) => values[b] == b.hardLimit);

  Map<String, Object?> toJson() => {
        for (final b in CsBound.values)
          if (values[b] != null) b.name: values[b]!.toJson(),
      };

  /// Progi niedozwolone albo uszkodzone są pomijane (próg znika → gaz
  /// „bez progu”, nigdy łagodniejszy próg).
  static CsLimits fromJson(Object? raw) {
    if (raw is! Map) return const CsLimits({});
    final m = <CsBound, CsQty>{};
    for (final b in CsBound.values) {
      final q = CsQty.fromJson(raw[b.name], b.gas);
      if (q != null && csLimitValid(b, q)) m[b] = q;
    }
    return CsLimits(m);
  }

  @override
  bool operator ==(Object other) {
    if (other is! CsLimits || other.values.length != values.length) {
      return false;
    }
    return values.entries.every((e) => other.values[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hashAllUnordered(
      values.entries.map((e) => Object.hash(e.key, e.value)));
}

// ── Pomiar ──────────────────────────────────────────────────────────────────

/// Jeden pomiar detektorem (jeden lub kilka gazów naraz).
class CsMeasurement {
  /// Identyfikator pomiaru (usuwanie i „Cofnij” po identyfikatorze — dwa
  /// identyczne odczyty to dwa pomiary). Pusty tylko w starych zapisach;
  /// odczyt protokołu nadaje wtedy identyfikator z pozycji.
  final String id;

  /// Godzina `HH:mm`.
  final String time;

  /// Chwila pomiaru (ms od epoki). O stanie decyduje pomiar NAJPÓŹNIEJSZY
  /// w czasie — porównywany z dokładnością do minuty (tyle widać na
  /// ekranie); pomiary z tej samej minuty to remis, nie kolejność.
  final int at;

  /// Chwila WPISANIA do aplikacji (ms od epoki); `null` w starych zapisach
  /// (wtedy = [at]). Odczyt STOP wpisany później niż decydujący blokuje
  /// zielony stan — zaległy wpis „w normie” z późniejszą godziną nie może
  /// przykryć świeżego alarmu.
  final int? enteredAt;

  /// Odczyty wg gazu (co najmniej jeden).
  final Map<CsGas, CsQty> values;

  /// Miejsce / poziom pomiaru (np. „dno”, „przy włazie”).
  final String place;

  const CsMeasurement({
    this.id = '',
    required this.time,
    required this.at,
    this.enteredAt,
    required this.values,
    this.place = '',
  });

  CsQty? operator [](CsGas g) => values[g];

  /// Chwila wpisania (stare zapisy — chwila pomiaru).
  int get entered => enteredAt ?? at;

  /// Minuta pomiaru — jednostka porównania „który najpóźniejszy”.
  int get minute => at ~/ 60000;

  CsMeasurement withId(String newId) => CsMeasurement(
        id: newId,
        time: time,
        at: at,
        enteredAt: enteredAt,
        values: values,
        place: place,
      );

  Map<String, Object?> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'time': time,
        'at': at,
        if (enteredAt != null) 'entered': enteredAt,
        for (final g in CsGas.values)
          if (values[g] != null) g.name: values[g]!.toJson(),
        'place': place,
      };

  /// `null`, gdy wpis jest uszkodzony: bez chwili pomiaru, bez żadnego
  /// odczytu, z którymkolwiek odczytem nieczytelnym (zły odczyt nie może
  /// zniknąć po cichu, a reszta pomiaru udawać kompletnego) albo — gdy
  /// podano [now] — z chwilą pomiaru dalej w przyszłości niż
  /// [kCsFutureSlack] (taki pomiar przykryłby wszystkie prawdziwe).
  static CsMeasurement? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! num || !at.isFinite) return null;
    if (now != null &&
        at > now.add(kCsFutureSlack).millisecondsSinceEpoch) {
      return null;
    }
    final entered = raw['entered'];
    final values = <CsGas, CsQty>{};
    for (final g in CsGas.values) {
      if (!raw.containsKey(g.name) || raw[g.name] == null) continue;
      final q = CsQty.fromJson(raw[g.name], g);
      if (q == null) return null;
      values[g] = q;
    }
    if (values.isEmpty) return null;
    return CsMeasurement(
      id: raw['id'] is String ? raw['id'] as String : '',
      time: raw['time'] is String ? raw['time'] as String : '',
      at: at.toInt(),
      enteredAt:
          entered is num && entered.isFinite ? entered.toInt() : null,
      values: values,
      place: raw['place'] is String ? raw['place'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! CsMeasurement ||
        other.id != id ||
        other.time != time ||
        other.at != at ||
        other.enteredAt != enteredAt ||
        other.place != place ||
        other.values.length != values.length) {
      return false;
    }
    return values.entries.every((e) => other.values[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hash(
      id,
      time,
      at,
      enteredAt,
      place,
      Object.hashAllUnordered(
          values.entries.map((e) => Object.hash(e.key, e.value))));
}

/// Pomiar świeży: nie starszy niż [maxAgeMin] i nie dalej w przyszłości niż
/// [kCsFutureSlack] względem [now].
bool csMeasurementFresh(CsMeasurement m, DateTime now, int maxAgeMin) {
  final t = now.millisecondsSinceEpoch;
  if (m.at > t + kCsFutureSlack.inMilliseconds) return false;
  return t - m.at <= maxAgeMin * 60000;
}

/// Pomiary w kolejności czasu (stabilnie: przy tej samej chwili — kolejność
/// wpisów; ocena i tak traktuje tę samą minutę jako remis).
List<CsMeasurement> csMeasurementsChrono(List<CsMeasurement> list) {
  final indexed = [...list.indexed]..sort((a, b) {
      final byAt = a.$2.at.compareTo(b.$2.at);
      return byAt != 0 ? byAt : a.$1.compareTo(b.$1);
    });
  return List.unmodifiable([for (final (_, m) in indexed) m]);
}

// ── Ocena odczytu ───────────────────────────────────────────────────────────

/// Ocena jednego odczytu gazu względem progów.
enum CsReadingState {
  ok,

  /// Poniżej dolnego progu (tylko tlen — niedotlenienie).
  low,

  /// Powyżej górnego progu (tlen — wzbogacenie; palne, CO, H₂S —
  /// przekroczenie).
  high,

  /// Brak progu, a odczyt mieści się w twardej granicy — nie da się go
  /// ocenić względem pozwolenia (przekroczenie twardej granicy to zawsze
  /// STOP, z progiem czy bez).
  noLimit;

  bool get stop => this == low || this == high;
}

/// Ocena odczytu. Brakujący próg zastępuje TWARDA GRANICA ([CsBound
/// .hardLimit]): tlen 5 % albo CO 500 ppm przy pustym polu progu to STOP,
/// nie „brak progu”.
CsReadingState csReadingState(CsGas gas, CsQty q, CsLimits limits) {
  final v = csCanonical(gas, q);
  double limitOf(CsBound b) => csCanonical(gas, limits[b] ?? b.hardLimit);
  switch (gas) {
    case CsGas.o2:
      if (v < limitOf(CsBound.o2Min) - kCsEps) return CsReadingState.low;
      if (v > limitOf(CsBound.o2Max) + kCsEps) return CsReadingState.high;
      if (limits[CsBound.o2Min] == null || limits[CsBound.o2Max] == null) {
        return CsReadingState.noLimit;
      }
      return CsReadingState.ok;
    case CsGas.lel:
    case CsGas.co:
    case CsGas.h2s:
      final bound = csMaxBound(gas)!;
      if (v > limitOf(bound) + kCsEps) return CsReadingState.high;
      return limits[bound] == null
          ? CsReadingState.noLimit
          : CsReadingState.ok;
  }
}

/// Górna granica gazu (dla tlenu `null` — ma dwie).
CsBound? csMaxBound(CsGas gas) => switch (gas) {
      CsGas.o2 => null,
      CsGas.lel => CsBound.lelMax,
      CsGas.co => CsBound.coMax,
      CsGas.h2s => CsBound.h2sMax,
    };
