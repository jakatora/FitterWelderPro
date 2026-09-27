// Timer spawalniczy jako serwis (lib/services/weld_timer_service.dart).
//
// Zegar i skutki uboczne (wibracja, dźwięk, wygaszanie ekranu, powiadomienie)
// są wstrzykiwane — test nie dotyka platformy i nie czeka na prawdziwy czas.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/weld_timer_service.dart';

import '../support/fake_weld_timer_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late FakeEffects fx;
  late WeldTimerService timer;

  void advance(Duration d) {
    now = now.add(d);
    timer.tick();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 25, 10);
    fx = FakeEffects();
    timer = WeldTimerService(
      now: () => now,
      effects: fx,
      // Bez prawdziwego Timer.periodic — takt wywołuje test (advance).
      startTicker: (_) => null,
      observeLifecycle: false,
    );
  });

  tearDown(() => timer.dispose());

  group('liczenie czasu z zegara, nie z taktów', () {
    test('spawanie: stoper liczy w górę, bez alarmu', () {
      timer.start();
      advance(const Duration(minutes: 7, seconds: 3));
      expect(timer.elapsed, const Duration(minutes: 7, seconds: 3));
      expect(timer.target, isNull);
      expect(timer.remaining, isNull);
      expect(timer.alarmActive, isFalse);
      expect(fx.alarms, isEmpty);
    });

    test('zgubione takty nie zjadają czasu (liczy się zegar)', () {
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(minutes: 2));
      timer.start();
      now = now.add(const Duration(seconds: 50)); // bez tick()
      expect(timer.elapsed, const Duration(seconds: 50));
      expect(timer.remaining, const Duration(seconds: 70));
    });

    test('pauza zamraża czas, wznowienie liczy dalej', () {
      timer.start();
      advance(const Duration(seconds: 30));
      timer.pause();
      advance(const Duration(minutes: 5));
      expect(timer.elapsed, const Duration(seconds: 30));
      timer.start();
      advance(const Duration(seconds: 10));
      expect(timer.elapsed, const Duration(seconds: 40));
    });

    test('reset zeruje i gasi alarm', () {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(5);
      timer.start();
      advance(const Duration(seconds: 6));
      expect(timer.alarmActive, isTrue);
      timer.reset();
      expect(timer.elapsed, Duration.zero);
      expect(timer.alarmActive, isFalse);
      expect(timer.finished, isFalse);
      expect(timer.running, isFalse);
    });
  });

  group('postęp i start purge z innego ekranu', () {
    test('hasProgress: biegnie lub pauza w połowie; nie po końcu/resecie', () {
      expect(timer.hasProgress, isFalse);
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(minutes: 8));
      timer.start();
      expect(timer.hasProgress, isTrue);
      advance(const Duration(minutes: 1));
      timer.pause();
      expect(timer.hasProgress, isTrue);
      timer.reset();
      expect(timer.hasProgress, isFalse);
    });

    test('startPurge: 138,4 s → 139 s odliczania, alarm na końcu', () {
      timer.startPurge(const Duration(milliseconds: 138400));
      expect(timer.mode, WeldTimerMode.purge);
      expect(timer.purgeSeconds, 139);
      expect(timer.running, isTrue);
      advance(const Duration(seconds: 139));
      expect(timer.alarmActive, isTrue);
      expect(fx.alarms, hasLength(1));
    });

    test('startPurge 0 s nic nie robi', () {
      timer.startPurge(Duration.zero);
      expect(timer.running, isFalse);
    });
  });

  group('koniec odliczania', () {
    test('chłodzenie: alarm raz, z przypomnieniem o temp. z WPS', () {
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(minutes: 2));
      timer.setMaxInterpass(150);
      timer.start();
      advance(const Duration(seconds: 119));
      expect(timer.alarmActive, isFalse);
      advance(const Duration(seconds: 1));
      expect(timer.alarmActive, isTrue);
      expect(timer.finished, isTrue);
      expect(timer.running, isFalse);
      // Wyświetlacz stoi na celu, nie „ucieka” dalej.
      expect(timer.elapsed, const Duration(minutes: 2));
      expect(fx.alarms, hasLength(1));
      expect(fx.alarms.single.mode, WeldTimerMode.cool);
      expect(fx.alarms.single.maxInterpassC, 150);

      advance(const Duration(seconds: 10));
      expect(fx.alarms, hasLength(1), reason: 'alarm nie powtarza się co takt');
    });

    test('potwierdzenie gasi pełnoekranowy komunikat, stan „koniec” zostaje', () {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(3);
      timer.start();
      advance(const Duration(seconds: 3));
      timer.acknowledgeAlarm();
      expect(timer.alarmActive, isFalse);
      expect(timer.finished, isTrue);
    });

    test('„kolejny ścieg” startuje to samo odliczanie od zera', () {
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(seconds: 30));
      timer.start();
      advance(const Duration(seconds: 30));
      timer.restart();
      expect(timer.alarmActive, isFalse);
      expect(timer.running, isTrue);
      expect(timer.elapsed, Duration.zero);
      advance(const Duration(seconds: 30));
      expect(fx.alarms, hasLength(2));
    });

    test('start po końcu zaczyna od nowa (nie od razu alarm)', () {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(2);
      timer.start();
      advance(const Duration(seconds: 2));
      timer.acknowledgeAlarm();
      timer.start();
      expect(timer.elapsed, Duration.zero);
      expect(timer.alarmActive, isFalse);
    });

    test('skrócenie czasu w trakcie kończy odliczanie na najbliższym takcie', () {
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(minutes: 5));
      timer.start();
      advance(const Duration(minutes: 1));
      timer.setCoolTime(const Duration(seconds: 30));
      timer.tick();
      expect(timer.alarmActive, isTrue);
    });

    test('czas 0 nie startuje odliczania z natychmiastowym alarmem', () {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(0);
      timer.start();
      expect(timer.running, isFalse);
      expect(fx.alarms, isEmpty);
    });
  });

  group('ekran nie gaśnie tylko w trakcie', () {
    test('start włącza, pauza / koniec / reset wyłączają', () {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(10);
      timer.start();
      expect(fx.keepsScreenOn, isTrue);
      timer.pause();
      expect(fx.keepsScreenOn, isFalse);
      timer.start();
      expect(fx.keepsScreenOn, isTrue);
      advance(const Duration(seconds: 10));
      expect(fx.keepsScreenOn, isFalse, reason: 'koniec odliczania');
      timer.start();
      timer.reset();
      expect(fx.keepsScreenOn, isFalse);
    });
  });

  group('zmiana trybu i parametry przeżywają ekran', () {
    test('zmiana trybu zatrzymuje i zeruje', () {
      timer.start();
      advance(const Duration(seconds: 20));
      timer.setMode(WeldTimerMode.cool);
      expect(timer.mode, WeldTimerMode.cool);
      expect(timer.running, isFalse);
      expect(timer.elapsed, Duration.zero);
    });

    test('ten sam tryb nie zeruje biegnącego timera', () {
      timer.setMode(WeldTimerMode.cool);
      timer.start();
      advance(const Duration(seconds: 20));
      timer.setMode(WeldTimerMode.cool);
      expect(timer.running, isTrue);
      expect(timer.elapsed, const Duration(seconds: 20));
    });

    test('granice: chłodzenie 0–600 min, purge 0–24 h', () {
      timer.setCoolTime(const Duration(minutes: 9000));
      expect(timer.coolTime, const Duration(minutes: 600));
      timer.setCoolTime(const Duration(minutes: -3));
      expect(timer.coolTime, Duration.zero);
      timer.setPurgeSeconds(999999);
      expect(timer.purgeSeconds, 24 * 3600);
    });

    test('słuchacze dostają powiadomienie o każdej zmianie', () {
      var calls = 0;
      timer.addListener(() => calls++);
      timer.start();
      advance(const Duration(seconds: 1));
      timer.pause();
      expect(calls, greaterThanOrEqualTo(3));
    });
  });

  group('aplikacja w tle', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('pierwszy start odliczania pyta o zgodę, kolejne już nie', () async {
      timer.setMode(WeldTimerMode.cool);
      timer.start();
      await flush();
      expect(fx.permissionRequests, 1);
      timer.reset();
      timer.start();
      await flush();
      expect(fx.permissionRequests, 1);

      // Nowa instancja (np. restart aplikacji) — pamięta, że już pytała.
      final again = WeldTimerService(
        now: () => now,
        effects: fx,
        startTicker: (_) => null,
        observeLifecycle: false,
      );
      addTearDown(again.dispose);
      again.setMode(WeldTimerMode.cool);
      again.start();
      await flush();
      expect(fx.permissionRequests, 1);
    });

    test('stoper spawania nie pyta o powiadomienia', () async {
      timer.start();
      await flush();
      expect(fx.permissionRequests, 0);
    });

    test('platforma bez powiadomień nie pyta', () async {
      fx.notificationsSupported = false;
      timer.setMode(WeldTimerMode.cool);
      timer.start();
      await flush();
      expect(fx.permissionRequests, 0);
      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      expect(fx.scheduled, isEmpty);
    });

    test('w tle: powiadomienie na koniec, po powrocie anulowane', () async {
      timer.setMode(WeldTimerMode.cool);
      timer.setCoolTime(const Duration(minutes: 2));
      timer.setMaxInterpass(150);
      timer.start();
      await flush();
      advance(const Duration(seconds: 30));

      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      expect(fx.scheduled, hasLength(1));
      final (at, title, body) = fx.scheduled.single;
      expect(at, now.add(const Duration(seconds: 90)));
      expect(title, isNotEmpty);
      expect(body, contains('150'));

      timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush();
      expect(fx.cancels, greaterThanOrEqualTo(1));
    });

    test('bez zgody: nic nie planuje, zostaje stan w aplikacji', () async {
      fx.grant = false;
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(60);
      timer.start();
      await flush();
      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      expect(fx.scheduled, isEmpty);
    });

    test('koniec w tle: bez wibracji (robi to powiadomienie), komunikat czeka', () async {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(60);
      timer.start();
      await flush();
      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      advance(const Duration(seconds: 61));
      expect(timer.alarmActive, isTrue);
      expect(fx.alarms, isEmpty);

      timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush();
      expect(timer.alarmActive, isTrue, reason: 'pełny ekran po powrocie');
    });

    test('zatrzymany timer w tle niczego nie planuje', () async {
      timer.setMode(WeldTimerMode.purge);
      timer.setPurgeSeconds(60);
      timer.start();
      await flush();
      timer.pause();
      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      expect(fx.scheduled, isEmpty);
      expect(fx.cancels, 0, reason: 'nic nie było zaplanowane');
    });

    test('reset / pauza anulują zaplanowane powiadomienie', () async {
      for (final stop in <void Function()>[timer.reset, timer.pause]) {
        timer.setMode(WeldTimerMode.purge);
        timer.setPurgeSeconds(60);
        timer.start();
        await flush();
        timer.didChangeAppLifecycleState(AppLifecycleState.paused);
        await flush();
        final before = fx.cancels;
        stop();
        expect(fx.cancels, before + 1);
        timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        timer.reset();
      }
      expect(fx.scheduled, hasLength(2));
    });
  });
}
