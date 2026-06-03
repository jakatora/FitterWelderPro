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
    const kCard   = Color(0xFF1A1D26);
    const kBorder = Color(0xFF2C3354);
    const kOrange = Color(0xFFF5A623);
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
                      color: Color(0xFFE8ECF0),
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
    const kOrange = Color(0xFFF5A623);
    const kBorder = Color(0xFF2C3354);
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

final kHelpHome = ScreenHelp(
  titlePl: 'Ekran główny',
  titleEn: 'Home screen',
  bodyPl:
      'Ekran startowy aplikacji FitterWelder Pro. Stąd przechodzisz do modułu FITTER (cut listy, kalkulatory) lub SPAWACZ (parametry spawania, dziennik). Na dole widać ostatnie projekty.',
  bodyEn:
      'The FitterWelder Pro start screen. From here you navigate to the FITTER module (cut lists, calculators) or the WELDER module (welding parameters, journal). Recent projects are shown at the bottom.',
  stepsPl: [
    HelpStep('🔧', 'FITTER — twórz listy cięć, używaj kalkulatorów i siatki ISO.'),
    HelpStep('⚡', 'SPAWACZ — parametry, gazy, dziennik spoin i kalkulatory spawalnicze.'),
    HelpStep('ðŸ“', 'Ostatnie projekty — szybki powrót do ostatnio otwartych projektów.'),
  ],
  stepsEn: [
    HelpStep('🔧', 'FITTER — create cut lists, use calculators and the ISO notebook.'),
    HelpStep('⚡', 'WELDER — parameters, gases, weld journal and welding calculators.'),
    HelpStep('ðŸ“', 'Recent projects — quick return to recently opened projects.'),
  ],
);

final kHelpFitterMenu = ScreenHelp(
  titlePl: 'Menu Fitter',
  titleEn: 'Fitter menu',
  bodyPl:
      'Centrum narzędzi montera rur. Znajdziesz tu Cut List do zarządzania projektami, tablicę DN-MM, kalkulatory geometrii rur, bibliotekę komponentów i zeszyt ISO.',
  bodyEn:
      'The pipe fitter tool hub. Here you find the Cut List for project management, the DN-MM table, pipe geometry calculators, the component library and the ISO notebook.',
  stepsPl: [
    HelpStep('📋', 'CUT LIST — projekty, segmenty i listy cięć z BOM.'),
    HelpStep('ðŸ“', 'Kalkulatory — cięcie kolanka, rolling offset, saddle cut, trasa rur i więcej.'),
    HelpStep('📚', 'Biblioteka komponentów — twój katalog kolan, redukcji, zaworów i kołnierzy.'),
    HelpStep('ðŸ—’ï¸', 'Zeszyt ISO — rysuj trasy na siatce izometrycznej.'),
  ],
  stepsEn: [
    HelpStep('📋', 'CUT LIST — projects, segments and cut lists with BOM.'),
    HelpStep('ðŸ“', 'Calculators — elbow cut, rolling offset, saddle cut, pipe route and more.'),
    HelpStep('📚', 'Component library — your catalogue of elbows, reducers, valves and flanges.'),
    HelpStep('ðŸ—’ï¸', 'ISO Notebook — draw pipe routes on an isometric grid.'),
  ],
);

final kHelpWelderMenu = ScreenHelp(
  titlePl: 'Menu Spawacz',
  titleEn: 'Welder menu',
  bodyPl:
      'Centrum narzędzi spawacza. Znajdziesz tu parametry spawania rur i zbiorników, kalkulatory (heat input, temperatura, gaz, O₂) oraz dziennik spoin.',
  bodyEn:
      'The welder tool hub. Here you find welding parameters for pipes and tanks, calculators (heat input, temperature, gas, O₂) and the weld journal.',
  stepsPl: [
    HelpStep('🔥', 'Rury — zestawy AMP, gazy osłonowe, zatwierdzone WPS, Twoje parametry.'),
    HelpStep('ðŸ›¢ï¸', 'Zbiorniki — parametry TIG dla zbiorników i tandem TIG.'),
    HelpStep('🗮', 'Kalkulatory — heat input, temperatura podgrzewania, przepływ gazu, timer.'),
    HelpStep('ðŸ“', 'Dziennik spoin — rejestruj spoiny z datą, numerem i statusem.'),
  ],
  stepsEn: [
    HelpStep('🔥', 'Pipes — AMP sets, shielding gases, approved WPS, your parameters.'),
    HelpStep('ðŸ›¢ï¸', 'Tanks — TIG parameters for tanks and tandem TIG.'),
    HelpStep('🗮', 'Calculators — heat input, preheat temperature, gas flow, timer.'),
    HelpStep('ðŸ“', 'Weld journal — log welds with date, number and status.'),
  ],
);

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
    HelpStep('ðŸ—‘ï¸', 'Przesuń w lewo na projekcie aby go usunąć.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Tap + (top right) to add a new project.'),
    HelpStep('👆', 'Tap a project to open its segments and cut list.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left on a project to delete it.'),
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
    HelpStep('➕', 'Dodaj nowy segment przyciskiem + lub FAB na dole.'),
    HelpStep('👆', 'Dotknij segmentu aby edytować komponenty i długości cięć.'),
    HelpStep('📊', 'Użyj przycisku BOM / Podsumowanie aby zobaczyć zestawienie materiałów.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new segment with the + button or FAB at the bottom.'),
    HelpStep('👆', 'Tap a segment to edit its components and cut lengths.'),
    HelpStep('📊', 'Use the BOM / Summary button to view the bill of materials.'),
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
    HelpStep('➕', 'Dodaj komponent z listy lub biblioteki przyciskiem +.'),
    HelpStep('↕️', 'Przeciągaj komponenty aby zmienić ich kolejność w segmencie.'),
    HelpStep('ðŸ“', 'Wpisz wymiary ISO — aplikacja przeliczy długość odcinka rury.'),
    HelpStep('✅', 'Zatwierdź segment aby zapisać go do projektu.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a component from the list or library with the + button.'),
    HelpStep('↕️', 'Drag components to reorder them in the segment.'),
    HelpStep('ðŸ“', 'Enter ISO dimensions — the app calculates the pipe spool length.'),
    HelpStep('✅', 'Confirm the segment to save it to the project.'),
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
    HelpStep('➕', 'Dodaj nowy komponent przyciskiem + (góra prawo).'),
    HelpStep('✏️', 'Dotknij komponentu aby edytować jego wymiary.'),
    HelpStep('ðŸ—‘ï¸', 'Przesuń w lewo aby usunąć komponent.'),
    HelpStep('ðŸ”', 'Filtruj listę wpisując typ lub średnicę w polu wyszukiwania.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new component with the + button (top right).'),
    HelpStep('✏️', 'Tap a component to edit its dimensions.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a component.'),
    HelpStep('ðŸ”', 'Filter the list by typing a type or diameter in the search field.'),
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
    HelpStep('ðŸ“¤', 'Użyj przycisku eksport aby zapisać zestawienie do PDF.'),
  ],
  stepsEn: [
    HelpStep('📋', 'Review the cut list — each row is one pipe spool.'),
    HelpStep('📊', 'The BOM section shows total quantities of elbows, reducers and other components.'),
    HelpStep('ðŸ“¤', 'Use the export button to save the summary as a PDF.'),
  ],
);

final kHelpFitterTools = ScreenHelp(
  titlePl: 'Kalkulatory — Fitter',
  titleEn: 'Calculators — Fitter',
  bodyPl:
      'Zestaw kalkulatorów geometrycznych dla monterów rur. Przełączaj się między zakładkami: Spadek, Cięcie kolanka, Obrót kolanka, Wstawka, Redukcja, Ciężar rury, Fazowanie i Dylatacja.',
  bodyEn:
      'A set of geometry calculators for pipe fitters. Switch between tabs: Slope, Elbow cut, Elbow rotation, Insert, Reducer, Pipe weight, Bevel and Thermal expansion.',
  stepsPl: [
    HelpStep('ðŸ“', 'Spadek — oblicz miter (1 cięcie) dla wymaganego kąta nachylenia.'),
    HelpStep('âœ‚ï¸', 'Cięcie kolanka — skróć kolano 90° do wymaganego kąta docelowego.'),
    HelpStep('ðŸ”„', 'Obrót kolanka — oblicz % / ° obrotu dla odejścia bocznego.'),
    HelpStep('ðŸ“', 'Wstawka — oblicz długość odcinka między dwoma kołnierzami/czołami.'),
    HelpStep('ðŸ—œï¸', 'Redukcja — oblicz skrócenie dla docelowej średnicy wyjściowej.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Slope — calculate miter (1 cut) for a required inclination angle.'),
    HelpStep('âœ‚ï¸', 'Elbow cut — trim a 90° elbow down to the required target angle.'),
    HelpStep('ðŸ”„', 'Elbow rotation — calculate % / ° of rotation for a lateral offset.'),
    HelpStep('ðŸ“', 'Insert — calculate spool length between two flanges or faces.'),
    HelpStep('ðŸ—œï¸', 'Reducer — calculate trimming for the required outlet diameter.'),
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
    HelpStep('ðŸ”¢', 'Wpisz DN aby znaleźć odpowiednie OD i NPS.'),
    HelpStep('ðŸ“', 'Wpisz OD (mm) aby znaleźć najbliższy DN/NPS (tolerancja ±0.25 mm).'),
    HelpStep('ðŸ”', 'Pole tekstowe filtruje po NPS, np. "1 1/2".'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter DN to find the corresponding OD and NPS.'),
    HelpStep('ðŸ“', 'Enter OD (mm) to find the closest DN/NPS (tolerance ±0.25 mm).'),
    HelpStep('ðŸ”', 'Text field filters by NPS, e.g. "1 1/2".'),
  ],
);

final kHelpPipeRoute = ScreenHelp(
  titlePl: 'Kalkulator trasy rur',
  titleEn: 'Pipe route calculator',
  bodyPl:
      'Oblicza długości odcinków rur dla trasy z 3 kołnami 90°: poziomy X → pionowy ΔH → poziomy Y. Uwzględnia wymiar kolanka (takeout) R.',
  bodyEn:
      'Calculates pipe spool lengths for a route with 3 × 90° elbows: horizontal X → vertical ΔH → horizontal Y. Takes the elbow takeout R into account.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wpisz H1 i H2 — poziomy startowy i końcowy (różnica = ΔH).'),
    HelpStep('↔ï¸', 'Wpisz X i Y — odległości poziome.'),
    HelpStep('ðŸ”„', 'Wpisz R — wymiar kolanka face-to-centre dla Twojego LR 90°.'),
    HelpStep('✅', 'Kliknij Oblicz — otrzymasz 3 długości do cięcia.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Enter H1 and H2 — start and end elevations (difference = ΔH).'),
    HelpStep('↔ï¸', 'Enter X and Y — horizontal distances.'),
    HelpStep('ðŸ”„', 'Enter R — elbow takeout face-to-centre for your LR 90°.'),
    HelpStep('✅', 'Tap Calculate — you get 3 cut lengths.'),
  ],
);

final kHelpRollingOffset = ScreenHelp(
  titlePl: 'Rolling Offset',
  titleEn: 'Rolling Offset',
  bodyPl:
      'Oblicza Travel (długość odcinka) dla offsetu biegnącego jednocześnie w pionie (Rise) i poziomie (Spread). Wzory: True Offset = √(Rise² + Spread²), Travel = True Offset / sin(θ).',
  bodyEn:
      'Calculates Travel (spool length) for an offset running simultaneously vertically (Rise) and horizontally (Spread). Formulas: True Offset = √(Rise² + Spread²), Travel = True Offset / sin(θ).',
  stepsPl: [
    HelpStep('↕️', 'Rise — odchylenie pionowe (w mm).'),
    HelpStep('↔ï¸', 'Spread — odchylenie poziome (w mm).'),
    HelpStep('ðŸ”„', 'Kąt kolanka — wybierz 45°, 30°, 60° lub podaj własny.'),
    HelpStep('ðŸ“', 'Wynik: True Offset, Travel, Run i Multiplier.'),
  ],
  stepsEn: [
    HelpStep('↕️', 'Rise — vertical deviation (in mm).'),
    HelpStep('↔ï¸', 'Spread — horizontal deviation (in mm).'),
    HelpStep('ðŸ”„', 'Elbow angle — choose 45°, 30°, 60° or enter your own.'),
    HelpStep('ðŸ“', 'Results: True Offset, Travel, Run and Multiplier.'),
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
    HelpStep('ðŸ“', 'Wybierz tryb: długość→rise, rise→długość lub slope ze znanych wartości.'),
    HelpStep('ðŸ”¢', 'Wpisz dane i kliknij Oblicz.'),
    HelpStep('📊', 'Wynik pokazuje slope w %, mm/m i stopniach równocześnie.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Choose mode: length→rise, rise→length or slope from known values.'),
    HelpStep('ðŸ”¢', 'Enter the data and tap Calculate.'),
    HelpStep('📊', 'Result shows slope in %, mm/m and degrees simultaneously.'),
  ],
);

final kHelpSaddleCut = ScreenHelp(
  titlePl: 'Saddle Cut (wycięcie siodłowe)',
  titleEn: 'Saddle Cut (fish-mouth cut)',
  bodyPl:
      'Oblicza głębokość wycięcia siodłowego na rurze odgałęzieniowej dla prostopadłego połączenia T. Wynik to profil nacięcia w 8 punktach kątowych wokół obwodu rury.',
  bodyEn:
      'Calculates the saddle cut depth on the branch pipe for a perpendicular T-junction. The result is the cut profile at 8 angular positions around the pipe circumference.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wpisz OD rury głównej (header) i rury odgałęzieniowej (branch).'),
    HelpStep('📊', 'Profil pokazuje głębokość cięcia co 22.5° (0°, 22.5°, 45°... 90°).'),
    HelpStep('ðŸ’¡', 'Głębokość 0 mm jest na wierzchołku (90°), max na boku (0°).'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Enter the OD of the header pipe and the branch pipe.'),
    HelpStep('📊', 'Profile shows cut depth every 22.5° (0°, 22.5°, 45°... 90°).'),
    HelpStep('ðŸ’¡', 'Depth 0 mm is at the top (90°), maximum depth is at the side (0°).'),
  ],
);

final kHelpRouteMeasure = ScreenHelp(
  titlePl: 'Pomiar trasy',
  titleEn: 'Route measure',
  bodyPl:
      'Przelicza wymiary zmierzone taśmą na wymiary C-C (oś do osi). Podaj wymiar boku A i B, OD rury i wymiar kolanka do osi — aplikacja obliczy wymiary C-C i długości do cięcia.',
  bodyEn:
      'Converts tape-measured dimensions to C-C (centre-to-centre) dimensions. Enter side A and B dimensions, pipe OD and elbow centre-to-face — the app calculates C-C dimensions and cut lengths.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wybierz typ pomiaru: inner (wewnątrz), center (C-C) lub outer (zewnątrz).'),
    HelpStep('ðŸ”¢', 'Wpisz wymiary A, B, OD rury i wymiar kolanka do osi (C-F).'),
    HelpStep('ðŸ“', 'Wynik: długości C-C dla obu boków, kąt skos i długości do cięcia.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Choose measurement type: inner, center (C-C) or outer.'),
    HelpStep('ðŸ”¢', 'Enter dimensions A, B, pipe OD and elbow centre-to-face (C-F).'),
    HelpStep('ðŸ“', 'Result: C-C lengths for both sides, diagonal angle and cut lengths.'),
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
  ],
  stepsEn: [
    HelpStep('📏', 'PIPE tool — drag on the grid, then enter the segment dimension on release.'),
    HelpStep('🔢', 'Tap a drawn segment to enter or correct its dimension.'),
    HelpStep('🔩', 'FITTINGS — elbows, tees, valves, flanges, welds: tap a grid node.'),
    HelpStep('🔄', 'Tap a placed fitting again to rotate it by 60°.'),
    HelpStep('🧭', 'ANNOTATIONS — north arrow, flow direction and free text (line no., elevation).'),
    HelpStep('📋', 'The copy button in the top bar builds a summary: dimensions + BOM.'),
    HelpStep('🗑️', 'Long-press any element to delete it.'),
  ],
);

final kHelpWelderPipes = ScreenHelp(
  titlePl: 'Parametry spawania — Rury',
  titleEn: 'Welding parameters — Pipes',
  bodyPl:
      'Zestawy parametrów spawania TIG dla rur: prąd (AMP), gazy osłonowe, zatwierdzone WPS i Twoje własne zestawy. Przeglądaj i edytuj zestawy dopasowane do średnicy i grubości ścianki.',
  bodyEn:
      'TIG welding parameter sets for pipes: current (AMP), shielding gases, approved WPS and your own sets. Browse and edit sets matched to pipe OD and wall thickness.',
  stepsPl: [
    HelpStep('📋', 'AMP — referencyjne prądy dla typowych średnic rur SS/CS.'),
    HelpStep('ðŸ’¨', 'Gazy — zalecane mieszanki i przepływy dla różnych materiałów.'),
    HelpStep('✅', 'Zatwierdzone — zestawy WPS zatwierdzone w Twoim zakładzie.'),
    HelpStep('ðŸ‘¤', 'Moje — własne zestawy parametrów zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('📋', 'AMP — reference currents for typical pipe diameters SS/CS.'),
    HelpStep('ðŸ’¨', 'Gases — recommended mixes and flow rates for different materials.'),
    HelpStep('✅', 'Approved — WPS sets approved in your workshop.'),
    HelpStep('ðŸ‘¤', 'Mine — your own parameter sets saved locally.'),
  ],
);

final kHelpWelderTanks = ScreenHelp(
  titlePl: 'Parametry spawania — Zbiorniki',
  titleEn: 'Welding parameters — Tanks',
  bodyPl:
      'Zestawy parametrów spawania TIG dla zbiorników i większych przekrojów, w tym tandem TIG (dwa palniki). Zawiera zakładki AMP i Tandem TIG.',
  bodyEn:
      'TIG welding parameter sets for tanks and larger sections, including tandem TIG (two torches). Contains AMP and Tandem TIG tabs.',
  stepsPl: [
    HelpStep('⚡', 'AMP — referencyjne prądy dla zgrzewów obwodowych i podłużnych zbiorników.'),
    HelpStep('ðŸ”€', 'Tandem TIG — parametry dla procesu z dwoma elektrodami (lead + trail).'),
  ],
  stepsEn: [
    HelpStep('⚡', 'AMP — reference currents for circumferential and longitudinal tank welds.'),
    HelpStep('ðŸ”€', 'Tandem TIG — parameters for the dual-electrode process (lead + trail).'),
  ],
);

final kHelpWelderTools = ScreenHelp(
  titlePl: 'Kalkulatory — Spawacz',
  titleEn: 'Calculators — Welder',
  bodyPl:
      'Kalkulatory spawalnicze w zakładkach: Heat Input (kJ/mm), Temperatura podgrzewania, Purge O₂, Zużycie gazu, Timer spawania i Przelicznik ciśnienia.',
  bodyEn:
      'Welding calculators in tabs: Heat Input (kJ/mm), Preheat temperature, O₂ purge, Gas consumption, Weld timer and Pressure converter.',
  stepsPl: [
    HelpStep('ðŸŒ¡ï¸', 'Heat Input — oblicza kJ/mm ze: napięcia, prądu i prędkości spawania.'),
    HelpStep('🔥', 'Temperatura — wymagana temperatura podgrzewania wg grubości i C.E.'),
    HelpStep('ðŸ’¨', 'O₂ Purge — czas i ilość gazu do wypłukania rury przed spawaniem.'),
    HelpStep('â±ï¸', 'Timer — stoper do mierzenia czasu łuku dla heat input.'),
  ],
  stepsEn: [
    HelpStep('ðŸŒ¡ï¸', 'Heat Input — calculates kJ/mm from: voltage, current and travel speed.'),
    HelpStep('🔥', 'Preheat — required preheat temperature based on thickness and C.E.'),
    HelpStep('ðŸ’¨', 'O₂ Purge — time and gas volume to purge a pipe before welding.'),
    HelpStep('â±ï¸', 'Timer — stopwatch to measure arc time for heat input.'),
  ],
);

final kHelpWeldJournal = ScreenHelp(
  titlePl: 'Dziennik spoin',
  titleEn: 'Weld journal',
  bodyPl:
      'Rejestr spoin dla danego projektu. Każdy wpis zawiera numer spoiny, materiał, OD, grubość ścianki, metodę spawania, spawacza, datę i status (OK / NOK / Pending).',
  bodyEn:
      'A weld register for a project. Each entry contains the weld number, material, OD, wall thickness, welding method, welder, date and status (OK / NOK / Pending).',
  stepsPl: [
    HelpStep('➕', 'Dodaj nową spoinę przyciskiem + (góra prawo).'),
    HelpStep('✏️', 'Dotknij spoiny aby edytować jej dane.'),
    HelpStep('ðŸŸ¢', 'Zmień status: OK (zielony), NOK (czerwony), Pending (pomarańczowy).'),
    HelpStep('ðŸ“¤', 'Eksportuj dziennik do PDF lub CSV.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new weld with the + button (top right).'),
    HelpStep('✏️', 'Tap a weld entry to edit its data.'),
    HelpStep('ðŸŸ¢', 'Change status: OK (green), NOK (red), Pending (orange).'),
    HelpStep('ðŸ“¤', 'Export the journal to PDF or CSV.'),
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
    HelpStep('ðŸ“¤', 'Eksportuj przyciskiem w górnym prawym rogu (PDF lub schowek).'),
  ],
  stepsEn: [
    HelpStep('📋', 'Each row is one type of element with quantity and unit.'),
    HelpStep('ðŸ“¤', 'Export with the button in the top right (PDF or clipboard).'),
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
    HelpStep('ðŸ‘¤', 'Moje parametry — Twoje własne zestawy zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('🗮', 'Calculator — calculate lead and trail parameters based on material and OD.'),
    HelpStep('📚', 'Library — browse sets approved for different applications.'),
    HelpStep('ðŸ‘¤', 'My params — your own parameter sets saved locally.'),
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
    HelpStep('ðŸ”¢', 'Wpisz OD, grubość ścianki i materiał.'),
    HelpStep('⚡', 'Wybierz tryb spawania i pozycję.'),
    HelpStep('✅', 'Kliknij Oblicz aby zobaczyć parametry lead i trail.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter OD, wall thickness and material.'),
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
    HelpStep('ðŸ—‘ï¸', 'Przesuń w lewo aby usunąć zestaw.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new set with the + button.'),
    HelpStep('✏️', 'Tap a set to edit its parameters.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a set.'),
  ],
);

final kHelpSpoolPlanner = ScreenHelp(
  titlePl: 'Projektant trasy 3D',
  titleEn: 'Route planner 3D',
  bodyPl:
      'Wizualny projektant 3D trasy rurowej. Definiujesz kolejne odcinki w osiach X, Y i Z, a aplikacja rysuje podgląd trasy i oblicza sumaryczne długości w każdym kierunku.',
  bodyEn:
      'A 3D visual pipe route planner. Define successive segments along X, Y and Z axes and the app draws a route preview and calculates total lengths in each direction.',
  stepsPl: [
    HelpStep('➕', 'Dodaj odcinek: wybierz oś (X/Y/Z) i wpisz długość.'),
    HelpStep('ðŸ”„', 'Podgląd 3D obraca się automatycznie po każdym dodaniu.'),
    HelpStep('ðŸ—‘ï¸', 'Usuń ostatni odcinek przyciskiem Cofnij.'),
    HelpStep('📊', 'Zestawienie na dole pokazuje sumy w osi X, Y i Z.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a segment: choose axis (X/Y/Z) and enter the length.'),
    HelpStep('ðŸ”„', 'The 3D preview rotates automatically after each addition.'),
    HelpStep('ðŸ—‘ï¸', 'Remove the last segment with the Undo button.'),
    HelpStep('📊', 'The summary at the bottom shows totals for X, Y and Z axes.'),
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
    HelpStep('ðŸ“·', 'Dodaj zdjęcie aparatem lub z galerii przyciskiem +.'),
    HelpStep('ðŸ”', 'Dotknij miniatury aby zobaczyć pełny podgląd.'),
    HelpStep('ðŸ—‘ï¸', 'Przytrzymaj miniaturę aby usunąć zdjęcie.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“·', 'Add a photo from the camera or gallery with the + button.'),
    HelpStep('ðŸ”', 'Tap a thumbnail to see the full preview.'),
    HelpStep('ðŸ—‘ï¸', 'Long-press a thumbnail to delete the photo.'),
  ],
);

final kHelpProjectComponents = ScreenHelp(
  titlePl: 'Komponenty projektu / Heat',
  titleEn: 'Project components / Heat',
  bodyPl:
      'Widok komponentów projektu z przypisaniem numerów wytopów (heat numbers). Dla każdego komponentu możesz przypisać numer certyfikatu materiałowego i zdjęcie etykiety.',
  bodyEn:
      'Project component view with heat number assignment. For each component you can assign a material certificate number and a label photo.',
  stepsPl: [
    HelpStep('ðŸ”¢', 'Wpisz numer heatu (wytopienia) dla każdego komponentu.'),
    HelpStep('ðŸ“·', 'Dodaj zdjęcie certyfikatu materiałowego przyciskiem aparatu.'),
    HelpStep('✅', 'Zapisz przypisania przyciskiem w górnym prawym rogu.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter the heat number for each component.'),
    HelpStep('ðŸ“·', 'Add a material certificate photo with the camera button.'),
    HelpStep('✅', 'Save the assignments with the button in the top right.'),
  ],
);

final kHelpFieldAssembly = ScreenHelp(
  titlePl: 'Montaż w terenie',
  titleEn: 'Field assembly',
  bodyPl:
      'Narzędzie do planowania i dokumentowania montażu w terenie. Rejestruj status każdego spool\'a (prefabrykatu) — gotowy do spawania, spawany lub zamontowany.',
  bodyEn:
      'A tool for planning and documenting field assembly. Record the status of each spool (prefab) — ready to weld, welded or installed.',
  stepsPl: [
    HelpStep('📋', 'Lista spoolów pokazuje status każdego prefabrykatu.'),
    HelpStep('✅', 'Dotknij spool\'a aby zmienić jego status montażu.'),
    HelpStep('ðŸ“¤', 'Eksportuj raport statusu przyciskiem w górnym prawym rogu.'),
  ],
  stepsEn: [
    HelpStep('📋', 'The spool list shows the status of each prefab.'),
    HelpStep('✅', 'Tap a spool to change its assembly status.'),
    HelpStep('ðŸ“¤', 'Export the status report with the button in the top right.'),
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
    HelpStep('ðŸ—‘ï¸', 'Przesuń w lewo aby usunąć zestaw.'),
  ],
  stepsEn: [
    HelpStep('➕', 'Add a new set with the + button.'),
    HelpStep('✏️', 'Tap a set to edit its parameters.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a set.'),
  ],
);
