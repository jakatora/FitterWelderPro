// Ekran „Wady spoin: przyczyny i naprawa”: wybór wady → przyczyny i naprawa,
// wyszukiwanie po numerze ISO i nazwie, przejście do ISO 5817, wersja EN,
// wąski telefon przy dużej czcionce, cele dotyku i udostępnianie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/defects/defect_advice.dart';
import 'package:cut_list_app/features/iso5817/iso5817_page.dart';
import 'package:cut_list_app/features/weld_defects/weld_defects_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(1000, 4000),
  double textScale = 1.0,
  WeldDefectsShareFn? onShare,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WeldDefectsPage(onShare: onShare),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija leniwą listę ekranu tak, żeby element [k] był zbudowany
/// i widoczny (najpierw w górę, potem w dół).
Future<void> _reveal(WidgetTester tester, String k) async {
  final f = _key(k);
  if (f.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
            of: _key('defects-list'), matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 300,
          scrollable: scrollable, maxScrolls: 200);
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String k) async {
  await _reveal(tester, k);
  await tester.tap(_key(k));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String q) async {
  await _reveal(tester, 'defects-search');
  await tester.enterText(_key('defects-search'), q);
  await tester.pumpAndSettle();
}

/// Kolejność kafli wyników (id wad) od góry.
List<String> _tileIds(WidgetTester tester) {
  final tiles = find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('defects-pick-'));
  final elements = tiles.evaluate().toList()
    ..sort((a, b) => tester
        .getTopLeft(find.byWidget(a.widget))
        .dy
        .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
  return [
    for (final e in elements)
      (e.widget.key as ValueKey<String>).value.substring('defects-pick-'.length)
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('start: lista wad w grupach ISO 6520-1, disclaimer, bez wyniku',
      (tester) async {
    await _pump(tester);
    expect(find.text('Wady spoin: przyczyny i naprawa'), findsOneWidget);
    expect(_key('defects-disclaimer'), findsOneWidget);
    expect(find.textContaining('Wiążące są WPS'), findsOneWidget);
    expect(find.text('1xx · Pęknięcia'), findsOneWidget);
    expect(find.text('5xx · Niezgodności kształtu i wymiarów'), findsOneWidget);
    expect(_key('defects-pick-undercut'), findsOneWidget);
    expect(_key('defects-pick-porosity'), findsOneWidget);
    expect(_key('defects-repair'), findsNothing);
    expect(_key('defects-share'), findsNothing);
  });

  testWidgets(
      '„5011” → podtopienie → MAG: przyczyny, naprawa, lista i ISO 5817',
      (tester) async {
    await _pump(tester);
    await _search(tester, '5011');
    expect(_tileIds(tester).first, 'undercut');

    await _tapKey(tester, 'defects-pick-undercut');
    expect(_key('defects-selected'), findsOneWidget);
    expect(find.text('5011 · Podtopienie ciągłe'), findsOneWidget);
    // Bez procesu nie ma przyczyn — proces trzeba wybrać.
    expect(_key('defects-pick-process'), findsOneWidget);
    expect(_key('defects-repair'), findsNothing);

    await _tapKey(tester, 'defects-process-mag135');
    final advice = defectAdvice(
        weldDefectById('undercut')!, DefectProcess.mag135)!;
    expect(advice.causes, isNotEmpty);
    for (final c in advice.causes) {
      expect(_key('defects-cause-${c.id}'), findsOneWidget, reason: c.id);
    }
    // Pierwsza przyczyna na górze listy.
    expect(find.text(advice.causes.first.cause.pl), findsOneWidget);
    expect(_key('defects-repair'), findsOneWidget);
    expect(_key('defects-cutout'), findsOneWidget);
    expect(_key('defects-safety'), findsOneWidget);
    expect(_key('defects-checklist'), findsOneWidget);
    expect(find.text('EN ISO 5817, tablica 1 — poz. 1.7, 1.8'), findsOneWidget);

    await _tapKey(tester, 'defects-iso5817');
    expect(find.byType(Iso5817Page), findsOneWidget);
    expect(find.text('Odbiór spoin ISO 5817'), findsOneWidget);
  });

  testWidgets('„porowatość” i „porowatosc” → porowatość na początku',
      (tester) async {
    await _pump(tester);
    await _search(tester, 'porowatość');
    expect(_tileIds(tester).first, 'porosity');
    await _search(tester, 'POROWATOSC');
    expect(_tileIds(tester).first, 'porosity');
    await _search(tester, 'xyzqq');
    expect(_key('defects-search-empty'), findsOneWidget);
    await _tapKey(tester, 'defects-search-clear');
    expect(_key('defects-pick-tungsten'), findsOneWidget);
  });

  testWidgets(
      'wtrącenie wolframu: tylko TIG (wybrany sam), bez ISO 5817, zmiana wady',
      (tester) async {
    await _pump(tester);
    await _search(tester, '3041');
    await _tapKey(tester, 'defects-pick-tungsten');
    expect(_key('defects-process-tig141'), findsOneWidget);
    expect(_key('defects-process-mag135'), findsNothing);
    expect(_key('defects-repair'), findsOneWidget,
        reason: 'jedyny proces wybiera się sam');
    expect(_key('defects-iso5817'), findsNothing);
    expect(_key('defects-iso5817-none'), findsOneWidget);

    await _tapKey(tester, 'defects-change');
    expect(_key('defects-search'), findsOneWidget);
    expect(_key('defects-selected'), findsNothing);
  });

  testWidgets('materiał i pozycja filtrują przyczyny', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'defects-pick-porosity');
    await _tapKey(tester, 'defects-process-tig141');
    final all = defectAdvice(
        weldDefectById('porosity')!, DefectProcess.tig141)!;
    final alu = defectAdvice(
        weldDefectById('porosity')!, DefectProcess.tig141,
        material: DefectMaterial.aluminium)!;
    final aluOnly = alu.causes
        .where((c) => c.materials.length == 1 &&
            c.materials.contains(DefectMaterial.aluminium))
        .toList();
    expect(aluOnly, isNotEmpty, reason: 'dane: TIG Al ma własną przyczynę');
    final ss = defectAdvice(
        weldDefectById('porosity')!, DefectProcess.tig141,
        material: DefectMaterial.stainless)!;
    expect(all.causes.length, greaterThan(ss.causes.length));

    await _tapKey(tester, 'defects-material-stainless');
    for (final c in aluOnly) {
      expect(_key('defects-cause-${c.id}'), findsNothing, reason: c.id);
    }
    await _tapKey(tester, 'defects-material-aluminium');
    for (final c in aluOnly) {
      expect(_key('defects-cause-${c.id}'), findsOneWidget, reason: c.id);
    }

    // 131 MIG Al: materiał narzucony.
    await _tapKey(tester, 'defects-process-mig131');
    expect(_key('defects-material-fixed'), findsOneWidget);
    expect(find.text('Materiał: Aluminium'), findsOneWidget);
  });

  testWidgets('EN: ten sam ekran po angielsku', (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Weld defects: causes and repair'), findsOneWidget);
    expect(find.text('5xx · Imperfect shape and dimensions'), findsOneWidget);
    await _search(tester, 'undercut');
    expect(_tileIds(tester).first, 'undercut');
    await _tapKey(tester, 'defects-pick-undercut');
    await _tapKey(tester, 'defects-process-tig141');
    expect(find.text('Causes — check in this order'), findsOneWidget);
    expect(find.text('See the ISO 5817 limit'), findsOneWidget);
    expect(find.text('EN ISO 5817, Table 1 — item 1.7, 1.8'), findsOneWidget);
    expect(find.textContaining('Przyczyny'), findsNothing);
    expect(find.textContaining('Sprawdź'), findsNothing);
  });

  testWidgets('320 × 640, czcionka 1,3 — bez przepełnień', (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    // Lista wad.
    for (var i = 0; i < 6; i++) {
      await tester.drag(_key('defects-list'), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // Najdłuższa wada (najwięcej przyczyn) w procesie z najdłuższym wynikiem.
    await _search(tester, 'porowatość');
    await _tapKey(tester, 'defects-pick-porosity');
    await _tapKey(tester, 'defects-process-mag135');
    await _reveal(tester, 'defects-position');
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 30; i++) {
      await tester.drag(_key('defects-list'), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // Koniec listy: źródła; przycisk udostępniania nad nimi.
    expect(_key('defects-sources'), findsOneWidget);
    await _reveal(tester, 'defects-share');
    expect(_key('defects-share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawice)', (tester) async {
    await _pump(tester, size: const Size(400, 3000));
    await _search(tester, 'pod');
    final targets = <String>['defects-search-clear', 'defects-pick-undercut'];
    for (final k in targets) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tapKey(tester, 'defects-pick-undercut');
    await _tapKey(tester, 'defects-process-mma111');
    final advice = defectAdvice(
        weldDefectById('undercut')!, DefectProcess.mma111)!;
    for (final k in [
      'defects-change',
      for (final p in weldDefectById('undercut')!.processes)
        'defects-process-${p.name}',
      'defects-material-any',
      'defects-material-carbon',
      'defects-position',
      for (final s in advice.checklist) 'defects-check-${s.id}',
      'defects-iso5817',
      'defects-share',
    ]) {
      await _reveal(tester, k);
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję, z odhaczeniami',
      (tester) async {
    String? text;
    String? subject;
    await _pump(tester, onShare: (t, s) async {
      text = t;
      subject = s;
    });
    await _tapKey(tester, 'defects-pick-undercut');
    await _tapKey(tester, 'defects-process-mag135');
    final advice = defectAdvice(
        weldDefectById('undercut')!, DefectProcess.mag135)!;
    final first = advice.checklist.first;
    await _tapKey(tester, 'defects-check-${first.id}');
    await _tapKey(tester, 'defects-share');

    expect(subject, 'Wada spoiny — ${advice.defect.title.pl}');
    expect(text, isNotNull);
    expect(text, contains('Wada spoiny: ${advice.defect.title.pl}'));
    expect(text, contains('Proces: 135/138 MAG'));
    expect(text, contains('1. ${advice.causes.first.cause.pl}'));
    expect(text, contains('[x] ${first.text.pl}'));
    expect(text, contains('[ ] ${advice.checklist[1].text.pl}'));
    expect(text, contains('tablica 1 poz. 1.7, 1.8'));
    expect(text, contains('Wiążące są WPS'));
  });

  testWidgets('nieudane udostępnianie → komunikat, bez wyjątku',
      (tester) async {
    await _pump(tester, onShare: (t, s) async => throw Exception('x'));
    await _tapKey(tester, 'defects-pick-spatter');
    await _tapKey(tester, 'defects-process-mag135');
    await _tapKey(tester, 'defects-share');
    expect(find.text('Nie udało się udostępnić — spróbuj ponownie'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
