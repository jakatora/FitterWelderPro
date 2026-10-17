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

import '../domain/welding/electrode_exposure.dart';
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
);

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
