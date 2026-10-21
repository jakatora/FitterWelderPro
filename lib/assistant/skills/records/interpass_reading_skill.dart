import 'package:uuid/uuid.dart';
import '../../../domain/welding/interpass_log.dart';
import '../../../domain/welding/interpass_text.dart';
import '../../../features/interpass/interpass_store.dart';
import '../../assistant_history.dart';
import '../../core/skill.dart';
import '../fitter_routes/quantities.dart' show signedQuantity;

final _intent = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:(?:dodaj|zapisz|zanotuj)\s+(?:pomiar(?: temperatury)?|temperature)|(?:add|record|log)\s+(?:(?:interpass|preheat)\s+)?(?:temperature|reading))\b');
final _temperature = RegExp(
    r'(?<![\w.,/])(-?\d+(?:[.,]\d+)?)\s*(?:°\s*)?(C|F|celsius|fahrenheit|stopni celsjusza|stopni fahrenheita)\b',
    caseSensitive: false);
final _pass = RegExp(
    r'\b(?:[śs]cieg(?:iem|u)?|pass|run)\s+(-?\d+(?:[.,]\d+)?)\b(?![\d.,/])',
    caseSensitive: false);
final _weld = RegExp(
    r'\b(?:spoina|spoiny|spoinie|weld)\s+(?:(?:nr|numer|number)\s+)?([A-Za-z0-9][A-Za-z0-9_./-]*)',
    caseSensitive: false);
final _dateTime = RegExp(r'\b(\d{4}-\d{2}-\d{2})[ T]+(\d{2}:\d{2})\b');

class InterpassReadingSkill extends AssistantSkill {
  InterpassReadingSkill(
      {this.store = const InterpassStore(), String Function()? newId})
      : _newId = newId ?? const Uuid().v4;
  final InterpassStore store;
  final String Function() _newId;
  @override
  String get id => 'interpass.reading';
  @override
  String get toolId => 'interpass';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Dodaj pomiar temperatury', 'Add interpass temperature'),
        SkillExample('Zapisz temperaturę 120 C', 'Record temperature 120 C'),
        SkillExample('Zanotuj pomiar 250 F przed ściegiem 2',
            'Log reading 250 F before pass 2'),
        SkillExample('Dodaj pomiar temperatury spoina W-12',
            'Add temperature weld W-12'),
        SkillExample('Zapisz pomiar 120 C przed ściegiem 3 pirometr',
            'Record reading 120 C before pass 3 pyrometer'),
        SkillExample('Dodaj pomiar 150 C kredka stopiła się',
            'Add reading 150 C crayon melted'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz temperaturę międzyściegową',
            routesTo: 'tool.open'),
        SkillRejection('ustaw maksymalną temperaturę WPS na 250 C'),
        SkillRejection('przelicz twardość 250 HV na HB',
            routesTo: 'hardness.convert'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!_intent.hasMatch(u.folded)) return null;
    final slots = slotsFrom(u, ctx);
    slots['origin_voice'] = u.byVoice;
    final modules = ctx.modules;
    if (!slots.containsKey('weld') && modules is RecordModuleContext) {
      final record = (modules as RecordModuleContext).selectedRecordId(toolId);
      if (record != null) slots['record_id'] = record;
    }
    return SkillMatch(this, .99, slots: slots, utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final s = <String, Object?>{};
    final note = RegExp(r'\b(?:uwaga|notatka|note)\s*:', caseSensitive: false)
        .firstMatch(u.raw);
    if (note != null) {
      s['note'] = u.raw.substring(note.end).trim();
      u = u.withRaw(u.raw.substring(0, note.start));
    }
    final temps = _temperature.allMatches(u.raw).toList();
    if (temps.isNotEmpty) {
      final t = temps.first;
      var value = double.tryParse(t[1]!.replaceAll(',', '.')) ?? double.nan;
      if (RegExp(r'(?:minus|\u2212)\s*$', caseSensitive: false)
          .hasMatch(u.raw.substring(0, t.start))) {
        value = -value.abs();
      }
      if (temps.length != 1 ||
          RegExp(r'\d[.,]?\s+$').hasMatch(u.raw.substring(0, t.start))) {
        value = double.nan;
      }
      s['temperature'] = value;
      s['unit'] = t[2]!.toLowerCase().contains('f') ? 'f' : 'c';
    }
    final passes = _pass
        .allMatches(u.raw.replaceAll('ś', 's').replaceAll('Ś', 'S'))
        .toList();
    if (passes.isNotEmpty) {
      s['pass'] = passes.length == 1
          ? double.tryParse(passes.single[1]!.replaceAll(',', '.'))
          : double.nan;
    }
    if (temps.isEmpty) {
      final spokenTemps = <(double, String)>[];
      for (var i = 0; i + 1 < u.items.length; i++) {
        if (!u.items[i].isNumber) continue;
        var j = i + 1;
        if (const ['stopni', 'stopnie', 'degrees', 'degree']
                .contains(u.items[j].word) &&
            j + 1 < u.items.length) {
          j++;
        }
        final word = u.items[j].word;
        final unit = const ['c', 'celsius', 'celsjusza'].contains(word)
            ? 'c'
            : const ['f', 'fahrenheit', 'fahrenheita'].contains(word)
                ? 'f'
                : null;
        if (unit != null) {
          spokenTemps.add((
            i > 0 && u.items[i - 1].isNumber
                ? double.nan
                : signedQuantity(u, i),
            unit
          ));
        }
      }
      if (spokenTemps.isNotEmpty) {
        s['temperature'] =
            spokenTemps.length == 1 ? spokenTemps.single.$1 : double.nan;
        s['unit'] = spokenTemps.first.$2;
      }
    }
    if (passes.isEmpty) {
      final spokenPasses = <double>[];
      for (var i = 0; i + 1 < u.items.length; i++) {
        if (!u.items[i].word.startsWith('scieg') &&
            !const ['pass', 'run'].contains(u.items[i].word)) {
          continue;
        }
        var j = i + 1;
        if (const ['numer', 'nr', 'number'].contains(u.items[j].word) &&
            j + 1 < u.items.length) {
          j++;
        }
        if (u.items[j].isNumber) {
          spokenPasses.add(u.items[j].fraction ||
                  (j + 1 < u.items.length && u.items[j + 1].isNumber)
              ? double.nan
              : signedQuantity(u, j));
        }
      }
      if (spokenPasses.isNotEmpty) {
        s['pass'] = spokenPasses.length == 1 ? spokenPasses.single : double.nan;
      }
    }
    final welds = _weld.allMatches(u.raw).toList();
    if (welds.isNotEmpty) {
      s['weld'] = welds.length == 1 ? welds.single[1]! : '';
      s['record_id'] = null;
    }
    final methods = <String>{};
    if (u.hasStem(const ['kontaktow', 'contact']) ||
        u.hasAny(const ['termopara', 'thermocouple'])) {
      methods.add('contact');
    }
    if (u.hasStem(const ['pirometr', 'pyromet', 'infrared'])) {
      methods.add('pyrometer');
    }
    if (u.hasStem(const ['kredk', 'crayon', 'tempilstik'])) {
      methods.add('crayon');
    }
    if (methods.isNotEmpty) {
      s['method'] = methods.length == 1 ? methods.single : '';
      s['bound'] = null;
    }
    final below = u.hasAny(const [
      'nie stopila sie',
      'nie stopiła się',
      'nie stopiona',
      'did not melt',
      'not melted'
    ]);
    final positiveText = u.folded.replaceAll(
        RegExp(r'nie stopila sie|nie stopiona|did not melt|not melted'), ' ');
    final melted =
        u.withRaw(positiveText).hasAny(const ['stopila sie', 'melted']);
    if (below || melted) {
      s['bound'] = below && melted
          ? null
          : below
              ? 'below'
              : 'atLeast';
    }
    if (u.hasAny(const ['teraz', 'now'])) {
      s['at'] = ctx.now().millisecondsSinceEpoch;
    }
    final times = _dateTime.allMatches(u.raw).toList();
    if (times.isNotEmpty) {
      final raw = '${times.first[1]}T${times.first[2]}:00';
      final date = DateTime.tryParse(raw);
      final valid = times.length == 1 &&
          date != null &&
          '${interpassDate(date)}T${interpassTime(date)}:00' == raw;
      s['at'] = valid ? date.millisecondsSinceEpoch : null;
    }
    return s;
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = slotsFrom(u, ctx);
    if (slot == 'record_id') {
      final choice =
          RegExp(r'^wybierz ([a-zA-Z0-9_-]+)$').firstMatch(u.raw.trim());
      if (choice != null) s['record_id'] = choice[1];
    }
    if (slot == 'weld' &&
        s.isEmpty &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9_./-]*$').hasMatch(u.raw.trim())) {
      s['weld'] = u.raw.trim();
    }
    if (slot == 'pass' && s.isEmpty) {
      s['pass'] = double.tryParse(u.raw.trim().replaceAll(',', '.'));
    }
    return s.containsKey(slot) ? s : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    AskResult ask(String slot, String pl, String en) =>
        AskResult(slot, AssistantText(pl, en), partial: m);
    final note = s['note'];
    if (note != null && (note is! String || note.length > 1000)) {
      return const FailedResult(AssistantText(
          'Notatka może mieć maksymalnie 1000 znaków.',
          'The note can contain up to 1000 characters.'));
    }
    final value = s['temperature'];
    final unit = InterpassUnit.byName(s['unit']);
    if (value is! num ||
        unit == null ||
        !value.isFinite ||
        !InterpassTemp.entered(value.toDouble(), unit).valid) {
      return ask(
          'temperature',
          'Podaj zmierzoną temperaturę z jednostką, np. 120 C albo 250 F.',
          'Give the measured temperature and unit, e.g. 120 C or 250 F.');
    }
    final pass = s['pass'];
    if (pass is! num ||
        !pass.isFinite ||
        pass != pass.roundToDouble() ||
        pass < 1 ||
        pass > kInterpassMaxPass) {
      return ask(
          'pass',
          'Przed którym ściegiem wykonano pomiar? Podaj numer ściegu.',
          'Before which pass was the reading taken? Give the pass number.');
    }
    final method = InterpassMethod.byName(s['method']);
    if (method == null) {
      return AskResult(
          'method',
          const AssistantText(
              'Czym wykonano pomiar: termometrem kontaktowym, pirometrem czy kredką?',
              'How was it measured: contact thermometer, pyrometer or crayon?'),
          partial: m,
          choices: const [
            FollowUp(
                AssistantText('Termometr kontaktowy', 'Contact thermometer'),
                'contact thermometer'),
            FollowUp(AssistantText('Pirometr', 'Pyrometer'), 'pyrometer'),
            FollowUp(AssistantText('Kredka', 'Crayon'), 'crayon')
          ]);
    }
    final bound = method == InterpassMethod.crayon
        ? InterpassBound.byName(s['bound'])
        : InterpassBound.exact;
    if (bound == null ||
        (method == InterpassMethod.crayon && bound == InterpassBound.exact)) {
      return AskResult(
          'bound',
          const AssistantText(
              'Czy ślad kredki stopił się? Podana temperatura jest progiem kredki.',
              'Did the crayon mark melt? The temperature is the crayon rating.'),
          partial: m,
          choices: const [
            FollowUp(AssistantText('Stopiła się', 'Melted'), 'melted'),
            FollowUp(
                AssistantText('Nie stopiła się', 'Did not melt'), 'not melted')
          ]);
    }
    final at = s['at'];
    if (at is! int ||
        interpassAtInFuture(
            DateTime.fromMillisecondsSinceEpoch(at), ctx.now())) {
      return ask(
          'at',
          'Kiedy wykonano pomiar? Powiedz „teraz” albo podaj datę i godzinę: RRRR-MM-DD GG:MM.',
          'When was it measured? Say “now” or give the date and time: YYYY-MM-DD HH:MM.');
    }
    String? recordId = s['record_id'] as String?;
    final explicitWeld = (s['weld'] as String?)?.trim();
    final modules = ctx.modules;
    if (recordId == null &&
        explicitWeld == null &&
        modules is RecordModuleContext) {
      recordId = (modules as RecordModuleContext).selectedRecordId(toolId);
    }
    if (recordId == null && (explicitWeld == null || explicitWeld.isEmpty)) {
      return ask(
          'weld',
          'Której spoiny dotyczy pomiar? Podaj numer albo otwórz jej rejestr temperatury.',
          'Which weld is this for? Give its number or open its temperature record.');
    }
    InterpassLoad load;
    try {
      load = await store.load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać rejestru temperatury. Spróbuj ponownie.',
          'Could not read the temperature log. Try again.'));
    }
    if (load.corrupt) {
      return const FailedResult(AssistantText(
          'Rejestr temperatury zawiera uszkodzone dane. Sprawdź go w module przed dopisaniem pomiaru.',
          'The temperature log contains damaged data. Review it in the module before adding a reading.'));
    }
    final found = load.welds
        .where((w) => recordId != null
            ? w.id == recordId
            : w.weldNo.trim().toLowerCase() == explicitWeld!.toLowerCase())
        .toList();
    if (found.isEmpty) {
      return const FailedResult(AssistantText(
          'Nie znaleziono tej spoiny w rejestrze temperatury. Najpierw utwórz jej kartę w module.',
          'This weld was not found in the temperature log. Create its record in the module first.'));
    }
    if (found.length != 1) {
      return AskResult(
          'record_id',
          const AssistantText(
              'Kilka kart ma ten numer spoiny. Wybierz właściwą.',
              'Several records have this weld number. Choose the correct one.'),
          partial: m,
          choices: [
            for (final w in found)
              FollowUp(
                  AssistantText.same(
                      '${w.weldNo} · ${w.description} · ${w.wpsRef}'),
                  'wybierz ${w.id}')
          ]);
    }
    final before = found.single;
    if (before.lostReadings != 0) {
      return const FailedResult(AssistantText(
          'Ta spoina ma nieodczytane pomiary. Sprawdź brakujące dane w module.',
          'This weld has unreadable readings. Review the missing data in the module.'));
    }
    if (before.passCount != null && pass > before.passCount!) {
      return ask(
          'pass',
          'Numer ściegu przekracza zapisaną liczbę ściegów tej spoiny. Podaj właściwy numer.',
          'The pass number exceeds this weld’s recorded pass count. Give the correct number.');
    }
    final temp = InterpassTemp.entered(value.toDouble(), unit);
    final preview = InterpassReading(
        pass: pass.toInt(),
        temp: temp,
        bound: bound,
        method: method,
        at: at,
        recordedAt: ctx.now().millisecondsSinceEpoch,
        note: note as String? ?? '');
    final en = ctx.lang.name == 'en';
    final summary = AssistantAnswer(
        text: const AssistantText(
            'Dopiszę podany pomiar. Nie zmienię limitów WPS ani wcześniejszych pomiarów.',
            'I will add the supplied reading, preserving WPS limits and previous readings.'),
        lines: [
          AnswerLine(const AssistantText('Spoina', 'Weld'),
              '${before.weldNo} · ${before.description}'),
          AnswerLine(const AssistantText('Przed ściegiem', 'Before pass'),
              '${pass.toInt()}'),
          AnswerLine(const AssistantText('Odczyt', 'Reading'),
              interpassReadingValue(preview, unit, en: en)),
          AnswerLine(
              const AssistantText('Metoda', 'Method'), method.label(en: en)),
          if (preview.note.isNotEmpty)
            AnswerLine(const AssistantText('Notatka', 'Note'), preview.note),
          AnswerLine(const AssistantText('Czas pomiaru', 'Measurement time'),
              interpassDateTime(at)),
          AnswerLine(
              const AssistantText('WPS', 'WPS'),
              before.wpsRef.isEmpty
                  ? (en ? 'Not entered' : 'Nie wpisano')
                  : before.wpsRef),
          AnswerLine(
              const AssistantText('Ocena względem zapisanych limitów',
                  'Assessment against recorded limits'),
              interpassCheckLabel(interpassCheck(preview, before.limits),
                  en: en)),
        ]);
    final historyId = 'interpass.reading:${_newId()}';
    return ConfirmResult(summary, () async {
      final now = ctx.now();
      if (interpassAtInFuture(DateTime.fromMillisecondsSinceEpoch(at), now)) {
        throw StateError('Measurement time is in the future');
      }
      final reading = InterpassReading(
          pass: preview.pass,
          temp: temp,
          bound: bound,
          method: method,
          at: at,
          recordedAt: now.millisecondsSinceEpoch,
          note: preview.note);
      final after = before
          .addReading(reading)
          .copyWith(updatedAt: now.millisecondsSinceEpoch);
      if (!await store.replaceIfUnchanged(before, after)) {
        throw StateError('The weld changed after the preview');
      }
      await AssistantHistoryStore.instance.add(AssistantHistoryEntry(
          id: historyId,
          kind: id,
          summary:
              '${before.weldNo} · ${reading.pass} · ${interpassReadingValue(reading, unit, en: en)}',
          recordId: before.id,
          at: now,
          byVoice:
              s['origin_voice'] == true || (m.utterance?.byVoice ?? false)));
      return () async {
        if (!await store.replaceIfUnchanged(after, before)) {
          throw StateError('The reading was changed after confirmation');
        }
        await AssistantHistoryStore.instance.markUndone(historyId);
      };
    }, show: ShowInModule(toolId, {'weld_id': before.id}));
  }
}
