import '../../core/skill.dart';
import 'pipe_slope_skill.dart';
import 'rolling_offset_skill.dart';
import 'thermal_expansion_skill.dart';
import 'bevel_geometry_skill.dart';
import 'slope_cut_skill.dart';
import 'reducer_cut_skill.dart';
import 'elbow_cut_skill.dart';
import 'elbow_rotation_skill.dart';
import 'insert_length_skill.dart';
import 'mitre_bend_skill.dart';
import 'tube_bending_skill.dart';
import 'pipe_route_skill.dart';
import 'cone_layout_skill.dart';
import 'transition_layout_skill.dart';
import 'development_height_skill.dart';
import 'development_summary_skill.dart';
import 'development_export_skill.dart';

List<AssistantSkill> fitterRoutesSkills() => [
      PipeSlopeSkill(),
      RollingOffsetSkill(),
      ThermalExpansionSkill(),
      BevelGeometrySkill(),
      SlopeCutSkill(),
      ReducerCutSkill(),
      ElbowCutSkill(),
      ElbowRotationSkill(),
      InsertLengthSkill(),
      MitreBendSkill(),
      TubeBendingSkill(),
      PipeRouteSkill(),
      ConeLayoutSkill(),
      EccentricConeSkill(),
      TransitionLayoutSkill(),
      DevelopmentHeightSkill(),
      DevelopmentSummarySkill(),
      DevelopmentExportSkill()
    ];
