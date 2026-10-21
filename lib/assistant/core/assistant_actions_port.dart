// Zapisy, które asystent może wykonać PO potwierdzeniu: parametr spawania
// i wpis do dziennika spoin. To tylko interfejs — implementację
// (`AssistantActions`, zadanie 1.0: logika 1:1 z `_save`, `_prepareJournal`,
// `_saveJournal` w AiChatScreen) podłącza sesja asystenta. W testach atrapa.
//
// Zasada (spec §3.4): podsumowanie → potwierdzenie → zapis → Cofnij.
// Metody „summary/prepare" NIC nie zapisują; „save" zapisuje i zwraca Cofnij.

import '../../i18n/app_language.dart';
import '../assistant_validator.dart' show WeldJournalDraft, WeldParamDraft;
import 'skill.dart';

abstract class AssistantActionsPort {
  /// Podsumowanie parametru spawania do pokazania przed „Zapisz" (bez I/O).
  AssistantAnswer weldParamSummary(WeldParamDraft draft,
      {required bool byVoice, required AppLanguage lang});

  /// Zapis parametru spawania („Parametry — rury" → Moje) i wpis w historii
  /// asystenta. Zwraca Cofnij (usunięcie rekordu). Rzuca, gdy zapis się nie
  /// udał — wtedy nic nie zostało zmienione.
  Future<UndoAction?> saveWeldParam(WeldParamDraft draft,
      {required bool byVoice, required AppLanguage lang});

  /// Przygotowanie wpisu do dziennika: odczyt dziennika i stempla spawacza,
  /// ujednolicenie nazwy projektu, sprawdzenie, czy numer spoiny jest wolny.
  /// Nic nie zapisuje.
  Future<JournalPreparation> prepareJournal(WeldJournalDraft draft,
      {required bool byVoice, required AppLanguage lang});

  /// Zapis przygotowanego wpisu. Zwraca Cofnij (wpis oznaczony jako
  /// usunięty — dziennik to dowód, nie kasujemy). Rzuca przy błędzie zapisu.
  Future<UndoAction?> saveJournal(PreparedJournal prepared,
      {required bool byVoice, required AppLanguage lang});
}

/// Wynik [AssistantActionsPort.prepareJournal].
sealed class JournalPreparation {
  const JournalPreparation();
}

/// Wpis gotowy do potwierdzenia.
class PreparedJournal extends JournalPreparation {
  const PreparedJournal(
      {required this.draft, required this.summary, this.payload});

  /// Szkic z kanoniczną nazwą projektu (jak w dzienniku).
  final WeldJournalDraft draft;
  final AssistantAnswer summary;

  /// Dane implementacji potrzebne do zapisu (rekord, stempel, czas).
  final Object? payload;
}

/// Numer spoiny jest już zajęty w tym projekcie — asystent pyta o inny,
/// projekt i WPS zostają.
class JournalWeldNoTaken extends JournalPreparation {
  const JournalWeldNoTaken(
      {required this.weldNo, required this.project, this.wps});
  final String weldNo;
  final String project;
  final String? wps;
}

/// Nie da się przygotować wpisu (np. błąd odczytu dziennika). Nic nie
/// zapisano.
class JournalUnavailable extends JournalPreparation {
  const JournalUnavailable(this.message);
  final AssistantText message;
}

/// Optional synchronous context; no file/DB access during slot matching.
abstract interface class LastJournalProjectPort {
  String get lastJournalProject;
}
