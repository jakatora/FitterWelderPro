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

class _DelayedSchedulePlatform extends _FakePlatform {
  final started = Completer<void>();
  final release = Completer<void>();
  final active = <int>{};
  int requests = 0;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    if (++requests == 1) {
      started.complete();
      await release.future;
    }
    active.addAll(reminders.map((r) => r.id));
    await super.schedule(reminders);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    active.removeAll(ids);
    await super.cancel(ids);
  }
}

class _FailingSchedulePlatform extends _FakePlatform {
  bool failSchedule = true;
  bool failCancel = false;
  int scheduleRequests = 0;
  final active = <int>{};

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    scheduleRequests++;
    if (reminders.isNotEmpty) {
      active.add(reminders.first.id);
    }
    if (failSchedule) {
      throw StateError('fixture partial schedule');
    }
    active.addAll(reminders.map((r) => r.id));
    await super.schedule(reminders);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    if (failCancel) {
      throw StateError('fixture cancellation unavailable');
    }
    active.removeAll(ids);
    await super.cancel(ids);
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

  test('disable cancels a schedule still being installed by the platform', () async {
    SharedPreferences.setMockInitialValues({QualificationReminders.enabledPrefsKey: true});
    final platform = _DelayedSchedulePlatform();
    final reminders = QualificationReminders(platform: platform);
    final scheduling = reminders.reschedule([_r(1)]);
    await platform.started.future;
    final disabling = reminders.disable();
    await Future<void>.delayed(Duration.zero);
    platform.release.complete();
    await Future.wait([scheduling, disabling]);
    expect(platform.active, isEmpty);
    expect(await reminders.isEnabled(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), isNull);
  });

  test('overlapping reschedules leave only the newest plan and stored IDs', () async {
    SharedPreferences.setMockInitialValues({QualificationReminders.enabledPrefsKey: true});
    final platform = _DelayedSchedulePlatform();
    final reminders = QualificationReminders(platform: platform);
    final first = reminders.reschedule([_r(1)]);
    await platform.started.future;
    final second = reminders.reschedule([_r(2)]);
    await Future<void>.delayed(Duration.zero);
    platform.release.complete();
    await Future.wait([first, second]);
    expect(platform.active, {2});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), ['2']);
  });

  test('a later enable wins over disable queued behind an older schedule', () async {
    SharedPreferences.setMockInitialValues({QualificationReminders.enabledPrefsKey: true});
    final platform = _DelayedSchedulePlatform();
    final reminders = QualificationReminders(platform: platform);
    final scheduling = reminders.reschedule([_r(1)]);
    await platform.started.future;
    final disabling = reminders.disable();
    final enabling = reminders.enable([_r(3)]);
    await Future<void>.delayed(Duration.zero);
    platform.release.complete();
    await Future.wait([scheduling, disabling]);
    expect(await enabling, isTrue);
    expect(await reminders.isEnabled(), isTrue);
    expect(platform.active, {3});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), ['3']);
  });

  test('partial platform schedule is cancelled after failure', () async {
    final platform = _FailingSchedulePlatform();
    final reminders = QualificationReminders(platform: platform);
    await reminders.enable([_r(1), _r(2)]);
    expect(platform.active, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), isNull);
  });

  test('failed cleanup preserves IDs for a later cancellation retry', () async {
    final platform = _FailingSchedulePlatform()..failCancel = true;
    final reminders = QualificationReminders(platform: platform);
    await reminders.enable([_r(1), _r(2)]);
    expect(platform.active, {1});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), ['1', '2']);
    platform.failCancel = false;
    await reminders.disable();
    expect(platform.active, isEmpty);
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), isNull);
  });

  test('failed cancellation keeps the old plan without installing another', () async {
    final platform = _FailingSchedulePlatform()..failSchedule = false;
    final reminders = QualificationReminders(platform: platform);
    await reminders.enable([_r(1)]);
    platform.failCancel = true;
    await reminders.reschedule([_r(2)]);
    expect(platform.scheduleRequests, 1);
    expect(platform.active, {1});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QualificationReminders.idsPrefsKey), ['1']);
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
