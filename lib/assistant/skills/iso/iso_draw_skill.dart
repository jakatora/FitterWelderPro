import '../../core/skill.dart';
import '../../core/command_words.dart' show looksLikeOtherCommand;
import 'iso_command_parser.dart';

final _independentQuestion = RegExp(
    r'^(?:(?:prosze|please|powiedz|tell me)\s+)*(?:co|jak\w*|ile|czy|kiedy|gdzie|dlaczego|w czym|what|how|why|when|where|which|is|are|does|can|could|help)\b');

/// The route owns navigation, mounted controllers and the ongoing drawing
/// dialogue. Matching only reads these flags; execution happens in run.
abstract interface class IsoDrawingPort {
  bool get isForeground;
  bool get hasPendingQuestion;
  Future<SkillResult> execute(Utterance utterance);
}

class IsoDrawingQuestion {
  const IsoDrawingQuestion(this.slot, this.question, {this.choices = const []});
  final String slot;
  final AssistantText question;
  final List<FollowUp> choices;
}

abstract interface class IsoQuestionPort {
  IsoDrawingQuestion? get pendingQuestion;
  bool acceptsReply(Utterance utterance);
  bool acceptsProposalReply(Utterance command, Utterance original);
}

class CallbackIsoDrawingPort implements IsoDrawingPort, IsoQuestionPort {
  CallbackIsoDrawingPort(
      {required bool Function() isForeground,
      required bool Function() hasPendingQuestion,
      IsoDrawingQuestion? Function()? pendingQuestion,
      bool Function(Utterance)? acceptsReply,
      bool Function(Utterance, Utterance)? acceptsProposalReply,
      required Future<SkillResult> Function(Utterance) execute})
      : _foreground = isForeground,
        _pending = hasPendingQuestion,
        _question = pendingQuestion,
        _acceptsReply = acceptsReply,
        _acceptsProposalReply = acceptsProposalReply,
        _execute = execute;
  final bool Function() _foreground, _pending;
  final IsoDrawingQuestion? Function()? _question;
  final bool Function(Utterance)? _acceptsReply;
  final bool Function(Utterance, Utterance)? _acceptsProposalReply;
  @override
  IsoDrawingQuestion? get pendingQuestion => _question?.call();
  @override
  bool acceptsReply(Utterance u) => _acceptsReply?.call(u) ?? false;
  @override
  bool acceptsProposalReply(Utterance command, Utterance original) =>
      _acceptsProposalReply?.call(command, original) ?? acceptsReply(command);
  final Future<SkillResult> Function(Utterance) _execute;
  @override
  bool get isForeground => _foreground();
  @override
  bool get hasPendingQuestion => _pending();
  @override
  Future<SkillResult> execute(Utterance utterance) => _execute(utterance);
}

class IsoDrawSkill extends AssistantSkill {
  IsoDrawSkill(this.port);
  final IsoDrawingPort port;
  @override
  String get id => 'iso.draw';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.d;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Narysuj rura kolanko rura', 'Draw pipe elbow pipe'),
        SkillExample('Narysuj rura dwa metry w prawo kolano w górę rura metr',
            'Draw pipe two meters right elbow up pipe one meter'),
        SkillExample('Dodaj zawór kulowy DN50', 'Add ball valve DN50'),
        SkillExample(
            'Dorysuj rura metr w prawo', 'Append pipe one meter right'),
        SkillExample(
            'Wstaw symbol kolana 45 DN50', 'Place 45 degree elbow symbol DN50'),
        SkillExample('Nowy rysunek', 'New drawing'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('ile waży rura DN50 ścianka 3 mm',
            routesTo: 'pipe.weight'),
        SkillRejection('otwórz zeszyt ISO', routesTo: 'tool.open'),
        SkillRejection('przygotuj protokół prac gorących',
            routesTo: 'hot_work.prepare'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (port.hasPendingQuestion &&
        const {
          'dorysuj',
          'append',
          'nowy',
          'new',
          'anuluj',
          'cancel',
          'stop',
          'nie',
          'no'
        }.contains(u.folded)) {
      return SkillMatch(this, .99, utterance: u);
    }
    final command = parseIsoCommand(u);
    if (command?.kind == IsoCommandKind.setPipeDimension) return null;
    final onIso = ctx.modules.activeToolId == toolId || port.isForeground;
    if (command != null &&
        (command.explicit || onIso || port.hasPendingQuestion)) {
      return SkillMatch(
          this,
          command.explicit
              ? .99
              : port.hasPendingQuestion
                  ? .94
                  : .65,
          utterance: u);
    }
    if (onIso &&
        u.tokens.length <= 3 &&
        (isoDirectionOf(u) != null || isoCompassOf(u) != null)) {
      return SkillMatch(this, .94, utterance: u);
    }
    // An answer to a route-owned drawing question must not steal a stronger
    // independent command. No controller is opened by this fallback match.
    if (port.hasPendingQuestion &&
        !_independentQuestion.hasMatch(u.folded) &&
        !looksLikeOtherCommand(u)) {
      return SkillMatch(this, .56, utterance: u);
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final u = m.utterance;
    if (u == null) {
      return const FailedResult(
          AssistantText('Brak polecenia rysowania.', 'No drawing command.'));
    }
    final result = await port.execute(u);
    final questions = port;
    final question = questions is IsoQuestionPort
        ? (questions as IsoQuestionPort).pendingQuestion
        : null;
    return question == null
        ? result
        : AskResult(question.slot, question.question,
            partial: m, choices: question.choices);
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final questions = port;
    if (questions is! IsoQuestionPort) return null;
    final p = questions as IsoQuestionPort;
    return p.pendingQuestion?.slot == slot && p.acceptsReply(u)
        ? {slot: u.raw}
        : null;
  }

  @override
  Map<String, Object?>? fillProposalSlot(String slot, Utterance command,
      Utterance original, AssistantContext ctx) {
    final questions = port;
    if (questions is! IsoQuestionPort) return null;
    final p = questions as IsoQuestionPort;
    return p.pendingQuestion?.slot == slot &&
            p.acceptsProposalReply(command, original)
        ? {slot: command.raw}
        : null;
  }
}
