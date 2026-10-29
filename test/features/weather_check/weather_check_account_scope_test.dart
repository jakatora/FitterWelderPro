import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/welding/weather_conditions.dart';
import 'package:cut_list_app/features/weather_check/weather_check_page.dart';
import 'package:cut_list_app/features/weather_check/weather_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/weather_check_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeatherCheckRecord _record(String id) => WeatherCheckRecord(
      id: id,
      takenAt: DateTime(2026, 10, 29, 8),
      place: '${id.toUpperCase()}_PRIVATE',
      input: const WeatherInput(ambientC: 15, rhPct: 50, windMs: 1),
      verdict: WeatherVerdict.go,
    );

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

    for (final id in ['a', 'b']) {
      await account.signIn('$id@example.test', 'test-password');
      await const WeatherCheckStore().saveHistory([_record(id)]);
    }
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: WeatherCheckPage(now: () => DateTime(2026, 10, 29))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('historia otwarta na koncie A znika po zalogowaniu na B',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('wx-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('A_PRIVATE'), findsWidgets);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A_PRIVATE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formularz i licznik historii resetują się po zmianie konta',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const ValueKey('wx-ambient')), '15');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('wx-ambient')))
            .controller!
            .text,
        '15');

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('wx-ambient')))
            .controller!
            .text,
        isEmpty);
    await tester.tap(find.byKey(const ValueKey('wx-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('B_PRIVATE'), findsWidgets);
    expect(find.textContaining('A_PRIVATE'), findsNothing);
  });

  testWidgets('otwarty podgląd pomiaru A znika po zmianie konta',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('wx-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wx-record-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('A_PRIVATE'), findsWidgets);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty edytor progów znika po zmianie konta', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('wx-thresholds')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wx-th-list')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wx-th-list')), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis historii i progów nie trafia na konto B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = WeatherCheckStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        stale.add(_record('stale')), throwsA(isA<AccountException>()));
    await expectLater(stale.saveThresholds(WeatherThresholds.defaults),
        throwsA(isA<AccountException>()));
    expect((await const WeatherCheckStore().loadHistory()).single.place,
        'B_PRIVATE');
    await account.signIn('a@example.test', 'test-password');
    expect((await const WeatherCheckStore().loadHistory()).single.place,
        'A_PRIVATE');
  });

  test('PDF nie otwiera udostępniania po zmianie konta podczas generowania',
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
      return 'shared';
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });

    final pending = WeatherCheckExport.sharePdf(_record('a'),
        english: false, mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(shareCalls, 0);
  });
}
