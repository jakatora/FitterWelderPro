/// Lista kontrolna stanowiska spawalniczego pod kątem dymu — jako dane
/// (PL/EN), w grupach: odciąg, materiał, pomieszczenie, ŚOI.
///
/// Zasada: punkt NIEZAZNACZONY to NIE „ok”. Lista jest kompletna tylko
/// wtedy, gdy każdy punkt jest zaznaczony albo — tam, gdzie to dozwolone —
/// oznaczony „nie dotyczy”. „Nie dotyczy” sprzeczne z wyborem na ekranie
/// ([fumeNaBlock]: powłoka / ocynk / nieznany materiał przy punkcie
/// o powłokach, maska przylegająca przy punkcie o dopasowaniu, gazy przy
/// punkcie o gazach) liczy się jako punkt otwarty. Stanu listy NIE
/// zapisujemy: każda zmiana i stanowisko to nowe sprawdzenie (stare
/// „ptaszki” nie mogą udawać aktualnych).
///
/// Czysty Dart.
library;

import 'fume_hazards.dart';

enum FumeCheckGroup {
  extraction('Odciąg u źródła', 'Extraction at source'),
  material('Materiał i powłoki', 'Material and coatings'),
  room('Pomieszczenie i otoczenie', 'Room and surroundings'),
  rpe('Ochrona dróg oddechowych', 'Respiratory protection');

  const FumeCheckGroup(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

class FumeCheck {
  const FumeCheck(
    this.id,
    this.group,
    this.pl,
    this.en, {
    this.naAllowed = false,
    this.naPl,
    this.naEn,
    required this.source,
  });

  /// Trwały identyfikator — nie zmieniać.
  final String id;
  final FumeCheckGroup group;
  final String pl;
  final String en;

  /// Wolno oznaczyć „nie dotyczy”.
  final bool naAllowed;

  /// Kiedy „nie dotyczy” (podpowiedź pod punktem).
  final String? naPl;
  final String? naEn;

  /// Krótkie odwołanie do źródła (pełne opisy: fume_sources.dart).
  final String source;

  String label({required bool en}) => en ? this.en : pl;
  String? naHint({required bool en}) => en ? naEn : naPl;
}

/// Stan punktu.
enum FumeCheckState { open, done, notApplicable }

/// Identyfikator punktu odsyłającego do modułu „Przestrzeń zamknięta”.
const String kFumeCheckConfinedId = 'room-confined';

/// Punkt o usunięciu powłok.
const String kFumeCheckCoatingsId = 'mat-coatings';

/// Punkt o gazach (ozon, NOx, CO, opary z powłok).
const String kFumeCheckGasId = 'room-gases';

/// Punkt o dopasowaniu maski przylegającej.
const String kFumeCheckFitId = 'rpe-fit';

/// Lista kontrolna — w kolejności wyświetlania.
const List<FumeCheck> kFumeChecks = [
  // ── Odciąg ────────────────────────────────────────────────────────────────
  FumeCheck(
    'lev-close',
    FumeCheckGroup.extraction,
    'Odciąg włączony przed zajarzeniem łuku; ssawka nie dalej od łuku niż '
        'zasięg z kalkulatora i przestawiana razem z postępem pracy',
    'Extraction switched on before striking the arc; the hood no further '
        'from the arc than the reach from the calculator and moved along '
        'with the work',
    source: 'DallaValle (ACGIH); OSHA 1910.252(c)(3)(i); HSE 2019',
  ),
  FumeCheck(
    'lev-plume',
    FumeCheckGroup.extraction,
    'Ssawka z boku lub z tyłu, nieco nad łukiem — smuga dymu idzie do '
        'ssawki, a nie przez strefę oddychania; głowa poza smugą',
    'Hood to the side or behind, slightly above the arc — the plume goes '
        'into the hood, not through the breathing zone; head out of the plume',
    source: 'praktyka: HSE — welding fume',
  ),
  FumeCheck(
    'lev-filter',
    FumeCheckGroup.extraction,
    'Filtr odciągu wymieniany / czyszczony wg producenta; wskaźnik '
        'przepływu lub oporu filtra w normie',
    'Extractor filter replaced / cleaned as the maker says; the flow or '
        'filter-resistance indicator within range',
    naAllowed: true,
    naPl: 'nie dotyczy: wywiew na zewnątrz bez filtra w urządzeniu',
    naEn: 'not applicable: exhaust outside with no filter in the unit',
    source: 'praktyka: instrukcja producenta',
  ),
  FumeCheck(
    'lev-recirc',
    FumeCheckGroup.extraction,
    'Powietrze z odciągu wraca do hali (recyrkulacja) tylko przez sprawny '
        'filtr z sygnalizacją zapchania; przy nierdzewce i stopach niklu '
        '(Cr, Ni) zasadniczo wywiew na zewnątrz, wyjątkowo urządzenie '
        'oznaczone W3',
    'Extracted air returned to the workshop (recirculation) only through a '
        'working filter with a blocked-filter alarm; with stainless and '
        'nickel alloys (Cr, Ni) in principle exhaust outside, exceptionally '
        'a unit marked W3',
    naAllowed: true,
    naPl: 'nie dotyczy: wywiew na zewnątrz, bez recyrkulacji',
    naEn: 'not applicable: exhaust outside, no recirculation',
    source: 'TRGS 528 pkt 4.5; EN ISO 21904-1/-2; HSE HSG258',
  ),
  FumeCheck(
    'lev-exam',
    FumeCheckGroup.extraction,
    'Odciąg ma aktualny przegląd skuteczności (przepływ zmierzony, wynik '
        'zapisany)',
    'The extraction has a current performance check (airflow measured, '
        'result recorded)',
    source: 'praktyka HSE: COSHH reg. 9, HSG258 — co najmniej co 14 mies.',
  ),
  // ── Materiał ──────────────────────────────────────────────────────────────
  FumeCheck(
    'mat-sds',
    FumeCheckGroup.material,
    'Skład znany: karta charakterystyki spoiwa (skład dymu) i materiału; '
        'gdy nieznany — ochrona jak dla najgorszego przypadku',
    'Composition known: the filler’s safety data sheet (fume composition) '
        'and the material; if unknown — protection for the worst case',
    source: 'karta charakterystyki (SDS) producenta spoiwa',
  ),
  FumeCheck(
    kFumeCheckCoatingsId,
    FumeCheckGroup.material,
    'Farby, ocynk, oleje, smary i inne powłoki usunięte ze strefy spawania '
        'lub cięcia (zdzieranie też z odciągiem i ŚOI)',
    'Paint, galvanising, oil, grease and other coatings removed from the '
        'weld or cut area (stripping also with extraction and RPE)',
    naAllowed: true,
    naPl: 'nie dotyczy: goły, czysty materiał',
    naEn: 'not applicable: bare, clean metal',
    source: 'praktyka: HSE — welding fume; eliminacja u źródła',
  ),
  // ── Pomieszczenie ─────────────────────────────────────────────────────────
  FumeCheck(
    kFumeCheckGasId,
    FumeCheckGroup.room,
    'Gazy (ozon, tlenki azotu, CO, opary z powłok) ujęte odciągiem '
        'i wentylacją ogólną — filtr P3 nie chroni przed gazami',
    'Gases (ozone, nitrogen oxides, CO, coating vapours) removed by '
        'extraction and general ventilation — a P3 filter does not protect '
        'against gases',
    naAllowed: true,
    naPl: 'nie dotyczy: przy tym materiale i procesie aplikacja nie '
        'wskazuje gazów',
    naEn: 'not applicable: the app lists no gases for this material and '
        'process',
    source: 'HSE — welding controls (FFP3/P3 nie chroni przed gazami)',
  ),
  FumeCheck(
    'room-general',
    FumeCheckGroup.room,
    'Wentylacja ogólna działa — dopływ świeżego powietrza, dym nie zbiera '
        'się w hali (uzupełnia odciąg, nie zastępuje go)',
    'General ventilation works — fresh air comes in, fume does not build '
        'up in the workshop (it adds to extraction, never replaces it)',
    naAllowed: true,
    naPl: 'nie dotyczy: praca na zewnątrz',
    naEn: 'not applicable: working outdoors',
    source: 'hierarchia środków ochrony (HSE 2019)',
  ),
  FumeCheck(
    kFumeCheckConfinedId,
    FumeCheckGroup.room,
    'Przestrzeń zamknięta (zbiornik, kanał, wnętrze konstrukcji): wykonana '
        'procedura z modułu „Przestrzeń zamknięta: wejście i spawanie”',
    'Confined space (tank, sewer, inside a structure): the procedure from '
        'the “Confined space: entry and welding” module done',
    naAllowed: true,
    naPl: 'nie dotyczy: to nie jest przestrzeń zamknięta',
    naEn: 'not applicable: not a confined space',
    source: 'rozp. MPiPS 26.09.1997 §§ 85–90',
  ),
  FumeCheck(
    'room-others',
    FumeCheckGroup.room,
    'Inne osoby poza smugą dymu (ekrany, kierunek ciągu, odstęp)',
    'Other people out of the plume (screens, airflow direction, distance)',
    naAllowed: true,
    naPl: 'nie dotyczy: nikogo w pobliżu',
    naEn: 'not applicable: nobody nearby',
    source: 'praktyka: HSE — welding fume',
  ),
  FumeCheck(
    'room-airing',
    FumeCheckGroup.room,
    'Po pracy: pomieszczenie przewietrzone, zanim zdejmiesz ŚOI lub wejdą '
        'inni; odciąg pracuje jeszcze chwilę po zgaszeniu łuku',
    'After work: the room aired before you take off RPE or others come in; '
        'extraction keeps running for a while after the arc goes out',
    naAllowed: true,
    naPl: 'nie dotyczy: praca na zewnątrz',
    naEn: 'not applicable: working outdoors',
    source: 'praktyka',
  ),
  // ── ŚOI ───────────────────────────────────────────────────────────────────
  FumeCheck(
    kFumeCheckFitId,
    FumeCheckGroup.rpe,
    'Półmaska / FFP: test dopasowania zrobiony, strefa uszczelnienia gładko '
        'ogolona; z zarostem — tylko przyłbica z nawiewem (TH)',
    'Half mask / FFP: fit test done, the seal area clean-shaven; with '
        'facial hair — only a powered helmet (TH)',
    naAllowed: true,
    naPl: 'nie dotyczy: przyłbica z nawiewem (TH)',
    naEn: 'not applicable: powered helmet (TH)',
    source: 'HSE INDG479; EN 529',
  ),
  FumeCheck(
    'rpe-maint',
    FumeCheckGroup.rpe,
    'ŚOI sprawne: FFP jednorazowa (NR) najwyżej na jedną zmianę; filtr '
        'i akumulator nawiewu wg wskaźnika producenta',
    'RPE in working order: a single-shift (NR) FFP for one shift at most; '
        'powered unit filter and battery per the maker’s indicator',
    source: 'EN 149 (oznaczenie NR / R); instrukcja producenta',
  ),
];

final Map<String, FumeCheck> _byId = {for (final c in kFumeChecks) c.id: c};

FumeCheck? fumeCheckById(String id) => _byId[id];

List<FumeCheck> fumeChecksIn(FumeCheckGroup g) => [
      for (final c in kFumeChecks)
        if (c.group == g) c
    ];

/// Wybory z ekranu, od których zależy, czy „nie dotyczy” ma sens.
class FumeCheckContext {
  const FumeCheckContext({this.material, this.process, this.rpe});

  final FumeMaterial? material;
  final FumeProcess? process;
  final FumeRpe? rpe;

  /// Para materiał–proces daje gazy, których filtry P nie zatrzymują.
  bool get gasHazard =>
      material != null &&
      process != null &&
      fumeHasGasHazard(material!, process!);
}

/// Dlaczego „nie dotyczy” jest w tym kontekście niedozwolone.
enum FumeNaBlock {
  /// Materiał z powłoką, ocynk albo nieznany — nie jest „goły”.
  coatedMaterial,

  /// Wybrany sprzęt nie jest przyłbicą z nawiewem (FFP / półmaska / brak).
  notPowered,

  /// Para materiał–proces daje gazy.
  gasHazard,
}

/// Blokada „nie dotyczy” dla punktu [c] przy wyborach [ctx]; `null` —
/// „nie dotyczy” wolno (o ile punkt w ogóle na nie pozwala).
FumeNaBlock? fumeNaBlock(FumeCheck c, FumeCheckContext ctx) {
  switch (c.id) {
    case kFumeCheckCoatingsId:
      final m = ctx.material;
      if (m == FumeMaterial.coated ||
          m == FumeMaterial.galvanised ||
          m == FumeMaterial.other) {
        return FumeNaBlock.coatedMaterial;
      }
    case kFumeCheckFitId:
      final r = ctx.rpe;
      if (r != null && !r.powered) return FumeNaBlock.notPowered;
    case kFumeCheckGasId:
      if (ctx.gasHazard) return FumeNaBlock.gasHazard;
  }
  return null;
}

/// Stan punktu — brak wpisu to „otwarty”; „nie dotyczy” tam, gdzie nie
/// wolno albo gdzie przeczy wyborom ([fumeNaBlock]), też liczy się jako
/// otwarty.
FumeCheckState fumeCheckState(FumeCheck c, Map<String, FumeCheckState> states,
    [FumeCheckContext ctx = const FumeCheckContext()]) {
  final s = states[c.id] ?? FumeCheckState.open;
  if (s == FumeCheckState.notApplicable &&
      (!c.naAllowed || fumeNaBlock(c, ctx) != null)) {
    return FumeCheckState.open;
  }
  return s;
}

/// Punkty jeszcze otwarte (niezaznaczone ≠ ok).
List<FumeCheck> fumeOpenChecks(Map<String, FumeCheckState> states,
        [FumeCheckContext ctx = const FumeCheckContext()]) =>
    [
      for (final c in kFumeChecks)
        if (fumeCheckState(c, states, ctx) == FumeCheckState.open) c
    ];
