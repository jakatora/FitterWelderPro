/// Lista kontrolna przed pracą szlifierką kątową — jako dane (PL/EN).
///
/// MODUŁ BEZPIECZEŃSTWA. Zasada: punkt niezaznaczony ≠ OK — lista jest
/// „gotowa” dopiero, gdy zaznaczono WSZYSTKIE punkty. Każdy punkt ma
/// źródło (pełne opisy: grinding_sources.dart) albo jest oznaczony jako
/// reguła przyjęta w aplikacji.
///
/// Bieg próbny: ostrzeżenia EN 62841-2-3 (w instrukcjach Bosch, Makita)
/// mówią o 1 MINUCIE na maks. obrotach bez obciążenia. Wartości „30 s”
/// (przypisywanej oSa) nie udało się potwierdzić — aplikacja podaje 1 min.
///
/// Identyfikatory punktów są trwałe (testy, ewentualny zapis) — nie zmieniaj.
///
/// Czysty Dart.
library;

import 'grinding_sources.dart';

class GrindingCheck {
  /// Trwały identyfikator — nie zmieniać.
  final String id;
  final String pl;
  final String en;

  /// Krótkie odwołanie do źródła (albo `null`).
  final String? source;

  /// Reguła przyjęta w aplikacji (dobra praktyka, nie norma).
  final bool appRule;

  const GrindingCheck(
    this.id,
    this.pl,
    this.en, {
    this.source,
    this.appRule = false,
  });

  String label({required bool en}) => en ? this.en : pl;

  String? sourceLabel({required bool en}) =>
      appRule ? (en ? kSrcAppEn : kSrcApp) : source;
}

/// Czas biegu próbnego po założeniu tarczy [min] — EN 62841-2-3
/// (ostrzeżenia w instrukcjach szlifierek).
const int kTestRunMinutes = 1;

const List<GrindingCheck> kGrindingChecks = [
  // „The guard must be securely attached to the power tool and positioned
  // for maximum safety, so the least amount of wheel is exposed towards
  // the operator” — ostrzeżenia EN 62841-2-3.
  GrindingCheck(
    'guard',
    'Osłona założona, zablokowana i ustawiona tak, by od strony operatora '
        'odsłonięta była jak najmniejsza część tarczy; do cięcia — osłona '
        'do cięcia',
    'Guard fitted, locked and set so the least of the wheel is exposed '
        'towards the operator; for cutting — the cutting guard',
    source: kSrcEn62841,
  ),
  // „Always use auxiliary handle, if provided”.
  GrindingCheck(
    'handle',
    'Rękojeść dodatkowa przykręcona; szlifierka trzymana oburącz',
    'Auxiliary handle fitted; grinder held with both hands',
    source: kSrcEn62841,
  ),
  // „Always use undamaged wheel flanges that are of correct size and shape
  // for your selected wheel. Flanges for cut-off wheels may be different”.
  GrindingCheck(
    'flanges',
    'Kołnierze właściwe dla tej tarczy (do tarcz tnących mogą być inne), '
        'nieuszkodzone i czyste; nakrętka dokręcona kluczem',
    'Flanges correct for this wheel (cut-off wheels may need different '
        'ones), undamaged and clean; nut tightened with the spanner',
    source: kSrcEn62841,
  ),
  // „Before each use inspect the accessory … for chips and cracks” (EN
  // 62841-2-3); oSa FAQ: wilgoć obniża wytrzymałość tarcz żywicznych.
  GrindingCheck(
    'inspect',
    'Tarcza obejrzana: bez pęknięć i wyszczerbień, nieupuszczona, '
        'niezawilgocona (przechowywana w suchym miejscu)',
    'Disc inspected: no cracks or chips, not dropped, not damp (stored '
        'dry)',
    source: '$kSrcEn62841; $kSrcOsaStorage',
  ),
  // „run the power tool at maximum no-load speed for one minute”.
  GrindingCheck(
    'test-run',
    'Bieg próbny po założeniu tarczy: $kTestRunMinutes min na maks. '
        'obrotach bez obciążenia — ty i inni poza płaszczyzną tarczy',
    'Test run after fitting the disc: $kTestRunMinutes min at max no-load '
        'speed — you and others out of the plane of the disc',
    source: kSrcEn62841,
  ),
  // „Keep bystanders a safe distance away from work area”.
  GrindingCheck(
    'bystanders',
    'Osoby postronne poza strefą pracy — odłamki lecą w płaszczyźnie tarczy',
    'Bystanders kept away — fragments fly in the plane of the disc',
    source: kSrcEn62841,
  ),
  // „Depending on application, use face shield, safety goggles or safety
  // glasses. As appropriate, wear dust mask, hearing protectors, gloves…”
  // (EN 62841-2-3); EN 12413 tab. A.3 — znaki ŚOI: oczy, słuch, ręce,
  // drogi oddechowe.
  GrindingCheck(
    'ppe',
    'Okulary ochronne albo przyłbica, ochronniki słuchu, rękawice; przy '
        'pyle — maska',
    'Safety glasses or face shield, hearing protection, gloves; dust mask '
        'when dusty',
    source: '$kSrcEn62841; EN 12413 tab. A.3',
  ),
  // „Do not operate the power tool near flammable materials. Sparks could
  // ignite these materials.”
  GrindingCheck(
    'sparks',
    'Iskry nie lecą na materiały palne, ludzi, butle ani węże gazowe; '
        'w strefie zagrożonej pożarem — zezwolenie (moduł „Prace pożarowo '
        'niebezpieczne”)',
    'Sparks not directed at combustibles, people, cylinders or gas hoses; '
        'in a fire-risk area — a permit (see the “Hot work permit” module)',
    source: kSrcEn62841,
  ),
  // „Support panels or any oversized workpiece to minimize the risk of
  // wheel pinching and kickback.”
  GrindingCheck(
    'workpiece',
    'Przedmiot zamocowany; przy cięciu podparty tak, by tarcza nie '
        'zakleszczyła się w rzazie',
    'Workpiece clamped; when cutting, supported so the wheel cannot pinch '
        'in the cut',
    source: kSrcEn62841,
  ),
  // Instrukcje Bosch: po zaniku zasilania przestaw włącznik na „wyłączony”.
  // Blokada włącznika w pozycji „włączony” — dobra praktyka (bez źródła).
  GrindingCheck(
    'switch',
    'Włącznik sprawny, NIE zablokowany w pozycji „włączony”; po zaniku '
        'zasilania przestaw go na „wyłączony”',
    'Switch works and is NOT locked on; after a power cut set it to off',
    appRule: true,
  ),
];

final Map<String, GrindingCheck> _byId = {
  for (final c in kGrindingChecks) c.id: c,
};

GrindingCheck? grindingCheckById(String id) => _byId[id];

/// Stan listy: zaznaczone / wszystkie i czego brakuje.
class GrindingChecklistStatus {
  final int checked;
  final int total;
  final List<GrindingCheck> missing;

  const GrindingChecklistStatus(this.checked, this.total, this.missing);

  /// Gotowe dopiero, gdy zaznaczono WSZYSTKIE punkty.
  bool get complete => total > 0 && missing.isEmpty;
}

/// Ocena listy. Nieznane identyfikatory (np. z innej wersji) są ignorowane
/// — nie mogą „dopełnić” listy.
GrindingChecklistStatus evaluateChecklist(Set<String> checkedIds) {
  final missing = [
    for (final c in kGrindingChecks)
      if (!checkedIds.contains(c.id)) c,
  ];
  return GrindingChecklistStatus(
    kGrindingChecks.length - missing.length,
    kGrindingChecks.length,
    List.unmodifiable(missing),
  );
}
