import 'package:flutter/foundation.dart';

/// One conversation stays mounted while the application changes modules.
class AssistantPanelController extends ChangeNotifier {
  static final instance = AssistantPanelController();
  bool expanded = false;
  Future<void> Function(String)? onCommand;
  void setExpanded(bool value) {
    expanded = value;
    notifyListeners();
  }

  Future<void> submit(String text) async {
    setExpanded(true);
    await onCommand?.call(text);
  }
}
