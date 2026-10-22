// Formularz jednej WPS w bibliotece spawacza.
//
// v25 — WPS jako dokument nadzorowany:
//  • zmiana treści zapisanej WPS pyta: „nowa rewizja” (nowy wpis, stara
//    rewizja zostaje) albo „popraw bieżącą” — obie drogi zostawiają ślad:
//    poprzednia treść zostaje wersją obowiązującą dla spoin sprzed zmiany;
//  • status dokumentu (pWPS / zatwierdzona / wycofana);
//  • ostrzeżenie o duplikacie numeru i rewizji;
//  • strażnik „Porzucić zmiany?” przy wyjściu.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../database/wps_dao.dart';
import '../../domain/qualification/weld_process.dart';
import '../../domain/welding/heat_input.dart';
import '../../domain/wps/wps_record.dart';
import '../../i18n/app_language.dart';
import '../../services/heat_photo_storage.dart';
import '../../services/welder_identity.dart';
import '../../services/welder_qualification_service.dart';
import '../../theme/app_theme.dart';
import '../qualification/form_bits.dart';
import '../../widgets/local_record_scope.dart';

/// v33: edytor należy do konta, dla którego go otwarto — po zmianie konta
/// dane chowają się, a zapis idzie wyłącznie do właściciela tej sesji.
class WpsEditPage extends StatelessWidget {
  /// `null` = nowa WPS.
  final WpsRecord? wps;

  const WpsEditPage({super.key, this.wps});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      restartOnAccountChange: false,
      builder: (_, session) => _WpsEditForm(wps: wps, session: session));
}

class _WpsEditForm extends StatefulWidget {
  final WpsRecord? wps;
  final LocalRecordSession session;

  const _WpsEditForm({this.wps, required this.session});

  @override
  State<_WpsEditForm> createState() => _WpsEditPageState();
}

class _WpsEditPageState extends State<_WpsEditForm> {
  final _formKey = GlobalKey<FormState>();

  late WpsStandard _standard;
  late WpsDocStatus _docStatus;
  bool _closing = false;
  late final String _initialSnapshot;
  late HeatInputStandard _hiMethod;
  late Set<WeldJointKind> _kinds;
  String? _attachment;
  bool _saving = false;

  late final TextEditingController _no;
  late final TextEditingController _rev;
  late final TextEditingController _pqr;
  late final TextEditingController _processes;
  late final TextEditingController _group;
  late final TextEditingController _tMin;
  late final TextEditingController _tMax;
  late final TextEditingController _dMin;
  late final TextEditingController _dMax;
  late final TextEditingController _positions;
  late final TextEditingController _filler;
  late final TextEditingController _shield;
  late final TextEditingController _backing;
  late final TextEditingController _preheat;
  late final TextEditingController _interpass;
  late final TextEditingController _hiMin;
  late final TextEditingController _hiMax;
  late final TextEditingController _pwht;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final w = widget.wps;
    TextEditingController t(String? v) => TextEditingController(text: v ?? '');
    _standard = w?.standard ?? WpsStandard.iso15614_1;
    _docStatus = w?.docStatus ?? WpsDocStatus.unknown;
    _hiMethod = w?.heatInputMethod ?? HeatInputStandard.en1011;
    _kinds = {...?w?.jointKinds};
    _attachment = w?.attachmentPath;
    _no = t(w?.wpsNo);
    _rev = t(w?.revision);
    _pqr = t(w?.pqrRef);
    _processes = t(w?.processes);
    _group = t(w?.materialGroup);
    _tMin = t(formatDecimalField(w?.thicknessMinMm));
    _tMax = t(formatDecimalField(w?.thicknessMaxMm));
    _dMin = t(formatDecimalField(w?.diameterMinMm));
    _dMax = t(formatDecimalField(w?.diameterMaxMm));
    _positions = t(w?.positions);
    _filler = t(w?.filler);
    _shield = t(w?.shieldingGas);
    _backing = t(w?.backingGas);
    _preheat = t(formatDecimalField(w?.preheatMinC));
    _interpass = t(formatDecimalField(w?.interpassMaxC));
    _hiMin = t(formatDecimalField(w?.heatInputMinKjMm));
    _hiMax = t(formatDecimalField(w?.heatInputMaxKjMm));
    _pwht = t(w?.pwht);
    _notes = t(w?.notes);
    _initialSnapshot = _snapshot();
  }

  List<TextEditingController> get _controllers => [
        _no,
        _rev,
        _pqr,
        _processes,
        _group,
        _tMin,
        _tMax,
        _dMin,
        _dMax,
        _positions,
        _filler,
        _shield,
        _backing,
        _preheat,
        _interpass,
        _hiMin,
        _hiMax,
        _pwht,
        _notes,
      ];

  String _snapshot() => [
        _standard.code,
        _docStatus.code,
        heatInputMethodCode(_hiMethod),
        encodeJointKinds(_kinds),
        _attachment ?? '',
        for (final c in _controllers) c.text,
      ].join('\u0001');

  Future<void> _handleClose() async {
    if (_saving || _closing) return;
    final nav = Navigator.of(context);
    if (_snapshot() == _initialSnapshot) {
      nav.pop();
      return;
    }
    _closing = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Porzucić zmiany?', en: 'Discard changes?')),
        content: Text(ctx.tr(
            pl: 'Wpisane dane WPS zostaną utracone.',
            en: 'The WPS data you entered will be lost.')),
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

  /// Nowa rewizja: pyta o oznaczenie; `null` = anulowano.
  Future<String?> _askRevision(String current) async {
    final ctrl = TextEditingController(text: _nextRevision(current));
    final rev = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Nowa rewizja WPS', en: 'New WPS revision')),
        content: TextField(
          key: const ValueKey('wps-new-revision'),
          controller: ctrl,
          autofocus: true,
          decoration:
              InputDecoration(labelText: ctx.tr(pl: 'Rewizja', en: 'Revision')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ctx.tr(pl: 'Zapisz', en: 'Save'))),
        ],
      ),
    );
    return rev;
  }

  /// „B” → „C”, „2” → „3”, pusta → „A”; inaczej bez zmian.
  static String _nextRevision(String rev) {
    final r = rev.trim();
    if (r.isEmpty) return 'A';
    final n = int.tryParse(r);
    if (n != null) return '${n + 1}';
    if (r.length == 1 && RegExp(r'[A-Ya-y]').hasMatch(r)) {
      return String.fromCharCode(r.codeUnitAt(0) + 1).toUpperCase();
    }
    return r;
  }

  @override
  void dispose() {
    for (final c in [
      _no,
      _rev,
      _pqr,
      _processes,
      _group,
      _tMin,
      _tMax,
      _dMin,
      _dMax,
      _positions,
      _filler,
      _shield,
      _backing,
      _preheat,
      _interpass,
      _hiMin,
      _hiMax,
      _pwht,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final stored = await persistPickedHeatPhoto(path);
      if (!mounted) return;
      setState(() => _attachment = stored);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się skopiować pliku.',
            en: 'Could not copy the file.')),
      ));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = widget.wps;
    var wps = WpsRecord(
      id: old?.id ?? const Uuid().v4(),
      wpsNo: _no.text.trim(),
      revision: _rev.text.trim(),
      standard: _standard,
      pqrRef: _pqr.text.trim(),
      processes: _processes.text.trim(),
      materialGroup: _group.text.trim(),
      thicknessMinMm: parseDecimalField(_tMin.text),
      thicknessMaxMm: parseDecimalField(_tMax.text),
      diameterMinMm: parseDecimalField(_dMin.text),
      diameterMaxMm: parseDecimalField(_dMax.text),
      positions: _positions.text.trim(),
      jointKinds: _kinds,
      filler: _filler.text.trim(),
      shieldingGas: _shield.text.trim(),
      backingGas: _backing.text.trim(),
      preheatMinC: parseDecimalField(_preheat.text),
      interpassMaxC: parseDecimalField(_interpass.text),
      heatInputMinKjMm: parseDecimalField(_hiMin.text),
      heatInputMaxKjMm: parseDecimalField(_hiMax.text),
      heatInputMethod: _hiMethod,
      pwht: _pwht.text.trim(),
      notes: _notes.text.trim(),
      docStatus: _docStatus,
      attachmentPath: _attachment,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    final problem = validateWps(wps);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: problem.messagePl, en: problem.messageEn)),
      ));
      return;
    }
    final dao = WpsDao(captureOwner: widget.session.captureOwner);
    // Zmiana treści zapisanej WPS: nowa rewizja albo poprawka bieżącej
    // (obie zostawiają ślad w wersjach).
    var keepOldFile = false;
    if (old != null && !old.sameContentAs(wps)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
              ctx.tr(pl: 'Zmieniono treść WPS', en: 'The WPS content changed')),
          content: Text(ctx.tr(
              pl: 'Spoiny wykonane wcześniej będą oceniane wg treści '
                  'obowiązującej w dniu spawania. Zapisać jako NOWĄ '
                  'rewizję (${old.displayName} zostaje), czy poprawić '
                  'bieżącą (poprzednia treść zostaje w historii wersji)?',
              en: 'Welds made earlier are judged against the content in '
                  'force on the weld date. Save as a NEW revision '
                  '(${old.displayName} stays), or correct the current one '
                  '(the previous content stays in the version history)?')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'fix'),
                child:
                    Text(ctx.tr(pl: 'Popraw bieżącą', en: 'Correct current'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'rev'),
                child: Text(ctx.tr(pl: 'Nowa rewizja', en: 'New revision'))),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'rev') {
        final rev = await _askRevision(wps.revision);
        if (rev == null || !mounted) return;
        wps = WpsRecord.fromRow({
          ...wps.toRow(),
          'id': const Uuid().v4(),
          'revision': rev,
          'created_at': now,
        });
        keepOldFile = true;
      }
    }
    // Duplikat numeru i rewizji — dziennik nie wie, którą wybrać.
    final dups =
        await dao.duplicatesOf(wps.wpsNo, wps.revision, exceptId: wps.id);
    if (!mounted) return;
    if (dups.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr(
              pl: 'Taka WPS już jest w bibliotece',
              en: 'This WPS is already in the library')),
          content: Text(ctx.tr(
              pl: '${wps.displayName} jest już zapisana. Zastąpić istniejącą '
                  '(jej poprzednia treść zostanie w historii wersji) czy '
                  'zapisać jako nową rewizję?',
              en: '${wps.displayName} is already saved. Replace the existing '
                  'one (its previous content stays in the version history) or '
                  'save as a new revision?')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel'))),
            if (old == null)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'replace'),
                  child: Text(
                      ctx.tr(pl: 'Zastąp istniejącą', en: 'Replace existing'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'rev'),
                child: Text(ctx.tr(pl: 'Nowa rewizja', en: 'New revision'))),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'replace') {
        final target = dups.first;
        wps = WpsRecord.fromRow({
          ...wps.toRow(),
          'id': target.id,
          'created_at': target.createdAt,
          'attachment_path': _attachment ?? target.attachmentPath,
        });
      } else {
        final rev = await _askRevision(wps.revision);
        if (rev == null || !mounted) return;
        wps = WpsRecord.fromRow({...wps.toRow(), 'revision': rev});
      }
    }
    setState(() => _saving = true);
    try {
      await dao.upsert(wps,
          by: WelderIdentityService.instance.current?.stamp ?? '');
      final oldFile = old?.attachmentPath;
      if (!keepOldFile && oldFile != null && oldFile != _attachment) {
        await WelderQualificationService.instance.deleteOwnedFile(oldFile);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się zapisać WPS.', en: 'Could not save the WPS.')),
      ));
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final english = context.language == AppLanguage.en;
    return PopScope<Object?>(
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
          title: Text(widget.wps == null
              ? context.tr(pl: 'Nowa WPS', en: 'New WPS')
              : 'WPS ${widget.wps!.displayName}'),
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
              FormSectionTitle(context.tr(pl: 'Identyfikacja', en: 'Identity')),
              FieldPair(
                left: TextFormField(
                  controller: _no,
                  decoration: InputDecoration(
                    labelText: context.tr(pl: 'Nr WPS *', en: 'WPS no. *'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? context.tr(pl: 'Wymagany', en: 'Required')
                      : null,
                ),
                right: PlainField(
                    controller: _rev,
                    label: context.tr(pl: 'Rewizja', en: 'Revision')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WpsStandard>(
                initialValue: _standard,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Norma kwalifikowania', en: 'Qualification standard'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final s in WpsStandard.values)
                    DropdownMenuItem(
                        value: s, child: Text(english ? s.labelEn : s.labelPl)),
                ],
                onChanged: (v) =>
                    setState(() => _standard = v ?? WpsStandard.iso15614_1),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WpsDocStatus>(
                key: const ValueKey('wps-doc-status'),
                initialValue: _docStatus,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      context.tr(pl: 'Status dokumentu', en: 'Document status'),
                  helperText: context.tr(
                      pl: 'pWPS i wycofana WPS dają ostrzeżenie w dzienniku.',
                      en: 'A pWPS or a withdrawn WPS gives a journal warning.'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final st in WpsDocStatus.values)
                    DropdownMenuItem(
                      value: st,
                      child: Text(st == WpsDocStatus.unknown
                          ? context.tr(pl: 'Nie podano', en: 'Not given')
                          : (english ? st.labelEn : st.labelPl)),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _docStatus = v ?? WpsDocStatus.unknown),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _pqr,
                label: context.tr(
                    pl: 'Powiązany WPQR / PQR', en: 'Supporting WPQR / PQR'),
                helper: context.tr(
                    pl: 'Protokół kwalifikowania procedury (ISO 15614-1 / '
                        'ASME IX) — nie uprawnienie spawacza.',
                    en: 'Procedure qualification record (ISO 15614-1 / ASME IX) '
                        '— not the welder qualification.'),
              ),
              FormSectionTitle(context.tr(pl: 'Zakres', en: 'Range')),
              PlainField(
                controller: _processes,
                label: context.tr(pl: 'Proces(y)', en: 'Process(es)'),
                helper: context.tr(
                    pl: 'Numery EN ISO 4063, np. 141 albo 141 + 111',
                    en: 'EN ISO 4063 numbers, e.g. 141 or 141 + 111'),
              ),
              const SizedBox(height: 12),
              PlainField(
                controller: _group,
                label:
                    context.tr(pl: 'Grupa materiałowa', en: 'Material group'),
                helper: context.tr(
                    pl: 'ISO/TR 15608 lub P-No; kilka po przecinku, złącze '
                        'różnoimienne jako 1 + 8.1',
                    en: 'ISO/TR 15608 or P-No; several comma-separated, '
                        'dissimilar joint as 1 + 8.1'),
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
                label: context.tr(pl: 'Pozycje', en: 'Positions'),
                helper: context.tr(
                    pl: 'np. PA, PC, PF albo „wszystkie”',
                    en: 'e.g. PA, PC, PF or "all"'),
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
                      label: Text(k.code),
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
              FormSectionTitle(
                  context.tr(pl: 'Spoiwo i gazy', en: 'Filler and gases')),
              PlainField(
                  controller: _filler,
                  label: context.tr(pl: 'Spoiwo', en: 'Filler')),
              const SizedBox(height: 12),
              PlainField(
                  controller: _shield,
                  label: context.tr(pl: 'Gaz osłonowy', en: 'Shielding gas')),
              const SizedBox(height: 12),
              PlainField(
                  controller: _backing,
                  label: context.tr(
                      pl: 'Gaz formujący', en: 'Backing (purge) gas')),
              FormSectionTitle(context.tr(
                  pl: 'Temperatury i energia liniowa',
                  en: 'Temperatures and heat input')),
              FieldPair(
                left: DecimalField(
                    controller: _preheat,
                    label:
                        context.tr(pl: 'Podgrzewanie min', en: 'Preheat min'),
                    unit: '°C'),
                right: DecimalField(
                    controller: _interpass,
                    label: context.tr(
                        pl: 'Międzyściegowa max', en: 'Interpass max'),
                    unit: '°C'),
              ),
              const SizedBox(height: 12),
              FieldPair(
                left: DecimalField(
                    controller: _hiMin,
                    label: context.tr(
                        pl: 'Energia liniowa min', en: 'Heat input min'),
                    unit: 'kJ/mm'),
                right: DecimalField(
                    controller: _hiMax,
                    label: context.tr(pl: 'max', en: 'max'),
                    unit: 'kJ/mm'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<HeatInputStandard>(
                initialValue: _hiMethod,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Konwencja energii liniowej',
                      en: 'Heat input convention'),
                  helperText: context.tr(
                      pl: 'Ta sama, w której liczono zakres na WPS.',
                      en: 'The one the WPS range was computed in.'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: HeatInputStandard.en1011,
                    child: Text(context.tr(
                        pl: 'EN 1011-1 / ISO 15614-1 (ze sprawnością k)',
                        en: 'EN 1011-1 / ISO 15614-1 (with efficiency k)')),
                  ),
                  DropdownMenuItem(
                    value: HeatInputStandard.asmeIx,
                    child: Text(context.tr(
                        pl: 'ASME IX QW-409.1 (bez k)',
                        en: 'ASME IX QW-409.1 (no k)')),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _hiMethod = v ?? HeatInputStandard.en1011),
              ),
              const SizedBox(height: 12),
              PlainField(
                  controller: _pwht,
                  label: context.tr(
                      pl: 'PWHT (obróbka cieplna po spawaniu)',
                      en: 'PWHT (post-weld heat treatment)')),
              FormSectionTitle(context.tr(pl: 'Inne', en: 'Other')),
              PlainField(
                  controller: _notes,
                  label: context.tr(pl: 'Uwagi', en: 'Notes'),
                  maxLines: 4),
              if (!kIsWeb) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickAttachment,
                        icon: const Icon(Icons.attach_file),
                        label: Text(_attachment == null
                            ? context.tr(
                                pl: 'Dołącz plik WPS (PDF / zdjęcie)',
                                en: 'Attach the WPS file (PDF / photo)')
                            : p.basename(_attachment!)),
                      ),
                    ),
                    if (_attachment != null)
                      IconButton(
                        tooltip: context.tr(pl: 'Usuń plik', en: 'Remove file'),
                        onPressed: () => setState(() => _attachment = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
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
