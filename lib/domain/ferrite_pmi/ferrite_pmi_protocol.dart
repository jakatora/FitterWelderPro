/// Protokół „Ferryt i PMI”: dane pomiaru, wymaganie ferrytu z odczytami
/// w wielu miejscach oraz pozycje PMI (XRF). Zapis JSON do historii.
///
/// Odporność zapisu: uszkodzone protokoły / miejsca / pozycje / odczyty są
/// liczone ([FerritePmiParse]) — magazyn robi kopię surowego tekstu,
/// ekran pokazuje baner. Nieczytelne wartości techniczne pozostają jako „?”,
/// aby nie zamienić ich w brak wymagania lub zerową niepewność.
/// Odczyty zapisywane jako tekst „tak, jak
/// wpisano” (bez zaokrąglania).
///
/// Czysty Dart.
library;

import '../../utils/decimal_parse.dart';
import 'ferrite.dart';
import 'ferrite_pmi_sources.dart';
import 'pmi.dart';

/// Pozycja PMI: element (rura, kształtka, spoina) i odczyty XRF.
class PmiItem {
  final String id;

  /// Oznaczenie, np. „Rura poz. 3, wytop 12345”.
  final String label;

  /// Id gatunku z tabeli ('' — nie wybrano).
  final String gradeId;

  /// Wariant normy w obrębie gatunku ('' — pierwszy, EN).
  final String specKey;
  final Map<PmiElement, String> readings;
  final Map<PmiElement, String> uncertainty;

  const PmiItem({
    required this.id,
    this.label = '',
    this.gradeId = '',
    this.specKey = '',
    this.readings = const {},
    this.uncertainty = const {},
  });

  PmiGrade? get grade => pmiGradeById(gradeId);

  /// Wybrany wariant normy; bez wyboru — pierwszy (EN). Nieznany klucz
  /// (zapis z innej wersji) → `null` (brak werdyktu, nie zgadujemy).
  PmiSpec? get spec {
    final g = grade;
    if (g == null) return null;
    if (specKey.isEmpty) return g.specs.first;
    return g.specByKey(specKey);
  }

  PmiResult evaluate() => evaluatePmi(
      grade: grade,
      spec: spec,
      readings: readings,
      uncertainty: uncertainty,
      table: kPmiGrades);

  bool get isBlank =>
      label.trim().isEmpty &&
      gradeId.isEmpty &&
      readings.values.every((v) => v.trim().isEmpty) &&
      uncertainty.values.every((v) => v.trim().isEmpty);

  PmiItem copyWith({
    String? label,
    String? gradeId,
    String? specKey,
    Map<PmiElement, String>? readings,
    Map<PmiElement, String>? uncertainty,
  }) =>
      PmiItem(
        id: id,
        label: label ?? this.label,
        gradeId: gradeId ?? this.gradeId,
        specKey: specKey ?? this.specKey,
        readings: readings ?? this.readings,
        uncertainty: uncertainty ?? this.uncertainty,
      );

  static Map<String, String> _mapOut(Map<PmiElement, String> m) => {
        for (final e in PmiElement.values)
          if ((m[e] ?? '').isNotEmpty) e.name: m[e]!,
      };

  /// Odczyty z JSON i liczba uszkodzeń. Nieznany pierwiastek uniemożliwia
  /// odczyt całej pozycji (protokół zachowa jej oryginalny JSON).
  /// Nieczytelna wartość znanego pierwiastka pozostaje jako „?”.
  static (Map<PmiElement, String>?, int) _mapIn(Object? raw) {
    if (raw == null) return (const {}, 0);
    if (raw is! Map) return ({for (final e in PmiElement.values) e: '?'}, 1);
    final out = <PmiElement, String>{};
    var lost = 0;
    for (final MapEntry(:key, :value) in raw.entries) {
      final e = PmiElement.byName(key);
      if (e == null) {
        return (null, lost + 1);
      }
      out[e] = value is String ? value : '?';
      if (value is! String) lost++;
    }
    return (out, lost);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'grade': gradeId,
        'spec': specKey,
        'r': _mapOut(readings),
        'u': _mapOut(uncertainty),
      };

  /// `null` dla wpisu bez id albo z nieznanymi pierwiastkami. Wywołujący
  /// musi zachować oryginalny wpis; nie oceniamy częściowego składu.
  static (PmiItem?, int) fromJson(Object? raw) {
    if (raw is! Map) return (null, 0);
    final id = raw['id'];
    if (id is! String || id.isEmpty) return (null, 0);
    String s(Object? v) => v is String ? v : '';
    final (r, lostR) = _mapIn(raw['r']);
    final (u, lostU) = _mapIn(raw['u']);
    if (r == null || u == null) return (null, lostR + lostU);
    var lost = lostR + lostU;
    String technical(Object? value) {
      if (value == null || value is String) return s(value);
      lost++;
      return '?';
    }

    final grade = technical(raw['grade']);
    final spec = technical(raw['spec']);
    return (
      PmiItem(
        id: id,
        label: s(raw['label']),
        gradeId: grade,
        specKey: spec,
        readings: r,
        uncertainty: u,
      ),
      lost,
    );
  }
}

class FerritePmiProtocol {
  final String id;

  /// Data pomiaru `YYYY-MM-DD`.
  final String date;

  /// Obiekt / linia / nr spoiny.
  final String title;
  final String inspector;

  /// Przyrząd: ferrytomierz / XRF — model, nr, data kalibracji.
  final String instrument;
  final String notes;

  // ── Ferryt ──
  /// Id presetu ('' — zakres ze specyfikacji wpisany ręcznie).
  final String presetId;
  final String customMin;
  final String customMax;
  final FerriteUnit customUnit;

  /// Jednostka, którą pokazuje ferrytomierz.
  final FerriteUnit readingUnit;
  final FerriteRule rule;

  /// N ze specyfikacji (reguła „średnia z N”) — tekst z pola.
  final String minCount;
  final List<FerriteSite> sites;

  // ── PMI ──
  final List<PmiItem> pmi;

  /// Original JSON of entries that cannot be interpreted. Never guess their
  /// location, readings or grade; retain them across edits and reloads.
  final List<Object?> unreadableSites;
  final List<Object?> unreadablePmi;
  bool get incomplete => unreadableSites.isNotEmpty || unreadablePmi.isNotEmpty;
  static const _unreadableKey = '_unreadableMeasurement';

  final int createdAt;
  final int updatedAt;

  /// Ile elementów wymagało odzyskiwania przy tym odczycie. Surowe dane
  /// nieczytelnych miejsc/pozycji są zachowane w unreadableSites/Pmi.
  final int droppedOnLoad;

  const FerritePmiProtocol({
    required this.id,
    required this.date,
    this.title = '',
    this.inspector = '',
    this.instrument = '',
    this.notes = '',
    this.presetId = '',
    this.customMin = '',
    this.customMax = '',
    this.customUnit = FerriteUnit.fn,
    this.readingUnit = FerriteUnit.fn,
    this.rule = FerriteRule.everyReading,
    this.minCount = '',
    this.sites = const [],
    this.pmi = const [],
    this.unreadableSites = const [],
    this.unreadablePmi = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
    this.droppedOnLoad = 0,
  });

  /// Nowy protokół: jedno puste miejsce „spoina” i jedna pusta pozycja PMI.
  factory FerritePmiProtocol.blank(
      {required String id, required DateTime now}) {
    final ms = now.millisecondsSinceEpoch;
    return FerritePmiProtocol(
      id: id,
      date: ferritePmiDate(now),
      sites: [FerriteSite(id: '$id-s1', location: FerriteLocation.weld)],
      pmi: [PmiItem(id: '$id-p1')],
      createdAt: ms,
      updatedAt: ms,
    );
  }

  /// Preset wybrany w protokole (`null` — własny zakres albo nieznany id).
  FerritePreset? get preset =>
      presetId.isEmpty ? null : ferritePresetById(presetId);

  /// Obowiązujące wymaganie. `null` — preset o nieznanym id (zapis z innej
  /// wersji aplikacji): brak werdyktu, nie zgadujemy. Własny zakres: puste
  /// pole = granica otwarta, nieczytelne pole = zakres nieprawidłowy.
  FerriteRequirement? get requirement {
    if (presetId.isNotEmpty) return preset?.requirement;
    double? bound(String t) {
      if (t.trim().isEmpty) return null;
      return parseDecimal(t) ?? double.nan;
    }

    return FerriteRequirement(
        min: bound(customMin), max: bound(customMax), unit: customUnit);
  }

  List<FerriteSiteResult> evaluateFerrite() => [
        for (final s in sites)
          evaluateFerriteSite(
            s,
            requirement: requirement,
            readingUnit: readingUnit,
            rule: rule,
            minCountText: minCount,
            preset: preset,
          ),
      ];

  /// Miejsca z odczytami albo oznaczeniem (puste pomijane w ocenie
  /// protokołu i w tekście).
  List<FerriteSite> get filledSites => [
        for (final s in sites)
          if (!s.isBlank) s,
      ];

  List<PmiItem> get filledPmi => [
        for (final p in pmi)
          if (!p.isBlank) p,
      ];

  bool get hasFerrite => filledSites.isNotEmpty || unreadableSites.isNotEmpty;
  bool get hasPmi => filledPmi.isNotEmpty || unreadablePmi.isNotEmpty;

  /// Werdykt ferrytu z miejsc wypełnionych.
  FerriteVerdict get ferriteVerdict {
    final verdict = ferriteOverall([
      for (final r in evaluateFerrite())
        if (!r.site.isBlank) r,
    ]);
    return unreadableSites.isNotEmpty && verdict != FerriteVerdict.fail
        ? FerriteVerdict.none
        : verdict;
  }

  /// Nic nie wpisano — nie trafia do historii.
  bool get isBlank =>
      !incomplete &&
      title.trim().isEmpty &&
      inspector.trim().isEmpty &&
      instrument.trim().isEmpty &&
      notes.trim().isEmpty &&
      customMin.trim().isEmpty &&
      customMax.trim().isEmpty &&
      minCount.trim().isEmpty &&
      presetId.isEmpty &&
      sites.every((s) => s.isBlank) &&
      pmi.every((p) => p.isBlank);

  static const Object _keep = Object();

  FerritePmiProtocol copyWith({
    String? id,
    String? date,
    String? title,
    String? inspector,
    String? instrument,
    String? notes,
    String? presetId,
    String? customMin,
    String? customMax,
    FerriteUnit? customUnit,
    FerriteUnit? readingUnit,
    FerriteRule? rule,
    String? minCount,
    List<FerriteSite>? sites,
    List<PmiItem>? pmi,
    List<Object?>? unreadableSites,
    List<Object?>? unreadablePmi,
    int? updatedAt,
    Object? droppedOnLoad = _keep,
  }) =>
      FerritePmiProtocol(
        id: id ?? this.id,
        date: date ?? this.date,
        title: title ?? this.title,
        inspector: inspector ?? this.inspector,
        instrument: instrument ?? this.instrument,
        notes: notes ?? this.notes,
        presetId: presetId ?? this.presetId,
        customMin: customMin ?? this.customMin,
        customMax: customMax ?? this.customMax,
        customUnit: customUnit ?? this.customUnit,
        readingUnit: readingUnit ?? this.readingUnit,
        rule: rule ?? this.rule,
        minCount: minCount ?? this.minCount,
        sites: sites ?? this.sites,
        pmi: pmi ?? this.pmi,
        unreadableSites: unreadableSites ?? this.unreadableSites,
        unreadablePmi: unreadablePmi ?? this.unreadablePmi,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        droppedOnLoad: identical(droppedOnLoad, _keep)
            ? this.droppedOnLoad
            : droppedOnLoad as int,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'date': date,
        'title': title,
        'inspector': inspector,
        'instrument': instrument,
        'notes': notes,
        'preset': presetId,
        'min': customMin,
        'max': customMax,
        'unit': customUnit.name,
        'readUnit': readingUnit.name,
        'rule': rule.name,
        'n': minCount,
        'sites': [
          for (final s in sites) s.toJson(),
          for (final raw in unreadableSites) {_unreadableKey: raw},
        ],
        'pmi': [
          for (final p in pmi) p.toJson(),
          for (final raw in unreadablePmi) {_unreadableKey: raw},
        ],
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// `null` dla wpisu bez id, daty lub z nieobsługiwaną wersją formatu.
  /// Nieznane jednostki / reguła →
  /// wpis odrzucony (nie zgadujemy jednostki — to zmienia werdykt).
  static FerritePmiProtocol? fromJson(Object? raw) {
    if (raw is! Map) return null;
    // Legacy records omitted v; an explicit unknown schema must never be
    // interpreted using today's measurement rules. The store preserves raw JSON.
    if (raw.containsKey('v') && raw['v'] != 1) return null;
    String s(Object? v) => v is String ? v : '';
    int i(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    final id = s(raw['id']);
    final date = s(raw['date']);
    final unit = FerriteUnit.byName(raw['unit']);
    final readUnit = FerriteUnit.byName(raw['readUnit']);
    final rule = FerriteRule.byName(raw['rule']);
    if (id.isEmpty || date.isEmpty) return null;
    if (unit == null || readUnit == null || rule == null) return null;
    var dropped = 0;
    List<Object?> entries(Object? value, List<Object?> unreadable) {
      if (value == null) return const [];
      if (value is List) return value;
      unreadable.add(value);
      dropped++;
      return const [];
    }

    bool retained(Object? value, List<Object?> unreadable) {
      if (value is Map &&
          value.length == 1 &&
          value.containsKey(_unreadableKey)) {
        unreadable.add(value[_unreadableKey]);
        return true;
      }
      return false;
    }

    String technical(Object? value) {
      if (value == null || value is String) return s(value);
      dropped++;
      return '?';
    }

    final sites = <FerriteSite>[];
    // The editor keys controllers and updates by id. A second entry with the
    // same id must retain its original data without sharing editable fields.
    final siteIds = <String>{};
    final unreadableSites = <Object?>[];
    for (final e in entries(raw['sites'], unreadableSites)) {
      if (retained(e, unreadableSites)) continue;
      final (site, lost) = FerriteSite.fromJson(e);
      if (site == null || !siteIds.add(site.id)) {
        unreadableSites.add(e);
        dropped++;
      } else {
        sites.add(site);
        dropped += lost;
      }
    }
    final pmi = <PmiItem>[];
    final pmiIds = <String>{};
    final unreadablePmi = <Object?>[];
    for (final e in entries(raw['pmi'], unreadablePmi)) {
      if (retained(e, unreadablePmi)) continue;
      final (p, lost) = PmiItem.fromJson(e);
      if (p == null || !pmiIds.add(p.id)) {
        unreadablePmi.add(e);
        dropped++;
      } else {
        pmi.add(p);
        dropped += lost;
      }
    }
    return FerritePmiProtocol(
      id: id,
      date: date,
      title: s(raw['title']),
      inspector: s(raw['inspector']),
      instrument: s(raw['instrument']),
      notes: s(raw['notes']),
      presetId: technical(raw['preset']),
      customMin: technical(raw['min']),
      customMax: technical(raw['max']),
      customUnit: unit,
      readingUnit: readUnit,
      rule: rule,
      minCount: technical(raw['n']),
      sites: sites,
      pmi: pmi,
      unreadableSites: unreadableSites,
      unreadablePmi: unreadablePmi,
      createdAt: i(raw['createdAt']),
      updatedAt: i(raw['updatedAt']),
      droppedOnLoad: dropped,
    );
  }
}

/// Wynik odczytu historii: ile protokołów i elementów odrzucono.
class FerritePmiParse {
  final List<FerritePmiProtocol> protocols;
  final int droppedProtocols;
  final int droppedItems;
  final int recoveredProtocols;

  const FerritePmiParse(
      this.protocols, this.droppedProtocols, this.droppedItems,
      {this.recoveredProtocols = 0});

  bool get damaged =>
      droppedProtocols > 0 || droppedItems > 0 || recoveredProtocols > 0;
}

/// Lista protokołów z JSON. Nie-lista → [FormatException] (zapis
/// nieczytelny w całości).
FerritePmiParse ferritePmiParse(Object? raw) {
  if (raw is! List) throw const FormatException('not a list');
  final out = <FerritePmiProtocol>[];
  // Reserve every original id, including ids later in the input, so generated
  // identities never collide with another saved protocol. Only metadata changes.
  final reservedIds = <String>{
    for (final e in raw)
      if (e is Map && e['id'] is String) e['id'] as String,
  };
  final seen = <String>{};
  var recovered = 0;
  var droppedProtocols = 0;
  var droppedItems = 0;
  for (final e in raw) {
    var p = FerritePmiProtocol.fromJson(e);
    if (p == null) {
      droppedProtocols++;
    } else {
      if (!seen.add(p.id)) {
        var suffix = 1;
        String id;
        do {
          id = '${p.id}-recovered-${suffix++}';
        } while (!reservedIds.add(id));
        p = p.copyWith(id: id);
        recovered++;
      }
      out.add(p);
      droppedItems += p.droppedOnLoad;
    }
  }
  return FerritePmiParse(out, droppedProtocols, droppedItems,
      recoveredProtocols: recovered);
}

List<Map<String, Object?>> ferritePmiToJson(List<FerritePmiProtocol> list) =>
    [for (final p in list) p.toJson()];

/// Najnowsze na górze: data malejąco, potem ostatnia zmiana.
List<FerritePmiProtocol> sortFerritePmi(List<FerritePmiProtocol> list) =>
    [...list]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.updatedAt.compareTo(a.updatedAt);
      });

/// `YYYY-MM-DD`.
String ferritePmiDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
