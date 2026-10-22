import 'calculator_result_readback.dart';
import 'assistant_text.dart';

/// Co jest teraz na ekranie — bez zależności od UI. Implementuje `ToolBridge`
/// (zadanie 1.4); w testach atrapa.
abstract class ModuleContext {
  /// Identyfikator narzędzia z rejestru, którego trasa jest na wierzchu
  /// (null = ekran Start, asystent albo ekran spoza rejestru).
  String? get activeToolId;

  /// Użytkownik jest na ekranie Start albo w asystencie — wolno otworzyć
  /// moduł bez pytania (spec §4.4a).
  bool get onHomeOrAssistant;
}

/// Stały kontekst modułów (testy, podgląd, wejście tekstowe bez nawigacji).
class FixedModuleContext implements ModuleContext {
  const FixedModuleContext({this.activeToolId, this.onHomeOrAssistant = true});

  @override
  final String? activeToolId;

  @override
  final bool onHomeOrAssistant;
}

/// A module can expose the selected persisted record without exposing widgets.
abstract interface class RecordModuleContext {
  String? selectedRecordId(String toolId);
}

/// Opt-in canonical calculator inputs from the visible, ready route. Manual
/// edits may be newer than conversation history. Validate after merging edits.
abstract interface class FieldModuleContext {
  Map<String, Object?>? inputFields(String toolId);
}

/// Opt-in native calculator output, independent of model inference or records.
abstract interface class CalculatorResultModuleContext {
  CalculatorResultReadback? calculatorResult(String toolId);
}

bool hasVisibleFormInputs(ModuleContext modules, String? toolId) =>
    toolId != null &&
    modules.activeToolId == toolId &&
    modules is FieldModuleContext &&
    (modules as FieldModuleContext).inputFields(toolId) != null;

/// Explicit, opt-in actions on the visible ready module. Credentials and hidden
/// forms never participate. Completion comes from execution, not a prediction.
abstract interface class ModuleActionContext {
  Future<ModuleActionResult> performModuleAction(String toolId, String action,
      {String? field});
}

class ModuleActionResult {
  const ModuleActionResult(this.completed, this.message);
  final bool completed;
  final AssistantText message;
}

/// A native screen prepares a bounded record snapshot; only confirmation calls
/// perform. No model-supplied record IDs or persistence callbacks are accepted.
typedef ModuleRecordUndo = Future<void> Function();

class PreparedModuleRecord {
  const PreparedModuleRecord(this.summary, this.perform);
  final AssistantText summary;
  final Future<ModuleRecordUndo?> Function() perform;
}

abstract interface class RecordActionModuleContext {
  PreparedModuleRecord? prepareModuleRecord(String toolId, String action);
}
