import '../../../database/instrument_dao.dart';
import '../../../domain/instruments/instrument.dart';
import '../../../domain/qualification/qualification_dates.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';

typedef InstrumentReader = Future<List<Instrument>> Function();

final _dueQuery = RegExp(
  r'^(?:(?:prosze|powiedz|powiedz mi|sprawdz|please|tell me|check)\s+)*'
  r'(?:kiedy (?:jest |mam |wypada )?(?:nastepna )?kalibracja|'
  r'(?:pokaz|podaj) terminy kalibracji|terminy kalibracji|'
  r'when (?:is|are) (?:my |the )?(?:next )?calibrations?|'
  r'(?:show |check )?(?:my )?calibration (?:due dates|dates|due))'
  r'(?:\s+(.*))?$',
);

final _namedDue = RegExp(r'^when is (?:my |the )?(.+) due for calibration$');

String? _query(Utterance u) =>
    _namedDue.firstMatch(u.folded)?.group(1) ??
    _dueQuery.firstMatch(u.folded)?.group(1);

String _normalized(String text) => Utterance(text, lang: AppLanguage.pl).folded;

class InstrumentsDueSkill extends AssistantSkill {
  InstrumentsDueSkill({InstrumentReader? load})
      : _load = load ?? InstrumentDao().listAll;

  final InstrumentReader _load;

  @override
  String get id => 'instruments.due';
  @override
  String get toolId => 'instruments';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Kiedy kalibracja?', 'When is calibration?'),
        SkillExample('Pokaż terminy kalibracji', 'Show calibration due dates'),
        SkillExample('Kiedy następna kalibracja?', 'When is next calibration?'),
        SkillExample('Kiedy kalibracja manometru?',
            'When is my pressure gauge due for calibration?'),
        SkillExample(
            'Kiedy kalibracja Kemppi?', 'When is Kemppi due for calibration?'),
        SkillExample('Podaj terminy kalibracji', 'My calibration dates'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz rejestr przyrządów', routesTo: 'tool.open'),
        SkillRejection('zapisz kalibrację manometru'),
        SkillRejection('jak skalibrować manometr'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!_dueQuery.hasMatch(u.folded) && !_namedDue.hasMatch(u.folded)) {
      return null;
    }
    return SkillMatch(this, .94,
        slots: {'query': _query(u) ?? ''}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final en = ctx.lang == AppLanguage.en;
    List<Instrument> all;
    try {
      all = (await _load()).where((i) => !i.isDeleted).toList();
    } catch (_) {
      return const FailedResult(AssistantText(
        'Nie udało się odczytać rejestru przyrządów. Spróbuj ponownie.',
        'Could not read the instrument register. Please try again.',
      ));
    }
    final query = m.slots['query'] as String? ?? '';
    final words = _normalized(query).split(' ').where((w) =>
        w.isNotEmpty &&
        !const {'dla', 'for', 'of', 'the', 'my', 'mojego'}.contains(w));
    final selected = all.where((i) {
      final searchable = _normalized(
          '${i.name} ${i.serialNo} ${i.kind.labelPl} ${i.kind.labelEn}');
      final terms = searchable.split(' ');
      return words.every((word) => terms.any((term) {
            if (term == word) return true;
            // Polish genitive: manometru -> manometr. Never stem serial digits.
            if (RegExp(r'\d').hasMatch(word) || word.length < 6) return false;
            return term.startsWith(word.substring(0, word.length - 1));
          }));
    }).toList();
    selected.sort((a, b) {
      final ad = a.dueDate, bd = b.dueDate;
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      final order = ad == null ? 0 : ad.compareTo(bd!);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    final today = dateOnly(ctx.now());
    String status(Instrument i) => switch (i.statusOn(today)) {
          InstrumentStatus.unknown =>
            en ? 'No recorded due date' : 'Brak zapisanego terminu',
          InstrumentStatus.overdue => en ? 'Overdue' : 'Po terminie',
          InstrumentStatus.dueSoon =>
            en ? 'Due within 30 days' : 'Termin w ciągu 30 dni',
          InstrumentStatus.ok =>
            en ? 'Date not exceeded' : 'Termin nieprzekroczony',
        };
    return AnswerResult(
      AssistantAnswer(
        text: selected.isEmpty
            ? (all.isEmpty
                ? const AssistantText('Rejestr przyrządów jest pusty.',
                    'The instrument register is empty.')
                : const AssistantText(
                    'Nie znalazłem pasującego przyrządu w rejestrze.',
                    'No matching instrument found in the register.'))
            : AssistantText(
                'Terminy z Twojego lokalnego rejestru na ${formatIsoDate(today)}. Sam termin nie potwierdza sprawności ani wykonania kalibracji.',
                'Dates from your local register as of ${formatIsoDate(today)}. A due date does not confirm fitness or completed calibration.',
              ),
        lines: [
          for (final i in selected)
            AnswerLine(
              AssistantText.same(i.displayName(en: en)),
              '${i.dueDate == null ? '—' : formatIsoDate(i.dueDate!)} · ${status(i)}',
            ),
        ],
        source: const AssistantText(
            'Lokalny rejestr przyrządów', 'Local instrument register'),
      ),
      show: const ShowInModule('instruments'),
    );
  }
}
