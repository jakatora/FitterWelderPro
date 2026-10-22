import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/component_find_skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/cutlist_summary_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';

Project project(String id, String name) => Project(
    id: id,
    name: name,
    materialGroup: 'SS',
    diameterMm: 60.3,
    wallThicknessMm: 2,
    currentDiameterMm: 60.3,
    stockLengthMm: 6000,
    sawKerfMm: 2,
    gapMm: 2,
    createdAt: 1,
    updatedAt: 1);

Segment seg(String id, String projectId, double cut) => Segment(
    id: id,
    projectId: projectId,
    seqNo: 1,
    diameterMm: 60.3,
    wallThicknessMm: 2,
    startKind: 'END',
    startLibraryId: null,
    startValueMm: 0,
    endKind: 'END',
    endLibraryId: null,
    endValueMm: 0,
    isoRef: 'END',
    isoExpr: '',
    isoMm: cut,
    cutMm: cut,
    createdAt: 1,
    updatedAt: 1);

LibraryComponent comp(String id, String type, double d, {double? axis}) =>
    LibraryComponent(
        id: id,
        materialGroup: 'SS',
        type: type,
        diameterMm: d,
        wallThicknessMm: 2,
        axisMm: axis,
        lengthMm: null,
        measurementMode: null,
        diameterOutMm: null,
        createdAt: 1,
        updatedAt: 1);

AssistantContext get _ctx =>
    AssistantContext(lang: AppLanguage.pl, modules: const FixedModuleContext());

Future<SkillResult> run(AssistantSkill s, String text) async {
  final m = s.match(Utterance(text, lang: AppLanguage.pl), _ctx);
  expect(m, isNotNull, reason: text);
  return s.run(m!, _ctx);
}

void main() {
  test('cut list: latest project by default, named project on request',
      () async {
    final s = CutListSummarySkill(
        projects: () async => [project('p1', 'Alfa'), project('p2', 'Beta')],
        segments: (id) async => id == 'p1'
            ? [seg('a', 'p1', 1200), seg('b', 'p1', 800)]
            : [seg('c', 'p2', 500)]);
    final latest = await run(s, 'Ile odcinków do cięcia') as AnswerResult;
    expect(latest.answer.text.pl, contains('„Alfa”: 2 odcinków, razem 2 m'));
    expect(latest.answer.text.pl, contains('najdłuższy 1200 mm'));
    final beta = await run(s, 'Lista cięć w projekcie Beta') as AnswerResult;
    expect(beta.answer.text.pl, contains('„Beta”: 1 odcinków'));
    expect(await run(s, 'lista cięć w projekcie Gamma'), isA<FailedResult>());
  });

  test('component library: type, DN and axis dimension', () async {
    final s = ComponentFindSkill(
        load: () async => [
              comp('1', 'ELB90', 114.3, axis: 152.4),
              comp('2', 'TEE', 60.3, axis: 64),
            ]);
    final elbow =
        await run(s, 'Znajdź w bibliotece kolano 90 DN100') as AnswerResult;
    expect(elbow.answer.text.pl, contains('kolano 90° SS 114,3 × 2, do osi 152,4 mm'));
    final none =
        await run(s, 'Czy mam w bibliotece redukcję 88,9 mm') as AnswerResult;
    expect(none.answer.text.pl, contains('Nie masz w bibliotece'));
  });
}
