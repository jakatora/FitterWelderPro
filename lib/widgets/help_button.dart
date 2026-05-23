import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

// â”€â”€â”€ Model treÅ›ci pomocy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€â”€ Ikona przycisku pomocy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€â”€ Bottom sheet z treÅ›ciÄ… â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            // Ikona + tytuÅ‚
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

// â”€â”€â”€ TreÅ›ci pomocy dla kaÅ¼dego ekranu â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final kHelpHome = ScreenHelp(
  titlePl: 'Ekran gÅ‚Ã³wny',
  titleEn: 'Home screen',
  bodyPl:
      'Ekran startowy aplikacji FitterWelder Pro. StÄ…d przechodzisz do moduÅ‚u FITTER (cut listy, kalkulatory) lub SPAWACZ (parametry spawania, dziennik). Na dole widaÄ‡ ostatnie projekty.',
  bodyEn:
      'The FitterWelder Pro start screen. From here you navigate to the FITTER module (cut lists, calculators) or the WELDER module (welding parameters, journal). Recent projects are shown at the bottom.',
  stepsPl: [
    HelpStep('ðŸ”§', 'FITTER â€” twÃ³rz listy ciÄ™Ä‡, uÅ¼ywaj kalkulatorÃ³w i siatki ISO.'),
    HelpStep('âš¡', 'SPAWACZ â€” parametry, gazy, dziennik spoin i kalkulatory spawalnicze.'),
    HelpStep('ðŸ“', 'Ostatnie projekty â€” szybki powrÃ³t do ostatnio otwartych projektÃ³w.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”§', 'FITTER â€” create cut lists, use calculators and the ISO notebook.'),
    HelpStep('âš¡', 'WELDER â€” parameters, gases, weld journal and welding calculators.'),
    HelpStep('ðŸ“', 'Recent projects â€” quick return to recently opened projects.'),
  ],
);

final kHelpFitterMenu = ScreenHelp(
  titlePl: 'Menu Fitter',
  titleEn: 'Fitter menu',
  bodyPl:
      'Centrum narzÄ™dzi montera rur. Znajdziesz tu Cut List do zarzÄ…dzania projektami, tablicÄ™ DN-MM, kalkulatory geometrii rur, bibliotekÄ™ komponentÃ³w i zeszyt ISO.',
  bodyEn:
      'The pipe fitter tool hub. Here you find the Cut List for project management, the DN-MM table, pipe geometry calculators, the component library and the ISO notebook.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'CUT LIST â€” projekty, segmenty i listy ciÄ™Ä‡ z BOM.'),
    HelpStep('ðŸ“', 'Kalkulatory â€” ciÄ™cie kolanka, rolling offset, saddle cut, trasa rur i wiÄ™cej.'),
    HelpStep('ðŸ“š', 'Biblioteka komponentÃ³w â€” twÃ³j katalog kolan, redukcji, zaworÃ³w i koÅ‚nierzy.'),
    HelpStep('ðŸ—’ï¸', 'Zeszyt ISO â€” rysuj trasy na siatce izometrycznej.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'CUT LIST â€” projects, segments and cut lists with BOM.'),
    HelpStep('ðŸ“', 'Calculators â€” elbow cut, rolling offset, saddle cut, pipe route and more.'),
    HelpStep('ðŸ“š', 'Component library â€” your catalogue of elbows, reducers, valves and flanges.'),
    HelpStep('ðŸ—’ï¸', 'ISO Notebook â€” draw pipe routes on an isometric grid.'),
  ],
);

final kHelpWelderMenu = ScreenHelp(
  titlePl: 'Menu Spawacz',
  titleEn: 'Welder menu',
  bodyPl:
      'Centrum narzÄ™dzi spawacza. Znajdziesz tu parametry spawania rur i zbiornikÃ³w, kalkulatory (heat input, temperatura, gaz, Oâ‚‚) oraz dziennik spoin.',
  bodyEn:
      'The welder tool hub. Here you find welding parameters for pipes and tanks, calculators (heat input, temperature, gas, Oâ‚‚) and the weld journal.',
  stepsPl: [
    HelpStep('ðŸ”¥', 'Rury â€” zestawy AMP, gazy osÅ‚onowe, zatwierdzone WPS, Twoje parametry.'),
    HelpStep('ðŸ›¢ï¸', 'Zbiorniki â€” parametry TIG dla zbiornikÃ³w i tandem TIG.'),
    HelpStep('ðŸ§®', 'Kalkulatory â€” heat input, temperatura podgrzewania, przepÅ‚yw gazu, timer.'),
    HelpStep('ðŸ“', 'Dziennik spoin â€” rejestruj spoiny z datÄ…, numerem i statusem.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¥', 'Pipes â€” AMP sets, shielding gases, approved WPS, your parameters.'),
    HelpStep('ðŸ›¢ï¸', 'Tanks â€” TIG parameters for tanks and tandem TIG.'),
    HelpStep('ðŸ§®', 'Calculators â€” heat input, preheat temperature, gas flow, timer.'),
    HelpStep('ðŸ“', 'Weld journal â€” log welds with date, number and status.'),
  ],
);

final kHelpProjects = ScreenHelp(
  titlePl: 'Lista projektÃ³w (Cut List)',
  titleEn: 'Projects list (Cut List)',
  bodyPl:
      'Tutaj zarzÄ…dzasz projektami cut list. KaÅ¼dy projekt ma przypisane Å›rednicÄ™, gruboÅ›Ä‡ Å›cianki, grupÄ™ materiaÅ‚owÄ… i luz montaÅ¼owy. Do projektu dodajesz segmenty z listami ciÄ™Ä‡.',
  bodyEn:
      'Here you manage cut list projects. Each project has a diameter, wall thickness, material group and fit-up gap assigned. You add segments with cut lists to a project.',
  stepsPl: [
    HelpStep('âž•', 'Kliknij + (gÃ³ra prawo) aby dodaÄ‡ nowy projekt.'),
    HelpStep('ðŸ‘†', 'Dotknij projektu aby otworzyÄ‡ jego segmenty i cut listÄ™.'),
    HelpStep('ðŸ—‘ï¸', 'PrzesuÅ„ w lewo na projekcie aby go usunÄ…Ä‡.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Tap + (top right) to add a new project.'),
    HelpStep('ðŸ‘†', 'Tap a project to open its segments and cut list.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left on a project to delete it.'),
  ],
);

final kHelpFitter = ScreenHelp(
  titlePl: 'Projekt â€” segmenty',
  titleEn: 'Project â€” segments',
  bodyPl:
      'Widok projektu cut list. KaÅ¼dy segment to jeden odcinek trasy rurowej ze swojÄ… listÄ… komponentÃ³w. MoÅ¼esz dodawaÄ‡ segmenty, generowaÄ‡ BOM i eksportowaÄ‡ podsumowanie.',
  bodyEn:
      'The cut list project view. Each segment is one section of the pipe route with its own component list. You can add segments, generate a BOM and export a summary.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj nowy segment przyciskiem + lub FAB na dole.'),
    HelpStep('ðŸ‘†', 'Dotknij segmentu aby edytowaÄ‡ komponenty i dÅ‚ugoÅ›ci ciÄ™Ä‡.'),
    HelpStep('ðŸ“Š', 'UÅ¼yj przycisku BOM / Podsumowanie aby zobaczyÄ‡ zestawienie materiaÅ‚Ã³w.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a new segment with the + button or FAB at the bottom.'),
    HelpStep('ðŸ‘†', 'Tap a segment to edit its components and cut lengths.'),
    HelpStep('ðŸ“Š', 'Use the BOM / Summary button to view the bill of materials.'),
  ],
);

final kHelpSegmentBuilder = ScreenHelp(
  titlePl: 'Budowniczy segmentu',
  titleEn: 'Segment builder',
  bodyPl:
      'Tutaj budujesz segment rury z komponentÃ³w. Dodaj kolano, redukcjÄ™, trÃ³jnik lub zawÃ³r â€” aplikacja automatycznie obliczy dÅ‚ugoÅ›ci ciÄ™Ä‡ i gap miÄ™dzy elementami.',
  bodyEn:
      'Here you build a pipe segment from components. Add an elbow, reducer, tee or valve â€” the app automatically calculates cut lengths and the fit-up gap between elements.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj komponent z listy lub biblioteki przyciskiem +.'),
    HelpStep('â†•ï¸', 'PrzeciÄ…gaj komponenty aby zmieniÄ‡ ich kolejnoÅ›Ä‡ w segmencie.'),
    HelpStep('ðŸ“', 'Wpisz wymiary ISO â€” aplikacja przeliczy dÅ‚ugoÅ›Ä‡ odcinka rury.'),
    HelpStep('âœ…', 'ZatwierdÅº segment aby zapisaÄ‡ go do projektu.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a component from the list or library with the + button.'),
    HelpStep('â†•ï¸', 'Drag components to reorder them in the segment.'),
    HelpStep('ðŸ“', 'Enter ISO dimensions â€” the app calculates the pipe spool length.'),
    HelpStep('âœ…', 'Confirm the segment to save it to the project.'),
  ],
);

final kHelpComponentLibrary = ScreenHelp(
  titlePl: 'Biblioteka komponentÃ³w',
  titleEn: 'Component library',
  bodyPl:
      'TwÃ³j katalog prefabrykowanych komponentÃ³w rurowych: kolana, redukcje, trÃ³jniki, zawory, koÅ‚nierze. KaÅ¼dy komponent ma wymiary (OD, dÅ‚ugoÅ›Ä‡, promieÅ„, typ punktu ISO) uÅ¼ywane do obliczeÅ„.',
  bodyEn:
      'Your catalogue of prefabricated pipe components: elbows, reducers, tees, valves, flanges. Each component has dimensions (OD, length, radius, ISO reference point) used for calculations.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj nowy komponent przyciskiem + (gÃ³ra prawo).'),
    HelpStep('âœï¸', 'Dotknij komponentu aby edytowaÄ‡ jego wymiary.'),
    HelpStep('ðŸ—‘ï¸', 'PrzesuÅ„ w lewo aby usunÄ…Ä‡ komponent.'),
    HelpStep('ðŸ”', 'Filtruj listÄ™ wpisujÄ…c typ lub Å›rednicÄ™ w polu wyszukiwania.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a new component with the + button (top right).'),
    HelpStep('âœï¸', 'Tap a component to edit its dimensions.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a component.'),
    HelpStep('ðŸ”', 'Filter the list by typing a type or diameter in the search field.'),
  ],
);

final kHelpCutListSummary = ScreenHelp(
  titlePl: 'Podsumowanie cut list (BOM)',
  titleEn: 'Cut list summary (BOM)',
  bodyPl:
      'Zestawienie wszystkich materiaÅ‚Ã³w dla projektu. WidaÄ‡ tu caÅ‚kowite dÅ‚ugoÅ›ci ciÄ™Ä‡ rur z podziaÅ‚em na odcinki, Å‚Ä…cznÄ… iloÅ›Ä‡ komponentÃ³w i moÅ¼liwoÅ›Ä‡ eksportu do PDF.',
  bodyEn:
      'Bill of materials summary for the project. It shows total pipe cut lengths broken down by spool, total component quantities and a PDF export option.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'Przejrzyj listÄ™ ciÄ™Ä‡ â€” kaÅ¼dy wiersz to jeden odcinek rury.'),
    HelpStep('ðŸ“Š', 'Sekcja BOM pokazuje Å‚Ä…czne iloÅ›ci kolan, redukcji i innych komponentÃ³w.'),
    HelpStep('ðŸ“¤', 'UÅ¼yj przycisku eksport aby zapisaÄ‡ zestawienie do PDF.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'Review the cut list â€” each row is one pipe spool.'),
    HelpStep('ðŸ“Š', 'The BOM section shows total quantities of elbows, reducers and other components.'),
    HelpStep('ðŸ“¤', 'Use the export button to save the summary as a PDF.'),
  ],
);

final kHelpFitterTools = ScreenHelp(
  titlePl: 'Kalkulatory â€” Fitter',
  titleEn: 'Calculators â€” Fitter',
  bodyPl:
      'Zestaw kalkulatorÃ³w geometrycznych dla monterÃ³w rur. PrzeÅ‚Ä…czaj siÄ™ miÄ™dzy zakÅ‚adkami: Spadek, CiÄ™cie kolanka, ObrÃ³t kolanka, Wstawka, Redukcja, CiÄ™Å¼ar rury, Fazowanie i Dylatacja.',
  bodyEn:
      'A set of geometry calculators for pipe fitters. Switch between tabs: Slope, Elbow cut, Elbow rotation, Insert, Reducer, Pipe weight, Bevel and Thermal expansion.',
  stepsPl: [
    HelpStep('ðŸ“', 'Spadek â€” oblicz miter (1 ciÄ™cie) dla wymaganego kÄ…ta nachylenia.'),
    HelpStep('âœ‚ï¸', 'CiÄ™cie kolanka â€” skrÃ³Ä‡ kolano 90Â° do wymaganego kÄ…ta docelowego.'),
    HelpStep('ðŸ”„', 'ObrÃ³t kolanka â€” oblicz % / Â° obrotu dla odejÅ›cia bocznego.'),
    HelpStep('ðŸ“', 'Wstawka â€” oblicz dÅ‚ugoÅ›Ä‡ odcinka miÄ™dzy dwoma koÅ‚nierzami/czoÅ‚ami.'),
    HelpStep('ðŸ—œï¸', 'Redukcja â€” oblicz skrÃ³cenie dla docelowej Å›rednicy wyjÅ›ciowej.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Slope â€” calculate miter (1 cut) for a required inclination angle.'),
    HelpStep('âœ‚ï¸', 'Elbow cut â€” trim a 90Â° elbow down to the required target angle.'),
    HelpStep('ðŸ”„', 'Elbow rotation â€” calculate % / Â° of rotation for a lateral offset.'),
    HelpStep('ðŸ“', 'Insert â€” calculate spool length between two flanges or faces.'),
    HelpStep('ðŸ—œï¸', 'Reducer â€” calculate trimming for the required outlet diameter.'),
  ],
);

final kHelpDnMm = ScreenHelp(
  titlePl: 'Tablica DN â†” OD (mm) + NPS',
  titleEn: 'DN â†” OD (mm) + NPS table',
  bodyPl:
      'Tabela przeliczeniowa nominalna: DN (metryczne), NPS (calowe) i rzeczywista zewnÄ™trzna Å›rednica OD w milimetrach. Wpisz wartoÅ›Ä‡ w pole DN lub OD aby przefiltrowaÄ‡ tabelÄ™.',
  bodyEn:
      'Nominal conversion table: DN (metric), NPS (inch) and actual outside diameter OD in millimetres. Enter a value in the DN or OD field to filter the table.',
  stepsPl: [
    HelpStep('ðŸ”¢', 'Wpisz DN aby znaleÅºÄ‡ odpowiednie OD i NPS.'),
    HelpStep('ðŸ“', 'Wpisz OD (mm) aby znaleÅºÄ‡ najbliÅ¼szy DN/NPS (tolerancja Â±0.25 mm).'),
    HelpStep('ðŸ”', 'Pole tekstowe filtruje po NPS, np. "1 1/2".'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter DN to find the corresponding OD and NPS.'),
    HelpStep('ðŸ“', 'Enter OD (mm) to find the closest DN/NPS (tolerance Â±0.25 mm).'),
    HelpStep('ðŸ”', 'Text field filters by NPS, e.g. "1 1/2".'),
  ],
);

final kHelpPipeRoute = ScreenHelp(
  titlePl: 'Kalkulator trasy rur',
  titleEn: 'Pipe route calculator',
  bodyPl:
      'Oblicza dÅ‚ugoÅ›ci odcinkÃ³w rur dla trasy z 3 koÅ‚nami 90Â°: poziomy X â†’ pionowy Î”H â†’ poziomy Y. UwzglÄ™dnia wymiar kolanka (takeout) R.',
  bodyEn:
      'Calculates pipe spool lengths for a route with 3 Ã— 90Â° elbows: horizontal X â†’ vertical Î”H â†’ horizontal Y. Takes the elbow takeout R into account.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wpisz H1 i H2 â€” poziomy startowy i koÅ„cowy (rÃ³Å¼nica = Î”H).'),
    HelpStep('â†”ï¸', 'Wpisz X i Y â€” odlegÅ‚oÅ›ci poziome.'),
    HelpStep('ðŸ”„', 'Wpisz R â€” wymiar kolanka face-to-centre dla Twojego LR 90Â°.'),
    HelpStep('âœ…', 'Kliknij Oblicz â€” otrzymasz 3 dÅ‚ugoÅ›ci do ciÄ™cia.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Enter H1 and H2 â€” start and end elevations (difference = Î”H).'),
    HelpStep('â†”ï¸', 'Enter X and Y â€” horizontal distances.'),
    HelpStep('ðŸ”„', 'Enter R â€” elbow takeout face-to-centre for your LR 90Â°.'),
    HelpStep('âœ…', 'Tap Calculate â€” you get 3 cut lengths.'),
  ],
);

final kHelpRollingOffset = ScreenHelp(
  titlePl: 'Rolling Offset',
  titleEn: 'Rolling Offset',
  bodyPl:
      'Oblicza Travel (dÅ‚ugoÅ›Ä‡ odcinka) dla offsetu biegnÄ…cego jednoczeÅ›nie w pionie (Rise) i poziomie (Spread). Wzory: True Offset = âˆš(RiseÂ² + SpreadÂ²), Travel = True Offset / sin(Î¸).',
  bodyEn:
      'Calculates Travel (spool length) for an offset running simultaneously vertically (Rise) and horizontally (Spread). Formulas: True Offset = âˆš(RiseÂ² + SpreadÂ²), Travel = True Offset / sin(Î¸).',
  stepsPl: [
    HelpStep('â†•ï¸', 'Rise â€” odchylenie pionowe (w mm).'),
    HelpStep('â†”ï¸', 'Spread â€” odchylenie poziome (w mm).'),
    HelpStep('ðŸ”„', 'KÄ…t kolanka â€” wybierz 45Â°, 30Â°, 60Â° lub podaj wÅ‚asny.'),
    HelpStep('ðŸ“', 'Wynik: True Offset, Travel, Run i Multiplier.'),
  ],
  stepsEn: [
    HelpStep('â†•ï¸', 'Rise â€” vertical deviation (in mm).'),
    HelpStep('â†”ï¸', 'Spread â€” horizontal deviation (in mm).'),
    HelpStep('ðŸ”„', 'Elbow angle â€” choose 45Â°, 30Â°, 60Â° or enter your own.'),
    HelpStep('ðŸ“', 'Results: True Offset, Travel, Run and Multiplier.'),
  ],
);

final kHelpPipeSlope = ScreenHelp(
  titlePl: 'Spadek rury',
  titleEn: 'Pipe slope',
  bodyPl:
      'Przelicza spadek rury miÄ™dzy formatami: procent (%), milimetry na metr (mm/m) i kÄ…t w stopniach. MoÅ¼esz teÅ¼ obliczyÄ‡ rise (wysokoÅ›Ä‡) dla danej dÅ‚ugoÅ›ci i spadku.',
  bodyEn:
      'Converts pipe slope between formats: percent (%), millimetres per metre (mm/m) and angle in degrees. You can also calculate rise (height) for a given length and slope.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wybierz tryb: dÅ‚ugoÅ›Ä‡â†’rise, riseâ†’dÅ‚ugoÅ›Ä‡ lub slope ze znanych wartoÅ›ci.'),
    HelpStep('ðŸ”¢', 'Wpisz dane i kliknij Oblicz.'),
    HelpStep('ðŸ“Š', 'Wynik pokazuje slope w %, mm/m i stopniach rÃ³wnoczeÅ›nie.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Choose mode: lengthâ†’rise, riseâ†’length or slope from known values.'),
    HelpStep('ðŸ”¢', 'Enter the data and tap Calculate.'),
    HelpStep('ðŸ“Š', 'Result shows slope in %, mm/m and degrees simultaneously.'),
  ],
);

final kHelpSaddleCut = ScreenHelp(
  titlePl: 'Saddle Cut (wyciÄ™cie siodÅ‚owe)',
  titleEn: 'Saddle Cut (fish-mouth cut)',
  bodyPl:
      'Oblicza gÅ‚Ä™bokoÅ›Ä‡ wyciÄ™cia siodÅ‚owego na rurze odgaÅ‚Ä™zieniowej dla prostopadÅ‚ego poÅ‚Ä…czenia T. Wynik to profil naciÄ™cia w 8 punktach kÄ…towych wokÃ³Å‚ obwodu rury.',
  bodyEn:
      'Calculates the saddle cut depth on the branch pipe for a perpendicular T-junction. The result is the cut profile at 8 angular positions around the pipe circumference.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wpisz OD rury gÅ‚Ã³wnej (header) i rury odgaÅ‚Ä™zieniowej (branch).'),
    HelpStep('ðŸ“Š', 'Profil pokazuje gÅ‚Ä™bokoÅ›Ä‡ ciÄ™cia co 22.5Â° (0Â°, 22.5Â°, 45Â°... 90Â°).'),
    HelpStep('ðŸ’¡', 'GÅ‚Ä™bokoÅ›Ä‡ 0 mm jest na wierzchoÅ‚ku (90Â°), max na boku (0Â°).'),
  ],
  stepsEn: [
    HelpStep('ðŸ“', 'Enter the OD of the header pipe and the branch pipe.'),
    HelpStep('ðŸ“Š', 'Profile shows cut depth every 22.5Â° (0Â°, 22.5Â°, 45Â°... 90Â°).'),
    HelpStep('ðŸ’¡', 'Depth 0 mm is at the top (90Â°), maximum depth is at the side (0Â°).'),
  ],
);

final kHelpRouteMeasure = ScreenHelp(
  titlePl: 'Pomiar trasy',
  titleEn: 'Route measure',
  bodyPl:
      'Przelicza wymiary zmierzone taÅ›mÄ… na wymiary C-C (oÅ› do osi). Podaj wymiar boku A i B, OD rury i wymiar kolanka do osi â€” aplikacja obliczy wymiary C-C i dÅ‚ugoÅ›ci do ciÄ™cia.',
  bodyEn:
      'Converts tape-measured dimensions to C-C (centre-to-centre) dimensions. Enter side A and B dimensions, pipe OD and elbow centre-to-face â€” the app calculates C-C dimensions and cut lengths.',
  stepsPl: [
    HelpStep('ðŸ“', 'Wybierz typ pomiaru: inner (wewnÄ…trz), center (C-C) lub outer (zewnÄ…trz).'),
    HelpStep('ðŸ”¢', 'Wpisz wymiary A, B, OD rury i wymiar kolanka do osi (C-F).'),
    HelpStep('ðŸ“', 'Wynik: dÅ‚ugoÅ›ci C-C dla obu bokÃ³w, kÄ…t skos i dÅ‚ugoÅ›ci do ciÄ™cia.'),
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
  titlePl: 'Parametry spawania â€” Rury',
  titleEn: 'Welding parameters â€” Pipes',
  bodyPl:
      'Zestawy parametrÃ³w spawania TIG dla rur: prÄ…d (AMP), gazy osÅ‚onowe, zatwierdzone WPS i Twoje wÅ‚asne zestawy. PrzeglÄ…daj i edytuj zestawy dopasowane do Å›rednicy i gruboÅ›ci Å›cianki.',
  bodyEn:
      'TIG welding parameter sets for pipes: current (AMP), shielding gases, approved WPS and your own sets. Browse and edit sets matched to pipe OD and wall thickness.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'AMP â€” referencyjne prÄ…dy dla typowych Å›rednic rur SS/CS.'),
    HelpStep('ðŸ’¨', 'Gazy â€” zalecane mieszanki i przepÅ‚ywy dla rÃ³Å¼nych materiaÅ‚Ã³w.'),
    HelpStep('âœ…', 'Zatwierdzone â€” zestawy WPS zatwierdzone w Twoim zakÅ‚adzie.'),
    HelpStep('ðŸ‘¤', 'Moje â€” wÅ‚asne zestawy parametrÃ³w zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'AMP â€” reference currents for typical pipe diameters SS/CS.'),
    HelpStep('ðŸ’¨', 'Gases â€” recommended mixes and flow rates for different materials.'),
    HelpStep('âœ…', 'Approved â€” WPS sets approved in your workshop.'),
    HelpStep('ðŸ‘¤', 'Mine â€” your own parameter sets saved locally.'),
  ],
);

final kHelpWelderTanks = ScreenHelp(
  titlePl: 'Parametry spawania â€” Zbiorniki',
  titleEn: 'Welding parameters â€” Tanks',
  bodyPl:
      'Zestawy parametrÃ³w spawania TIG dla zbiornikÃ³w i wiÄ™kszych przekrojÃ³w, w tym tandem TIG (dwa palniki). Zawiera zakÅ‚adki AMP i Tandem TIG.',
  bodyEn:
      'TIG welding parameter sets for tanks and larger sections, including tandem TIG (two torches). Contains AMP and Tandem TIG tabs.',
  stepsPl: [
    HelpStep('âš¡', 'AMP â€” referencyjne prÄ…dy dla zgrzewÃ³w obwodowych i podÅ‚uÅ¼nych zbiornikÃ³w.'),
    HelpStep('ðŸ”€', 'Tandem TIG â€” parametry dla procesu z dwoma elektrodami (lead + trail).'),
  ],
  stepsEn: [
    HelpStep('âš¡', 'AMP â€” reference currents for circumferential and longitudinal tank welds.'),
    HelpStep('ðŸ”€', 'Tandem TIG â€” parameters for the dual-electrode process (lead + trail).'),
  ],
);

final kHelpWelderTools = ScreenHelp(
  titlePl: 'Kalkulatory â€” Spawacz',
  titleEn: 'Calculators â€” Welder',
  bodyPl:
      'Kalkulatory spawalnicze w zakÅ‚adkach: Heat Input (kJ/mm), Temperatura podgrzewania, Purge Oâ‚‚, ZuÅ¼ycie gazu, Timer spawania i Przelicznik ciÅ›nienia.',
  bodyEn:
      'Welding calculators in tabs: Heat Input (kJ/mm), Preheat temperature, Oâ‚‚ purge, Gas consumption, Weld timer and Pressure converter.',
  stepsPl: [
    HelpStep('ðŸŒ¡ï¸', 'Heat Input â€” oblicza kJ/mm ze: napiÄ™cia, prÄ…du i prÄ™dkoÅ›ci spawania.'),
    HelpStep('ðŸ”¥', 'Temperatura â€” wymagana temperatura podgrzewania wg gruboÅ›ci i C.E.'),
    HelpStep('ðŸ’¨', 'Oâ‚‚ Purge â€” czas i iloÅ›Ä‡ gazu do wypÅ‚ukania rury przed spawaniem.'),
    HelpStep('â±ï¸', 'Timer â€” stoper do mierzenia czasu Å‚uku dla heat input.'),
  ],
  stepsEn: [
    HelpStep('ðŸŒ¡ï¸', 'Heat Input â€” calculates kJ/mm from: voltage, current and travel speed.'),
    HelpStep('ðŸ”¥', 'Preheat â€” required preheat temperature based on thickness and C.E.'),
    HelpStep('ðŸ’¨', 'Oâ‚‚ Purge â€” time and gas volume to purge a pipe before welding.'),
    HelpStep('â±ï¸', 'Timer â€” stopwatch to measure arc time for heat input.'),
  ],
);

final kHelpWeldJournal = ScreenHelp(
  titlePl: 'Dziennik spoin',
  titleEn: 'Weld journal',
  bodyPl:
      'Rejestr spoin dla danego projektu. KaÅ¼dy wpis zawiera numer spoiny, materiaÅ‚, OD, gruboÅ›Ä‡ Å›cianki, metodÄ™ spawania, spawacza, datÄ™ i status (OK / NOK / Pending).',
  bodyEn:
      'A weld register for a project. Each entry contains the weld number, material, OD, wall thickness, welding method, welder, date and status (OK / NOK / Pending).',
  stepsPl: [
    HelpStep('âž•', 'Dodaj nowÄ… spoinÄ™ przyciskiem + (gÃ³ra prawo).'),
    HelpStep('âœï¸', 'Dotknij spoiny aby edytowaÄ‡ jej dane.'),
    HelpStep('ðŸŸ¢', 'ZmieÅ„ status: OK (zielony), NOK (czerwony), Pending (pomaraÅ„czowy).'),
    HelpStep('ðŸ“¤', 'Eksportuj dziennik do PDF lub CSV.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a new weld with the + button (top right).'),
    HelpStep('âœï¸', 'Tap a weld entry to edit its data.'),
    HelpStep('ðŸŸ¢', 'Change status: OK (green), NOK (red), Pending (orange).'),
    HelpStep('ðŸ“¤', 'Export the journal to PDF or CSV.'),
  ],
);

final kHelpMaterialList = ScreenHelp(
  titlePl: 'Lista materiaÅ‚Ã³w',
  titleEn: 'Material list',
  bodyPl:
      'Zestawienie wszystkich materiaÅ‚Ã³w dla segmentu lub projektu. Pokazuje rury, komponenty i ich iloÅ›ci. MoÅ¼esz wyeksportowaÄ‡ listÄ™ lub skopiowaÄ‡ do schowka.',
  bodyEn:
      'A material breakdown for a segment or project. Shows pipes, components and their quantities. You can export the list or copy it to the clipboard.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'KaÅ¼dy wiersz to jeden typ elementu z iloÅ›ciÄ… i jednostkÄ….'),
    HelpStep('ðŸ“¤', 'Eksportuj przyciskiem w gÃ³rnym prawym rogu (PDF lub schowek).'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'Each row is one type of element with quantity and unit.'),
    HelpStep('ðŸ“¤', 'Export with the button in the top right (PDF or clipboard).'),
  ],
);

final kHelpTandemMenu = ScreenHelp(
  titlePl: 'Tandem TIG â€” Menu',
  titleEn: 'Tandem TIG â€” Menu',
  bodyPl:
      'ModuÅ‚ Tandem TIG. Znajdziesz tu kalkulator parametrÃ³w tandem, bibliotekÄ™ zapisanych zestawÃ³w i Twoje wÅ‚asne parametry do szybkiego dostÄ™pu.',
  bodyEn:
      'The Tandem TIG module. Here you find the tandem parameter calculator, a library of saved sets and your own parameters for quick access.',
  stepsPl: [
    HelpStep('ðŸ§®', 'Kalkulator â€” oblicz parametry lead i trail na podstawie materiaÅ‚u i OD.'),
    HelpStep('ðŸ“š', 'Biblioteka â€” przeglÄ…daj zestawy zatwierdzone dla rÃ³Å¼nych aplikacji.'),
    HelpStep('ðŸ‘¤', 'Moje parametry â€” Twoje wÅ‚asne zestawy zapisane lokalnie.'),
  ],
  stepsEn: [
    HelpStep('ðŸ§®', 'Calculator â€” calculate lead and trail parameters based on material and OD.'),
    HelpStep('ðŸ“š', 'Library â€” browse sets approved for different applications.'),
    HelpStep('ðŸ‘¤', 'My params â€” your own parameter sets saved locally.'),
  ],
);

final kHelpTandemCalc = ScreenHelp(
  titlePl: 'Kalkulator Tandem TIG',
  titleEn: 'Tandem TIG Calculator',
  bodyPl:
      'Oblicza parametry procesu Tandem TIG (lead + trail) dla spawania zbiornikÃ³w i duÅ¼ych przekrojÃ³w. Wyniki zawierajÄ… sugerowane prÄ…dy, napiÄ™cia, prÄ™dkoÅ›Ä‡ spawania i heat input.',
  bodyEn:
      'Calculates Tandem TIG process parameters (lead + trail) for tank and large-section welding. Results include suggested currents, voltages, travel speed and heat input.',
  stepsPl: [
    HelpStep('ðŸ”¢', 'Wpisz OD, gruboÅ›Ä‡ Å›cianki i materiaÅ‚.'),
    HelpStep('âš¡', 'Wybierz tryb spawania i pozycjÄ™.'),
    HelpStep('âœ…', 'Kliknij Oblicz aby zobaczyÄ‡ parametry lead i trail.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter OD, wall thickness and material.'),
    HelpStep('âš¡', 'Choose the welding mode and position.'),
    HelpStep('âœ…', 'Tap Calculate to see lead and trail parameters.'),
  ],
);

final kHelpWelderPipeParams = ScreenHelp(
  titlePl: 'Lista parametrÃ³w spawania rur',
  titleEn: 'Pipe welding parameters list',
  bodyPl:
      'Lista Twoich wÅ‚asnych zestawÃ³w parametrÃ³w spawania rur TIG. KaÅ¼dy zestaw zawiera prÄ…d, napiÄ™cie, gaz, przepÅ‚yw i dodatkowe notatki. Zestawy sÄ… przechowywane lokalnie.',
  bodyEn:
      'A list of your own TIG pipe welding parameter sets. Each set contains current, voltage, gas, flow rate and additional notes. Sets are stored locally on the device.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj nowy zestaw przyciskiem +.'),
    HelpStep('âœï¸', 'Dotknij zestawu aby edytowaÄ‡ parametry.'),
    HelpStep('ðŸ—‘ï¸', 'PrzesuÅ„ w lewo aby usunÄ…Ä‡ zestaw.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a new set with the + button.'),
    HelpStep('âœï¸', 'Tap a set to edit its parameters.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a set.'),
  ],
);

final kHelpSpoolPlanner = ScreenHelp(
  titlePl: 'Projektant trasy 3D',
  titleEn: 'Route planner 3D',
  bodyPl:
      'Wizualny projektant 3D trasy rurowej. Definiujesz kolejne odcinki w osiach X, Y i Z, a aplikacja rysuje podglÄ…d trasy i oblicza sumaryczne dÅ‚ugoÅ›ci w kaÅ¼dym kierunku.',
  bodyEn:
      'A 3D visual pipe route planner. Define successive segments along X, Y and Z axes and the app draws a route preview and calculates total lengths in each direction.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj odcinek: wybierz oÅ› (X/Y/Z) i wpisz dÅ‚ugoÅ›Ä‡.'),
    HelpStep('ðŸ”„', 'PodglÄ…d 3D obraca siÄ™ automatycznie po kaÅ¼dym dodaniu.'),
    HelpStep('ðŸ—‘ï¸', 'UsuÅ„ ostatni odcinek przyciskiem Cofnij.'),
    HelpStep('ðŸ“Š', 'Zestawienie na dole pokazuje sumy w osi X, Y i Z.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a segment: choose axis (X/Y/Z) and enter the length.'),
    HelpStep('ðŸ”„', 'The 3D preview rotates automatically after each addition.'),
    HelpStep('ðŸ—‘ï¸', 'Remove the last segment with the Undo button.'),
    HelpStep('ðŸ“Š', 'The summary at the bottom shows totals for X, Y and Z axes.'),
  ],
);

final kHelpHeatPhotos = ScreenHelp(
  titlePl: 'Heat Numbers â€” zdjÄ™cia',
  titleEn: 'Heat Numbers â€” photos',
  bodyPl:
      'Galeria zdjÄ™Ä‡ certyfikatÃ³w materiaÅ‚owych (heat numbers) przypisanych do projektu. MoÅ¼esz dodawaÄ‡, przeglÄ…daÄ‡ i usuwaÄ‡ zdjÄ™cia etykiet materiaÅ‚owych dla identyfikowalnoÅ›ci (traceability).',
  bodyEn:
      'A photo gallery of material certificates (heat numbers) assigned to the project. You can add, view and delete label photos for material traceability.',
  stepsPl: [
    HelpStep('ðŸ“·', 'Dodaj zdjÄ™cie aparatem lub z galerii przyciskiem +.'),
    HelpStep('ðŸ”', 'Dotknij miniatury aby zobaczyÄ‡ peÅ‚ny podglÄ…d.'),
    HelpStep('ðŸ—‘ï¸', 'Przytrzymaj miniaturÄ™ aby usunÄ…Ä‡ zdjÄ™cie.'),
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
      'Widok komponentÃ³w projektu z przypisaniem numerÃ³w wytopÃ³w (heat numbers). Dla kaÅ¼dego komponentu moÅ¼esz przypisaÄ‡ numer certyfikatu materiaÅ‚owego i zdjÄ™cie etykiety.',
  bodyEn:
      'Project component view with heat number assignment. For each component you can assign a material certificate number and a label photo.',
  stepsPl: [
    HelpStep('ðŸ”¢', 'Wpisz numer heatu (wytopienia) dla kaÅ¼dego komponentu.'),
    HelpStep('ðŸ“·', 'Dodaj zdjÄ™cie certyfikatu materiaÅ‚owego przyciskiem aparatu.'),
    HelpStep('âœ…', 'Zapisz przypisania przyciskiem w gÃ³rnym prawym rogu.'),
  ],
  stepsEn: [
    HelpStep('ðŸ”¢', 'Enter the heat number for each component.'),
    HelpStep('ðŸ“·', 'Add a material certificate photo with the camera button.'),
    HelpStep('âœ…', 'Save the assignments with the button in the top right.'),
  ],
);

final kHelpFieldAssembly = ScreenHelp(
  titlePl: 'MontaÅ¼ w terenie',
  titleEn: 'Field assembly',
  bodyPl:
      'NarzÄ™dzie do planowania i dokumentowania montaÅ¼u w terenie. Rejestruj status kaÅ¼dego spool\'a (prefabrykatu) â€” gotowy do spawania, spawany lub zamontowany.',
  bodyEn:
      'A tool for planning and documenting field assembly. Record the status of each spool (prefab) â€” ready to weld, welded or installed.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'Lista spoolÃ³w pokazuje status kaÅ¼dego prefabrykatu.'),
    HelpStep('âœ…', 'Dotknij spool\'a aby zmieniÄ‡ jego status montaÅ¼u.'),
    HelpStep('ðŸ“¤', 'Eksportuj raport statusu przyciskiem w gÃ³rnym prawym rogu.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'The spool list shows the status of each prefab.'),
    HelpStep('âœ…', 'Tap a spool to change its assembly status.'),
    HelpStep('ðŸ“¤', 'Export the status report with the button in the top right.'),
  ],
);

final kHelpTandemLibrary = ScreenHelp(
  titlePl: 'Biblioteka â€” Tandem TIG',
  titleEn: 'Library â€” Tandem TIG',
  bodyPl:
      'Biblioteka zatwierdzonych zestawÃ³w parametrÃ³w Tandem TIG. KaÅ¼dy zestaw zawiera prÄ…dy lead i trail, napiÄ™cia i prÄ™dkoÅ›Ä‡ dla danego przekroju i materiaÅ‚u.',
  bodyEn:
      'Library of approved Tandem TIG parameter sets. Each set contains lead and trail currents, voltages and travel speed for the given section and material.',
  stepsPl: [
    HelpStep('ðŸ“‹', 'PrzeglÄ…daj zatwierdzone zestawy wedÅ‚ug materiaÅ‚u i gruboÅ›ci.'),
    HelpStep('ðŸ‘†', 'Dotknij zestawu aby zobaczyÄ‡ peÅ‚ne parametry.'),
  ],
  stepsEn: [
    HelpStep('ðŸ“‹', 'Browse approved sets by material and thickness.'),
    HelpStep('ðŸ‘†', 'Tap a set to view the full parameters.'),
  ],
);

final kHelpTandemMyParams = ScreenHelp(
  titlePl: 'Moje parametry â€” Tandem TIG',
  titleEn: 'My parameters â€” Tandem TIG',
  bodyPl:
      'Twoje wÅ‚asne zestawy parametrÃ³w Tandem TIG zapisane lokalnie. Dodawaj, edytuj i usuwaj zestawy dopasowane do Twoich warunkÃ³w i materiaÅ‚Ã³w.',
  bodyEn:
      'Your own Tandem TIG parameter sets saved locally. Add, edit and delete sets tailored to your conditions and materials.',
  stepsPl: [
    HelpStep('âž•', 'Dodaj nowy zestaw przyciskiem +.'),
    HelpStep('âœï¸', 'Dotknij zestawu aby edytowaÄ‡ parametry.'),
    HelpStep('ðŸ—‘ï¸', 'PrzesuÅ„ w lewo aby usunÄ…Ä‡ zestaw.'),
  ],
  stepsEn: [
    HelpStep('âž•', 'Add a new set with the + button.'),
    HelpStep('âœï¸', 'Tap a set to edit its parameters.'),
    HelpStep('ðŸ—‘ï¸', 'Swipe left to delete a set.'),
  ],
);
