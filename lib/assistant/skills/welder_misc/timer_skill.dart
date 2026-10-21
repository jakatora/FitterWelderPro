import '../../../services/weld_timer_service.dart';
import '../../../domain/welding/welder_calculator_input.dart';
import 'package:flutter/foundation.dart' show mapEquals;
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
bool _set(Utterance u) =>
    u.hasStem(const ['ustaw', 'zmien', 'set', 'change', 'configure']);

const _literalWords = {
  'na',
  'to',
  'the',
  'a',
  'of',
  'at',
  'for',
  'using',
  'czas',
  'time',
  'duration',
  'limit',
  'c',
  's',
  'h',
  'tak',
  'nie',
  'yes',
  'no',
  'or',
  'and',
  'albo',
  'lub',
  'czy',
  'minus',
  'stop',
  'prosze',
  'please',
  'mi',
  'me',
  'my',
  'teraz',
  'now',
  'keep',
  'wps',
  'wedlug',
  'wg',
};
const _literalStems = [
  'timer',
  'stoper',
  'stopwatch',
  'odlicz',
  'chlodzen',
  'cooldown',
  'cooling',
  'formowan',
  'purge',
  'spawan',
  'welding',
  'uruchom',
  'wlacz',
  'start',
  'rozpocz',
  'wznow',
  'resume',
  'zatrzymaj',
  'pauz',
  'pause',
  'wyzeruj',
  'reset',
  'ustaw',
  'zmien',
  'set',
  'change',
  'configure',
  'obliczon',
  'obliczen',
  'wyliczon',
  'calculated',
  'wynik',
  'result',
  'sek',
  'sec',
  'min',
  'godzin',
  'hour',
  'cels',
  'replace',
  'zastap',
  'zostaw',
  'cancel',
  'anuluj',
];

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
    if (u.hasStem(const ['obliczon', 'obliczen', 'wyliczon', 'calculated']) ||
        u.hasAny(const ['wyniku', 'result']))
      'calculated': true,
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
  bool requiresInterpretationFor(Utterance u, Map<String, Object?> supplied) =>
      pendingReplyNeedsInterpretation(u) ||
      u.raw.contains('%') ||
      u.items.any((i) =>
          !i.isNumber &&
          !_literalWords.contains(i.word) &&
          !_literalStems.any(i.word.startsWith)) ||
      action == 'stop' &&
          (supplied.containsKey('seconds') || supplied.containsKey('max_c'));
  @override
  bool acceptsProposal(
      Utterance original, Utterance command, AssistantContext context) {
    final clauses = original.folded
        .split(RegExp(r'\b(?:potem|nastepnie|pozniej|then|after that)\b'));
    final timerClauses =
        clauses.where((c) => _topic(original.withRaw(c))).toList();
    final intent = timerClauses.isEmpty
        ? original
        : original.withRaw(timerClauses.join(' '));
    final supplied = _slots(intent), normalized = _slots(command);
    final originalMode = supplied['mode'];
    var proposedMode = normalized['mode'];
    if (proposedMode == null) {
      final modules = context.modules;
      final visible = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      if (visible?['tab'] == 'timer') proposedMode = visible?['mode'];
    }
    if (originalMode != null &&
        originalMode != 'ambiguous' &&
        proposedMode != originalMode) {
      return false;
    }
    if (supplied['resume'] == true &&
        (normalized['resume'] != true ||
            supplied.containsKey('seconds') ||
            supplied.containsKey('max_c') ||
            pendingReplyNeedsInterpretation(intent))) {
      return false;
    }
    if (_set(intent) && !_start(intent) && !_stop(intent)) {
      return action == 'set';
    }
    if (_start(intent) && !_set(intent) && !_stop(intent)) {
      return action != 'set' && action != 'stop';
    }
    if (_stop(intent) && !_set(intent) && !_start(intent)) {
      if ((supplied['reset'] == true) != (normalized['reset'] == true)) {
        return false;
      }
      if (pendingReplyNeedsInterpretation(intent) ||
          supplied.containsKey('seconds') ||
          supplied.containsKey('max_c')) {
        return false;
      }
      return action == 'stop';
    }
    return true;
  }

  @override
  List<SkillExample> get examples => switch (action) {
        'set' => const [
            SkillExample('Ustaw timer chłodzenia 2 minuty',
                'Set cooldown timer 2 minutes'),
            SkillExample('Ustaw timer formowania 90 sekund',
                'Set purge timer 90 seconds'),
            SkillExample('Zmień czas timera chłodzenia na 3 minuty',
                'Change cooldown timer to 3 minutes'),
            SkillExample('Ustaw timer chłodzenia 2 minuty limit 150 C',
                'Set cooldown timer 2 minutes limit 150 C'),
            SkillExample('Ustaw stoper spawania', 'Set welding stopwatch'),
            SkillExample('Ustaw timer 90 sekund', 'Set timer 90 seconds'),
          ],
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
            SkillExample('Uruchom timer formowania na obliczony czas',
                'Start purge timer using the calculated time'),
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
        : _set(u)
            ? 'set'
            : _cool(u)
                ? 'cool'
                : 'start';
    if (chosen != action ||
        (!_start(u) &&
            !_stop(u) &&
            !_set(u) &&
            !(_cool(u) && u.hasAny(const ['timer'])))) {
      return null;
    }
    if (u.raw.trim().endsWith('?') ||
        u.hasAny(const ['ile', 'dlaczego', 'why', 'how long'])) {
      return null;
    }
    if (kOpenVerbAtStartRe.hasMatch(u.folded) && !_start(u)) return null;
    final slots = _slots(u);
    return SkillMatch(this, .98,
        slots: slots,
        utterance: u,
        requiresAiInterpretation: requiresInterpretationFor(u, slots));
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
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Zostawiam obecny timer.', 'Keeping the current timer.')),
          actionCompleted: false);
    }
    final reset = s['reset'] == true;
    if (action == 'stop' && s['mode'] != null && s['mode'] != timer.mode.name) {
      if (!timer.hasProgress) {
        return const AnswerResult(
            AssistantAnswer(
                text: AssistantText(
                    'Nie ma aktywnego timera w wybranym trybie.',
                    'There is no active timer in the requested mode.')),
            actionCompleted: false);
      }
      return const FailedResult(AssistantText(
          'Aktywny timer ma inny tryb. Podaj właściwy tryb albo powiedz „zatrzymaj timer”.',
          'The active timer has a different mode. Give the matching mode or say “stop timer”.'));
    }
    if (action == 'stop' && !reset) {
      timer.pause();
      return _answer(timer, 'Timer zatrzymany; czas zachowany.',
          'Timer paused; elapsed time kept.');
    }
    final modules = ctx.modules;
    final fields = modules is FieldModuleContext
        ? (modules as FieldModuleContext).inputFields(toolId)
        : null;
    final visibleTimer = fields?['tab'] == 'timer' ? fields : null;
    final previousInputs = s['timer_inputs'];
    if (previousInputs is Map<String, Object?> &&
        !mapEquals(previousInputs, visibleTimer)) {
      return const FailedResult(AssistantText(
          'Ustawienia timera zmieniły się. Ponów polecenie dla aktualnych danych.',
          'Timer settings changed. Repeat the request for the current inputs.'));
    }
    final modeName = s['mode'] ?? visibleTimer?['mode'];
    if (action != 'stop' && s['resume'] == true) {
      if (s.containsKey('seconds') ||
          s.containsKey('max_c') ||
          s['calculated'] == true ||
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
    var seconds = s['seconds'] as double?;
    var durationFromForm = s['duration_from_form'] == true;
    final fromVisible =
        visibleTimer != null && visibleTimer['mode'] == modeName;
    if (action != 'stop' &&
        s['calculated'] != true &&
        seconds == null &&
        fromVisible &&
        mode != WeldTimerMode.weld) {
      final value = visibleTimer[
          mode == WeldTimerMode.cool ? 'cool_minutes' : 'purge_seconds'];
      final limit =
          mode == WeldTimerMode.cool ? 600 : WeldTimerService.maxPurgeSeconds;
      final configured = visibleTimer['target_seconds'];
      seconds = value is num &&
              value.isFinite &&
              value > 0 &&
              value <= limit &&
              configured is num &&
              configured.isFinite
          ? configured.toDouble()
          : double.nan;
      durationFromForm = true;
    }
    if (s['calculated'] == true &&
        (mode != WeldTimerMode.purge ||
            (seconds != null && s['purge_inputs'] == null))) {
      return const FailedResult(AssistantText(
          'Wybierz timer formowania według obliczenia albo podaj jego czas wprost.',
          'Choose the calculated purge countdown or give its duration explicitly.'));
    }
    Map<String, Object?>? purgeInputs;
    if (action != 'stop' &&
        mode == WeldTimerMode.purge &&
        (seconds == null || s['purge_inputs'] != null)) {
      final modules = ctx.modules;
      final fields = modules is FieldModuleContext
          ? (modules as FieldModuleContext).inputFields(toolId)
          : null;
      final previous = s['purge_inputs'];
      if (previous is Map<String, Object?> && !mapEquals(previous, fields)) {
        return const FailedResult(AssistantText(
            'Dane kalkulatora formowania zmieniły się. Ponownie poproś o uruchomienie timera dla aktualnego wyniku.',
            'The purge calculator inputs changed. Ask again to start the timer for the current result.'));
      }
      if (fields?['tab'] == 'purge') {
        try {
          seconds = PurgeCalculatorInput.fromFields(fields!).estimate.timeSec;
          purgeInputs = Map<String, Object?>.from(fields);
        } on FormatException {
          // Incomplete native inputs must never supply an inferred duration.
        }
      }
      if (seconds == null && s['calculated'] == true) {
        return _ask(
            m.copyWith(slots: {...s}..remove('calculated')),
            'seconds',
            'Brak poprawnego wyniku w otwartym kalkulatorze formowania. Podaj czas timera z jednostką albo uzupełnij kalkulator i ponów polecenie.',
            'There is no valid result in the open purge calculator. Give a timer duration with a unit, or complete the calculator and repeat the command.');
      }
    }
    var max = s['max_c'] as double?;
    if (mode == WeldTimerMode.cool &&
        !s.containsKey('max_c') &&
        action != 'stop') {
      if (fromVisible && visibleTimer['max_c_valid'] == false) {
        return _ask(
            m,
            'max_c',
            'Podaj poprawny limit WPS w °C albo wyczyść pole.',
            'Enter a valid WPS limit in °C or clear the field.');
      }
      if (fromVisible) {
        max = ((visibleTimer.containsKey('configured_max_c')
                ? visibleTimer['configured_max_c']
                : visibleTimer['max_c']) as num?)
            ?.toDouble();
      } else if (action == 'set' && timer.mode == WeldTimerMode.cool) {
        max = timer.maxInterpassC;
      }
    }
    if (max != null && mode != WeldTimerMode.cool) {
      return const FailedResult(AssistantText(
          'Limit temperatury dotyczy timera chłodzenia.',
          'The temperature limit applies to the cooldown timer.'));
    }
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
    final sameRunningWeld = action != 'stop' &&
        action != 'set' &&
        mode == WeldTimerMode.weld &&
        timer.mode == mode;
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
            if (visibleTimer != null) ...{
              'timer_inputs': Map<String, Object?>.from(visibleTimer),
              'mode': modeName,
              if (mode != WeldTimerMode.weld) 'seconds': seconds,
              if (durationFromForm) 'duration_from_form': true,
              if (mode == WeldTimerMode.cool) 'max_c': max,
            },
            if (purgeInputs != null) ...{
              'seconds': seconds,
              'purge_inputs': purgeInputs,
            },
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
      final milliseconds = seconds! * 1000;
      timer.setCoolTime(Duration(
          milliseconds:
              durationFromForm ? milliseconds.round() : milliseconds.ceil()));
      timer.setMaxInterpass(
          max); // Preserve explicit/visible settings; never invent a WPS limit.
    } else if (mode == WeldTimerMode.purge) {
      timer.setPurgeSeconds(seconds!.ceil());
    }
    if (action == 'set') {
      return _answer(
          timer,
          'Timer ustawiony. Odliczanie nie zostało uruchomione.',
          'Timer configured. The countdown has not been started.');
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
