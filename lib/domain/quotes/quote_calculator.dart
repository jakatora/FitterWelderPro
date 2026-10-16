/// Kalkulator wyceny spawalniczej.
///
/// Ścieżka liczenia jednej pozycji (× liczba spoin):
///   geometria rowka → objętość stopiwa (weld_geometry.dart)
///   → masa = objętość · gęstość materiału
///   → podział na proces grani i wypełnienia (schemat „TIG + MMA")
///   → per proces: czas łuku = masa / wydajność stapiania,
///                 spoiwo   = masa / uzysk,
///                 gaz      = przepływ · czas łuku · 1,15,
///                 energia  = moc łuku · czas łuku / sprawność źródła
///   → czas spawania = Σ czas łuku / współczynnik jarzenia · pozycja
///   → przygotowanie (fazowanie, ustawienie, sczepianie) — ręczne albo
///     z reguły kosztorysowej [autoPrepMinutes]
///   → oba czasy · warunki pracy (warsztat / obiekt / trudny dostęp).
///
/// Pieniądze: każdy składnik kosztu jest zaokrąglany do GROSZA w chwili
/// powstania (int), a sumy, narzut, zysk i VAT liczone są na groszach —
/// suma pozycji na ofercie zawsze zgadza się z „Razem" co do grosza.
/// Kolejność: koszty bezpośrednie → + koszty ogólne (% od bezpośrednich)
/// → + zysk (% od bezpośrednich z kosztami ogólnymi) → + pozycje
/// przenoszone 1:1 (bez narzutu) = netto → VAT od netto → brutto.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import '../../data/pipe_schedules.dart';
import '../welder_pipes/purge_estimate.dart';
import 'quote_process.dart';
import 'weld_geometry.dart';
import 'weld_quote.dart';

/// Zużycie jednego procesu w pozycji albo w całej wycenie.
class ProcessUsage {
  final double depositedKg;
  final double fillerKg;
  final double arcHours;

  /// Czas spawania przed mnożnikami pozycji i warunków (łuk / jarzenie).
  final double baseWeldHours;
  final double shieldGasL;
  final double energyKWh;
  final double fluxKg;

  const ProcessUsage({
    this.depositedKg = 0,
    this.fillerKg = 0,
    this.arcHours = 0,
    this.baseWeldHours = 0,
    this.shieldGasL = 0,
    this.energyKWh = 0,
    this.fluxKg = 0,
  });

  static const zero = ProcessUsage();

  ProcessUsage operator +(ProcessUsage o) => ProcessUsage(
        depositedKg: depositedKg + o.depositedKg,
        fillerKg: fillerKg + o.fillerKg,
        arcHours: arcHours + o.arcHours,
        baseWeldHours: baseWeldHours + o.baseWeldHours,
        shieldGasL: shieldGasL + o.shieldGasL,
        energyKWh: energyKWh + o.energyKWh,
        fluxKg: fluxKg + o.fluxKg,
      );

  ProcessUsage times(double k) => ProcessUsage(
        depositedKg: depositedKg * k,
        fillerKg: fillerKg * k,
        arcHours: arcHours * k,
        baseWeldHours: baseWeldHours * k,
        shieldGasL: shieldGasL * k,
        energyKWh: energyKWh * k,
        fluxKg: fluxKg * k,
      );
}

/// Wynik jednej pozycji (już razy liczba spoin).
class JointResult {
  final QuoteJoint joint;
  final List<JointProblem> problems;
  final WeldScheme scheme;
  final Map<QuoteProcess, ProcessUsage> byProcess;

  /// Czas spawania po mnożnikach pozycji i warunków, h.
  final double weldHours;

  /// Czas przygotowania po mnożniku warunków, h.
  final double prepHours;

  /// Gaz formujący, L.
  final double purgeL;

  /// Cale-średnice (NPS × liczba spoin); 0 dla blach.
  final double diameterInches;

  /// `true`, gdy OD nie pasuje do tabeli NPS i DI = OD / 25,4.
  final bool diApprox;

  /// Łączna długość spoin, m.
  final double weldLengthM;

  /// Masa stopiwa na JEDNĄ spoinę, kg.
  final double depositedKgPerWeld;

  const JointResult({
    required this.joint,
    required this.problems,
    required this.scheme,
    required this.byProcess,
    required this.weldHours,
    required this.prepHours,
    required this.purgeL,
    required this.diameterInches,
    required this.diApprox,
    required this.weldLengthM,
    required this.depositedKgPerWeld,
  });

  bool get isValid => problems.isEmpty;

  double get depositedKg =>
      byProcess.values.fold(0.0, (s, u) => s + u.depositedKg);

  double get arcHours => byProcess.values.fold(0.0, (s, u) => s + u.arcHours);
}

/// Pozycja kosztorysu w groszach.
enum QuoteCostKind {
  weldLabour,
  prepLabour,
  filler,
  shieldGas,
  purgeGas,
  flux,
  energy,
  ndt,
  extras,
}

class QuoteResult {
  final List<JointResult> joints;

  /// Sumy zużycia per proces (tylko poprawne pozycje).
  final Map<QuoteProcess, ProcessUsage> byProcess;

  final double weldHours;
  final double prepHours;
  final double purgeL;
  final double diameterInches;
  final bool diApprox;
  final double weldLengthM;

  /// Liczba spoin (poprawne pozycje).
  final int weldCount;

  /// Badane złącza per metoda.
  final Map<NdtMethod, int> ndtJoints;

  /// Koszty bezpośrednie per rodzaj, grosze. [QuoteCostKind.extras] — tylko
  /// pozycje dodatkowe Z narzutem.
  final Map<QuoteCostKind, int> costs;

  /// Koszt NDT per metoda, grosze (suma = costs[ndt]).
  final Map<NdtMethod, int> ndtCosts;

  /// Koszt spoiwa per proces, grosze (suma = costs[filler]).
  final Map<QuoteProcess, int> fillerCosts;

  final int directGrosze;
  final int overheadGrosze;
  final int marginGrosze;

  /// Pozycje dodatkowe przenoszone 1:1 (bez narzutu i zysku).
  final int passThroughGrosze;
  final int netGrosze;
  final int vatGrosze;
  final int grossGrosze;

  /// Netto według rynkowej stawki za cal-średnicę (0 = nie podano).
  final int marketNetGrosze;

  final int crew;

  const QuoteResult({
    required this.joints,
    required this.byProcess,
    required this.weldHours,
    required this.prepHours,
    required this.purgeL,
    required this.diameterInches,
    required this.diApprox,
    required this.weldLengthM,
    required this.weldCount,
    required this.ndtJoints,
    required this.costs,
    required this.ndtCosts,
    required this.fillerCosts,
    required this.directGrosze,
    required this.overheadGrosze,
    required this.marginGrosze,
    required this.passThroughGrosze,
    required this.netGrosze,
    required this.vatGrosze,
    required this.grossGrosze,
    required this.marketNetGrosze,
    required this.crew,
  });

  int get invalidJointCount => joints.where((j) => !j.isValid).length;

  double get depositedKg =>
      byProcess.values.fold(0.0, (s, u) => s + u.depositedKg);

  double get fillerKg => byProcess.values.fold(0.0, (s, u) => s + u.fillerKg);

  double get arcHours => byProcess.values.fold(0.0, (s, u) => s + u.arcHours);

  double get energyKWh => byProcess.values.fold(0.0, (s, u) => s + u.energyKWh);

  double get fluxKg => byProcess.values.fold(0.0, (s, u) => s + u.fluxKg);

  /// Roboczogodziny razem (spawacz + monter).
  double get labourHours => weldHours + prepHours;

  /// Dni robocze po 8 h przy [crew] osobach.
  double get workingDays => crew <= 0 ? 0 : labourHours / (8 * crew);

  /// Gaz osłonowy danego rodzaju, m³.
  double shieldGasM3(QuoteGasKind kind) => byProcess.entries
      .where((e) => e.key.gasKind == kind)
      .fold(0.0, (s, e) => s + e.value.shieldGasL / 1000);

  double get purgeM3 => purgeL / 1000;

  int costOf(QuoteCostKind k) => costs[k] ?? 0;

  /// Netto na jedną spoinę, grosze (0 bez spoin).
  int get netPerWeldGrosze =>
      weldCount <= 0 ? 0 : (netGrosze / weldCount).round();

  /// Netto na cal-średnicę, grosze (0 bez rur).
  int get netPerDiGrosze =>
      diameterInches <= 0 ? 0 : (netGrosze / diameterInches).round();

  /// Netto na metr spoiny, grosze.
  int get netPerMetreGrosze =>
      weldLengthM <= 0 ? 0 : (netGrosze / weldLengthM).round();

  /// Koszt robocizny razem, grosze.
  int get labourGrosze =>
      costOf(QuoteCostKind.weldLabour) + costOf(QuoteCostKind.prepLabour);

  /// Materiały i media razem (spoiwo, gazy, topnik, energia), grosze.
  int get materialsGrosze =>
      costOf(QuoteCostKind.filler) +
      costOf(QuoteCostKind.shieldGas) +
      costOf(QuoteCostKind.purgeGas) +
      costOf(QuoteCostKind.flux) +
      costOf(QuoteCostKind.energy);
}

/// Grosze z kwoty w złotych (zaokrąglenie połówek od zera).
int toGrosze(double zl) => zl.isFinite ? (zl * 100).round() : 0;

/// Mnożenie ilości przez cenę prosto do groszy — bez pośredniego
/// zaokrąglania ilości.
int costGrosze(double quantity, double unitPriceZl) =>
    toGrosze(quantity * unitPriceZl);

/// `25` (procent) od kwoty w groszach, zaokrąglone do grosza.
int percentOf(int grosze, double percent) =>
    percent.isFinite ? (grosze * percent / 100).round() : 0;

/// „1 1/4" → 1.25; „1/2" → 0.5; „24" → 24.
double? parseNps(String nps) {
  var total = 0.0;
  var any = false;
  for (final part in nps.trim().split(RegExp(r'\s+'))) {
    if (part.isEmpty) continue;
    if (part.contains('/')) {
      final f = part.split('/');
      if (f.length != 2) return null;
      final a = double.tryParse(f[0]), b = double.tryParse(f[1]);
      if (a == null || b == null || b == 0) return null;
      total += a / b;
    } else {
      final v = double.tryParse(part);
      if (v == null) return null;
      total += v;
    }
    any = true;
  }
  return any ? total : null;
}

/// Rozmiar NPS w calach dla średnicy zewnętrznej z tabeli B36.10M/B36.19M
/// (tolerancja ±0,6 mm — „114,3" i „114" to ta sama rura) albo `null`.
double? npsInchesForOd(double odMm) {
  for (final row in kPipeWalls) {
    if ((row.od - odMm).abs() <= 0.6) return parseNps(row.nps);
  }
  return null;
}

/// Reguła kosztorysowa czasu przygotowania JEDNEJ spoiny (min): fazowanie
/// / sprawdzenie fazy, ustawienie, sczepianie. Ręczna wartość w pozycji
/// ma pierwszeństwo.
///   • doczołowa rury: 10 + 0,15·OD + 0,5·t   (DN100 Sch40 ≈ 30 min)
///   • króciec:        15 + 0,25·OD króćca + 0,5·t (wycięcie otworu)
///   • pachwina rury:   5 + 0,08·OD
///   • blachy doczołowo: (20 + t) min na metr
///   • blachy pachwinowo: 6 min na metr
double autoPrepMinutes(QuoteJoint j) => switch (j.kind) {
      JointKind.pipeButt => 10 + 0.15 * j.odMm + 0.5 * j.wallMm,
      JointKind.branch => 15 + 0.25 * j.odMm + 0.5 * j.wallMm,
      JointKind.pipeFillet => 5 + 0.08 * j.odMm,
      JointKind.plateButt => (20 + j.wallMm) * j.lengthM,
      JointKind.plateFillet => 6 * j.lengthM,
    };

/// Objętości stopiwa jednej spoiny pozycji.
WeldVolumes volumesOf(QuoteJoint j) => switch (j.kind) {
      JointKind.pipeButt => pipeButtVolumes(
          od: j.odMm,
          t: j.wallMm,
          gap: j.gapMm,
          rootFace: j.rootFaceMm,
          includedAngleDeg: j.groove == GrooveType.square ? 0 : j.angleDeg,
        ),
      JointKind.pipeFillet => pipeFilletVolumes(od: j.odMm, throat: j.throatMm),
      JointKind.branch => branchVolumes(
          branchOd: j.odMm,
          t: j.wallMm,
          headerOd: j.headerOdMm,
          gap: j.gapMm,
          rootFace: j.rootFaceMm,
          bevelDeg: j.angleDeg,
        ),
      JointKind.plateButt => plateButtVolumes(
          t: j.wallMm,
          lengthMm: j.lengthM * 1000,
          groove: j.groove,
          gap: j.gapMm,
          rootFace: j.rootFaceMm,
          includedAngleDeg: j.angleDeg,
        ),
      JointKind.plateFillet =>
        plateFilletVolumes(throat: j.throatMm, lengthMm: j.lengthM * 1000),
    };

ProcessUsage _usage(double depositedKg, ProcessProfile p) {
  if (depositedKg <= 0) return ProcessUsage.zero;
  final arc = depositedKg / p.depositionKgH;
  final filler = depositedKg / p.efficiency;
  return ProcessUsage(
    depositedKg: depositedKg,
    fillerKg: filler,
    arcHours: arc,
    baseWeldHours: arc / p.dutyCycle,
    shieldGasL: p.gasLpm * 60 * arc * kShieldGasAllowance,
    energyKWh: p.arcKw * arc / kWelderPowerEfficiency,
    fluxKg: filler * p.fluxRatio,
  );
}

/// Gaz formujący dla jednej spoiny (L): przedmuch N wymian objętości
/// odcinka między przegrodami + przepływ ~5 L/min w czasie spawania grani
/// (purge_estimate.dart, HFT WP-269).
double purgeLitresPerWeld({
  required QuoteJoint j,
  required QuoteRates rates,
  required double rootWeldHoursPerWeld,
}) {
  if (!(j.kind == JointKind.pipeButt || j.kind == JointKind.branch)) return 0;
  var idMm = j.odMm - 2 * j.wallMm;
  if (j.kind == JointKind.branch && j.headerOdMm > j.odMm) {
    // Formuje się rurę główną; ściankę przyjmujemy jak króćca.
    idMm = math.max(idMm, j.headerOdMm - 2 * j.wallMm);
  }
  if (idMm <= 0 || rates.purgeLengthMm <= 0) return 0;
  final sectionL = math.pi / 4 * idMm * idMm * rates.purgeLengthMm / 1e6;
  final n = volumeChangesForTargetPpm(rates.purgeTargetPpm);
  final prePurge = n.isFinite ? sectionL * n : 0.0;
  final during = kWeldingPurgeFlowLpmMax * 60 * rootWeldHoursPerWeld;
  return prePurge + during;
}

/// Liczy jedną pozycję.
JointResult computeJoint(WeldQuote quote, QuoteJoint j) {
  final scheme = j.scheme ?? quote.scheme;
  final problems = j.problems;
  if (problems.isNotEmpty) {
    return JointResult(
      joint: j,
      problems: problems,
      scheme: scheme,
      byProcess: const {},
      weldHours: 0,
      prepHours: 0,
      purgeL: 0,
      diameterInches: 0,
      diApprox: false,
      weldLengthM: 0,
      depositedKgPerWeld: 0,
    );
  }
  final rates = quote.rates;
  final vol = volumesOf(j);
  final kgPerMm3 = quote.material.densityGcm3 * 1e-6;
  final rootKg = vol.rootMm3 * kgPerMm3;
  final fillKg = vol.fillMm3 * kgPerMm3;

  final perWeld = <QuoteProcess, ProcessUsage>{};
  void add(QuoteProcess p, double kg) {
    if (kg <= 0) return;
    final u = _usage(kg, rates.profileOf(p));
    perWeld[p] = (perWeld[p] ?? ProcessUsage.zero) + u;
  }

  if (scheme.isCombo) {
    add(scheme.root!, rootKg);
    add(scheme.fill, fillKg);
  } else {
    add(scheme.fill, rootKg + fillKg);
  }

  final n = j.count.toDouble();
  final byProcess = {
    for (final e in perWeld.entries) e.key: e.value.times(n),
  };

  final baseWeldPerWeld =
      perWeld.values.fold(0.0, (s, u) => s + u.baseWeldHours);
  final weldHours = baseWeldPerWeld * j.position.factor * quote.site.factor * n;
  final prepMin = j.prepMinutes ?? autoPrepMinutes(j);
  final prepHours = prepMin / 60 * quote.site.factor * n;

  var purgeL = 0.0;
  if (quote.purge && j.kind.onPipe) {
    final rootProcess = scheme.isCombo ? scheme.root! : scheme.fill;
    final rootUsage = _usage(rootKg, rates.profileOf(rootProcess));
    purgeL = purgeLitresPerWeld(
          j: j,
          rates: rates,
          rootWeldHoursPerWeld: rootUsage.baseWeldHours * j.position.factor,
        ) *
        n;
  }

  var di = 0.0;
  var approx = false;
  if (j.kind.onPipe) {
    final nps = npsInchesForOd(j.odMm);
    if (nps != null) {
      di = nps * n;
    } else {
      di = j.odMm / 25.4 * n;
      approx = true;
    }
  }

  return JointResult(
    joint: j,
    problems: const [],
    scheme: scheme,
    byProcess: byProcess,
    weldHours: weldHours,
    prepHours: prepHours,
    purgeL: purgeL,
    diameterInches: di,
    diApprox: approx,
    weldLengthM: vol.lengthMm / 1000 * n,
    depositedKgPerWeld: rootKg + fillKg,
  );
}

/// Liczy całą wycenę.
QuoteResult computeQuote(WeldQuote quote) {
  final rates = quote.rates;
  final joints = [for (final j in quote.joints) computeJoint(quote, j)];
  final valid = joints.where((j) => j.isValid).toList();

  final byProcess = <QuoteProcess, ProcessUsage>{};
  var weldHours = 0.0, prepHours = 0.0, purgeL = 0.0, di = 0.0, lengthM = 0.0;
  var approx = false;
  var weldCount = 0;
  for (final r in valid) {
    for (final e in r.byProcess.entries) {
      byProcess[e.key] = (byProcess[e.key] ?? ProcessUsage.zero) + e.value;
    }
    weldHours += r.weldHours;
    prepHours += r.prepHours;
    purgeL += r.purgeL;
    di += r.diameterInches;
    approx = approx || r.diApprox;
    lengthM += r.weldLengthM;
    weldCount += r.joint.count;
  }

  // ── Koszty bezpośrednie, grosze ──────────────────────────────────────────
  final fillerCosts = <QuoteProcess, int>{
    for (final e in byProcess.entries)
      e.key: costGrosze(e.value.fillerKg, rates.fillerPriceOf(e.key)),
  };
  var shieldGas = 0;
  for (final kind in QuoteGasKind.values) {
    if (kind == QuoteGasKind.none) continue;
    final m3 = byProcess.entries
        .where((e) => e.key.gasKind == kind)
        .fold(0.0, (s, e) => s + e.value.shieldGasL / 1000);
    shieldGas += costGrosze(m3, rates.shieldGasPrice(kind));
  }
  final energyKWh = byProcess.values.fold(0.0, (s, u) => s + u.energyKWh);
  final fluxKg = byProcess.values.fold(0.0, (s, u) => s + u.fluxKg);

  final ndtJoints = <NdtMethod, int>{};
  final ndtCosts = <NdtMethod, int>{};
  for (final m in NdtMethod.values) {
    final r = rates.ndtOf(m);
    if (r.percent <= 0 || weldCount == 0) continue;
    // Procent zaokrąglany w górę: 10 % z 12 spoin = 2 badane, nie 1,2.
    final n = (weldCount * r.percent / 100 - 1e-9).ceil();
    ndtJoints[m] = n;
    ndtCosts[m] = costGrosze(n.toDouble(), r.pricePerJoint);
  }

  var extrasMarkup = 0, passThrough = 0;
  for (final e in quote.extras) {
    final g = costGrosze(e.quantity, e.unitPrice);
    if (e.withMarkup) {
      extrasMarkup += g;
    } else {
      passThrough += g;
    }
  }

  final costs = <QuoteCostKind, int>{
    QuoteCostKind.weldLabour: costGrosze(weldHours, rates.welderRate),
    QuoteCostKind.prepLabour: costGrosze(prepHours, rates.fitterRate),
    QuoteCostKind.filler: fillerCosts.values.fold(0, (s, v) => s + v),
    QuoteCostKind.shieldGas: shieldGas,
    QuoteCostKind.purgeGas: costGrosze(purgeL / 1000, rates.purgeGasPrice),
    QuoteCostKind.flux: costGrosze(fluxKg, rates.fluxPrice),
    QuoteCostKind.energy: costGrosze(energyKWh, rates.electricityPrice),
    QuoteCostKind.ndt: ndtCosts.values.fold(0, (s, v) => s + v),
    QuoteCostKind.extras: extrasMarkup,
  };

  final direct = costs.values.fold(0, (s, v) => s + v);
  final overhead = percentOf(direct, rates.overheadPct);
  final margin = percentOf(direct + overhead, rates.marginPct);
  final net = direct + overhead + margin + passThrough;
  final vat = percentOf(net, rates.vat.rate * 100);

  return QuoteResult(
    joints: joints,
    byProcess: byProcess,
    weldHours: weldHours,
    prepHours: prepHours,
    purgeL: purgeL,
    diameterInches: di,
    diApprox: approx,
    weldLengthM: lengthM,
    weldCount: weldCount,
    ndtJoints: ndtJoints,
    costs: costs,
    ndtCosts: ndtCosts,
    fillerCosts: fillerCosts,
    directGrosze: direct,
    overheadGrosze: overhead,
    marginGrosze: margin,
    passThroughGrosze: passThrough,
    netGrosze: net,
    vatGrosze: vat,
    grossGrosze: net + vat,
    marketNetGrosze: rates.marketDiRate > 0 && di > 0
        ? costGrosze(di, rates.marketDiRate)
        : 0,
    crew: quote.crew,
  );
}

/// Kwota w groszach jako „12 345,67 zł" (spacja nierozdzielająca między
/// tysiącami, przecinek dziesiętny — zapis polski).
String formatPln(int grosze, {bool withUnit = true}) {
  final neg = grosze < 0;
  final abs = grosze.abs();
  final zl = abs ~/ 100;
  final gr = abs % 100;
  final digits = zl.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  final s = '${neg ? '−' : ''}$buf,${gr.toString().padLeft(2, '0')}';
  return withUnit ? '$s zł' : s;
}

/// Liczba z przecinkiem dziesiętnym i [decimals] miejscami, bez zbędnych
/// zer: 1.50 → „1,5", 2.0 → „2".
String formatQty(double v, {int decimals = 2}) {
  if (!v.isFinite) return '—';
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}
