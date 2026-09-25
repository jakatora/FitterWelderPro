/// Pełnoekranowy komunikat końca odliczania timera spawalniczego.
///
/// Siedzi w `MaterialApp.builder` (app.dart) NAD nawigatorem, więc pokazuje
/// się na każdym ekranie — spawacz mógł wyjść z timera do dziennika spoin.
/// Duże litery i przyciski ≥ 64 dp: czytane przez szybkę przyłbicy,
/// naciskane w rękawicach. Znika dopiero po potwierdzeniu.
library;

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/weld_timer_service.dart';

class WeldTimerAlarmOverlay extends StatelessWidget {
  const WeldTimerAlarmOverlay({super.key, required this.child, this.service});

  final Widget child;

  /// Domyślnie [WeldTimerService.instance]; testy mogą podać własny.
  final WeldTimerService? service;

  @override
  Widget build(BuildContext context) {
    final timer = service ?? WeldTimerService.instance;
    return ListenableBuilder(
      listenable: timer,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (timer.alarmActive)
            Positioned.fill(child: _AlarmScreen(timer: timer)),
        ],
      ),
    );
  }
}

class _AlarmScreen extends StatelessWidget {
  const _AlarmScreen({required this.timer});

  final WeldTimerService timer;

  static const _bg = Color(0xFF0B3D1F);
  static const _accent = Color(0xFF2ECC71);

  @override
  Widget build(BuildContext context) {
    final text = weldTimerAlarmText(timer.currentAlarm,
        english: context.language == AppLanguage.en);
    final restartLabel = timer.mode == WeldTimerMode.cool
        ? context.tr(pl: 'Kolejny ścieg — chłodzenie od nowa', en: 'Next pass — restart cooldown')
        : context.tr(pl: 'Odliczaj jeszcze raz', en: 'Count down again');
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        key: const ValueKey('weld-timer-alarm'),
        color: _bg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.alarm_on, size: 96, color: _accent),
                    const SizedBox(height: 16),
                    Text(
                      text.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      text.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 80,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: timer.acknowledgeAlarm,
                        child: Text(
                          context.tr(pl: 'OK', en: 'OK'),
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 72,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70, width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: timer.restart,
                        icon: const Icon(Icons.replay, size: 28),
                        label: Text(
                          restartLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
