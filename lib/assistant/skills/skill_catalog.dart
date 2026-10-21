import 'iso/catalog.dart';
import 'iso/iso_draw_skill.dart';
import 'records/quote_new_skill.dart';
import 'records/interpass_reading_skill.dart';
// Katalog wszystkich umiejętności asystenta = suma katalogów grup.
//
// Każda grupa rejestruje się we własnym `skills/<grupa>/catalog.dart`;
// koordynator dopisuje ją TUTAJ po scaleniu i uruchamia globalny test
// routera (test/assistant/router_corpus_test.dart), który łapie kolizje
// zamiarów między grupami.

import '../core/assistant_actions_port.dart';
import '../core/skill.dart';
import '../../services/weld_timer_service.dart';
import 'core/catalog.dart';
import 'core/account_navigation_skill.dart';
import 'fitter_routes/catalog.dart';
import 'fitter_tables/catalog.dart';
import 'welder_calc/catalog.dart';
import 'welder_misc/catalog.dart';
import 'knowledge_modules/catalog.dart';
import 'own_data/instruments_due_skill.dart';
import 'own_data/certificates_expiry_skill.dart';
import 'own_data/journal_last_skill.dart';
import 'own_data/electrodes_status_skill.dart';
import 'own_data/progress_today_skill.dart';
import 'records/hot_work_prepare_skill.dart';
import 'records/confined_space_prepare_skill.dart';

/// Pełny katalog. [actions] — zapisy (bez nich brak umiejętności `legacy.*`).
List<AssistantSkill> buildSkillCatalog(
    {AssistantActionsPort? actions,
    WeldTimerService Function()? timer,
    InstrumentReader? instruments,
    CertificateReader? certificates,
    JournalReader? journal,
    ElectrodeReader? electrodes,
    IsoDrawingPort? iso}) {
  final all = <AssistantSkill>[];
  Iterable<AssistantSkill> catalog() => all;
  all.addAll(coreSkills(actions: actions, catalog: catalog));
  all.addAll(welderCalcSkills());
  all.addAll(welderMiscSkills(timer: timer));
  all.add(AccountNavigationSkill());
  all.addAll(fitterRoutesSkills());
  all.addAll(fitterTablesSkills());
  // Kolejne grupy (koordynator):
  all.addAll(knowledgeModuleSkills());
  all.add(InstrumentsDueSkill(load: instruments));
  all.add(CertificatesExpirySkill(load: certificates));
  all.add(JournalLastSkill(load: journal));
  all.add(ElectrodesStatusSkill(load: electrodes));
  all.add(ProgressTodaySkill(load: journal));
  all.add(QuoteNewSkill());
  all.add(InterpassReadingSkill());
  all.add(HotWorkPrepareSkill());
  all.add(ConfinedSpacePrepareSkill());
  if (iso != null) all.addAll(isoSkills(iso));
  return List.unmodifiable(all);
}
