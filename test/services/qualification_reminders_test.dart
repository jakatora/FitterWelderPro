// Włącznik przypomnień: zgoda dopiero przy włączeniu, anulowanie starego
// planu, platformy bez powiadomień — na atrapie platformy.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';

class _FakePlatform implements ReminderPlatform {
  _FakePlatform({this.supported = true, this.grant = true});

  @override
  final bool supported;
  bool grant;
  int permissionRequests = 0;
  final List<List<int>> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    scheduled.add([for (final r in reminders) r.id]);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    cancelled.addAll(ids);
  }
}

class _DelayedPermissionPlatform extends _FakePlatform {
  final requested = Completer<void>();
  final permission = Completer<bool>();

  @override
  Future<bool> requestPermission() {
    permissionRequests++;
    if (permissionRequests == 1) {
      requested.complete();
      return permission.future;
    }
    return Future.value(false);
  }
}

PlannedReminder _r(int id) => PlannedReminder(
      id: id,
      fireAt: DateTime(2027, 1, 1, 9),
      certificateId: 'c',
      kind: ReminderKind.expiry,
      daysBefore: 30,
      deadline: DateTime(2027, 1, 31),
      title: 't',
      body: 'b',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('domyślnie wyłączone — przeliczenie rejestru nic nie planuje i o nic '
      'nie pyta', () async {
    final platform = _FakePlatform();
    final reminders = QualificationReminders(platform: platform);
    expect(await reminders.isEnabled(), isFalse);
    await reminders.reschedule([_r(1)]);
    expect(platform.scheduled, isEmpty);
    expect(platform.permissionRequests, 0);
  });

  test('włączenie pyta o zgodę i planuje; ponowny plan anuluje stary',
      () async {
    final platform = _FakePlatform();
    final reminders = QualificationReminders(platform: platform);

    expect(await reminders.enable([_r(1), _r(2)]), isTrue);
    expect(platform.permissionRequests, 1);
    expect(platform.scheduled, [
      [1, 2]
    ]);
    expect(await reminders.isEnabled(), isTrue);

    await reminders.reschedule([_r(3)]);
    expect(platform.cancelled, [1, 2]);
    expect(platform.scheduled.last, [3]);
    // Przeliczenie nie pyta ponownie o zgodę.
    expect(platform.permissionRequests, 1);
  });

  test('odmowa zgody — przełącznik zostaje wyłączony, nic nie planujemy',
      () async {
    final platform = _FakePlatform(grant: false);
    final reminders = QualificationReminders(platform: platform);
    expect(await reminders.enable([_r(1)]), isFalse);
    expect(await reminders.isEnabled(), isFalse);
    expect(platform.scheduled, isEmpty);
  });

  test('wyłączenie anuluje wszystko, co zaplanowaliśmy', () async {
    final platform = _FakePlatform();
    final reminders = QualificationReminders(platform: platform);
    await reminders.enable([_r(7), _r(8)]);
    await reminders.disable();
    expect(platform.cancelled, [7, 8]);
    expect(await reminders.isEnabled(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), isNull);
  });

  test('disable while permission is pending wins over a late grant', () async {
    final platform = _DelayedPermissionPlatform();
    final reminders = QualificationReminders(platform: platform);
    final enabling = reminders.enable([_r(1)]);
    await platform.requested.future;
    await reminders.disable();
    platform.permission.complete(true);
    expect(await enabling, isFalse);
    expect(await reminders.isEnabled(), isFalse);
    expect(platform.scheduled, isEmpty);
  });

  test('later denied enable cannot be replaced by an older granted request', () async {
    final platform = _DelayedPermissionPlatform();
    final reminders = QualificationReminders(platform: platform);
    final first = reminders.enable([_r(1)]);
    await platform.requested.future;
    expect(await reminders.enable([_r(2)]), isFalse);
    platform.permission.complete(true);
    expect(await first, isFalse);
    expect(await reminders.isEnabled(), isFalse);
    expect(platform.scheduled, isEmpty);
  });

  test('wtyczka: powiadomienia tylko na Androidzie i iOS', () {
    final platform = LocalNotificationsReminderPlatform();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final (target, expected) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, true),
      (TargetPlatform.windows, false),
      (TargetPlatform.macOS, false),
      (TargetPlatform.linux, false),
    ]) {
      debugDefaultTargetPlatformOverride = target;
      expect(platform.supported, expected, reason: target.name);
    }
  });

  test('web / Windows — bez powiadomień i bez prośby o zgodę', () async {
    final platform = _FakePlatform(supported: false);
    final reminders = QualificationReminders(platform: platform);
    expect(reminders.supported, isFalse);
    expect(await reminders.enable([_r(1)]), isFalse);
    expect(platform.permissionRequests, 0);
    expect(await reminders.isEnabled(), isFalse);
  });
}
