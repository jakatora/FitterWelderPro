import '../../../database/weld_journal_dao.dart';
import '../../../domain/piecework/piecework.dart';
import '../../../domain/progress/progress_report.dart' show progressNum;
import '../../../domain/quotes/quote_calculator.dart' show formatPln;
import '../../../domain/weld_journal/weld_entry.dart';
import '../../../features/piecework/piecework_store.dart';
import '../../../services/welder_identity.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_guards.dart';

PieceworkPeriod? _period(Utterance u) {
  final f = u.folded;
  if (RegExp(r'\b(?:zeszl\w*|poprzedni\w*|ostatni\w*) miesiac|\blast month\b|\bprevious month\b')
      .hasMatch(f)) {
    return PieceworkPeriod.lastMonth;
  }
  if (RegExp(r'\b(?:dzis|dzisiaj|today)\b').hasMatch(f)) {
    return PieceworkPeriod.today;
  }
  if (RegExp(r'\btydzie\w*|\btygodni\w*|\bweek\b').hasMatch(f)) {
    return PieceworkPeriod.week;
  }
  if (RegExp(r'\bmiesiac\w*|\bmonth\b').hasMatch(f)) {
    return PieceworkPeriod.month;
  }
  return null;
}

Map<String, Object?> _slots(Utterance u) => {
      if (_period(u) case final p?) 'period': p.name,
      if (u.hasStem(const ['brygad', 'crew', 'zespol', 'ekip'])) 'crew': true,
    };

/// „Ile zarobiłem akordem” — dziennik spoin + zapisane stawki modułu „Akord”,
/// spawacz z tożsamości telefonu (albo cała brygada). Tylko odczyt.
class PieceworkEarningsSkill extends AssistantSkill {
  PieceworkEarningsSkill({
    Future<List<WeldEntry>> Function()? loadWelds,
    Future<String?> Function()? loadIdentity,
    PieceworkRatesStore store = const PieceworkRatesStore(),
    DateTime Function()? clock,
  })  : _loadWelds = loadWelds ?? (() => WeldJournalDao().listAll()),
        _loadIdentity = loadIdentity ??
            (() async => (await WelderIdentityService.instance.get())?.stamp),
        _store = store,
        _clock = clock ?? DateTime.now;
  final Future<List<WeldEntry>> Function() _loadWelds;
  final Future<String?> Function() _loadIdentity;
  final PieceworkRatesStore _store;
  final DateTime Function() _clock;

  @override
  String get id => 'piecework.earnings';
  @override
  String get toolId => 'piecework';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile zarobiłem akordem w tym miesiącu',
            'How much did I earn on piecework this month'),
        SkillExample('Akord za zeszły miesiąc', 'Piecework for last month'),
        SkillExample('Ile wyszło akordu w tym tygodniu',
            'How much piecework this week'),
        SkillExample('Akord brygady w tym miesiącu',
            'Crew piecework this month'),
        SkillExample('Ile mam akordu dzisiaj', 'How much piecework today'),
        SkillExample('Policz mój akord', 'Calculate my piecework'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz akord', routesTo: 'tool.open'),
        SkillRejection('do czego służy akord', routesTo: 'tool.explain'),
        SkillRejection('ile brać za godzinę'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        kOpenOrAboutStart.hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['akord', 'piecework'])) return null;
    return SkillMatch(this, .92, slots: _slots(u), utterance: u);
  }

  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      _slots(u);

  @override
  Map<String, Object?>? fillSlot(
          String slot, Utterance u, AssistantContext ctx) =>
      slot == 'period' && _period(u) != null ? {'period': _period(u)!.name} : null;

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final period = PieceworkPeriod.values
        .where((p) => p.name == m.slots['period'])
        .firstOrNull;
    if (period == null) {
      return AskResult(
          'period',
          const AssistantText(
              'Za jaki okres: dziś, ten tydzień, ten miesiąc czy poprzedni miesiąc?',
              'For which period: today, this week, this month or last month?'),
          partial: m);
    }
    final List<WeldEntry> all;
    try {
      all = (await _loadWelds()).where((e) => !e.isDeleted).toList();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać dziennika spoin.',
          'Could not read the weld journal.'));
    }
    final rates = (await _store.load()).rates;
    final crew = m.slots['crew'] == true;
    String? welder;
    if (!crew) {
      String? me;
      try {
        me = (await _loadIdentity())?.trim();
      } catch (_) {}
      welder = defaultPieceworkWelder(
          identityStamp: me == null || me.isEmpty ? null : me,
          stamps: pieceworkStamps(all));
    }
    final now = _clock();
    final r = computePiecework(
        entries: all,
        rates: rates,
        range: pieceworkRange(period, now),
        welder: welder,
        today: now);
    final en = ctx.lang.name == 'en';
    final who = welder == null
        ? (en ? 'crew' : 'brygada')
        : (en ? 'welder $welder' : 'spawacz $welder');
    final label = pieceworkPeriodLabel(period, en: en).toLowerCase();
    final fields = <String, Object?>{'period': period.name, 'crew': welder == null};
    if (r.isEmpty) {
      return AnswerResult(
          AssistantAnswer(
              text: AssistantText(
                  'Akord ($label, $who): brak spoin w dzienniku w tym okresie.',
                  'Piecework ($label, $who): no welds in the journal for this period.')),
          show: ShowInModule(toolId, fields));
    }
    final total = formatPln(r.totalGrosze);
    final perDay = r.perDayGrosze;
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Akord ($label, $who): $total za ${r.welds} spoin, ${progressNum(r.di, en: false)} DI, ${r.daysWorked} dni pracy${perDay == null ? '' : ', średnio ${formatPln(perDay)}/dzień'}. Stawki z modułu „Akord”; to wyliczenie z dziennika, nie rozliczenie pracodawcy.',
                'Piecework ($label, $who): $total for ${r.welds} welds, ${progressNum(r.di, en: true)} DI, ${r.daysWorked} working days${perDay == null ? '' : ', average ${formatPln(perDay)}/day'}. Rates from the Piecework module; this is a journal estimate, not the employer\'s settlement.')),
        show: ShowInModule(toolId, fields));
  }
}
