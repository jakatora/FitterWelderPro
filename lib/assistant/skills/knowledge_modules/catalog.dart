import '../../core/skill.dart';
import 'defects_causes_skill.dart';
import 'iso5817_limit_skill.dart';
import 'electrodes_exposure_skill.dart';
import 'rigging_colour_skill.dart';
import 'grinding_stripe_skill.dart';
import 'filler_pick_skill.dart';
import 'fume_oel_skill.dart';
import 'qualification_range_skill.dart';
import 'weld_symbol_skill.dart';
import 'exam_question_skill.dart';
import 'ferrite_range_skill.dart';
import 'flange_alignment_skill.dart';

List<AssistantSkill> knowledgeModuleSkills() => [
      DefectsCausesSkill(),
      Iso5817LimitSkill(),
      ElectrodesExposureSkill(),
      RiggingColourSkill(),
      GrindingStripeSkill(),
      FillerPickSkill(),
      FumeOelSkill(),
      QualificationRangeSkill(),
      WeldSymbolSkill(),
      ExamQuestionSkill(),
      FerriteRangeSkill(),
      FlangeAlignmentSkill()
    ];
