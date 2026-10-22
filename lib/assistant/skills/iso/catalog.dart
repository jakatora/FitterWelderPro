import '../../core/skill.dart';
import 'iso_draw_skill.dart';
import 'iso_dimension_skill.dart';
import 'iso_name_skill.dart';
import 'iso_gap_skill.dart';

List<AssistantSkill> isoSkills(IsoDrawingPort port) => [
      IsoDrawSkill(port),
      IsoDimensionSkill(port),
      IsoNameSkill(port),
      IsoGapSkill(port)
    ];
