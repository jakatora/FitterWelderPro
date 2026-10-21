import 'assistant_ai_client.dart';

/// A proposed plan advances once per actual result. Questions/confirmations
/// pause it; superseding commands and failure discard the remainder.
class AiExecutionQueue {
  final List<AiCommandStep> _remaining = [];
  String? original, waitingSkill;
  bool get hasNext => _remaining.isNotEmpty;
  bool get waiting => waitingSkill != null;
  void start(String source, List<AiCommandStep> steps) {
    cancel();
    original = source;
    _remaining.addAll(steps);
  }

  AiCommandStep? takeNext() =>
      waiting || _remaining.isEmpty ? null : _remaining.removeAt(0);
  void pause(String id) => waitingSkill = id;
  bool resolve(String? id, {required bool completed}) {
    if (id != waitingSkill) {
      cancel();
      return false;
    }
    if (!completed) return false;
    waitingSkill = null;
    return hasNext;
  }

  void cancel() {
    _remaining.clear();
    original = null;
    waitingSkill = null;
  }
}
