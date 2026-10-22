import '../../../database/coupon_dao.dart';
import '../../../domain/weld_journal/coupon_entry.dart';
import '../../core/skill.dart';
import '../core/explain_tool_skill.dart' show explainedTool;
import '../core/skill_words.dart';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Stan logu kuponów konta: dziś, do oceny, ostatni kupon. Tylko odczyt.
class CouponsStatusSkill extends AssistantSkill {
  CouponsStatusSkill({
    Future<List<CouponEntry>> Function()? load,
    DateTime Function()? clock,
  })  : _load = load ?? (() => CouponDao().listAll()),
        _clock = clock ?? DateTime.now;
  final Future<List<CouponEntry>> Function() _load;
  final DateTime Function() _clock;

  @override
  String get id => 'coupons.status';
  @override
  String get toolId => 'coupon_log';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile kuponów dzisiaj', 'How many coupons today'),
        SkillExample('Jaki był ostatni kupon', 'What was the last coupon'),
        SkillExample('Ile kuponów czeka na ocenę', 'How many coupons await assessment'),
        SkillExample('Stan logu kuponów', 'Coupon log status'),
        SkillExample('Czy ostatni kupon przeszedł', 'Did the last coupon pass'),
        SkillExample('Pokaż kupony', 'Show coupons'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz log kuponów', routesTo: 'tool.open'),
        SkillRejection('do czego służy log kuponów', routesTo: 'tool.explain'),
        SkillRejection('ile spoin zrobiłem dziś'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (explainedTool(u) != null ||
        RegExp(r'^(?:otworz|open|do czego)\b').hasMatch(u.folded)) {
      return null;
    }
    if (!u.hasStem(const ['kupon', 'coupon'])) return null;
    if (u.hasStem(const ['dodaj', 'zapisz', 'nowy', 'add', 'new', 'usun', 'delete'])) {
      return null;
    }
    return SkillMatch(this, .92, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final List<CouponEntry> all;
    try {
      all = (await _load()).where((c) => !c.isDeleted).toList();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać logu kuponów.', 'Could not read the coupon log.'));
    }
    if (all.isEmpty) {
      return const AnswerResult(
          AssistantAnswer(
              text: AssistantText('Log kuponów jest pusty.', 'The coupon log is empty.')),
          show: ShowInModule('coupon_log'));
    }
    final today = _day(_clock());
    final todays = all.where((c) => c.date == today).length;
    final pending = all.where((c) => c.isPending).length;
    final sorted = [...all]..sort((a, b) => b.date.compareTo(a.date));
    final last = sorted.first;
    String result(bool en) => last.isOk
        ? 'OK'
        : last.isRejected
            ? (en ? 'REJECTED' : 'ODRZUCONY')
            : (en ? 'awaiting assessment' : 'do oceny');
    final extra = [
      if (last.o2Ppm != null) 'O₂ ${fmt(last.o2Ppm!, ctx.lang)} ppm',
      if (last.heatTint != null) '${ctx.lang.name == 'en' ? 'tint' : 'przebarwienie'} ${last.heatTint}',
    ].join(', ');
    final who = [last.welder, last.machine].where((s) => s.trim().isNotEmpty).join(', ');
    return AnswerResult(
        AssistantAnswer(
            text: AssistantText(
                'Dziś kuponów: $todays, do oceny: $pending (wszystkich ${all.length}). Ostatni: ${last.date}${who.isEmpty ? '' : ' ($who)'} — ${result(false)}${extra.isEmpty ? '' : ', $extra'}.',
                'Coupons today: $todays, awaiting assessment: $pending (all ${all.length}). Last: ${last.date}${who.isEmpty ? '' : ' ($who)'} — ${result(true)}${extra.isEmpty ? '' : ', $extra'}.')),
        show: ShowInModule(toolId));
  }
}
