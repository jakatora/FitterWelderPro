import '../../../services/weld_timer_service.dart';
import '../../core/skill.dart';
import '../../core/command_words.dart';
import '../fitter_routes/quantities.dart' show signedQuantity;

bool _topic(Utterance u) => u.hasStem(
    const ['timer', 'stoper', 'stopwatch', 'odlicz', 'chlodzen', 'cooldown']);
bool _stop(Utterance u) =>
    (u.hasStem(const ['zatrzymaj', 'pauz', 'pause', 'wyzeruj', 'reset']) ||
        u.hasAny(const ['stop']));
bool _start(Utterance u) => u.hasStem(const [
      'uruchom',
      'wlacz',
      'start',
      'rozpocznij',
      'wznow',
      'resume',
      'odlicz'
    ]);
bool _cool(Utterance u) => u.hasStem(const ['chlodzen', 'cooldown', 'cooling']);

Map<String, Object?> _slots(Utterance original) {
  final u = original
      .withRaw(original.raw.replaceAll(RegExp(r'[-−]\s*(?=\d)'), ' minus '));
  final modes = <String>{};
  if (_cool(u)) modes.add('cool');
  if (u.hasStem(const ['formowan', 'purge'])) modes.add('purge');
  if (u.hasStem(const ['spawan', 'welding', 'stoper', 'stopwatch'])) {
    modes.add('weld');
  }
  final parts = <String, double>{};
  double? temp;
  var unknownNumber = false;
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final unit = i + 1 < u.items.length ? u.items[i + 1].word : '';
    final factor = unit.startsWith('sek') ||
            unit.startsWith('sec') ||
            unit == 's'
        ? 1.0
        : unit.startsWith('min')
            ? 60.0
            : unit.startsWith('godz') || unit.startsWith('hour') || unit == 'h'
                ? 3600.0
                : null;
    final v = signedQuantity(u, i);
    if (factor != null) {
      parts[unit.startsWith('min')
          ? 'min'
          : factor == 1
              ? 's'
              : 'h'] = parts.containsKey(unit.startsWith('min')
              ? 'min'
              : factor == 1
                  ? 's'
                  : 'h')
          ? double.nan
          : v < 0
              ? double.nan
              : v * factor;
    } else if (unit == 'c' || unit.startsWith('cels')) {
      temp = temp == null || temp == v ? v : double.nan;
    } else {
      unknownNumber = true;
    }
  }
  return {
    if (modes.isNotEmpty)
      'mode': modes.length == 1 ? modes.single : 'ambiguous',
    if (unknownNumber || parts.isNotEmpty)
      'seconds': unknownNumber
          ? double.nan
          : parts.values.fold<double>(0, (a, b) => a + b),
    if (temp != null) 'max_c': temp,
    if (u.hasStem(const ['wznow', 'resume'])) 'resume': true,
    if (u.hasStem(const ['wyzeruj', 'reset'])) 'reset': true,
  };
}

/// Explicit, reversible runtime controls. No saved records or AI calls.
class TimerSkill extends AssistantSkill {
  TimerSkill(this.action, {WeldTimerService Function()? timer})
      : _timer = timer ?? (() => WeldTimerService.instance);
  final String action;
  final WeldTimerService Function() _timer;
  @override
  String get id => 'timer.$action';
  @override
  String get toolId => 'welder_calculators';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => switch (action) {
        'cool' => const [
            SkillExample(
                'Uruchom chłodzenie 2 minuty', 'Start cooldown 2 minutes'),
            SkillExample(
                'Odlicz chłodzenie 30 sekund', 'Start cooldown 30 seconds'),
            SkillExample('Włącz timer chłodzenia 3 minuty',
                'Start cooling timer 3 minutes'),
            SkillExample('Chłodzenie timer 1 minuta 30 sekund',
                'Cooldown timer 1 minute 30 seconds'),
            SkillExample('Uruchom chłodzenie 5 minut limit 150 C',
                'Start cooldown 5 minutes limit 150 C'),
            SkillExample(
                'Odlicz chłodzenie 1 godzina', 'Start cooldown 1 hour'),
          ],
        'stop' => const [
            SkillExample('Zatrzymaj timer', 'Stop timer'),
            SkillExample('Zatrzymaj stoper spawania', 'Stop welding stopwatch'),
            SkillExample('Pauza timera', 'Pause timer'),
            SkillExample(
                'Zatrzymaj odliczanie chłodzenia', 'Stop cooldown timer'),
            SkillExample('Wyzeruj timer', 'Reset timer'),
            SkillExample('Wyzeruj stoper', 'Reset stopwatch'),
          ],
        _ => const [
            SkillExample('Uruchom stoper spawania', 'Start welding stopwatch'),
            SkillExample('Włącz stoper', 'Start stopwatch'),
            SkillExample('Wznów timer', 'Resume timer'),
            SkillExample('Uruchom timer formowania 90 sekund',
                'Start purge timer 90 seconds'),
            SkillExample('Uruchom timer', 'Start timer'),
            SkillExample('Rozpocznij stoper spawania', 'Start welding timer'),
          ],
      };
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('Oblicz t8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm'),
        SkillRejection('Ile trwa chłodzenie spoiny?'),
        SkillRejection('Otwórz timer', routesTo: 'tool.open'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (isNegatedCommand(u) || referencesInstruction(u) || !_topic(u)) {
      return null;
    }
    final chosen = _stop(u)
        ? 'stop'
        : _cool(u)
            ? 'cool'
            : 'start';
    if (chosen != action ||
        (!_start(u) && !_stop(u) && !(_cool(u) && u.hasAny(const ['timer'])))) {
      return null;
    }
    if (u.raw.trim().endsWith('?') ||
        u.hasAny(const ['ile', 'dlaczego', 'why', 'how long'])) {
      return null;
    }
    if (kOpenVerbAtStartRe.hasMatch(u.folded) && !_start(u)) return null;
    return SkillMatch(this, .98, slots: _slots(u), utterance: u);
  }

  // Bare numeric continuations must never restart a timer.
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) => const {};
  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    if (slot == 'replace') {
      if (u.hasAny(const ['tak', 'yes', 'zastap', 'replace'])) {
        return {'replace': true};
      }
      if (u.hasAny(const ['nie', 'no', 'zostaw', 'keep'])) {
        return {'replace': false};
      }
      return null;
    }
    final s = _slots(u);
    return s.containsKey(slot) ? s : null;
  }

  AskResult _ask(SkillMatch m, String slot, String pl, String en) =>
      AskResult(slot, AssistantText(pl, en), partial: m);
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    final timer = _timer();
    if (s['replace'] == false) {
      return const AnswerResult(AssistantAnswer(
          text: AssistantText(
              'Zostawiam obecny timer.', 'Keeping the current timer.')));
    }
    final reset = s['reset'] == true;
    if (action == 'stop' && !reset) {
      timer.pause();
      return _answer(timer, 'Timer zatrzymany; czas zachowany.',
          'Timer paused; elapsed time kept.');
    }
    final modeName = s['mode'];
    if (action != 'stop' && s['resume'] == true) {
      if (s.containsKey('seconds') ||
          s.containsKey('max_c') ||
          (modeName != null && modeName != timer.mode.name)) {
        return const FailedResult(AssistantText(
            'Wznowienie zachowuje tryb i czas. Aby zmienić ustawienia, powiedz „uruchom” z nowym trybem i czasem.',
            'Resume keeps the mode and duration. To change settings, say “start” with the new mode and duration.'));
      }
      if (!timer.hasProgress) {
        return _answer(
            timer,
            'Nie ma przerwanego timera do wznowienia. Wybierz tryb i uruchom nowy.',
            'There is no paused timer to resume. Choose a mode and start a new one.');
      }
      timer.start();
      return _answer(timer, 'Timer wznowiony.', 'Timer resumed.');
    }
    if (action != 'stop' && (modeName == null || modeName == 'ambiguous')) {
      return _ask(
          m,
          'mode',
          'Jaki tryb: stoper spawania, chłodzenie czy formowanie?',
          'Which mode: welding stopwatch, cooldown or purge?');
    }
    final mode = modeName == 'cool'
        ? WeldTimerMode.cool
        : modeName == 'purge'
            ? WeldTimerMode.purge
            : WeldTimerMode.weld;
    final seconds = s['seconds'] as double?;
    final max = s['max_c'] as double?;
    if (max != null && (!max.isFinite || max <= 0)) {
      return _ask(
          m,
          'max_c',
          'Podaj jeden dodatni limit temperatury z WPS w °C.',
          'Give one positive WPS temperature limit in °C.');
    }
    if (action != 'stop' && mode != WeldTimerMode.weld) {
      final limit = mode == WeldTimerMode.cool
          ? WeldTimerService.maxCoolTime.inSeconds
          : WeldTimerService.maxPurgeSeconds;
      if (seconds == null ||
          !seconds.isFinite ||
          seconds <= 0 ||
          seconds > limit) {
        return _ask(
            m,
            'seconds',
            'Podaj czas z jednostką, większy od zera i nie większy niż $limit sekund.',
            'Give a duration with a unit, above zero and no more than $limit seconds.');
      }
    }
    if (action != 'stop' && mode == WeldTimerMode.weld && seconds != null) {
      return const FailedResult(AssistantText(
          'Stoper spawania liczy w górę. Odliczanie wybierz jako chłodzenie lub formowanie.',
          'The welding stopwatch counts up. Choose cooldown or purge for a countdown.'));
    }
    final sameRunningWeld =
        action != 'stop' && mode == WeldTimerMode.weld && timer.mode == mode;
    if (timer.hasProgress &&
        !sameRunningWeld &&
        (s['replace'] != true || s['revision'] != timer.controlRevision)) {
      return AskResult(
          'replace',
          const AssistantText(
              'Obecny timer ma postęp. Zastąpić go i wyzerować czas?',
              'The current timer has progress. Replace it and reset elapsed time?'),
          partial: m.copyWith(slots: {
            ...s,
            'revision': timer.controlRevision,
            'replace': null
          }),
          choices: const [
            FollowUp(AssistantText('Zastąp', 'Replace'), 'tak zastąp timer'),
            FollowUp(AssistantText('Zostaw', 'Keep'), 'nie zostaw timer')
          ]);
    }
    if (action == 'stop') {
      timer.reset();
      return _answer(timer, 'Timer wyzerowany.', 'Timer reset.');
    }
    if (!sameRunningWeld) timer.reset();
    timer.setMode(mode);
    if (mode == WeldTimerMode.cool) {
      timer.setCoolTime(Duration(milliseconds: (seconds! * 1000).ceil()));
      timer.setMaxInterpass(
          max); // No inherited/default 150 °C for a new command.
    } else if (mode == WeldTimerMode.purge) {
      timer.setPurgeSeconds(seconds!.ceil());
    }
    timer.start();
    return _answer(
        timer,
        mode == WeldTimerMode.cool
            ? 'Chłodzenie uruchomione. Po odliczeniu zmierz temperaturę przed kolejnym ściegiem.'
            : 'Timer uruchomiony.',
        mode == WeldTimerMode.cool
            ? 'Cooldown started. Measure temperature before the next pass when the countdown ends.'
            : 'Timer started.');
  }

  AnswerResult _answer(WeldTimerService timer, String pl, String en) =>
      AnswerResult(
          AssistantAnswer(text: AssistantText(pl, en), lines: [
            AnswerLine(const AssistantText('Upłynęło [s]', 'Elapsed [s]'),
                timer.elapsed.inSeconds.toString()),
            if (timer.target != null)
              AnswerLine(const AssistantText('Czas [s]', 'Duration [s]'),
                  '${timer.target!.inMilliseconds / 1000}'),
            if (timer.mode == WeldTimerMode.cool && timer.maxInterpassC != null)
              AnswerLine(
                  const AssistantText('Limit WPS [°C]', 'WPS limit [°C]'),
                  '${timer.maxInterpassC}'),
          ]),
          show: const ShowInModule('welder_calculators', {'tab': 'timer'}));
}
