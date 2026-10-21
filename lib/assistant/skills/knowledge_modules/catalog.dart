import '../../core/skill.dart';
import 'defects_causes_skill.dart';
import 'iso5817_limit_skill.dart';
import 'electrodes_exposure_skill.dart';

List<AssistantSkill> knowledgeModuleSkills() =>
    [DefectsCausesSkill(), Iso5817LimitSkill(), ElectrodesExposureSkill()];
