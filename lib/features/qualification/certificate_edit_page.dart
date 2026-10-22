// Formularz jednego certyfikatu uprawnień spawacza.
//
// v25: pole „Stempel spawacza” (certyfikat bez stempla obejmuje tylko
// właściciela telefonu), walidacja dat (egzamin ≤ dziś, potwierdzenie
// w [egzamin, dziś], ostrzeżenie o potwierdzeniu po terminie), strażnik
// „Porzucić zmiany?” przy wyjściu. Potwierdzenia 6-miesięczne żyją
// w historii (rejestr → „Potwierdzenie 6 mies.”); tu tylko pierwsze przy
// nowym certyfikacie.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/qualification/certificate_status.dart';
import '../../domain/qualification/qualification_dates.dart';
import '../../domain/qualification/weld_process.dart';
import '../../domain/qualification/welder_certificate.dart';
import '../../i18n/app_language.dart';
import '../../services/heat_photo_storage.dart';
import '../../services/welder_identity.dart';
import '../../services/welder_qualification_service.dart';
import '../../theme/app_theme.dart';
import 'form_bits.dart';
import '../../widgets/local_record_scope.dart';

class CertificateEditPage extends StatelessWidget {
  const CertificateEditPage(
      {super.key, this.certificate, this.initial, this.originSession});
  final WelderCertificate? certificate;
  final WelderCertificate? initial;
  final LocalRecordSession? originSession;
  @override
  Widget build(BuildContext context) => LocalRecordScope(
      restartOnAccountChange: false,
      originSession: originSession,
      builder: (_, session) => _CertificateEditPage(
          certificate: certificate, initial: initial, session: session));
}

class _CertificateEditPage extends StatefulWidget {
  const _CertificateEditPage(
      {this.certificate, this.initial, required this.session});
  final WelderCertificate? certificate;
  final WelderCertificate? initial;
  final LocalRecordSession session;
  @override
  State<_CertificateEditPage> createState() => _CertificateEditPageState();
}

class _CertificateEditPageState extends State<_CertificateEditPage> {
  LocalRecordSession get _session => widget.session;
  Future<T?> _showOwnedDialog<T>(
          {required BuildContext context, required WidgetBuilder builder}) =>
      showDialog<T>(
          context: context,
          builder: (dialogContext) => LocalRecordScope(
              restartOnAccountChange: false,
              originSession: _session,
              builder: (_, __) => builder(dialogContext)));

  final _formKey = GlobalKey<FormState>();

  late QualificationStandard _standard;
  late final TextEditingController _standardLabel;
  late final TextEditingController _certNo;
  late final TextEditingController _examiner;
  late final TextEditingController _stamp;
  DateTime? _testDate;
  DateTime? _expiryDate;
  DateTime? _confirmedDate;
  IsoProlongation? _prolongation;
  late final TextEditingController _processes;
  late final TextEditingController _group;
  late final TextEditingController _tMin;
  late final TextEditingController _tMax;
  late final TextEditingController _dMin;
  late final TextEditingController _dMax;
  late final TextEditingController _positions;
  late final TextEditingController _filler;
  late final TextEditingController _notes;
  late Set<WeldJointKind> _kinds;
  String? _photoPath;
  bool _saving = false;
  bool _closing = false;

  /// Formularz przy otwarciu — strażnik porzucenia porównuje z nim.
  late final String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    final existing = widget.certificate;
    final draft = existing == null ? widget.initial : null;
    final c = existing ?? draft;
    _standard = c?.standard ?? QualificationStandard.iso9606_1;
    _standardLabel = TextEditingController(text: c?.standardLabel ?? '');
    _certNo = TextEditingController(text: c?.certNo ?? '');
    _examiner = TextEditingController(text: c?.examiner ?? '');
    final draftStamp = draft?.welderStamp?.trim() ?? '';
    _stamp = TextEditingController(
        text: existing == null
            ? (draftStamp.isNotEmpty
                ? draftStamp
                : (WelderIdentityService.instance.current?.stamp ?? ''))
            : (existing.welderStamp ?? ''));
    _testDate = c?.testDate;
    _expiryDate = c?.expiryDate;
    _confirmedDate = c?.lastConfirmedDate;
    _prolongation = c?.prolongation;
    _processes = TextEditingController(text: c?.processes ?? '');
    _group = TextEditingController(text: c?.materialGroup ?? '');
    _tMin = TextEditingController(text: formatDecimalField(c?.thicknessMinMm));
    _tMax = TextEditingController(text: formatDecimalField(c?.thicknessMaxMm));
    _dMin = TextEditingController(text: formatDecimalField(c?.diameterMinMm));
    _dMax = TextEditingController(text: formatDecimalField(c?.diameterMaxMm));
    _positions = TextEditingController(text: c?.positions ?? '');
    _filler = TextEditingController(text: c?.filler ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _kinds = {...?c?.jointKinds};
    _photoPath = existing?.photoPath;
    // Szkic: formularz od początku „zmieniony” — wyjście bez zapisu pyta.
    _initialSnapshot = draft == null ? _snapshot() : '';
  }

  String _snapshot() => [
        _standard.code,
        _prolongation?.code ?? '',
        _testDate?.toIso8601String() ?? '',
        _expiryDate?.toIso8601String() ?? '',
        _confirmedDate?.toIso8601String() ?? '',
        _photoPath ?? '',
        encodeJointKinds(_kinds),
        for (final c in _controllers) c.text,
      ].join('\u0001');

  List<TextEditingController> get _controllers => [
        _standardLabel,
        _certNo,
        _examiner,
        _stamp,
        _processes,
        _group,
        _tMin,
        _tMax,
        _dMin,
        _dMax,
        _positions,
        _filler,
        _notes,
      ];

  bool get _dirty => _snapshot() != _initialSnapshot;

  Future<void> _handleClose() async {
    if (_saving || _closing) return;
    final nav = Navigator.of(context);
    if (!_dirty) {
      nav.pop();
      return;
    }
    _closing = true;
    final discard = await _showOwnedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Porzucić zmiany?', en: 'Discard changes?')),
        content: Text(ctx.tr(
            pl: 'Wpisane dane certyfikatu zostaną utracone.',
            en: 'The certificate data you entered will be lost.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr(pl: 'Wróć do edycji', en: 'Keep editing'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr(pl: 'Porzuć', en: 'Discard'))),
        ],
      ),
    );
    _closing = false;
    if (discard == true && mounted) nav.pop();
  }

  @override
  void dispose() {
    for (final ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      // Kopia do <documents>/heat_photos — katalogu, który obejmuje kopia
      // zapasowa; ścieżka z pickera znika przy czyszczeniu pamięci podręcznej.
      final stored = await persistPickedHeatPhoto(path);
      if (!mounted || !_session.isCurrent) return;
      setState(() => _photoPath = stored);
    } catch (_) {
      if (!mounted || !_session.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie udało się skopiować zdjęcia.',
          en: 'Could not copy the photo.',
        )),
      ));
    }
  }

  String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tMin = parseDecimalField(_tMin.text);
    final tMax = parseDecimalField(_tMax.text);
    final dMin = parseDecimalField(_dMin.text);
    final dMax = parseDecimalField(_dMax.text);
    final today = dateOnly(DateTime.now());
    final stampText = _stamp.text.trim().toUpperCase();
    final problem =
        rangeProblem(context, tMin, tMax, pl: 'Grubość', en: 'Thickness') ??
            (stampText.isNotEmpty && !kStampRegex.hasMatch(stampText)
                ? context.tr(
                    pl: 'Stempel: tylko A–Z, 0–9, „-”, 2–12 znaków.',
                    en: 'Stamp: only A–Z, 0–9, "-", 2–12 characters.')
                : null) ??
            (_testDate != null && _testDate!.isAfter(today)
                ? context.tr(
                    pl: 'Data egzaminu nie może być z przyszłości.',
                    en: 'The test date cannot be in the future.')
                : null) ??
            (_confirmedDate != null && _confirmedDate!.isAfter(today)
                ? context.tr(
                    pl: 'Potwierdzenie nie może być z przyszłości.',
                    en: 'The confirmation cannot be in the future.')
                : null) ??
            (_confirmedDate != null &&
                    _testDate != null &&
                    _confirmedDate!.isBefore(_testDate!)
                ? context.tr(
                    pl: 'Potwierdzenie nie może być wcześniejsze niż egzamin.',
                    en: 'The confirmation cannot be earlier than the test.')
                : null) ??
            rangeProblem(context, dMin, dMax, pl: 'Średnica', en: 'Diameter') ??
            (_testDate != null &&
                    _expiryDate != null &&
                    _expiryDate!.isBefore(_testDate!)
                ? context.tr(
                    pl: 'Data ważności jest wcześniejsza niż data egzaminu.',
                    en: 'The expiry date is before the test date.')
                : null);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final old = widget.certificate;
    // Pierwsze potwierdzenie nowego certyfikatu wpisane po terminie — nie
    // przywraca ważności (ISO 9606-1 §9.2); ostrzegamy, zapis do historii.
    final firstConfirmation = old == null ? _confirmedDate : null;
    if (firstConfirmation != null && _testDate != null) {
      final deadline =
          addMonthsClamped(dateOnly(_testDate!), kContinuityMonths);
      if (firstConfirmation.isAfter(deadline)) {
        final keep = await _showOwnedDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr(
                pl: 'Potwierdzenie po terminie',
                en: 'Confirmation after the deadline')),
            content: Text(ctx.tr(
                pl: 'Termin potwierdzenia minął ${formatIsoDate(deadline)} — '
                    'podpis z ${formatIsoDate(firstConfirmation)} nie '
                    'przywraca uprawnienia (EN ISO 9606-1 §9.2). Zapisać?',
                en: 'The confirmation deadline passed on '
                    '${formatIsoDate(deadline)} — a signature dated '
                    '${formatIsoDate(firstConfirmation)} does not restore the '
                    'qualification (EN ISO 9606-1 §9.2). Save?')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tr(pl: 'Popraw', en: 'Fix'))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr(pl: 'Zapisz', en: 'Save'))),
            ],
          ),
        );
        if (keep != true || !mounted) return;
      }
    }
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final certificate = WelderCertificate(
      id: old?.id ?? const Uuid().v4(),
      welderStamp: stampText.isEmpty ? null : stampText,
      standard: _standard,
      standardLabel: _standard == QualificationStandard.other
          ? _text(_standardLabel)
          : null,
      certNo: _text(_certNo),
      examiner: _text(_examiner),
      testDate: _testDate,
      expiryDate: _expiryDate,
      // Potwierdzenia żyją w historii; tu tylko skrót (ostatnie).
      lastConfirmedDate: old == null ? _confirmedDate : old.lastConfirmedDate,
      confirmations: old?.confirmations ?? const [],
      prolongation:
          _standard == QualificationStandard.iso9606_1 ? _prolongation : null,
      processes: _processes.text.trim(),
      materialGroup: _group.text.trim(),
      thicknessMinMm: tMin,
      thicknessMaxMm: tMax,
      diameterMinMm: dMin,
      diameterMaxMm: dMax,
      positions: _positions.text.trim(),
      filler: _filler.text.trim(),
      jointKinds: _kinds,
      notes: _notes.text.trim(),
      photoPath: _photoPath,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (!mounted || !_session.isCurrent) return;
      await WelderQualificationService.instance.save(certificate);
      _session.requireCurrent();
      if (firstConfirmation != null) {
        await WelderQualificationService.instance
            .addConfirmation(certificate, date: firstConfirmation);
      }
      _session.requireCurrent();
      // Zastąpione / usunięte zdjęcie — skasuj starą kopię z heat_photos.
      final oldPhoto = old?.photoPath;
      if (oldPhoto != null && oldPhoto != _photoPath) {
        await WelderQualificationService.instance.deleteOwnedFile(oldPhoto);
      }
    } catch (_) {
      if (!mounted || !_session.isCurrent) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie udało się zapisać certyfikatu.',
          en: 'Could not save the certificate.',
        )),
      ));
      return;
    }
    if (!mounted || !_session.isCurrent) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final iso = _standard == QualificationStandard.iso9606_1;
    final english = context.language == AppLanguage.en;
    return PopScope<Object?>(
      // Decyzja w chwili wyjścia, na świeżym stanie (pola tekstowe nie
      // przebudowują strony).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.tr(pl: 'Wstecz', en: 'Back'),
            icon: const BackButtonIcon(),
            onPressed: _handleClose,
          ),
          title: Text(widget.certificate == null
              ? context.tr(pl: 'Nowy certyfikat', en: 'New certificate')
              : context.tr(pl: 'Certyfikat', en: 'Certificate')),
          actions: [
            IconButton(
              tooltip: context.tr(pl: 'Zapisz', en: 'Save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              FormSectionTitle(context.tr(pl: 'Certyfikat', en: 'Certificate')),
              DropdownButtonFormField<QualificationStandard>(
                initialValue: _standard,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Norma', en: 'Standard'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final s in QualificationStandard.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(english ? s.labelEn : s.labelPl),
                    ),
                ],
                onChanged: (v) => setState(
                    () => _standard = v ?? QualificationStandard.iso9606_1),
              ),
              if (_standard == QualificationStandard.other) ...[
                const SizedBox(height: 12),
                PlainField(
                  controller: _standardLabel,
                  label: context.tr(pl: 'Nazwa normy', en: 'Standard name'),
                  helper: context.tr(
                    pl: 'np. AWS D1.1, EN ISO 9606-2. Aplikacja pilnuje wtedy '
                        'tylko daty ważności.',
                    en: 'e.g. AWS D1.1, EN ISO 9606-2. The app then tracks only '
                        'the expiry date.',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PlainField(
                controller: _certNo,
                label: context.tr(
                    pl: 'Nr certyfikatu / WPQ', en: 'Certificate / WPQ no.'),
                maxLength: 60,
              ),
              const SizedBox(height: 4),
              PlainField(
                controller: _stamp,
                label: context.tr(pl: 'Stempel spawacza', en: 'Welder stamp'),
                helper: context.tr(
                    pl: 'Czyj to certyfikat. Domyślnie Twój stempel z '
                        'tożsamości; pusty = Twój (nie obejmuje spoin innych '
                        'stempli brygady).',
                    en: 'Whose certificate this is. Defaults to your identity '
                        'stamp; empty = yours (does not cover welds of other '
                        'crew stamps).'),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _examiner,
                label: context.tr(
                    pl: 'Jednostka / egzaminator',
                    en: 'Examining body / examiner'),
                helper: context.tr(
                    pl: 'np. UDT, TÜV Rheinland — J. Nowak',
                    en: 'e.g. UDT, TÜV Rheinland — J. Smith'),
              ),
              FormSectionTitle(context.tr(pl: 'Daty', en: 'Dates')),
              DateField(
                session: _session,
                label: context.tr(
                    pl: 'Data egzaminu (spawania złącza próbnego)',
                    en: 'Test date (test piece welded)'),
                value: _testDate,
                onChanged: (d) => setState(() => _testDate = d),
              ),
              const SizedBox(height: 12),
              DateField(
                session: _session,
                label: context.tr(pl: 'Ważny do', en: 'Valid until'),
                value: _expiryDate,
                helper: context.tr(
                  pl: 'Puste = bez daty końcowej (np. ISO 9606-1 §9.3 c albo WPQ '
                      'utrzymywane ciągłością).',
                  en: 'Empty = no end date (e.g. ISO 9606-1 §9.3 c or a WPQ kept '
                      'by continuity).',
                ),
                onChanged: (d) => setState(() => _expiryDate = d),
              ),
              const SizedBox(height: 12),
              if (widget.certificate == null)
                DateField(
                  session: _session,
                  label: iso
                      ? context.tr(
                          pl: 'Ostatnie potwierdzenie 6 mies. (§9.2)',
                          en: 'Last 6-month confirmation (§9.2)')
                      : context.tr(
                          pl: 'Ostatnie potwierdzenie ciągłości',
                          en: 'Last continuity confirmation'),
                  value: _confirmedDate,
                  helper: iso
                      ? context.tr(
                          pl: 'Data podpisu koordynatora spawania / '
                              'egzaminatora — pierwszy wpis historii. Kolejne '
                              'dodasz na liście („Potwierdzenie 6 mies.”).',
                          en: 'Date signed by the welding coordinator / '
                              'examiner — the first history entry. Add more '
                              'on the list ("6-month confirmation").')
                      : context.tr(
                          pl: 'Spoiny z dziennika tym procesem liczą się same.',
                          en: 'Journal welds with this process count '
                              'automatically.'),
                  onChanged: (d) => setState(() => _confirmedDate = d),
                )
              else
                Text(
                  context.tr(
                    pl: 'Potwierdzeń w historii: '
                        '${widget.certificate!.confirmations.length}'
                        '${widget.certificate!.lastConfirmedDate == null ? '' : ' (ostatnie ${formatIsoDate(widget.certificate!.lastConfirmedDate!)})'}. '
                        'Nowe potwierdzenie dodasz na liście — „Potwierdzenie '
                        '6 mies.”; dawne zostają w łańcuchu.',
                    en: 'Confirmations in the history: '
                        '${widget.certificate!.confirmations.length}'
                        '${widget.certificate!.lastConfirmedDate == null ? '' : ' (last ${formatIsoDate(widget.certificate!.lastConfirmedDate!)})'}. '
                        'Add a new one on the list — "6-month confirmation"; '
                        'older ones stay in the chain.',
                  ),
                  style: const TextStyle(fontSize: 12, color: kTextSec),
                ),
              if (iso) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<IsoProlongation?>(
                  initialValue: _prolongation,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Przedłużanie (ISO 9606-1 §9.3)',
                        en: 'Prolongation (ISO 9606-1 §9.3)'),
                    helperText: context.tr(
                        pl: 'Informacyjnie — tak, jak wpisano na certyfikacie.',
                        en: 'For information — as written on the certificate.'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<IsoProlongation?>(
                      value: null,
                      child:
                          Text(context.tr(pl: 'Nie podano', en: 'Not given')),
                    ),
                    DropdownMenuItem(
                      value: IsoProlongation.a,
                      child: Text(context.tr(
                          pl: 'a) ponowny egzamin co 3 lata',
                          en: 'a) re-test every 3 years')),
                    ),
                    DropdownMenuItem(
                      value: IsoProlongation.b,
                      child: Text(context.tr(
                          pl: 'b) co 2 lata — 2 spoiny badane RT/UT/niszcząco',
                          en: 'b) every 2 years — 2 welds tested RT/UT/destr.')),
                    ),
                    DropdownMenuItem(
                      value: IsoProlongation.c,
                      child: Text(context.tr(
                          pl: 'c) ważność ciągła (ISO 3834-2/-3)',
                          en: 'c) continuous validity (ISO 3834-2/-3)')),
                    ),
                  ],
                  onChanged: (v) => setState(() => _prolongation = v),
                ),
              ],
              FormSectionTitle(context.tr(
                  pl: 'Zakres uprawnienia', en: 'Range of qualification')),
              Text(
                context.tr(
                  pl: 'Wpisz ZAKRES z certyfikatu (co jest objęte), nie '
                      'parametry złącza próbnego.',
                  en: 'Enter the RANGE from the certificate (what is covered), '
                      'not the test piece parameters.',
                ),
                style: const TextStyle(fontSize: 12, color: kTextSec),
              ),
              const SizedBox(height: 10),
              PlainField(
                controller: _processes,
                label: context.tr(pl: 'Proces(y)', en: 'Process(es)'),
                helper: context.tr(
                    pl: 'Numery EN ISO 4063, np. 141 albo 135, 136',
                    en: 'EN ISO 4063 numbers, e.g. 141 or 135, 136'),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _group,
                label:
                    context.tr(pl: 'Grupa materiałowa', en: 'Material group'),
                helper: context.tr(
                    pl: 'ISO/TR 15608 (np. 8.1) lub P-No (np. P8); kilka po '
                        'przecinku',
                    en: 'ISO/TR 15608 (e.g. 8.1) or P-No (e.g. P8); several '
                        'comma-separated'),
              ),
              const SizedBox(height: 12),
              FieldPair(
                left: DecimalField(
                    controller: _tMin,
                    label: context.tr(pl: 'Grubość od', en: 'Thickness from'),
                    unit: 'mm'),
                right: DecimalField(
                    controller: _tMax,
                    label: context.tr(pl: 'do', en: 'to'),
                    unit: 'mm'),
              ),
              const SizedBox(height: 12),
              FieldPair(
                left: DecimalField(
                    controller: _dMin,
                    label:
                        context.tr(pl: 'Średnica D od', en: 'Diameter D from'),
                    unit: 'mm'),
                right: DecimalField(
                    controller: _dMax,
                    label: context.tr(pl: 'do', en: 'to'),
                    unit: 'mm'),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _positions,
                label:
                    context.tr(pl: 'Pozycje (zakres)', en: 'Positions (range)'),
                helper: context.tr(
                    pl: 'np. PA, PC, PE, PF albo „wszystkie” — w jednym systemie '
                        '(ISO 6947 albo ASME)',
                    en: 'e.g. PA, PC, PE, PF or "all" — one system (ISO 6947 or '
                        'ASME)'),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _filler,
                label: context.tr(pl: 'Spoiwo / typ', en: 'Filler / type'),
                helper: context.tr(
                    pl: 'np. FM5, S 19 12 3 L albo F-No 6',
                    en: 'e.g. FM5, S 19 12 3 L or F-No 6'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr(pl: 'Rodzaj spoiny:', en: 'Weld type:'),
                      style: const TextStyle(color: kTextSec)),
                  for (final k in WeldJointKind.values)
                    FilterChip(
                      label: Text(k == WeldJointKind.bw
                          ? context.tr(pl: 'BW — czołowa', en: 'BW — butt')
                          : context.tr(
                              pl: 'FW — pachwinowa', en: 'FW — fillet')),
                      selected: _kinds.contains(k),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _kinds.add(k);
                        } else {
                          _kinds.remove(k);
                        }
                      }),
                    ),
                ],
              ),
              FormSectionTitle(context.tr(pl: 'Inne', en: 'Other')),
              PlainField(
                controller: _notes,
                label: context.tr(pl: 'Uwagi', en: 'Notes'),
                maxLines: 4,
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 12),
                _PhotoRow(
                  path: _photoPath,
                  onPick: _pickPhoto,
                  onRemove: () => setState(() => _photoPath = null),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving
                    ? context.tr(pl: 'Zapisuję…', en: 'Saving…')
                    : context.tr(pl: 'Zapisz', en: 'Save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PhotoRow({
    required this.path,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = path;
    return Row(
      children: [
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(p),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                cacheWidth: 216,
                errorBuilder: (context, error, stack) => const SizedBox(
                    width: 72,
                    height: 72,
                    child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(p == null
                ? context.tr(
                    pl: 'Dodaj zdjęcie certyfikatu',
                    en: 'Add certificate photo')
                : context.tr(pl: 'Zmień zdjęcie', en: 'Change photo')),
          ),
        ),
        if (p != null)
          IconButton(
            tooltip: context.tr(pl: 'Usuń zdjęcie', en: 'Remove photo'),
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}
