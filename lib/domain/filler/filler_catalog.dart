// Dobór spoiwa — katalog: materiały rodzime, gazy, spoiwa. Czysty Dart, bez
// Fluttera (testy tabelaryczne w test/domain/filler/).
//
// CO TU JEST: TYPOWY dobór spoiwa do pary materiałów, taki jak podają karty
// producentów spoiw i poradniki. Wiążące spoiwo, gaz, podgrzewanie i PWHT
// podaje WPS / specyfikacja projektu — aplikacja nie zastępuje technologa.
//
// ŹRÓDŁA OZNACZEŃ — normy klasyfikacji spoiw (strona ISO / strona AWS):
//   EN ISO 636-A    pręty TIG do stali niestopowych i drobnoziarnistych
//                   (W3Si1, W3Ni1)                       ↔ AWS A5.18 / A5.28
//   EN ISO 14341-A  druty MIG/MAG, j.w. (G3Si1, G3Ni1)   ↔ AWS A5.18 / A5.28
//   EN ISO 2560-A   elektrody otulone, j.w. (E 42 x B, E 38 x C 21,
//                   E 46 x 1Ni B)                         ↔ AWS A5.1 / A5.5
//   EN ISO 17632-A  druty proszkowe, j.w. (T 46 x P M21, T 46 x 1Ni P M21)
//                                                         ↔ AWS A5.20 / A5.29
//                   (AWS A5.36 zastępuje A5.20 i A5.29 klasyfikacją otwartą;
//                   na opakowaniach nadal najczęściej E71T-1M / E81T1-Ni1M)
//   EN ISO 21952-A  druty i pręty do stali odpornych na pełzanie
//                   (W/G MoSi, CrMo1Si, CrMo2Si, CrMo91)   ↔ AWS A5.28
//   EN ISO 3580-A   elektrody otulone, j.w. (E Mo B, E CrMo1 B, E CrMo2 B,
//                   E CrMo91 B)                           ↔ AWS A5.5
//   EN ISO 14343-A  druty i pręty do stali nierdzewnych (W/G 19 9 L,
//                   19 12 3 L, 19 9 Nb, 23 12 L, 23 12 2 L, 22 9 3 N L,
//                   25 9 4 N L)                           ↔ AWS A5.9
//   EN ISO 3581-A   elektrody otulone do stali nierdzewnych (E … R)
//                                                         ↔ AWS A5.4
//   EN ISO 17633-A  druty proszkowe do stali nierdzewnych (T … P)
//                                                         ↔ AWS A5.22
//   EN ISO 18273    druty i pręty do aluminium (S Al 5183, 4043, 5356)
//                                                         ↔ AWS A5.10
//   EN ISO 18274    druty niklowe (S Ni 6082, S Ni 4060)   ↔ AWS A5.14
//   EN ISO 14172    elektrody niklowe (E Ni 6182, E Ni 4060) ↔ AWS A5.11
//   EN ISO 24373    druty miedziane (S Cu 7158)            ↔ AWS A5.7
//
// Pary ISO ↔ AWS sprawdzone 2026-10 na kartach producentów (ESAB, Böhler,
// Lincoln Electric, Gedik, Certilas, Magmaweld, Metrode). Oznaczenie
// AWS A5.28 / A5.5 dla P91 zmieniono z B9 na B91 (A5.5:2014, nowsze A5.28) —
// podajemy oba, bo na magazynach leżą oba.
//
// „x” w oznaczeniu (E 42 x B, T 46 x P M21) to symbol udarności — zależy od
// konkretnego produktu, czytaj z karty. Druty i pręty lite podajemy symbolem
// składu chemicznego (G3Si1, W 19 9 L), który normy dopuszczają jako
// oznaczenie samego drutu.
//
// Gazy: EN ISO 14175:2008, tab. 3 (zestawienie Linde „Die neue ISO
// 14175:2008”). Dupleks: IMOA „Practical guidelines for the fabrication of
// duplex stainless steels”, 3. wyd. — §12.1.6 (energia liniowa,
// międzyściegowa), §12.1.9 tab. 16 (połączenia różnoimienne), §12.3 (gazy:
// bez wodoru, do 3 % N₂ w osłonie TIG).
//
// POMINIĘTE z braku pewnego źródła (lepiej mniej, ale prawdziwie): drut
// proszkowy do 347, 309LMo, 2594, 16Mo3, Cr-Mo, CuNi i spoiw niklowych;
// elektroda ECuNi (AWS A5.6) — brak pewnego odpowiednika EN ISO; MMA do
// aluminium. Takie procesy zwracają „brak typowego doboru — wg WPS”.

/// Tekst w dwóch językach — domena nie zna Fluttera ani `context.tr`.
class FillerText {
  final String pl;
  final String en;
  const FillerText(this.pl, this.en);

  String of({required bool english}) => english ? en : pl;
}

/// Proces spawania wg EN ISO 4063, w którym spawacz wybiera spoiwo.
enum FillerProcess {
  /// 141 — TIG.
  tig('TIG', '141'),

  /// 131 / 135 — MIG / MAG drutem litym.
  mig('MIG/MAG', '131/135'),

  /// 111 — elektroda otulona.
  mma('MMA', '111'),

  /// 136 — drut proszkowy w osłonie gazu.
  fcaw('FCAW', '136');

  const FillerProcess(this.name3, this.iso4063);

  final String name3;
  final String iso4063;

  /// „TIG (141)”.
  String get label => '$name3 ($iso4063)';

  /// Proces z gazem osłonowym (MMA — otulina, bez butli).
  bool get usesShieldingGas => this != FillerProcess.mma;
}

/// Symbol gazu wg EN ISO 14175:2008 (tab. 3). Tylko te, które dobór używa.
enum GasSymbol {
  i1('I1', FillerText('Ar 100 %', 'Ar 100 %')),
  i3('I3', FillerText('Ar + He (He 0,5–95 %)', 'Ar + He (He 0.5–95 %)')),
  m12('M12', FillerText('Ar + CO₂ 0,5–5 %', 'Ar + CO₂ 0.5–5 %')),
  m13('M13', FillerText('Ar + O₂ 0,5–3 %', 'Ar + O₂ 0.5–3 %')),
  m21('M21', FillerText('Ar + CO₂ 15–25 %', 'Ar + CO₂ 15–25 %')),
  c1('C1', FillerText('CO₂ 100 %', 'CO₂ 100 %')),
  n1('N1', FillerText('N₂ 100 %', 'N₂ 100 %')),
  n2('N2', FillerText('Ar + N₂ 0,5–5 %', 'Ar + N₂ 0.5–5 %')),
  n5(
      'N5',
      FillerText('N₂ + H₂ 0,5–50 % (formier, np. 90/10)',
          'N₂ + H₂ 0.5–50 % (forming gas, e.g. 90/10)'));

  const GasSymbol(this.code, this.description);

  final String code;
  final FillerText description;

  /// Gaz z wodorem — zakazany przy dupleksie i stalach ferrytycznych.
  bool get containsHydrogen => this == GasSymbol.n5;
}

/// Czy grań trzeba formować (gaz od strony grani, spoina jednostronna).
enum BackingNeed { notNeeded, recommended, required }

/// Grupa materiałowa — porządek listy wyboru.
enum MaterialGroup {
  carbon(FillerText('Stale węglowe i niskostopowe', 'Carbon and low-alloy steels')),
  creep(FillerText('Stale Mo i Cr-Mo (żarowytrzymałe)', 'Mo and Cr-Mo steels (creep resisting)')),
  austenitic(FillerText('Nierdzewne austenityczne', 'Austenitic stainless')),
  duplex(FillerText('Dupleks', 'Duplex')),
  aluminium(FillerText('Aluminium', 'Aluminium')),
  copperNickel(FillerText('Miedzionikiel', 'Copper-nickel'));

  const MaterialGroup(this.title);
  final FillerText title;
}

/// Materiał rodzimy po jednej stronie złącza.
///
/// [ferriticRank] porządkuje stale ferrytyczne wg stopowania (połączenie
/// różnoimienne dwóch stali ferrytycznych dostaje spoiwo słabiej stopowanej);
/// `null` dla nierdzewnych, aluminium i miedzioniklu.
enum BaseMaterial {
  carbonSteel(
    group: MaterialGroup.carbon,
    label: FillerText('Stal węglowa C-Mn', 'C-Mn carbon steel'),
    grades: 'S235–S355, P235GH, P265GH, L245–L360, A106 B',
    ferriticRank: 0,
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wCarbonGrades, _wLowHydrogen],
    seeAlso: [kSeeHeatInput],
  ),
  lowTempSteel(
    group: MaterialGroup.carbon,
    label: FillerText('Stal niskotemperaturowa', 'Low-temperature steel'),
    grades: 'P355NL1, P275NL1, A333 Gr 6, A350 LF2',
    ferriticRank: 0,
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wLowTempImpact, _wLowTemp7018, _wLowHydrogen],
    seeAlso: [kSeeHeatInput],
  ),
  mo05(
    group: MaterialGroup.creep,
    label: FillerText('Stal 0,5 Mo', '0.5 Mo steel'),
    grades: '16Mo3, A335 P1',
    ferriticRank: 1,
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wMoPreheat, _wLowHydrogen],
    seeAlso: [kSeeHeatInput],
  ),
  crMo1(
    group: MaterialGroup.creep,
    label: FillerText('Stal 1–1,25 Cr 0,5 Mo', '1–1.25 Cr 0.5 Mo steel'),
    grades: 'P11, P12, 13CrMo4-5',
    ferriticRank: 2,
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wCrMoPreheat, _wCrMoPwht, _wLowHydrogen],
    seeAlso: [kSeeHeatInput],
  ),
  crMo2(
    group: MaterialGroup.creep,
    label: FillerText('Stal 2,25 Cr 1 Mo', '2.25 Cr 1 Mo steel'),
    grades: 'P22, 10CrMo9-10',
    ferriticRank: 3,
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1],
    warnings: [_wCrMoPreheat, _wCrMoPwht, _wLowHydrogen],
    seeAlso: [kSeeHeatInput, kSeePurge],
  ),
  p91(
    group: MaterialGroup.creep,
    label: FillerText('Stal 9 Cr 1 Mo V (P91)', '9 Cr 1 Mo V steel (P91)'),
    grades: 'P91, T91, X10CrMoVNb9-1',
    ferriticRank: 4,
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1],
    warnings: [_wP91Pwht, _wP91Preheat, _wP91Filler, _wLowHydrogen],
    seeAlso: [kSeeHeatInput, kSeePurge],
  ),
  ss304L(
    group: MaterialGroup.austenitic,
    label: FillerText('Nierdzewna 304L / 304', 'Stainless 304L / 304'),
    grades: '1.4307, 1.4301',
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1, GasSymbol.n5],
    warnings: [_wStainlessHeat, _wStainlessTools],
    seeAlso: [kSeePurge, kSeeHeatTint, kSeePassivation],
  ),
  ss316L(
    group: MaterialGroup.austenitic,
    label: FillerText('Nierdzewna 316L / 316', 'Stainless 316L / 316'),
    grades: '1.4404, 1.4401',
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1, GasSymbol.n5],
    warnings: [_wStainlessHeat, _wStainlessTools],
    seeAlso: [kSeePurge, kSeeHeatTint, kSeePassivation],
  ),
  ss321(
    group: MaterialGroup.austenitic,
    label: FillerText('Nierdzewna 321', 'Stainless 321'),
    grades: '1.4541',
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1, GasSymbol.n5],
    warnings: [_wStainlessHeat, _wStainlessTools],
    seeAlso: [kSeePurge, kSeeHeatTint, kSeePassivation],
  ),
  duplex2205(
    group: MaterialGroup.duplex,
    label: FillerText('Dupleks 2205', 'Duplex 2205'),
    grades: '1.4462, S31803, S32205',
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1, GasSymbol.n1, GasSymbol.n2],
    warnings: [
      _wDuplexHeat,
      _wDuplexNoHydrogen,
      _wDuplexNoAutogenous,
      _wDuplexNoPwht
    ],
    seeAlso: [kSeeHeatInput, kSeePurge, kSeeHeatTint],
  ),
  superDuplex2507(
    group: MaterialGroup.duplex,
    label: FillerText('Super dupleks 2507', 'Super duplex 2507'),
    grades: '1.4410, S32750',
    backing: BackingNeed.required,
    backingGases: [GasSymbol.i1, GasSymbol.n1, GasSymbol.n2],
    warnings: [
      _wSuperDuplexHeat,
      _wDuplexNoHydrogen,
      _wDuplexNoAutogenous,
      _wDuplexNoPwht
    ],
    seeAlso: [kSeeHeatInput, kSeePurge, kSeeHeatTint],
  ),
  al5083(
    group: MaterialGroup.aluminium,
    label: FillerText('Aluminium 5083', 'Aluminium 5083'),
    grades: 'AlMg4,5Mn0,7 (EN AW-5083)',
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wAlOxide, _wAlMgTemperature],
  ),
  al6xxx(
    group: MaterialGroup.aluminium,
    label: FillerText('Aluminium 6061 / 6082', 'Aluminium 6061 / 6082'),
    grades: 'AlMgSi (EN AW-6082, 6061)',
    backing: BackingNeed.notNeeded,
    backingGases: [GasSymbol.i1],
    warnings: [_wAlOxide, _wAl6xxxCracking, _wAl6xxxHaz],
  ),
  cuNi9010(
    group: MaterialGroup.copperNickel,
    label: FillerText('Miedzionikiel CuNi 90/10', 'Copper-nickel CuNi 90/10'),
    grades: 'CuNi10Fe1Mn (CW352H), C70600',
    backing: BackingNeed.recommended,
    backingGases: [GasSymbol.i1],
    warnings: [_wCuNiHeat, _wCuNiContamination],
    seeAlso: [kSeePurge],
  );

  const BaseMaterial({
    required this.group,
    required this.label,
    required this.grades,
    this.ferriticRank,
    required this.backing,
    required this.backingGases,
    this.warnings = const [],
    this.seeAlso = const [],
  });

  final MaterialGroup group;

  /// Nazwa materiału (pole nie nazywa się `name`, bo zasłoniłoby
  /// `Enum.name` — identyfikator używany w kluczach widżetów).
  final FillerText label;

  /// Gatunki, po których spawacz rozpozna materiał (z atestu, rysunku).
  final String grades;
  final int? ferriticRank;
  final BackingNeed backing;

  /// Gazy formujące dopuszczalne od strony grani dla tego materiału. Dla
  /// pary bierzemy część wspólną — dlatego stal ferrytyczna ma tylko Ar:
  /// formier z wodorem na stali ferrytycznej / martenzytycznej to ryzyko
  /// pęknięć wodorowych.
  final List<GasSymbol> backingGases;
  final List<FillerText> warnings;
  final List<FillerText> seeAlso;

  bool get isFerritic => ferriticRank != null;
  bool get isAustenitic => group == MaterialGroup.austenitic;
  bool get isDuplex => group == MaterialGroup.duplex;
  bool get isAluminium => group == MaterialGroup.aluminium;
  bool get isCopperNickel => group == MaterialGroup.copperNickel;

  /// Stal Cr-Mo (P11/P12, P22, P91) — pracuje zwykle w wysokiej temperaturze
  /// i wymaga PWHT.
  bool get isCrMo => (ferriticRank ?? 0) >= 2;
}

/// Jedno spoiwo: oznaczenie wg EN ISO i jego odpowiednik AWS.
class Consumable {
  final String isoStandard;
  final String isoDesignation;
  final String awsStandard;
  final String awsDesignation;

  /// Do czego (np. „grań pipeline”) albo opis kompromisu; `null` gdy jedno
  /// spoiwo bez dopisku.
  final FillerText? use;

  const Consumable({
    required this.isoStandard,
    required this.isoDesignation,
    required this.awsStandard,
    required this.awsDesignation,
    this.use,
  });
}

/// Spoiwo i gaz osłonowy dla jednego procesu.
class ProcessFiller {
  final List<Consumable> consumables;

  /// Gaz osłonowy wg EN ISO 14175; pusty dla MMA.
  final List<GasSymbol> shielding;
  final FillerText? note;

  const ProcessFiller({
    required this.consumables,
    this.shielding = const [],
    this.note,
  });
}

/// Rodzina spoiwa (np. „309L”) z odmianami dla procesów.
class FillerFamily {
  final String id;
  final FillerText name;

  /// Procesy, dla których mamy pewne oznaczenia. Brak klucza = brak
  /// typowego doboru w aplikacji (wg WPS).
  final Map<FillerProcess, ProcessFiller> processes;

  /// Uwagi dotyczące samego spoiwa.
  final List<FillerText> notes;

  const FillerFamily({
    required this.id,
    required this.name,
    required this.processes,
    this.notes = const [],
  });
}

// ── Odesłania do innych narzędzi (tylko tekst, bez nawigacji) ──────────────

const kSeeHeatInput = FillerText(
    '„Heat input i CE” — podgrzewanie z chemii stali i energia liniowa.',
    '“Heat input and CE” — preheat from steel chemistry and arc energy.');
const kSeePurge = FillerText(
    '„Gaz, formowanie i timer” — czas formowania i zużycie gazu.',
    '“Gas, purge and timer” — purge time and gas consumption.');
const kSeeHeatTint = FillerText(
    '„Przebarwienia” — karta kolorów spoiny nierdzewnej.',
    '“Heat tint” — stainless weld colour chart.');
const kSeePassivation = FillerText(
    '„Trawienie i pasywacja” — obróbka po spawaniu nierdzewki.',
    '“Pickling and passivation” — post-weld treatment of stainless.');

// ── Ostrzeżenia materiałowe ────────────────────────────────────────────────

const _wCarbonGrades = FillerText(
    'Dobór dla stali do S355 / L360 (X52). Wyższe gatunki (np. X60 i więcej) '
        '— spoiwo wyłącznie wg WPS.',
    'Selection for steels up to S355 / L360 (X52). Higher grades (e.g. X60 '
        'and up) — filler per the WPS only.');
const _wLowHydrogen = FillerText(
    'Elektrody zasadowe i druty proszkowe przechowuj i susz wg karty '
        'producenta (niski wodór, H5).',
    'Store and re-dry basic electrodes and flux-cored wires per the data '
        'sheet (low hydrogen, H5).');
const _wLowTempImpact = FillerText(
    'Spoiwo musi mieć udarność potwierdzoną w temperaturze projektowej '
        '(np. A333 Gr 6: −45 °C) — sprawdź kartę spoiwa i WPS. Energię '
        'liniową ogranicz wg WPS.',
    'The filler must have impact toughness proven at the design temperature '
        '(e.g. A333 Gr 6: −45 °C) — check the data sheet and the WPS. Limit '
        'arc energy per the WPS.');
const _wLowTemp7018 = FillerText(
    'Przy −45 °C bywa dopuszczana także elektroda E7018-1 — tylko jeśli WPS '
        'tak stanowi.',
    'At −45 °C an E7018-1 electrode is sometimes accepted too — only if the '
        'WPS says so.');
const _wMoPreheat = FillerText(
    'Podgrzewanie i ewentualne PWHT zależą od grubości i normy — wg WPS.',
    'Preheat and any PWHT depend on thickness and the code — per the WPS.');
const _wCrMoPreheat = FillerText(
    'Podgrzewanie obowiązkowe — wartość i temperatura międzyściegowa z WPS.',
    'Preheat is mandatory — value and interpass temperature from the WPS.');
const _wCrMoPwht = FillerText(
    'PWHT zwykle wymagane powyżej grubości granicznej normy (np. EN 13480, '
        'ASME B31.3) — wg WPS.',
    'PWHT is usually required above the code thickness limit (e.g. EN 13480, '
        'ASME B31.3) — per the WPS.');
const _wP91Pwht = FillerText(
    'P91: PWHT obowiązkowe — temperatura, czas i szybkość nagrzewania '
        'wyłącznie wg WPS.',
    'P91: PWHT is mandatory — temperature, time and heating rate per the WPS '
        'only.');
const _wP91Preheat = FillerText(
    'P91: podgrzewanie (typowo ok. 200 °C lub więcej), temperatura '
        'międzyściegowa i chłodzenie przed PWHT ściśle wg WPS — błąd grozi '
        'pęknięciami.',
    'P91: preheat (typically about 200 °C or more), interpass temperature and '
        'cooling before PWHT strictly per the WPS — mistakes lead to '
        'cracking.');
const _wP91Filler = FillerText(
    'P91: nie zastępuj spoiwa przypadkowym „9Cr” — skład spoiwa (m.in. '
        'Mn + Ni) jest ograniczony ze względu na PWHT.',
    'P91: do not swap in a random “9Cr” filler — the filler chemistry '
        '(incl. Mn + Ni) is restricted because of PWHT.');
const _wStainlessHeat = FillerText(
    'Temperaturę międzyściegową i energię liniową ogranicz wg WPS — nadmiar '
        'ciepła to przebarwienia i utrata odporności korozyjnej.',
    'Limit interpass temperature and arc energy per the WPS — excess heat '
        'means heat tint and lost corrosion resistance.');
const _wStainlessTools = FillerText(
    'Osobne szczotki i tarcze tylko do nierdzewki — bez zanieczyszczenia '
        'żelazem.',
    'Dedicated brushes and discs for stainless only — no iron '
        'contamination.');
const _wDuplexHeat = FillerText(
    'Dupleks 2205: energia liniowa typowo 0,5–2,5 kJ/mm, temperatura '
        'międzyściegowa ≤ 150 °C (IMOA) — wiążą wartości z WPS.',
    'Duplex 2205: arc energy typically 0.5–2.5 kJ/mm, interpass ≤ 150 °C '
        '(IMOA) — the WPS values govern.');
const _wSuperDuplexHeat = FillerText(
    'Super dupleks 2507: energia liniowa typowo 0,3–1,5 kJ/mm, temperatura '
        'międzyściegowa ≤ 100 °C (IMOA) — wiążą wartości z WPS.',
    'Super duplex 2507: arc energy typically 0.3–1.5 kJ/mm, interpass '
        '≤ 100 °C (IMOA) — the WPS values govern.');
const _wDuplexNoHydrogen = FillerText(
    'Dupleks: bez wodoru w gazie osłonowym i formującym (kruchość wodorowa '
        'ferrytu) — żadnego formiera N₂/H₂.',
    'Duplex: no hydrogen in shielding or backing gas (hydrogen embrittlement '
        'of ferrite) — no N₂/H₂ forming gas.');
const _wDuplexNoAutogenous = FillerText(
    'Dupleks: nie spawaj bez spoiwa ani spoiwem o składzie rury bez '
        'nadstopowania niklem — spoina wyjdzie zbyt ferrytyczna.',
    'Duplex: no autogenous welds and no filler matching the pipe without '
        'extra nickel — the weld would be too ferritic.');
const _wDuplexNoPwht = FillerText(
    'Dupleks: bez odprężania (PWHT) — szkodzi przez wydzielenia faz '
        'międzymetalicznych (IMOA).',
    'Duplex: no stress relief (PWHT) — it harms through intermetallic '
        'phases (IMOA).');
const _wAlOxide = FillerText(
    'Usuń tlenek szczotką nierdzewną używaną tylko do aluminium i odtłuść '
        'tuż przed spawaniem. TIG prądem przemiennym (AC).',
    'Remove the oxide with a stainless brush used only on aluminium and '
        'degrease just before welding. TIG on alternating current (AC).');
const _wAlMgTemperature = FillerText(
    'Stopy i spoiwa Al-Mg (5083, 5183, 5356) — nie do pracy stale powyżej '
        'ok. 65 °C (korozja naprężeniowa).',
    'Al-Mg alloys and fillers (5083, 5183, 5356) — not for sustained service '
        'above about 65 °C (stress corrosion).');
const _wAl6xxxCracking = FillerText(
    '6061 / 6082 nie spawaj bez spoiwa — pęka na gorąco; spoiwo zmienia skład '
        'spoiny i usuwa tę skłonność.',
    'Never weld 6061 / 6082 without filler — it hot-cracks; the filler '
        'changes the weld chemistry and removes that tendency.');
const _wAl6xxxHaz = FillerText(
    'Strefa wpływu ciepła traci wytrzymałość stanu T6 — to uwzględnia '
        'projekt, nie spawacz.',
    'The heat-affected zone loses its T6 strength — the design accounts for '
        'it, not the welder.');
const _wCuNiHeat = FillerText(
    'Bez podgrzewania, temperatura międzyściegowa ≤ 150 °C, bez PWHT.',
    'No preheat, interpass ≤ 150 °C, no PWHT.');
const _wCuNiContamination = FillerText(
    'Usuń ślady ołowiu, cyny i cynku (np. z mosiądzu, brązu) — powodują '
        'pęknięcia spoiny.',
    'Remove any lead, tin or zinc (e.g. from brass, bronze) — they crack the '
        'weld.');

// ── Spoiwa: wspólne odmiany procesów ────────────────────────────────────────

const _gasStainlessMig = [GasSymbol.m12, GasSymbol.m13];
const _gasStainlessFcaw = [GasSymbol.c1, GasSymbol.m21];
const _noteStainlessFcaw = FillerText(
    'C1 dla drutów …T1-1, M21 dla …T1-4 (AWS A5.22).',
    'C1 for …T1-1 wires, M21 for …T1-4 (AWS A5.22).');
const _noteFcawIso = FillerText(
    'Pełne oznaczenie EN ISO dodaje gaz i pozycję — z karty drutu.',
    'The full EN ISO designation adds gas and position — from the data '
        'sheet.');

// ── Spoiwa ─────────────────────────────────────────────────────────────────

const _carbonTig = ProcessFiller(
  consumables: [
    Consumable(
        isoStandard: 'EN ISO 636-A',
        isoDesignation: 'W3Si1',
        awsStandard: 'AWS A5.18',
        awsDesignation: 'ER70S-6'),
  ],
  shielding: [GasSymbol.i1],
);
const _carbonMig = ProcessFiller(
  consumables: [
    Consumable(
        isoStandard: 'EN ISO 14341-A',
        isoDesignation: 'G3Si1',
        awsStandard: 'AWS A5.18',
        awsDesignation: 'ER70S-6'),
  ],
  shielding: [GasSymbol.m21, GasSymbol.c1],
);
const _carbon7018 = Consumable(
  isoStandard: 'EN ISO 2560-A',
  isoDesignation: 'E 42 x B',
  awsStandard: 'AWS A5.1',
  awsDesignation: 'E7018',
  use: FillerText('Zasadowa, niskowodorowa (H5) — wypełnienie i lico.',
      'Basic, low hydrogen (H5) — fill and cap.'),
);
const _carbonFcaw = ProcessFiller(
  consumables: [
    Consumable(
        isoStandard: 'EN ISO 17632-A',
        isoDesignation: 'T 46 x P M21',
        awsStandard: 'AWS A5.20',
        awsDesignation: 'E71T-1M'),
  ],
  shielding: [GasSymbol.m21, GasSymbol.c1],
  note: FillerText(
      'M21 dla E71T-1M, C1 dla odmiany E71T-1C. Pełne oznaczenie EN ISO '
          'dodaje pozycję i wodór — z karty drutu.',
      'M21 for E71T-1M, C1 for the E71T-1C variant. The full EN ISO '
          'designation adds position and hydrogen — from the data sheet.'),
);

/// Stal węglowa — spoiwo niskowodorowe (bez elektrody celulozowej): także
/// do połączeń różnoimiennych z Mo / Cr-Mo.
const kFillerCarbon = FillerFamily(
  id: 'carbon',
  name: FillerText('Węglowe G3Si1 / ER70S-6', 'Carbon steel G3Si1 / ER70S-6'),
  processes: {
    FillerProcess.tig: _carbonTig,
    FillerProcess.mig: _carbonMig,
    FillerProcess.mma: ProcessFiller(consumables: [_carbon7018]),
    FillerProcess.fcaw: _carbonFcaw,
  },
);

/// Stal węglowa + stal węglowa: jak [kFillerCarbon] plus elektroda
/// celulozowa do grani rurociągu (EN ISO 2560-A E 38 3 C 21 = AWS E6010 na
/// kartach Böhler FOX CEL, Gedik LINK 6010, Certilas E 6010).
const kFillerCarbonPipeline = FillerFamily(
  id: 'carbon_pipeline',
  name: FillerText('Węglowe G3Si1 / ER70S-6', 'Carbon steel G3Si1 / ER70S-6'),
  processes: {
    FillerProcess.tig: _carbonTig,
    FillerProcess.mig: _carbonMig,
    FillerProcess.mma: ProcessFiller(consumables: [
      _carbon7018,
      Consumable(
        isoStandard: 'EN ISO 2560-A',
        isoDesignation: 'E 38 x C 21',
        awsStandard: 'AWS A5.1',
        awsDesignation: 'E6010',
        use: FillerText(
            'Celulozowa — grań rurociągu w pozycji PG (z góry na dół), gdy '
                'przewiduje ją WPS.',
            'Cellulosic — pipeline root in PG (vertical down), where the WPS '
                'provides for it.'),
      ),
    ]),
    FillerProcess.fcaw: _carbonFcaw,
  },
);

/// Stal niskotemperaturowa — 1 % Ni.
const kFillerNi1 = FillerFamily(
  id: 'ni1',
  name: FillerText('Niskotemperaturowe 1 % Ni', 'Low-temperature 1 % Ni'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 636-A',
            isoDesignation: 'W3Ni1',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER80S-Ni1'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14341-A',
            isoDesignation: 'G3Ni1',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER80S-Ni1'),
      ],
      shielding: [GasSymbol.m21],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 2560-A',
          isoDesignation: 'E 46 x 1Ni B',
          awsStandard: 'AWS A5.5',
          awsDesignation: 'E8018-C3'),
    ]),
    FillerProcess.fcaw: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 17632-A',
            isoDesignation: 'T 46 x 1Ni P M21',
            awsStandard: 'AWS A5.29',
            awsDesignation: 'E81T1-Ni1M'),
      ],
      shielding: [GasSymbol.m21],
      note: _noteFcawIso,
    ),
  },
);

/// 16Mo3 i podobne 0,5 % Mo.
const kFillerMo = FillerFamily(
  id: 'mo',
  name: FillerText('0,5 % Mo (MoSi / A1)', '0.5 % Mo (MoSi / A1)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'W MoSi',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER70S-A1'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'G MoSi',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER70S-A1'),
      ],
      shielding: [GasSymbol.m21],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3580-A',
          isoDesignation: 'E Mo B',
          awsStandard: 'AWS A5.5',
          awsDesignation: 'E7018-A1'),
    ]),
  },
);

/// P11 / P12.
const kFillerCrMo1 = FillerFamily(
  id: 'crmo1',
  name: FillerText('1CrMo (CrMo1Si / B2)', '1CrMo (CrMo1Si / B2)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'W CrMo1Si',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER80S-B2'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'G CrMo1Si',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER80S-B2'),
      ],
      shielding: [GasSymbol.m21],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3580-A',
          isoDesignation: 'E CrMo1 B',
          awsStandard: 'AWS A5.5',
          awsDesignation: 'E8018-B2'),
    ]),
  },
);

/// P22.
const kFillerCrMo2 = FillerFamily(
  id: 'crmo2',
  name: FillerText('2CrMo (CrMo2Si / B3)', '2CrMo (CrMo2Si / B3)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'W CrMo2Si',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER90S-B3'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'G CrMo2Si',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER90S-B3'),
      ],
      shielding: [GasSymbol.m21],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3580-A',
          isoDesignation: 'E CrMo2 B',
          awsStandard: 'AWS A5.5',
          awsDesignation: 'E9018-B3'),
    ]),
  },
);

/// P91 — 9CrMoV (EN ISO 21952-A „CrMo91”, AWS B9 / B91).
const kFillerCrMo91 = FillerFamily(
  id: 'crmo91',
  name: FillerText('9CrMoV (CrMo91 / B9)', '9CrMoV (CrMo91 / B9)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'W CrMo91',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER90S-B9 (ER90S-B91)'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 21952-A',
            isoDesignation: 'G CrMo91',
            awsStandard: 'AWS A5.28',
            awsDesignation: 'ER90S-B9 (ER90S-B91)'),
      ],
      shielding: [GasSymbol.m21],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3580-A',
          isoDesignation: 'E CrMo91 B',
          awsStandard: 'AWS A5.5',
          awsDesignation: 'E9015-B9 / E9018-B9 (B91)'),
    ]),
  },
);

/// 304L.
const kFiller308L = FillerFamily(
  id: '308L',
  name: FillerText('308L (19 9 L)', '308L (19 9 L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 19 9 L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER308L'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 19 9 L Si',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER308LSi'),
      ],
      shielding: _gasStainlessMig,
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 19 9 L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E308L-16'),
    ]),
    FillerProcess.fcaw: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 17633-A',
            isoDesignation: 'T 19 9 L P',
            awsStandard: 'AWS A5.22',
            awsDesignation: 'E308LT1-1 / -4'),
      ],
      shielding: _gasStainlessFcaw,
      note: _noteStainlessFcaw,
    ),
  },
);

/// 316L.
const kFiller316L = FillerFamily(
  id: '316L',
  name: FillerText('316L (19 12 3 L)', '316L (19 12 3 L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 19 12 3 L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER316L'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 19 12 3 L Si',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER316LSi'),
      ],
      shielding: _gasStainlessMig,
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 19 12 3 L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E316L-16'),
    ]),
    FillerProcess.fcaw: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 17633-A',
            isoDesignation: 'T 19 12 3 L P',
            awsStandard: 'AWS A5.22',
            awsDesignation: 'E316LT1-1 / -4'),
      ],
      shielding: _gasStainlessFcaw,
      note: _noteStainlessFcaw,
    ),
  },
);

/// 321 → 347 (stabilizowane niobem).
const kFiller347 = FillerFamily(
  id: '347',
  name: FillerText('347 (19 9 Nb)', '347 (19 9 Nb)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 19 9 Nb',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER347'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 19 9 Nb Si',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER347Si'),
      ],
      shielding: _gasStainlessMig,
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 19 9 Nb R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E347-16'),
    ]),
  },
  notes: [
    FillerText(
        'Tytan z 321 nie przechodzi przez łuk — dlatego spoiwo stabilizowane '
            'niobem (347).',
        'Titanium from 321 does not transfer across the arc — hence a '
            'niobium-stabilised filler (347).'),
  ],
);

/// Węglowa / niskostopowa + nierdzewna: 309L (23 12 L).
const kFiller309L = FillerFamily(
  id: '309L',
  name: FillerText('309L (23 12 L)', '309L (23 12 L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 23 12 L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER309L'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 23 12 L Si',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER309LSi'),
      ],
      shielding: _gasStainlessMig,
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 23 12 L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E309L-16'),
    ]),
    FillerProcess.fcaw: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 17633-A',
            isoDesignation: 'T 23 12 L P',
            awsStandard: 'AWS A5.22',
            awsDesignation: 'E309LT1-1 / -4'),
      ],
      shielding: _gasStainlessFcaw,
      note: _noteStainlessFcaw,
    ),
  },
);

/// Nierdzewna austenityczna + dupleks: 309LMo (23 12 2 L).
const kFiller309LMo = FillerFamily(
  id: '309LMo',
  name: FillerText('309LMo (23 12 2 L)', '309LMo (23 12 2 L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 23 12 2 L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER309LMo'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 23 12 2 L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER309LMo'),
      ],
      shielding: _gasStainlessMig,
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 23 12 2 L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E309LMo-16'),
    ]),
  },
);

/// Dupleks 2205: 2209 (22 9 3 N L, nadstopowane Ni).
const kFiller2209 = FillerFamily(
  id: '2209',
  name: FillerText('2209 (22 9 3 N L)', '2209 (22 9 3 N L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 22 9 3 N L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER2209'),
      ],
      shielding: [GasSymbol.i1, GasSymbol.n2],
      note: FillerText('IMOA: do argonu można dodać do 3 % N₂ (grupa N2).',
          'IMOA: up to 3 % N₂ may be added to the argon (group N2).'),
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 22 9 3 N L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER2209'),
      ],
      shielding: [GasSymbol.m12, GasSymbol.m13],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 22 9 3 N L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E2209-16'),
    ]),
    FillerProcess.fcaw: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 17633-A',
            isoDesignation: 'T 22 9 3 N L P',
            awsStandard: 'AWS A5.22',
            awsDesignation: 'E2209T1-1 / -4'),
      ],
      shielding: [GasSymbol.c1, GasSymbol.m21],
      note: _noteStainlessFcaw,
    ),
  },
);

/// Super dupleks 2507: 2594 (25 9 4 N L).
const kFiller2594 = FillerFamily(
  id: '2594',
  name: FillerText('2594 (25 9 4 N L)', '2594 (25 9 4 N L)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'W 25 9 4 N L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER2594'),
      ],
      shielding: [GasSymbol.i1, GasSymbol.n2],
      note: FillerText('IMOA: do argonu można dodać do 3 % N₂ (grupa N2).',
          'IMOA: up to 3 % N₂ may be added to the argon (group N2).'),
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 14343-A',
            isoDesignation: 'G 25 9 4 N L',
            awsStandard: 'AWS A5.9',
            awsDesignation: 'ER2594'),
      ],
      shielding: [GasSymbol.m12, GasSymbol.m13],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 3581-A',
          isoDesignation: 'E 25 9 4 N L R',
          awsStandard: 'AWS A5.4',
          awsDesignation: 'E2594-16'),
    ]),
  },
);

/// Spoiwo niklowe typu 82 / 182 — połączenia różnoimienne w wysokiej
/// temperaturze.
const kFillerNiCr3 = FillerFamily(
  id: 'nicr3',
  name: FillerText('Niklowe NiCr-3 (Ni 6082)', 'Nickel NiCr-3 (Ni 6082)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 18274',
            isoDesignation: 'S Ni 6082 (NiCr20Mn3Nb)',
            awsStandard: 'AWS A5.14',
            awsDesignation: 'ERNiCr-3'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 18274',
            isoDesignation: 'S Ni 6082 (NiCr20Mn3Nb)',
            awsStandard: 'AWS A5.14',
            awsDesignation: 'ERNiCr-3'),
      ],
      shielding: [GasSymbol.i1, GasSymbol.i3],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 14172',
          isoDesignation: 'E Ni 6182 (NiCr15Fe6Mn)',
          awsStandard: 'AWS A5.11',
          awsDesignation: 'ENiCrFe-3'),
    ]),
  },
);

/// Miedzionikiel + stal węglowa: NiCu (typ Monel 60).
const kFillerNiCu7 = FillerFamily(
  id: 'nicu7',
  name: FillerText('Niklowo-miedziane NiCu-7 (Ni 4060)',
      'Nickel-copper NiCu-7 (Ni 4060)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 18274',
            isoDesignation: 'S Ni 4060 (NiCu30Mn3Ti)',
            awsStandard: 'AWS A5.14',
            awsDesignation: 'ERNiCu-7'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 18274',
            isoDesignation: 'S Ni 4060 (NiCu30Mn3Ti)',
            awsStandard: 'AWS A5.14',
            awsDesignation: 'ERNiCu-7'),
      ],
      shielding: [GasSymbol.i1, GasSymbol.i3],
    ),
    FillerProcess.mma: ProcessFiller(consumables: [
      Consumable(
          isoStandard: 'EN ISO 14172',
          isoDesignation: 'E Ni 4060 (NiCu30Mn3Ti)',
          awsStandard: 'AWS A5.11',
          awsDesignation: 'ENiCu-7'),
    ]),
  },
);

/// CuNi 90/10 + CuNi 90/10: spoiwo 70/30 (CuNi30).
const kFillerCuNi30 = FillerFamily(
  id: 'cuni30',
  name: FillerText('Miedzioniklowe 70/30 (CuNi30)', 'Copper-nickel 70/30 (CuNi30)'),
  processes: {
    FillerProcess.tig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 24373',
            isoDesignation: 'S Cu 7158 (CuNi30Mn1FeTi)',
            awsStandard: 'AWS A5.7',
            awsDesignation: 'ERCuNi'),
      ],
      shielding: [GasSymbol.i1],
    ),
    FillerProcess.mig: ProcessFiller(
      consumables: [
        Consumable(
            isoStandard: 'EN ISO 24373',
            isoDesignation: 'S Cu 7158 (CuNi30Mn1FeTi)',
            awsStandard: 'AWS A5.7',
            awsDesignation: 'ERCuNi'),
      ],
      shielding: [GasSymbol.i1, GasSymbol.i3],
    ),
  },
  notes: [
    FillerText(
        'Spoiwo 70/30 jest standardem także dla CuNi 90/10 (spoina '
            'szlachetniejsza i mocniejsza od rury). MMA: elektrody ECuNi '
            '(AWS A5.6) — tylko wg WPS.',
        'The 70/30 filler is standard for CuNi 90/10 too (the weld is nobler '
            'and stronger than the pipe). MMA: ECuNi electrodes (AWS A5.6) — '
            'per the WPS only.'),
  ],
);

const _alShielding = [GasSymbol.i1, GasSymbol.i3];
const _alTigNote = FillerText('TIG prądem przemiennym (AC).',
    'TIG on alternating current (AC).');
const _al5183 = Consumable(
  isoStandard: 'EN ISO 18273',
  isoDesignation: 'S Al 5183 (AlMg4,5Mn0,7(A))',
  awsStandard: 'AWS A5.10',
  awsDesignation: 'ER5183',
);
const _al4043 = Consumable(
  isoStandard: 'EN ISO 18273',
  isoDesignation: 'S Al 4043 (AlSi5)',
  awsStandard: 'AWS A5.10',
  awsDesignation: 'ER4043',
  use: FillerText(
      'Mniejsza skłonność do pęknięć na gorąco, lepiej płynie. Niższa '
          'wytrzymałość na ścinanie i plastyczność; po anodowaniu szara. '
          'Dobra przy pracy powyżej ok. 65 °C.',
      'Lower hot-cracking tendency, flows better. Lower shear strength and '
          'ductility; turns grey after anodising. Fine for service above '
          'about 65 °C.'),
);
const _al5356 = Consumable(
  isoStandard: 'EN ISO 18273',
  isoDesignation: 'S Al 5356 (AlMg5Cr(A))',
  awsStandard: 'AWS A5.10',
  awsDesignation: 'ER5356',
  use: FillerText(
      'Wyższa wytrzymałość (pachwiny, ścinanie) i plastyczność, kolor po '
          'anodowaniu bliski blasze. Wrażliwsza na pęknięcia w sztywnym '
          'złączu; nie do pracy stale powyżej ok. 65 °C.',
      'Higher strength (fillets, shear) and ductility, colour after '
          'anodising close to the plate. More crack-sensitive in a rigid '
          'joint; not for sustained service above about 65 °C.'),
);

/// 5083 (i 5083 + 6xxx).
const kFiller5183 = FillerFamily(
  id: '5183',
  name: FillerText('Al-Mg 5183', 'Al-Mg 5183'),
  processes: {
    FillerProcess.tig: ProcessFiller(
        consumables: [_al5183], shielding: _alShielding, note: _alTigNote),
    FillerProcess.mig:
        ProcessFiller(consumables: [_al5183], shielding: _alShielding),
  },
);

/// 6061 / 6082 — dwa spoiwa, kompromis opisany przy każdym.
const kFiller6xxx = FillerFamily(
  id: '4043_5356',
  name: FillerText('Al 4043 albo 5356', 'Al 4043 or 5356'),
  processes: {
    FillerProcess.tig: ProcessFiller(
        consumables: [_al4043, _al5356],
        shielding: _alShielding,
        note: _alTigNote),
    FillerProcess.mig: ProcessFiller(
        consumables: [_al4043, _al5356], shielding: _alShielding),
  },
);
