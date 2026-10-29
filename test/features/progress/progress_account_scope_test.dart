import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/progress/progress_forecast.dart';
import 'package:cut_list_app/domain/progress/progress_filter.dart';
import 'package:cut_list_app/domain/progress/progress_report.dart';
import 'package:cut_list_app/domain/progress/weld_progress.dart';
import 'package:cut_list_app/features/progress/progress_page.dart';
import 'package:cut_list_app/features/quotes/quote_widgets.dart'
    show QuoteNumberField;
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/progress_scope_store.dart';
import 'package:cut_list_app/services/progress_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

DateTime _clock() => DateTime(2026, 10, 14, 12);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

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

    final db = await AppDatabase.get();
    await db.delete('weld_repairs');
    await db.delete('weld_journal_history');
    await db.delete('weld_journal');

    for (final id in ['a', 'b']) {
      await account.signIn('$id@example.test', 'test-password');
      await WeldJournalDao().insert(
          weld('weld-$id',
              project: '${id.toUpperCase()}_PRIVATE', date: '2026-10-14'),
          by: 'TEST');
      await const ProgressScopeStore().save('${id.toUpperCase()}_PRIVATE', '',
          ProgressScope(total: id == 'a' ? 40 : 90));
    }
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarty postęp przełącza dziennik i zakres na nowe konto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: ProgressPage(clock: _clock)),
    ));
    await _settle(tester);

    expect(find.text('A_PRIVATE'), findsWidgets);
    expect(tester.widget<QuoteNumberField>(find.byType(QuoteNumberField)).value,
        40);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);

    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_PRIVATE'), findsWidgets);
    expect(tester.widget<QuoteNumberField>(find.byType(QuoteNumberField)).value,
        90);
    expect(tester.takeException(), isNull);
  });

  test('opóźniony zapis starej sesji nie trafia do nowego konta', () async {
    final owner = await LocalRecordOwner.capture();
    final oldSessionStore = ProgressScopeStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
      oldSessionStore.save('A_PRIVATE', '', const ProgressScope(total: 777)),
      throwsA(isA<AccountException>()),
    );
    expect((await const ProgressScopeStore().load('B_PRIVATE', '')).total, 90);
    await account.signIn('a@example.test', 'test-password');
    expect((await const ProgressScopeStore().load('A_PRIVATE', '')).total, 40);
  });

  testWidgets('otwarty kalendarz terminu ukrywa dane po zmianie konta',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: ProgressPage(clock: _clock)),
    ));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('progress-due')),
      300,
      scrollable: find
          .descendant(
              of: find.byKey(const ValueKey('progress-list')),
              matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('progress-due')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test(
      'PDF nie przechodzi do udostępniania po zmianie konta podczas odczytu czcionki',
      () async {
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    var fontReads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      fontReads++;
      if (!entered.isCompleted) entered.complete();
      await release.future;
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      return ByteData.sublistView(await File(key).readAsBytes());
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final report = ProgressReport(
      filter: const ProgressFilter(project: 'A_PRIVATE'),
      range: null,
      summary: summarizeProgress(const []),
      pace: null,
      forecast: null,
      generatedAt: _clock(),
    );
    final pending = ProgressExport.sharePdf(report,
        en: false, mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(fontReads, 1);
  });
}
