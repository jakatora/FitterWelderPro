import '../../core/skill.dart';
import 'pipe_slope_skill.dart';
import 'rolling_offset_skill.dart';
import 'thermal_expansion_skill.dart';
import 'bevel_geometry_skill.dart';
import 'slope_cut_skill.dart';
import 'reducer_cut_skill.dart';
import 'elbow_cut_skill.dart';
import 'elbow_rotation_skill.dart';

List<AssistantSkill> fitterRoutesSkills() => [
      PipeSlopeSkill(),
      RollingOffsetSkill(),
      ThermalExpansionSkill(),
      BevelGeometrySkill(),
      SlopeCutSkill(),
      ReducerCutSkill(),
      ElbowCutSkill(),
      ElbowRotationSkill()
    ];
