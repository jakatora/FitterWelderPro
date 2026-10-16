// Dobór spoiwa do pary materiałów — reguły. Czysty Dart.
//
// Para jest NIEUPORZĄDKOWANA: (A, B) i (B, A) dają ten sam wynik — reguły
// liczymy na parze posortowanej po indeksie enuma.
//
// REGUŁY (źródła w filler_catalog.dart):
//   • ten sam materiał → spoiwo jednoimienne (304L → 308L, 316L → 316L,
//     321 → 347, 2205 → 2209, 2507 → 2594, P91 → CrMo91 / B9 …);
//   • dwie stale ferrytyczne → spoiwo SŁABIEJ stopowanej, podgrzewanie i PWHT
//     wg wyżej stopowanej; wyjątki: węglowa + niskotemperaturowa → 1 % Ni
//     (udarność strony niskotemperaturowej), P91 z węglową / 16Mo3 oraz stal
//     niskotemperaturowa z Mo / Cr-Mo → tylko WPS (kolizja PWHT / udarności);
//   • węglowa / niskotemperaturowa / 16Mo3 + austenit → 309L; Cr-Mo + austenit
//     → spoiwo niklowe (praca w wysokiej temperaturze);
//   • węglowa / niskotemperaturowa / 16Mo3 + dupleks → 309L (IMOA tab. 16:
//     2209 / 309L / 309LMo); Cr-Mo + dupleks → tylko WPS (PWHT szkodzi
//     dupleksowi);
//   • austenit + austenit różnoimienny → spoiwo bardziej stopowanego (316L)
//     albo stabilizowane (347 przy 321 + 304L);
//   • austenit + dupleks → 309LMo (IMOA tab. 16: 2209 / 309LMo);
//     2205 + 2507 → 2594 (IMOA tab. 16);
//   • aluminium tylko z aluminium; miedzionikiel z miedzioniklem (70/30) albo
//     ze stalą węglową (NiCu-7); reszta par z CuNi → tylko WPS.

import 'filler_catalog.dart';

/// Rodzaj odpowiedzi.
enum FillerVerdict {
  /// Typowy dobór — spoiwo podane.
  typical,

  /// Połączenie specjalne — spoiwo i technologia wyłącznie wg WPS /
  /// technologa, aplikacja nie podaje spoiwa.
  specialist,

  /// Nie da się zespawać łukowo (np. aluminium ze stalą).
  notArcWeldable,
}

class FillerRecommendation {
  final BaseMaterial a;
  final BaseMaterial b;
  final FillerVerdict verdict;

  /// Spoiwo; `null` dla [FillerVerdict.specialist] i
  /// [FillerVerdict.notArcWeldable].
  final FillerFamily? family;

  /// Jedno zdanie: dlaczego takie spoiwo / dlaczego brak spoiwa.
  final FillerText summary;
  final BackingNeed backing;

  /// Gazy formujące dopuszczalne dla OBU materiałów (część wspólna).
  final List<GasSymbol> backingGases;

  /// Ostrzeżenia: najpierw dla pary i spoiwa, potem materiałowe.
  final List<FillerText> warnings;

  /// Odesłania do innych narzędzi aplikacji (tylko tekst).
  final List<FillerText> seeAlso;

  const FillerRecommendation({
    required this.a,
    required this.b,
    required this.verdict,
    required this.family,
    required this.summary,
    required this.backing,
    required this.backingGases,
    required this.warnings,
    required this.seeAlso,
  });

  bool get sameMaterial => a == b;

  /// Spoiwo i gaz dla [process]; `null`, gdy brak typowego doboru (proces
  /// nietypowy dla tego spoiwa albo połączenie specjalne).
  ProcessFiller? forProcess(FillerProcess process) =>
      family?.processes[process];

  /// Procesy, dla których aplikacja podaje spoiwo.
  List<FillerProcess> get availableProcesses => [
        for (final p in FillerProcess.values)
          if (family?.processes.containsKey(p) ?? false) p,
      ];
}

// ── Teksty reguł par ────────────────────────────────────────────────────────

const _sMatching = FillerText(
    'Spoiwo jednoimienne — dopasowane do materiału rodzimego.',
    'Matching filler — selected for the parent metal.');
const _sCarbonLowTemp = FillerText(
    'Węglowa + niskotemperaturowa: spoiwo 1 % Ni, bo spoina musi spełnić '
        'udarność strony niskotemperaturowej.',
    'Carbon + low-temperature steel: 1 % Ni filler, because the weld must '
        'meet the toughness of the low-temperature side.');
const _sFerriticLower = FillerText(
    'Dwie stale ferrytyczne: spoiwo słabiej stopowanej, podgrzewanie i PWHT '
        'wg wyżej stopowanej.',
    'Two ferritic steels: filler of the lower-alloyed one, preheat and PWHT '
        'per the higher-alloyed one.');
const _s309L = FillerText(
    'Połączenie różnoimienne ze stalą nierdzewną: nadstopowane spoiwo 309L '
        'kompensuje rozcieńczenie stalą niestopową.',
    'Dissimilar joint with stainless: the over-alloyed 309L filler offsets '
        'dilution by the unalloyed steel.');
const _sNiCrMoAustenitic = FillerText(
    'Cr-Mo + nierdzewna austenityczna pracuje zwykle w wysokiej temperaturze '
        '— typowo spoiwo niklowe.',
    'Cr-Mo + austenitic stainless usually runs hot — typically a nickel '
        'filler.');
const _s309LDuplex = FillerText(
    'Stal niestopowa + dupleks: 309L (IMOA tab. 16 podaje 2209, 309L, '
        '309LMo).',
    'Unalloyed steel + duplex: 309L (IMOA table 16 lists 2209, 309L, '
        '309LMo).');
const _sAusteniticMix = FillerText(
    'Dwie różne nierdzewne austenityczne: spoiwo bardziej stopowanej / '
        'stabilizowanej strony.',
    'Two different austenitic stainless steels: filler of the more alloyed / '
        'stabilised side.');
const _s309LMoDuplex = FillerText(
    'Nierdzewna austenityczna + dupleks: 309LMo (IMOA tab. 16 podaje 2209 '
        'albo 309LMo).',
    'Austenitic stainless + duplex: 309LMo (IMOA table 16 lists 2209 or '
        '309LMo).');
const _sDuplexSuper = FillerText(
    'Dupleks + super dupleks: 2594 (IMOA tab. 16).',
    'Duplex + super duplex: 2594 (IMOA table 16).');
const _sAlMix = FillerText(
    '5083 + 6061 / 6082: spoiwo Al-Mg 5183 (tabele producentów podają 5183 '
        'albo 5356).',
    '5083 + 6061 / 6082: Al-Mg filler 5183 (maker tables list 5183 or '
        '5356).');
const _sCuNiSteel = FillerText(
    'Miedzionikiel + stal węglowa: spoiwo niklowo-miedziane NiCu-7 (typ '
        'Monel 60).',
    'Copper-nickel + carbon steel: nickel-copper NiCu-7 filler (Monel 60 '
        'type).');

const _sSpecP91Weak = FillerText(
    'P91 ze stalą węglową / 16Mo3 to połączenie specjalne: PWHT konieczne dla '
        'P91 przegrzewa słabszą stronę. Spoiwo i cykl cieplny tylko wg WPS / '
        'technologa.',
    'P91 to carbon steel / 16Mo3 is a special joint: the PWHT P91 needs '
        'overheats the weaker side. Filler and thermal cycle per the WPS / '
        'welding engineer only.');
const _sSpecLowTempCreep = FillerText(
    'Stal niskotemperaturowa z Mo / Cr-Mo to połączenie nietypowe: udarność '
        'jednej strony i podgrzewanie / PWHT drugiej kolidują. Tylko wg WPS.',
    'Low-temperature steel to Mo / Cr-Mo is unusual: toughness on one side '
        'and preheat / PWHT on the other conflict. Per the WPS only.');
const _sSpecCrMoDuplex = FillerText(
    'Cr-Mo + dupleks: PWHT wymagane dla Cr-Mo szkodzi dupleksowi (fazy '
        'międzymetaliczne). Tylko wg WPS / technologa.',
    'Cr-Mo + duplex: the PWHT Cr-Mo needs harms the duplex (intermetallic '
        'phases). Per the WPS / welding engineer only.');
const _sSpecCuNi = FillerText(
    'Brak typowego doboru w aplikacji dla miedzioniklu z tym materiałem — '
        'spoiwo (zwykle na bazie niklu) wyłącznie wg WPS / producenta.',
    'No typical selection in the app for copper-nickel to this material — '
        'filler (usually nickel-based) per the WPS / manufacturer only.');
const _sNotWeldableAl = FillerText(
    'Aluminium nie da się zespawać łukowo ze stalą ani ze stopami miedzi — '
        'powstają kruche fazy międzymetaliczne. Stosuje się złącza przejściowe '
        '(bimetaliczne, np. platerowane wybuchowo) albo połączenie mechaniczne.',
    'Aluminium cannot be arc welded to steel or copper alloys — brittle '
        'intermetallic phases form. Use transition joints (bimetallic, e.g. '
        'explosion-clad) or a mechanical joint.');

// ── Ostrzeżenia par ─────────────────────────────────────────────────────────

const _w309LHot = FillerText(
    'Praca powyżej ok. 315–370 °C albo cykle cieplne: połączenie 309L ze '
        'stalą niestopową degraduje (migracja węgla, różna rozszerzalność) — '
        'specyfikacje wymagają wtedy zwykle spoiwa niklowego (ERNiCr-3 / '
        'S Ni 6082, elektroda ENiCrFe-3). Decyduje WPS.',
    'Service above about 315–370 °C or thermal cycling: a 309L joint to '
        'unalloyed steel degrades (carbon migration, different expansion) — '
        'specs then usually require a nickel filler (ERNiCr-3 / S Ni 6082, '
        'electrode ENiCrFe-3). The WPS decides.');
const _wNo308L = FillerText(
    'Nie łącz stali niestopowej z nierdzewną spoiwem 308L — po rozcieńczeniu '
        'za mało ferrytu, pęknięcia.',
    'Never join unalloyed steel to stainless with 308L — after dilution there '
        'is too little ferrite, it cracks.');
const _wDissimilarSides = FillerText(
    'Podgrzewanie wg strony niestopowej; formowanie grani — ze względu na '
        'stronę nierdzewną.',
    'Preheat per the unalloyed side; root purge because of the stainless '
        'side.');
const _w309LMoFor316 = FillerText(
    'Przy 316L po drugiej stronie 309L nie ma molibdenu — jeśli połączenie '
        'musi mieć odporność 316L, technolog może wymagać 309LMo.',
    'With 316L on the other side 309L carries no molybdenum — if the joint '
        'needs 316L corrosion resistance, the engineer may require 309LMo.');
const _wNickelDmw = FillerText(
    'Spoiwo niklowe: bufor (napawanie warstwy przejściowej), PWHT strony '
        'Cr-Mo i kolejność ściegów — tylko wg WPS. 309L najwyżej przy pracy '
        'poniżej ok. 315 °C i tylko jeśli WPS tak stanowi.',
    'Nickel filler: buttering, PWHT of the Cr-Mo side and bead sequence — per '
        'the WPS only. 309L at most for service below about 315 °C and only '
        'if the WPS says so.');
const _wFerriticPwht = FillerText(
    'Temperatura PWHT nie może przekroczyć dopuszczalnej dla słabiej '
        'stopowanej strony — kompromis ustala WPS.',
    'The PWHT temperature must not exceed what the lower-alloyed side '
        'allows — the WPS sets the compromise.');
const _wIntermediateFiller = FillerText(
    'Spotykane jest też spoiwo pośrednie (np. 1CrMo / B2) — wg WPS.',
    'An intermediate filler (e.g. 1CrMo / B2) is also used — per the WPS.');
const _wDuplexDissimilarStrength = FillerText(
    'Spoina 309L / 309LMo ma niższą wytrzymałość niż dupleks i wiele stali '
        'węglowych — sprawdź WPS. Spoiwa niklowe tylko bez niobu (IMOA).',
    '309L / 309LMo weld metal is weaker than duplex and many carbon steels — '
        'check the WPS. Nickel fillers only niobium-free (IMOA).');
const _wNo309LWith316 = FillerText(
    'Nie stosuj 309L bez Mo, gdy po drugiej stronie jest 316L.',
    'Do not use Mo-free 309L when the other side is 316L.');
const _wMo308LAlternative = FillerText(
    '308L jest też stosowany, gdy połączenie nie wymaga molibdenu — wg WPS.',
    '308L is also used when the joint does not need molybdenum — per the '
        'WPS.');
const _w308LFor321Alternative = FillerText(
    '308L jest też stosowany przy pracy w niskiej temperaturze — wg WPS.',
    '308L is also used for low-temperature service — per the WPS.');
const _wHot316L321 = FillerText(
    'Przy pracy w podwyższonej temperaturze technolog może wymagać spoiwa '
        'stabilizowanego — wg WPS.',
    'For elevated-temperature service the engineer may require a stabilised '
        'filler — per the WPS.');
const _wAlMix5356 = FillerText(
    'Alternatywnie 5356 (ER5356 / S Al 5356) — wg tabel producenta spoiwa.',
    'Alternatively 5356 (ER5356 / S Al 5356) — per the filler maker tables.');
const _wCuNiSteelDilution = FillerText(
    'Rozcieńczenie żelazem ze strony stali kontroluj wg WPS (np. warstwa '
        'buforowa NiCu).',
    'Control iron dilution from the steel side per the WPS (e.g. a NiCu '
        'buttering layer).');

// ── Dobór ───────────────────────────────────────────────────────────────────

/// Typowy dobór spoiwa dla połączenia [a] + [b] (kolejność bez znaczenia).
FillerRecommendation selectFiller(BaseMaterial a, BaseMaterial b) {
  final x = a.index <= b.index ? a : b;
  final y = identical(x, a) ? b : a;
  final rule = _rule(x, y);

  final materialWarnings = <FillerText>[];
  final seeAlso = <FillerText>[];
  if (rule.verdict != FillerVerdict.notArcWeldable) {
    for (final m in {x, y}) {
      for (final w in m.warnings) {
        if (!materialWarnings.contains(w)) materialWarnings.add(w);
      }
      for (final s in m.seeAlso) {
        if (!seeAlso.contains(s)) seeAlso.add(s);
      }
    }
  }

  final backing = rule.verdict == FillerVerdict.notArcWeldable
      ? BackingNeed.notNeeded
      : _stronger(x.backing, y.backing);
  final backingGases = backing == BackingNeed.notNeeded
      ? const <GasSymbol>[]
      : [
          for (final g in x.backingGases)
            if (y.backingGases.contains(g)) g,
        ];

  return FillerRecommendation(
    a: a,
    b: b,
    verdict: rule.verdict,
    family: rule.family,
    summary: rule.summary,
    backing: backing,
    backingGases: backingGases,
    warnings: [
      ...rule.warnings,
      ...?rule.family?.notes,
      ...materialWarnings,
    ],
    seeAlso: seeAlso,
  );
}

BackingNeed _stronger(BackingNeed p, BackingNeed q) =>
    p.index >= q.index ? p : q;

class _Rule {
  final FillerVerdict verdict;
  final FillerFamily? family;
  final FillerText summary;
  final List<FillerText> warnings;

  const _Rule.typical(FillerFamily this.family, this.summary,
      [this.warnings = const []])
      : verdict = FillerVerdict.typical;

  const _Rule.specialist(this.summary)
      : verdict = FillerVerdict.specialist,
        family = null,
        warnings = const [];

  const _Rule.notWeldable(this.summary)
      : verdict = FillerVerdict.notArcWeldable,
        family = null,
        warnings = const [];
}

/// Spoiwo jednoimienne dla materiału.
FillerFamily _matching(BaseMaterial m) => switch (m) {
      BaseMaterial.carbonSteel => kFillerCarbonPipeline,
      BaseMaterial.lowTempSteel => kFillerNi1,
      BaseMaterial.mo05 => kFillerMo,
      BaseMaterial.crMo1 => kFillerCrMo1,
      BaseMaterial.crMo2 => kFillerCrMo2,
      BaseMaterial.p91 => kFillerCrMo91,
      BaseMaterial.ss304L => kFiller308L,
      BaseMaterial.ss316L => kFiller316L,
      BaseMaterial.ss321 => kFiller347,
      BaseMaterial.duplex2205 => kFiller2209,
      BaseMaterial.superDuplex2507 => kFiller2594,
      BaseMaterial.al5083 => kFiller5183,
      BaseMaterial.al6xxx => kFiller6xxx,
      BaseMaterial.cuNi9010 => kFillerCuNi30,
    };

/// Spoiwo stali ferrytycznej użyte w połączeniu różnoimiennym (bez
/// elektrody celulozowej — ta tylko dla rurociągu węglowa + węglowa).
FillerFamily _ferriticDissimilar(BaseMaterial m) =>
    m == BaseMaterial.carbonSteel ? kFillerCarbon : _matching(m);

/// [x] ma indeks enuma ≤ [y] — kolejność deklaracji w [BaseMaterial]:
/// ferrytyczne, austenityczne, dupleks, aluminium, miedzionikiel.
_Rule _rule(BaseMaterial x, BaseMaterial y) {
  if (x == y) return _Rule.typical(_matching(x), _sMatching);

  // Aluminium spawa się łukowo tylko z aluminium.
  if (x.isAluminium || y.isAluminium) {
    if (x.isAluminium && y.isAluminium) {
      return const _Rule.typical(kFiller5183, _sAlMix, [_wAlMix5356]);
    }
    return const _Rule.notWeldable(_sNotWeldableAl);
  }

  // Miedzionikiel: ze stalą węglową — NiCu-7; z resztą — tylko WPS.
  if (y.isCopperNickel) {
    if (x == BaseMaterial.carbonSteel) {
      return const _Rule.typical(
          kFillerNiCu7, _sCuNiSteel, [_wCuNiSteelDilution]);
    }
    return const _Rule.specialist(_sSpecCuNi);
  }

  // Dwie stale ferrytyczne.
  if (x.isFerritic && y.isFerritic) {
    final lowTemp =
        x == BaseMaterial.lowTempSteel || y == BaseMaterial.lowTempSteel;
    if (lowTemp) {
      final other = x == BaseMaterial.lowTempSteel ? y : x;
      if (other == BaseMaterial.carbonSteel) {
        return const _Rule.typical(kFillerNi1, _sCarbonLowTemp);
      }
      return const _Rule.specialist(_sSpecLowTempCreep);
    }
    if (y == BaseMaterial.p91 &&
        (x == BaseMaterial.carbonSteel || x == BaseMaterial.mo05)) {
      return const _Rule.specialist(_sSpecP91Weak);
    }
    final lower = x.ferriticRank! <= y.ferriticRank! ? x : y;
    final higher = identical(lower, x) ? y : x;
    return _Rule.typical(_ferriticDissimilar(lower), _sFerriticLower, [
      _wFerriticPwht,
      if (lower == BaseMaterial.carbonSteel && higher == BaseMaterial.crMo2)
        _wIntermediateFiller,
    ]);
  }

  // Ferrytyczna + nierdzewna austenityczna.
  if (x.isFerritic && y.isAustenitic) {
    if (x.isCrMo) {
      return const _Rule.typical(
          kFillerNiCr3, _sNiCrMoAustenitic, [_wNickelDmw]);
    }
    return _Rule.typical(kFiller309L, _s309L, [
      _w309LHot,
      _wNo308L,
      _wDissimilarSides,
      if (y == BaseMaterial.ss316L) _w309LMoFor316,
    ]);
  }

  // Ferrytyczna + dupleks.
  if (x.isFerritic && y.isDuplex) {
    if (x.isCrMo) return const _Rule.specialist(_sSpecCrMoDuplex);
    return const _Rule.typical(kFiller309L, _s309LDuplex, [
      _wDuplexDissimilarStrength,
      _wDissimilarSides,
    ]);
  }

  // Dwie różne nierdzewne austenityczne.
  if (x.isAustenitic && y.isAustenitic) {
    final pair = {x, y};
    if (pair.containsAll({BaseMaterial.ss304L, BaseMaterial.ss316L})) {
      return const _Rule.typical(
          kFiller316L, _sAusteniticMix, [_wMo308LAlternative]);
    }
    if (pair.containsAll({BaseMaterial.ss304L, BaseMaterial.ss321})) {
      return const _Rule.typical(
          kFiller347, _sAusteniticMix, [_w308LFor321Alternative]);
    }
    // 316L + 321.
    return const _Rule.typical(kFiller316L, _sAusteniticMix, [_wHot316L321]);
  }

  // Austenityczna + dupleks.
  if (x.isAustenitic && y.isDuplex) {
    return _Rule.typical(kFiller309LMo, _s309LMoDuplex, [
      _wDuplexDissimilarStrength,
      if (x == BaseMaterial.ss316L) _wNo309LWith316,
    ]);
  }

  // Dupleks + super dupleks (jedyna para dwóch różnych dupleksów).
  return const _Rule.typical(kFiller2594, _sDuplexSuper);
}
