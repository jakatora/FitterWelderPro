import '../../core/skill.dart';
import 'pipe_slope_skill.dart';
import 'rolling_offset_skill.dart';

List<AssistantSkill> fitterRoutesSkills() =>
    [PipeSlopeSkill(), RollingOffsetSkill()];
