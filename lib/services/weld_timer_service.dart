/// Timer spawalniczy (stoper spawania, chłodzenie między ściegami,
/// formowanie) — logika poza ekranem.
///
/// Dlaczego serwis, a nie stan zakładki: spawacz startuje chłodzenie,
/// przełącza zakładkę albo wychodzi do dziennika spoin, a timer ma liczyć
/// dalej i zaalarmować na koniec. Stan zakładki ginął razem z nią.
///
/// Czas liczy się z ZEGARA (`now()` przy starcie i teraz), nie z liczby
/// taktów `Timer.periodic` — zgubione takty (aplikacja w tle, przycięty
/// wątek) nie zjadają sekund. Takt co sekundę tylko odświeża ekran
/// i sprawdza koniec. Zegar domyślnie to `clock.now()` z pakietu `clock`
/// (w testach widgetów podąża za czasem testu); testy serwisu podają własny.
///
/// Skutki uboczne za interfejsem [WeldTimerEffects] (testy podstawiają
/// atrapę):
///  • wibracja + dźwięk + komunikat głosowy na koniec odliczania — spawacz
///    pod przyłbicą i w rękawicach nie zobaczy zmiany koloru;
///  • ekran nie gaśnie, ale tylko gdy timer biegnie (`wakelock_plus`);
///  • aplikacja w tle: lokalne powiadomienie na chwilę końca
///    (`flutter_local_notifications`, bez uprawnień exact alarm). O zgodę
///    na powiadomienia pytamy raz — przy pierwszym starcie odliczania, nie
///    przy starcie aplikacji. Bez zgody zostaje sam stan w aplikacji
///    (pełnoekranowy komunikat po powrocie).
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../assistant/speech_io.dart';
import '../i18n/app_language.dart';

enum WeldTimerMode {
  /// Stoper: liczy w górę, bez alarmu.
  weld,

  /// Chłodzenie między ściegami: odliczanie + przypomnienie o maks.
  /// temperaturze międzyściegowej z WPS.
  cool,

  /// Formowanie (purge): odliczanie.
  purge,
}

/// Co się skończyło — wystarcza do napisania komunikatu.
@immutable
class WeldTimerAlarm {
  const WeldTimerAlarm({required this.mode, this.maxInterpassC});

  final WeldTimerMode mode;

  /// Maks. temperatura międzyściegowa z WPS (tylko chłodzenie).
  final double? maxInterpassC;
}

/// Teksty komunikatu końca odliczania — jedno źródło dla pełnego ekranu,
/// powiadomienia i komunikatu głosowego.
({String title, String body, String spoken}) weldTimerAlarmText(
  WeldTimerAlarm alarm, {
  required bool english,
}) {
  String t(String pl, String en) => english ? en : pl;
  switch (alarm.mode) {
    case WeldTimerMode.cool:
      final max = alarm.maxInterpassC;
      final hasMax = max != null && max > 0;
      return (
        title: t('KONIEC CHŁODZENIA', 'COOLDOWN OVER'),
        body: hasMax
            ? t(
                'Zmierz temperaturę pirometrem — kolejny ścieg dopiero przy '
                    '≤ ${max.toStringAsFixed(0)} °C (WPS).',
                'Measure the temperature — next pass only at '
                    '≤ ${max.toStringAsFixed(0)} °C (WPS).')
            : t('Zmierz temperaturę pirometrem przed kolejnym ściegiem (WPS).',
                'Measure the temperature before the next pass (WPS).'),
        spoken: t('Koniec chłodzenia. Zmierz temperaturę.',
            'Cooldown over. Measure the temperature.'),
      );
    case WeldTimerMode.purge:
    case WeldTimerMode.weld:
      return (
        title: t('KONIEC FORMOWANIA', 'PURGE TIME OVER'),
        body: t('Sprawdź zawartość O₂ analizatorem przed spawaniem.',
            'Check O₂ with the analyser before welding.'),
        spoken: t('Koniec formowania. Sprawdź tlen.',
            'Purge time over. Check oxygen.'),
      );
  }
}

/// Skutki uboczne timera — platforma albo atrapa w testach. Żadna metoda
/// nie może wywrócić timera: serwis i tak łapie błędy.
abstract class WeldTimerEffects {
  /// Ekran nie gaśnie (`true`) / wraca zwykłe wygaszanie (`false`).
  Future<void> setKeepScreenOn(bool on);

  /// Wibracja + dźwięk + komunikat głosowy na koniec odliczania.
  Future<void> alarm(WeldTimerAlarm alarm);

  /// Czy platforma dostaje powiadomienia systemowe (Android / iOS).
  bool get backgroundNotificationsSupported;

  /// Prośba o zgodę na powiadomienia; `true` = można planować.
  Future<bool> requestNotificationPermission();

  Future<void> scheduleEndNotification({
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancelEndNotification();
}

/// Tworzy takt co sekundę; `null` = bez taktu (testy wołają [WeldTimerService.tick]).
typedef WeldTimerTickerFactory = Timer? Function(void Function() onTick);

// Preserve platform call order, including cancellation after an in-flight
// operation. Failures must not prevent the next requested state from applying.
class _OrderedTimerEffects {
  Future<void>? _operation;

  Future<void> run(Future<void> Function() action) {
    final previous = _operation;
    final operation = previous == null
        ? Future<void>.sync(action)
        : previous.then((_) => action());
    final settled = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    _operation = settled;
    unawaited(settled.then((_) {
      if (identical(_operation, settled)) {
        _operation = null;
      }
    }));
    return operation;
  }
}

class WeldTimerService extends ChangeNotifier with WidgetsBindingObserver {
  WeldTimerService({
    DateTime Function()? now,
    WeldTimerEffects? effects,
    WeldTimerTickerFactory? startTicker,
    bool observeLifecycle = true,
  })  : _now = now ?? (() => clock.now()),
        _effects = effects ?? SystemWeldTimerEffects(),
        _startTicker = startTicker ?? _periodicTicker,
        _observeLifecycle = observeLifecycle;

  static WeldTimerService? _instance;

  /// Jeden timer na aplikację — przeżywa zakładkę i ekran.
  static WeldTimerService get instance => _instance ??= WeldTimerService();

  @visibleForTesting
  static set instance(WeldTimerService service) => _instance = service;

  /// Zapamiętana odpowiedź na prośbę o powiadomienia (pytamy raz).
  static const String notificationsPrefsKey = 'weld_timer_notifications_v1';

  static const Duration maxCoolTime = Duration(minutes: 600);
  static const int maxPurgeSeconds = 24 * 3600;

  static Timer _periodicTicker(void Function() onTick) =>
      Timer.periodic(const Duration(seconds: 1), (_) => onTick());

  final DateTime Function() _now;
  final WeldTimerEffects _effects;
  final WeldTimerTickerFactory _startTicker;
  final bool _observeLifecycle;

  WeldTimerMode _mode = WeldTimerMode.weld;
  Duration _coolTime = const Duration(minutes: 2);
  double? _maxInterpassC = 150;
  int _purgeSeconds = 90;

  Duration _accumulated = Duration.zero;
  DateTime? _runningSince;
  bool _finished = false;
  bool _alarmActive = false;
  Timer? _ticker;

  bool _observing = false;
  bool _inForeground = true;
  bool _notificationScheduled = false;
  int _notificationRevision = 0;
  final _notificationEffects = _OrderedTimerEffects();
  final _screenEffects = _OrderedTimerEffects();
  bool? _notificationsGranted;
  Future<void>? _permission;
  bool _disposed = false;

  // ── Stan ────────────────────────────────────────────────────────────────
  WeldTimerMode get mode => _mode;
  Duration get coolTime => _coolTime;
  double? get maxInterpassC => _maxInterpassC;
  int get purgeSeconds => _purgeSeconds;

  int _controlRevision = 0;

  /// Changes only on controls/configuration, not on clock ticks.
  int get controlRevision => _controlRevision;

  bool get running => _runningSince != null;

  /// Odliczanie doszło do końca (zostaje do resetu / nowego startu).
  bool get finished => _finished;

  /// Pełnoekranowy komunikat czeka na potwierdzenie.
  bool get alarmActive => _alarmActive;

  bool get isCountdown => _mode != WeldTimerMode.weld;

  /// Cel odliczania; `null` dla stopera spawania.
  Duration? get target => switch (_mode) {
        WeldTimerMode.weld => null,
        WeldTimerMode.cool => _coolTime,
        WeldTimerMode.purge => Duration(seconds: _purgeSeconds),
      };

  Duration get _rawElapsed {
    final since = _runningSince;
    return since == null
        ? _accumulated
        : _accumulated + _now().difference(since);
  }

  /// Upłynęło — dla odliczania nigdy ponad cel.
  Duration get elapsed {
    final raw = _rawElapsed;
    final t = target;
    if (t == null) return raw;
    if (_finished) return t;
    return raw > t ? t : raw;
  }

  /// Zostało do końca odliczania; `null` dla stopera.
  Duration? get remaining {
    final t = target;
    if (t == null) return null;
    final left = t - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  WeldTimerAlarm get currentAlarm =>
      WeldTimerAlarm(mode: _mode, maxInterpassC: _maxInterpassC);

  /// Biegnie albo jest zapauzowany w połowie — zmiana trybu skasowałaby ten
  /// czas, więc ekran pyta najpierw o potwierdzenie (przegląd G4: dotknięcie
  /// rękawicą „Purge” w trakcie 8-minutowego chłodzenia kasowało odliczanie).
  bool get hasProgress =>
      running || (!_finished && _accumulated > Duration.zero);

  /// Odliczanie formowania z innego ekranu (Rury → Gazy, O₂ Purge): tryb
  /// purge, czas [duration] (zaokrąglony w górę do sekundy), start. Alarm,
  /// powiadomienie w tle i pełnoekranowy komunikat — jak w zakładce Timer.
  void startPurge(Duration duration) {
    final secs = (duration.inMilliseconds / 1000).ceil();
    if (secs <= 0) return;
    if (_mode != WeldTimerMode.purge) {
      setMode(WeldTimerMode.purge);
    } else {
      _resetState();
    }
    setPurgeSeconds(secs);
    start();
  }

  // ── Parametry ───────────────────────────────────────────────────────────
  /// Zmienia tryb; inny tryb zatrzymuje i zeruje timer. Ekran przy
  /// [hasProgress] najpierw pyta o potwierdzenie.
  void setMode(WeldTimerMode mode) {
    if (mode == _mode) return;
    _resetState();
    _controlRevision++;
    _mode = mode;
    notifyListeners();
  }

  void setCoolTime(Duration value) {
    final v = value.isNegative
        ? Duration.zero
        : (value > maxCoolTime ? maxCoolTime : value);
    if (v == _coolTime) return;
    _controlRevision++;
    _coolTime = v;
    notifyListeners();
  }

  void setMaxInterpass(double? celsius) {
    if (celsius == _maxInterpassC) return;
    _controlRevision++;
    _maxInterpassC = celsius;
    notifyListeners();
  }

  void setPurgeSeconds(int seconds) {
    final v = seconds.clamp(0, maxPurgeSeconds);
    if (v == _purgeSeconds) return;
    _controlRevision++;
    _purgeSeconds = v;
    notifyListeners();
  }

  // ── Sterowanie ──────────────────────────────────────────────────────────
  void start() {
    if (running) return;
    if (_finished) {
      _accumulated = Duration.zero;
      _finished = false;
      _alarmActive = false;
    }
    final t = target;
    if (t != null && t <= Duration.zero) return; // nie ma czego odliczać
    _ensureObserving();
    _controlRevision++;
    _runningSince = _now();
    _ticker?.cancel();
    _ticker = _startTicker(tick);
    _setKeepScreenOn(true);
    if (isCountdown) unawaited(_ensurePermission());
    notifyListeners();
    // Cel skrócony do już upłyniętego czasu — koniec od razu.
    if (t != null && _rawElapsed >= t) tick();
  }

  void pause() {
    if (!running) return;
    _controlRevision++;
    _accumulated = _rawElapsed;
    _runningSince = null;
    _stopRunningSideEffects();
    notifyListeners();
  }

  void reset() {
    _resetState();
    notifyListeners();
  }

  /// „Kolejny ścieg”: to samo odliczanie jeszcze raz, od zera.
  void restart() {
    _resetState();
    start();
  }

  /// Spawacz potwierdził pełnoekranowy komunikat.
  void acknowledgeAlarm() {
    if (!_alarmActive) return;
    _alarmActive = false;
    notifyListeners();
  }

  /// Takt: odświeża słuchaczy i sprawdza koniec odliczania.
  void tick() {
    if (_disposed) return;
    if (running) {
      final t = target;
      if (t != null && _rawElapsed >= t) {
        _finish();
        return;
      }
    }
    notifyListeners();
  }

  void _finish() {
    _controlRevision++;
    _accumulated = target ?? _rawElapsed;
    _runningSince = null;
    _finished = true;
    _alarmActive = true;
    _ticker?.cancel();
    _ticker = null;
    _setKeepScreenOn(false);
    // W tle alarmuje zaplanowane powiadomienie; tu tylko stan, żeby po
    // powrocie czekał pełnoekranowy komunikat.
    if (_inForeground) {
      final alarm = currentAlarm;
      _safe(() => _effects.alarm(alarm));
    }
    notifyListeners();
  }

  void _resetState() {
    _controlRevision++;
    final wasRunning = running;
    _accumulated = Duration.zero;
    _runningSince = null;
    _finished = false;
    _alarmActive = false;
    if (wasRunning) {
      _stopRunningSideEffects();
    } else {
      _ticker?.cancel();
      _ticker = null;
      _cancelNotification();
    }
  }

  void _stopRunningSideEffects() {
    _ticker?.cancel();
    _ticker = null;
    _setKeepScreenOn(false);
    _cancelNotification();
  }

  // ── Tło aplikacji ───────────────────────────────────────────────────────
  void _ensureObserving() {
    if (!_observeLifecycle || _observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  Future<void> _ensurePermission() => _permission ??= _loadOrAskPermission();

  Future<void> _loadOrAskPermission() async {
    if (!_effects.backgroundNotificationsSupported) {
      _notificationsGranted = false;
      return;
    }
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(notificationsPrefsKey);
      if (stored != null) {
        _notificationsGranted = stored;
        return;
      }
    } catch (_) {
      // Bez preferencji po prostu zapytamy.
    }
    bool granted;
    try {
      granted = await _effects.requestNotificationPermission();
    } catch (e) {
      debugPrint('[weld timer] permission request failed: $e');
      granted = false;
    }
    _notificationsGranted = granted;
    try {
      await prefs?.setBool(notificationsPrefsKey, granted);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        final wasBackground = !_inForeground;
        _inForeground = true;
        if (wasBackground) {
          _cancelNotification();
          tick(); // koniec mógł minąć w tle
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _inForeground = false;
        unawaited(_scheduleForBackground());
    }
  }

  Future<void> _scheduleForBackground() async {
    if (_disposed || _notificationScheduled || !running || !isCountdown) return;
    if (!_effects.backgroundNotificationsSupported) return;
    final left = remaining;
    if (left == null || left <= Duration.zero) return;
    await _ensurePermission();
    if (_notificationsGranted != true) return;
    // Mogło się zmienić w czasie await (powrót, pauza).
    if (_disposed || _inForeground || !running || _notificationScheduled) return;
    final currentRemaining = remaining;
    if (currentRemaining == null || currentRemaining <= Duration.zero) return;
    final at = _now().add(currentRemaining);
    final text = weldTimerAlarmText(currentAlarm,
        english: AppLanguageController.isEnglish);
    _notificationScheduled = true;
    final revision = ++_notificationRevision;
    try {
      await _notificationEffects.run(() => _effects.scheduleEndNotification(
          at: at, title: text.title, body: text.body));
    } catch (e) {
      if (revision == _notificationRevision) {
        _notificationScheduled = false;
      }
      debugPrint('[weld timer] schedule failed: $e');
    }
  }

  /// Anuluje tylko to, co sami zaplanowaliśmy — bez zbędnych wywołań
  /// wtyczki przy każdej zmianie trybu.
  void _cancelNotification() {
    if (!_notificationScheduled) return;
    _notificationScheduled = false;
    _notificationRevision++;
    _safe(() => _notificationEffects.run(_effects.cancelEndNotification));
  }

  void _setKeepScreenOn(bool on) {
    _safe(() => _screenEffects.run(() => _effects.setKeepScreenOn(on)));
  }

  void _safe(Future<void> Function() action) {
    unawaited(Future<void>.sync(action).catchError((Object e) {
      debugPrint('[weld timer] effect failed: $e');
    }));
  }

  @override
  void dispose() {
    _disposed = true;
    if (running) _setKeepScreenOn(false);
    _cancelNotification();
    _ticker?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Platforma: `vibration`, `SystemSound`, `flutter_tts`, `wakelock_plus`,
/// `flutter_local_notifications`.
class SystemWeldTimerEffects implements WeldTimerEffects {
  SystemWeldTimerEffects({SpeechOutput? speech})
      : _speech = speech ?? SystemSpeechOutput();

  final SpeechOutput _speech;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  /// Stały identyfikator — jedno powiadomienie timera naraz. Przypomnienia
  /// o uprawnieniach mają identyfikatory z hasha (reminder_plan.dart).
  static const int notificationId = 0x57454C44; // „WELD”
  static const String _channelId = 'weld_timer_alarm';

  /// Długie impulsy: krótkie „tyknięcia” HapticFeedback giną w rękawicach
  /// i pod kurtką, a na Androidzie w ogóle znikają, gdy użytkownik wyłączył
  /// wibracje dotyku w ustawieniach.
  static const List<int> vibrationPattern = [
    0,
    800,
    400,
    800,
    400,
    800,
    400,
    1500
  ];

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get backgroundNotificationsSupported => _mobile;

  @override
  Future<void> setKeepScreenOn(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('[weld timer] wakelock: $e');
    }
  }

  @override
  Future<void> alarm(WeldTimerAlarm alarm) async {
    unawaited(_vibrate());
    try {
      // iOS: systemowy dźwięk alertu. Android go nie gra (obsługuje tylko
      // „click”) — tam dźwiękiem jest komunikat głosowy niżej.
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    final text =
        weldTimerAlarmText(alarm, english: AppLanguageController.isEnglish);
    await _speech.speak(text.spoken, AppLanguageController.current);
  }

  Future<void> _vibrate() async {
    if (_mobile) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: vibrationPattern);
          return;
        }
      } catch (e) {
        debugPrint('[weld timer] vibration: $e');
      }
    }
    // Zapas: seria mocnych impulsów haptycznych.
    for (var i = 0; i < 5; i++) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _ensureInitialized() => _initializing ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          // Ta sama ikona co przypomnienia o uprawnieniach
          // (res/drawable/ic_stat_notify.xml, trzymana przez res/raw/keep.xml).
          android: AndroidInitializationSettings('ic_stat_notify'),
          // Bez próśb przy inicjalizacji — zgoda tylko w
          // requestNotificationPermission (pierwszy start odliczania).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<bool> requestNotificationPermission() async {
    if (!_mobile) return false;
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? (await android?.areNotificationsEnabled() ?? false);
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> scheduleEndNotification({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!_mobile) return;
    await _ensureInitialized();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Timer spawalniczy / Weld timer',
        channelDescription: 'Koniec chłodzenia między ściegami i formowania, '
            'gdy aplikacja jest w tle.',
        icon: 'ic_stat_notify',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: Int64List.fromList(vibrationPattern),
      ),
      iOS: const DarwinNotificationDetails(presentSound: true),
    );
    // Harmonogram przybliżony (inexactAllowWhileIdle) — bez uprawnień
    // SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM. W głębokim uśpieniu telefonu
    // (Doze) powiadomienie może przyjść nieco później niż koniec odliczania.
    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'weld_timer',
    );
  }

  @override
  Future<void> cancelEndNotification() async {
    if (!_mobile) return;
    await _ensureInitialized();
    await _plugin.cancel(id: notificationId);
  }
}
