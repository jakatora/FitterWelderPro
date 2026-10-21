import '../models/weld_param.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/weld_param_dao.dart';
import '../database/weld_journal_dao.dart';
import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_defaults.dart';
import '../i18n/app_language.dart';
import 'assistant_history.dart';
import 'assistant_intents.dart';
import 'assistant_local_ops.dart';
import 'assistant_validator.dart';
import 'core/assistant_actions_port.dart';
import 'core/skill.dart';

/// Native persistence shared by local dialogs and AI proposals. Preparing a
/// summary never writes a record. The caller still owns actual confirmation.
class AssistantActions extends AssistantActionsPort
    implements LastJournalProjectPort {
  AssistantActions(
      {WeldParamDao? parameters,
      WeldJournalDao? journal,
      AssistantHistoryStore? history,
      DateTime Function()? now,
      Future<String> Function()? stamp,
      String Function()? projectContext,
      void Function(String)? onProjectSaved})
      : parameters = parameters ?? WeldParamDao(),
        journal = journal ?? WeldJournalDao(),
        history = history ?? AssistantHistoryStore.instance,
        now = now ?? DateTime.now,
        stamp = stamp ?? _emptyStamp,
        _projectContext = projectContext,
        _onProjectSaved = onProjectSaved;
  static Future<String> _emptyStamp() async => '';
  final WeldParamDao parameters;
  final WeldJournalDao journal;
  final AssistantHistoryStore history;
  final DateTime Function() now;
  final Future<String> Function() stamp;
  final String Function()? _projectContext;
  final void Function(String)? _onProjectSaved;
  final _paramSaves = Expando<Future<UndoAction?>>();
  final _parameterSnapshots = Expando<_ParameterSnapshot>();
  final _journalSaves = Expando<Future<UndoAction?>>();
  String _lastProject = '';
  @override
  String get lastJournalProject => _projectContext?.call() ?? _lastProject;
  static const _uuid = Uuid();

  static Map<String, Object?> _fields(WeldParamDraft d) => {
        'material': d.material,
        'process': d.process,
        'filler': d.filler,
        'wall_mm': d.wallMm,
        'current_a': d.currentA,
        'diameter_mm': d.diameterMm,
        'position': d.position,
        'gas': d.gas,
        'flow_lpm': d.flowLpm,
        'electrode_mm': d.electrodeMm,
        'joint': d.joint,
        'purge_lpm': d.purgeLpm
      };
  static void _validate(WeldParamDraft d) {
    if (validateAssistantProposal(kIntentSaveWeldParameter, _fields(d))
        is! AssistantReadyToSave) {
      throw const FormatException('weld parameter');
    }
  }

  static String parameterSummary(WeldParamDraft d, AppLanguage lang) {
    final en = lang == AppLanguage.en;
    final process = d.process == 'MIG_MAG' ? 'MIG/MAG' : d.process;
    return [
      '$process ${d.filler ? (en ? 'with filler' : 'z drutem') : (en ? 'no filler' : 'bez drutu')}',
      d.material,
      't ${assistantNumber(d.wallMm, lang)} mm',
      '${assistantNumber(d.currentA, lang)} A',
      if (d.diameterMm != null) 'Ø ${assistantNumber(d.diameterMm!, lang)}'
    ].join(' · ');
  }

  @override
  AssistantAnswer weldParamSummary(WeldParamDraft d,
      {required bool byVoice, required AppLanguage lang}) {
    _validate(d);
    return AssistantAnswer(
        text: AssistantText(parameterSummary(d, AppLanguage.pl),
            parameterSummary(d, AppLanguage.en)),
        lines: [
          AnswerLine(const AssistantText('Materiał', 'Material'),
              assistantMaterialLabel(d.material, lang)),
          AnswerLine(const AssistantText('Metoda', 'Process'),
              assistantProcessLabel(d.process, lang)),
          AnswerLine(
              const AssistantText('Spoiwo', 'Filler'),
              d.filler
                  ? (lang == AppLanguage.pl ? 'z drutem' : 'with filler')
                  : (lang == AppLanguage.pl ? 'bez drutu' : 'no filler')),
          AnswerLine(const AssistantText('Ścianka', 'Wall'),
              '${assistantNumber(d.wallMm, lang)} mm'),
          AnswerLine(const AssistantText('Prąd', 'Current'),
              '${assistantNumber(d.currentA, lang)} A'),
          AnswerLine(
              const AssistantText('Średnica', 'Diameter'),
              d.diameterMm == null
                  ? (lang == AppLanguage.pl ? 'nie podano' : 'not given')
                  : '${assistantNumber(d.diameterMm!, lang)} mm'),
          if (d.position != null)
            AnswerLine(const AssistantText('Pozycja', 'Position'), d.position!),
          if (d.gas != null)
            AnswerLine(const AssistantText('Gaz', 'Gas'),
                assistantGasLabel(d.gas!, lang)),
          if (d.flowLpm != null)
            AnswerLine(const AssistantText('Przepływ gazu', 'Gas flow'),
                '${assistantNumber(d.flowLpm!, lang)} l/min'),
          if (d.electrodeMm != null)
            AnswerLine(
                const AssistantText('Drut / elektroda', 'Wire / electrode'),
                '${assistantNumber(d.electrodeMm!, lang)} mm'),
          if (d.purgeLpm != null)
            AnswerLine(const AssistantText('Formowanie', 'Purge'),
                '${assistantNumber(d.purgeLpm!, lang)} l/min'),
          if (d.joint != null)
            AnswerLine(const AssistantText('Złącze', 'Joint'),
                assistantJointLabel(d.joint!, lang)),
        ]);
  }

  @override
  Future<UndoAction?> saveWeldParam(WeldParamDraft d,
      {required bool byVoice, required AppLanguage lang}) {
    _validate(d);
    var snapshot = _parameterSnapshots[d];
    if (snapshot != null &&
        (snapshot.byVoice != byVoice || snapshot.lang != lang)) {
      throw const FormatException('parameter source changed');
    }
    if (snapshot == null) {
      final at = now();
      final record =
          d.toWeldParam(id: _uuid.v4(), at: at, byVoice: byVoice, lang: lang);
      snapshot = _ParameterSnapshot(
          record,
          AssistantHistoryEntry(
              id: _uuid.v4(),
              kind: kIntentSaveWeldParameter,
              summary: parameterSummary(d, lang),
              recordId: record.id,
              at: at,
              byVoice: byVoice),
          byVoice,
          lang);
      _parameterSnapshots[d] = snapshot;
    }
    final prior = _paramSaves[d];
    if (prior != null) return prior;
    final pending = _saveParameter(snapshot);
    _paramSaves[d] = pending;
    return pending.catchError((Object e, StackTrace st) {
      _paramSaves[d] = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<UndoAction?> _saveParameter(_ParameterSnapshot snapshot) async {
    final record = snapshot.record, entry = snapshot.history;
    if (!await parameters.insertAssistantIdempotent(record)) {
      throw StateError('Saved parameter identity changed');
    }
    await _addHistory(entry);
    var undone = false;
    return () async {
      if (undone) return;
      if (!await parameters.deleteIfUnchanged(record)) {
        throw StateError('Saved parameters changed');
      }
      undone = true;
      await _markUndone(entry.id);
    };
  }

  @override
  Future<JournalPreparation> prepareJournal(WeldJournalDraft d,
      {required bool byVoice, required AppLanguage lang}) async {
    if (validateAssistantProposal(kIntentAddWeldJournalEntry, {
      'weld_no': d.weldNo,
      'project': d.project,
      'wps': d.wps
    }) is! AssistantReadyToJournal) {
      throw const FormatException('journal');
    }
    try {
      final all = await journal.listAll();
      final who = await stamp();
      final project = canonicalJournalProject(all, d.project);
      if (isWeldNoTaken(all, project: project, weldNo: d.weldNo)) {
        return JournalWeldNoTaken(
            weldNo: d.weldNo, project: project, wps: d.wps);
      }
      final draft =
          WeldJournalDraft(weldNo: d.weldNo, project: project, wps: d.wps);
      final at = now();
      final e = buildAssistantWeldEntry(draft,
          id: _uuid.v4(), stamp: who, at: at, byVoice: byVoice, lang: lang);
      return PreparedJournal(
          draft: draft,
          summary: AssistantAnswer(
              text: AssistantText('Spoina ${e.weldNo} · $project',
                  'Weld ${e.weldNo} · $project'),
              lines: [
                AnswerLine(const AssistantText('Status', 'Status'),
                    lang == AppLanguage.pl ? 'do badania' : 'pending'),
                AnswerLine(const AssistantText('Spawacz', 'Welder'), e.welder),
                if (e.wpsRef.isNotEmpty)
                  AnswerLine(const AssistantText('WPS', 'WPS'), e.wpsRef),
                AnswerLine(const AssistantText('Data', 'Date'), e.date),
              ]),
          payload: AssistantJournalSnapshot._(e, who, at, this, byVoice, lang));
    } catch (_) {
      return const JournalUnavailable(AssistantText(
          'Nie udało się odczytać dziennika. Nic nie zapisano.',
          'Could not read the journal. Nothing saved.'));
    }
  }

  @override
  Future<UndoAction?> saveJournal(PreparedJournal prepared,
      {required bool byVoice, required AppLanguage lang}) {
    final prior = _journalSaves[prepared];
    if (prior != null) return prior;
    final p = prepared.payload;
    if (p is! AssistantJournalSnapshot ||
        !identical(p.owner, this) ||
        p.byVoice != byVoice ||
        p.lang != lang ||
        p.entry.weldNo != prepared.draft.weldNo ||
        p.entry.projectName != prepared.draft.project ||
        p.entry.wpsRef != (prepared.draft.wps ?? '')) {
      throw const FormatException('journal snapshot');
    }
    final pending = _saveJournal(p);
    _journalSaves[prepared] = pending;
    return pending.catchError((Object e, StackTrace st) {
      _journalSaves[prepared] = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<UndoAction?> _saveJournal(AssistantJournalSnapshot p) async {
    final e = p.entry;
    if (!await journal.insertAssistantIfAvailable(e, by: p.stamp)) {
      throw StateError('Journal project or weld number changed');
    }
    _lastProject = e.projectName;
    try {
      _onProjectSaved?.call(e.projectName);
    } catch (_) {
      debugPrint('Assistant project context not updated');
    }
    try {
      await saveLastWeldProject(e.projectName);
    } catch (_) {
      debugPrint('Assistant project metadata not saved');
    }
    final h = AssistantHistoryEntry(
        id: _uuid.v4(),
        kind: kIntentAddWeldJournalEntry,
        summary: [
          '${p.lang == AppLanguage.en ? 'Weld' : 'Spoina'} ${e.weldNo}',
          e.projectName,
          if (e.wpsRef.isNotEmpty) 'WPS ${e.wpsRef}',
          if (e.welder.isNotEmpty) e.welder
        ].join(' · '),
        recordId: e.id,
        at: p.at,
        byVoice: p.byVoice);
    await _addHistory(h);
    var undone = false;
    return () async {
      if (undone) return;
      if (!await journal.softDeleteAssistantIfUnchanged(e, by: p.stamp)) {
        throw StateError('Saved journal entry changed');
      }
      undone = true;
      await _markUndone(h.id);
    };
  }

  Future<void> _addHistory(AssistantHistoryEntry h) async {
    try {
      await history.add(h);
    } catch (_) {
      debugPrint('Assistant history metadata not saved');
    }
  }

  Future<void> _markUndone(String id) async {
    try {
      await history.markUndone(id);
    } catch (_) {
      debugPrint('Assistant undo metadata not saved');
    }
  }
}

/// Read-only native summary data; snapshots cannot be forged outside this library.
class AssistantJournalSnapshot {
  AssistantJournalSnapshot._(
      this.entry, this.stamp, this.at, this.owner, this.byVoice, this.lang);
  final WeldEntry entry;
  final String stamp;
  final DateTime at;
  final AssistantActions owner;
  final bool byVoice;
  final AppLanguage lang;
}

class _ParameterSnapshot {
  const _ParameterSnapshot(this.record, this.history, this.byVoice, this.lang);
  final WeldParam record;
  final AssistantHistoryEntry history;
  final bool byVoice;
  final AppLanguage lang;
}
