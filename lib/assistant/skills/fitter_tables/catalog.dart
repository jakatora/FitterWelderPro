import '../../core/skill.dart';
import 'units_convert_skill.dart';
import 'pipe_weight_skill.dart';
import 'elbow_takeout_skill.dart';

List<AssistantSkill> fitterTablesSkills() =>
    [UnitsConvertSkill(), PipeWeightSkill(), ElbowTakeoutSkill()];
