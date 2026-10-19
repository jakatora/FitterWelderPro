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
