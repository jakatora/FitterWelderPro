import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/features/piecework/piecework_page.dart';
import 'package:cut_list_app/features/piecework/piecework_store.dart';
import 'package:cut_list_app/features/quotes/quote_widgets.dart'
    show QuoteNumberField;
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/piecework_export.dart';
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
              welder: '${id.toUpperCase()}-01', date: '2026-10-14'),
          by: 'TEST');
      await const PieceworkRatesStore()
          .save(PieceworkRates(rateGrosze: id == 'a' ? 4500 : 9000));
    }
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarty akord przełącza spoiny, stawkę i kwotę na nowe konto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: PieceworkPage(
        clock: _clock,
        loadIdentity: () async => null,
        loadHourlyMinimum: () async => null,
      )),
    ));
    await _settle(tester);

    expect(
        tester
            .widget<QuoteNumberField>(
                find.byKey(const ValueKey('piecework-rate-di')))
            .value,
        45);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('piecework-total')),
            matching: find.text('90,00\u00a0zł')),
        findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);

    expect(
        tester
            .widget<QuoteNumberField>(
                find.byKey(const ValueKey('piecework-rate-di')))
            .value,
        90);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('piecework-total')),
            matching: find.text('180,00\u00a0zł')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('opóźniony zapis starej stawki nie trafia do nowego konta', () async {
    final owner = await LocalRecordOwner.capture();
    final oldSessionStore =
        PieceworkRatesStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
      oldSessionStore.save(const PieceworkRates(rateGrosze: 77700)),
      throwsA(isA<AccountException>()),
    );
    expect((await const PieceworkRatesStore().load()).rates.rateGrosze, 9000);
    await account.signIn('a@example.test', 'test-password');
    expect((await const PieceworkRatesStore().load()).rates.rateGrosze, 4500);
  });

  testWidgets('otwarty wybór okresu ukrywa dane po zmianie konta',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: PieceworkPage(
        clock: _clock,
        loadIdentity: () async => null,
        loadHourlyMinimum: () async => null,
      )),
    ));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('piecework-period-custom')));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('PDF z kwotą nie jest udostępniany po zmianie konta podczas generowania',
      () async {
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      return ByteData.sublistView(await File(key).readAsBytes());
    });
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    var shareCalls = 0;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls++;
      return 'share-complete';
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });

    final result = computePiecework(
      entries: await WeldJournalDao().listAll(),
      rates: (await const PieceworkRatesStore().load()).rates,
      range: pieceworkRange(PieceworkPeriod.today, _clock()),
      today: _clock(),
    );
    final report = PieceworkReport(result: result, generatedAt: _clock());
    final pending = PieceworkExport.sharePdf(report, false,
        mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(shareCalls, 0);
  });
}
