import 'help_button.dart';

// Pomoc do menu montera i spawacza po przebudowie na pogrupowaną listę.
// Poprzednie treści (kHelpFitterMenu / kHelpWelderMenu w help_button.dart)
// opisywały płaską siatkę kafli i nazwę „FITTER" — te są aktualne.

const kFitterMenuHelp = ScreenHelp(
  titlePl: 'Menu Monter',
  titleEn: 'Fitter menu',
  bodyPl: 'Narzędzia montera rur, pogrupowane według pracy: cięcie i projekty, '
      'kolana i kształtki, odgałęzienia, trasa i spadki, tabele, podpory i '
      'kołnierze. Wszystko działa bez internetu.',
  bodyEn: 'Pipe fitter tools grouped by job: cutting and projects, elbows and '
      'fittings, branches, route and slope, tables, supports and flanges. '
      'Everything works offline.',
  stepsPl: [
    HelpStep('📋', 'Lista cięć — projekty, segmenty i długości do cięcia.'),
    HelpStep(
        '📐', 'Kolana i kształtki — wymiary kolan, cięcie i obrót kolanka.'),
    HelpStep(
        '📌', 'Przytrzymaj narzędzie, żeby przypiąć je na ekranie głównym.'),
    HelpStep('🔍', 'Na ekranie głównym wpisz nazwę albo słowo, np. „kolano".'),
  ],
  stepsEn: [
    HelpStep('📋', 'Cut list — projects, segments and cut lengths.'),
    HelpStep('📐', 'Elbows and fittings — takeouts, elbow cut and rotation.'),
    HelpStep('📌', 'Long-press a tool to pin it to the home screen.'),
    HelpStep('🔍', 'On the home screen, type a name or a word, e.g. "elbow".'),
  ],
);

const kWelderMenuHelp = ScreenHelp(
  titlePl: 'Menu Spawacz',
  titleEn: 'Welder menu',
  bodyPl: 'Narzędzia spawacza: parametry dla rur i zbiorników, kalkulatory '
      '(heat input i CE, gaz, formowanie, timer), kontrola i dokumentacja '
      'spoin oraz wykończenie stali nierdzewnej.',
  bodyEn:
      'Welder tools: parameters for pipes and tanks, calculators (heat input '
      'and CE, gas, purge, timer), weld inspection and records, and stainless '
      'finishing.',
  stepsPl: [
    HelpStep(
        '🔥', 'Heat input i CE — energia liniowa i podgrzewanie z chemii.'),
    HelpStep('📝', 'Dziennik spoin — numeracja, weld map, stempel spawacza.'),
    HelpStep(
        '📌', 'Przytrzymaj narzędzie, żeby przypiąć je na ekranie głównym.'),
  ],
  stepsEn: [
    HelpStep(
        '🔥', 'Heat input and CE — arc energy and preheat from chemistry.'),
    HelpStep('📝', 'Weld journal — numbering, weld map, welder stamp.'),
    HelpStep('📌', 'Long-press a tool to pin it to the home screen.'),
  ],
);
