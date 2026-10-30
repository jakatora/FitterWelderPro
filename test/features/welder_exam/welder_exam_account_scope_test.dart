import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/exam/exam_session.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_page.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExamStats _stats(int score, {bool missed = false}) {
  var stats = const ExamStats();
  if (missed) {
    stats = stats.withAnswer(drawExamQuestions(seed: 7, en: false).first,
        correct: false);
  }
  return stats.withSession(ExamSessionRecord(
      at: DateTime(2026, 10, 30),
      mode: ExamMode.quick,
      score: score,
      total: 10));
}

class _SlowFirstLoadStore extends WelderExamStore {
  final firstReadReady = Completer<void>();
  final release = Completer<void>();
  var reads = 0;

  @override
  Future<WelderExamLoad> load() async {
    final result = await super.load();
    if (reads++ == 0) {
      firstReadReady.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  late AccountService account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((request) async {
      final id = (jsonDecode(request.body)['email'] as String).split('@').first;
      return http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'},
          }),
          200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
    await account.signIn('a@example.test', 'test-password');
    await const WelderExamStore().save(_stats(2, missed: true));
    await account.signIn('b@example.test', 'test-password');
    await const WelderExamStore().save(_stats(7));
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('sesja i statystyki A znikają po przełączeniu na B',
      (tester) async {
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: WelderExamPage(seed: 7)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pytania, które mi nie wychodzą (1)'), findsOneWidget);
    expect(find.text('Ostatnia sesja: 2 / 10 (20 %)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('we-quick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('we-prompt')), findsOneWidget);
    final q = drawExamQuestions(seed: 7, en: false).first;
    await tester.tap(find
        .byKey(ValueKey('we-opt-${(q.correctIndex + 1) % q.options.length}')));
    await tester.pumpAndSettle();

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('we-prompt')), findsNothing);
    expect(find.text('Pytania, które mi nie wychodzą (0)'), findsOneWidget);
    expect(find.text('Ostatnia sesja: 7 / 10 (70 %)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis statystyk A nie zmienia konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = WelderExamStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(stale.save(_stats(3)), throwsA(isA<AccountException>()));
    expect((await const WelderExamStore().load()).stats.last!.score, 7);
    await account.signIn('a@example.test', 'test-password');
    expect((await const WelderExamStore().load()).stats.last!.score, 2);
  });

  testWidgets('opóźniony odczyt A nie nadpisuje widoku B', (tester) async {
    final store = _SlowFirstLoadStore();
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: WelderExamPage(store: store)),
    ));
    await tester.runAsync(() => store.firstReadReady.future);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('Ostatnia sesja: 7 / 10 (70 %)'), findsOneWidget);

    store.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ostatnia sesja: 7 / 10 (70 %)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
