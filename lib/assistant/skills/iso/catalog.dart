import '../../core/skill.dart';
import 'iso_draw_skill.dart';

List<AssistantSkill> isoSkills(IsoDrawingPort port) => [IsoDrawSkill(port)];
