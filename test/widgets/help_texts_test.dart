// Teksty pomocy (ikona „?” w pasku) muszą opisywać aplikację, która jest —
// nie usunięte zakładki, stare nazwy narzędzi ani „wymaganą” temperaturę,
// której kalkulator nie może wyznaczyć.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/widgets/help_button.dart';

String _all(ScreenHelp h) => [
      h.titlePl,
      h.titleEn,
      h.bodyPl,
      h.bodyEn,
      for (final s in h.stepsPl) s.text,
      for (final s in h.stepsEn) s.text,
    ].join('\n');

String _pl(ScreenHelp h) =>
    [h.titlePl, h.bodyPl, for (final s in h.stepsPl) s.text].join('\n');

final _allHelps = <String, ScreenHelp>{
  'kHelpProjects': kHelpProjects,
  'kHelpFitter': kHelpFitter,
  'kHelpSegmentBuilder': kHelpSegmentBuilder,
  'kHelpComponentLibrary': kHelpComponentLibrary,
  'kHelpCutListSummary': kHelpCutListSummary,
  'kHelpFitterTools': kHelpFitterTools,
  'kHelpDnMm': kHelpDnMm,
  'kHelpPipeRoute': kHelpPipeRoute,
  'kHelpRollingOffset': kHelpRollingOffset,
  'kHelpPipeSlope': kHelpPipeSlope,
  'kHelpSaddleCut': kHelpSaddleCut,
  'kHelpIsoNotebook': kHelpIsoNotebook,
  'kHelpWelderPipes': kHelpWelderPipes,
  'kHelpWelderTanks': kHelpWelderTanks,
  'kHelpWelderTools': kHelpWelderTools,
  'kHelpHeatInput': kHelpHeatInput,
  'kHelpWeldJournal': kHelpWeldJournal,
  'kHelpMaterialList': kHelpMaterialList,
  'kHelpTandemMenu': kHelpTandemMenu,
  'kHelpTandemCalc': kHelpTandemCalc,
  'kHelpWelderPipeParams': kHelpWelderPipeParams,
  'kHelpHeatPhotos': kHelpHeatPhotos,
  'kHelpProjectComponents': kHelpProjectComponents,
  'kHelpTandemLibrary': kHelpTandemLibrary,
  'kHelpTandemMyParams': kHelpTandemMyParams,
  'kHelpCertificateRegister': kHelpCertificateRegister,
  'kHelpWpsLibrary': kHelpWpsLibrary,
};

void main() {
  test('kalkulatory spawacza: tylko istniejące zakładki, bez heat input', () {
    final t = _all(kHelpWelderTools);
    expect(t, isNot(contains('Heat Input')));
    expect(t, isNot(contains('wymagana')));
    for (final tab in ['Gaz', 'O₂', 'Timer', 'Ciśnienie']) {
      expect(_pl(kHelpWelderTools), contains(tab), reason: tab);
    }
    expect(t, contains('Heat input i CE'),
        reason: 'odsyła tam, gdzie heat input jest teraz');
  });

  test('heat input i CE: podgrzewanie szacunkowe, wiąże WPS / EN 1011-2 / '
      'minimum kodowe', () {
    final pl = _pl(kHelpHeatInput);
    expect(pl, contains('szacunkowa'));
    expect(pl, isNot(contains('wymagana')));
    for (final binding in ['WPS', 'EN 1011-2', 'minimum kodowe']) {
      expect(pl, contains(binding), reason: binding);
    }
    expect(_all(kHelpHeatInput), contains('η z WPS'));
  });

  test('ekrany heat input i kalkulatorów spawacza mają swoją pomoc', () {
    final heat = File('lib/screens/heat_input_screen.dart').readAsStringSync();
    expect(heat, contains('HelpButton(help: kHelpHeatInput)'));
    final tools = File('lib/screens/welder_tools_screen.dart').readAsStringSync();
    expect(tools, contains('HelpButton(help: kHelpWelderTools)'));
  });

  test('zeszyt ISO: autozapis i menu „Szkice”', () {
    final pl = _pl(kHelpIsoNotebook);
    expect(pl, contains('zapisuje się sam'));
    expect(pl, contains('„Szkice”'));
    expect(pl, contains('Nowy szkic'));
    expect(pl, contains('Zapisane szkice'));
    expect(_all(kHelpIsoNotebook), contains('Saved sketches'));
  });

  test('trasa rur: 2 kolana 90° (nie 3), łuki 2 × π·R/2', () {
    final pl = _pl(kHelpPipeRoute);
    expect(pl, contains('2 kolanami 90°'));
    expect(pl, isNot(contains('3 kołnami')));
    expect(pl, contains('π·R/2'));
    expect(_all(kHelpPipeRoute), isNot(contains('3 × 90°')));
  });

  test('rolling offset: kąt obrotu kolana i opcjonalna długość cięcia', () {
    final pl = _pl(kHelpRollingOffset);
    expect(pl, contains('od pionu'));
    expect(pl, contains('od poziomu'));
    expect(pl, contains('Travel − 2 × take-out − 2 × szczelina'));
    expect(_all(kHelpRollingOffset), contains('Travel − 2 × take-out − 2 × gap'));
  });

  test('stare nazwy narzędzi zniknęły z pomocy', () {
    for (final e in _allHelps.entries) {
      final t = _all(e.value);
      expect(t, isNot(contains('Saddle / Coping')), reason: e.key);
      expect(t, isNot(contains('Heat Input + CE')), reason: e.key);
      // W polskim interfejsie moduł nazywa się MONTER.
      expect(_pl(e.value), isNot(contains('FITTER')), reason: e.key);
      expect(e.value.titlePl, isNot(contains('Fitter')), reason: e.key);
    }
    expect(kHelpSaddleCut.titlePl, contains('Siodło 90°'));
    expect(_pl(kHelpSaddleCut), contains('Szablon siodła do druku'));
  });

  test('nieużywane wpisy pomocy usunięte z help_button.dart', () {
    final src = File('lib/widgets/help_button.dart').readAsStringSync();
    for (final gone in [
      'kHelpHome',
      'kHelpFitterMenu',
      'kHelpWelderMenu',
      'kHelpRouteMeasure',
      'kHelpSpoolPlanner',
      'kHelpFieldAssembly',
    ]) {
      expect(src, isNot(contains('final $gone ')), reason: gone);
    }
  });

  test('rury: „Startowe” to dane z aplikacji, nie WPS zakładu; odsyła do '
      'Biblioteki WPS', () {
    final t = _all(kHelpWelderPipes);
    expect(t, isNot(contains('zatwierdzone w Twoim zakładzie')));
    expect(t, isNot(contains('approved in your workshop')));
    expect(_pl(kHelpWelderPipes), contains('Startowe'));
    expect(_pl(kHelpWelderPipes), contains('orientacyjne'));
    expect(_pl(kHelpWelderPipes), contains('Bibliotece WPS'));
    final screen =
        File('lib/screens/welder_pipes_screen.dart').readAsStringSync();
    expect(screen, isNot(contains("Tab(text: _tr('Zatwierdzone'")));
  });

  test('zbiorniki: brak zakładki AMP i „lead + trail”; brak danych poza '
      'zakresem; wiąże WPS', () {
    final t = _all(kHelpWelderTanks);
    expect(t, isNot(contains('lead + trail')));
    expect(t, isNot(contains('AMP —')));
    expect(_pl(kHelpWelderTanks), contains('brak danych dla tej grubości'));
    expect(_pl(kHelpWelderTanks), contains('wiąże WPS'));
    expect(_pl(kHelpWelderTanks), contains('Startowe'));
  });

  test('rejestr uprawnień i Biblioteka WPS mają pomoc', () {
    final register = File(
            'lib/features/qualification/certificate_register_page.dart')
        .readAsStringSync();
    expect(register, contains('HelpButton(help: kHelpCertificateRegister)'));
    final library =
        File('lib/features/wps/wps_library_page.dart').readAsStringSync();
    expect(library, contains('HelpButton(help: kHelpWpsLibrary)'));
    expect(_pl(kHelpCertificateRegister), contains('6-miesięcznej'));
    expect(_pl(kHelpWpsLibrary), contains('Wybierz WPS'));
    expect(_pl(kHelpWeldJournal), contains('Zapisz mimo to'));
  });
}
