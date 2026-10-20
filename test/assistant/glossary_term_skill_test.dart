import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/data/welding_glossary.dart';
import 'package:cut_list_app/features/glossary/glossary_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('exact ISO number selects a real dictionary entry with its definition',
      () async {
    final r = (await BrainHarness().say('znajdź hasło 5011 w słowniku')).result
        as AnswerResult;
    final term = kWeldingGlossary.firstWhere((t) => t.iso6520 == '5011');
    expect(r.show!.fields['term_id'], term.id);
    expect(r.answer.text.pl, contains(term.defPl!));
    expect(r.answer.source!.pl, contains('ISO 6520-1: 5011'));
    expect(r.answer.lines, hasLength(5));
  });
  test('ambiguous undercut asks before selecting continuous or intermittent',
      () async {
    final h = BrainHarness();
    final first =
        (await h.say('jak jest podtopienie po niemiecku')).result as AskResult;
    expect(first.choices.length, greaterThan(1));
    final r = (await h.say('5011')).result as AnswerResult;
    expect(r.answer.text.pl, contains('DE:'));
    expect(r.show!.fields['target'], 'de');
  });
  test('two target languages require choosing one', () async {
    final h = BrainHarness();
    expect((await h.say('słownik WPS po niemiecku i angielsku')).result,
        isA<AskResult>());
    final r = (await h.say('EN')).result as AnswerResult;
    expect(r.show!.fields['target'], 'en');
  });
  test('translation without a target asks instead of assuming German',
      () async {
    final h = BrainHarness();
    expect(
        (await h.say('przetłumacz w słowniku WPS')).result, isA<AskResult>());
    final r = (await h.say('po norwesku')).result as AnswerResult;
    expect(r.show!.fields['target'], 'no');
  });
  test('unknown explicit entry reports a dictionary gap', () async {
    final r = (await BrainHarness().say('znajdź w słowniku zyxwfoobar')).result
        as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test('Polish language inflection does not become part of the searched term',
      () async {
    final r =
        (await BrainHarness().say('znajdź WPS w języku niemieckim w słowniku'))
            .result as AnswerResult;
    expect(r.show!.fields['target'], 'de');
  });
  test('opening the dictionary in its own context remains navigation',
      () async {
    final r = await BrainHarness(activeToolId: 'glossary', onHome: false)
        .say('otwórz słownik spawalniczy');
    expect(r.match!.skill.id, 'tool.open');
  });
  test('a chosen English term keeps its internal prepositions intact',
      () async {
    final h = BrainHarness(lang: AppLanguage.en);
    expect((await h.say('find undercut in the dictionary')).result,
        isA<AskResult>());
    final r = (await h.say('continuous undercut')).result as AnswerResult;
    expect(r.answer.text.en, contains('Continuous undercut'));
  });
  testWidgets(
      'page expands exact entry and preserves language/favorites preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      GlossaryPage.targetPrefsKey: 'no',
      GlossaryPage.favoritesPrefsKey: ['saved-test']
    });
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r =
        (await BrainHarness().say('słownik 5011 po angielsku', byVoice: true))
            .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final term = kWeldingGlossary.firstWhere((t) => t.iso6520 == '5011');
    expect(find.byKey(ValueKey('glossary-term-${term.id}')), findsOneWidget);
    expect(find.text(term.en), findsWidgets);
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({'term_id': 'missing'}), isNotEmpty);
    expect(await handle.apply({'term_id': term.id, 'target': 'invalid'}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('glossary-term-${term.id}')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(GlossaryPage.targetPrefsKey), 'no');
    expect(prefs.getStringList(GlossaryPage.favoritesPrefsKey), ['saved-test']);
    await tester.tap(find.byKey(const ValueKey('glossary-target-en')));
    await tester.pumpAndSettle();
    expect(prefs.getString(GlossaryPage.targetPrefsKey), 'en');
    await tester.enterText(
        find.byKey(const ValueKey('glossary-search')), 'WPS');
    await tester.pumpAndSettle();
    final wps = kWeldingGlossary.firstWhere((t) => t.code == 'WPS');
    expect(find.byKey(ValueKey('glossary-term-${wps.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
