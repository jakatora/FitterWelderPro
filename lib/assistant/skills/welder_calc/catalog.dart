import 'hardness_convert_skill.dart';
import '../../core/skill.dart';
import 'heat_input_skill.dart';
import 'shade_number_skill.dart';
import 'cooling_time_skill.dart';
import 'preheat_ce_skill.dart';
import 'power_duty_skill.dart';
import 'power_cable_skill.dart';
import 'tungsten_pick_skill.dart';

List<AssistantSkill> welderCalcSkills() => [
      HardnessConvertSkill(),
      HeatInputSkill(),
      ShadeNumberSkill(),
      CoolingTimeSkill(),
      PreheatCeSkill(),
      PowerDutySkill(),
      PowerCableSkill(),
      TungstenPickSkill(),
    ];
