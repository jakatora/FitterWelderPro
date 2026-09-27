// Spójność tekstów prawnych z tym, co aplikacja NAPRAWDĘ robi (przegląd G6,
// 2026-09-26):
//   • polityka nie może mówić, że imię i nazwisko „nie opuszczają
//     urządzenia", skoro czat wysyła je z każdą wiadomością;
//   • „usuwają się z odinstalowaniem" musi uwzględniać kopię zapasową
//     Androida (manifest ma allowBackup z regułami — patrz
//     test/store/privacy_manifests_test.dart);
//   • regulamin i zgoda nie obiecują moderacji, której nie ma („24 h",
//     „odbieramy dostęp") — backend ukrywa wiadomości (automatycznie po 3
//     zgłoszeniach i ręcznie w panelu) i usuwa dane, ale nie banuje;
//   • zgoda dla asystenta mówi o asystencie (treść pytań → Anthropic), a nie
//     o czacie pod nazwiskiem.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/widgets/community_gate.dart';

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

LegalSection _section(LegalDocument d, String heading) =>
    d.sections.firstWhere((s) => s.heading == heading);

void main() {
  group('polityka: co zostaje na telefonie, a co wychodzi', () {
    testWidgets('PL: imię i nazwisko nie są na liście „nie opuszczają"',
        (tester) async {
      final doc = await _build(tester, AppLanguage.pl, privacyPolicy);
      final stays = _section(doc, 'Co zostaje na Twoim telefonie').body;
      expect(stays, isNot(contains('Te dane nie opuszczają urządzenia')));
      // Imię jest wymienione — ale z zastrzeżeniem, że czat je wysyła.
      expect(stays, contains('podpis Twoich wiadomości na czacie'));
      final chat = _section(doc, 'Co wysyłamy, gdy piszesz na czacie').body;
      expect(chat, contains('imię i nazwisko'));
    });

    testWidgets('EN: the name is not listed as never leaving the device',
        (tester) async {
      final doc = await _build(tester, AppLanguage.en, privacyPolicy);
      final stays = _section(doc, 'What stays on your phone').body;
      expect(stays, isNot(contains('never leaves the device')));
      expect(stays, contains('signature of your chat messages'));
    });

    testWidgets('kopia zapasowa Androida opisana; bez tożsamości instalacji',
        (tester) async {
      final pl = _all(await _build(tester, AppLanguage.pl, privacyPolicy));
      expect(pl, contains('kopię zapasową Androida'));
      expect(pl, contains('identyfikatora ani sekretu instalacji'));
      expect(pl, isNot(contains('Usuwają się razem z odinstalowaniem')));
      final en = _all(await _build(tester, AppLanguage.en, privacyPolicy));
      expect(en, contains('Android backup'));
      expect(en, contains('installation identifier or secret'));
    });

    testWidgets('usuwanie danych wymienia zgodę skanera i historię asystenta',
        (tester) async {
      final pl = _all(await _build(tester, AppLanguage.pl, privacyPolicy));
      expect(pl, contains('zgodę na wysyłkę zdjęć do skanera'));
      expect(pl, contains('historię asystenta'));
    });
  });

  group('moderacja: bez obietnic ponad to, co jest', () {
    testWidgets('regulamin PL/EN bez „24 h" i „odbieramy dostęp"',
        (tester) async {
      final pl = _all(await _build(tester, AppLanguage.pl, termsOfUse));
      expect(pl, isNot(contains('24 godzin')));
      expect(pl, isNot(contains('odbieramy dostęp')));
      expect(pl, isNot(contains('zwrotu')));
      expect(pl, contains('po 3 zgłoszeniach'));
      final en = _all(await _build(tester, AppLanguage.en, termsOfUse));
      expect(en, isNot(contains('24 hours')));
      expect(en, isNot(contains('lose access')));
      expect(en, contains('after 3 reports'));
    });

    testWidgets('zgoda czatu bez „24 godziny"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      LegalConsent.instance.resetForTest();
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(home: ConsentScreen(onAccepted: () {})),
      ));
      await tester.pump();
      expect(find.textContaining('24 godzin'), findsNothing);
      expect(find.textContaining('po 3 zgłoszeniach'), findsOneWidget);
    });
  });

  group('treść zgody zależy od funkcji', () {
    Future<void> pumpConsent(WidgetTester tester, ConsentPurpose purpose) async {
      SharedPreferences.setMockInitialValues({});
      LegalConsent.instance.resetForTest();
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
          home: ConsentScreen(purpose: purpose, onAccepted: () {}),
        ),
      ));
      await tester.pump();
    }

    testWidgets('czat: publiczne imię i nazwisko', (tester) async {
      await pumpConsent(tester, ConsentPurpose.chat);
      expect(find.textContaining('własnym imieniem i nazwiskiem'),
          findsOneWidget);
      expect(find.textContaining('Anthropic'), findsNothing);
    });

    testWidgets('asystent: treść pytań do Anthropic, bez nazwiska',
        (tester) async {
      await pumpConsent(tester, ConsentPurpose.assistant);
      expect(find.textContaining('Anthropic'), findsWidgets);
      expect(find.textContaining('Nie wysyłamy imienia ani nazwiska'),
          findsOneWidget);
      expect(find.textContaining('własnym imieniem i nazwiskiem'),
          findsNothing);
      expect(find.textContaining('napiszesz na czacie'), findsNothing);
    });

    testWidgets('bramka asystenta (ensureServerConsent) pokazuje wariant '
        'asystenta', (tester) async {
      SharedPreferences.setMockInitialValues({});
      LegalConsent.instance.resetForTest();
      late BuildContext ctx;
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold();
          }),
        ),
      ));
      final result = ensureServerConsent(ctx);
      await tester.pumpAndSettle();
      final screen =
          tester.widget<ConsentScreen>(find.byType(ConsentScreen));
      expect(screen.purpose, ConsentPurpose.assistant);
      expect(find.textContaining('Anthropic'), findsWidgets);
      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
