/// Lokalne przypomnienia o uprawnieniach spawacza — warstwa wtyczki.
///
/// CO i KIEDY liczy czysta funkcja `planQualificationReminders`
/// (lib/domain/qualification/reminder_plan.dart, testy bez platformy). Tu
/// tylko: zgoda użytkownika, zaplanowanie planu we wtyczce
/// `flutter_local_notifications`, anulowanie starego planu.
///
/// Zasady platform:
///  • Android / iOS — powiadomienia systemowe. O zgodę pytamy WYŁĄCZNIE, gdy
///    spawacz sam włącza przypomnienia w rejestrze uprawnień (nie przy starcie
///    aplikacji): Android 13+ — POST_NOTIFICATIONS, iOS — alert + dźwięk.
///    Inicjalizacja wtyczki ma wyłączone wszystkie `request*Permission`, więc
///    samo uruchomienie aplikacji nigdy nie wyświetla prośby.
///  • Android — zwykły harmonogram `inexactAllowWhileIdle`: przypomnienie
///    o 9:00 może przyjść kilka minut później i to nie ma znaczenia przy
///    terminie za 7 dni. Dzięki temu NIE potrzebujemy SCHEDULE_EXACT_ALARM /
///    USE_EXACT_ALARM (Play wymaga ich uzasadnienia).
///  • web, Windows, macOS, Linux — bez powiadomień; ostrzega baner w menu
///    SPAWACZ i w profilu ([supported] = false).
///
/// Strefa czasowa: planujemy chwilę bezwzględną (`TZDateTime` w UTC
/// utworzone z lokalnej daty 9:00). Dla jednorazowego powiadomienia to
/// wystarcza i nie wymaga bazy stref czasowych ani wtyczki `flutter_timezone`.
/// Zmiana strefy (podróż) przesuwa godzinę, nie dzień — przy następnym
/// otwarciu aplikacji plan i tak liczy się od nowa.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../database/local_record_owner.dart';
import '../domain/qualification/reminder_plan.dart';

/// Co warstwa usług potrzebuje od platformy. Interfejs, żeby testy mogły
/// podstawić atrapę i nie dotykać kanałów platformy.
abstract class ReminderPlatform {
  /// Czy ta platforma w ogóle dostaje powiadomienia systemowe.
  bool get supported;

  /// Prosi o zgodę na powiadomienia; `true` = można planować.
  Future<bool> requestPermission();

  Future<void> schedule(List<PlannedReminder> reminders);

  Future<void> cancel(Iterable<int> ids);
}

/// Implementacja na `flutter_local_notifications`.
class LocalNotificationsReminderPlatform implements ReminderPlatform {
  LocalNotificationsReminderPlatform({
    this.channelId = 'welder_qualification_reminders',
    this.channelName = 'Uprawnienia spawacza / Welder qualifications',
    this.channelDescription = 'Przypomnienia o ważności i potwierdzeniu '
        'uprawnień (ISO 9606-1, ASME IX).',
    this.payloadPrefix = 'welder_certificate',
  });

  /// Kanał powiadomień (Android) — osobny dla każdego rejestru, żeby
  /// użytkownik mógł wyciszyć jeden bez drugiego.
  final String channelId;
  final String channelName;
  final String channelDescription;

  /// Prefiks ładunku powiadomienia: `prefiks:id rekordu`.
  final String payloadPrefix;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  /// Nazwa zasobu ikony (android/app/src/main/res/drawable/ic_stat_notify.xml).
  /// Trzymana przez res/raw/keep.xml — R8 z shrinkResources wyciąłby ikonę
  /// wskazywaną tylko napisem, a wtedy powiadomienie po cichu się nie pokaże.
  static const String androidIcon = 'ic_stat_notify';

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _ensureInitialized() => _initializing ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(androidIcon),
          // Wszystkie prośby wyłączone: zgoda tylko przy świadomym włączeniu
          // przypomnień (requestPermission), nigdy przy starcie aplikacji.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      // Poniżej Androida 13 prośby nie ma — liczy się, czy użytkownik nie
      // wyłączył powiadomień w ustawieniach.
      return granted ?? (await android?.areNotificationsEnabled() ?? false);
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    if (!supported || reminders.isEmpty) return;
    await _ensureInitialized();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        icon: androidIcon,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.fireAt, tz.UTC),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '$payloadPrefix:${r.certificateId}',
      );
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    if (!supported) return;
    await _ensureInitialized();
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }
}

/// Włącznik przypomnień + przechowywanie identyfikatorów zaplanowanych
/// powiadomień (żeby umieć je anulować po zmianie rejestru).
///
/// [ownerScoped] (rejestr uprawnień — dane konta, schema32): włącznik należy
/// do właściciela danych (gość zostaje na dawnym kluczu), a harmonogram
/// pamięta, dla kogo go ułożono. Po zmianie konta [syncWithAccount] anuluje
/// powiadomienia poprzedniego właściciela — z numerami JEGO certyfikatów.
class QualificationReminders {
  QualificationReminders({
    ReminderPlatform? platform,
    this.enabledKey = enabledPrefsKey,
    this.idsKey = idsPrefsKey,
    this.ownerScoped = false,
    Future<LocalRecordOwner> Function()? captureOwner,
  })  : _platform = platform ?? LocalNotificationsReminderPlatform(),
        _captureOwner = captureOwner ?? LocalRecordOwner.capture;

  /// Klucze SharedPreferences tego rejestru (uprawnienia — domyślne).
  final String enabledKey;
  final String idsKey;
  final bool ownerScoped;
  final Future<LocalRecordOwner> Function() _captureOwner;

  static QualificationReminders instance =
      QualificationReminders(ownerScoped: true);

  final ReminderPlatform _platform;
  int _enableRevision = 0;

  static const String enabledPrefsKey = 'welder_cert_reminders_enabled_v1';
  static const String idsPrefsKey = 'welder_cert_reminder_ids_v1';

  /// Właściciel, dla którego ułożono obecny harmonogram (tylko [ownerScoped]).
  String get scheduleOwnerKey => '${idsKey}_owner';

  bool get supported => _platform.supported;

  /// Klucz włącznika bieżącego właściciela; `null` = właściciela nie da się
  /// ustalić (sesja w trakcie zmiany) — traktujemy jak wyłączone.
  Future<({String key, String? owner})?> _enabledKeyNow() async {
    if (!ownerScoped) return (key: enabledKey, owner: null);
    try {
      final owner = await _captureOwner();
      owner.requireCurrent();
      final key = owner.key == LocalRecordOwner.guest
          ? enabledKey
          : '$enabledKey.owner.${Uri.encodeComponent(owner.key)}';
      return (key: key, owner: owner.key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isEnabled() async {
    if (!supported) return false;
    final current = await _enabledKeyNow();
    if (current == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(current.key) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Po zmianie konta: harmonogram ułożony dla INNEGO właściciela jest
  /// anulowany od razu (nie czeka na następne przeliczenie rejestru). Ten
  /// sam właściciel po ponownym uruchomieniu aplikacji — nic się nie dzieje.
  Future<void> syncWithAccount() async {
    if (!ownerScoped || !supported) return;
    final current = await _enabledKeyNow();
    if (current == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final scheduledFor = prefs.getString(scheduleOwnerKey);
      if (scheduledFor != null && scheduledFor != current.owner) {
        await _cancelStored();
      }
    } catch (e) {
      debugPrint('[reminders] account sync failed: $e');
    }
  }

  /// Włącza przypomnienia: pyta o zgodę i planuje [plan]. `false`, gdy
  /// platforma nie obsługuje powiadomień albo użytkownik odmówił — wtedy
  /// przełącznik zostaje wyłączony.
  Future<bool> enable(List<PlannedReminder> plan) async {
    if (!supported) return false;
    final revision = ++_enableRevision;
    // Permission UI may stay open while the user switches accounts. Capture
    // the owner before that await so an A plan never enables B's switch.
    LocalRecordOwner? requestedBy;
    bool currentRequest() => revision == _enableRevision &&
        (requestedBy?.isCurrent ?? true);
    if (ownerScoped) {
      try {
        requestedBy = await _captureOwner();
      } catch (_) {
        return false;
      }
    }
    if (!currentRequest()) return false;
    bool granted;
    try {
      granted = await _platform.requestPermission();
    } catch (e) {
      debugPrint('[reminders] permission request failed: $e');
      granted = false;
    }
    if (!granted) return false;
    if (!currentRequest()) return false;
    final current = await _enabledKeyNow();
    if (current == null || !currentRequest()) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!currentRequest()) return false;
      await prefs.setBool(current.key, true);
    } catch (_) {
      return false;
    }
    if (!currentRequest()) return false;
    await reschedule(plan);
    return currentRequest();
  }

  /// Wyłącza (dla bieżącego właściciela) i anuluje wszystko, co
  /// zaplanowaliśmy.
  Future<void> disable() async {
    _enableRevision++;
    final current = await _enabledKeyNow();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (current != null) await prefs.setBool(current.key, false);
    } catch (_) {
      // Anulujemy mimo to.
    }
    await _cancelStored();
  }

  /// Zastępuje poprzedni plan [plan]em. Nic nie robi, gdy przypomnienia są
  /// wyłączone. Nigdy nie rzuca — błąd platformy nie może zablokować zapisu
  /// certyfikatu.
  Future<void> reschedule(List<PlannedReminder> plan) async {
    LocalRecordOwner? requestedBy;
    if (ownerScoped) {
      try {
        requestedBy = await _captureOwner();
      } catch (_) {
        return;
      }
    }
    bool sessionCurrent() => requestedBy?.isCurrent ?? true;
    if (!await isEnabled()) {
      // Wyłączone dla tego właściciela — harmonogram innego nie zostaje.
      if (sessionCurrent()) await syncWithAccount();
      return;
    }
    if (!sessionCurrent()) return;
    final current = await _enabledKeyNow();
    if (current == null || !sessionCurrent()) return;
    try {
      await _cancelStored();
      if (!sessionCurrent()) return;
      await _platform.schedule(plan);
      if (!sessionCurrent()) {
        await _platform.cancel(plan.map((r) => r.id));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (!sessionCurrent()) {
        await _platform.cancel(plan.map((r) => r.id));
        return;
      }
      await prefs
          .setStringList(idsKey, [for (final r in plan) r.id.toString()]);
      if (ownerScoped && current.owner != null) {
        await prefs.setString(scheduleOwnerKey, current.owner!);
      }
    } catch (e) {
      debugPrint('[reminders] reschedule failed: $e');
    }
  }

  Future<void> _cancelStored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(idsKey) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) await _platform.cancel(ids);
      await prefs.remove(idsKey);
      if (ownerScoped) await prefs.remove(scheduleOwnerKey);
    } catch (e) {
      debugPrint('[reminders] cancel failed: $e');
    }
  }
}
