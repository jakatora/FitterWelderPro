import 'welder_gas_skills.dart';
import 'hardness_convert_skill.dart';
import '../../core/skill.dart';
import 'heat_input_skill.dart';
import 'shade_number_skill.dart';
import 'cooling_time_skill.dart';
import 'preheat_ce_skill.dart';
import 'power_duty_skill.dart';
import 'power_cable_skill.dart';
import 'tungsten_pick_skill.dart';
import 'fillet_strength_skill.dart';
import 'distortion_skill.dart';
import 'weather_check_skill.dart';
import 'pwht_plan_skill.dart';

List<AssistantSkill> welderCalcSkills() => [
      GasConsumptionSkill(),
      CylinderRemainingSkill(),
      PurgeEstimateSkill(),
      HardnessConvertSkill(),
      HeatInputSkill(),
      ShadeNumberSkill(),
      CoolingTimeSkill(),
      PreheatCeSkill(),
      PowerDutySkill(),
      PowerCableSkill(),
      TungstenPickSkill(),
      FilletStrengthSkill(),
      DistortionShrinkageSkill(),
      WeatherCheckSkill(),
      PwhtPlanSkill(),
    ];
