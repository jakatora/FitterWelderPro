import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

// ─── Model treści pomocy ────────────────────────────────────────────────────
class ScreenHelp {
  final String titlePl;
  final String titleEn;
  final String bodyPl;
  final String bodyEn;
  final List<HelpStep> stepsPl;
  final List<HelpStep> stepsEn;

  const ScreenHelp({
    required this.titlePl,
    required this.titleEn,
    required this.bodyPl,
    required this.bodyEn,
    this.stepsPl = const [],
    this.stepsEn = const [],
  });
}

class HelpStep {
  final String icon;
  final String text;
  const HelpStep(this.icon, this.text);
}

// ─── Ikona przycisku pomocy ─────────────────────────────────────────────────
class HelpButton extends StatelessWidget {
  final ScreenHelp help;

  const HelpButton({super.key, required this.help});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline_rounded),
      tooltip: context.tr(pl: 'Pomoc', en: 'Help'),
      onPressed: () => _showHelp(context),
    );
  }

  void _showHelp(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final title = isPl ? help.titlePl : help.titleEn;
    final body  = isPl ? help.bodyPl  : help.bodyEn;
    final steps = isPl ? help.stepsPl : help.stepsEn;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HelpSheet(title: title, body: body, steps: steps),
    );
  }
}

// ─── Bottom sheet z treścią ─────────────────────────────────────────────────
class _HelpSheet extends StatelessWidget {
  final String title;
  final String body;
  final List<HelpStep> steps;

  const _HelpSheet({
    required this.title,
    required this.body,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    const kCard   = Color(0xFF141821);
    const kBorder = Color(0xFF2A3140);
    const kOrange = Color(0xFFFF8E1E);
    const kSec    = Color(0xFF9BA3C7);

    return DraggableScrollableSheet(
      initialChildSize: steps.isEmpty ? 0.45 : 0.60,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            // Uchwyt
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Ikona + tytuł
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: kOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.help_outline_rounded,
                      size: 22, color: kOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE7ECF3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Opis
            Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                color: kSec,
                height: 1.55,
              ),
            ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...steps.asMap().entries.map((e) => _StepRow(
                    number: e.key + 1,
                    icon: e.value.icon,
                    text: e.value.text,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String icon;
  final String text;

  const _StepRow({
    required this.number,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    const kOrange = Color(0xFFFF8E1E);
    const kBorder = Color(0xFF2A3140);
    const kSec    = Color(0xFF9BA3C7);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: kOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: Center(
              child: Text(
                icon,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: kSec,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Treści pomocy dla każdego ekranu ──────────────────────────────────────

final kHelpProjects = ScreenHelp(
  titlePl: 'Lista projektów (Cut List)',
  titleEn: 'Projects list (Cut List)',
  bodyPl:
      'Tutaj zarządzasz projektami cut list. Każdy projekt ma przypisane średnicę, grubość ścianki, grupę materiałową i luz montażowy. Do projektu dodajesz segmenty z listami cięć.',
  bodyEn:
      'Here you manage cut list projects. Each project has a diameter, wall thickness, material group and fit-up gap assigned. You add segments with cut lists to a project.',
  stepsPl: [
    HelpStep('➕', 'Kliknij + (góra prawo) aby dodać nowy projekt.'),
    HelpStep('👆', 'Dotknij projektu aby otworzyć jego segmenty i cut listę.'),
    HelpStep('🗑️', 'Przesuń w lewo na projekcie aby go usunąć.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Tap + (top right) to add a new project.'),
    HelpStep('👆', 'Tap a project to open its segments and cut list.'),
    HelpStep('🗑️', 'Swipe left on a project to delete it.'),
  ],
);

final kHelpFitter = ScreenHelp(
  titlePl: 'Projekt — segmenty',
  titleEn: 'Project — segments',
  bodyPl:
      'Widok projektu cut list. Każdy segment to jeden odcinek trasy rurowej ze swoją listą komponentów. Możesz dodawać segmenty, generować BOM i eksportować podsumowanie.',
  bodyEn:
      'The cut list project view. Each segment is one section of the pipe route with its own component list. You can add segments, generate a BOM and export a summary.',
  stepsPl: [
    HelpStep('➕', 'Dodaj nowy segment przyciskiem „Dodaj segment” na dole.'),
    HelpStep('👆', 'Dotknij segmentu aby poprawić komponenty i wymiar ISO.'),
    HelpStep('🗑️', 'Przesuń segment w lewo, aby go usunąć — przez kilka sekund możesz to cofnąć.'),
    HelpStep('📊', 'Ikony u góry: lista materiałowa (BOM), numery wytopów, zdjęcia atestów. „Zakończ CUT LIST” otwiera plan cięcia sztang.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new segment with the "Add segment" button at the bottom.'),
    HelpStep('👆', 'Tap a segment to correct its components and ISO dimension.'),
    HelpStep('🗑️', 'Swipe a segment left to delete it — you can undo it for a few seconds.'),
    HelpStep('📊', 'Top icons: material list (BOM), heat numbers, certificate photos. "Finish CUT LIST" opens the bar cutting plan.'),
  ],
);

final kHelpSegmentBuilder = ScreenHelp(
  titlePl: 'Budowniczy segmentu',
  titleEn: 'Segment builder',
  bodyPl:
      'Tutaj budujesz segment rury z komponentów. Dodaj kolano, redukcję, trójnik lub zawór — aplikacja automatycznie obliczy długości cięć i gap między elementami.',
  bodyEn:
      'Here you build a pipe segment from components. Add an elbow, reducer, tee or valve — the app automatically calculates cut lengths and the fit-up gap between elements.',
  stepsPl: [
    HelpStep('➕', 'Dotykaj przycisków palety w kolejności: KOMPONENT → Rura → KOMPONENT (albo Open end na początku lub końcu). Brakujący komponent zapiszesz od razu w bibliotece.'),
    HelpStep('🎯', 'Po wyborze komponentu wskaż, do którego miejsca (oś, czoło bliskie, czoło dalekie) sięga wymiar ISO.'),
    HelpStep('✖️', 'X na elemencie sekwencji usuwa go (z opcją Cofnij).'),
    HelpStep('📏', 'Wpisz wymiar ISO — aplikacja przeliczy CUT rury.'),
    HelpStep('✅', 'Zapisz segment, aby dodać go do projektu.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Tap the palette buttons in order: COMPONENT → Pipe → COMPONENT (or Open end at the start or end). A missing component is saved to the library right away.'),
    HelpStep('🎯', 'After picking a component, choose where the ISO dimension ends on it (axis, near face, far face).'),
    HelpStep('✖️', 'The X on a sequence item removes it (with Undo).'),
    HelpStep('📏', 'Enter the ISO dimension — the app calculates the pipe CUT.'),
    HelpStep('✅', 'Save the segment to add it to the project.'),
  ],
);

final kHelpComponentLibrary = ScreenHelp(
  titlePl: 'Biblioteka komponentów',
  titleEn: 'Component library',
  bodyPl:
      'Twój katalog prefabrykowanych komponentów rurowych: kolana, redukcje, trójniki, zawory, kołnierze. Każdy komponent ma wymiary (OD, długość, promień, typ punktu ISO) używane do obliczeń.',
  bodyEn:
      'Your catalogue of prefabricated pipe components: elbows, reducers, tees, valves, flanges. Each component has dimensions (OD, length, radius, ISO reference point) used for calculations.',
  stepsPl: [
    HelpStep('➕', 'Dodaj nowy komponent przyciskiem + (góra prawo). Dla redukcji podaj oba końce i długość H — przycisk podpowie H z ASME B16.9.'),
    HelpStep('✏️', 'Dotknij komponentu aby poprawić jego wymiary. Zapisane segmenty nie przeliczają się same — aplikacja pokaże, które otworzyć i zapisać ponownie.'),
    HelpStep('🗑️', 'Ikona kosza usuwa wpis. Wpisu użytego w segmencie nie da się usunąć — można go tylko poprawić.'),
    HelpStep('🔍', 'Filtruj listę wpisując typ, materiał lub średnicę w polu wyszukiwania.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new component with the + button (top right). For a reducer enter both ends and the length H — a button suggests H from ASME B16.9.'),
    HelpStep('✏️', 'Tap a component to correct its dimensions. Saved segments are not recomputed by themselves — the app lists which ones to open and save again.'),
    HelpStep('🗑️', 'The bin icon deletes an entry. An entry used by a segment cannot be deleted — only corrected.'),
    HelpStep('🔍', 'Filter the list by typing a type, material or diameter in the search field.'),
  ],
);

final kHelpCutListSummary = ScreenHelp(
  titlePl: 'Podsumowanie cut list (BOM)',
  titleEn: 'Cut list summary (BOM)',
  bodyPl:
      'Zestawienie wszystkich materiałów dla projektu. Widać tu całkowite długości cięć rur z podziałem na odcinki, łączną ilość komponentów i możliwość eksportu do PDF.',
  bodyEn:
      'Bill of materials summary for the project. It shows total pipe cut lengths broken down by spool, total component quantities and a PDF export option.',
  stepsPl: [
    HelpStep('📋', 'Przejrzyj listę cięć — każdy wiersz to jeden odcinek rury.'),
    HelpStep('📊', 'Sekcja BOM pokazuje łączne ilości kolan, redukcji i innych komponentów.'),
    HelpStep('📤', 'Użyj przycisku eksport aby zapisać zestawienie do PDF.'),
  ],
  stepsEn: [
    HelpStep('📋', 'Review the cut list — each row is one pipe spool.'),
    HelpStep('📊', 'The BOM section shows total quantities of elbows, reducers and other components.'),
    HelpStep('📤', 'Use the export button to save the summary as a PDF.'),
  ],
);

final kHelpFitterTools = ScreenHelp(
  titlePl: 'Kalkulatory — Monter',
  titleEn: 'Calculators — Fitter',
  bodyPl:
      'Zestaw kalkulatorów geometrycznych dla monterów rur. Przełączaj się między zakładkami: Cięcie pod spadek, Cięcie kolanka, Obrót kolanka, Wstawka, Redukcja, Ciężar rury, Fazowanie i Dylatacja.',
  bodyEn:
      'A set of geometry calculators for pipe fitters. Switch between tabs: Slope cut, Elbow cut, Elbow rotation, Insert, Reducer, Pipe weight, Bevel and Thermal expansion.',
  stepsPl: [
    HelpStep('📐', 'Cięcie pod spadek — jedno cięcie skośne końca rury: Δh = D × tan α; kąt piły podany od cięcia prostopadłego (skala 0°) i na skali 90°.'),
    HelpStep('✂️', 'Cięcie kolanka — skróć kolano 90° lub 45° do kąta docelowego z pomiaru taśmą po łukach.'),
    HelpStep('🔄', 'Obrót kolanka — zamień obrót w % lub ° na długość łuku do odmierzenia po obwodzie rury.'),
    HelpStep('📏', 'Wstawka — rura MIĘDZY DWOMA KOLANAMI w odsadzce: travel − 2 × take-out − 2 × szczelina.'),
    HelpStep('🗜️', 'Redukcja — gdzie uciąć redukcję koncentryczną, żeby uzyskać pośrednie OD.'),
    HelpStep('⚖️', 'Ciężar rury — kg/m, masa odcinka i partii (SS 316L 8,0 / 304L 7,9 / CS 7,85 kg/dm³).'),
    HelpStep('🔧', 'Fazowanie — V lub X; kąt jako kąt rowka (EN ISO 9692-1, np. 60°) albo na stronę (ASME B16.25, 37,5°).'),
    HelpStep('🌡️', 'Dylatacja — wydłużenie cieplne ΔL = α × L × ΔT (L w metrach).'),
  ],
  stepsEn: [
    HelpStep('📐', 'Slope cut — single angled cut of the pipe end: Δh = D × tan α; saw angle given off square (0° scale) and on a 90° scale.'),
    HelpStep('✂️', 'Elbow cut — trim a 90° or 45° elbow to the target angle from tape measurements along the arcs.'),
    HelpStep('🔄', 'Elbow rotation — turn a rotation in % or ° into the arc length to mark along the pipe circumference.'),
    HelpStep('📏', 'Insert — pipe BETWEEN TWO ELBOWS in an offset: travel − 2 × take-out − 2 × gap.'),
    HelpStep('🗜️', 'Reducer — where to cut a concentric reducer to get an intermediate OD.'),
    HelpStep('⚖️', 'Pipe weight — kg/m, piece and batch mass (SS 316L 8.0 / 304L 7.9 / CS 7.85 kg/dm³).'),
    HelpStep('🔧', 'Bevel — V or X; angle as the groove angle (EN ISO 9692-1, e.g. 60°) or per side (ASME B16.25, 37.5°).'),
    HelpStep('🌡️', 'Expansion — thermal growth ΔL = α × L × ΔT (L in metres).'),
  ],
);

final kHelpDnMm = ScreenHelp(
  titlePl: 'Tablica DN ↔ OD (mm) + NPS',
  titleEn: 'DN ↔ OD (mm) + NPS table',
  bodyPl:
      'Tabela przeliczeniowa nominalna: DN (metryczne), NPS (calowe) i rzeczywista zewnętrzna średnica OD w milimetrach. Wpisz wartość w pole DN lub OD aby przefiltrować tabelę.',
  bodyEn:
      'Nominal conversion table: DN (metric), NPS (inch) and actual outside diameter OD in millimetres. Enter a value in the DN or OD field to filter the table.',
  stepsPl: [
    HelpStep('🔢', 'Wpisz DN aby znaleźć odpowiednie OD i NPS.'),
    HelpStep('📐', 'Wpisz OD (mm) aby znaleźć najbliższy DN/NPS (tolerancja ±0.25 mm).'),
    HelpStep('🔍', 'Pole tekstowe filtruje po NPS, np. "1 1/2".'),
  ],
  stepsEn: [
    HelpStep('🔢', 'Enter DN to find the corresponding OD and NPS.'),
    HelpStep('📐', 'Enter OD (mm) to find the closest DN/NPS (tolerance ±0.25 mm).'),
    HelpStep('🔍', 'Text field filters by NPS, e.g. "1 1/2".'),
  ],
);

final kHelpPipeRoute = ScreenHelp(
  titlePl: 'Trasa rur – 2 kolana 90°',
  titleEn: 'Pipe route – 2 × 90° elbows',
  bodyPl:
      'Oblicza długości odcinków rur dla trasy z 2 kolanami 90°: poziomy X → pionowy ΔH → poziomy Y (3 odcinki, 4 spoiny). Odejmuje wymiar kolanka (takeout) R; łuki kolan po osi to 2 × π·R/2.',
  bodyEn:
      'Calculates pipe spool lengths for a route with 2 × 90° elbows: horizontal X → vertical ΔH → horizontal Y (3 segments, 4 welds). Subtracts the elbow takeout R; the elbow arcs along the centreline are 2 × π·R/2.',
  stepsPl: [
    HelpStep('📏', 'Wpisz H1 i H2 — poziomy startowy i końcowy (różnica = ΔH).'),
    HelpStep('↔️', 'Wpisz X i Y — odległości poziome.'),
    HelpStep('🔄', 'Wybierz DN kolan — R = wymiar A kolana LR 90° wg ASME B16.9 — albo wpisz take-out z karty kolana. R nie startuje od 0: R = 0 to wymiary osiowe, nie długości cięcia.'),
    HelpStep('🔥', 'Wpisz szczelinę spoiny g — odejmowana przy każdej spoinie kolana (opcjonalnie też na końcach trasy).'),
    HelpStep('✅', 'Kliknij Oblicz — otrzymasz 3 długości do cięcia: X−R−g, ΔH−2R−2g, Y−R−g.'),
  ],
  stepsEn: [
    HelpStep('📏', 'Enter H1 and H2 — start and end elevations (difference = ΔH).'),
    HelpStep('↔️', 'Enter X and Y — horizontal distances.'),
    HelpStep('🔄', 'Pick the elbow DN — R = dimension A of the LR 90° elbow per ASME B16.9 — or type the take-out from the datasheet. R does not start at 0: R = 0 means centreline dimensions, not cut lengths.'),
    HelpStep('🔥', 'Enter the weld gap g — deducted at every elbow weld (optionally at the route ends too).'),
    HelpStep('✅', 'Tap Calculate — you get 3 cut lengths: X−R−g, ΔH−2R−2g, Y−R−g.'),
  ],
);

final kHelpRollingOffset = ScreenHelp(
  titlePl: 'Rolling Offset',
  titleEn: 'Rolling Offset',
  bodyPl:
      'Oblicza Travel — odległość między punktami przecięcia osi kolan — dla przesunięcia pionowego (Rise) i bocznego (Spread). Wzory: True Offset = √(Rise² + Spread²), Travel = True Offset / sin(θ). Travel to nie długość cięcia — tę policzy ekran, gdy podasz DN kolan (ASME B16.9 LR) i szczelinę.',
  bodyEn:
      'Calculates Travel — the distance between elbow centreline intersection points — for vertical (Rise) and lateral (Spread) offsets. Formulas: True Offset = √(Rise² + Spread²), Travel = True Offset / sin(θ). Travel is not a cut length — the screen gives one when you enter the elbow DN (ASME B16.9 LR) and the gap.',
  stepsPl: [
    HelpStep('↕️', 'Rise — odchylenie pionowe (w mm).'),
    HelpStep('↔️', 'Spread — odchylenie poziome (w mm).'),
    HelpStep('🔄', 'Kąt kolanka — wybierz 45°, 30°, 60° lub podaj własny.'),
    HelpStep('📐', 'Wynik: True Offset, Travel, Run i Multiplier.'),
    HelpStep('🧭', 'Kąt obrotu kolana: od pionu = atan(Spread / Rise), od poziomu = atan(Rise / Spread).'),
    HelpStep('✂️', 'Opcjonalnie: podaj DN kolan i szczelinę — długość cięcia = Travel − 2 × take-out − 2 × szczelina.'),
  ],
  stepsEn: [
    HelpStep('↕️', 'Rise — vertical deviation (in mm).'),
    HelpStep('↔️', 'Spread — horizontal deviation (in mm).'),
    HelpStep('🔄', 'Elbow angle — choose 45°, 30°, 60° or enter your own.'),
    HelpStep('📐', 'Results: True Offset, Travel, Run and Multiplier.'),
    HelpStep('🧭', 'Elbow roll angle: from vertical = atan(Spread / Rise), from horizontal = atan(Rise / Spread).'),
    HelpStep('✂️', 'Optional: enter the elbow DN and the gap — cut length = Travel − 2 × take-out − 2 × gap.'),
  ],
);

final kHelpPipeSlope = ScreenHelp(
  titlePl: 'Spadek rury',
  titleEn: 'Pipe slope',
  bodyPl:
      'Przelicza spadek rury między formatami: procent (%), milimetry na metr (mm/m) i kąt w stopniach. Możesz też obliczyć rise (wysokość) dla danej długości i spadku.',
  bodyEn:
      'Converts pipe slope between formats: percent (%), millimetres per metre (mm/m) and angle in degrees. You can also calculate rise (height) for a given length and slope.',
  stepsPl: [
    HelpStep('📐', 'Wybierz tryb: długość→rise, rise→długość lub slope ze znanych wartości.'),
    HelpStep('🔢', 'Wpisz dane i kliknij Oblicz.'),
    HelpStep('📊', 'Wynik pokazuje slope w %, mm/m i stopniach równocześnie.'),
  ],
  stepsEn: [
    HelpStep('📐', 'Choose mode: length→rise, rise→length or slope from known values.'),
    HelpStep('🔢', 'Enter the data and tap Calculate.'),
    HelpStep('📊', 'Result shows slope in %, mm/m and degrees simultaneously.'),
  ],
);

final kHelpSaddleCut = ScreenHelp(
  titlePl: 'Siodło 90° — tabela (wycięcie siodłowe)',
  titleEn: 'Saddle 90° — table (fish-mouth cut)',
  bodyPl:
      'Profil zewnętrznych powierzchni rur dla centralnego połączenia T pod kątem 90°. Szybka tabela obejmuje 0–90°, a pełny obwód i kopiowanie: 0–360° co 15° (25 punktów z zamknięciem). Bez grubości ścianki, ukosowania, szczeliny i naddatków — sprawdź dokumentację przed cięciem.',
  bodyEn:
      'Outside-surface profile for a centred 90° T-junction. The quick table covers 0–90°; the full circumference and copy cover 0–360° every 15° (25 points including closure). Wall thickness, bevel, gap and allowances are excluded — check project requirements before cutting.',
  stepsPl: [
    HelpStep('📏', 'Wpisz OD rury głównej (header) i rury odgałęzieniowej (branch).'),
    HelpStep('📊', 'Na obwodzie mierz po łuku od 0°. Głębokość odmierzaj osiowo od płaszczyzny prostopadłej do osi, przechodzącej przez najdłuższe punkty, w stronę korpusu rury.'),
    HelpStep('💡', '0° i 180° leżą w płaszczyźnie obu osi — maksymalne wycięcie. 90° i 270° to najdłuższe końce rury (głębokość 0 mm). 360° zamyka obwód w 0°.'),
    HelpStep('🖨️', 'Odgałęzienie pod innym kątem niż 90° albo szablon 1:1 do owinięcia rury — narzędzie „Szablon siodła do druku”.'),
  ],
  stepsEn: [
    HelpStep('📏', 'Enter the OD of the header pipe and the branch pipe.'),
    HelpStep('📊', 'Measure circumference distance along the arc from 0°. Measure depth axially from the plane perpendicular to the axis through the longest points, towards the pipe body.'),
    HelpStep('💡', '0° and 180° lie in the plane of both axes — maximum cutback. 90° and 270° are the longest pipe-end points (depth 0 mm). 360° closes the circumference at 0°.'),
    HelpStep('🖨️', 'Branch at an angle other than 90°, or a 1:1 template to wrap the pipe — use the “Printable saddle template” tool.'),
  ],
);

final kHelpIsoNotebook = ScreenHelp(
  titlePl: 'Zeszyt ISO',
  titleEn: 'ISO Notebook',
  bodyPl:
      'Narysuj pełny rysunek izometryczny rurociągu: rury z wymiarami, kształtki, zawory, spoiny, podpory, instrumenty oraz opisy (strzałka północy, kierunek przepływu, numer linii, rzędne). Na końcu skopiuj zestawienie materiałowe (BOM).',
  bodyEn:
      'Draw a complete piping isometric: dimensioned pipe runs, fittings, valves, welds, supports, instruments and annotations (north arrow, flow direction, line number, elevations). Then copy the material list (BOM).',
  stepsPl: [
    HelpStep('📏', 'RURA — przeciągnij po siatce, a po puszczeniu wpisz wymiar odcinka.'),
    HelpStep('🔢', 'Dotknij narysowanego odcinka aby wpisać lub poprawić wymiar.'),
    HelpStep('🔩', 'KSZTAŁTKI — kolana, trójniki, zawory, kołnierze, spoiny: dotknij węzła siatki.'),
    HelpStep('🔄', 'Dotknij wstawionej kształtki ponownie aby ją obrócić o 60°.'),
    HelpStep('🧭', 'OPISY — strzałka północy, kierunek przepływu, tekst (nr linii, rzędna).'),
    HelpStep('📋', 'Przycisk kopiowania w pasku górnym tworzy zestawienie: wymiary + BOM.'),
    HelpStep('🗑️', 'Przytrzymaj dowolny element aby go usunąć.'),
    HelpStep('💾', 'Szkic zapisuje się sam po każdej zmianie — wyjście z ekranu, telefon czy rozładowana bateria go nie skasują. Po powrocie otwiera się ostatni szkic.'),
    HelpStep('📂', 'Menu „Szkice” (ikona folderu w pasku górnym): „Nowy szkic” zaczyna czystą kartkę, a poprzedni zostaje w pamięci; „Zapisane szkice” otwiera lub usuwa wcześniejsze.'),
    HelpStep('↔️', 'Menu „Szkice” → „Szczelina spoiny”: ustaw szczelinę (gap) dla tego szkicu — domyślnie 0. CUT każdej rury jest krótszy o szczelinę × liczbę spawanych końców (koniec z kształtką), tak samo jak w kreatorze segmentu; wolny koniec rury jest bez szczeliny.'),
    HelpStep('✂️', 'Menu „Szkice” → „Utwórz projekt CUT”: rury z wymiarem stają się segmentami nowego projektu w kolejności trasy, z tym samym CUT co w zeszycie i z szczeliną szkicu. W oknie potwierdź nazwę, DN, OD, ściankę, sztangę i rzaz; rury bez wymiaru albo z niepewnym odliczeniem są wypisane jako „do uzupełnienia” i nie trafiają do projektu. Po utworzeniu otwiera się projekt.'),
  ],
  stepsEn: [
    HelpStep('📏', 'PIPE tool — drag on the grid, then enter the segment dimension on release.'),
    HelpStep('🔢', 'Tap a drawn segment to enter or correct its dimension.'),
    HelpStep('🔩', 'FITTINGS — elbows, tees, valves, flanges, welds: tap a grid node.'),
    HelpStep('🔄', 'Tap a placed fitting again to rotate it by 60°.'),
    HelpStep('🧭', 'ANNOTATIONS — north arrow, flow direction and free text (line no., elevation).'),
    HelpStep('📋', 'The copy button in the top bar builds a summary: dimensions + BOM.'),
    HelpStep('🗑️', 'Long-press any element to delete it.'),
    HelpStep('💾', 'The sketch saves itself after every change — leaving the screen, a phone call or a flat battery won\'t lose it. The last sketch opens again when you come back.'),
    HelpStep('📂', '“Sketches” menu (folder icon in the top bar): “New sketch” starts a clean sheet and keeps the previous one; “Saved sketches” opens or deletes earlier ones.'),
    HelpStep('↔️', '“Sketches” menu → “Weld gap”: set the root gap for this sketch — 0 by default. Each pipe\'s CUT gets shorter by gap × number of welded ends (an end with a fitting), the same as in the segment builder; a free pipe end has no gap.'),
    HelpStep('✂️', '“Sketches” menu → “Create CUT project”: dimensioned pipes become the segments of a new project in route order, with the same CUT as in the notebook and the sketch\'s gap. Confirm the name, DN, OD, wall, stock length and kerf in the window; pipes without a dimension or with an uncertain deduct are listed as “to complete” and left out. The project opens once created.'),
  ],
);

final kHelpWelderPipes = ScreenHelp(
  titlePl: 'Parametry spawania — Rury',
  titleEn: 'Welding parameters — Pipes',
  bodyPl:
      'Zestawy parametrów spawania TIG dla rur: prąd (AMP), gazy osłonowe, dane startowe z aplikacji i Twoje własne zestawy. To wartości orientacyjne — wiąże WPS; swoje WPS prowadź w Bibliotece WPS (menu SPAWACZ).',
  bodyEn:
      'TIG welding parameter sets for pipes: current (AMP), shielding gases, starter data shipped with the app and your own sets. These are guide values — the WPS is binding; keep your WPS in the WPS library (WELDER menu).',
  stepsPl: [
    HelpStep('📋', 'AMP — prąd z listy „Startowe” (ta sama rura = ta sama liczba, między punktami interpolacja, poza danymi brak wyniku); elektroda i gaz palnika z tych samych tabel co ekran Wolfram. Stal węglowa bez własnych punktów = nierdzewna / 0,9.'),
    HelpStep('💨', 'Gazy — czas przedmuchu, szacunkowy O₂ i wyloty. „Złoty środek” Q celuje w ok. 2 m/s na wylotach (heurystyka), więc nie wywołuje ostrzeżenia o back-pressure. Minutnik pre-purge działa jak Timer spawacza: alarm, praca w tle, komunikat na cały ekran.'),
    HelpStep('✅', 'Startowe — dane dostarczone z aplikacją, orientacyjne (to nie są WPS Twojego zakładu). Swoje WPS wpisz albo zaimportuj w Bibliotece WPS.'),
    HelpStep('👤', 'Moje — własne zestawy parametrów zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('📋', 'AMP — current from the “Starter” list (same pipe = same number, interpolated between points, no result outside the data); electrode and torch gas from the same tables as the Tungsten screen. Carbon steel without its own points = stainless / 0.9.'),
    HelpStep('💨', 'Gases — pre-purge time, estimated O₂ and outlets. The “golden middle” Q aims at about 2 m/s through the outlets (a heuristic), so it never triggers the back-pressure warning. The pre-purge timer works like the welder Timer: alarm, runs in the background, full-screen message.'),
    HelpStep('✅', 'Starter — data shipped with the app, for guidance (not your workshop\'s WPS). Enter or import your WPS in the WPS library.'),
    HelpStep('👤', 'Mine — your own parameter sets saved locally.'),
  ],
);

final kHelpWelderTanks = ScreenHelp(
  titlePl: 'Parametry spawania — Zbiorniki',
  titleEn: 'Welding parameters — Tanks',
  bodyPl:
      'Tandem TIG na zbiornikach SS: dwóch spawaczy po obu stronach ścianki — palnik zewnętrzny z drutem i wewnętrzny bez drutu. Prądy to wartości startowe z danych użytkownika, nie kwalifikacja — wiąże WPS.',
  bodyEn:
      'Tandem TIG on SS tanks: two welders on both sides of the wall — the outer torch with wire and the inner torch without. The currents are starting values from user data, not a qualification — the WPS is binding.',
  stepsPl: [
    HelpStep('🔀', 'Tandem — prądy zewn./wewn. z grubości t1/t2, pozycji i złącza. Liczba pojawia się tylko w zakresie punktów startowych (interpolacja); poza nim ekran pisze „brak danych dla tej grubości” — ustal prąd na próbce.'),
    HelpStep('⚠️', 'Gdy w danych prąd maleje przy rosnącej grubości, wynik dostaje ostrzeżenie.'),
    HelpStep('📋', 'Startowe — lista punktów startowych (tylko odczyt).'),
  ],
  stepsEn: [
    HelpStep('🔀', 'Tandem — OUT/IN currents from wall t1/t2, position and joint. A number appears only within the range of the starting points (interpolation); outside it the screen says “no data for this thickness” — set the current on a test piece.'),
    HelpStep('⚠️', 'When the data show the current dropping as thickness grows, the result gets a warning.'),
    HelpStep('📋', 'Starting points — list of starting points (read only).'),
  ],
);

final kHelpWelderTools = ScreenHelp(
  titlePl: 'Gaz, formowanie i timer',
  titleEn: 'Gas, purge and timer',
  bodyPl:
      'Kalkulatory spawacza w zakładkach: Zużycie gazu, Formowanie O₂ (purge), Timer i Przelicznik ciśnienia. Heat input i podgrzewanie liczy osobny ekran „Heat input i CE”.',
  bodyEn:
      'Welder calculators in tabs: Gas consumption, O₂ purge, Timer and Pressure converter. Heat input and preheat are on the separate “Heat input and CE” screen.',
  stepsPl: [
    HelpStep('🧪', 'Gaz — zużycie gazu osłonowego i formującego na projekt oraz liczba butli (pojemność wodna × ciśnienie, z rezerwą).'),
    HelpStep('💨', 'O₂ Purge — szacunkowy czas i ilość gazu do wypłukania rury do zadanego ppm O₂; sprawdź analizatorem przed spawaniem.'),
    HelpStep('⏱️', 'Timer — spawanie, chłodzenie między ściegami (przypomnienie o max temp. międzyściegowej z WPS) i formowanie. Liczy dalej po zmianie zakładki i wyjściu z ekranu; na koniec wibruje, daje sygnał i pokazuje komunikat na cały ekran, a ekran nie gaśnie w trakcie odliczania. Gdy aplikacja jest w tle — powiadomienie (o zgodę pyta przy pierwszym odliczaniu). Zmiana trybu w trakcie odliczania pyta „Przerwać odliczanie?”. Z zakładki O₂ Purge można od razu uruchomić odliczanie purge.'),
    HelpStep('🔁', 'Ciśnienie — przelicznik bar / MPa / kPa / PSI / atm / kgf/cm².'),
  ],
  stepsEn: [
    HelpStep('🧪', 'Gas — shielding and purge gas for a project and the number of cylinders (water capacity × pressure, with reserve).'),
    HelpStep('💨', 'O₂ Purge — estimated time and gas to purge a pipe down to a target ppm O₂; verify with an analyser before welding.'),
    HelpStep('⏱️', 'Timer — welding, cooldown between passes (reminder of the max interpass temperature from the WPS) and purge. Keeps running when you switch tabs or leave the screen; at the end it vibrates, sounds and shows a full-screen message, and the screen stays on while counting down. With the app in the background — a notification (permission is asked at the first countdown). Changing the mode during a countdown asks “Stop the countdown?”. The O₂ Purge tab can start the purge countdown directly.'),
    HelpStep('🔁', 'Pressure — converter bar / MPa / kPa / PSI / atm / kgf/cm².'),
  ],
);

final kHelpHeatInput = ScreenHelp(
  titlePl: 'Heat input i CE',
  titleEn: 'Heat input and CE',
  bodyPl:
      'Energia liniowa (heat input) wg EN 1011-1 (z η) albo ASME IX (bez η) oraz szacunkowa temperatura podgrzewania ze składu chemicznego i grubości. Wynik jest pomocniczy: wiąże temperatura z WPS, nie niższa niż minimum kodowe; normatywne metody obliczeniowe to EN 1011-2 zał. C.',
  bodyEn:
      'Heat input per EN 1011-1 (with η) or ASME IX (no η), plus an estimated preheat temperature from chemistry and thickness. The result is an aid: the WPS temperature is binding, never below the code minimum; the normative calculation methods are EN 1011-2 Annex C.',
  stepsPl: [
    HelpStep('🌡️', 'Heat input — kJ/mm z napięcia, prądu i prędkości spawania; η wynika z procesu, a „η z WPS” wpisz tylko, gdy WPS podaje inną wartość. Prędkość można wziąć z pomiaru: długość ściegu + czas jarzenia. Wynik i zakres WPS także w kJ/in i J/in. Gdy danych nie da się policzyć, wynik to „—”.'),
    HelpStep('📏', 'Zakres WPS — wpisz min i/lub max z Twojego WPS albo „Wybierz WPS” z Biblioteki WPS (ustawia zakres i normę liczenia), żeby zobaczyć, czy wynik mieści się w zakresie.'),
    HelpStep('🔥', 'Preheat / CE — szacunkowa temperatura podgrzewania (Seferian i reguła CE) z CE i grubości. Wiąże WPS / EN 1011-2 / minimum kodowe (ASME B31.3 Tab. 330.1.1 po wyborze gatunku: wydanie ≥ 2014, równe B31.1, oraz dla porównania wydanie 2012). Dla stali Cr-Mo i P91 (P-No 4, 5A, 5B, 5C, 15E) metody z CE są ukryte — tylko minimum kodowe i WPS.'),
    HelpStep('📋', 'DN / SCH — wybór rury wpisuje ściankę z tabeli ASME B36.10/19 do pola „Grubość” (z Cofnij).'),
    HelpStep('📐', 'EN 1011-2 zał. C, metoda B — Tp z CET, grubości, wodoru HD (wybierz 5/10/15) i energii liniowej Q z pierwszej zakładki; poza zakresem stosowania metody wynik to „—” z przyczyną.'),
    HelpStep('🧾', 'Gatunek z listy uzupełnia typową chemię — do obliczeń z atestu wpisz skład z atestu 3.1.'),
  ],
  stepsEn: [
    HelpStep('🌡️', 'Heat input — kJ/mm from voltage, current and travel speed; η follows the process, enter “η from WPS” only if the WPS states another value. Travel speed can come from a measurement: bead length + arc time. Result and WPS range also in kJ/in and J/in. When the inputs cannot be calculated, the result is “—”.'),
    HelpStep('📏', 'WPS range — enter min and/or max from your WPS or “Pick WPS” from the WPS library (sets the range and the calculation standard) to see whether the result is within range.'),
    HelpStep('🔥', 'Preheat / CE — estimated preheat temperature (Seferian and the CE rule) from CE and thickness. The WPS / EN 1011-2 / code minimum is binding (ASME B31.3 Tab. 330.1.1 once a grade is picked: edition ≥ 2014, equal to B31.1, plus the 2012 edition for comparison). For Cr-Mo and P91 steels (P-No 4, 5A, 5B, 5C, 15E) the CE methods are hidden — only the code minimum and the WPS.'),
    HelpStep('📋', 'DN / SCH — picking a pipe puts the ASME B36.10/19 wall into the “Thickness” field (with Undo).'),
    HelpStep('📐', 'EN 1011-2 Annex C, method B — Tp from CET, thickness, hydrogen HD (pick 5/10/15) and the heat input Q from the first tab; outside the method\'s scope the result is “—” with the reason.'),
    HelpStep('🧾', 'A grade from the list fills typical chemistry — for an MTR-based result type the chemistry from the 3.1 certificate.'),
  ],
);

final kHelpWeldJournal = ScreenHelp(
  titlePl: 'Dziennik spoin',
  titleEn: 'Weld journal',
  bodyPl:
      'Rejestr spoin do odbioru: numer, ISO i rewizja, linia, spool, WPS, spawacz (grań i lico), materiał, spoiwo, parametry, badania NDT (VT/PT/MT/RT/UT), naprawy R1/R2, PWHT i odbiór inspektora. Każda zmiana trafia do historii spoiny.',
  bodyEn:
      'A weld register for acceptance: number, ISO and revision, line, spool, WPS, welder (root and cap), material, filler, parameters, NDT (VT/PT/MT/RT/UT), R1/R2 repairs, PWHT and inspector sign-off. Every change is kept in the weld history.',
  stepsPl: [
    HelpStep('➕', 'Dodaj spoinę przyciskiem +. „Zapisz i następna” kopiuje dane i podbija numer.'),
    HelpStep('✏️', 'Dotknij spoiny, aby ją edytować; historia zmian jest na dole karty.'),
    HelpStep('📐', 'WPS wybierz z Biblioteki WPS (ikona przy polu). Przy zapisie spoina jest porównywana z WPS i z uprawnieniami spawacza w dniu spawania — niezgodność to ostrzeżenie („Zapisz mimo to” trafia do historii), nie blokada. Znaczki „poza WPS” / „spawacz bez ważnych uprawnień” widać na liście i na karcie.'),
    HelpStep('🟢', 'Status zmieniasz z listy wyboru z potwierdzeniem — nie jednym dotknięciem.'),
    HelpStep('🔧', 'Naprawa: menu ⋮ przy spoinie → Naprawa (spoina wraca do badania).'),
    HelpStep('🗑️', 'Usunięcie jest odwracalne: filtr „Pokaż usunięte” → Przywróć.'),
    HelpStep('📤', 'Eksport PDF/CSV obejmuje dokładnie to, co widać po filtrach; PDF ma blok podpisów.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a weld with +. "Save and next" copies the data and bumps the number.'),
    HelpStep('✏️', 'Tap a weld to edit it; the change history is at the bottom of the card.'),
    HelpStep('📐', 'Pick the WPS from the WPS library (icon next to the field). On save the weld is checked against the WPS and the welder\'s qualifications on the weld date — a mismatch is a warning ("Save anyway" goes to the history), not a block. "Outside WPS" / "welder not qualified" badges show on the list and the card.'),
    HelpStep('🟢', 'Status changes through a confirmed choice — never a single tap.'),
    HelpStep('🔧', 'Repair: ⋮ menu on the weld → Repair (the weld goes back to testing).'),
    HelpStep('🗑️', 'Deleting is reversible: "Show deleted" filter → Restore.'),
    HelpStep('📤', 'PDF/CSV export covers exactly what the filters show; the PDF has a sign-off block.'),
  ],
);

final kHelpMaterialList = ScreenHelp(
  titlePl: 'Lista materiałów',
  titleEn: 'Material list',
  bodyPl:
      'Zestawienie wszystkich materiałów dla segmentu lub projektu. Pokazuje rury, komponenty i ich ilości. Możesz wyeksportować listę lub skopiować do schowka.',
  bodyEn:
      'A material breakdown for a segment or project. Shows pipes, components and their quantities. You can export the list or copy it to the clipboard.',
  stepsPl: [
    HelpStep('📋', 'Każdy wiersz to jeden typ elementu z ilością i jednostką.'),
    HelpStep('📤', 'Eksportuj przyciskiem w górnym prawym rogu (PDF lub schowek).'),
  ],
  stepsEn: [
    HelpStep('📋', 'Each row is one type of element with quantity and unit.'),
    HelpStep('📤', 'Export with the button in the top right (PDF or clipboard).'),
  ],
);

final kHelpTandemMenu = ScreenHelp(
  titlePl: 'Tandem TIG — Menu',
  titleEn: 'Tandem TIG — Menu',
  bodyPl:
      'Moduł Tandem TIG. Znajdziesz tu kalkulator parametrów tandem, bibliotekę zapisanych zestawów i Twoje własne parametry do szybkiego dostępu.',
  bodyEn:
      'The Tandem TIG module. Here you find the tandem parameter calculator, a library of saved sets and your own parameters for quick access.',
  stepsPl: [
    HelpStep('🗮', 'Kalkulator — oblicz parametry lead i trail na podstawie materiału i OD.'),
    HelpStep('📚', 'Biblioteka — przeglądaj zestawy zatwierdzone dla różnych aplikacji.'),
    HelpStep('👤', 'Moje parametry — Twoje własne zestawy zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('🗮', 'Calculator — calculate lead and trail parameters based on material and OD.'),
    HelpStep('📚', 'Library — browse sets approved for different applications.'),
    HelpStep('👤', 'My params — your own parameter sets saved locally.'),
  ],
);

final kHelpTandemCalc = ScreenHelp(
  titlePl: 'Kalkulator Tandem TIG',
  titleEn: 'Tandem TIG Calculator',
  bodyPl:
      'Oblicza parametry procesu Tandem TIG (lead + trail) dla spawania zbiorników i dużych przekrojów. Wyniki zawierają sugerowane prądy, napięcia, prędkość spawania i heat input.',
  bodyEn:
      'Calculates Tandem TIG process parameters (lead + trail) for tank and large-section welding. Results include suggested currents, voltages, travel speed and heat input.',
  stepsPl: [
    HelpStep('🔢', 'Wpisz OD, grubość ścianki i materiał.'),
    HelpStep('⚡', 'Wybierz tryb spawania i pozycję.'),
    HelpStep('✅', 'Kliknij Oblicz aby zobaczyć parametry lead i trail.'),
  ],
  stepsEn: [
    HelpStep('🔢', 'Enter OD, wall thickness and material.'),
    HelpStep('⚡', 'Choose the welding mode and position.'),
    HelpStep('✅', 'Tap Calculate to see lead and trail parameters.'),
  ],
);

final kHelpWelderPipeParams = ScreenHelp(
  titlePl: 'Lista parametrów spawania rur',
  titleEn: 'Pipe welding parameters list',
  bodyPl:
      'Lista Twoich własnych zestawów parametrów spawania rur TIG. Każdy zestaw zawiera prąd, napięcie, gaz, przepływ i dodatkowe notatki. Zestawy są przechowywane lokalnie.',
  bodyEn:
      'A list of your own TIG pipe welding parameter sets. Each set contains current, voltage, gas, flow rate and additional notes. Sets are stored locally on the device.',
  stepsPl: [
    HelpStep('➕', 'Dodaj nowy zestaw przyciskiem +.'),
    HelpStep('✏️', 'Dotknij zestawu aby edytować parametry.'),
    HelpStep('🗑️', 'Przesuń w lewo aby usunąć zestaw.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new set with the + button.'),
    HelpStep('✏️', 'Tap a set to edit its parameters.'),
    HelpStep('🗑️', 'Swipe left to delete a set.'),
  ],
);

final kHelpHeatPhotos = ScreenHelp(
  titlePl: 'Heat Numbers — zdjęcia',
  titleEn: 'Heat Numbers — photos',
  bodyPl:
      'Galeria zdjęć certyfikatów materiałowych (heat numbers) przypisanych do projektu. Możesz dodawać, przeglądać i usuwać zdjęcia etykiet materiałowych dla identyfikowalności (traceability).',
  bodyEn:
      'A photo gallery of material certificates (heat numbers) assigned to the project. You can add, view and delete label photos for material traceability.',
  stepsPl: [
    HelpStep('📷', '„Dodaj zdjęcie” → Aparat (zdjęcie etykiety od razu) albo Galeria. Na komputerze — wybór pliku.'),
    HelpStep('💾', 'Zdjęcie jest zmniejszane i zapisywane w aplikacji — trafia do kopii zapasowej.'),
    HelpStep('🗑️', 'Ikona kosza przy zdjęciu usuwa je (nie da się cofnąć).'),
  ],
  stepsEn: [
    HelpStep('📷', '“Add photo” → Camera (shoot the label right away) or Gallery. On a computer — choose a file.'),
    HelpStep('💾', 'The photo is downsized and stored in the app — it is included in the backup.'),
    HelpStep('🗑️', 'The bin icon next to a photo deletes it (cannot be undone).'),
  ],
);

final kHelpProjectComponents = ScreenHelp(
  titlePl: 'Komponenty projektu / Heat',
  titleEn: 'Project components / Heat',
  bodyPl:
      'Numery wytopów (heat numbers) projektu: osobno dla rury każdego segmentu i dla każdej kształtki (kształtka na złączu dwóch segmentów to jeden wiersz). Numery trafiają do PDF i CSV listy cięć oraz do kopii listy materiałowej.',
  bodyEn:
      'The project\'s heat numbers: separately for each segment\'s pipe and for each fitting (a fitting joining two segments is one row). They go into the cut-list PDF and CSV and the copied material list.',
  stepsPl: [
    HelpStep('➕', 'Przycisk + przy wierszu dodaje numer wytopu (można kilka, np. rura z dwóch sztang).'),
    HelpStep('📷', 'W oknie „Dodaj HEAT” zrób zdjęcie etykiety lub atestu (Aparat) albo wybierz z Galerii.'),
    HelpStep('✏️', 'Dotknij numeru, aby go poprawić albo usunąć.'),
    HelpStep('📌', 'Numer jest przypięty do segmentu, nie do jego numeru — po usunięciu segmentu wpis ląduje w sekcji „Bez miejsca”.'),
  ],
  stepsEn: [
    HelpStep('➕', 'The + button on a row adds a heat number (several are fine, e.g. a pipe cut from two bars).'),
    HelpStep('📷', 'In the “Add HEAT” window take a photo of the label or certificate (Camera) or pick one from the Gallery.'),
    HelpStep('✏️', 'Tap a number to correct or delete it.'),
    HelpStep('📌', 'A number is pinned to the segment, not to its number — after the segment is deleted the entry moves to “No place”.'),
  ],
);

final kHelpTandemLibrary = ScreenHelp(
  titlePl: 'Biblioteka — Tandem TIG',
  titleEn: 'Library — Tandem TIG',
  bodyPl:
      'Biblioteka zatwierdzonych zestawów parametrów Tandem TIG. Każdy zestaw zawiera prądy lead i trail, napięcia i prędkość dla danego przekroju i materiału.',
  bodyEn:
      'Library of approved Tandem TIG parameter sets. Each set contains lead and trail currents, voltages and travel speed for the given section and material.',
  stepsPl: [
    HelpStep('📋', 'Przeglądaj zatwierdzone zestawy według materiału i grubości.'),
    HelpStep('👆', 'Dotknij zestawu aby zobaczyć pełne parametry.'),
  ],
  stepsEn: [
    HelpStep('📋', 'Browse approved sets by material and thickness.'),
    HelpStep('👆', 'Tap a set to view the full parameters.'),
  ],
);

final kHelpTandemMyParams = ScreenHelp(
  titlePl: 'Moje parametry — Tandem TIG',
  titleEn: 'My parameters — Tandem TIG',
  bodyPl:
      'Twoje własne zestawy parametrów Tandem TIG zapisane lokalnie. Dodawaj, edytuj i usuwaj zestawy dopasowane do Twoich warunków i materiałów.',
  bodyEn:
      'Your own Tandem TIG parameter sets saved locally. Add, edit and delete sets tailored to your conditions and materials.',
  stepsPl: [
    HelpStep('➕', 'Dodaj nowy zestaw przyciskiem +.'),
    HelpStep('✏️', 'Dotknij zestawu aby edytować parametry.'),
    HelpStep('🗑️', 'Przesuń w lewo aby usunąć zestaw.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new set with the + button.'),
    HelpStep('✏️', 'Tap a set to edit its parameters.'),
    HelpStep('🗑️', 'Swipe left to delete a set.'),
  ],
);

final kHelpCertificateRegister = ScreenHelp(
  titlePl: 'Uprawnienia spawacza',
  titleEn: 'Welder qualifications',
  bodyPl:
      'Rejestr Twoich certyfikatów EN ISO 9606-1 i ASME IX (WPQ): numer, egzaminator, data egzaminu, ważność, zakres (proces, grupa materiałowa, grubość, średnica, pozycje, BW/FW) i zdjęcie certyfikatu. Status na dziś liczy datę ważności i termin ciągłości 6-miesięcznej.',
  bodyEn:
      'A register of your EN ISO 9606-1 and ASME IX (WPQ) certificates: number, examiner, test date, validity, range (process, material group, thickness, diameter, positions, BW/FW) and a photo of the certificate. Today\'s status counts the expiry date and the 6-month continuity deadline.',
  stepsPl: [
    HelpStep('➕', 'Dodaj certyfikat — wpisz zakres KWALIFIKACJI z certyfikatu (co jest dopuszczone), nie parametry próbki.'),
    HelpStep('✅', 'Potwierdzenie 6-miesięczne (podpis koordynatora / egzaminatora) wpisz przy certyfikacie; dla ASME ciągłość liczy się też ze spoin w dzienniku.'),
    HelpStep('🔔', 'Przypomnienia przychodzą 30 i 7 dni przed datą ważności i terminem ciągłości.'),
    HelpStep('📋', 'Dziennik spoin sprawdza przy zapisie, czy spawacz miał w dniu spawania ważne uprawnienie obejmujące spoinę.'),
    HelpStep('💾', 'Rejestr i zdjęcia są w kopii zapasowej; „Usuń moje dane” kasuje rejestr, zdjęcia i przypomnienia.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a certificate — enter the QUALIFIED range from the certificate (what is allowed), not the test piece parameters.'),
    HelpStep('✅', 'Enter the 6-month confirmation (coordinator / examiner signature) on the certificate; for ASME, continuity also counts welds from the journal.'),
    HelpStep('🔔', 'Reminders arrive 30 and 7 days before the expiry date and the continuity deadline.'),
    HelpStep('📋', 'On save, the weld journal checks whether the welder held a valid qualification covering the weld on the weld date.'),
    HelpStep('💾', 'The register and photos are in the backup; "Delete my data" erases the register, the photos and the reminders.'),
  ],
);

final kHelpWpsLibrary = ScreenHelp(
  titlePl: 'Biblioteka WPS',
  titleEn: 'WPS library',
  bodyPl:
      'Twoje WPS (instrukcje technologiczne spawania) przepisane z dokumentów zakładu: procesy, grupa materiałowa, zakresy grubości i średnicy, pozycje, BW/FW, spoiwo, gazy, podgrzewanie, temperatura międzyściegowa i zakres energii liniowej w konwencji EN 1011-1 albo ASME IX. WPS ≠ WPQR: numer WPQR / PQR to tylko odnośnik.',
  bodyEn:
      'Your WPS (welding procedure specifications) copied from your workshop\'s documents: processes, material group, thickness and diameter ranges, positions, BW/FW, filler, gases, preheat, interpass temperature and the heat input range in the EN 1011-1 or ASME IX convention. WPS ≠ WPQR: the WPQR / PQR number is only a reference.',
  stepsPl: [
    HelpStep('➕', 'Dodaj WPS ręcznie albo zaimportuj plik JSON od koordynatora; udostępnij WPS brygadzie jednym plikiem.'),
    HelpStep('📋', 'W dzienniku spoin wybierzesz WPS z listy — spoina jest porównywana z jej zakresem przy zapisie.'),
    HelpStep('🌡️', 'Na ekranie „Heat input i CE” przycisk „Wybierz WPS” ustawia zakres energii i normę liczenia z WPS.'),
    HelpStep('⚠️', 'Wiąże dokument WPS zakładu. Dane startowe w parametrach rur to nie są WPS.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a WPS by hand or import a JSON file from your coordinator; share a WPS with the crew as one file.'),
    HelpStep('📋', 'In the weld journal you pick the WPS from the list — the weld is checked against its range on save.'),
    HelpStep('🌡️', 'On the “Heat input and CE” screen, “Pick WPS” sets the heat input range and the calculation standard from the WPS.'),
    HelpStep('⚠️', 'Your workshop\'s WPS document is binding. The starter data in pipe parameters is not a WPS.'),
  ],
);
