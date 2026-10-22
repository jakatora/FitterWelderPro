import '../../core/skill.dart';
import '../../core/command_words.dart';
import 'iso_draw_skill.dart';

/// Read-only native facts, never an estimate from paper-space segment lengths.
class IsoSummarySkill extends AssistantSkill {
  IsoSummarySkill(this.port);
  final IsoDrawingPort port;
  @override
  String get id => 'iso.summary';
  @override
  String get toolId => 'iso_notebook';
  @override
  AssistantTier get tier => AssistantTier.d;
  @override
  bool get readOnly => true;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Podsumuj rysunek ISO', 'Summarize the ISO drawing'),
        SkillExample(
            'Ile rur jest w tym rysunku', 'How many pipes are in this drawing'),
        SkillExample('Jaka jest suma długości CUT w tym rysunku',
            'What is the total CUT length in this drawing'),
      ];
  bool _requested(Utterance u) {
    if (referencesInstruction(u)) return false;
    final text = u.folded.replaceFirst(
        RegExp(
            r'^(?:prosze |please |(?:czy )?mozesz (?:prosze )?|czy moglbys (?:prosze )?|czy moglabys (?:prosze )?|(?:can|could|would|will) you (?:please )?|powiedz mi |tell me )'),
        '');
    return RegExp(
            r'^(?:podsum(?:uj|owac) (?:ten |aktualny |obecny )?(?:rysunek(?: iso)?|iso|szkic)|summari[sz]e (?:the |this )?(?:current )?(?:iso drawing|drawing|sketch)|ile rur (?:jest|mam) (?:w (?:tym|aktualnym|obecnym) (?:rysunku|szkicu)|w iso)|how many pipes are in (?:this|the) (?:current )?(?:iso )?drawing|jaka jest suma dlugosci cut w tym rysunku|what is the total cut length in this drawing)$')
        .hasMatch(text);
  }

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) => _requested(u)
      ? SkillMatch(this, .99, utterance: u, explicitToolTarget: true)
      : null;
  @override
  bool acceptsProposal(
          Utterance original, Utterance command, AssistantContext context) =>
      _requested(command) && _summaryIntent(original);

  bool _summaryIntent(Utterance source) {
    if (source.hasStem(const ['skopiuj', 'kopiuj', 'copy', 'schow', 'clipboard', 'wyslij', 'send', 'udostepnij', 'share'])) {
      return false;
    }
    if (referencesInstruction(source) ||
        source.hasAny(const ['nie', 'not', 'dont', 'don t', 'never'])) {
      return false;
    }
    if (_requested(source)) return true;
    final drawing = source.hasAny(const ['iso']) ||
        source
            .hasStem(const ['rysun', 'szkic', 'izometr', 'drawing', 'sketch']);
    final summary = source.hasStem(const ['podsum', 'summari']);
    final count = source.hasAny(const ['ile rur', 'how many pipes']);
    final cutTotal = source.hasAny(const ['cut']) &&
        source.hasAny(const ['suma', 'sume', 'sum', 'total']);
    return drawing && (summary || count || cutTotal);
  }

  @override
  Future<SkillResult> run(SkillMatch match, AssistantContext ctx) async {
    final snapshot = port.isForeground && port is IsoSummaryPort
        ? (port as IsoSummaryPort).summary
        : null;
    if (snapshot == null) {
      return const FailedResult(AssistantText(
          'Otwórz rysunek ISO i poczekaj na zakończenie rysowania, abym odczytał jego podsumowanie.',
          'Open the ISO drawing and wait until drawing finishes so I can read its summary.'));
    }
    final missing = snapshot.pipeCount - snapshot.computedCutCount;
    final total = snapshot.computedCutTotalMm.toStringAsFixed(1);
    final gap = snapshot.gapMm.toStringAsFixed(1);
    return AnswerResult(AssistantAnswer(
        text: AssistantText(
            'Odcinki rur: ${snapshot.pipeCount}. Obliczalne długości CUT: ${snapshot.computedCutCount}; ich suma: $total mm. Odcinki bez obliczalnego CUT: $missing. Szczelina: $gap mm. Suma obejmuje tylko obliczalne odcinki, nie zastępuje weryfikacji listy cięcia.',
            'Pipe segments: ${snapshot.pipeCount}. Computable CUT lengths: ${snapshot.computedCutCount}; their total: $total mm. Segments without a computable CUT: $missing. Gap: $gap mm. The total includes only computable segments and does not replace cut-list verification.')));
  }
}
