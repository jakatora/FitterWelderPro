// Lista „Tolerancje spoola”: nowy protokół → historia ze stanem, następny
// spool z serii (wymiary bez pomiarów), usunięcie z „Cofnij” przez magazyn
// także po zamknięciu ekranu, usunięta pozycja przywrócona po zamknięciu
// edycji, limit historii, uszkodzony zapis, wąski ekran.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/features/spool_check/spool_check_page.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 18, 9, 0);

/// Ekran startowy z przyciskiem otwierającym moduł — żeby dało się moduł
/// zamknąć i sprawdzić „Cofnij” po zamknięciu.
class _Launcher extends StatelessWidget {
  const _Launcher(this.page);
  final Widget page;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('Otwórz'),
          ),
        ),
      );
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  AppLanguage language = AppLanguage.pl,
  SpoolCheckStore store = const SpoolCheckStore(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var n = 0;
  final page = SpoolCheckPage(
    store: store,
    now: () => _now,
    newId: () => 'id-${++n}',
    shareText: (_, __) async {},
  );
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: _Launcher(page),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Finder _scrollable(String listKey) => find
    .descendant(
        of: find.byKey(ValueKey(listKey)), matching: find.byType(Scrollable))
    .first;

String get _currentList =>
    find.byKey(const ValueKey('sc-edit-list')).evaluate().isNotEmpty
        ? 'sc-edit-list'
        : 'sc-list';

Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    final list = _currentList;
    await tester.drag(_scrollable(list), const Offset(0, 20000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 300, scrollable: _scrollable(list));
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  return f;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(await _show(tester, key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(await _show(tester, key), text);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

String _status(WidgetTester tester, int i) =>
    tester.widget<Text>(find.byKey(ValueKey('sc-hist-status-$i'))).data!;

SpoolCheck _stored({String id = 'old', String spoolNo = '100-P-1203-S02'}) =>
    SpoolCheck(
      id: id,
      spoolNo: spoolNo,
      isoNo: 'ISO-1203',
      date: '2026-10-17',
      inspector: 'Jan Kowalski',
      dn: 150,
      items: const [
        SpoolItem(
            id: 'a',
            kind: SpoolItemKind.faceToFace,
            label: 'F1–F2',
            drawingMm: 1250,
            measuredMm: 1251),
        SpoolItem(
            id: 'b',
            kind: SpoolItemKind.centerToFace,
            label: 'K1–F2',
            drawingMm: 600,
            measuredMm: 599,
            toleranceMm: 2),
      ],
      createdAt: 1,
      updatedAt: 1,
    );

void _seed(List<SpoolCheck> list) => SharedPreferences.setMockInitialValues(
    {SpoolCheckStore.key: jsonEncode(spoolChecksToJson(list))});

/// Pamięć, która odmawia zapisu kopii uszkodzonej historii.
class _NoBackupPrefs implements SharedPreferences {
  _NoBackupPrefs(this._real);
  final SharedPreferences _real;

  @override
  Future<void> reload() => _real.reload();

  @override
  Object? get(String key) => _real.get(key);

  @override
  String? getString(String key) => _real.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    if (key == SpoolCheckStore.corruptBackupKey ||
        key == SpoolCheckStore.corruptLastBackupKey) {
      return false;
    }
    return _real.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingDuplicateStore extends SpoolCheckStore {
  const _FailingDuplicateStore();

  @override
  Future<void> upsert(SpoolCheck check) async =>
      throw StateError('simulated save failure');
}

class _FailingDeleteStore extends SpoolCheckStore {
  const _FailingDeleteStore();

  @override
  Future<void> delete(String id) async =>
      throw StateError('simulated delete failure');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('nowy protokół trafia do historii ze stanem; pusty — nie',
      (tester) async {
    await _pump(tester);
    expect(find.text('Tolerancje spoola'), findsOneWidget);
    expect(find.byKey(const ValueKey('sc-empty')), findsOneWidget);

    // Pusty protokół nie zostaje w historii.
    await _tapKey(tester, 'sc-new');
    await _back(tester);
    expect(find.byKey(const ValueKey('sc-empty')), findsOneWidget);

    await _tapKey(tester, 'sc-new');
    await _enter(tester, 'sc-f-spoolNo', 'S-01');
    await _enter(tester, 'sc-f-dn', '150');
    await _tapKey(tester, 'sc-add-faceToFace');
    await _enter(tester, 'sc-i-0-drawing', '1250');
    await _back(tester);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect(find.text('S-01'), findsOneWidget);
    expect(_status(tester, 0), 'Niekompletny');

    await _tapKey(tester, 'sc-open-0');
    await _enter(tester, 'sc-i-0-measured', '1252');
    await _back(tester);
    expect(_status(tester, 0), 'W tolerancji');
    await _tapKey(tester, 'sc-open-0');
    await _enter(tester, 'sc-i-0-measured', '1254');
    await _back(tester);
    expect(_status(tester, 0), 'Poza tolerancją');
  });

  testWidgets(
      'następny spool z serii: wymiary z rysunku i tolerancje bez '
      'pomiarów, numer +1', (tester) async {
    _seed([_stored()]);
    await _pump(tester);
    expect(_status(tester, 0), 'W tolerancji');
    await _tapKey(tester, 'sc-dup-last');
    expect(find.text('Protokół spoola'), findsOneWidget);
    expect(find.text('100-P-1203-S03'), findsOneWidget);
    await _back(tester);
    expect(find.text('HISTORIA (2)'), findsOneWidget);
    final saved = await const SpoolCheckStore().load();
    final copy = saved.firstWhere((c) => c.id != 'old');
    expect(copy.spoolNo, '100-P-1203-S03');
    expect(copy.date, '2026-10-18');
    expect(copy.inspector, 'Jan Kowalski');
    expect(copy.items.map((i) => i.drawingMm), [1250, 600]);
    expect(copy.items.map((i) => i.measuredMm), everyElement(isNull));
    expect(copy.items[1].toleranceMm, 2);
    expect(copy.evaluate().overall, SpoolOverall.incomplete);
    // Oryginał nietknięty.
    expect(saved.firstWhere((c) => c.id == 'old').items.first.measuredMm, 1251);
  });

  testWidgets('błąd powielenia nie otwiera niezapisanego protokołu',
      (tester) async {
    _seed([_stored()]);
    await _pump(tester, store: const _FailingDuplicateStore());
    await _tapKey(tester, 'sc-dup-last');
    expect(find.byKey(const ValueKey('sc-duplicate-failed')), findsOneWidget);
    expect(find.text('Protokół spoola'), findsNothing);
    expect((await const SpoolCheckStore().load()).map((c) => c.id), ['old']);
  });

  testWidgets('błąd usuwania zachowuje historię i pokazuje komunikat',
      (tester) async {
    _seed([_stored()]);
    await _pump(tester, store: const _FailingDeleteStore());
    await _tapKey(tester, 'sc-menu-0');
    await tester.tap(find.byKey(const ValueKey('sc-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sc-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sc-delete-failed')), findsOneWidget);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect((await const SpoolCheckStore().load()).map((c) => c.id), ['old']);
  });

  testWidgets(
      'usunięcie protokołu z „Cofnij” — działa przez magazyn także po '
      'zamknięciu ekranu', (tester) async {
    _seed([_stored()]);
    await _pump(tester);
    await _tapKey(tester, 'sc-menu-0');
    await tester.tap(find.byKey(const ValueKey('sc-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sc-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sc-empty')), findsOneWidget);
    expect(await const SpoolCheckStore().load(), isEmpty);

    // Zamknięcie modułu — pasek z „Cofnij” zostaje na ekranie startowym.
    await _back(tester);
    expect(find.byKey(const ValueKey('sc-list')), findsNothing);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    final back = await const SpoolCheckStore().load();
    expect(back.single.id, 'old');
    expect(back.single.items, hasLength(2));
  });

  testWidgets('usunięta pozycja przywrócona po zamknięciu ekranu edycji',
      (tester) async {
    _seed([_stored()]);
    await _pump(tester);
    await _tapKey(tester, 'sc-open-0');
    await _tapKey(tester, 'sc-i-0-del');
    await _back(tester);
    expect((await const SpoolCheckStore().load()).single.items.map((i) => i.id),
        ['b']);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect((await const SpoolCheckStore().load()).single.items.map((i) => i.id),
        ['a', 'b']);
  });

  testWidgets(
      'historia: ostrzeżenie od 180 protokołów, przy 200 nowy '
      'odrzucony z komunikatem', (tester) async {
    List<SpoolCheck> many(int n) =>
        [for (var i = 0; i < n; i++) _stored(id: 'p$i', spoolNo: 'S-$i')];
    _seed(many(SpoolCheckStore.warnAt));
    await _pump(tester);
    await _show(tester, 'sc-store-warn');
    expect(find.textContaining('Historia: 180/200'), findsOneWidget);

    _seed(many(SpoolCheckStore.maxEntries));
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _tapKey(tester, 'sc-new');
    expect(find.byKey(const ValueKey('sc-store-full')), findsOneWidget);
    expect(find.text('Protokół spoola'), findsNothing);
    await _tapKey(tester, 'sc-dup-last');
    expect(find.text('Protokół spoola'), findsNothing);
    expect(await const SpoolCheckStore().load(),
        hasLength(SpoolCheckStore.maxEntries));
  });

  testWidgets(
      'uszkodzony zapis: baner i kopia surowego zapisu; protokół '
      'z uszkodzoną tolerancją bez werdyktu', (tester) async {
    final json = _stored().toJson();
    ((json['items'] as List)[1] as Map)['tolMm'] = 'dwa';
    final raw = jsonEncode([json]);
    SharedPreferences.setMockInitialValues({SpoolCheckStore.key: raw});
    await _pump(tester);
    await _show(tester, 'sc-load-damaged');
    expect(find.textContaining('uszkodzeń w protokołach: 1'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SpoolCheckStore.corruptBackupKey), raw);
    expect(_status(tester, 0), 'Niekompletny');
    await _tapKey(tester, 'sc-open-0');
    await _show(tester, 'sc-damaged-notice');
    expect(find.text('• zapisana tolerancja nieczytelna — wpisz ponownie'),
        findsOneWidget);
  });

  testWidgets('nieczytelna historia w całości — baner, pusta lista',
      (tester) async {
    SharedPreferences.setMockInitialValues({SpoolCheckStore.key: '{zepsute'});
    await _pump(tester);
    await _show(tester, 'sc-load-damaged');
    expect(find.textContaining('Zapisanej historii nie da się odczytać'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('sc-empty')), findsOneWidget);
  });

  testWidgets('ekran 360×640, tekst ×1,5: lista i edycja bez przepełnień',
      (tester) async {
    _seed([
      _stored(
          spoolNo: '100-P-1203-S02-REV-C-RAFINERIA-INSTALACJA-HDS-ESTAKADA-E4'),
      _stored(id: 'x', spoolNo: 'S-9'),
    ]);
    await _pump(tester, size: const Size(360, 640), textScale: 1.5);
    expect(tester.takeException(), isNull);
    await _show(tester, 'sc-hist-1');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'sc-open-0');
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sc-share-text-btn')), 300,
        scrollable: _scrollable('sc-edit-list'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku listy ≥ 48 dp i wersja angielska', (tester) async {
    _seed([_stored()]);
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Spool tolerances'), findsOneWidget);
    expect(_status(tester, 0), 'Within tolerance');
    for (final k in ['sc-new', 'sc-dup-last', 'sc-open-0', 'sc-menu-0']) {
      final f = await _show(tester, k);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
      expect(tester.getSize(f).width, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });

  testWidgets(
      'następny spool z nieczytelnym zestawem i uszkodzoną tolerancją '
      '— kopia bez werdyktu, bez podstawienia ES-3', (tester) async {
    final json = _stored().toJson();
    json['set'] = 'ISO';
    ((json['items'] as List)[1] as Map)['tolMm'] = 'dwa';
    SharedPreferences.setMockInitialValues({
      SpoolCheckStore.key: jsonEncode([json])
    });
    await _pump(tester);
    await _tapKey(tester, 'sc-dup-last');
    await _show(tester, 'sc-set-unreadable');
    await _enter(tester, 'sc-i-1-measured', '600');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('sc-i-1-verdict'))).data,
        'brak werdyktu');
    expect(find.text('• zestaw tolerancji nieczytelny'), findsWidgets);
    await _back(tester);
    final copy =
        (await const SpoolCheckStore().load()).firstWhere((c) => c.id != 'old');
    expect(copy.toleranceSet, isNull);
    expect(copy.items[1].toleranceDamaged, isTrue);
    expect(copy.evaluate().overall, SpoolOverall.incomplete);
  });

  testWidgets(
      'następny spool po numerze bez cyfr („A”) — pusty numer '
      'z przypomnieniem, bez duplikatu', (tester) async {
    _seed([_stored(spoolNo: 'A')]);
    await _pump(tester);
    await _tapKey(tester, 'sc-dup-last');
    await _show(tester, 'sc-spoolno-missing');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sc-f-spoolNo')))
            .controller!
            .text,
        isEmpty);
    await _back(tester);
    final nos = (await const SpoolCheckStore().load()).map((c) => c.spoolNo);
    expect(nos, containsAll(['', 'A']));
  });

  testWidgets(
      'pamięć odmawia kopii uszkodzonego zapisu — baner „pamięć '
      'niedostępna”, usunięcie i nowy protokół niczego nie nadpisują',
      (tester) async {
    final json = _stored().toJson();
    json['items'] = [
      ...(json['items'] as List),
      {'id': 'zz', 'kind': 'nieznany'},
    ];
    final raw = jsonEncode([json]);
    SharedPreferences.setMockInitialValues({SpoolCheckStore.key: raw});
    final real = await SharedPreferences.getInstance();
    final store = SpoolCheckStore(prefs: () async => _NoBackupPrefs(real));
    await _pump(tester, store: store);
    await _show(tester, 'sc-store-unavailable-banner');
    expect(find.textContaining('Pamięć niedostępna — nic nie zapisano'),
        findsWidgets);

    await _tapKey(tester, 'sc-menu-0');
    await tester.tap(find.byKey(const ValueKey('sc-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sc-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sc-store-unavailable')), findsOneWidget);
    expect(real.getString(SpoolCheckStore.key), raw);

    await _tapKey(tester, 'sc-new');
    expect(find.text('Protokół spoola'), findsNothing);
    await _tapKey(tester, 'sc-dup-last');
    expect(find.text('Protokół spoola'), findsNothing);
    expect(real.getString(SpoolCheckStore.key), raw);
    expect(real.getString(SpoolCheckStore.corruptBackupKey), isNull);
  });
}
