/// Przypomnienia o końcu czasu na powietrzu elektrod zasadowych — ta sama
/// warstwa co uprawnienia spawacza i kalibracja przyrządów
/// ([QualificationReminders] + [LocalNotificationsReminderPlatform]), własny
/// kanał i własne klucze.
///
/// Plan (co i kiedy) liczy czysta funkcja `planElectrodeReminders`
/// (lib/domain/welding/electrode_exposure.dart): X minut przed końcem
/// limitu i w chwili końca. Platforma planuje chwilę bezwzględną, więc
/// dokładność do minuty wystarcza bez zmian w [QualificationReminders].
/// Android: harmonogram `inexactAllowWhileIdle` (bez uprawnienia
/// SCHEDULE_EXACT_ALARM) — w trybie Doze powiadomienie może przyjść kilka
/// minut później; dlatego pierwsze przypomnienie jest z wyprzedzeniem,
/// a ekran i tak pokazuje licznik na żywo.
library;

import 'dart:async';

import '../database/local_record_owner.dart';
import '../domain/welding/electrode_exposure.dart';
import '../features/electrode_exposure/electrode_batch_store.dart';
import '../i18n/app_language.dart';
import 'account_service.dart';
import 'qualification_reminders.dart';

final QualificationReminders electrodeReminders = QualificationReminders(
  platform: LocalNotificationsReminderPlatform(
    channelId: 'electrode_exposure_reminders',
    channelName: 'Elektrody zasadowe / Low-hydrogen electrodes',
    channelDescription:
        'Koniec czasu na powietrzu elektrod zasadowych (AWS D1.1, karta '
        'producenta).',
    payloadPrefix: 'electrode_batch',
  ),
  enabledKey: 'electrode_reminders_enabled_v1',
  idsKey: 'electrode_reminder_ids_v1',
  ownerScoped: true,
);

/// Cancels the previous owner's notifications and restores the current
/// owner's plan even when the electrode screen is closed. Call once at start.
class ElectrodeReminderAccountBinding {
  ElectrodeReminderAccountBinding({
    required this.account,
    required this.reminders,
    this.now = DateTime.now,
  });

  final AccountService account;
  final QualificationReminders reminders;
  final DateTime Function() now;
  bool _started = false;
  Future<void> _pending = Future<void>.value();

  void start() {
    if (_started) return;
    _started = true;
    account.addListener(_accountChanged);
    _accountChanged();
  }

  void _accountChanged() {
    _pending = _pending.then((_) => _sync());
    unawaited(_pending);
  }

  Future<void> _sync() async {
    if (!_started || !reminders.supported) return;
    try {
      final owner = await LocalRecordOwner.capture();
      if (!_started || !owner.isCurrent) return;
      await reminders.syncWithAccount();
      if (!_started || !owner.isCurrent) return;
      final batches =
          await ElectrodeBatchStore(captureOwner: () async => owner).load();
      if (!_started || !owner.isCurrent) return;
      await rescheduleElectrodeReminders(reminders, batches,
          now: now(), english: AppLanguageController.isEnglish);
    } catch (_) {
      // A stale or unavailable session must not interrupt account switching.
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    account.removeListener(_accountChanged);
  }
}

/// Przeplanowanie po każdej zmianie partii (dodanie, piecyk, suszenie,
/// zużycie, usunięcie, zmiana limitu). Nic nie robi przy wyłączonych
/// przypomnieniach; nigdy nie rzuca.
Future<void> rescheduleElectrodeReminders(
  QualificationReminders reminders,
  List<ElectrodeBatch> batches, {
  required DateTime now,
  required bool english,
}) =>
    reminders.reschedule(
        planElectrodeReminders(batches, now: now, english: english));
