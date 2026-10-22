import '../../core/skill.dart';
import 'bolt_torque_skill.dart';
import 'glossary_term_skill.dart';
import 'timer_skill.dart';
import 'tandem_tig_skill.dart';
import 'bolt_kit_skill.dart';
import '../../../services/weld_timer_service.dart';

List<AssistantSkill> welderMiscSkills({WeldTimerService Function()? timer}) => [
      BoltTorqueSkill(),
      GlossaryTermSkill(),
      TandemTigSkill(),
      BoltKitSkill(),
      for (final action in ['start', 'stop', 'cool', 'set'])
        TimerSkill(action, timer: timer)
    ];
