/// „Tolerancje spoola” — kontrola wymiarów prefabrykatu przed wysyłką na
/// budowę: pozycje pomiaru (wymiar z izometrii, wymiar zmierzony →
/// odchyłka, tolerancja, werdykt), zestaw tolerancji (PFI ES-3 /
/// EN 13480-4 / z projektu) i protokół spoola.
///
/// Domena czysta (bez Fluttera i bez zegara — `now` zawsze z zewnątrz).
/// Ekran: `lib/features/spool_check/`, źródła wartości:
/// `spool_check_sources.dart`, jednostki: `spool_units.dart`.
///
/// Zasady werdyktu:
/// * werdykt liczony w mm (wartości kanoniczne) — jednostka wyświetlania
///   go nie zmienia;
/// * |odchyłka| = tolerancja → w tolerancji („nie więcej niż”);
/// * brak wymiaru z rysunku, pomiaru, średnicy albo tolerancji = BRAK
///   werdyktu, nigdy „OK”; nieczytelny zapis tolerancji nie jest po cichu
///   zastępowany wartością z normy;
/// * spool „OK” tylko wtedy, gdy KAŻDA pozycja ma werdykt i jest
///   w tolerancji; jedna pozycja poza — spool poza tolerancją.
library;

import 'dart:math' as math;

import 'spool_check_sources.dart';
import 'spool_units.dart';

export 'spool_check_sources.dart';
export 'spool_units.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RODZAJE POZYCJI, ZESTAWY TOLERANCJI, WERDYKTY
// ═══════════════════════════════════════════════════════════════════════════

/// Rodzaj pozycji pomiaru. Nazwy enumów są kluczami JSON — nie zmieniać.
enum SpoolItemKind {
  /// Czoło–czoło (face-to-face).
  faceToFace,

  /// Środek–czoło (center-to-face).
  centerToFace,

  /// Środek–środek (center-to-center).
  centerToCenter,

  /// Położenie odgałęzienia / uchwytu wzdłuż rury.
  branchPosition,

  /// Skręt otworów śrub kołnierza względem osi (dwuotworowanie).
  boltRotation,

  /// Nachylenie czoła kołnierza (odchyłka na średnicy).
  faceTilt,

  /// Przesunięcie boczne odgałęzienia od położenia z rysunku.
  branchOffset,

  /// Prostoliniowość / łuk.
  straightness;

  /// Wymiar z rysunku i zmierzony — odchyłka = różnica.
  bool get isLinear => switch (this) {
        faceToFace || centerToFace || centerToCenter || branchPosition => true,
        _ => false,
      };

  static SpoolItemKind? byName(Object? name) =>
      values.where((k) => k.name == name).firstOrNull;
}

/// Zestaw tolerancji protokołu. Nazwy enumów są kluczami JSON.
enum SpoolToleranceSet {
  /// PFI ES-3 — wartości wbudowane tam, gdzie je potwierdzono.
  pfiEs3,

  /// EN 13480-4 zał. B — wartości wpisuje monter (z normy, dla
  /// uzgodnionej klasy).
  en13480,

  /// Tolerancje z projektu / specyfikacji — wpisuje monter.
  project;

  static SpoolToleranceSet? byName(Object? name) =>
      values.where((s) => s.name == name).firstOrNull;
}

/// Podstawa tolerancji pozycji — „wobec czego oceniono”.
enum SpoolToleranceBasis {
  es3Linear,
  es3Rotation,
  es3Alignment,

  /// Wartość wpisana przy pozycji, gdy zestaw to ES-3 (z rysunku /
  /// projektu — zastępuje ES-3 albo uzupełnia, gdy ES-3 nie podaje).
  drawing,

  /// Wartość wpisana z EN 13480-4 zał. B.
  en13480,

  /// Wartość wpisana z projektu.
  project,
}

/// Dlaczego pozycja nie ma werdyktu.
enum SpoolGap {
  noDrawing,
  noMeasured,
  noPcd,
  noDiameter,
  noDn,
  dnBeyondEs3,
  notInEs3,
  noTolerance,
  toleranceInvalid,

  /// Tolerancja niesymetryczna z jedną wartością (+ albo −) — wpisz obie.
  toleranceAsymIncomplete,
  toleranceDamaged,
  setUnreadable,
}

enum SpoolVerdict {
  /// |odchyłka| ≤ tolerancja.
  ok,

  /// |odchyłka| > tolerancja.
  out,

  /// Brak danych — brak werdyktu (to nie jest „OK”).
  none,
}

enum SpoolOverall {
  /// Każda pozycja ma werdykt i jest w tolerancji.
  ok,

  /// Co najmniej jedna pozycja poza tolerancją.
  out,

  /// Co najmniej jedna pozycja bez werdyktu (żadna poza).
  incomplete,

  /// Brak pozycji pomiaru.
  empty,
}

/// Własna tolerancja (mm) jest użyteczna: dodatnia i nie większa niż
/// [kSpoolMaxToleranceMm].
bool spoolToleranceValid(double v) =>
    v.isFinite && v > 0 && v <= kSpoolMaxToleranceMm + kSpoolCompareEpsMm;

/// Część tolerancji niesymetrycznej (+ albo −), mm: 0…[kSpoolMaxToleranceMm]
/// (zero dozwolone — „+0 / −3”).
bool spoolTolerancePartValid(double v) =>
    v.isFinite && v >= 0 && v <= kSpoolMaxToleranceMm + kSpoolCompareEpsMm;

/// DN z pola: 1…[kSpoolMaxDn].
bool spoolDnValid(int dn) => dn > 0 && dn <= kSpoolMaxDn;

// ═══════════════════════════════════════════════════════════════════════════
// POZYCJA POMIARU
// ═══════════════════════════════════════════════════════════════════════════

const Object _keep = Object();

class SpoolItem {
  final String id;
  final SpoolItemKind kind;

  /// Oznaczenie z izometrii („F1–F2”, „odg. B”, „uchwyt U3”).
  final String label;

  /// Wymiar z rysunku, mm — tylko pozycje liniowe.
  final double? drawingMm;

  /// Pozycje liniowe: wymiar zmierzony, mm. Pozostałe: zmierzona odchyłka
  /// (przesunięcie po obwodzie, różnica szczelin, przesunięcie boczne,
  /// strzałka łuku), mm, ≥ 0.
  final double? measuredMm;

  /// Średnica / długość odniesienia, mm: nachylenie czoła — średnica, na
  /// której zmierzono odchyłkę; skręt otworów — średnica podziałowa (PCD);
  /// prostoliniowość — długość odcinka (informacyjnie).
  final double? baseMm;

  /// Skręt otworów zmierzony jako kąt (stopnie) zamiast przesunięcia.
  final bool rotationByAngle;
  final double? angleDeg;

  /// DN tej pozycji, gdy inny niż spoola (tolerancja liniowa ES-3).
  final int? dn;

  /// Tolerancja ± wpisana przy pozycji, mm (W DÓŁ do siatki).
  final double? toleranceMm;

  /// Tolerancja niesymetryczna z projektu (tylko zestaw „z projektu”,
  /// pozycje liniowe): dopuszczalne wydłużenie (+) i skrócenie (−), mm,
  /// każda ≥ 0 (np. +0 / −3). Obie wpisane — zastępują ±; jedna — brak
  /// werdyktu.
  final double? tolPlusMm;
  final double? tolMinusMm;

  /// Zapis tolerancji był nieczytelny — pozycja bez werdyktu, dopóki
  /// monter nie wpisze tolerancji ponownie (nie podstawiamy normy).
  final bool toleranceDamaged;

  final String note;

  const SpoolItem({
    required this.id,
    required this.kind,
    this.label = '',
    this.drawingMm,
    this.measuredMm,
    this.baseMm,
    this.rotationByAngle = false,
    this.angleDeg,
    this.dn,
    this.toleranceMm,
    this.tolPlusMm,
    this.tolMinusMm,
    this.toleranceDamaged = false,
    this.note = '',
  });

  /// Wpisano choć jedną część tolerancji niesymetrycznej.
  bool get hasAsymmetric => tolPlusMm != null || tolMinusMm != null;

  /// Zmierzona odchyłka przy pozycjach mierzonych wprost (nie liniowych),
  /// mm, w górę do siatki. Skręt jako kąt → przesunięcie po obwodzie na
  /// średnicy podziałowej.
  double? get measuredDeviationMm {
    if (kind.isLinear) return null;
    if (kind == SpoolItemKind.boltRotation && rotationByAngle) {
      final a = angleDeg;
      final pcd = baseMm;
      if (a == null || pcd == null || pcd <= 0) return null;
      return boltArcFromAngle(a, pcd);
    }
    final m = measuredMm;
    return m == null ? null : spoolCeilMm(m.abs());
  }

  /// Odchyłka ze znakiem (zmierzony − rysunek) dla pozycji liniowych, mm.
  double? get signedDeviationMm {
    final d = drawingMm;
    final m = measuredMm;
    if (!kind.isLinear || d == null || m == null) return null;
    final dev = spoolDeviationMm(m, d);
    return m >= d ? dev : -dev;
  }

  /// Odchyłka do oceny (|…|, mm, w górę do siatki) albo `null`.
  double? get deviationMm {
    if (kind.isLinear) return signedDeviationMm?.abs();
    return measuredDeviationMm;
  }

  /// Nic nie wpisano.
  bool get isBlank =>
      label.trim().isEmpty &&
      drawingMm == null &&
      measuredMm == null &&
      baseMm == null &&
      angleDeg == null &&
      dn == null &&
      toleranceMm == null &&
      tolPlusMm == null &&
      tolMinusMm == null &&
      note.trim().isEmpty;

  SpoolItem copyWith({
    String? id,
    SpoolItemKind? kind,
    String? label,
    Object? drawingMm = _keep,
    Object? measuredMm = _keep,
    Object? baseMm = _keep,
    bool? rotationByAngle,
    Object? angleDeg = _keep,
    Object? dn = _keep,
    Object? toleranceMm = _keep,
    Object? tolPlusMm = _keep,
    Object? tolMinusMm = _keep,
    bool? toleranceDamaged,
    String? note,
  }) {
    final newTolerance = identical(toleranceMm, _keep)
        ? this.toleranceMm
        : _asDouble(toleranceMm);
    final touched = !identical(toleranceMm, _keep) ||
        !identical(tolPlusMm, _keep) ||
        !identical(tolMinusMm, _keep);
    return SpoolItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      drawingMm:
          identical(drawingMm, _keep) ? this.drawingMm : _asDouble(drawingMm),
      measuredMm: identical(measuredMm, _keep)
          ? this.measuredMm
          : _asDouble(measuredMm),
      baseMm: identical(baseMm, _keep) ? this.baseMm : _asDouble(baseMm),
      rotationByAngle: rotationByAngle ?? this.rotationByAngle,
      angleDeg:
          identical(angleDeg, _keep) ? this.angleDeg : _asDouble(angleDeg),
      dn: identical(dn, _keep) ? this.dn : dn as int?,
      toleranceMm: newTolerance,
      tolPlusMm:
          identical(tolPlusMm, _keep) ? this.tolPlusMm : _asDouble(tolPlusMm),
      tolMinusMm: identical(tolMinusMm, _keep)
          ? this.tolMinusMm
          : _asDouble(tolMinusMm),
      // Nowo wpisana tolerancja zdejmuje znacznik uszkodzenia.
      toleranceDamaged:
          toleranceDamaged ?? (touched ? false : this.toleranceDamaged),
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'drawingMm': drawingMm,
        'measuredMm': measuredMm,
        'baseMm': baseMm,
        'byAngle': rotationByAngle,
        'angleDeg': angleDeg,
        'dn': dn,
        'tolMm': toleranceMm,
        'tolPlusMm': tolPlusMm,
        'tolMinusMm': tolMinusMm,
        if (toleranceDamaged) 'tolDamaged': true,
        'note': note,
      };

  /// Odczyt z JSON: `(pozycja, uszkodzona)`. Nieznany rodzaj → `null`
  /// (pozycja pominięta). Pole liczbowe obecne, ale nieczytelne → `null`
  /// i znacznik uszkodzenia; nieczytelna tolerancja dodatkowo
  /// [toleranceDamaged] — bez cichego podstawienia normy.
  static (SpoolItem?, bool) fromJson(Object? raw, {required int index}) {
    if (raw is! Map) return (null, true);
    final kind = SpoolItemKind.byName(raw['kind']);
    if (kind == null) return (null, true);
    var damaged = false;
    double? readNum(String key, {bool allowZero = true}) {
      final (v, bad) = _readNum(raw, key, allowZero: allowZero);
      if (bad) damaged = true;
      return v;
    }

    final drawing = readNum('drawingMm', allowZero: false);
    final measured = readNum('measuredMm');
    final base = readNum('baseMm', allowZero: false);
    final angle = readNum('angleDeg');
    final (tol, tolBad) = _readNum(raw, 'tolMm', allowZero: false);
    final (plus, plusBad) = _readNum(raw, 'tolPlusMm', allowZero: true);
    final (minus, minusBad) = _readNum(raw, 'tolMinusMm', allowZero: true);
    final tolInvalid = (tol != null && !spoolToleranceValid(tol)) ||
        (plus != null && !spoolTolerancePartValid(plus)) ||
        (minus != null && !spoolTolerancePartValid(minus));
    final anyBad = tolBad || plusBad || minusBad || tolInvalid;
    if (anyBad) damaged = true;
    final tolDamaged = anyBad || raw['tolDamaged'] == true;
    final rawDn = raw['dn'];
    int? dn;
    if (rawDn != null) {
      if (rawDn is int && spoolDnValid(rawDn)) {
        dn = rawDn;
      } else {
        damaged = true;
      }
    }
    final id = raw['id'];
    return (
      SpoolItem(
        id: id is String && id.isNotEmpty ? id : 'item-$index',
        kind: kind,
        label: _str(raw['label']),
        drawingMm: drawing,
        measuredMm: measured,
        baseMm: base,
        rotationByAngle: raw['byAngle'] == true,
        angleDeg: angle,
        dn: dn,
        toleranceMm: tolDamaged ? null : tol,
        tolPlusMm: tolDamaged ? null : plus,
        tolMinusMm: tolDamaged ? null : minus,
        toleranceDamaged: tolDamaged,
        note: _str(raw['note']),
      ),
      damaged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OCENA POZYCJI
// ═══════════════════════════════════════════════════════════════════════════

/// Tolerancja pozycji: wartość (± albo + / −), podstawa albo powód braku.
class SpoolTolerance {
  /// Tolerancja symetryczna ±, mm (`null` przy niesymetrycznej).
  final double? mm;

  /// Tolerancja niesymetryczna: dopuszczalne + i −, mm.
  final double? plusMm;
  final double? minusMm;
  final SpoolToleranceBasis? basis;

  /// Pasmo ES-3 (tolerancja liniowa).
  final Es3LinearBand? band;

  /// DN użyte do pasma ES-3.
  final int? dn;
  final SpoolGap? gap;

  const SpoolTolerance._({this.mm, this.basis, this.band, this.dn})
      : plusMm = null,
        minusMm = null,
        gap = null;

  const SpoolTolerance._asym(double this.plusMm, double this.minusMm)
      : mm = null,
        basis = SpoolToleranceBasis.project,
        band = null,
        dn = null,
        gap = null;

  const SpoolTolerance.missing(SpoolGap this.gap)
      : mm = null,
        plusMm = null,
        minusMm = null,
        basis = null,
        band = null,
        dn = null;

  bool get isAsymmetric => plusMm != null && minusMm != null;

  bool get known => mm != null || isAsymmetric;
}

class SpoolItemResult {
  final SpoolItem item;
  final double? deviationMm;
  final double? signedDeviationMm;
  final SpoolTolerance tolerance;

  /// Braki danych (pusta lista — jest werdykt).
  final List<SpoolGap> gaps;

  const SpoolItemResult({
    required this.item,
    required this.deviationMm,
    required this.signedDeviationMm,
    required this.tolerance,
    required this.gaps,
  });

  SpoolVerdict get verdict {
    if (gaps.isNotEmpty) return SpoolVerdict.none;
    final tol = tolerance;
    if (tol.isAsymmetric) {
      // Wg znaku odchyłki: dłuższy niż rysunek — „+”, krótszy — „−”.
      final s = signedDeviationMm;
      if (s == null) return SpoolVerdict.none;
      final ok =
          s >= 0 ? spoolWithin(s, tol.plusMm!) : spoolWithin(-s, tol.minusMm!);
      return ok ? SpoolVerdict.ok : SpoolVerdict.out;
    }
    final d = deviationMm;
    final t = tol.mm;
    if (d == null || t == null) return SpoolVerdict.none;
    return spoolWithin(d, t) ? SpoolVerdict.ok : SpoolVerdict.out;
  }
}

class SpoolCheckResult {
  final List<SpoolItemResult> items;
  final SpoolToleranceSet? set;

  const SpoolCheckResult(this.items, this.set);

  int count(SpoolVerdict v) => items.where((r) => r.verdict == v).length;

  SpoolOverall get overall {
    if (items.isEmpty) return SpoolOverall.empty;
    if (items.any((r) => r.verdict == SpoolVerdict.out)) {
      return SpoolOverall.out;
    }
    if (items.any((r) => r.verdict == SpoolVerdict.none)) {
      return SpoolOverall.incomplete;
    }
    return SpoolOverall.ok;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOKÓŁ SPOOLA
// ═══════════════════════════════════════════════════════════════════════════

class SpoolCheck {
  final String id;

  /// Numer spoola (oznaczenie z izometrii, np. „100-P-1203-S02”).
  final String spoolNo;
  final String isoNo;
  final String drawingNo;
  final String revision;

  /// Data pomiaru `RRRR-MM-DD`.
  final String date;

  /// Kto mierzył.
  final String inspector;

  /// DN spoola (tolerancja liniowa ES-3), `null` — nie podano.
  final int? dn;

  /// Jednostka wyświetlania i wpisywania — NIE wpływa na werdykt.
  final SpoolUnit unit;

  /// `null` — zapis nieczytelny (pozycje bez werdyktu, dopóki monter nie
  /// wybierze zestawu ponownie).
  final SpoolToleranceSet? toleranceSet;

  /// Klasa (grade) EN 13480-4 zał. B uzgodniona przed prefabrykacją.
  final String enGrade;
  final List<SpoolItem> items;
  final String notes;
  final int createdAt;
  final int updatedAt;

  /// Ile uszkodzeń pominięto / oznaczono przy odczycie (baner).
  final int damagedOnLoad;

  const SpoolCheck({
    required this.id,
    this.spoolNo = '',
    this.isoNo = '',
    this.drawingNo = '',
    this.revision = '',
    required this.date,
    this.inspector = '',
    this.dn,
    this.unit = SpoolUnit.mm,
    this.toleranceSet = SpoolToleranceSet.pfiEs3,
    this.enGrade = '',
    this.items = const [],
    this.notes = '',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.damagedOnLoad = 0,
  });

  /// Nowy, pusty protokół na dziś (zestaw PFI ES-3, mm).
  factory SpoolCheck.blank({required String id, required DateTime now}) =>
      SpoolCheck(
        id: id,
        date: spoolDate(now),
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  /// Nic nie wpisano — takiego protokołu nie zapisujemy.
  bool get isBlank =>
      spoolNo.trim().isEmpty &&
      isoNo.trim().isEmpty &&
      drawingNo.trim().isEmpty &&
      revision.trim().isEmpty &&
      inspector.trim().isEmpty &&
      dn == null &&
      enGrade.trim().isEmpty &&
      items.every((i) => i.isBlank) &&
      notes.trim().isEmpty;

  /// Tolerancja pozycji wg zestawu protokołu.
  SpoolTolerance toleranceFor(SpoolItem item) {
    final set = toleranceSet;
    if (set == null) {
      return const SpoolTolerance.missing(SpoolGap.setUnreadable);
    }
    if (item.toleranceDamaged) {
      return const SpoolTolerance.missing(SpoolGap.toleranceDamaged);
    }
    if (set == SpoolToleranceSet.project &&
        item.kind.isLinear &&
        item.hasAsymmetric) {
      final plus = item.tolPlusMm;
      final minus = item.tolMinusMm;
      if (plus == null || minus == null) {
        return const SpoolTolerance.missing(SpoolGap.toleranceAsymIncomplete);
      }
      if (!spoolTolerancePartValid(plus) ||
          !spoolTolerancePartValid(minus) ||
          plus + minus <= 0) {
        return const SpoolTolerance.missing(SpoolGap.toleranceInvalid);
      }
      return SpoolTolerance._asym(spoolFloorMm(plus), spoolFloorMm(minus));
    }
    final own = item.toleranceMm;
    if (own != null) {
      if (!spoolToleranceValid(own)) {
        return const SpoolTolerance.missing(SpoolGap.toleranceInvalid);
      }
      return SpoolTolerance._(
        mm: spoolFloorMm(own),
        basis: switch (set) {
          SpoolToleranceSet.pfiEs3 => SpoolToleranceBasis.drawing,
          SpoolToleranceSet.en13480 => SpoolToleranceBasis.en13480,
          SpoolToleranceSet.project => SpoolToleranceBasis.project,
        },
      );
    }
    if (set != SpoolToleranceSet.pfiEs3) {
      return const SpoolTolerance.missing(SpoolGap.noTolerance);
    }
    switch (item.kind) {
      case SpoolItemKind.faceToFace:
      case SpoolItemKind.centerToFace:
      case SpoolItemKind.centerToCenter:
      case SpoolItemKind.branchPosition:
        final d = item.dn ?? dn;
        if (d == null) return const SpoolTolerance.missing(SpoolGap.noDn);
        final band = es3LinearBandFor(d);
        if (band == null) {
          return const SpoolTolerance.missing(SpoolGap.dnBeyondEs3);
        }
        return SpoolTolerance._(
            mm: band.mm,
            basis: SpoolToleranceBasis.es3Linear,
            band: band,
            dn: d);
      case SpoolItemKind.boltRotation:
        return SpoolTolerance._(
            mm: kEs3RotationMm, basis: SpoolToleranceBasis.es3Rotation);
      case SpoolItemKind.faceTilt:
        final base = item.baseMm;
        if (base == null || base <= 0) {
          return const SpoolTolerance.missing(SpoolGap.noDiameter);
        }
        return SpoolTolerance._(
            mm: es3FaceAlignmentLimitMm(base),
            basis: SpoolToleranceBasis.es3Alignment);
      case SpoolItemKind.branchOffset:
      case SpoolItemKind.straightness:
        return const SpoolTolerance.missing(SpoolGap.notInEs3);
    }
  }

  SpoolItemResult evaluateItem(SpoolItem item) {
    final gaps = <SpoolGap>[];
    if (item.kind.isLinear) {
      if (item.drawingMm == null) gaps.add(SpoolGap.noDrawing);
      if (item.measuredMm == null) gaps.add(SpoolGap.noMeasured);
    } else if (item.kind == SpoolItemKind.boltRotation &&
        item.rotationByAngle) {
      if (item.angleDeg == null) gaps.add(SpoolGap.noMeasured);
      if (item.baseMm == null) gaps.add(SpoolGap.noPcd);
    } else if (item.measuredMm == null) {
      gaps.add(SpoolGap.noMeasured);
    }
    final tol = toleranceFor(item);
    if (tol.gap != null) gaps.add(tol.gap!);
    return SpoolItemResult(
      item: item,
      deviationMm: item.deviationMm,
      signedDeviationMm: item.signedDeviationMm,
      tolerance: tol,
      gaps: gaps,
    );
  }

  SpoolCheckResult evaluate() =>
      SpoolCheckResult([for (final i in items) evaluateItem(i)], toleranceSet);

  /// Następny spool z tej samej serii: dane nagłówka, zestaw tolerancji,
  /// pozycje z wymiarami z rysunku i własnymi tolerancjami — BEZ pomiarów
  /// i uwag; numer spoola wg [spoolNextNo]. Nieczytelny zestaw zostaje
  /// nieczytelny, a uszkodzona tolerancja — uszkodzona (bez cichego
  /// podstawienia normy w kopii).
  SpoolCheck duplicateFor({
    required String newId,
    required DateTime now,
    required String Function(int index) itemId,
  }) =>
      SpoolCheck(
        id: newId,
        spoolNo: spoolNextNo(spoolNo),
        isoNo: isoNo,
        drawingNo: drawingNo,
        revision: revision,
        date: spoolDate(now),
        inspector: inspector,
        dn: dn,
        unit: unit,
        toleranceSet: toleranceSet,
        enGrade: enGrade,
        items: [
          for (final (i, it) in items.indexed)
            SpoolItem(
              id: itemId(i),
              kind: it.kind,
              label: it.label,
              drawingMm: it.drawingMm,
              baseMm: it.baseMm,
              rotationByAngle: it.rotationByAngle,
              dn: it.dn,
              toleranceMm: it.toleranceMm,
              tolPlusMm: it.tolPlusMm,
              tolMinusMm: it.tolMinusMm,
              toleranceDamaged: it.toleranceDamaged,
            ),
        ],
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  SpoolCheck copyWith({
    String? spoolNo,
    String? isoNo,
    String? drawingNo,
    String? revision,
    String? date,
    String? inspector,
    Object? dn = _keep,
    SpoolUnit? unit,
    Object? toleranceSet = _keep,
    String? enGrade,
    List<SpoolItem>? items,
    String? notes,
    int? updatedAt,
    int? damagedOnLoad,
  }) =>
      SpoolCheck(
        id: id,
        spoolNo: spoolNo ?? this.spoolNo,
        isoNo: isoNo ?? this.isoNo,
        drawingNo: drawingNo ?? this.drawingNo,
        revision: revision ?? this.revision,
        date: date ?? this.date,
        inspector: inspector ?? this.inspector,
        dn: identical(dn, _keep) ? this.dn : dn as int?,
        unit: unit ?? this.unit,
        toleranceSet: identical(toleranceSet, _keep)
            ? this.toleranceSet
            : toleranceSet as SpoolToleranceSet?,
        enGrade: enGrade ?? this.enGrade,
        items: items ?? this.items,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        damagedOnLoad: damagedOnLoad ?? this.damagedOnLoad,
      );

  /// Pozycja zmieniona po identyfikatorze.
  SpoolCheck withItem(SpoolItem item) => copyWith(items: [
        for (final i in items) i.id == item.id ? item : i,
      ]);

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'spoolNo': spoolNo,
        'isoNo': isoNo,
        'drawingNo': drawingNo,
        'revision': revision,
        'date': date,
        'inspector': inspector,
        'dn': dn,
        'unit': unit.name,
        'set': toleranceSet?.name,
        'enGrade': enGrade,
        'items': [for (final i in items) i.toJson()],
        'notes': notes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Odczyt z JSON. `null` dla wpisu bez identyfikatora albo daty.
  /// Nieczytelne pozycje są pomijane, nieczytelne pola — puste (brak
  /// werdyktu); wszystko liczone w [damagedOnLoad].
  static SpoolCheck? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw.containsKey('v') && raw['v'] != 1) return null;
    final id = _str(raw['id']);
    final date = _str(raw['date']);
    if (id.isEmpty || date.isEmpty) return null;
    var damaged = 0;
    final rawItems = raw['items'];
    final items = <SpoolItem>[];
    if (rawItems != null && rawItems is! List) damaged++;
    if (rawItems is List) {
      for (final (i, e) in rawItems.indexed) {
        final (item, bad) = SpoolItem.fromJson(e, index: i);
        if (bad) damaged++;
        if (item != null) items.add(item);
      }
    }
    final set = SpoolToleranceSet.byName(raw['set']);
    if (set == null) damaged++;
    final rawDn = raw['dn'];
    int? dn;
    if (rawDn != null) {
      if (rawDn is int && spoolDnValid(rawDn)) {
        dn = rawDn;
      } else {
        damaged++;
      }
    }
    return SpoolCheck(
      id: id,
      spoolNo: _str(raw['spoolNo']),
      isoNo: _str(raw['isoNo']),
      drawingNo: _str(raw['drawingNo']),
      revision: _str(raw['revision']),
      date: date,
      inspector: _str(raw['inspector']),
      dn: dn,
      unit: raw['unit'] == SpoolUnit.inch.name ? SpoolUnit.inch : SpoolUnit.mm,
      toleranceSet: set,
      enGrade: _str(raw['enGrade']),
      items: items,
      notes: _str(raw['notes']),
      createdAt: _int(raw['createdAt']),
      updatedAt: _int(raw['updatedAt']),
      damagedOnLoad: damaged,
    );
  }
}

/// Wynik odczytu listy protokołów.
class SpoolChecksParse {
  final List<SpoolCheck> checks;
  final int droppedChecks;
  final int damagedEntries;
  const SpoolChecksParse(this.checks, this.droppedChecks, this.damagedEntries);

  bool get damaged => droppedChecks > 0 || damagedEntries > 0;
}

/// Lista protokołów z JSON. Rzuca [FormatException], gdy to nie lista —
/// magazyn robi wtedy kopię surowego zapisu. Powtórzony identyfikator —
/// drugi wpis pominięty (liczony).
SpoolChecksParse spoolChecksParse(Object? raw) {
  if (raw is! List) throw const FormatException('not a list');
  final out = <SpoolCheck>[];
  final ids = <String>{};
  var dropped = 0;
  var damaged = 0;
  for (final e in raw) {
    final c = SpoolCheck.fromJson(e);
    if (c == null || !ids.add(c.id)) {
      dropped++;
    } else {
      out.add(c);
      damaged += c.damagedOnLoad;
    }
  }
  return SpoolChecksParse(out, dropped, damaged);
}

List<Map<String, Object?>> spoolChecksToJson(List<SpoolCheck> list) =>
    [for (final c in list) c.toJson()];

// ═══════════════════════════════════════════════════════════════════════════
// KALKULATORY POMOCNICZE
// ═══════════════════════════════════════════════════════════════════════════

/// Nachylenie czoła z dwóch szczelin w przeciwległych punktach.
class FaceTiltReading {
  /// |g1 − g2|, mm (w górę do siatki).
  final double deviationMm;

  /// Średnica (rozstaw punktów), na której zmierzono, mm.
  final double diameterMm;

  const FaceTiltReading(this.deviationMm, this.diameterMm);

  /// Kąt nachylenia: atan(odchyłka / średnica), stopnie.
  double get angleDeg => spoolTiltAngleDeg(deviationMm, diameterMm);

  /// mm na metr.
  double get mmPerM => deviationMm / diameterMm * 1000;
}

/// `null`, gdy brakuje szczeliny albo średnicy (≤ 0).
FaceTiltReading? faceTiltFromGaps(
    double? gap1, double? gap2, double? diameter) {
  if (gap1 == null || gap2 == null || diameter == null) return null;
  if (gap1 < 0 || gap2 < 0 || diameter <= 0) return null;
  return FaceTiltReading(spoolDeviationMm(gap1, gap2), diameter);
}

/// atan(odchyłka / średnica) w stopniach.
double spoolTiltAngleDeg(double deviationMm, double diameterMm) =>
    math.atan(deviationMm / diameterMm) * 180 / math.pi;

/// Odchyłka zmierzona na średnicy [fromMm] przeliczona na średnicę [toMm]
/// (ten sam kąt), w górę do 0,001 mm.
double spoolScaleDeviation(double deviationMm, double fromMm, double toMm) =>
    spoolCeilMicron(deviationMm * toMm / fromMm);

/// Skręt otworów: kąt → przesunięcie po obwodzie średnicy podziałowej,
/// mm, w górę do 0,001 mm (π · PCD · kąt / 360).
double boltArcFromAngle(double angleDeg, double pcdMm) =>
    spoolCeilMicron(math.pi * pcdMm * angleDeg.abs() / 360);

/// Skręt otworów: przesunięcie po obwodzie → kąt, stopnie.
double boltAngleFromArc(double arcMm, double pcdMm) =>
    arcMm.abs() * 360 / (math.pi * pcdMm);

// ═══════════════════════════════════════════════════════════════════════════
// POMOCNICZE
// ═══════════════════════════════════════════════════════════════════════════

/// Numer następnego spoola z serii:
/// * zwiększa grupę cyfr po OSTATNIM „S” / „SP” (wielkość liter bez
///   znaczenia, z opcjonalnym „-”, „_” albo spacją), z zachowaniem zer
///   wiodących: „100-P-1203-S02-R1” → „100-P-1203-S03-R1” (rewizja bez
///   zmian), „SP-9” → „SP-10”, „s09” → „s10”;
/// * bez takiej grupy — ostatnią grupę cyfr („L-101-F1” → „L-101-F2”);
/// * bez cyfr albo pusty — „” (monter uzupełnia numer; nie powstaje po
///   cichu drugi protokół z tym samym numerem).
String spoolNextNo(String no) {
  final s = no.trim();
  final spool =
      RegExp(r'(?<![A-Za-z])((?:SP|S)[-_ ]?)(\d+)', caseSensitive: false)
          .allMatches(s)
          .lastOrNull;
  if (spool != null) {
    final start = spool.start + spool.group(1)!.length;
    return _bump(s, start, spool.end);
  }
  final last = RegExp(r'(\d+)(?!.*\d)').firstMatch(s);
  if (last == null) return '';
  return _bump(s, last.start, last.end);
}

String _bump(String s, int start, int end) {
  final digits = s.substring(start, end);
  final next = (BigInt.parse(digits) + BigInt.one).toString();
  return s.replaceRange(start, end, next.padLeft(digits.length, '0'));
}

/// Numer do porównań duplikatów: bez spacji na końcach, wielkość liter
/// bez znaczenia.
String spoolNoKey(String no) => no.trim().toLowerCase();

/// `RRRR-MM-DD`.
String spoolDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Liczba z copyWith (`Object?` — przyjmuje też int, np. `measuredMm: 1251`).
double? _asDouble(Object? v) => v == null ? null : (v as num).toDouble();

String _two(int v) => v.toString().padLeft(2, '0');
String _str(Object? v) => v is String ? v : '';
int _int(Object? v) => v is num && v.isFinite ? v.toInt() : 0;

/// Liczba z zapisu: brak / `null` → `(null, false)`; nieczytelna (nie
/// liczba, nieskończona, ujemna, zero gdy niedozwolone) → `(null, true)`.
(double?, bool) _readNum(Map raw, String key, {required bool allowZero}) {
  if (!raw.containsKey(key) || raw[key] == null) return (null, false);
  final v = raw[key];
  if (v is! num) return (null, true);
  final d = v.toDouble();
  if (!d.isFinite || d < 0 || (!allowZero && d == 0)) return (null, true);
  return (d, false);
}
