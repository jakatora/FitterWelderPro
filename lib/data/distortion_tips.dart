/// Lista kontrolna „jak zapobiec odkształceniom” — środki dobrane do
/// sytuacji (rodzaj elementu × rodzaj odkształcenia), każdy z „dlaczego”
/// i źródłem. Typy: `lib/domain/welding/distortion.dart`.
///
/// Źródła (treść sprawdzona 2026-10-17):
/// * TWI Job Knowledge 33–37 (twi-global.com, „Distortion …”): typy
///   i przyczyny, zapobieganie przez konstrukcję, przez ustawienie wstępne /
///   wygięcie wstępne / utwierdzenie, przez technikę wykonania, korekta.
/// * TWI FAQ „How much shall I allow for weld shrinkage?”.
/// * Lincoln Electric, Welding How-Tos „Weld Distortion”.
/// * Lake Washington Institute of Technology, „Pipe Welding” (2024,
///   CC BY-NC 4.0), rozdz. 6 „Tack Welds”.
/// * R. A. Hay, C. H. Holtyn, „The Effect of Thermal Fabrication Practices
///   on Aluminum”, Naval Engineers Journal 92 (5), 1980 — aluminium nie
///   zmienia barwy aż do stopienia; kontrola temperatury chroni własności
///   mechaniczne i odporność na korozję (sprawdzone 2026-10-17).
/// * TWI FAQ „What is metal fume fever?” — powłoki rozpoznać przed
///   spawaniem / cięciem, cynk usunąć z zapasem, odciąg dymów, w razie
///   potrzeby aparat oddechowy (sprawdzone 2026-10-17).
///
/// Nadmiar pachwiny: TWI JK34 pisze, że noga 8 mm zamiast 6 mm to „57 %”
/// więcej stopiwa — to niezgodne z geometrią (przekrój ~ noga², 64 : 36 =
/// 1,78). Na ekranie stosunek geometryczny (+78 %, ok. 1,8 raza), jak
/// w module wad spoin.
///
/// Czego celowo NIE ma, bo źródła nie podają liczb: kąta ustawienia
/// wstępnego (TWI i Lincoln: wyznaczyć na spoinie próbnej), rozstawu
/// i długości sczepów na blachach (TWI: „liczba, długość i rozstaw mają
/// znaczenie” — bez wartości), tolerancji ustawienia kołnierza przed
/// spawaniem (z odbioru kołnierzy / projektu), temperatur prostowania stali
/// nierdzewnych, Cr-Mo i ulepszanych cieplnie (tylko wg WPS / za zgodą).
///
/// Liczby w tekstach PL i EN są te same (test).
///
/// Czysty Dart.
library;

import '../domain/welding/distortion.dart';

const String _twi33 = 'TWI Job Knowledge 33: Distortion — types and causes';
const String _twiFaq = 'TWI FAQ: How much shall I allow for weld shrinkage?';
const String _twi34 = 'TWI Job Knowledge 34: Distortion — prevention by design';
const String _twi35 = 'TWI Job Knowledge 35: Distortion — prevention by '
    'pre-setting, pre-bending or use of restraint';
const String _twi36 = 'TWI Job Knowledge 36: Distortion control — prevention '
    'by fabrication techniques';
const String _twi37 = 'TWI Job Knowledge 37: Distortion — corrective '
    'techniques';
const String _lincoln = 'Lincoln Electric: Weld Distortion (Welding How-Tos)';
const String _lwtech =
    'Lake Washington Institute of Technology: Pipe Welding (2024), '
    'ch. 6 Tack Welds';
const String _aluminium = 'Hay, Holtyn: The Effect of Thermal Fabrication '
    'Practices on Aluminum, Naval Engineers Journal 92(5), 1980';
const String _twiFumeFever = 'TWI FAQ: What is metal fume fever?';

const Set<DistortionElement> _allElements = {
  DistortionElement.plateButt,
  DistortionElement.teeFillet,
  DistortionElement.pipeGirth,
  DistortionElement.flangeOnPipe,
  DistortionElement.tankShell,
  DistortionElement.longMember,
};

const Set<DistortionKind> _allKinds = {
  DistortionKind.angular,
  DistortionKind.bowing,
  DistortionKind.buckling,
  DistortionKind.twisting,
  DistortionKind.flangeTilt,
  DistortionKind.gapClosing,
};

/// Jakie odkształcenia mają sens dla danego elementu (kolejność = kolejność
/// chipów; pierwszy — domyślny po zmianie elementu).
const Map<DistortionElement, List<DistortionKind>> kElementKinds = {
  DistortionElement.plateButt: [
    DistortionKind.angular,
    DistortionKind.gapClosing,
    DistortionKind.bowing,
    DistortionKind.buckling,
  ],
  DistortionElement.teeFillet: [
    DistortionKind.angular,
    DistortionKind.bowing,
    DistortionKind.twisting,
    DistortionKind.buckling,
  ],
  DistortionElement.pipeGirth: [
    DistortionKind.gapClosing,
    DistortionKind.angular,
  ],
  DistortionElement.flangeOnPipe: [
    DistortionKind.flangeTilt,
    DistortionKind.gapClosing,
  ],
  DistortionElement.tankShell: [
    DistortionKind.angular,
    DistortionKind.gapClosing,
    DistortionKind.buckling,
  ],
  DistortionElement.longMember: [
    DistortionKind.bowing,
    DistortionKind.twisting,
    DistortionKind.angular,
  ],
};

const List<DistortionMeasure> kDistortionMeasures = [
  DistortionMeasure(
    id: 'trial',
    titlePl: 'Zmierz skurcz na pierwszym złączu',
    titleEn: 'Measure the shrinkage on the first joint',
    howPl: 'Zmierz wymiar po sczepieniu i po spawaniu pierwszego złącza. '
        'Różnicę wpisz w kalkulatorze wymiaru jako „mój pomiar”.',
    howEn: 'Measure the dimension after tacking and after welding the first '
        'joint. Enter the difference in the dimension calculator as '
        '“my measurement”.',
    whyPl: 'Wzory i reguły z literatury to szacunek — według TWI dokładne '
        'przewidzenie skurczu jest prawie niemożliwe. Pomiar uwzględnia '
        'twoje utwierdzenie, kolejność i energię liniową.',
    whyEn: 'Formulas and rules of thumb are estimates — according to TWI, '
        'predicting shrinkage accurately is almost impossible. A measurement '
        'includes your restraint, sequence and heat input.',
    elements: _allElements,
    kinds: _allKinds,
    source: _twiFaq,
  ),
  DistortionMeasure(
    id: 'preset',
    titlePl: 'Ustawienie wstępne pod kątem (presetting)',
    titleEn: 'Presetting',
    howPl: 'Ustaw części odchylone przeciwnie do spodziewanego odkształcenia '
        'i zostaw je swobodne. Kąt wyznacz na spoinie próbnej, podobnej do '
        'konstrukcji — źródła nie podają jednej wartości.',
    howEn: 'Set the parts tilted opposite to the expected distortion and '
        'leave them free. Find the angle on a trial weld similar to the '
        'structure — the sources give no single value.',
    whyPl: 'Skurcz sam ściąga części do linii. W porównaniu z utwierdzeniem '
        'zostaje mniej naprężeń własnych i nie trzeba przyrządów.',
    whyEn: 'Shrinkage pulls the parts into line by itself. Compared with '
        'restraint it leaves lower residual stress and needs no fixtures.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.longMember,
    },
    kinds: {DistortionKind.angular},
    source: '$_twi35; $_lincoln',
  ),
  DistortionMeasure(
    id: 'gap-ahead',
    titlePl: 'Szczelina zamyka się przed łukiem',
    titleEn: 'The gap closes ahead of the arc',
    howPl: 'Przy MMA i MIG złącze doczołowe zwykle zamyka się przed łukiem '
        '(przy łuku krytym może się otwierać). Ustaw szczelinę rozchyloną '
        'w kierunku spawania albo sczep gęściej; rozchylenie sprawdź na '
        'próbie.',
    howEn: 'With MMA and MIG a butt joint usually closes ahead of the arc '
        '(with submerged arc it may open). Set the gap tapering open in the '
        'welding direction or tack more densely; check the taper on a '
        'trial.',
    whyPl: 'Za łukiem spoina stygnie i kurczy się, obracając brzegi przed '
        'łukiem ku sobie — dalsza część złącza dostaje coraz mniejszą '
        'szczelinę grani.',
    whyEn: 'Behind the arc the weld cools and shrinks, rotating the edges '
        'ahead of the arc towards each other — the rest of the joint gets an '
        'ever smaller root gap.',
    elements: {DistortionElement.plateButt, DistortionElement.tankShell},
    kinds: {DistortionKind.gapClosing},
    source: '$_twi35; $_twi36',
  ),
  DistortionMeasure(
    id: 'tacks',
    titlePl: 'Sczepy: liczba, długość, kolejność',
    titleEn: 'Tacks: number, length, sequence',
    howPl: 'Sczepiaj od środka, dalej krokiem wstecz; albo od jednego końca '
        'krokiem wstecz; albo na wprost, trzymając szczelinę dociskami lub '
        'klinami. Rozstaw i długość sczepów wg WPS — TWI nie podaje liczb.',
    howEn: 'Tack from the centre, then back-step; or from one end with '
        'back-stepping; or straight through, holding the gap with clamps or '
        'wedges. Tack spacing and length per the WPS — TWI gives no '
        'figures.',
    whyPl: 'Sczepy ustalają i trzymają szczelinę oraz opierają się skurczowi '
        'poprzecznemu. Za mało sczepów — złącze zamyka się w trakcie '
        'spawania, a na długiej spoinie brzegi mogą zajść na siebie.',
    whyEn: 'Tacks set and hold the gap and resist transverse shrinkage. Too '
        'few tacks — the joint closes up as welding proceeds, and on a long '
        'seam the edges may overlap.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {DistortionKind.gapClosing, DistortionKind.angular},
    source: _twi36,
  ),
  DistortionMeasure(
    id: 'pipe-tacks',
    titlePl: 'Rura: 4 sczepy równo po obwodzie',
    titleEn: 'Pipe: 4 tacks evenly round',
    howPl: 'Typowo 4 sczepy na godzinach 12, 3, 6 i 9 (albo 11, 2, 5 i 8), '
        'każdy z przetopem do grani, ok. 19 mm (¾") długości; na dużych '
        'średnicach ok. 5–10 % średnicy. Po sczepieniu sprawdź szczelinę '
        'grani i przesunięcie krawędzi (hi-lo). Wiążący jest WPS.',
    howEn: 'Typically 4 tacks at 12, 3, 6 and 9 o’clock (or 11, 2, 5 and 8), '
        'each penetrating to the root, about ¾" (19 mm) long; on large '
        'diameters about 5–10 % of the diameter. After tacking check the '
        'root gap and the hi-lo misalignment. The WPS is binding.',
    whyPl: 'Sczepy trzymają osiowość i równą szczelinę grani. Sczep '
        'przeszlifowany zbyt cienko pęka i szczelina się zamyka.',
    whyEn: 'Tacks hold alignment and an even root gap. A tack ground too thin '
        'cracks and the gap closes.',
    elements: {DistortionElement.pipeGirth, DistortionElement.flangeOnPipe},
    kinds: {
      DistortionKind.gapClosing,
      DistortionKind.angular,
      DistortionKind.flangeTilt,
    },
    source: _lwtech,
  ),
  DistortionMeasure(
    id: 'opposite',
    titlePl: 'Spawaj odcinkami naprzeciwległymi',
    titleEn: 'Weld opposite segments',
    howPl: 'Na kołnierzu i na dużej rurze nie obchodź obwodu jednym ciągiem — '
        'kładź odcinki na zmianę po przeciwnych stronach. Kolejność ściegów '
        'wg WPS.',
    howEn: 'On a flange and on a large pipe do not go round in one run — lay '
        'segments alternately on opposite sides. Run sequence per the WPS.',
    whyPl: 'Skurcz odcinka po jednej stronie równoważy skurcz po drugiej — '
        'tak jak spoiny rozłożone symetrycznie względem osi.',
    whyEn: 'Shrinkage of a segment on one side balances the shrinkage on the '
        'other — like welds balanced about the neutral axis.',
    elements: {DistortionElement.flangeOnPipe, DistortionElement.pipeGirth},
    kinds: {DistortionKind.flangeTilt, DistortionKind.angular},
    source: _lincoln,
  ),
  DistortionMeasure(
    id: 'flange-check',
    titlePl: 'Sprawdź kołnierz po sczepieniu',
    titleEn: 'Check the flange after tacking',
    howPl: 'Po sczepieniu i po pierwszym ściegu sprawdź prostopadłość '
        'przylgi do osi rury kątownikiem lub poziomicą w dwóch kierunkach. '
        'Tolerancję ustawienia weź z odbioru kołnierzy (PCC-1) albo '
        'z projektu.',
    howEn: 'After tacking and after the first run check that the flange face '
        'is square to the pipe axis with a square or level in two '
        'directions. Take the alignment tolerance from the flange check '
        '(PCC-1) or the design.',
    whyPl: 'Sczepy też się kurczą i ciągną kołnierz. Póki jest tylko '
        'sczepiony, poprawisz go bez cięcia spoiny.',
    whyEn: 'Tacks shrink too and pull the flange. While it is only tacked you '
        'can correct it without cutting a weld.',
    elements: {DistortionElement.flangeOnPipe},
    kinds: {DistortionKind.flangeTilt},
    source: _lwtech,
    link: MeasureLink.flangeCheck,
  ),
  DistortionMeasure(
    id: 'heat-input',
    titlePl: 'Mniej ciepła na spoinę',
    titleEn: 'Less heat per weld',
    howPl: 'W granicach WPS: większa wydajność stapiania i prędkość zamiast '
        'wolnego, szerokiego ściegu; krótkie przerwy między ściegami '
        '(w granicach temperatury międzyściegowej). Policz energię liniową '
        'w kalkulatorze.',
    howEn: 'Within the WPS: higher deposition rate and travel speed instead '
        'of a slow, wide run; short time between runs (within the interpass '
        'temperature). Work out the heat input in the calculator.',
    whyPl: 'Im więcej ciepła, tym szersza strefa, która rozszerza się, '
        'a potem kurczy. Szybkie spawanie kończy spoinę, zanim nagrzeje się '
        'dużo metalu dookoła.',
    whyEn: 'The more heat, the wider the zone that expands and then shrinks. '
        'Fast welding finishes the weld before much of the surrounding metal '
        'heats up.',
    elements: _allElements,
    kinds: _allKinds,
    source: '$_lincoln; $_twi36',
    link: MeasureLink.heatInput,
  ),
  DistortionMeasure(
    id: 'fewer-passes',
    titlePl: 'Jak najmniej ściegów',
    titleEn: 'As few passes as possible',
    howPl: 'W złączach jednostronnych wypełniaj mniejszą liczbą większych '
        'ściegów: największa elektroda (MMA) albo największy prąd (MIG), '
        'przy których nie ma przyklejeń. Na cienkiej blasze uwaga — duży '
        'ścieg zwiększa ryzyko falowania.',
    howEn: 'In single-sided joints fill with fewer, larger runs: the largest '
        'electrode (MMA) or highest current (MIG) that avoids lack of '
        'fusion. On thin plate take care — a large deposit raises the risk '
        'of buckling.',
    whyPl: 'W złączu swobodnym odkształcenie kątowe rośnie mniej więcej '
        'proporcjonalnie do liczby ściegów, a skurcz z kolejnych ściegów się '
        'sumuje.',
    whyEn: 'In an unrestrained joint angular distortion grows roughly in '
        'proportion to the number of passes, and the shrinkage of successive '
        'passes adds up.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.pipeGirth,
      DistortionElement.tankShell,
    },
    kinds: {DistortionKind.angular, DistortionKind.gapClosing},
    source: '$_twi34; $_twi36; $_lincoln',
  ),
  DistortionMeasure(
    id: 'less-metal',
    titlePl: 'Mniej stopiwa w złączu',
    titleEn: 'Less weld metal in the joint',
    howPl: 'Na grubych blachach rowek X zamiast V (często połowa przekroju), '
        'mniejszy kąt rowka i szczelina — o ile grań da się dobrze '
        'przetopić. Nie przewymiarowuj pachwin: przekrój rośnie z kwadratem '
        'nogi, więc noga 8 zamiast 6 mm to 64 : 36 — ok. 1,8 raza tyle '
        'stopiwa (+78 %). Porównaj rowki w kalkulatorze skurczu.',
    howEn: 'On thick plate a double-V instead of a single-V (often half the '
        'cross-section), a smaller groove angle and gap — as long as the '
        'root can still be fused properly. Do not over-weld fillets: the '
        'cross-section grows with the square of the leg, so a leg of 8 '
        'instead of 6 mm is 64 : 36 — about 1.8 times the weld metal '
        '(+78 %). Compare the grooves in the shrinkage calculator.',
    whyPl: 'Skurcz rośnie z ilością stopiwa. Wypukły nadmiar nie dodaje '
        'wytrzymałości, a dokłada skurczu.',
    whyEn: 'Shrinkage grows with the amount of weld metal. Excess convexity '
        'adds no strength but adds shrinkage.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {
      DistortionKind.angular,
      DistortionKind.gapClosing,
      DistortionKind.bowing,
      DistortionKind.buckling,
    },
    source: _twi34,
  ),
  DistortionMeasure(
    id: 'alternate-sides',
    titlePl: 'Rowek X: na zmianę z obu stron',
    titleEn: 'Double-V: alternate the sides',
    howPl: 'Nie kończ jednej strony przed drugą — kładź ściegi na zmianę '
        'z obu stron i koryguj odkształcenie kątowe kolejnością ściegów. '
        'Gdy nie da się obracać elementu: rowek niesymetryczny, więcej '
        'stopiwa po stronie spawanej jako druga.',
    howEn: 'Do not finish one side before the other — alternate the runs '
        'between the sides and correct angular distortion with the run '
        'order. If the part cannot be turned: an asymmetric preparation with '
        'more weld metal on the side welded second.',
    whyPl: 'Skurcz po jednej stronie osi obojętnej znosi skurcz po drugiej, '
        'więc odkształcenie kątowe koryguje się w trakcie spawania.',
    whyEn: 'Shrinkage on one side of the neutral axis cancels the other, so '
        'angular distortion is corrected as welding proceeds.',
    elements: {DistortionElement.plateButt, DistortionElement.tankShell},
    kinds: {DistortionKind.angular},
    source: '$_twi34; $_lincoln',
  ),
  DistortionMeasure(
    id: 'neutral-axis',
    titlePl: 'Spoiny blisko osi obojętnej, symetrycznie',
    titleEn: 'Welds near the neutral axis, balanced',
    howPl: 'Spawaj parami po obu stronach osi obojętnej przekroju, a podzespoły '
        'łącz w kolejności, która stale równoważy skurcz.',
    howEn: 'Weld in pairs on both sides of the neutral axis of the section, '
        'and join sub-assemblies in an order that keeps balancing the '
        'shrinkage.',
    whyPl: 'Im bliżej osi obojętnej, tym krótsze ramię, na którym skurcz '
        'wygina element; spoina po drugiej stronie go równoważy.',
    whyEn: 'The closer to the neutral axis, the shorter the lever the '
        'shrinkage has to bend the member; a weld on the other side balances '
        'it.',
    elements: {DistortionElement.teeFillet, DistortionElement.longMember},
    kinds: {
      DistortionKind.bowing,
      DistortionKind.twisting,
      DistortionKind.angular,
    },
    source: '$_lincoln; $_twi34',
  ),
  DistortionMeasure(
    id: 'backstep',
    titlePl: 'Krokiem wstecz albo odcinkami przestawnymi',
    titleEn: 'Back-step or skip welding',
    howPl: 'Długiej spoiny nie kładź jednym ciągiem w jednym kierunku. Krok '
        'wstecz: krótkie odcinki kładzione przeciwnie do ogólnego postępu. '
        'Odcinki przestawne: krótkie odcinki w ustalonej kolejności, równo '
        'rozłożone. Odcinek i przerwa ≈ długość stopienia jednej elektrody. '
        'Spawaj w stronę swobodnego końca.',
    howEn: 'Do not lay a long weld in one run in one direction. Back-step: '
        'short lengths laid against the general progression. Skip welding: '
        'short lengths in a set, evenly spaced order. Length and gap ≈ the '
        'run-out length of one electrode. Weld towards the free end.',
    whyPl: 'Ciepło rozkłada się po długości zamiast gromadzić się na jednym '
        'końcu, a każdy odcinek kurczy się na tle już usztywnionego złącza.',
    whyEn: 'The heat is spread along the length instead of building up at one '
        'end, and each length shrinks against an already stiffened joint.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {
      DistortionKind.bowing,
      DistortionKind.buckling,
      DistortionKind.gapClosing,
      DistortionKind.twisting,
    },
    source: '$_twi36; $_lincoln',
  ),
  DistortionMeasure(
    id: 'intermittent',
    titlePl: 'Spoiny przerywane, gdzie pozwala projekt',
    titleEn: 'Intermittent welds where the design allows',
    howPl: 'Przy żebrach i usztywnieniach spoina przerywana zamiast ciągłej — '
        'tylko jeśli dopuszcza ją rysunek.',
    howEn: 'For ribs and stiffeners an intermittent weld instead of a '
        'continuous one — only where the drawing allows it.',
    whyPl: 'Według Lincoln przy mocowaniu usztywnień może to dać nawet 75 % '
        'mniej stopiwa przy wystarczającej wytrzymałości — mniej stopiwa, '
        'mniej skurczu.',
    whyEn: 'According to Lincoln, for attaching stiffeners this can cut weld '
        'metal by as much as 75 % with adequate strength — less weld metal, '
        'less shrinkage.',
    elements: {
      DistortionElement.teeFillet,
      DistortionElement.longMember,
      DistortionElement.tankShell,
    },
    kinds: {
      DistortionKind.bowing,
      DistortionKind.buckling,
      DistortionKind.twisting,
    },
    source: '$_lincoln; $_twi34',
  ),
  DistortionMeasure(
    id: 'restraint',
    titlePl: 'Sztywne mocowanie: przyrząd, ściski, strongbacki',
    titleEn: 'Restraint: jigs, clamps, strongbacks',
    howPl: 'Trzymaj części w przyrządzie, ściskach albo na strongbackach '
        'z klinami do końca spawania. Po zwolnieniu zostaje niewielki ruch — '
        'skompensuj go małym ustawieniem wstępnym. Przy materiałach '
        'skłonnych do pęknięć dobierz kolejność i podgrzewanie.',
    howEn: 'Hold the parts in a jig, clamps or wedged strongbacks until '
        'welding is complete. A small movement remains on release — offset '
        'it with a small preset. With crack-sensitive materials choose the '
        'sequence and preheat accordingly.',
    whyPl: 'Utwierdzenie nie pozwala częściom się ruszyć, ale podnosi '
        'naprężenia własne. Strongback z klinami pozwala na skurcz '
        'poprzeczny, więc mniej grozi pęknięciem niż przyspawany z obu '
        'stron.',
    whyEn: 'Restraint stops the parts moving but raises residual stress. A '
        'wedged strongback allows transverse shrinkage, so it risks cracking '
        'less than one welded on both sides.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {
      DistortionKind.angular,
      DistortionKind.bowing,
      DistortionKind.buckling,
      DistortionKind.twisting,
    },
    source: '$_twi35; $_lincoln',
  ),
  DistortionMeasure(
    id: 'shell-strongbacks',
    titlePl: 'Płaszcz: strongbacki z klinami na szwach',
    titleEn: 'Shell: wedged strongbacks on the seams',
    howPl: 'Na szwach płaszcza walcowego stosuj strongbacki z klinami — '
        'pomagają uniknąć „daszka” (peaking) i kątowego załamania blach.',
    howEn: 'On cylindrical shell seams use wedged strongbacks — they help '
        'prevent peaking and angular distortion of the plates.',
    whyPl: 'Kliny trzymają krawędzie w linii, ale pozwalają na skurcz '
        'poprzeczny, co mocno zmniejsza ryzyko pęknięcia.',
    whyEn: 'The wedges hold the edges in line but allow transverse shrinkage, '
        'which greatly reduces the risk of cracking.',
    elements: {DistortionElement.tankShell},
    kinds: {DistortionKind.angular},
    source: _twi35,
  ),
  DistortionMeasure(
    id: 'back-to-back',
    titlePl: 'Dwa jednakowe elementy plecami do siebie',
    titleEn: 'Two identical parts back to back',
    howPl: 'Sczep albo ściśnij dwa jednakowe elementy plecami i spawaj '
        'symetrycznie. Przed rozdzieleniem wyżarz odprężająco albo włóż '
        'kliny między elementy, żeby po ich wyjęciu odbiły do właściwego '
        'kształtu.',
    howEn: 'Tack or clamp two identical parts back to back and weld them '
        'symmetrically. Stress relieve before separating, or put wedges '
        'between them so the parts spring back to shape when the wedges are '
        'removed.',
    whyPl: 'Spawanie rozkłada się równo wokół wspólnej osi obojętnej, więc '
        'wygięcia obu elementów się znoszą.',
    whyEn: 'Welding is balanced about the common neutral axis, so the '
        'bending of the two parts cancels out.',
    elements: {DistortionElement.teeFillet, DistortionElement.longMember},
    kinds: {
      DistortionKind.bowing,
      DistortionKind.angular,
      DistortionKind.twisting,
    },
    source: '$_twi36; $_lincoln',
  ),
  DistortionMeasure(
    id: 'prebend',
    titlePl: 'Wygięcie wstępne (pre-bending)',
    titleEn: 'Pre-bending',
    howPl: 'Wygnij element przeciwnie do spodziewanego wygięcia — '
        'strongbackami z klinami albo w przyrządzie — i po spawaniu zwolnij.',
    howEn: 'Bend the part opposite to the expected bowing — with wedged '
        'strongbacks or in a fixture — and release it after welding.',
    whyPl: 'Siła mechaniczna przeciwdziała skurczowi; po zwolnieniu spoina '
        'się skraca, a element wraca do linii.',
    whyEn: 'A mechanical force opposes the shrinkage; on release the weld '
        'shortens and the part returns to line.',
    elements: {
      DistortionElement.longMember,
      DistortionElement.teeFillet,
      DistortionElement.plateButt,
    },
    kinds: {DistortionKind.bowing, DistortionKind.angular},
    source: '$_twi35; $_lincoln',
  ),
  DistortionMeasure(
    id: 'thin-stiffeners',
    titlePl: 'Cienka blacha: usztywnienia wzdłuż spoiny',
    titleEn: 'Thin plate: stiffeners along the seam',
    howPl: 'Przyspawaj płaskowniki albo kątowniki wzdłuż obu stron spoiny '
        'doczołowej, tak daleko, żeby nie przeszkadzały w spawaniu; przy '
        'spawaniu jednostronnym mogą być po drugiej stronie.',
    howEn: 'Weld flats or angles along both sides of the butt seam, far '
        'enough not to obstruct welding; with one-sided welding they can go '
        'on the reverse side.',
    whyPl: 'Usztywnienia nie pozwalają cienkiej blasze wygiąć się wzdłuż '
        'spoiny i falować.',
    whyEn: 'The stiffeners keep thin plate from bowing along the seam and '
        'buckling.',
    elements: {DistortionElement.plateButt, DistortionElement.tankShell},
    kinds: {DistortionKind.buckling, DistortionKind.bowing},
    source: _twi36,
  ),
  DistortionMeasure(
    id: 'cooling-jig',
    titlePl: 'Odbieraj ciepło: miedziane dociski',
    titleEn: 'Take the heat away: copper clamps',
    howPl: 'Przy cienkiej blasze dociski z miedzi, w razie potrzeby chłodzone '
        'wodą płynącą w przylutowanych rurkach.',
    howEn: 'On thin sheet use copper clamps, if needed water-cooled through '
        'tubes brazed to them.',
    whyPl: 'Miedź szybko odbiera ciepło ze strefy spoiny, a docisk '
        'dodatkowo trzyma blachy.',
    whyEn: 'Copper draws heat quickly from the weld zone, and the clamp also '
        'holds the sheets.',
    elements: {DistortionElement.plateButt, DistortionElement.tankShell},
    kinds: {DistortionKind.buckling},
    source: _lincoln,
  ),
  DistortionMeasure(
    id: 'process',
    titlePl: 'Szybszy proces',
    titleEn: 'A faster process',
    howPl: 'Jeśli WPS pozwala: MIG zamiast MMA, proces zmechanizowany o dużej '
        'wydajności i prędkości zamiast ręcznego. Spawanie gazowe daje '
        'zwykle większe odkształcenie kątowe niż łukowe.',
    howEn: 'If the WPS allows: MIG instead of MMA, a mechanised high '
        'deposition, high speed process instead of manual welding. Gas '
        'welding usually gives more angular distortion than arc welding.',
    whyPl: 'Krótszy czas spawania to mniej metalu wokół spoiny, który zdąży '
        'się nagrzać i rozszerzyć.',
    whyEn: 'Shorter welding time means less surrounding metal has time to '
        'heat up and expand.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {
      DistortionKind.angular,
      DistortionKind.buckling,
      DistortionKind.bowing,
    },
    source: '$_twi36; $_lincoln',
  ),
  DistortionMeasure(
    id: 'longitudinal',
    titlePl: 'Dodaj naddatek na skurcz wzdłużny',
    titleEn: 'Allow for longitudinal shrinkage',
    howPl: 'Orientacyjnie wg TWI: spoina czołowa ok. 3 mm na 3 m spoiny, '
        'pachwinowa ok. 0,8 mm na 3 m. Dodaj do długości elementu, gdy '
        'spoina biegnie wzdłuż wymiaru.',
    howEn: 'As a rule of thumb per TWI: butt weld about 3 mm per 3 m of weld, '
        'fillet weld about 0.8 mm per 3 m. Add it to the member length when '
        'the weld runs along the dimension.',
    whyPl: 'Spoina wzdłuż elementu skraca go, a spoina poza osią obojętną '
        'skraca tylko jedną stronę — element się wygina.',
    whyEn: 'A weld along the member shortens it, and a weld off the neutral '
        'axis shortens one side only — the member bows.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {DistortionKind.bowing},
    source: '$_twiFaq; $_twi33',
  ),
  DistortionMeasure(
    id: 'peening',
    titlePl: 'Młotkowanie międzyściegowe — tylko za zgodą',
    titleEn: 'Interpass peening — only with approval',
    howPl: 'Nigdy grani i zwykle nie ostatniego ściegu. Przed użyciem uzyskaj '
        'zgodę inżyniera albo zapis w WPS.',
    howEn: 'Never the root run and usually not the final run. Get the '
        'engineer’s approval or a WPS entry before use.',
    whyPl: 'Młotkowanie rozciąga stygnący ścieg i zmniejsza siły skurczu, '
        'ale może ukryć albo wywołać pęknięcie i utwardza powierzchnię.',
    whyEn: 'Peening stretches the cooling run and reduces shrinkage forces, '
        'but it can hide or cause a crack and work-hardens the surface.',
    elements: {DistortionElement.plateButt, DistortionElement.teeFillet},
    kinds: {DistortionKind.gapClosing, DistortionKind.angular},
    source: _lincoln,
  ),
  DistortionMeasure(
    id: 'flame',
    titlePl: 'Prostowanie płomieniem (korekta po spawaniu)',
    titleEn: 'Flame straightening (correction after welding)',
    howPl: 'Stal węglowa i C-Mn: grzej miejscowo najwyżej do ok. 600–650 °C '
        '(ciemnoczerwony żar). Punkty — falowanie cienkiej blachy na '
        'sztywnej ramie: grzej stronę wypukłą, od środka wybrzuszenia na '
        'zewnątrz. Linia — kątowe przy pachwinie: wzdłuż spoiny, po '
        'przeciwnej stronie. Klin — wygięcie: długość klina 2/3 szerokości '
        'blachy, podstawa 1/6 długości klina (typowo ok. 5 mm prostowania na '
        '3 m). Po przerwaniu grzania odczekaj do pełnego ostygnięcia. Stal '
        'nierdzewna, Cr-Mo, stale ulepszane cieplnie: tylko wg WPS i za '
        'zgodą — bez zgody nie prostuj płomieniem. Aluminium: temperatury '
        'wyżej dotyczą stali — aluminium aż do stopienia nie zmienia barwy, '
        'więc żaru nie zobaczysz; tylko wg WPS i z kontrolą temperatury '
        '(termokredki), bo przegrzanie obniża wytrzymałość i odporność na '
        'korozję. Ocynk, farba, inne powłoki: przed grzaniem rozpoznaj '
        'powłokę i usuń ją z zapasem wokół miejsca grzania — dymy cynku '
        '(gorączka metaliczna) i powłok są toksyczne. BHP: odciąg dymów przy '
        'źródle, a gdy nie wystarcza — ochrona dróg oddechowych z '
        'doprowadzeniem powietrza; prace pożarowo niebezpieczne wg zezwolenia '
        'zakładu, gaśnica pod ręką.',
    howEn: 'Carbon and C-Mn steel: heat locally to no more than about '
        '600–650 °C (dull red heat). Spots — buckling of thin sheet on a '
        'stiff frame: heat the convex side, from the centre of the buckle '
        'outwards. Line — angular distortion at a fillet: along the weld, on '
        'the opposite side. Wedge — bowing: wedge length 2/3 of the plate '
        'width, base 1/6 of the wedge length (typically about 5 mm of '
        'straightening in 3 m). If heating is interrupted, let the metal '
        'cool fully before restarting. Stainless, Cr-Mo, quenched and '
        'tempered steels: only per the WPS and with approval — without '
        'approval do not flame straighten. Aluminium: the temperatures above '
        'are for steel — aluminium shows no colour change right up to '
        'melting, so you will not see any glow; only per the WPS and with '
        'temperature control (temperature-indicating crayons), because '
        'overheating lowers its strength and corrosion resistance. '
        'Galvanizing, paint, other coatings: identify the coating before '
        'heating and remove it well clear of the heated spot — zinc fume '
        '(metal fume fever) and coating fumes are toxic. Safety: fume '
        'extraction at the source, and where that is not enough, '
        'air-supplied respiratory protection; hot work under the site '
        'permit, an extinguisher at hand.',
    whyPl: 'Nagrzany obszar ma niską granicę plastyczności i spęcza się na '
        'zimnym otoczeniu, a stygnąc kurczy się i ściąga element. Za wysoka '
        'temperatura zmienia strukturę metalu, a palnik odparowuje powłoki '
        'tak samo jak przy spawaniu i cięciu.',
    whyEn: 'The heated area has a low yield strength and is upset by the cold '
        'surroundings; as it cools it shrinks and pulls the part back. Too '
        'high a temperature changes the metal’s structure, and the torch '
        'vaporises coatings just as welding and cutting do.',
    elements: {
      DistortionElement.plateButt,
      DistortionElement.teeFillet,
      DistortionElement.tankShell,
      DistortionElement.longMember,
    },
    kinds: {
      DistortionKind.angular,
      DistortionKind.bowing,
      DistortionKind.buckling,
    },
    source: '$_twi37; $_aluminium; $_twiFumeFever',
    correction: true,
  ),
];

/// Rodzaje odkształceń sensowne dla [e].
List<DistortionKind> kindsFor(DistortionElement e) => kElementKinds[e]!;

/// Środki dla sytuacji: najpierw zapobieganie, korekta na końcu
/// (kolejność z listy zachowana).
List<DistortionMeasure> measuresFor(DistortionElement e, DistortionKind k) {
  final hits = [
    for (final m in kDistortionMeasures)
      if (m.appliesTo(e, k)) m,
  ];
  return [
    ...hits.where((m) => !m.correction),
    ...hits.where((m) => m.correction),
  ];
}
