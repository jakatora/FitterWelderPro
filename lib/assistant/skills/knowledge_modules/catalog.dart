import '../../core/skill.dart';
import 'defects_causes_skill.dart';
import 'iso5817_limit_skill.dart';
import 'electrodes_exposure_skill.dart';
import 'rigging_colour_skill.dart';
import 'grinding_stripe_skill.dart';

List<AssistantSkill> knowledgeModuleSkills() => [
      DefectsCausesSkill(),
      Iso5817LimitSkill(),
      ElectrodesExposureSkill(),
      RiggingColourSkill(),
      GrindingStripeSkill()
    ];
