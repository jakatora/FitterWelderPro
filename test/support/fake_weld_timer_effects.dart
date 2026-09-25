// Atrapa skutków ubocznych timera spawalniczego — zapisuje, co by się stało
// na telefonie (wibracja, ekran, powiadomienie), zamiast dotykać platformy.

import 'package:cut_list_app/services/weld_timer_service.dart';

class FakeEffects implements WeldTimerEffects {
  FakeEffects({this.notificationsSupported = true, this.grant = true});

  bool notificationsSupported;
  bool grant;

  final List<bool> screenOn = [];
  final List<WeldTimerAlarm> alarms = [];
  int permissionRequests = 0;
  final List<(DateTime, String, String)> scheduled = [];
  int cancels = 0;

  bool get keepsScreenOn => screenOn.isNotEmpty && screenOn.last;

  @override
  bool get backgroundNotificationsSupported => notificationsSupported;

  @override
  Future<void> setKeepScreenOn(bool on) async => screenOn.add(on);

  @override
  Future<void> alarm(WeldTimerAlarm alarm) async => alarms.add(alarm);

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> scheduleEndNotification(
          {required DateTime at,
          required String title,
          required String body}) async =>
      scheduled.add((at, title, body));

  @override
  Future<void> cancelEndNotification() async => cancels++;
}
