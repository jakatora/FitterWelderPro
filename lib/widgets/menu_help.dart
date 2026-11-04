import 'help_button.dart';

// Pomoc do menu montera i spawacza po przebudowie na pogrupowaną listę.
// Zastąpiła dawne kHelpFitterMenu / kHelpWelderMenu / kHelpHome z
// help_button.dart (płaska siatka kafli, nazwa „FITTER") — tamte usunięto.

const kFitterMenuHelp = ScreenHelp(
  titlePl: 'Menu Monter',
  titleEn: 'Fitter menu',
  bodyPl: 'Narzędzia montera rur, pogrupowane według pracy: cięcie i projekty, '
      'kolana i kształtki, odgałęzienia, trasa i spadki, tabele, podpory i '
      'kołnierze. Lokalne kalkulatory działają bez internetu; skaner rysunków '
      'wymaga połączenia.',
  bodyEn: 'Pipe fitter tools grouped by job: cutting and projects, elbows and '
      'fittings, branches, route and slope, tables, supports and flanges. '
      'Local calculators work offline; the drawing scanner needs an internet '
      'connection.',
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
  bodyPl: 'Wybierz grupę, aby zobaczyć jej narzędzia: Parametry spawania, '
      'Kalkulatory, Kontrola i badania, Bezpieczeństwo pracy, Dokumentacja i '
      'uprawnienia, Wykończenie nierdzewki albo Wyceny i koszty.',
  bodyEn: 'Choose a group to see its tools: Welding parameters, Calculators, '
      'Inspection and testing, Work safety, Records and qualifications, '
      'Stainless finishing, or Quotes and costs.',
  stepsPl: [
    HelpStep(
        '🔥', 'Heat input i CE — energia liniowa i podgrzewanie z chemii.'),
    HelpStep('📝', 'Dokumentacja i uprawnienia — znajdziesz tu dziennik spoin i bibliotekę WPS.'),
    HelpStep(
        '📌', 'Przytrzymaj narzędzie, żeby przypiąć je na ekranie głównym.'),
  ],
  stepsEn: [
    HelpStep(
        '🔥', 'Heat input and CE — arc energy and preheat from chemistry.'),
    HelpStep('📝', 'Records and qualifications — find the weld journal and WPS library here.'),
    HelpStep('📌', 'Long-press a tool to pin it to the home screen.'),
  ],
);
