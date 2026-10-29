import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_batch_store.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_exposure_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/electrode_reminders.dart';
import 'package:cut_list_app/services/electrode_log_export.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoReminders implements ReminderPlatform {
  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {}
  @override
  Future<void> cancel(Iterable<int> ids) async {}
}

class _RecordingReminders implements ReminderPlatform {
  @override
  bool get supported => true;
  final scheduled = <int>[];
  final cancelled = <int>[];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> schedule(List<PlannedReminder> reminders) async =>
      scheduled.addAll(reminders.map((r) => r.id));
  @override
  Future<void> cancel(Iterable<int> ids) async => cancelled.addAll(ids);
}

class _DelayedPermission extends _RecordingReminders {
  final requested = Completer<void>();
  final answer = Completer<bool>();

  @override
  Future<bool> requestPermission() {
    requested.complete();
    return answer.future;
  }
}

class _BlockingCancel extends _RecordingReminders {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool block = false;

  @override
  Future<void> cancel(Iterable<int> ids) async {
    await super.cancel(ids);
    if (block) {
      entered.complete();
      await release.future;
    }
  }
}

class _BlockingSchedule extends _RecordingReminders {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool block = false;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    await super.schedule(reminders);
    if (block) {
      entered.complete();
      await release.future;
    }
  }
}

ElectrodeBatch _batch(String id) => ElectrodeBatch.takenOut(
      id: id,
      electrode: ElectrodeClass.e7018,
      at: DateTime(2026, 10, 29, 7),
      location: '${id.toUpperCase()}_PRIVATE',
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
      await const ElectrodeBatchStore().save([_batch(id)]);
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
        home: ElectrodeExposurePage(
          now: () => DateTime(2026, 10, 29, 8),
          reminders: QualificationReminders(platform: _NoReminders()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('otwarta lista partii przełącza się z konta A na B',
      (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey('electrode-card-a')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('electrode-card-a')), findsNothing);
    expect(find.byKey(const ValueKey('electrode-card-b')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty formularz nowej partii A znika po zmianie konta',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('electrode-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('electrode-location')), 'A_DRAFT');
    await tester.pumpAndSettle();
    expect(find.text('A_DRAFT'), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('A_DRAFT'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty wybór godziny A znika po zmianie konta', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('electrode-add')));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('electrode-time-pick'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog limitu partii A znika po zmianie konta', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('electrode-more-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień limit / suszenia'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('electrode-limit-edit')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('electrode-limit-edit')), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis partii A nie nadpisuje dziennika konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = ElectrodeBatchStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        stale.save([_batch('stale')]), throwsA(isA<AccountException>()));
    expect((await const ElectrodeBatchStore().load()).single.id, 'b');
    await account.signIn('a@example.test', 'test-password');
    expect((await const ElectrodeBatchStore().load()).single.id, 'a');
  });

  test('zmiana konta anuluje powiadomienia elektrod mimo zamkniętego ekranu',
      () async {
    expect(electrodeReminders.ownerScoped, isTrue);
    final platform = _RecordingReminders();
    final reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
      ownerScoped: true,
    );
    final plan = <PlannedReminder>[
      PlannedReminder(
        id: 77,
        fireAt: DateTime(2026, 10, 29, 10),
        certificateId: 'a',
        kind: ReminderKind.expiry,
        daysBefore: 0,
        deadline: DateTime(2026, 10, 29, 11),
        title: 'A_PRIVATE',
        body: 'A_PRIVATE',
      ),
    ];
    expect(await reminders.enable(plan), isTrue);
    expect(platform.scheduled, [77]);
    final binding =
        ElectrodeReminderAccountBinding(account: account, reminders: reminders)
          ..start();
    addTearDown(binding.dispose);

    await account.signIn('b@example.test', 'test-password');
    await pumpEventQueue();
    expect(platform.cancelled, contains(77));
    expect(await reminders.isEnabled(), isFalse);
    await account.signIn('a@example.test', 'test-password');
    expect(await reminders.isEnabled(), isTrue);
  });

  test('powrót na konto A wznawia przypomnienia bez otwierania ekranu',
      () async {
    final now = DateTime.now();
    final batch = ElectrodeBatch.takenOut(
      id: 'resume-a',
      electrode: ElectrodeClass.e7018,
      at: now.subtract(const Duration(minutes: 5)),
    );
    await const ElectrodeBatchStore().save([batch]);
    final platform = _RecordingReminders();
    final reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
      ownerScoped: true,
    );
    final plan = planElectrodeReminders([batch], now: now, english: false);
    expect(plan, isNotEmpty);
    expect(await reminders.enable(plan), isTrue);
    final binding =
        ElectrodeReminderAccountBinding(account: account, reminders: reminders)
          ..start();
    addTearDown(binding.dispose);

    await account.signIn('b@example.test', 'test-password');
    await pumpEventQueue();
    final scheduledBeforeReturn = platform.scheduled.length;
    await account.signIn('a@example.test', 'test-password');
    await pumpEventQueue();
    expect(platform.scheduled.length, greaterThan(scheduledBeforeReturn));
  });

  test('zgoda na przypomnienia A nie włącza ich na koncie B', () async {
    final platform = _DelayedPermission();
    final reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
      ownerScoped: true,
    );
    final pending = reminders.enable([
      PlannedReminder(
        id: 88,
        fireAt: DateTime(2026, 10, 29, 10),
        certificateId: 'a',
        kind: ReminderKind.expiry,
        daysBefore: 0,
        deadline: DateTime(2026, 10, 29, 11),
        title: 'A_PRIVATE',
        body: 'A_PRIVATE',
      ),
    ]);
    await platform.requested.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    platform.answer.complete(true);

    expect(await pending, isFalse);
    expect(await reminders.isEnabled(), isFalse);
    expect(platform.scheduled, isEmpty);
  });

  test('PDF partii A nie otwiera udostępniania po zmianie konta', () async {
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

    final pending = ElectrodeLogExport.sharePdf([_batch('a')],
        now: DateTime(2026, 10, 29, 8),
        range: LogRange.all,
        mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(shareCalls, 0);
  });

  test('przeplanowanie A nie planuje jego powiadomień po zmianie na B',
      () async {
    final platform = _BlockingCancel();
    final reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
      ownerScoped: true,
    );
    PlannedReminder planned(int id) => PlannedReminder(
          id: id,
          fireAt: DateTime(2026, 10, 29, 10),
          certificateId: 'a',
          kind: ReminderKind.expiry,
          daysBefore: 0,
          deadline: DateTime(2026, 10, 29, 11),
          title: 'A_PRIVATE',
          body: 'A_PRIVATE',
        );
    expect(await reminders.enable([planned(90)]), isTrue);
    platform.block = true;

    final pending = reminders.reschedule([planned(91)]);
    await platform.entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    platform.release.complete();
    await pending;
    expect(platform.scheduled, [90]);
  });

  test('powiadomienie A rozpoczęte przed zmianą konta zostaje anulowane',
      () async {
    final platform = _BlockingSchedule();
    final reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
      ownerScoped: true,
    );
    PlannedReminder planned(int id) => PlannedReminder(
          id: id,
          fireAt: DateTime(2026, 10, 29, 10),
          certificateId: 'a',
          kind: ReminderKind.expiry,
          daysBefore: 0,
          deadline: DateTime(2026, 10, 29, 11),
          title: 'A_PRIVATE',
          body: 'A_PRIVATE',
        );
    expect(await reminders.enable([planned(90)]), isTrue);
    platform.block = true;

    final pending = reminders.reschedule([planned(91)]);
    await platform.entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    platform.release.complete();
    await pending;
    expect(platform.scheduled, [90, 91]);
    expect(platform.cancelled, contains(91));
  });
}
