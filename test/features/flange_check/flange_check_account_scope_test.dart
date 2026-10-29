import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/flange/flange_check.dart';
import 'package:cut_list_app/features/flange_check/flange_check_page.dart';
import 'package:cut_list_app/features/flange_check/flange_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/flange_check_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

FlangeCheck _check(String id) => FlangeCheck(
      id: id,
      joint:
          FlangeJoint(tag: '${id.toUpperCase()}_PRIVATE', date: '2026-10-29'),
      measurements: FlangeMeasurements.empty(),
      createdAt: 1,
      updatedAt: 1,
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
      await const FlangeCheckStore().save([_check(id)]);
    }
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarta historia kołnierzy przełącza dane na nowe konto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: FlangeCheckPage(clock: () => DateTime(2026, 10, 29))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flange-tab-history')));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsWidgets);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('flange-tab-history')));
    await tester.pumpAndSettle();
    expect(find.text('B_PRIVATE'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis protokołu nie trafia do nowego konta', () async {
    final owner = await LocalRecordOwner.capture();
    final oldStore = FlangeCheckStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        oldStore.save([_check('stale')]), throwsA(isA<AccountException>()));
    expect(
        (await const FlangeCheckStore().load()).single.joint.tag, 'B_PRIVATE');
    await account.signIn('a@example.test', 'test-password');
    expect(
        (await const FlangeCheckStore().load()).single.joint.tag, 'A_PRIVATE');
  });

  testWidgets('otwarty kalendarz ukrywa starą sesję po zmianie konta',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: FlangeCheckPage(clock: () => DateTime(2026, 10, 29))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flange-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('niezapisany szkic A nie pojawia się na koncie B',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          home: FlangeCheckPage(clock: () => DateTime(2026, 10, 29))),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('flange-tag')), 'A-DRAFT');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('flange-tag')))
            .controller!
            .text,
        'A-DRAFT');

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('flange-tag')))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('PDF nie jest udostępniany po zmianie konta podczas generowania',
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

    final pending = shareFlangeCheck(_check('a'), FlangeShareFormat.pdf, false,
        mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(fontReads, 1);
    expect(shareCalls, 0);
  });
}
