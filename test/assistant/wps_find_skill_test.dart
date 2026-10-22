import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/wps_find_skill.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/i18n/app_language.dart';

WpsRecord wps(String no, String processes, String group,
        {double? tMin, double? tMax}) =>
    WpsRecord(
        id: no,
        wpsNo: no,
        processes: processes,
        materialGroup: group,
        thicknessMinMm: tMin,
        thicknessMaxMm: tMax,
        createdAt: 1,
        updatedAt: 1);

void main() {
  final library = [
    wps('001', '141', '8.1', tMin: 1.5, tMax: 6),
    wps('002', '141/111', '1.1', tMin: 3, tMax: 24),
    wps('003', '135', '1.1', tMin: 6, tMax: 40),
  ];
  Future<SkillResult> say(String text, {List<WpsRecord>? data}) async {
    final s = WpsFindSkill(load: () async => data ?? library);
    final u = Utterance(text, lang: AppLanguage.pl);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final m = s.match(u, ctx);
    expect(m, isNotNull, reason: text);
    return s.run(m!, ctx);
  }

  test('process filter and thickness inside the WPS range', () async {
    final tig = await say('Znajdź WPS na 141') as AnswerResult;
    expect(tig.answer.text.pl, contains('Pasujące WPS (2)'));
    expect(tig.show!.fields, {'query': '141'});
    final eight = await say('Jaka WPS na TIG grubość 8 mm') as AnswerResult;
    expect(eight.answer.text.pl, contains('WPS 002'));
    expect(eight.answer.text.pl, isNot(contains('WPS 001')));
  });

  test('number and group; empty results said plainly', () async {
    final one = await say('Pokaż WPS 003') as AnswerResult;
    expect(one.answer.text.pl, contains('WPS 003'));
    final group = await say('Znajdź WPS 135 grupa 1.1') as AnswerResult;
    expect(group.answer.text.pl, contains('Pasujące WPS (1)'));
    final none = await say('znajdź WPS na 311') as AnswerResult;
    expect(none.answer.text.pl, contains('Nie masz WPS'));
    final empty = await say('pokaż moje WPS', data: const []) as AnswerResult;
    expect(empty.answer.text.pl, contains('pusta'));
  });

  test('adding a WPS is not a search', () {
    final s = WpsFindSkill(load: () async => library);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    expect(s.match(Utterance('dodaj nową WPS', lang: AppLanguage.pl), ctx),
        isNull);
  });
}
