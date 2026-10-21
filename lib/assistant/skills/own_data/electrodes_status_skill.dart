import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/welding/electrode_exposure.dart';
import '../../../i18n/app_language.dart';
import '../../core/skill.dart';

typedef ElectrodeReader = Future<BatchDecodeResult> Function();

/// Read-only snapshot: unlike the screen's recovery loader, this does not
/// write backup preferences or silently turn a lossy decode into an empty log.
Future<BatchDecodeResult> readLocalElectrodeBatches() async {
  final raw =
      (await SharedPreferences.getInstance()).get(kElectrodeBatchesPrefsKey);
  if (raw != null && raw is! String) {
    return const BatchDecodeResult([], lossy: true);
  }
  return decodeBatchesDetailed(raw as String?);
}

final _statusQuery = RegExp(
  r'^(?:(?:prosze|please)\s+)*'
  r'(?:ile jeszcze moga lezec (?:moje )?elektrody|'
  r'(?:pokaz |sprawdz )?(?:stan|status) (?:moich )?elektrod|'
  r'pokaz moje partie elektrod|'
  r'how much time (?:is )?left for (?:my )?electrodes|'
  r'(?:show |check )?(?:my )?electrode (?:batch )?status)$',
);
final _namedStatus = RegExp(
  r'^(?:(?:prosze|please)\s+)*(?:(?:pokaz|sprawdz|show|check)\s+)?'
  r'(?:stan partii elektrod|status partii elektrod|electrode batch status)\s+.+$',
);
final _rawName = RegExp(
  r'^(?:(?:prosze|please)\s+)?(?:(?:pokaz|pokaż|sprawdz|sprawdź|show|check)\s+)?'
  r'(?:stan\s+partii\s+elektrod|status\s+partii\s+elektrod|electrode\s+batch\s+status)\s+(.+?)\s*\??$',
  caseSensitive: false,
);

/// Also used by the reference skill: personal log queries must not trigger
/// a question about a theoretical electrode classification instead.
bool isElectrodeStatusQuery(Utterance u) =>
    _statusQuery.hasMatch(u.folded) || _namedStatus.hasMatch(u.folded);

class ElectrodesStatusSkill extends AssistantSkill {
  ElectrodesStatusSkill({ElectrodeReader? load})
      : _load = load ?? readLocalElectrodeBatches;
  final ElectrodeReader _load;

  @override
  String get id => 'electrodes.status';
  @override
  String get toolId => 'electrode_exposure';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Ile jeszcze mogą leżeć elektrody?',
            'How much time is left for my electrodes?'),
        SkillExample('Ile jeszcze mogą leżeć moje elektrody?',
            'How much time left for electrodes?'),
        SkillExample(
            'Sprawdź stan moich elektrod', 'Check my electrode status'),
        SkillExample(
            'Pokaż moje partie elektrod', 'Show electrode batch status'),
        SkillExample('Status moich elektrod', 'My electrode status'),
        SkillExample(
            'Stan partii elektrod Warsztat', 'Electrode batch status Warsztat'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz elektrody zasadowe', routesTo: 'tool.open'),
        SkillRejection('wyjąłem elektrody z piecyka'),
        SkillRejection('zapisz suszenie elektrod'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    if (!isElectrodeStatusQuery(u)) return null;
    final name = _rawName.firstMatch(u.raw)?.group(1)?.trim();
    return SkillMatch(this, .96,
        slots: {
          'name': name ?? '',
          'invalidName': _namedStatus.hasMatch(u.folded) && name == null,
        },
        utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    if (m.slots['invalidName'] == true) {
      return const FailedResult(AssistantText(
          'Podaj identyfikator lub miejsce po słowach „stan partii elektrod”.',
          'Give an ID or location after "electrode batch status".'));
    }
    BatchDecodeResult data;
    try {
      data = await _load();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się odczytać partii elektrod. Spróbuj ponownie.',
          'Could not read electrode batches. Please try again.'));
    }
    if (data.lossy) {
      return const FailedResult(AssistantText(
          'Zapis partii jest niepełny lub niespójny. Sprawdź dziennik elektrod; nie mogę wiarygodnie obliczyć pozostałego czasu.',
          'The batch record is incomplete or inconsistent. Check the electrode log; I cannot reliably calculate the remaining time.'));
    }
    final now = ctx.now();
    final en = ctx.lang == AppLanguage.en;
    final name = (m.slots['name'] as String? ?? '').trim().toLowerCase();
    final selected = name.isEmpty
        ? sortActive(data.batches, now)
        : [
            for (final b in data.batches)
              if (b.id.toLowerCase() == name ||
                  b.location.trim().toLowerCase() == name)
                b,
          ];
    String span(Duration d) =>
        d.abs() > Duration.zero && d.abs() < const Duration(minutes: 1)
            ? (en ? 'less than 1 min' : 'mniej niż 1 min')
            : formatSpan(d);
    String status(ElectrodeBatch b) {
      if ([
        b.takenOutAt,
        b.exposureStart,
        b.ovenSince,
        b.closedAt,
        for (final event in b.events) event.at
      ].any((t) => t != null && t.isAfter(now))) {
        return en
            ? 'Future timestamp — cannot assess'
            : 'Data z przyszłości — nie mogę ocenić';
      }
      final left = b.remainingAt(now);
      final state = switch (b.stateAt(now)) {
        ExposureState.consumed =>
          en ? 'Consumed — closed batch' : 'Zużyte — partia zamknięta',
        ExposureState.scrapped =>
          en ? 'Scrapped — closed batch' : 'Złom — partia zamknięta',
        ExposureState.inOven => en
            ? 'In oven — clock paused; remaining ${span(left)}'
            : 'W piecyku — licznik wstrzymany; pozostało ${span(left)}',
        ExposureState.exceeded => en
            ? 'Exposure limit exceeded by ${span(left)}'
            : 'Limit ekspozycji przekroczony o ${span(left)}',
        ExposureState.endingSoon => en
            ? 'Limit ending — remaining ${span(left)}'
            : 'Limit kończy się — pozostało ${span(left)}',
        ExposureState.ok =>
          en ? 'Remaining ${span(left)}' : 'Pozostało ${span(left)}',
      };
      return '$state · ${en ? 'Recorded limit' : 'Zapisany limit'}: ${span(b.limit)}'
          ' · ${en ? 'Re-dry cycles' : 'Suszenia'}: ${b.redryCount}/${b.maxRedries}'
          '${b.redryLimitExceeded ? (en ? ' — re-dry limit exceeded' : ' — przekroczony limit suszeń') : ''}';
    }

    return AnswerResult(
        AssistantAnswer(
          text: selected.isEmpty
              ? (name.isEmpty
                  ? const AssistantText(
                      'Brak aktywnych partii w Twoim dzienniku elektrod.',
                      'No active batches in your electrode log.')
                  : const AssistantText(
                      'Nie znalazłem partii o tym identyfikatorze lub miejscu.',
                      'No batch found for this ID or location.'))
              : AssistantText(
                  'Stan według zapisanych limitów partii na ${formatYmd(now)} ${formatHm(now)}.',
                  'Status based on recorded batch limits as of ${formatYmd(now)} ${formatHm(now)}.'),
          lines: [
            for (final b in selected)
              AnswerLine(
                  AssistantText.same(
                      '${b.label(en: en)}${b.location.isEmpty ? '' : ' · ${b.location}'}'),
                  status(b))
          ],
          source: const AssistantText('Lokalny dziennik ekspozycji elektrod',
              'Local electrode exposure log'),
        ),
        show: const ShowInModule('electrode_exposure'));
  }
}
