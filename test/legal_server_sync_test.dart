// Polityka w aplikacji musi mówić to samo, co strona /privacy backendu
// (backend/src/routes/publicPages.js) — i to, co aplikacja naprawdę robi po
// zmianie z 2026-09-24: sekret instalacji, skróty IP, rejestracja dopiero przy
// czacie, usuwanie danych z serwera przyciskiem w profilu.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/app_links.dart';
import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';

Future<LegalDocument> _build(
  WidgetTester tester,
  AppLanguage language,
  LegalDocument Function(BuildContext) doc,
) async {
  late LegalDocument out;
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: Builder(builder: (c) {
      out = doc(c);
      return const SizedBox.shrink();
    }),
  ));
  return out;
}

String _all(LegalDocument d) =>
    [d.intro, for (final s in d.sections) '${s.heading}\n${s.body}'].join('\n');

void main() {
  test('wersja zasad podniesiona do 5 z datą zmiany (skaner + asystent)', () {
    expect(kLegalVersion, 5);
    // 2026-09-26: doprecyzowania bez ponownej akceptacji (imię na czacie,
    // kopia Androida, moderacja) — patrz nagłówek legal_texts.dart.
    expect(kLegalUpdated, '2026-10-21');
  });

  testWidgets('polityka PL: skaner rysunków — serwer, Anthropic, bez zapisu',
      (tester) async {
    final text = _all(await _build(tester, AppLanguage.pl, privacyPolicy));
    expect(text, contains('Skaner rysunków'));
    expect(text, contains('Anthropic'));
    expect(text, contains('Serwer nie zapisuje zdjęcia ani wyniku'));
    expect(text, contains('dzienny limit'));
    // Dawna polityka twierdziła, że skaner jest wyłączony — już nie jest.
    expect(text, isNot(contains('skaner rysunków są w tej wersji WYŁĄCZONE')));
  });

  testWidgets(
      'polityka PL: asystent — Wykonaj lokalnie, Odpowiedz przez serwer',
      (tester) async {
    final text = _all(await _build(tester, AppLanguage.pl, privacyPolicy));
    expect(text, contains('Asystent AI'));
    expect(text, contains('udostępnione pola widocznego kalkulatora'));
    expect(text, contains('„Wykonaj"'));
    expect(text, contains('„Odpowiedz"'));
    expect(text, contains('rozpoznaje polecenia na telefonie'));
    expect(text, contains('Google'));
    expect(text, contains('Apple'));
    expect(text, contains('tylko po naciśnięciu'));
    expect(text, contains('Nie zapisujemy treści pytań'));
  });

  testWidgets('polityka EN: scanner and assistant say the same',
      (tester) async {
    final text = _all(await _build(tester, AppLanguage.en, privacyPolicy));
    expect(text, contains('Drawing scanner'));
    expect(text, contains('The server does not store the photo or the result'));
    expect(text, contains('daily limit'));
    expect(text, contains('AI assistant'));
    expect(text, contains('shared inputs of the visible calculator'));
    expect(text, contains('"Do"'));
    expect(text, contains('"Answer"'));
    expect(text, contains('Google'));
    expect(text, contains('only when you press'));
    expect(text, contains('Anthropic'));
  });

  testWidgets('regulamin: wyniki skanera i asystenta trzeba sprawdzić',
      (tester) async {
    final pl = _all(await _build(tester, AppLanguage.pl, termsOfUse));
    expect(pl, contains('Skaner i asystent AI'));
    expect(pl, contains('niepewne wartości'));
    final en = _all(await _build(tester, AppLanguage.en, termsOfUse));
    expect(en, contains('Scanner and AI assistant'));
  });

  test('adresy dla sklepów wskazują dedykowany backend', () {
    expect(AppLinks.privacyPolicyUrl, '${BackendConfig.baseUrl}/privacy');
    expect(AppLinks.dataDeletionUrl, '${BackendConfig.baseUrl}/data-deletion');
    expect(AppLinks.privacyPolicyUrl, startsWith('https://'));
  });

  testWidgets('polityka PL: dane techniczne, sekret, rejestracja, usuwanie',
      (tester) async {
    final text = _all(await _build(tester, AppLanguage.pl, privacyPolicy));
    expect(text, contains('Dane techniczne na serwerze'));
    expect(text, contains('skrót (HMAC)'));
    expect(text, contains('usuwane po 2 dobach'));
    expect(text, contains('sekret instalacji'));
    expect(text, contains('nieodwracalny skrót'));
    expect(text, contains('dopiero wtedy, gdy'));
    expect(text, contains('Profil → „Usuń moje dane"'));
    expect(text, contains(AppLinks.supportEmail));
    expect(text, contains('art. 6 ust. 1 lit. f RODO'));
  });

  testWidgets('polityka EN mówi to samo', (tester) async {
    final text = _all(await _build(tester, AppLanguage.en, privacyPolicy));
    expect(text, contains('Technical data on the server'));
    expect(text, contains('one-way hash (HMAC)'));
    expect(text, contains('installation secret'));
    expect(text, contains('only when you'));
    expect(text, contains('Profile → "Delete my data"'));
    expect(text, contains('Art. 6(1)(f) GDPR'));
  });

  testWidgets('regulamin: „Usuń moje dane" usuwa też z serwera',
      (tester) async {
    final pl = _all(await _build(tester, AppLanguage.pl, termsOfUse));
    expect(pl, contains('usuwa Twoje dane z serwera'));
    final en = _all(await _build(tester, AppLanguage.en, termsOfUse));
    expect(en, contains('deletes your data from the server'));
  });
}
