/// Teksty modułu odbioru kołnierzy wspólne dla ekranu i eksportu (tekst,
/// PDF). Czyste funkcje z flagą `en` — eksport nie ma BuildContext.
library;

import 'flange_check.dart';

String _t(bool en, String pl, String e) => en ? e : pl;

String criterionTitle(FlangeCriterion c, {required bool en}) => switch (c) {
      FlangeCriterion.centerline =>
        _t(en, 'Przesunięcie osi (high/low)', 'Centerline high/low'),
      FlangeCriterion.parallelism => _t(en,
          'Równoległość szczeliny (max − min)', 'Gap parallelism (max − min)'),
      FlangeCriterion.rotation => _t(
          en, 'Przesunięcie obrotowe otworów', 'Rotational two-hole alignment'),
      FlangeCriterion.spacing => _t(en, 'Nadmierna szczelina (vs uszczelka)',
          'Excessive spacing (vs gasket)'),
      FlangeCriterion.force =>
        _t(en, 'Siła potrzebna do zestawienia', 'Force needed to align'),
    };

String criterionHint(FlangeCriterion c, {required bool en}) => switch (c) {
      FlangeCriterion.centerline => _t(
          en,
          'Liniał na OD jednego kołnierza, przez drugi — w 4 punktach co 90°. '
              'Wpisz największe przesunięcie.',
          'Straight edge on the OD of one flange, across the other — at 4 '
              'points 90° apart. Enter the largest offset.'),
      FlangeCriterion.parallelism => _t(
          en,
          'Szczelinomierz na zewnętrznej średnicy powierzchni uszczelniającej. '
              'Różnica najmniejszej i największej szczeliny.',
          'Feeler gauge at the OD of the gasket seating surface. Difference '
              'between the smallest and the largest gap.'),
      FlangeCriterion.rotation => _t(
          en,
          'Śruba ma przejść przez oba otwory pod kątem prostym. Wpisz '
              'przesunięcie otworów.',
          'A bolt must pass through both holes at a right angle. Enter the '
              'bolt-hole offset.'),
      FlangeCriterion.spacing => _t(
          en,
          'Kołnierze w spoczynku, bez ściągania. Największa szczelina ≤ '
              '${fmtNum(kPcc1GapFactor, en: en)} × grubość uszczelki.',
          'Flanges at rest, not pulled. Largest gap ≤ '
              '${fmtNum(kPcc1GapFactor, en: en)} × gasket thickness.'),
      FlangeCriterion.force => _t(
          en,
          'Bez urządzeń: < $kPcc1ForceTotalPct % docelowego obciążenia śrub, '
              'żadna śruba > $kPcc1ForceSingleBoltPct %. Potrzeba więcej — '
              'decyzja inżyniera.',
          'Without devices: < $kPcc1ForceTotalPct % of the total target bolt '
              'load, no bolt > $kPcc1ForceSingleBoltPct %. Needs more — refer '
              'to the engineer.'),
    };

String forceLabel(AlignmentForce f, {required bool en}) => switch (f) {
      AlignmentForce.light =>
        _t(en, 'Ręcznie / zwykłymi narzędziami', 'By hand / common hand tools'),
      AlignmentForce.heavy =>
        _t(en, 'Duża siła (ściąganie)', 'Heavy force (pulling)'),
    };

String checklistTitle(FlangeChecklistItem i, {required bool en}) => switch (i) {
      FlangeChecklistItem.faces => _t(
          en,
          'Powierzchnie uszczelniające czyste i nieuszkodzone',
          'Gasket seating surfaces clean and undamaged'),
      FlangeChecklistItem.gasket =>
        _t(en, 'Właściwa uszczelka, nowa', 'Correct gasket, new'),
      FlangeChecklistItem.bolting => _t(
          en,
          'Śruby i nakrętki: gatunek, średnica, długość',
          'Studs and nuts: grade, diameter, length'),
      FlangeChecklistItem.lubrication => _t(
          en,
          'Smar na gwintach i powierzchniach nośnych nakrętek',
          'Lubricant on threads and nut bearing faces'),
      FlangeChecklistItem.sequence =>
        _t(en, 'Kolejność dokręcania i rundy', 'Tightening pattern and rounds'),
    };

String checklistHint(FlangeChecklistItem i, {required bool en}) => switch (i) {
      FlangeChecklistItem.faces => _t(
          en,
          'Bez rdzy, farby i resztek starej uszczelki. Rysy promieniowe '
              'i wżery w granicach PCC-1 zał. D.',
          'No rust, paint or old gasket residue. Radial scratches and pits '
              'within PCC-1 Appendix D.'),
      FlangeChecklistItem.gasket => _t(
          en,
          'Typ, rozmiar i klasa jak w specyfikacji; nigdy używana ponownie; '
              'wycentrowana; bez taśmy i smaru, chyba że dopuszcza producent.',
          'Type, size and rating as specified; never reused; centred; no '
              'tape or grease unless the manufacturer allows it.'),
      FlangeChecklistItem.bolting => _t(
          en,
          'Np. A193 B7 / A194 2H. Gwint na całej wysokości nakrętki — '
              'zwykle min. 1 pełny zwój wystaje (PCC-1 nie podaje liczby '
              'zwojów; specyfikacje zakładów 1–3).',
          'E.g. A193 B7 / A194 2H. Thread engaged over the full nut height — '
              'usually at least 1 full thread protrudes (PCC-1 gives no '
              'thread count; plant specs 1–3).'),
      FlangeChecklistItem.lubrication => _t(
          en,
          'Ten sam smar, który przyjęto do momentu (współczynnik K). '
              'Nie na uszczelce.',
          'The same lubricant the torque was based on (nut factor K). '
              'Not on the gasket.'),
      FlangeChecklistItem.sequence => _t(
          en,
          'Wzór krzyżowy. PCC-1 Legacy: dociągnięcie ≤ 20 %, R1 20–30 %, '
              'R2 50–70 %, R3 100 %, R4 okrężnie do braku obrotu nakrętek, '
              'R5 po ≥ 4 h. Szczelina równa po każdej rundzie.',
          'Star pattern. PCC-1 Legacy: snug ≤ 20 %, R1 20–30 %, R2 50–70 %, '
              'R3 100 %, R4 circular until nuts stop turning, R5 after ≥ 4 h. '
              'Even gap after every round.'),
    };

String checkVerdictLabel(CheckVerdict v, {required bool en}) => switch (v) {
      CheckVerdict.ok => 'OK',
      CheckVerdict.fail => _t(en, 'Poza tolerancją', 'Out of tolerance'),
      CheckVerdict.missing => _t(en, 'Brak pomiaru', 'Not measured'),
    };

String protocolVerdictLabel(ProtocolVerdict v, {required bool en}) =>
    switch (v) {
      ProtocolVerdict.accepted =>
        _t(en, 'Zgodny — można skręcać', 'Accepted — ready to bolt up'),
      ProtocolVerdict.rejected =>
        _t(en, 'Niezgodny — popraw osiowanie', 'Rejected — correct alignment'),
      ProtocolVerdict.incomplete => _t(en, 'Niekompletny', 'Incomplete'),
    };

String problemLabel(FlangeDataProblem p, {required bool en}) => switch (p) {
      FlangeDataProblem.boltCount => _t(
          en,
          'Liczba śrub: $kMinBolts–$kMaxBolts, wielokrotność 4.',
          'Bolt count: $kMinBolts–$kMaxBolts, a multiple of 4.'),
      FlangeDataProblem.gasketThickness => _t(
          en,
          'Grubość uszczelki musi być większa od zera.',
          'Gasket thickness must be greater than zero.'),
      FlangeDataProblem.tolerances => _t(
          en,
          'Tolerancje nieważne: wartość spoza zakresu (granica 0–'
              '${fmtNum(kMaxLimitMm, en: en)} mm, współczynnik 0–'
              '${fmtNum(kMaxGapFactor, en: en)}) albo uszkodzona w zapisie. '
              'Popraw je albo przywróć PCC-1.',
          'Tolerances invalid: out of range (limit 0–'
              '${fmtNum(kMaxLimitMm, en: en)} mm, factor 0–'
              '${fmtNum(kMaxGapFactor, en: en)}) or damaged in storage. '
              'Correct them or restore PCC-1.'),
    };

/// „UWAGA: tolerancje luźniejsze niż PCC-1 (przesunięcie osi, …).” albo
/// `null`, gdy żadna nie jest luźniejsza.
String? looserWarning(List<FlangeCriterion> looser, {required bool en}) {
  if (looser.isEmpty) return null;
  final names = looser.map((c) => criterionTitle(c, en: en)).join(', ');
  return _t(en, 'UWAGA: tolerancje luźniejsze niż PCC-1 ($names).',
      'WARNING: tolerances looser than PCC-1 ($names).');
}

/// Co brakuje do zielonego: „brak 2 pomiarów · 3 punkty listy”.
String missingSummary(FlangeEvaluation e, {required bool en}) {
  final m = e.count(CheckVerdict.missing);
  final c = e.checklistTotal - e.checkedCount;
  return [
    if (m > 0) _t(en, 'brak pomiarów: $m', 'missing measurements: $m'),
    if (c > 0)
      _t(en, 'nieodhaczone punkty listy: $c', 'unchecked list items: $c'),
    if (e.problems.isNotEmpty)
      _t(en, 'błędne dane: ${e.problems.length}',
          'invalid data: ${e.problems.length}'),
  ].join(' · ');
}

/// Wartość i granica kryterium jednym wierszem:
/// „0,6 mm ≤ 0,8 mm (1/32")”, „4,2 mm ≤ 2 × 4,5 mm = 9 mm”.
String criterionValueLine(FlangeCheck check, CriterionResult r,
    {required bool en}) {
  final u = check.unit;
  if (r.criterion == FlangeCriterion.force) {
    final f = check.measurements.force;
    return f == null ? '—' : forceLabel(f, en: en);
  }
  final value = r.valueMm == null ? '—' : formatLength(r.valueMm!, u, en: en);
  final tol = check.tolerances;
  String lim(DualLimit l) => l.isValid
      ? formatLimit(l, u, en: en)
      : _t(en, '? (tolerancja nieważna)', '? (invalid tolerance)');
  final limit = switch (r.criterion) {
    FlangeCriterion.centerline => lim(tol.centerline),
    FlangeCriterion.parallelism => lim(tol.parallelism),
    FlangeCriterion.rotation => lim(tol.rotation),
    FlangeCriterion.spacing => _spacingLimit(check, en: en),
    FlangeCriterion.force => '',
  };
  return '$value ≤ $limit';
}

String _spacingLimit(FlangeCheck check, {required bool en}) {
  if (!check.tolerances.gapFactorValid) {
    return _t(en, '? (współczynnik nieważny)', '? (invalid factor)');
  }
  final factor = fmtNum(check.tolerances.gapFactor, en: en);
  final t = check.joint.gasketThicknessMm;
  if (t == null || t <= 0) {
    return _t(en, '$factor × grubość uszczelki (podaj grubość)',
        '$factor × gasket thickness (enter the thickness)');
  }
  final u = check.unit;
  return '$factor × ${formatLength(t, u, en: en)} = '
      '${formatLength(check.tolerances.gapFactor * t, u, en: en)}';
}
