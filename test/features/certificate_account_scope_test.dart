import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cut_list_app/widgets/local_record_scope.dart';
import 'package:cut_list_app/services/qualification_export.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/features/qualification/certificate_edit_page.dart';
import 'package:cut_list_app/features/qualification/certificate_register_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import '../support/test_database.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 50));
  }
}

const privateCertificate = WelderCertificate(
    id: 'private-a',
    certNo: 'PRIVATE-A',
    welderStamp: 'SAME',
    standard: QualificationStandard.iso9606_1,
    createdAt: 1,
    updatedAt: 1);
void main() {
  useTestDatabase();
  late AccountService account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({kLegacyCertMigratedPrefsKey: true});
    FlutterSecureStorage.setMockInitialValues({});
    account = AccountService.forTesting(MockClient((request) async {
      final id = (jsonDecode(request.body)['email'] as String).split('@').first;
      return http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200);
    }));
    AccountService.instance = account;
    await account.signIn('a@example.test', 'test-password');
    final db = await AppDatabase.get();
    await db.delete('welder_cert_confirmations');
    await db.delete('welder_certificates');
    await WelderCertificateDao().upsert(privateCertificate);
  });
  Future<void> mount(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(home: child)));
    await settle(t);
  }

  testWidgets(
      'visible register and cached overview do not survive account change',
      (t) async {
    await mount(t, const CertificateRegisterPage());
    expect(find.textContaining('PRIVATE-A'), findsWidgets);
    await t.runAsync(() => account.signIn('b@example.test', 'test-password'));
    expect(WelderQualificationService.instance.overview.value, isNull);
    await settle(t);
    expect(find.textContaining('PRIVATE-A'), findsNothing);
    expect(find.textContaining('Brak certyfikatów'), findsWidgets);
    await t.runAsync(() => account.signIn('a@example.test', 'test-password'));
    await settle(t);
    expect(find.textContaining('PRIVATE-A'), findsWidgets);
  });
  testWidgets('old editor hides its initial certificate on account change',
      (t) async {
    await mount(t, const CertificateEditPage(certificate: privateCertificate));
    expect(find.text('PRIVATE-A'), findsOneWidget);
    await t.runAsync(() => account.signIn('b@example.test', 'test-password'));
    await settle(t);
    expect(find.text('PRIVATE-A'), findsNothing);
    expect(find.text('Konto zmieniło się. Otwórz rejestr ponownie.'),
        findsOneWidget);
    expect(await t.runAsync(() => WelderCertificateDao().count()), 0);
  });
  testWidgets(
      'delete dialog hides old certificate and cannot delete after account change',
      (t) async {
    await mount(t, const CertificateRegisterPage());
    await t.tap(find.byTooltip('Usuń').first);
    await settle(t);
    expect(find.textContaining('Usuniemy wpis'), findsOneWidget);
    await t.runAsync(() => account.signIn('b@example.test', 'test-password'));
    await settle(t);
    expect(find.textContaining('Usuniemy wpis'), findsNothing);
    expect(find.text('Konto zmieniło się. Otwórz rejestr ponownie.'),
        findsOneWidget);
    await t.tap(find.text('Zamknij'));
    await settle(t);
    await t.runAsync(() => account.signIn('a@example.test', 'test-password'));
    await settle(t);
    expect(find.textContaining('PRIVATE-A'), findsWidgets);
  });
  testWidgets(
      'date picker hides the original certificate date after account change',
      (t) async {
    await mount(t, const CertificateEditPage(certificate: privateCertificate));
    await t.tap(find.byIcon(Icons.calendar_today).first);
    await settle(t);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await t.runAsync(() => account.signIn('b@example.test', 'test-password'));
    await settle(t);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('Konto zmieniło się. Otwórz rejestr ponownie.'),
        findsWidgets);
    expect(await t.runAsync(() => WelderCertificateDao().count()), 0);
  });
  test('expired export authorization does not invoke platform sharing',
      () async {
    await QualificationExport.shareCsv(const [], mayShare: () => false);
    await QualificationExport.sharePdf(const [], mayShare: () => false);
  });
  test('account change while PDF fonts load prevents later platform sharing',
      () async {
    final origin = LocalRecordSession.capture();
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
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    final pending = QualificationExport.sharePdf(const [],
        mayShare: () => origin.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(origin.isCurrent, isFalse);
  });
}
