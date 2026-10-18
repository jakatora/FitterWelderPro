/// Lista kontrolna przed podniesieniem: kryteria odrzucenia zawiesia
/// (EN 1492-1/-2, EN 818-6, EN 13414-2 — wg DGUV 209-021, instrukcji RUD
/// i Dolezych) oraz przygotowanie miejsca (krawędzie, środek ciężkości,
/// strefa pod ładunkiem).
///
/// Zasady:
///   • pozycja NIEZAZNACZONA ≠ OK — lista jest kompletna dopiero, gdy każda
///     pozycja ma ocenę;
///   • „wada” przy zawiesiu → zawiesie do wycofania (STOP); przy miejscu →
///     nie podnosić, dopóki nie usunięto (STOP);
///   • „nie dotyczy” tylko tam, gdzie pozycja na to pozwala;
///   • etykieta to ten sam stan co w kalkulatorze ([LabelState]) — jedno
///     źródło prawdy.
///
/// Lista NIE jest zapisywana — przed każdym podniesieniem od nowa.
///
/// Czysty Dart.
library;

import 'rigging_calc.dart';

enum RiggingCheckGroup {
  sling('Zawiesie', 'Sling'),
  fittings('Okucia i temperatura', 'Fittings and temperature'),
  site('Miejsce i podniesienie', 'Site and lift');

  const RiggingCheckGroup(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

/// Ocena pozycji.
enum CheckMark { ok, defect, na }

class RiggingCheck {
  final String id;
  final RiggingCheckGroup group;
  final String pl;
  final String en;

  /// Krótkie odwołanie do źródła pod pozycją.
  final String source;

  /// `null` — dotyczy każdego rodzaju zawiesia.
  final Set<SlingType>? onlyFor;

  /// Wolno oznaczyć „nie dotyczy”.
  final bool naAllowed;

  const RiggingCheck(
    this.id,
    this.group,
    this.pl,
    this.en, {
    required this.source,
    this.onlyFor,
    this.naAllowed = false,
  });

  String label({required bool en}) => en ? this.en : pl;
  bool appliesTo(SlingType s) => onlyFor == null || onlyFor!.contains(s);
}

/// Pozycja „etykieta” — jej stan to [LabelState] z kalkulatora.
const String kRiggingLabelCheckId = 'label';

const Set<SlingType> _textile = {SlingType.webbing, SlingType.roundsling};

const String _srcEn1492 = 'EN 1492-1/-2 (instrukcja Dolezych BA-001)';
const String _srcEn818 = 'EN 818-6 (DGUV 209-021, instrukcja RUD)';
const String _srcEn13414 = 'EN 13414-2 (DGUV 209-021)';

/// Wszystkie pozycje w kolejności wyświetlania.
const List<RiggingCheck> kRiggingChecks = [
  // ── Zawiesie ─────────────────────────────────────────────────────────────
  RiggingCheck(
    kRiggingLabelCheckId,
    RiggingCheckGroup.sling,
    'Etykieta (pas) albo zawieszka (łańcuch, lina) jest i jest czytelna: '
        'WLL, materiał, długość, producent, norma',
    'The label (webbing) or tag (chain, rope) is present and legible: WLL, '
        'material, length, maker, standard',
    source: 'EN 1492-1/-2, EN 818-6, EN 13414-2; DGUV 209-021',
  ),
  RiggingCheck(
    'tx-cuts',
    RiggingCheckGroup.sling,
    'Taśma bez nacięć, przetarć i pękniętej przędzy na brzegach i na '
        'powierzchni (przy wątpliwości — odrzuć)',
    'Webbing free of cuts, abrasion and broken yarns on the edges and the '
        'surface (if in doubt — reject)',
    source: _srcEn1492,
    onlyFor: _textile,
  ),
  RiggingCheck(
    'tx-seams',
    RiggingCheckGroup.sling,
    'Szwy nośne i pętle bez uszkodzeń; pas okrągły — osłona cała, rdzeń '
        'niewidoczny',
    'Load-bearing stitching and eyes undamaged; roundsling — cover intact, '
        'core not visible',
    source: _srcEn1492,
    onlyFor: _textile,
  ),
  RiggingCheck(
    'tx-heat',
    RiggingCheckGroup.sling,
    'Bez śladów ciepła i tarcia (stopione, zeszklone, stwardniałe włókna) '
        'ani odprysków spawalniczych',
    'No heat or friction damage (melted, glazed, hardened fibres) and no '
        'weld spatter burns',
    source: _srcEn1492,
    onlyFor: _textile,
  ),
  RiggingCheck(
    'tx-chem',
    RiggingCheckGroup.sling,
    'Bez śladów chemikaliów (przebarwienia, kruche albo rozsypujące się '
        'włókna)',
    'No chemical attack (discolouration, brittle or powdering fibres)',
    source: _srcEn1492,
    onlyFor: _textile,
  ),
  RiggingCheck(
    'tx-knot',
    RiggingCheckGroup.sling,
    'Pas nie jest zawiązany na węzeł, skręcony ani przedłużony przez '
        'łączenie pasów',
    'The sling is not knotted, twisted or lengthened by joining slings',
    source: _srcEn1492,
    onlyFor: _textile,
  ),
  RiggingCheck(
    'ch-stretch',
    RiggingCheckGroup.sling,
    'Łańcuch niewydłużony: ani ogniwo, ani cały łańcuch nie wydłużył się '
        'o 5 % lub więcej',
    'Chain not stretched: no link and not the whole chain elongated by 5 % '
        'or more',
    source: _srcEn818,
    onlyFor: {SlingType.chain},
  ),
  RiggingCheck(
    'ch-wear',
    RiggingCheckGroup.sling,
    'Zużycie ogniw najwyżej 10 % grubości nominalnej (suwmiarka, łańcuch '
        'luźny)',
    'Link wear at most 10 % of the nominal size (calliper, chain slack)',
    source: _srcEn818,
    onlyFor: {SlingType.chain},
  ),
  RiggingCheck(
    'ch-damage',
    RiggingCheckGroup.sling,
    'Ogniwa bez nacięć, karbów, pęknięć, nadmiernej korozji i przebarwień '
        'od ciepła; nie zgięte ani skręcone',
    'Links free of cuts, nicks, cracks, heavy corrosion and heat '
        'discolouration; not bent or twisted',
    source: _srcEn818,
    onlyFor: {SlingType.chain},
  ),
  RiggingCheck(
    'wr-wires',
    RiggingCheckGroup.sling,
    'Pęknięte druty poniżej granicy: lina splotkowa — mniej niż 6 na '
        'długości 6d i mniej niż 14 na 30d (d — średnica liny); żadna '
        'splotka nie pękła',
    'Broken wires below the limit: stranded rope — fewer than 6 over 6d and '
        'fewer than 14 over 30d (d — rope diameter); no broken strand',
    source: _srcEn13414,
    onlyFor: {SlingType.wireRope},
  ),
  RiggingCheck(
    'wr-deform',
    RiggingCheckGroup.sling,
    'Lina bez załamań (kinków), koszyczków, zgnieceń i wypchniętego rdzenia',
    'Rope free of kinks, birdcaging, crushing and protruding core',
    source: _srcEn13414,
    onlyFor: {SlingType.wireRope},
  ),
  RiggingCheck(
    'wr-corr',
    RiggingCheckGroup.sling,
    'Bez wżerów korozyjnych i śladów przegrzania',
    'No corrosion pitting and no signs of overheating',
    source: _srcEn13414,
    onlyFor: {SlingType.wireRope},
  ),
  RiggingCheck(
    'wr-ends',
    RiggingCheckGroup.sling,
    'Zakończenia (tuleje zaciskane, oploty, kausze) bez uszkodzeń; przy '
        'oczku nie więcej niż 4 pęknięte druty w zgnieceniu',
    'Terminations (ferrules, splices, thimbles) undamaged; at the eye no '
        'more than 4 broken wires in a crushed area',
    source: _srcEn13414,
    onlyFor: {SlingType.wireRope},
  ),
  // ── Okucia i temperatura ─────────────────────────────────────────────────
  RiggingCheck(
    'fit-hooks',
    RiggingCheckGroup.fittings,
    'Haki, szekle i ogniwa zawieszenia nieodkształcone i bez pęknięć; '
        'rozwarcie gardzieli haka najwyżej +10 %; zapadka zamyka hak',
    'Hooks, shackles and master links not deformed or cracked; hook throat '
        'opening at most +10 %; the latch closes the hook',
    source: 'EN 818-6 (instrukcja RUD); EN 1492-1/-2',
    naAllowed: true,
  ),
  RiggingCheck(
    'fit-temp',
    RiggingCheckGroup.fittings,
    'Temperatura ładunku w zakresie zawiesia: pasy PES/PA do 100 °C, PP do '
        '80 °C; łańcuch kl. 8 powyżej 200 °C — nośność niższa. Świeżo spawany '
        'albo podgrzewany spool — odczekaj',
    'Load temperature within the sling range: PES/PA webbing up to 100 °C, '
        'PP up to 80 °C; grade 8 chain above 200 °C — reduced WLL. A spool '
        'just welded or preheated — wait',
    source: 'DGUV 209-021; instrukcja Dolezych BA-001',
  ),
  // ── Miejsce i podniesienie ───────────────────────────────────────────────
  RiggingCheck(
    'site-edges',
    RiggingCheckGroup.site,
    'Ostre krawędzie (krawędź rury, kołnierz, faza, narożnik zbiornika) '
        'zabezpieczone ochraniaczem — krawędź jest ostra, gdy jej promień '
        'jest mniejszy niż grubość pasa albo średnica ogniwa / liny',
    'Sharp edges (pipe end, flange, bevel, tank corner) protected — an edge '
        'is sharp when its radius is smaller than the sling thickness or the '
        'link / rope diameter',
    source: 'DGUV 209-021; instrukcja Dolezych BA-001',
    naAllowed: true,
  ),
  RiggingCheck(
    'site-cog',
    RiggingCheckGroup.site,
    'Hak nad środkiem ciężkości, punkty zaczepienia powyżej niego; ładunek '
        'nie przechyli się ani nie wysunie z pętli',
    'Hook above the centre of gravity, attachment points above it; the '
        'load will not tilt or slip out of the hitch',
    source: 'instrukcja Dolezych BA-001',
  ),
  RiggingCheck(
    'site-crane',
    RiggingCheckGroup.site,
    'Udźwig suwnicy / dźwigu przy tym wysięgu nie mniejszy niż masa ładunku '
        'z zawiesiem i osprzętem',
    'Crane / hoist capacity at this radius not less than the load plus '
        'slings and accessories',
    source: 'praktyka (przyjęte w aplikacji)',
  ),
  RiggingCheck(
    'site-legs',
    RiggingCheckGroup.site,
    'Nieużywane cięgna zawiesia wielocięgnowego zawieszone na ogniwie — nie '
        'zwisają i nie zaczepią',
    'Unused legs of a multi-leg sling hooked back to the master link — not '
        'dangling, will not snag',
    source: 'LEEA COPSULE 14.5.2; instrukcja Dolezych BA-001',
    naAllowed: true,
  ),
  RiggingCheck(
    'site-zone',
    RiggingCheckGroup.site,
    'Strefa pod ładunkiem i na drodze przenoszenia wolna, nikt nie stoi pod '
        'ładunkiem; przy długim spoolu — lina prowadząca',
    'The area under the load and along its path clear, nobody under the '
        'load; long spool — tag line',
    source: 'instrukcja Dolezych BA-001',
  ),
  RiggingCheck(
    'site-signals',
    RiggingCheckGroup.site,
    'Jeden sygnalista, sygnały uzgodnione z operatorem',
    'One signaller, signals agreed with the operator',
    source: 'instrukcja Dolezych BA-001',
  ),
  RiggingCheck(
    'site-trial',
    RiggingCheckGroup.site,
    'Próbne uniesienie o kilka centymetrów: ładunek w poziomie, cięgna równo '
        'napięte, nic nie zaczepione',
    'Trial lift of a few centimetres: load level, legs evenly tensioned, '
        'nothing snagged',
    source: 'instrukcja Dolezych BA-001',
  ),
];

/// Pozycje dla rodzaju zawiesia, w kolejności wyświetlania.
List<RiggingCheck> riggingChecksFor(SlingType sling) => [
      for (final c in kRiggingChecks)
        if (c.appliesTo(sling)) c
    ];

enum ChecklistVerdict {
  /// Każda pozycja oceniona, bez wad.
  complete,

  /// Są pozycje bez oceny (≠ OK).
  incomplete,

  /// Co najmniej jedna wada — STOP.
  rejected,
}

class ChecklistStatus {
  final int total;
  final int okCount;
  final int naCount;
  final int uncheckedCount;

  /// Pozycje z wadą (id).
  final List<String> defects;

  const ChecklistStatus({
    required this.total,
    required this.okCount,
    required this.naCount,
    required this.uncheckedCount,
    required this.defects,
  });

  ChecklistVerdict get verdict {
    if (defects.isNotEmpty) return ChecklistVerdict.rejected;
    if (uncheckedCount > 0) return ChecklistVerdict.incomplete;
    return ChecklistVerdict.complete;
  }

  /// Wada dotyczy samego zawiesia (do wycofania), a nie miejsca.
  bool get slingRejected => defects.any((id) =>
      kRiggingChecks.firstWhere((c) => c.id == id).group !=
      RiggingCheckGroup.site);
}

/// Ocena pozycji z uwzględnieniem stanu etykiety. „Nie dotyczy” przy
/// pozycji, która na to nie pozwala, liczy się jak brak oceny.
CheckMark? effectiveMark(
  RiggingCheck check,
  Map<String, CheckMark> marks,
  LabelState label,
) {
  if (check.id == kRiggingLabelCheckId) {
    return switch (label) {
      LabelState.readable => CheckMark.ok,
      LabelState.missing => CheckMark.defect,
      LabelState.unknown => null,
    };
  }
  final m = marks[check.id];
  if (m == CheckMark.na && !check.naAllowed) return null;
  return m;
}

ChecklistStatus evaluateChecklist(
  SlingType sling,
  Map<String, CheckMark> marks,
  LabelState label,
) {
  final checks = riggingChecksFor(sling);
  var ok = 0, na = 0, unchecked = 0;
  final defects = <String>[];
  for (final c in checks) {
    switch (effectiveMark(c, marks, label)) {
      case CheckMark.ok:
        ok++;
      case CheckMark.na:
        na++;
      case CheckMark.defect:
        defects.add(c.id);
      case null:
        unchecked++;
    }
  }
  return ChecklistStatus(
    total: checks.length,
    okCount: ok,
    naCount: na,
    uncheckedCount: unchecked,
    defects: List.unmodifiable(defects),
  );
}

/// Gotowość do podniesienia — kalkulator i lista razem.
enum LiftReadiness {
  /// Nośność OK i lista kompletna bez wad.
  go,

  /// STOP z kalkulatora albo wada na liście.
  stop,

  /// Brak werdyktu albo lista niekompletna.
  notReady,
}

LiftReadiness liftReadiness(RiggingResult calc, ChecklistStatus list) {
  if (calc.verdict.isStop || list.verdict == ChecklistVerdict.rejected) {
    return LiftReadiness.stop;
  }
  if (calc.verdict == RiggingVerdict.ok &&
      list.verdict == ChecklistVerdict.complete) {
    return LiftReadiness.go;
  }
  return LiftReadiness.notReady;
}
