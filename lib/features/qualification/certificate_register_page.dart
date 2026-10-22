// Rejestr uprawnień spawacza (EN ISO 9606-1 / ASME IX WPQ).
//
// Lista certyfikatów ze statusem na dziś (data ważności + termin
// 6-miesięczny), wpis potwierdzenia, przypomnienia systemowe i objaśnienie
// zasad. Logika statusów: lib/domain/qualification/certificate_status.dart.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../domain/qualification/certificate_status.dart';
import '../../domain/qualification/qualification_dates.dart';
import '../../domain/qualification/reminder_plan.dart';
import '../../domain/qualification/weld_process.dart';
import '../../domain/qualification/welder_certificate.dart';
import '../../i18n/app_language.dart';
import '../../services/qualification_export.dart';
import '../../services/qualification_reminders.dart';
import '../../services/welder_qualification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/help_button.dart';
import '../../widgets/wpqr_chip.dart';
import 'certificate_edit_page.dart';
import 'form_bits.dart';
import '../../widgets/local_record_scope.dart';

class CertificateRegisterPage extends StatelessWidget {
  const CertificateRegisterPage({super.key});
  @override
  Widget build(BuildContext context) => LocalRecordScope(
      builder: (_, session) => _CertificateRegisterPage(session: session));
}

class _CertificateRegisterPage extends StatefulWidget {
  const _CertificateRegisterPage({required this.session});
  final LocalRecordSession session;
  @override
  State<_CertificateRegisterPage> createState() =>
      _CertificateRegisterPageState();
}

class _CertificateRegisterPageState extends State<_CertificateRegisterPage> {
  LocalRecordSession get _session => widget.session;
  Future<T?> _showOwnedDialog<T>(
          {required BuildContext context, required WidgetBuilder builder}) =>
      showDialog<T>(
          context: context,
          builder: (dialogContext) => LocalRecordScope(
              restartOnAccountChange: false,
              originSession: _session,
              builder: (_, __) => builder(dialogContext)));

  QualificationOverview? _overview;
  bool _loading = true;
  bool _loadFailed = false;
  bool _remindersOn = false;
  bool _togglingReminders = false;

  final _service = WelderQualificationService.instance;
  QualificationReminders get _reminders => QualificationReminders.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted || !_session.isCurrent) return;
    QualificationOverview? overview;
    var failed = false;
    try {
      // Sprawdzamy dostęp do bazy wprost — refresh() połyka błędy (baner ma
      // milczeć), a tutaj spawacz musi wiedzieć, że lista się nie wczytała.
      await _service.listCertificates();
      overview = await _service.refresh();
    } catch (_) {
      failed = true;
    }
    final on = await _reminders.isEnabled();
    if (!mounted || !_session.isCurrent) return;
    setState(() {
      _overview = overview;
      _loadFailed = failed;
      _remindersOn = on;
      _loading = false;
    });
  }

  Future<void> _openEditor([WelderCertificate? certificate]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CertificateEditPage(
          certificate: certificate, originSession: _session),
    ));
    if (saved == true) await _load();
  }

  Future<void> _toggleReminders(bool on) async {
    if (_togglingReminders) return;
    setState(() => _togglingReminders = true);
    var result = false;
    if (on) {
      final plan = planQualificationReminders(
        _overview?.evaluations ?? const [],
        now: DateTime.now(),
        english: AppLanguageController.isEnglish,
      );
      if (!mounted || !_session.isCurrent) return;
      result = await _reminders.enable(plan);
      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Brak zgody na powiadomienia — włącz je w ustawieniach '
                'telefonu. Baner w menu Spawacz ostrzega nadal.',
            en: 'Notifications not allowed — enable them in the phone '
                'settings. The banner in the Welder menu still warns you.',
          )),
        ));
      }
    } else {
      if (!mounted || !_session.isCurrent) return;
      await _reminders.disable();
    }
    if (!mounted || !_session.isCurrent) return;
    setState(() {
      _remindersOn = result;
      _togglingReminders = false;
    });
  }

  Future<void> _recordConfirmation(CertificateEvaluation e) async {
    final c = e.certificate;
    final asme = c.standard == QualificationStandard.asmeIx;
    final input = await _showOwnedDialog<_ConfirmationInput>(
      context: context,
      builder: (_) => _ConfirmationDialog(evaluation: e, session: _session),
    );
    if (input == null || !mounted) return;
    final picked = input.date;
    final byText = input.by;
    final notesText = input.notes;
    if (picked.isAfter(dateOnly(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Data potwierdzenia nie może być z przyszłości.',
          en: 'The confirmation date cannot be in the future.',
        )),
      ));
      return;
    }
    final test = c.testDate;
    if (test != null && picked.isBefore(dateOnly(test))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Potwierdzenie nie może być wcześniejsze niż egzamin '
              '(${formatIsoDate(test)}).',
          en: 'The confirmation cannot be earlier than the test '
              '(${formatIsoDate(test)}).',
        )),
      ));
      return;
    }
    // Termin łańcucha w dniu podpisu. Podpis po terminie nie przywraca
    // wygasłego uprawnienia (ISO 9606-1 §9.2; ASME — odnowienie QW-322.2).
    final onDay = evaluateCertificate(c, asOf: picked);
    final deadline = onDay.continuityDeadline;
    if (deadline != null && picked.isAfter(deadline)) {
      final keep = await _showOwnedDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(context.tr(
              pl: 'Potwierdzenie po terminie',
              en: 'Confirmation after the deadline')),
          content: Text(asme
              ? context.tr(
                  pl: 'Ciągłość WPQ skończyła się ${formatIsoDate(deadline)}. '
                      'Wpis z ${formatIsoDate(picked)} jej nie przywraca — '
                      'potrzebne odnowienie (ASME IX QW-322.2). Zapisać wpis '
                      'w historii mimo to?',
                  en: 'WPQ continuity ended on ${formatIsoDate(deadline)}. '
                      'A record dated ${formatIsoDate(picked)} does not '
                      'restore it — renewal is needed (ASME IX QW-322.2). '
                      'Save the record to the history anyway?')
              : context.tr(
                  pl: 'Termin potwierdzenia minął ${formatIsoDate(deadline)} — '
                      'uprawnienie wygasło (EN ISO 9606-1 §9.2). Podpis z '
                      '${formatIsoDate(picked)} go nie przywraca: potrzebny '
                      'nowy egzamin. Zapisać wpis w historii mimo to?',
                  en: 'The confirmation deadline passed on '
                      '${formatIsoDate(deadline)} — the qualification lapsed '
                      '(EN ISO 9606-1 §9.2). A signature dated '
                      '${formatIsoDate(picked)} does not restore it: a new '
                      'test is needed. Save the entry to the history anyway?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(
                  context.tr(pl: 'Zapisz do historii', en: 'Save to history')),
            ),
          ],
        ),
      );
      if (keep != true) return;
    }
    if (!mounted || !_session.isCurrent) return;
    await _service.addConfirmation(c,
        date: picked, confirmedBy: byText, notes: notesText);
    await _load();
  }

  Future<void> _deleteConfirmation(CertificateConfirmation k) async {
    final ok = await _showOwnedDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(
            pl: 'Usunąć wpis z historii?', en: 'Delete the history entry?')),
        content: Text(context.tr(
          pl: 'Potwierdzenie z ${formatIsoDate(k.date)} zniknie z łańcucha '
              'ciągłości. Usuwaj tylko błędne wpisy (literówka w dacie).',
          en: 'The confirmation dated ${formatIsoDate(k.date)} leaves the '
              'continuity chain. Delete only wrong entries (a typo).',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kFail),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted || !_session.isCurrent) return;
    await _service.deleteConfirmation(k);
    await _load();
  }

  Future<void> _delete(WelderCertificate c) async {
    final ok = await _showOwnedDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(
            pl: 'Usunąć certyfikat?', en: 'Delete the certificate?')),
        content: Text(context.tr(
          pl: 'Usuniemy wpis ${c.shortTitle(english: false)} i jego zdjęcie '
              'z telefonu. Spoiny w dzienniku zostają.',
          en: 'The entry ${c.shortTitle(english: true)} and its photo will '
              'be removed from this phone. Welds in the journal stay.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kFail),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted || !_session.isCurrent) return;
    await _service.delete(c);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _overview?.evaluations ?? const <CertificateEvaluation>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Uprawnienia spawacza', en: 'Welder qualifications')),
        actions: [
          HelpButton(help: kHelpCertificateRegister),
          PopupMenuButton<String>(
            tooltip: context.tr(pl: 'Eksport', en: 'Export'),
            icon: const Icon(Icons.ios_share),
            enabled: items.isNotEmpty,
            onSelected: (v) async {
              try {
                if (v == 'pdf') {
                  await QualificationExport.sharePdf(items,
                      mayShare: () => mounted && _session.isCurrent);
                } else {
                  await QualificationExport.shareCsv(items,
                      mayShare: () => mounted && _session.isCurrent);
                }
              } catch (e) {
                debugPrint('[qualification] export failed: $e');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf',
                child: Text(context.tr(
                    pl: 'PDF: rejestr i log ciągłości',
                    en: 'PDF: register and continuity log')),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Text(context.tr(
                    pl: 'CSV (Excel): rejestr', en: 'CSV (Excel): register')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _loadFailed ? null : () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj certyfikat', en: 'Add certificate')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  context.tr(
                    pl: 'EN ISO 9606-1 i ASME IX (WPQ) — uprawnienia '
                        'SPAWACZA. WPQR / PQR to kwalifikacja PROCEDURY i '
                        'należy do WPS (Biblioteka WPS).',
                    en: 'EN ISO 9606-1 and ASME IX (WPQ) — WELDER '
                        'qualifications. A WPQR / PQR qualifies the '
                        'PROCEDURE and belongs to the WPS (WPS library).',
                  ),
                  style: const TextStyle(fontSize: 12, color: kTextSec),
                ),
                const SizedBox(height: 12),
                if (_loadFailed)
                  _Notice(
                    color: kFail,
                    text: context.tr(
                      pl: 'Nie udało się odczytać rejestru z bazy. Zamknij '
                          'i otwórz ekran ponownie.',
                      en: 'Could not read the register from the database. '
                          'Close and reopen this screen.',
                    ),
                  ),
                QualificationBanner(
                  overview: _overview,
                  padding: const EdgeInsets.only(bottom: 12),
                ),
                _RemindersTile(
                  supported: _reminders.supported,
                  on: _remindersOn,
                  busy: _togglingReminders,
                  onChanged: _toggleReminders,
                ),
                const SizedBox(height: 12),
                if (items.isEmpty && !_loadFailed)
                  _Notice(
                    color: kTextSec,
                    text: context.tr(
                      pl: 'Brak certyfikatów. Dodaj swoje uprawnienia — '
                          'aplikacja przypilnuje daty ważności i terminu '
                          'potwierdzenia co 6 miesięcy.',
                      en: 'No certificates yet. Add your qualifications — '
                          'the app will track the expiry date and the '
                          '6-month confirmation deadline.',
                    ),
                  ),
                for (final e in items)
                  _CertificateCard(
                    key: ValueKey('cert-${e.certificate.id}'),
                    evaluation: e,
                    onEdit: () => _openEditor(e.certificate),
                    onConfirm: () => _recordConfirmation(e),
                    onDelete: () => _delete(e.certificate),
                    onDeleteConfirmation: _deleteConfirmation,
                  ),
                const SizedBox(height: 8),
                const _RulesCard(),
              ],
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final String text;
  const _Notice({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 13)),
      );
}

class _RemindersTile extends StatelessWidget {
  final bool supported;
  final bool on;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _RemindersTile({
    required this.supported,
    required this.on,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!supported) {
      return _Notice(
        color: kTextSec,
        text: context.tr(
          pl: 'Przypomnienia systemowe działają na Androidzie i iOS. Tutaj '
              'o terminach ostrzega baner w menu Spawacz.',
          en: 'System reminders work on Android and iOS. Here the banner '
              'in the Welder menu warns you about deadlines.',
        ),
      );
    }
    // Material, nie Container z kolorem: ListTile rysuje tło i „atrament"
    // na najbliższym Material — kolorowy DecoratedBox by je zasłonił.
    return Material(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: const ValueKey('qualification-reminders-switch'),
        value: on,
        onChanged: busy ? null : onChanged,
        title: Text(context.tr(
            pl: 'Przypomnienia o terminach', en: 'Deadline reminders')),
        subtitle: Text(context.tr(
          pl: 'Powiadomienie 30 i 7 dni przed datą ważności i przed '
              'terminem potwierdzenia 6-miesięcznego.',
          en: 'A notification 30 and 7 days before the expiry date and '
              'before the 6-month confirmation deadline.',
        )),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final CertificateEvaluation evaluation;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;
  final VoidCallback onDelete;
  final ValueChanged<CertificateConfirmation> onDeleteConfirmation;

  const _CertificateCard({
    super.key,
    required this.evaluation,
    required this.onEdit,
    required this.onConfirm,
    required this.onDelete,
    required this.onDeleteConfirmation,
  });

  Color get _accent => switch (evaluation.state.severity) {
        0 => kPass,
        1 => kWarn,
        _ => kFail,
      };

  String _statusLine(BuildContext context) {
    final e = evaluation;
    final english = context.language == AppLanguage.en;
    if (e.state != QualificationState.valid) {
      return qualificationWarningText(e, english: english);
    }
    final parts = <String>[
      context.tr(pl: 'Ważny', en: 'Valid'),
      if (e.expiryDate != null)
        context.tr(
          pl: 'do ${formatIsoDate(e.expiryDate!)}',
          en: 'until ${formatIsoDate(e.expiryDate!)}',
        ),
      if (e.continuityDeadline != null)
        context.tr(
          pl: 'następny termin 6 mies.: ${formatIsoDate(e.continuityDeadline!)}',
          en: 'next 6-month deadline: ${formatIsoDate(e.continuityDeadline!)}',
        ),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final e = evaluation;
    final c = e.certificate;
    final english = context.language == AppLanguage.en;
    final asme = c.standard == QualificationStandard.asmeIx;
    final scope = <String>[
      if (c.processes.trim().isNotEmpty)
        context.tr(
            pl: 'Proces ${c.processes.trim()}',
            en: 'Process ${c.processes.trim()}'),
      if (c.materialGroup.trim().isNotEmpty)
        context.tr(
            pl: 'Grupa ${c.materialGroup.trim()}',
            en: 'Group ${c.materialGroup.trim()}'),
      if (c.thicknessMinMm != null || c.thicknessMaxMm != null)
        't ${describeRange(c.thicknessMinMm, c.thicknessMaxMm, 'mm')}',
      if (c.diameterMinMm != null || c.diameterMaxMm != null)
        'D ${describeRange(c.diameterMinMm, c.diameterMaxMm, 'mm')}',
      if (c.positions.trim().isNotEmpty) c.positions.trim(),
      if (c.jointKinds.isNotEmpty) encodeJointKinds(c.jointKinds),
      if (c.filler.trim().isNotEmpty) c.filler.trim(),
    ];
    final details = <String>[
      if (c.testDate != null)
        context.tr(
            pl: 'Egzamin: ${formatIsoDate(c.testDate!)}',
            en: 'Test: ${formatIsoDate(c.testDate!)}'),
      if (c.welderStamp != null)
        context.tr(
            pl: 'Stempel: ${c.welderStamp}', en: 'Stamp: ${c.welderStamp}'),
      if (c.examiner != null)
        context.tr(
            pl: 'Egzaminator: ${c.examiner}', en: 'Examiner: ${c.examiner}'),
      if (c.lastConfirmedDate != null)
        asme
            ? context.tr(
                pl:
                    'Ciągłość potwierdzona: ${formatIsoDate(c.lastConfirmedDate!)}',
                en:
                    'Continuity confirmed: ${formatIsoDate(c.lastConfirmedDate!)}')
            : context.tr(
                pl: 'Ostatnie potwierdzenie: ${formatIsoDate(c.lastConfirmedDate!)}',
                en: 'Last confirmation: ${formatIsoDate(c.lastConfirmedDate!)}'),
      e.lastJournalWeld != null
          ? context.tr(
              pl: 'Ostatnia spoina tym procesem (dziennik): '
                  '${formatIsoDate(e.lastJournalWeld!)}',
              en: 'Last weld with this process (journal): '
                  '${formatIsoDate(e.lastJournalWeld!)}')
          : context.tr(
              pl: 'Brak spoin tym procesem w dzienniku',
              en: 'No welds with this process in the journal'),
      if (c.prolongation != null &&
          c.standard == QualificationStandard.iso9606_1)
        context.tr(
          pl: 'Przedłużanie: EN ISO 9606-1 §9.3 ${c.prolongation!.code.toLowerCase()})',
          en: 'Prolongation: EN ISO 9606-1 §9.3 ${c.prolongation!.code.toLowerCase()})',
        ),
    ];
    final photo = c.photoPath;
    final showPhoto = !kIsWeb &&
        photo != null &&
        RegExp(r'\.(jpe?g|png|webp|heic|gif)$', caseSensitive: false)
            .hasMatch(photo);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                e.state.severity == 0
                    ? Icons.verified_outlined
                    : (e.state.severity == 1
                        ? Icons.warning_amber_rounded
                        : Icons.gpp_bad_outlined),
                color: _accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.shortTitle(english: english),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Text(
              _statusLine(context),
              style: TextStyle(
                  color: _accent, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (scope.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child:
                  Text(scope.join(' · '), style: const TextStyle(fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text(details.join('\n'),
                style: const TextStyle(
                    fontSize: 12, color: kTextSec, height: 1.4)),
          ),
          if (e.continuityUnknown)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(
                context.tr(
                  pl: 'Uzupełnij datę egzaminu albo ostatniego potwierdzenia — '
                      'bez niej nie da się policzyć terminu 6-miesięcznego.',
                  en: 'Add the test date or the last confirmation — without it '
                      'the 6-month deadline cannot be computed.',
                ),
                style: const TextStyle(fontSize: 12, color: kWarn),
              ),
            ),
          if (e.lateConfirmation != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(
                context.tr(
                  pl: 'Potwierdzenie z ${formatIsoDate(e.lateConfirmation!)} '
                      'podpisano po terminie '
                      '${formatIsoDate(e.continuityDeadline!)} — nie '
                      'przywróciło uprawnienia. Potrzebny nowy egzamin.',
                  en: 'The confirmation dated '
                      '${formatIsoDate(e.lateConfirmation!)} was signed after '
                      'the ${formatIsoDate(e.continuityDeadline!)} deadline — '
                      'it did not restore the qualification. A new test is '
                      'needed.',
                ),
                style: const TextStyle(fontSize: 12, color: kFail),
              ),
            ),
          if (c.confirmations.isNotEmpty)
            Material(
              // ListTile rysuje tło i „atrament" na najbliższym Material —
              // kolorowy Container karty by je zasłonił.
              type: MaterialType.transparency,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: ValueKey('cert-history-${c.id}'),
                  tilePadding: const EdgeInsets.only(right: 8),
                  title: Text(
                    context.tr(
                        pl: 'Historia potwierdzeń (${c.confirmations.length})',
                        en: 'Confirmation history (${c.confirmations.length})'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  children: [
                    for (final k in c.confirmations.reversed)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(right: 0),
                        title: Text(formatIsoDate(k.date)),
                        subtitle: Text(
                          [
                            if (k.confirmedBy.trim().isNotEmpty) k.confirmedBy,
                            if (k.notes.trim().isNotEmpty) k.notes,
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: context.tr(
                              pl: 'Usuń błędny wpis', en: 'Delete wrong entry'),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => onDeleteConfirmation(k),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (showPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(photo),
                  height: 120,
                  fit: BoxFit.cover,
                  cacheHeight: 360,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          Wrap(
            spacing: 4,
            children: [
              if (e.rule != ContinuityRule.none)
                TextButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text(asme
                      ? context.tr(
                          pl: 'Wpis ciągłości', en: 'Continuity record')
                      : context.tr(
                          pl: 'Potwierdzenie 6 mies.',
                          en: '6-month confirmation')),
                ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.tr(pl: 'Edytuj', en: 'Edit')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(context.tr(
            pl: 'Jak liczymy terminy', en: 'How deadlines are computed')),
        children: [
          Text(
            context.tr(
              pl: '• EN ISO 9606-1 §9.2: co 6 miesięcy koordynator spawania '
                  '(albo egzaminator) potwierdza, że pracowałeś w zakresie '
                  'uprawnienia. Termin liczymy z historii potwierdzeń: '
                  'egzamin → kolejne podpisy, każdy w terminie przesuwa go '
                  'o 6 miesięcy. Podpis po terminie nie przywraca wygasłego '
                  'certyfikatu (potrzebny nowy egzamin), a nowe potwierdzenie '
                  'nie zmienia oceny dawnych spoin. Spoiny w dzienniku są '
                  'dowodem, ale nie zastępują podpisu.\n'
                  '• EN ISO 9606-1 §9.3 — przedłużenie ważności: a) ponowny '
                  'egzamin co 3 lata; b) co 2 lata: dwie spoiny z ostatnich '
                  '6 miesięcy zbadane RT/UT lub niszcząco; c) ważność ciągła '
                  'przy potwierdzeniach, u tego samego producenta z ISO 3834-2 '
                  'lub -3 (wg załącznika ZA nie dla PED kat. II–IV). Sposób '
                  'jest wpisany na certyfikacie.\n'
                  '• ASME IX QW-322.1(a): uprawnienie do procesu wygasa, gdy '
                  'przez 6 miesięcy nie spawałeś tym procesem. Każda spoina '
                  'w dzienniku (z Twoim stemplem) albo wpis ciągłości '
                  'przesuwa termin o 6 miesięcy od swojej daty. Przerwy nie '
                  'da się „nadrobić" późniejszą spoiną — potrzebne odnowienie '
                  '(QW-322.2).\n'
                  '• Status „wymaga potwierdzenia" pojawia się 30 dni przed '
                  'terminem. To pomoc, nie dokument — wiążący jest certyfikat '
                  'i podpisy na nim.',
              en: '• EN ISO 9606-1 §9.2: every 6 months the welding '
                  'coordinator (or examiner) confirms you worked within the '
                  'qualification range. The deadline comes from the '
                  'confirmation history: test → each signature in time moves '
                  'it by 6 months. A signature after the deadline does not '
                  'restore a lapsed certificate (a new test is needed), and a '
                  'new confirmation does not change how older welds are '
                  'judged. Journal welds are evidence but do not replace the '
                  'signature.\n'
                  '• EN ISO 9606-1 §9.3 — prolongation: a) re-test every '
                  '3 years; b) every 2 years: two welds from the last 6 months '
                  'tested by RT/UT or destructively; c) continuous validity '
                  'with confirmations, same manufacturer with ISO 3834-2 or -3 '
                  '(per Annex ZA not for PED cat. II–IV). The method is '
                  'written on the certificate.\n'
                  '• ASME IX QW-322.1(a): the qualification for a process '
                  'expires when you have not welded with it for 6 months. '
                  'Every journal weld (with your stamp) or continuity record '
                  'moves the deadline to 6 months after its date. A gap '
                  'cannot be "repaired" by a later weld — renewal is needed '
                  '(QW-322.2).\n'
                  '• "Confirmation due" shows 30 days before the deadline. '
                  'This is an aid, not a document — the certificate and its '
                  'signatures are what counts.',
            ),
            style:
                const TextStyle(fontSize: 12.5, color: kTextSec, height: 1.45),
          ),
          const SizedBox(height: 8),
        ],
      );
}

/// Wynik dialogu potwierdzenia: data podpisu, kto, uwagi.
class _ConfirmationInput {
  final DateTime date;
  final String by;
  final String notes;
  const _ConfirmationInput(this.date, this.by, this.notes);
}

/// Dialog wpisu potwierdzenia — własny stan, żeby pola tekstowe żyły tak
/// długo jak dialog (także w animacji zamykania).
class _ConfirmationDialog extends StatefulWidget {
  final CertificateEvaluation evaluation;
  final LocalRecordSession session;
  const _ConfirmationDialog({required this.evaluation, required this.session});

  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  DateTime _picked = dateOnly(DateTime.now());
  final _by = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _by.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evaluation;
    final asme = e.certificate.standard == QualificationStandard.asmeIx;
    return AlertDialog(
      scrollable: true,
      title: Text(asme
          ? context.tr(pl: 'Wpis ciągłości WPQ', en: 'WPQ continuity record')
          : context.tr(
              pl: 'Potwierdzenie 6-miesięczne', en: '6-month confirmation')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            asme
                ? context.tr(
                    pl: 'Wpisz datę potwierdzenia ciągłości przez '
                        'pracodawcę (np. z rejestru WPQ). Spoiny tym '
                        'procesem zapisane w dzienniku liczą się same '
                        '(ASME IX QW-322.1).',
                    en: 'Enter the date the employer confirmed '
                        'continuity (e.g. from the WPQ log). Welds with '
                        'this process in the journal count automatically '
                        '(ASME IX QW-322.1).',
                  )
                : context.tr(
                    pl: 'Wpisz datę podpisu koordynatora spawania albo '
                        'egzaminatora na certyfikacie (EN ISO 9606-1 '
                        '§9.2). Aplikacja nie zastępuje tego podpisu — '
                        'tylko pilnuje terminu. Wpis trafia do historii; '
                        'wcześniejsze potwierdzenia zostają.',
                    en: 'Enter the date the welding coordinator or '
                        'examiner signed the certificate (EN ISO 9606-1 '
                        '§9.2). The app does not replace that signature '
                        '— it only tracks the deadline. The entry goes '
                        'to the history; earlier confirmations stay.',
                  ),
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          if (e.lastJournalWeld != null) ...[
            const SizedBox(height: 10),
            Text(
              context.tr(
                pl: 'Ostatnia spoina tym procesem w dzienniku: '
                    '${formatIsoDate(e.lastJournalWeld!)}.',
                en: 'Last weld with this process in the journal: '
                    '${formatIsoDate(e.lastJournalWeld!)}.',
              ),
              style: const TextStyle(fontSize: 12.5, color: kTextSec),
            ),
          ],
          const SizedBox(height: 14),
          DateField(
            session: widget.session,
            label: context.tr(pl: 'Data', en: 'Date'),
            value: _picked,
            onChanged: (d) {
              if (d != null) setState(() => _picked = d);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('confirmation-by'),
            controller: _by,
            decoration: InputDecoration(
              labelText: context.tr(pl: 'Kto potwierdził', en: 'Confirmed by'),
              hintText: context.tr(
                  pl: 'koordynator spawania / egzaminator',
                  en: 'welding coordinator / examiner'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: InputDecoration(
              labelText: context.tr(pl: 'Uwagi', en: 'Notes'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, _ConfirmationInput(_picked, _by.text, _notes.text)),
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}
