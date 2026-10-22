import '../../../database/local_record_owner.dart';
import '../../../database/weld_journal_dao.dart';
import '../../../database/db.dart';
import '../../../database/welder_certificate_dao.dart';
import '../../../domain/qualification/certificate_status.dart';
import '../../../domain/qualification/journal_welds.dart';
import '../../../domain/qualification/qualification_dates.dart';
import '../../../domain/qualification/weld_process.dart';
import '../../../domain/weld_journal/weld_compliance.dart'
    show certificatesForStamp;
import '../../../i18n/app_language.dart';
import '../../../services/welder_identity.dart';
import '../../core/skill.dart';

typedef CertificateReader = Future<List<CertificateEvaluation>> Function(
    DateTime asOf);

/// One read transaction: certificates, confirmation history and journal from
/// the same snapshot. Unlike refresh(), this neither migrates records nor
/// schedules notifications, and a failed journal read is not treated as empty.
Future<List<CertificateEvaluation>> readLocalCertificateEvaluations(
    DateTime asOf,
    {required String? ownerStamp}) async {
  final recordOwner = await LocalRecordOwner.capture();
  final db = await AppDatabase.get();
  final result = await db.transaction((txn) async {
    recordOwner.requireCurrent();
    final certificates = certificatesForStamp(
      await WelderCertificateDao().listAll(db: txn),
      ownerStamp,
      ownerStamp: ownerStamp,
    );
    final journal = journalWeldsFromRows(
        await readOwnedWeldJournalRows(txn, recordOwner),
        stamp: ownerStamp,
        today: asOf);
    return [
      for (final c in certificates)
        evaluateCertificate(c,
            asOf: asOf, journalWelds: journalWeldsFor(c, journal)),
    ];
  });
  recordOwner.requireCurrent();
  return result;
}

Future<List<CertificateEvaluation>> _readCurrent(DateTime asOf) async =>
    readLocalCertificateEvaluations(asOf,
        ownerStamp: (await WelderIdentityService.instance.get())?.stamp);

final _expiryQuery = RegExp(
  r'^(?:(?:prosze|powiedz|powiedz mi|sprawdz|please|tell me|check)\s+)*'
  r'(?:(?:kiedy (?:wygasa|wygasaja|konczy sie|koncza sie)|'
  r'do kiedy (?:jest |sa )?wazne) (?:moje |moj )?'
  r'(?:uprawnienie|uprawnienia|certyfikat|certyfikaty)|'
  r'(?:pokaz|podaj) terminy (?:moich )?uprawnien|'
  r'when (?:does|do) (?:my |the )?(?:certificate|certificates|qualification|qualifications) expire|'
  r'(?:show )?(?:my )?certificate expiry dates)'
  r'(?:\s+(.*))?$',
);
final _namedExpiry = RegExp(
    r'^when (?:does|do) (?:my |the )?(.+) (?:qualification|certificate) expire$');

class CertificatesExpirySkill extends AssistantSkill {
  CertificatesExpirySkill({CertificateReader? load})
      : _load = load ?? _readCurrent;
  final CertificateReader _load;

  @override
  String get id => 'certs.expiry';
  @override
  String get toolId => 'welder_certificates';
  @override
  AssistantTier get tier => AssistantTier.b;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Kiedy wygasa moje uprawnienie 141?',
            'When does my 141 qualification expire?'),
        SkillExample('Do kiedy ważne moje uprawnienie TIG?',
            'When does my TIG qualification expire?'),
        SkillExample(
            'Kiedy wygasa mój certyfikat?', 'When does my certificate expire?'),
        SkillExample('Pokaż terminy moich uprawnień',
            'Show my certificate expiry dates'),
        SkillExample('Kiedy wygasają moje uprawnienia?',
            'When do my qualifications expire?'),
        SkillExample('Podaj terminy uprawnień', 'Certificate expiry dates'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz uprawnienia spawacza', routesTo: 'tool.open'),
        SkillRejection('zapisz potwierdzenie uprawnienia 141'),
        SkillRejection('co to jest uprawnienie 141'),
      ];
  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final named = _namedExpiry.firstMatch(u.folded);
    // Optional "my/the" may backtrack into the process capture when the
    // question contains no actual process name.
    final m = named != null && !const {'my', 'the'}.contains(named.group(1))
        ? named
        : _expiryQuery.firstMatch(u.folded);
    if (m == null) return null;
    return SkillMatch(this, .94,
        slots: {'process': m.group(1) ?? ''}, utterance: u);
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final today = dateOnly(ctx.now());
    final en = ctx.lang == AppLanguage.en;
    List<CertificateEvaluation> all;
    try {
      all = await _load(today);
    } catch (_) {
      return const FailedResult(AssistantText(
        'Nie udało się odczytać uprawnień lub danych ciągłości. Spróbuj ponownie.',
        'Could not read qualifications or continuity records. Please try again.',
      ));
    }
    final process = m.slots['process'] as String? ?? '';
    final selected = all
        .where((e) =>
            process.isEmpty ||
            matchProcess(process, e.certificate.processes) ==
                ProcessMatch.covered)
        .toList();
    selected.sort((a, b) {
      final ad = a.expiryDate, bd = b.expiryDate;
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      final order = ad == null ? 0 : ad.compareTo(bd!);
      return order != 0 ? order : a.certificate.id.compareTo(b.certificate.id);
    });
    String date(DateTime? value) => value == null
        ? (en ? 'No recorded date' : 'Brak wpisanej daty')
        : formatIsoDate(value);
    String state(CertificateEvaluation e) {
      if (e.continuityUnknown && e.state != QualificationState.expired) {
        return en ? 'Continuity data incomplete' : 'Niepełne dane ciągłości';
      }
      return switch (e.state) {
        QualificationState.expired =>
          en ? 'Expiry date exceeded' : 'Data ważności przekroczona',
        QualificationState.lapsed =>
          en ? 'Continuity deadline exceeded' : 'Termin ciągłości przekroczony',
        QualificationState.expiringSoon =>
          en ? 'Expiry within 30 days' : 'Ważność kończy się w ciągu 30 dni',
        QualificationState.confirmationDue => en
            ? 'Continuity deadline within 30 days'
            : 'Termin ciągłości w ciągu 30 dni',
        QualificationState.valid => en
            ? 'No recorded deadline exceeded'
            : 'Brak przekroczonych zapisanych terminów',
      };
    }

    return AnswerResult(
      AssistantAnswer(
        text: selected.isEmpty
            ? (all.isEmpty
                ? const AssistantText(
                    'Nie ma uprawnień przypisanych do Twojego stempla. Sprawdź stempel i rejestr uprawnień.',
                    'No qualifications assigned to your welder stamp. Check your stamp and qualification register.')
                : const AssistantText(
                    'Nie znalazłem Twojego uprawnienia dla wskazanego procesu.',
                    'No qualification found for the requested process.'))
            : AssistantText(
                'Terminy z Twojego rejestru na ${formatIsoDate(today)}. Data ważności i ciągłość są sprawdzane osobno; to nie jest kontrola zakresu konkretnej spoiny.',
                'Dates from your register as of ${formatIsoDate(today)}. Expiry and continuity are checked separately; this is not a scope check for a particular weld.'),
        lines: [
          for (final e in selected) ...[
            AnswerLine(
                AssistantText.same(e.certificate.shortTitle(english: en)),
                '${en ? 'Expiry' : 'Ważność'}: ${date(e.expiryDate)} · ${state(e)}'),
            AnswerLine(
                const AssistantText('Ciągłość', 'Continuity'),
                e.rule == ContinuityRule.none
                    ? (en
                        ? 'Not evaluated for this standard'
                        : 'Nieoceniana dla tej normy')
                    : '${e.rule == ContinuityRule.confirmation ? (en ? 'Confirmation' : 'Potwierdzenie') : (en ? 'Process use' : 'Spawanie procesem')}: ${date(e.continuityDeadline)}'),
            if (e.lateConfirmation != null)
              AnswerLine(
                  const AssistantText(
                      'Spóźnione potwierdzenie', 'Late confirmation'),
                  '${date(e.lateConfirmation)} · ${en ? 'Does not restore continuity' : 'Nie przywraca ciągłości'}'),
          ],
        ],
        source: const AssistantText(
            'Lokalny rejestr uprawnień, historia potwierdzeń i dziennik spoin',
            'Local qualification register, confirmation history and weld journal'),
      ),
      show: const ShowInModule('welder_certificates'),
    );
  }
}
