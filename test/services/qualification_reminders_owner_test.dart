// Przypomnienia o uprawnieniach a konta: włącznik należy do właściciela
// danych (gość zostaje na dawnym kluczu), a po zmianie konta powiadomienia
// poprzedniego (z numerami JEGO certyfikatów) są od razu anulowane.

import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_account.dart';

class _FakePlatform implements ReminderPlatform {
  @override
  bool get supported => true;
  final List<List<int>> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    scheduled.add([for (final r in reminders) r.id]);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async => cancelled.addAll(ids);
}

class _DelayedSchedulePlatform extends _FakePlatform {
  final started = Completer<void>();
  final release = Completer<void>();
  bool first = true;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    if (first) {
      first = false;
      started.complete();
      await release.future;
    }
    await super.schedule(reminders);
  }
}

PlannedReminder _r(int id) => PlannedReminder(
      id: id,
      fireAt: DateTime(2027, 1, 1, 9),
      certificateId: 'c$id',
      kind: ReminderKind.expiry,
      daysBefore: 30,
      deadline: DateTime(2027, 1, 31),
      title: 't',
      body: 'b',
    );

Future<void> signIn(String id) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance =
      AccountService.forTesting(MockClient((_) async => http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200)));
  await AccountService.instance.signIn('$id@example.test', 'test-password');
}

void main() {
  late _FakePlatform platform;
  late QualificationReminders previous;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await seedGuestAccount();
    platform = _FakePlatform();
    previous = QualificationReminders.instance;
    QualificationReminders.instance =
        QualificationReminders(platform: platform, ownerScoped: true);
  });
  tearDown(() => QualificationReminders.instance = previous);

  test('włącznik należy do właściciela; gość zostaje na dawnym kluczu',
      () async {
    final reminders = QualificationReminders.instance;
    expect(await reminders.enable([_r(1)]), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(QualificationReminders.enabledPrefsKey), isTrue,
        reason: 'gość: dawny klucz bez zmian');

    await signIn('a');
    expect(await reminders.isEnabled(), isFalse,
        reason: 'konto nie dziedziczy zgody gościa');
    await reminders.reschedule([_r(2)]);
    expect(platform.scheduled, [
      [1]
    ], reason: 'wyłączone dla konta — nic nie zaplanowano');
    expect(await reminders.enable([_r(2)]), isTrue);

    await seedGuestAccount();
    expect(await reminders.isEnabled(), isTrue);
    await reminders.disable();
    await signIn('a');
    expect(await reminders.isEnabled(), isTrue,
        reason: 'wyłączenie u gościa nie wyłącza konta');
  });

  test('queued guest plans never become the new account plan', () async {
    final delayed = _DelayedSchedulePlatform();
    final reminders = QualificationReminders(platform: delayed, ownerScoped: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(QualificationReminders.enabledPrefsKey, true);
    final first = reminders.reschedule([_r(1)]);
    await delayed.started.future;
    final queuedGuest = reminders.reschedule([_r(2)]);
    await signIn('b');
    final enablingB = reminders.enable([_r(3)]);
    await pumpEventQueue();
    delayed.release.complete();
    await Future.wait([first, queuedGuest]);
    expect(await enablingB, isTrue);
    expect(delayed.scheduled, [[1], [3]]);
    expect(delayed.cancelled, contains(1));
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), ['3']);
  });

  test('zmiana konta anuluje powiadomienia poprzedniego od razu', () async {
    await signIn('a');
    final reminders = QualificationReminders.instance;
    await reminders.enable([_r(7), _r(8)]);
    WelderQualificationService.instance; // wiąże serwis z bieżącą sesją
    platform.cancelled.clear();

    await signIn('b');
    WelderQualificationService.instance; // zmiana sesji
    await pumpEventQueue();
    expect(platform.cancelled, containsAll(<int>[7, 8]),
        reason: 'konto B nie dostaje powiadomień o certyfikatach konta A');
  });
}
