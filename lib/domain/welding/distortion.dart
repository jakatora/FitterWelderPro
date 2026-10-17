/// Odkształcenia spawalnicze: szacunek skurczu poprzecznego spoiny czołowej,
/// wymiar zestawienia przed spawaniem i typy do listy środków zapobiegania
/// (dane: `lib/data/distortion_tips.dart`).
///
/// ŹRÓDŁA (sprawdzone 2026-10-17):
///
/// 1. Skurcz poprzeczny spoiny czołowej — wzór empiryczny Spraragena
///    i Ettingera:
///
///        S = 0,2 · A_w / t + 0,05 · d
///
///    A_w — pole przekroju spoiny, t — grubość blachy, d — odstęp w grani.
///    Praca źródłowa: W. Spraragen, W. G. Ettinger, „Shrinkage Distortion in
///    Welding”, Welding Journal 23 (11), 545s–559s, 1944 (cytowanie za
///    raportem MIT „Integration of M.I.T. Studies on Prediction and Control
///    of Distortion in Welded Aluminum Structures”, DTIC ADA033490, 1976,
///    rozdz. 3, poz. 18 — tamże: wzory na skurcz poprzeczny są empiryczne,
///    część zebrał Masubuchi w biuletynach WRC 149 i 174). Postać wzoru
///    i współczynniki 0,2 / 0,05 za literaturą wtórną (Masubuchi, „Analysis
///    of Welded Structures”, 1980; kalkulatory inżynierskie) — tekstu
///    pierwotnego nie udało się otworzyć.
///
///    JEDNOSTKI — wzór jest jednorodny wymiarowo: A_w/t to długość (średnia
///    szerokość spoiny), a 0,2 i 0,05 są bezwymiarowe. Wejście w calach daje
///    cale, wejście w mm daje mm — z TYMI SAMYMI współczynnikami (test
///    liczy ten sam rowek w obu układach). Spotykana postać
///    „5,08·A_w/t + 1,27·d” to 25,4·0,2 i 25,4·0,05: daje mm tylko przy
///    wejściu w CALACH — wpisanie do niej milimetrów zawyża wynik 25,4 raza.
///
///    ZAKRES: spoina czołowa blach stalowych w złączu swobodnym, rowek V,
///    X albo ½V. Utwierdzenie zmniejsza skurcz poprzeczny (Parmar, „Welding
///    Engineering and Technology”; NPTEL IIT Roorkee, Welding Metallurgy,
///    wykł. 42). NIE dla rowka I: pole rowka b·t nie jest polem stopiwa.
///    Spoina obwodowa rury — wzór dotyczy blach, wynik traktuj orientacyjnie.
///    A_w = pole ROWKA z geometrii (weld_geometry.dart), bez nadlewu lica
///    i grani — nadlew zwiększa rzeczywisty skurcz.
///
///    Ta sama literatura podaje też prostszą regułę „ok. 10 % średniej
///    szerokości spoiny” (0,1·A_w/t — Parmar / NPTEL wykł. 42), która daje
///    mniej więcej połowę. Wybraliśmy Spraragena–Ettingera, bo jest zgodny
///    z regułą TWI (poniżej) i daje większy naddatek — a lepiej dociąć niż
///    dospawać.
///
/// 2. Reguły TWI dla stali (TWI Job Knowledge 33 „Distortion — types and
///    causes” i FAQ „How much shall I allow for weld shrinkage?”):
///    poprzecznie — spoina czołowa rowek V 60°: 1,5–3 mm na spoinę
///    (zależnie od liczby ściegów); pachwinowa: 0,8 mm na spoinę, gdy noga
///    ≤ ¾ grubości blachy. Wzdłużnie — czołowa ok. 3 mm na 3 m spoiny,
///    pachwinowa ok. 0,8 mm na 3 m. TWI zaznacza, że dokładne przewidzenie
///    skurczu jest „prawie niemożliwe”.
///
/// Wzoru na odkształcenie kątowe pachwin (np. Δ = 0,02·W·ω^1,3/t²
/// przypisywany Blodgettowi) ani na skurcz wzdłużny z prądu NIE ma: źródła
/// wtórne podają różne postaci i współczynniki, a tekstu pierwotnego nie
/// udało się sprawdzić.
///
/// Każdy wynik to SZACUNEK — rzeczywisty skurcz zależy od sztywności,
/// kolejności spawania i energii liniowej; sprawdź na próbie.
///
/// Czysty Dart.
library;

import '../quotes/weld_geometry.dart';

// ─── Stałe ze źródeł ─────────────────────────────────────────────────────

/// Spraragen–Ettinger: współczynnik przy średniej szerokości A_w/t.
const double kSeAreaCoef = 0.2;

/// Spraragen–Ettinger: współczynnik przy odstępie w grani d.
const double kSeGapCoef = 0.05;

/// TWI: skurcz poprzeczny spoiny czołowej, rowek V 60° — dolna granica [mm].
const double kTwiButtV60MinMm = 1.5;

/// TWI: skurcz poprzeczny spoiny czołowej, rowek V 60° — górna granica [mm].
const double kTwiButtV60MaxMm = 3.0;

/// TWI: skurcz poprzeczny spoiny pachwinowej [mm na spoinę], gdy noga
/// ≤ ¾ grubości blachy.
const double kTwiFilletTransverseMm = 0.8;

/// Krok zaokrąglenia wymiaru przed spawaniem [mm] — w górę.
const double kPreWeldStepMm = 0.5;

// ─── Zakresy pól (granice wpisu, nie dane techniczne) ────────────────────

const double kMaxThicknessMm = 100;
const double kMaxGapMm = 10;
const double kMinIncludedAngleDeg = 10;
const double kMaxIncludedAngleDeg = 120;
const double kMinBevelDeg = 5;
const double kMaxBevelDeg = 60;
const double kMaxFinalLengthMm = 100000;
const int kMaxWelds = 100;
const double kMaxShrinkagePerWeldMm = 20;

// ─── Skurcz poprzeczny spoiny czołowej ───────────────────────────────────

/// Rowek spoiny czołowej, dla którego liczymy skurcz.
enum ButtGroove {
  /// Rowek V (Y z progiem) — spawany z jednej strony; kąt = całkowity α.
  v,

  /// Rowek X — próg w środku grubości, spawany z dwóch stron; kąt = α
  /// każdej połowy.
  x,

  /// Rowek ½V — faza tylko na jednym elemencie; kąt = kąt fazy β.
  halfV,
}

class ButtShrinkageInput {
  final ButtGroove groove;

  /// Grubość blachy t [mm].
  final double thicknessMm;

  /// Odstęp w grani d [mm].
  final double gapMm;

  /// Próg (płaska część czoła) c [mm].
  final double rootFaceMm;

  /// V i X: całkowity kąt rowka α; ½V: kąt fazy β [°].
  final double angleDeg;

  const ButtShrinkageInput({
    required this.groove,
    required this.thicknessMm,
    required this.gapMm,
    required this.rootFaceMm,
    required this.angleDeg,
  });
}

enum ShrinkageProblem { thickness, gap, rootFace, angle }

/// Co jest nie tak z danymi — pusta lista = da się liczyć. Puste albo
/// nieczytelne pole przychodzi jako NaN i zawsze jest problemem.
List<ShrinkageProblem> shrinkageProblems(ButtShrinkageInput i) {
  final out = <ShrinkageProblem>[];
  final t = i.thicknessMm;
  final tOk = t.isFinite && t > 0 && t <= kMaxThicknessMm;
  if (!tOk) out.add(ShrinkageProblem.thickness);
  if (!(i.gapMm.isFinite && i.gapMm >= 0 && i.gapMm <= kMaxGapMm)) {
    out.add(ShrinkageProblem.gap);
  }
  final c = i.rootFaceMm;
  if (!(c.isFinite && c >= 0 && (!tOk || c < t))) {
    out.add(ShrinkageProblem.rootFace);
  }
  final a = i.angleDeg;
  final angleOk = i.groove == ButtGroove.halfV
      ? a.isFinite && a >= kMinBevelDeg && a <= kMaxBevelDeg
      : a.isFinite && a >= kMinIncludedAngleDeg && a <= kMaxIncludedAngleDeg;
  if (!angleOk) out.add(ShrinkageProblem.angle);
  return out;
}

/// Pole przekroju rowka A_w [mm²] z modelu wycen (weld_geometry.dart),
/// bez nadlewów. Rowek X = dwie połówki V o głębokości t/2 z progiem c/2:
/// 2·[d·t/2 + ((t − c)/2)²·tg(α/2)] — to samo co w `plateButtVolumes`.
double buttGrooveAreaMm2(ButtShrinkageInput i) {
  final t = i.thicknessMm, d = i.gapMm, c = i.rootFaceMm, a = i.angleDeg;
  return switch (i.groove) {
    ButtGroove.v =>
      grooveAreaV(h: t, gap: d, rootFace: c, includedAngleDeg: a),
    ButtGroove.halfV =>
      grooveAreaHalfV(h: t, gap: d, rootFace: c, bevelDeg: a),
    ButtGroove.x => 2 *
        grooveAreaV(h: t / 2, gap: d, rootFace: c / 2, includedAngleDeg: a),
  };
}

/// Wzór Spraragena–Ettingera w dowolnych SPÓJNYCH jednostkach długości
/// (pole w jednostkach²): S = 0,2·A_w/t + 0,05·d.
double spraragenEttingerShrinkage({
  required double areaW,
  required double thickness,
  required double gap,
}) =>
    kSeAreaCoef * areaW / thickness + kSeGapCoef * gap;

class ButtShrinkageResult {
  final ButtShrinkageInput input;

  /// Pole rowka A_w [mm²].
  final double areaMm2;

  const ButtShrinkageResult({required this.input, required this.areaMm2});

  /// Średnia szerokość spoiny A_w/t [mm].
  double get meanWidthMm => areaMm2 / input.thicknessMm;

  /// 0,2·A_w/t [mm].
  double get areaTermMm => kSeAreaCoef * meanWidthMm;

  /// 0,05·d [mm].
  double get gapTermMm => kSeGapCoef * input.gapMm;

  /// Szacowany skurcz poprzeczny jednej spoiny [mm].
  double get shrinkageMm => areaTermMm + gapTermMm;

  /// Skurcz zaokrąglony do 0,1 mm — ta liczba stoi na ekranie i idzie do
  /// łańcucha wymiarowego, żeby „n × S” zgadzało się z tym, co widać.
  double get shrinkageRoundedMm => roundToTenth(shrinkageMm);
}

/// null, gdy dane mają problem (nigdy NaN ani ∞).
ButtShrinkageResult? computeButtShrinkage(ButtShrinkageInput i) {
  if (shrinkageProblems(i).isNotEmpty) return null;
  final area = buttGrooveAreaMm2(i);
  if (!area.isFinite || area <= 0) return null;
  return ButtShrinkageResult(input: i, areaMm2: area);
}

/// Zaokrąglenie do 0,1 (połówki w górę).
double roundToTenth(double v) => (v * 10).round() / 10;

// ─── Wymiar przed spawaniem (łańcuch wymiarowy) ──────────────────────────

class PreWeldInput {
  /// Wymiar elementu po spawaniu [mm].
  final double finalLengthMm;

  /// Liczba spoin czołowych poprzecznych w łańcuchu (liczba całkowita;
  /// double, żeby pole z ułamkiem było problemem, nie ucięciem).
  final double buttWelds;

  /// Skurcz jednej spoiny czołowej [mm] — szacunek albo pomiar z próby.
  final double shrinkagePerButtMm;

  /// Liczba spoin pachwinowych poprzecznych w łańcuchu — każda po
  /// [kTwiFilletTransverseMm] (TWI, noga ≤ ¾ t).
  final double filletWelds;

  const PreWeldInput({
    required this.finalLengthMm,
    required this.buttWelds,
    required this.shrinkagePerButtMm,
    this.filletWelds = 0,
  });
}

enum PreWeldProblem {
  finalLength,
  buttWelds,
  filletWelds,
  noWelds,
  shrinkagePerButt,
}

bool _isCount(double v) =>
    v.isFinite && v >= 0 && v <= kMaxWelds && v == v.roundToDouble();

List<PreWeldProblem> preWeldProblems(PreWeldInput i) {
  final out = <PreWeldProblem>[];
  final l = i.finalLengthMm;
  if (!(l.isFinite && l > 0 && l <= kMaxFinalLengthMm)) {
    out.add(PreWeldProblem.finalLength);
  }
  final buttOk = _isCount(i.buttWelds);
  final filletOk = _isCount(i.filletWelds);
  if (!buttOk) out.add(PreWeldProblem.buttWelds);
  if (!filletOk) out.add(PreWeldProblem.filletWelds);
  if (buttOk && filletOk && i.buttWelds + i.filletWelds < 1) {
    out.add(PreWeldProblem.noWelds);
  }
  // Skurcz na spoinę czołową liczy się tylko, gdy są spoiny czołowe.
  if (!buttOk || i.buttWelds > 0) {
    final s = i.shrinkagePerButtMm;
    if (!(s.isFinite && s >= 0 && s <= kMaxShrinkagePerWeldMm)) {
      out.add(PreWeldProblem.shrinkagePerButt);
    }
  }
  return out;
}

/// [v] zaokrąglone W GÓRĘ do wielokrotności [step]. Tolerancja 1e-6 kroku
/// chroni przed „1002,5000000001 → 1003” z arytmetyki zmiennoprzecinkowej.
double roundUpToStep(double v, double step) =>
    ((v / step) - 1e-6).ceilToDouble() * step;

class PreWeldResult {
  final PreWeldInput input;

  const PreWeldResult(this.input);

  int get buttWelds => input.buttWelds.round();
  int get filletWelds => input.filletWelds.round();

  /// Σ skurczu spoin czołowych [mm].
  double get buttShrinkageMm =>
      buttWelds == 0 ? 0 : buttWelds * input.shrinkagePerButtMm;

  /// Σ skurczu spoin pachwinowych [mm] (TWI 0,8 mm na spoinę).
  double get filletShrinkageMm => filletWelds * kTwiFilletTransverseMm;

  double get totalShrinkageMm => buttShrinkageMm + filletShrinkageMm;

  /// Wymiar końcowy + Σ skurczu, bez zaokrąglenia [mm].
  double get rawLengthMm => input.finalLengthMm + totalShrinkageMm;

  /// Wymiar zestawienia przed spawaniem, zaokrąglony W GÓRĘ do 0,5 mm.
  ///
  /// Dlaczego w górę: element za długi po spawaniu da się dociąć albo
  /// dopasować przy kolejnym złożeniu; za krótki trzeba dospawać
  /// (napawanie, wstawka) — drożej i z kolejną spoiną, która też się
  /// kurczy. Zaokrąglenie dodaje najwyżej 0,5 mm naddatku.
  double get preWeldLengthMm => roundUpToStep(rawLengthMm, kPreWeldStepMm);

  /// Ile dodało zaokrąglenie [mm] (0 ≤ x < 0,5).
  double get roundingAddMm => preWeldLengthMm - rawLengthMm;
}

PreWeldResult? computePreWeld(PreWeldInput i) =>
    preWeldProblems(i).isEmpty ? PreWeldResult(i) : null;

// ─── Zapobieganie: sytuacja i środki ─────────────────────────────────────

/// Rodzaj elementu.
enum DistortionElement {
  plateButt('Blachy doczołowo', 'Plates, butt joint'),
  teeFillet('Teownik / pachwina', 'Tee / fillet weld'),
  pipeGirth('Rura — spoina obwodowa', 'Pipe — girth weld'),
  flangeOnPipe('Kołnierz na rurze', 'Flange on pipe'),
  tankShell('Zbiornik / płaszcz', 'Tank / shell'),
  longMember('Długi profil / belka', 'Long member / beam');

  const DistortionElement(this.pl, this.en);
  final String pl;
  final String en;
  String label({required bool en}) => en ? this.en : pl;
}

/// Rodzaj odkształcenia.
enum DistortionKind {
  angular('Kątowe — załamanie na spoinie', 'Angular — kink at the weld'),
  bowing('Wygięcie wzdłużne', 'Longitudinal bowing'),
  buckling('Falowanie cienkiej blachy', 'Buckling of thin plate'),
  twisting('Skręcenie', 'Twisting'),
  flangeTilt('Kołnierz poszedł w skos', 'Flange out of square'),
  gapClosing('Szczelina się zamyka / element się skraca',
      'Gap closing / part shortening');

  const DistortionKind(this.pl, this.en);
  final String pl;
  final String en;
  String label({required bool en}) => en ? this.en : pl;
}

/// Przycisk przy środku — otwiera inny moduł.
enum MeasureLink { heatInput, flangeCheck }

/// Jeden środek zapobiegania (albo korekty) z krótkim „dlaczego”.
class DistortionMeasure {
  final String id;
  final String titlePl;
  final String titleEn;

  /// Co zrobić.
  final String howPl;
  final String howEn;

  /// Dlaczego to działa.
  final String whyPl;
  final String whyEn;

  final Set<DistortionElement> elements;
  final Set<DistortionKind> kinds;

  /// Skąd zalecenie (i liczby w nim).
  final String source;

  final MeasureLink? link;

  /// Korekta po spawaniu, nie zapobieganie — na liście na końcu.
  final bool correction;

  const DistortionMeasure({
    required this.id,
    required this.titlePl,
    required this.titleEn,
    required this.howPl,
    required this.howEn,
    required this.whyPl,
    required this.whyEn,
    required this.elements,
    required this.kinds,
    required this.source,
    this.link,
    this.correction = false,
  });

  String title({required bool en}) => en ? titleEn : titlePl;
  String how({required bool en}) => en ? howEn : howPl;
  String why({required bool en}) => en ? whyEn : whyPl;

  bool appliesTo(DistortionElement e, DistortionKind k) =>
      elements.contains(e) && kinds.contains(k);
}

// ─── Tekst ───────────────────────────────────────────────────────────────

/// Liczba z [decimals] miejscami: przecinek po polsku, kropka po angielsku.
String distFixed(double v, int decimals, {required bool en}) {
  var s = v.toStringAsFixed(decimals);
  if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  return en ? s : s.replaceAll('.', ',');
}

/// Liczba bez zbędnych zer (do 2 miejsc): 1,50 → „1,5”, 60 → „60”.
String distNum(double v, {required bool en}) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

String grooveLabel(ButtGroove g, {required bool en}) => switch (g) {
      ButtGroove.v => en ? 'single-V' : 'rowek V',
      ButtGroove.x => en ? 'double-V (X)' : 'rowek X',
      ButtGroove.halfV => en ? 'single-bevel (½V)' : 'rowek ½V',
    };

/// Zastrzeżenie przy każdym wyniku.
String distortionDisclaimer({required bool en}) => en
    ? 'ESTIMATE: actual shrinkage depends on restraint, welding sequence and '
        'heat input — check it on a trial joint. The WPS and the drawing '
        'are binding.'
    : 'SZACUNEK: rzeczywisty skurcz zależy od sztywności, kolejności '
        'spawania i energii liniowej — sprawdź na próbie. Wiążące są WPS '
        'i rysunek.';

/// Opis wzoru i źródła — na ekranie i w udostępnianym tekście.
String shrinkageFormulaNote({required bool en}) => en
    ? 'Spraragen–Ettinger (Welding Journal, 1944): S = 0.2·A_w/t + 0.05·d. '
        'Dimensionally consistent — the same coefficients for mm and inches. '
        'For butt welds in steel plates, unrestrained joint; restraint '
        'reduces shrinkage. A_w = groove area without reinforcement. For a '
        'pipe girth weld treat it as a guide only.'
    : 'Spraragen–Ettinger (Welding Journal, 1944): S = 0,2·A_w/t + 0,05·d. '
        'Wzór jednorodny wymiarowo — te same współczynniki dla mm i cali. '
        'Dla spoin czołowych blach stalowych w złączu swobodnym; utwierdzenie '
        'zmniejsza skurcz. A_w = pole rowka bez nadlewów. Dla spoiny '
        'obwodowej rury — tylko orientacyjnie.';

/// Reguła TWI do porównania (rowek V 60°).
String twiButtNote({required bool en}) {
  final lo = distNum(kTwiButtV60MinMm, en: en);
  final hi = distNum(kTwiButtV60MaxMm, en: en);
  return en
      ? 'TWI rule of thumb for a 60° V joint: $lo–$hi mm per weld, '
          'depending on the number of runs.'
      : 'Reguła TWI dla rowka V 60°: $lo–$hi mm na spoinę, zależnie od '
          'liczby ściegów.';
}

/// Reguła TWI — skurcz wzdłużny (informacyjnie).
String twiLongitudinalNote({required bool en}) {
  final f = distNum(kTwiFilletTransverseMm, en: en);
  return en
      ? 'Longitudinal shrinkage (TWI, rule of thumb): butt weld about 3 mm '
          'per 3 m of weld, fillet weld about $f mm per 3 m.'
      : 'Skurcz wzdłużny (TWI, orientacyjnie): spoina czołowa ok. 3 mm na '
          '3 m spoiny, pachwinowa ok. $f mm na 3 m.';
}

/// Tekst do udostępnienia: szacunek, wymiar przed spawaniem, sytuacja
/// i środki. Każda część opcjonalna — brak wyniku to brak sekcji, nie zero.
String distortionShareText({
  required bool en,
  ButtShrinkageResult? shrinkage,
  PreWeldResult? preWeld,
  bool measuredShrinkage = false,
  DistortionElement? element,
  DistortionKind? kind,
  List<DistortionMeasure> measures = const [],
}) {
  String n(double v) => distNum(v, en: en);
  String f1(double v) => distFixed(v, 1, en: en);
  final b = StringBuffer()
    ..writeln(en
        ? 'Welding distortion — estimate and prevention'
        : 'Odkształcenia spawalnicze — szacunek i zapobieganie');
  if (shrinkage != null) {
    final i = shrinkage.input;
    final angle = i.groove == ButtGroove.halfV
        ? (en ? 'bevel ${n(i.angleDeg)}°' : 'faza ${n(i.angleDeg)}°')
        : '${n(i.angleDeg)}°';
    b
      ..writeln()
      ..writeln(en
          ? 'Transverse shrinkage of a butt weld:'
          : 'Skurcz poprzeczny spoiny czołowej:')
      ..writeln('${grooveLabel(i.groove, en: en)} $angle, '
          't = ${n(i.thicknessMm)} mm, d = ${n(i.gapMm)} mm, '
          'c = ${n(i.rootFaceMm)} mm')
      ..writeln('A_w = ${f1(shrinkage.areaMm2)} mm², '
          'A_w/t = ${distFixed(shrinkage.meanWidthMm, 2, en: en)} mm')
      ..writeln(en
          ? 'S ≈ ${f1(shrinkage.shrinkageRoundedMm)} mm per weld'
          : 'S ≈ ${f1(shrinkage.shrinkageRoundedMm)} mm na spoinę')
      ..writeln(shrinkageFormulaNote(en: en))
      ..writeln(twiButtNote(en: en));
  }
  if (preWeld != null) {
    final p = preWeld;
    b
      ..writeln()
      ..writeln(en ? 'Dimension before welding:' : 'Wymiar przed spawaniem:')
      ..writeln(en
          ? 'Final dimension ${n(p.input.finalLengthMm)} mm'
          : 'Wymiar końcowy ${n(p.input.finalLengthMm)} mm');
    if (p.buttWelds > 0) {
      final src = measuredShrinkage
          ? (en ? 'measured' : 'pomiar')
          : (en ? 'estimate' : 'szacunek');
      b.writeln(en
          ? 'Butt welds: ${p.buttWelds} × ${n(p.input.shrinkagePerButtMm)} mm '
              '($src) = ${f1(p.buttShrinkageMm)} mm'
          : 'Spoiny czołowe: ${p.buttWelds} × ${n(p.input.shrinkagePerButtMm)} mm '
              '($src) = ${f1(p.buttShrinkageMm)} mm');
    }
    if (p.filletWelds > 0) {
      b.writeln(en
          ? 'Fillet welds: ${p.filletWelds} × ${n(kTwiFilletTransverseMm)} mm '
              '(TWI) = ${f1(p.filletShrinkageMm)} mm'
          : 'Spoiny pachwinowe: ${p.filletWelds} × ${n(kTwiFilletTransverseMm)} mm '
              '(TWI) = ${f1(p.filletShrinkageMm)} mm');
    }
    b
      ..writeln(en
          ? 'Total shrinkage ${f1(p.totalShrinkageMm)} mm'
          : 'Suma skurczu ${f1(p.totalShrinkageMm)} mm')
      ..writeln(en
          ? 'Set up before welding: ${f1(p.preWeldLengthMm)} mm '
              '(rounded UP to 0.5 mm — better to trim than to add weld)'
          : 'Zestaw przed spawaniem: ${f1(p.preWeldLengthMm)} mm '
              '(zaokrąglone W GÓRĘ do 0,5 mm — lepiej dociąć niż dospawać)');
  }
  if (element != null && kind != null) {
    b
      ..writeln()
      ..writeln(en
          ? 'Situation: ${element.label(en: en)} — ${kind.label(en: en)}'
          : 'Sytuacja: ${element.label(en: en)} — ${kind.label(en: en)}');
    var k = 0;
    for (final m in measures) {
      k++;
      b
        ..writeln('$k. ${m.title(en: en)}'
            '${m.correction ? (en ? ' (correction)' : ' (korekta)') : ''}')
        ..writeln('   ${m.how(en: en)}')
        ..writeln('   ${en ? 'Why' : 'Dlaczego'}: ${m.why(en: en)}')
        ..writeln('   ${en ? 'Source' : 'Źródło'}: ${m.source}');
    }
  }
  b
    ..writeln()
    ..write(distortionDisclaimer(en: en));
  return b.toString();
}
