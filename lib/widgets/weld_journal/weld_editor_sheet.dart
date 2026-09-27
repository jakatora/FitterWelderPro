/// The weld card: create or edit one joint of the journal.
///
/// Extracted from `weld_journal_screen.dart` (the screen had grown to 70 KB)
/// and extended with what an inspector checks: identification (ISO number and
/// revision, line, spool, test package, joint type, shop/field, position),
/// root and cap stamps, filler, actual preheat / interpass / heat input, NDT
/// per method, PWHT, acceptance, the coupon picked from the coupon log, the
/// repairs and the change history of the weld.
///
/// Glove rules: the Save buttons are pinned to the bottom of the sheet (they
/// used to sit under 15 fields, below the keyboard), every chip is ≥ 48 dp,
/// and "Zapisz i następna" saves and hands the screen a copy for the next
/// joint with the number incremented.
///
/// v25 (dokumentacja jakości):
///  • spójność dokumentu — status OK / odbiór przy NDT NOK, badaniu bez
///    wyniku, dacie odbioru sprzed spawania, kuponie NOK itd. to jawne
///    ostrzeżenie przy zapisie; „Zapisz mimo to” trafia do historii;
///  • odnośnik kuponu jest „żywy” — karta pokazuje stan kuponu z logu
///    (OK / do oceny / NOK / usunięty);
///  • odebrana spoina ma zablokowane pola wykonawcze; odblokowanie wymaga
///    uzasadnienia, które trafia do historii;
///  • WPS wybrana z biblioteki jest zapamiętana w spoinie (`wps_id`).
library;

import 'package:flutter/material.dart';

import '../../database/coupon_dao.dart';
import '../../database/weld_journal_dao.dart';
import '../../domain/weld_journal/coupon_entry.dart';
import '../../domain/weld_journal/weld_compliance.dart';
import '../../domain/weld_journal/weld_consistency.dart';
import '../../domain/weld_journal/weld_dates.dart';
import '../../domain/weld_journal/weld_defaults.dart';
import '../../domain/weld_journal/weld_entry.dart';
import '../../domain/weld_journal/weld_history.dart';
import '../../domain/weld_journal/weld_ndt.dart';
import '../../domain/weld_journal/weld_numbering.dart';
import '../../domain/welding/heat_input.dart';
import '../../features/wps/wps_picker_sheet.dart';
import '../../i18n/app_language.dart';
import '../../services/weld_compliance_check.dart';
import '../../theme/app_theme.dart';
import 'coupon_picker_sheet.dart';
import 'weld_compliance_view.dart';
import 'weld_history_view.dart';
import 'weld_ndt_editor.dart';
import 'weld_project_picker.dart';
import 'wj_ui.dart';
import '../number_field.dart';

/// What the editor did.
class WeldEditorResult {
  final WeldEntry saved;

  /// "Zapisz i następna" — the screen opens the next weld right away.
  final bool next;
  const WeldEditorResult(this.saved, {this.next = false});
}

const List<String> _kMethods = ['TIG', 'MIG/MAG', 'MMA', 'Tandem'];
const List<String> _kWeldTypes = ['ORBITAL', 'AUTO', 'MANUAL'];

/// Opens the weld card for [initial]. [isNew] decides insert vs update.
/// [journal] (the whole journal, deleted entries included) feeds the number
/// suggestion and the duplicate warning. [stamp] is recorded as "who" in the
/// history.
Future<WeldEditorResult?> showWeldEditor(
  BuildContext context, {
  required WeldEntry initial,
  required bool isNew,
  required List<WeldEntry> journal,
  required List<String> journalProjects,
  required String stamp,
  WeldJournalDao? dao,
  WeldComplianceCheck? check,
  CouponDao? coupons,
}) =>
    showModalBottomSheet<WeldEditorResult>(
      context: context,
      isScrollControlled: true,
      // One stray tap on the scrim, or a gloved thumb brushing downwards,
      // used to throw away every typed field. Both gestures are off; the X
      // button and the back gesture go through "Porzucić wpis?".
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => WeldEditorSheet(
        initial: initial,
        isNew: isNew,
        journal: journal,
        journalProjects: journalProjects,
        stamp: stamp,
        dao: dao ?? WeldJournalDao(),
        check: check ?? checkWeldCompliance,
        coupons: coupons ?? CouponDao(),
      ),
    );

class WeldEditorSheet extends StatefulWidget {
  final WeldEntry initial;
  final bool isNew;
  final List<WeldEntry> journal;
  final List<String> journalProjects;
  final String stamp;
  final WeldJournalDao dao;

  /// WPS + welder qualification — on save and on the card of an existing
  /// weld.
  final WeldComplianceCheck check;

  /// Log kuponów — stan podpiętego kuponu („żywy” odnośnik).
  final CouponDao? coupons;

  const WeldEditorSheet({
    super.key,
    required this.initial,
    required this.isNew,
    required this.journal,
    required this.journalProjects,
    required this.stamp,
    required this.dao,
    this.check = checkWeldCompliance,
    this.coupons,
  });

  @override
  State<WeldEditorSheet> createState() => _WeldEditorSheetState();
}

class _WeldEditorSheetState extends State<WeldEditorSheet> {
  late final WeldEntry _e = widget.initial;

  late final _no = TextEditingController(text: _e.weldNo);
  late final _proj = TextEditingController(text: _e.projectName);
  late final _line = TextEditingController(text: _e.pipeName);
  late final _iso = TextEditingController(text: _e.isoDrawing);
  late final _isoRev = TextEditingController(text: _e.isoRev);
  late final _spool = TextEditingController(text: _e.spool);
  late final _pkg = TextEditingController(text: _e.testPackage);
  late final _mat = TextEditingController(text: _e.material);
  late final _od = TextEditingController(text: _e.od);
  late final _t = TextEditingController(text: _e.t);
  late final _heat1 = TextEditingController(text: _e.heatNo1);
  late final _heat2 = TextEditingController(text: _e.heatNo2);
  late final _wps = TextEditingController(text: _e.wpsRef);
  late final _fillerClass = TextEditingController(text: _e.fillerClass);
  late final _fillerBatch = TextEditingController(text: _e.fillerBatch);
  late final _preheat = TextEditingController(text: _e.preheatC);
  late final _interpass = TextEditingController(text: _e.interpassC);
  late final HeatInputText _hiInitial = splitHeatInput(_e.heatInput);
  late final _heatInput = TextEditingController(text: _hiInitial.number);
  late final _welder = TextEditingController(text: _e.welder);
  late final _root = TextEditingController(text: _e.rootWelder);
  late final _cap = TextEditingController(text: _e.capWelder);
  late final _fitter = TextEditingController(text: _e.fitter);
  late final _date = TextEditingController(text: _e.date);
  late final _coupon = TextEditingController(text: _e.couponRef);
  late final _exam = TextEditingController(text: _e.exam);
  late final _pwhtChart = TextEditingController(text: _e.pwhtChart);
  late final _hardness = TextEditingController(text: _e.hardness);
  late final _inspector = TextEditingController(text: _e.inspector);
  late final _inspectedAt = TextEditingController(text: _e.inspectedAt);
  late final _notes = TextEditingController(text: _e.notes);

  late String _method = _e.method;
  late String _weldType = _e.weldType;
  late String _jointType = _e.jointType;
  late String _shopField = _e.shopField;
  late String _position = _e.position;
  late String _status = _e.status;
  late bool? _pwht = _e.pwhtRequired;
  late Map<NdtMethod, WeldNdt> _ndt = _e.ndt;
  late String? _projectId = _e.projectId;
  late String? _couponId = _e.couponId;

  /// Convention of the heat input value — stored as a suffix of the text
  /// ("1,25 EN"), see weld_compliance.dart.
  late HeatInputStandard? _hiMethod = _hiInitial.method;

  /// WPS picked from the library (stored in the weld since v25); typing
  /// unlinks it — then `wps_ref` is matched to the library by text.
  late String? _wpsId = _e.wpsId;

  /// Kupon podpięty do spoiny, odczytany z logu (także usunięty); `null` =
  /// brak w logu. [_couponKnown] — log udało się odczytać.
  CouponEntry? _couponRow;
  bool _couponKnown = false;

  /// Niespójności spoiny w chwili otwarcia — przy zapisie pytamy tylko o
  /// nowe.
  List<WeldConsistencyIssue> _initialIssues = const [];

  /// Odebrana spoina: pola wykonawcze zablokowane do czasu odblokowania
  /// z uzasadnieniem.
  late bool _locked = !widget.isNew &&
      (_e.inspector.trim().isNotEmpty || _e.inspectedAt.trim().isNotEmpty);
  String? _unlockReason;

  /// Last WPS / qualification check (on open of an existing weld, and after
  /// "Popraw" in the save warning).
  WeldCompliance? _check;

  /// The number is still the app's suggestion — picking a project may
  /// re-suggest it. Any keystroke in the number field hands it to the welder.
  late bool _autoNo = widget.isNew;

  bool _saving = false;
  bool _closing = false;
  String? _noError;
  String? _dateError;
  String? _inspectedError;

  /// The form exactly as it was opened — taken in initState, before any
  /// keystroke. A sheet nobody touched closes silently; one typed character
  /// arms the discard guard.
  late final Map<String, String> _initialSnapshot;

  final Set<String> _open = {};
  List<WeldHistoryEntry>? _history;

  List<TextEditingController> get _controllers => [
        _no,
        _proj,
        _line,
        _iso,
        _isoRev,
        _spool,
        _pkg,
        _mat,
        _od,
        _t,
        _heat1,
        _heat2,
        _wps,
        _fillerClass,
        _fillerBatch,
        _preheat,
        _interpass,
        _heatInput,
        _welder,
        _root,
        _cap,
        _fitter,
        _date,
        _coupon,
        _exam,
        _pwhtChart,
        _hardness,
        _inspector,
        _inspectedAt,
        _notes,
      ];

  @override
  void initState() {
    super.initState();
    _initialSnapshot = _snapshot();
    // Sections open when they hold data (or, for a new weld, the ones a
    // welder fills on every joint).
    final e = _e;
    if (widget.isNew ||
        [
          e.spool,
          e.testPackage,
          e.jointType,
          e.position,
          e.material,
          e.od,
          e.t,
          e.heatNo1,
          e.heatNo2
        ].any((s) => s.isNotEmpty)) {
      _open.add('joint');
    }
    if (widget.isNew ||
        [e.method, e.wpsRef, e.fillerClass, e.preheatC, e.heatInput]
            .any((s) => s.isNotEmpty)) {
      _open.add('process');
    }
    if ([e.rootWelder, e.capWelder, e.fitter].any((s) => s.isNotEmpty) &&
        !widget.isNew) {
      _open.add('welders');
    }
    if (e.ndt.isNotEmpty || e.exam.isNotEmpty || e.couponRef.isNotEmpty) {
      _open.add('ndt');
    }
    if (e.pwhtRequired != null ||
        [e.pwhtChart, e.hardness, e.inspector].any((s) => s.isNotEmpty)) {
      _open.add('acceptance');
    }
    if (!widget.isNew) {
      _loadHistory();
      _runCardCheck();
    }
    _loadCoupon(_e.couponId, initial: true);
  }

  Future<void> _loadCoupon(String? id, {bool initial = false}) async {
    final dao = widget.coupons;
    CouponEntry? row;
    var known = false;
    if (id != null && id.isNotEmpty && dao != null) {
      try {
        row = await dao.getById(id);
        known = true;
      } catch (e) {
        debugPrint('[weld_journal] coupon read failed: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _couponRow = row;
      _couponKnown = known;
      if (initial) {
        _initialIssues = widget.isNew
            ? const []
            : weldConsistencyIssues(_e,
                coupon: row, couponKnown: known, today: DateTime.now());
      }
    });
  }

  Future<void> _unlock() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(
            pl: 'Odblokować odebraną spoinę?',
            en: 'Unlock the accepted weld?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ctx.tr(
                  pl: 'Spoina ma odbiór inspektora. Zmiana danych wykonania '
                      'po odbiorze wymaga uzasadnienia — trafi ono do '
                      'historii spoiny razem ze zmianami.',
                  en: 'The weld has an inspector acceptance. Changing the '
                      'execution data after acceptance needs a reason — it '
                      'goes to the weld history with the changes.'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('weld-unlock-reason'),
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: ctx.tr(pl: 'Uzasadnienie', en: 'Reason'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(ctx.tr(pl: 'Odblokuj', en: 'Unlock')),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() {
      _locked = false;
      _unlockReason = reason;
    });
  }

  /// Ostrzeżenie o nowych niespójnościach: `true` = „Zapisz mimo to”.
  Future<bool> _confirmConsistency(List<WeldConsistencyIssue> issues) async {
    final en = AppLanguageController.isEnglish;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(
            pl: 'Niespójny dokument odbiorowy',
            en: 'Inconsistent acceptance record')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${i.text(en: en)}',
                      style: const TextStyle(fontSize: 13)),
                ),
              const SizedBox(height: 8),
              Text(
                ctx.tr(
                    pl: 'Zapis nie jest blokowany — ostrzeżenie trafi do '
                        'historii spoiny i do PDF.',
                    en: 'Saving is not blocked — the warning goes to the '
                        "weld's history and the PDF."),
                style: const TextStyle(fontSize: 12, color: kTextSec),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr(pl: 'Popraw', en: 'Fix')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(pl: 'Zapisz mimo to', en: 'Save anyway')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<WeldCompliance?> _runCheck(WeldEntry entry) async {
    try {
      return await widget.check(entry, wpsId: _wpsId);
    } catch (e) {
      // No library, no register, no DB: the check is advice, never a reason
      // to lose a weld.
      debugPrint('[weld_journal] compliance check failed: $e');
      return null;
    }
  }

  Future<void> _runCardCheck() async {
    final c = await _runCheck(_e);
    if (mounted && c != null) setState(() => _check = c);
  }

  Future<void> _loadHistory() async {
    try {
      final h = await widget.dao.history(_e.id);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      debugPrint('[weld_journal] history load failed: $e');
      if (mounted) setState(() => _history = const []);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// The form as an entry (values trimmed; dates as typed — [_save]
  /// validates them).
  WeldEntry _build() => _e.copyWith(
        weldNo: _no.text.trim(),
        projectName: _proj.text.trim(),
        projectId: _projectId,
        pipeName: _line.text.trim(),
        isoDrawing: _iso.text.trim(),
        isoRev: _isoRev.text.trim(),
        spool: _spool.text.trim(),
        testPackage: _pkg.text.trim(),
        jointType: _jointType,
        shopField: _shopField,
        position: _position,
        material: _mat.text.trim(),
        od: _od.text.trim(),
        t: _t.text.trim(),
        heatNo1: _heat1.text.trim(),
        heatNo2: _heat2.text.trim(),
        method: _method,
        weldType: _weldType,
        wpsRef: _wps.text.trim(),
        wpsId: _wpsId,
        fillerClass: _fillerClass.text.trim(),
        fillerBatch: _fillerBatch.text.trim(),
        preheatC: _preheat.text.trim(),
        interpassC: _interpass.text.trim(),
        heatInput: joinHeatInput(_heatInput.text, _hiMethod),
        welder: _welder.text.trim(),
        rootWelder: _root.text.trim(),
        capWelder: _cap.text.trim(),
        fitter: _fitter.text.trim(),
        date: _date.text.trim(),
        couponRef: _coupon.text.trim(),
        couponId: _couponId,
        exam: _exam.text.trim(),
        status: _status,
        pwhtRequired: _pwht,
        pwhtChart: _pwhtChart.text.trim(),
        hardness: _hardness.text.trim(),
        inspector: _inspector.text.trim(),
        inspectedAt: _inspectedAt.text.trim(),
        notes: _notes.text.trim(),
        ndt: compactNdt(_ndt),
      );

  Map<String, String> _snapshot() => {
        ..._build().auditFields(),
        'project_id': _projectId ?? '',
        'coupon_id': _couponId ?? '',
        'wps_id': _wpsId ?? '',
      };

  bool get _isDirty {
    final now = _snapshot();
    for (final f in _initialSnapshot.entries) {
      if (now[f.key] != f.value) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Porzucić wpis?', en: 'Discard entry?')),
        content: Text(ctx.tr(
          pl: 'Wypełnione pola spoiny zostaną utracone.',
          en: 'The weld data you entered will be lost.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr(pl: 'Wróć do edycji', en: 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(pl: 'Porzuć', en: 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// The one exit path besides saving: X button and back gesture.
  Future<void> _handleClose() async {
    if (_saving || _closing) return;
    final nav = Navigator.of(context);
    if (!_isDirty) {
      nav.pop();
      return;
    }
    _closing = true;
    final discard = await _confirmDiscard();
    _closing = false;
    if (discard && mounted) nav.pop();
  }

  Future<bool> _confirmDuplicate(List<WeldEntry> dups) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(
            pl: 'Numer już użyty w projekcie',
            en: 'Number already used in the project')),
        content: Text(ctx.tr(
          pl: 'Spoina ${_no.text.trim()} jest już w projekcie '
              '„${_proj.text.trim().isEmpty ? '—' : _proj.text.trim()}” '
              '(${dups.length}×). Dwie spoiny o tym samym numerze to dla '
              'inspektora jedna — zapisać mimo to?',
          en: 'Weld ${_no.text.trim()} already exists in project '
              '"${_proj.text.trim().isEmpty ? '—' : _proj.text.trim()}" '
              '(${dups.length}×). To an inspector two welds with one number '
              'are one weld — save anyway?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr(pl: 'Zmień numer', en: 'Change number')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(pl: 'Zapisz mimo to', en: 'Save anyway')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save({bool next = false}) async {
    if (_saving) return;
    final no = _no.text.trim();
    final date = normalizeWeldDate(_date.text);
    final inspected = normalizeWeldDate(_inspectedAt.text);
    final ndt = normalizeNdtDates(_ndt);
    setState(() {
      _noError = no.isEmpty
          ? context.tr(pl: 'Podaj numer spoiny', en: 'Enter the weld number')
          : null;
      _dateError = date == null
          ? context.tr(
              pl: 'Data RRRR-MM-DD lub DD.MM.RRRR',
              en: 'Date YYYY-MM-DD or DD.MM.YYYY')
          : null;
      _inspectedError = inspected == null
          ? context.tr(pl: 'Nieprawidłowa data', en: 'Invalid date')
          : null;
    });
    if (no.isEmpty || date == null || inspected == null) return;
    if (ndt == null) {
      setState(() => _open.add('ndt'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Popraw datę badania NDT (RRRR-MM-DD).',
            en: 'Fix the NDT examination date (YYYY-MM-DD).')),
      ));
      return;
    }
    // Keep the normalised dates visible in the form.
    _date.text = date;
    _inspectedAt.text = inspected;
    final entry = _build().copyWith(
      date: date,
      inspectedAt: inspected,
      ndt: ndt,
    );

    final dups = findDuplicateWeldNos(widget.journal, entry);
    if (dups.isNotEmpty && !await _confirmDuplicate(dups)) return;
    if (!mounted) return;

    // Spójność dokumentu odbiorowego: nowe niespójności → jawne ostrzeżenie,
    // „Zapisz mimo to” do historii.
    final en = AppLanguageController.isEnglish;
    final fresh = newConsistencyIssues(
        _initialIssues,
        weldConsistencyIssues(entry,
            coupon: _couponRow,
            couponKnown: _couponKnown,
            today: DateTime.now()));
    String? consistencyWarning;
    if (fresh.isNotEmpty) {
      if (!await _confirmConsistency(fresh)) {
        if (mounted) setState(() => _open.addAll(['ndt', 'acceptance']));
        return;
      }
      if (!mounted) return;
      consistencyWarning = consistencyHistoryText(fresh, en: en);
    }

    // WPS and welder qualification: a warning, never a block. The welder
    // decides; "Zapisz mimo to" goes to the weld's history.
    setState(() => _saving = true);
    final compliance = await _runCheck(entry);
    if (!mounted) return;
    String? warning;
    if (compliance != null && compliance.hasWarnings) {
      setState(() => _saving = false);
      final saveAnyway = await confirmWeldCompliance(context, compliance);
      if (!mounted) return;
      if (!saveAnyway) {
        setState(() {
          _check = compliance;
          _open.addAll(['joint', 'process', 'welders']);
        });
        return;
      }
      warning = compliance.historyText(en: AppLanguageController.isEnglish);
      setState(() => _saving = true);
    }
    final allWarnings = [
      if (warning != null) warning,
      if (consistencyWarning != null) consistencyWarning,
    ].join('\n\n');
    try {
      if (widget.isNew) {
        await widget.dao.insert(entry, by: widget.stamp, warning: allWarnings);
      } else {
        await widget.dao.update(entry,
            by: widget.stamp,
            warning: allWarnings,
            unlockReason: _unlockReason);
      }
      // Remember for the next joint — a name typed by hand too.
      await saveLastWeldProject(entry.projectName);
      await saveWeldDefaults(WeldEntryDefaults.fromEntry(entry));
      if (!mounted) return;
      Navigator.pop(context, WeldEditorResult(entry, next: next));
    } catch (err) {
      // A DAO failure must not strand the sheet at "Zapisywanie…": the typed
      // traceability data stays in the form for another try.
      debugPrint('WeldJournal save error: $err');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie udało się zapisać spoiny. Dane zostają w edytorze — '
              'spróbuj ponownie.',
          en: 'Failed to save weld. Your data is kept in the editor — '
              'try again.',
        )),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  Future<void> _pickProject() async {
    FocusScope.of(context).unfocus();
    final picked = await showWeldProjectPicker(
      context,
      journalProjects: widget.journalProjects,
      current: _proj.text.trim(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _proj.text = picked.name;
      _projectId = picked.id;
      if (_autoNo) {
        _no.text = suggestNextWeldNo(widget.journal, projectName: picked.name);
      }
    });
    // Remembered now: a welder who picks the project and then abandons the
    // sheet has still told us which job he is on.
    await saveLastWeldProject(picked.name);
  }

  Future<void> _pickCoupon() async {
    FocusScope.of(context).unfocus();
    final c = await showCouponPickerSheet(context,
        currentId: _couponId,
        dao: widget.coupons,
        weldDate: normalizeWeldDate(_date.text) ?? '');
    if (c == null || !mounted) return;
    setState(() {
      _coupon.text = c.reference;
      _couponId = c.id;
      _couponRow = c;
      _couponKnown = true;
    });
  }

  Future<void> _pickWps() async {
    FocusScope.of(context).unfocus();
    final w = await showWpsPickerSheet(context, currentId: _wpsId);
    if (w == null || !mounted) return;
    setState(() {
      _wps.text = wpsRefOf(w);
      _wpsId = w.id;
      // No value typed yet: offer the WPS convention (visible and
      // changeable in the chips under the kJ/mm field).
      if (_hiMethod == null && _heatInput.text.trim().isEmpty) {
        _hiMethod = w.heatInputMethod;
      }
    });
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 10);
    final last = DateTime(now.year + 1, 12, 31);
    var initial = DateTime.tryParse(ctrl.text.trim()) ?? now;
    // Stara spoina albo literówka poza zakresem kalendarza — przycięte.
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) ctrl.text = isoDate(picked);
  }

  void _toggle(String key) =>
      setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  @override
  Widget build(BuildContext context) {
    // canPop is a constant `false`: typing into a TextField does NOT rebuild
    // this sheet, so a `!_isDirty` value registered on the first build would
    // let the back gesture drop every filled field. The decision is made in
    // the callback, at pop time, on fresh state.
    final height = MediaQuery.sizeOf(context).height;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleClose();
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: height * 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _form(context),
                ),
              ),
              _bottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
        child: Row(children: [
          Expanded(
            child: Text(
              widget.isNew
                  ? context.tr(pl: 'Nowa spoina', en: 'New weld')
                  : context.tr(pl: 'Karta spoiny', en: 'Weld card'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: kText),
            ),
          ),
          // Required, not decorative: with isDismissible/enableDrag off
          // there is no other way out on an iPhone.
          IconButton(
            icon: const Icon(Icons.close, color: kTextSec),
            tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
            onPressed: _saving ? null : _handleClose,
          ),
        ]),
      );

  /// Save buttons pinned under the form — always reachable, even with the
  /// keyboard up and 40 fields above.
  Widget _bottomBar(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 8 + MediaQuery.viewPaddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: kCard,
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : () => _save(next: true),
              child: Text(
                context.tr(pl: 'Zapisz i następna', en: 'Save & next'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving
                  ? context.tr(pl: 'Zapisywanie...', en: 'Saving...')
                  : context.tr(pl: 'Zapisz', en: 'Save')),
            ),
          ),
        ]),
      );

  InputDecoration _dec(String pl, String en, {String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: context.tr(pl: pl, en: en),
        hintText: hint,
        suffixIcon: suffix,
      );

  TextField _text(TextEditingController c, String pl, String en,
          {String? hint, bool numeric = false, Widget? suffix}) =>
      TextField(
        controller: c,
        textInputAction: TextInputAction.next,
        keyboardType: numeric ? numberKeyboard() : TextInputType.text,
        inputFormatters: numeric ? numberInputFormatters() : null,
        decoration: _dec(pl, en, hint: hint, suffix: suffix),
      );

  Widget _dropdown(String pl, String en, String value, List<String> values,
      ValueChanged<String> onChanged,
      {Map<String, String> labels = const {}}) {
    final all = [
      '',
      ...values,
      if (value.isNotEmpty && !values.contains(value)) value,
    ];
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _dec(pl, en),
      items: [
        for (final v in all)
          DropdownMenuItem(
            value: v,
            child: Text(v.isEmpty ? '—' : (labels[v] ?? v),
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => onChanged(v ?? '')),
    );
  }

  Widget _chips<T>(List<(T, String, Color)> options, T selected,
          ValueChanged<T> onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              WjChoiceChip(
                label: o.$2,
                color: o.$3,
                selected: selected == o.$1,
                onTap: () => setState(() => onTap(o.$1)),
              ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(fontSize: 12, color: kTextSec)),
      );

  Widget _form(BuildContext context) {
    final e = _build();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.isDeleted)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kFail.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kFail),
            ),
            child: Text(
              context.tr(
                  pl: 'Ta spoina jest usunięta. Przywrócisz ją z menu na '
                      'liście (⋮ → Przywróć).',
                  en: 'This weld is deleted. Restore it from the list menu '
                      '(⋮ → Restore).'),
              style: const TextStyle(fontSize: 12, color: kFail),
            ),
          ),
        if (_check != null) WeldCompliancePanel(compliance: _check!),
        if (_locked) _lockBanner(context),
        AbsorbPointer(
          absorbing: _locked,
          child: Opacity(
            opacity: _locked ? 0.6 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Identification ────────────────────────────────────────────────
                TextField(
                  controller: _no,
                  onChanged: (_) => _autoNo = false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText:
                        context.tr(pl: 'Numer spoiny', en: 'Weld number'),
                    hintText: 'W-001 / SP-001-W005',
                    errorText: _noError,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.auto_awesome, size: 20),
                      tooltip: context.tr(
                          pl: 'Następny numer wg projektu',
                          en: 'Next number for this project'),
                      onPressed: () => setState(() {
                        _no.text = suggestNextWeldNo(widget.journal,
                            projectName: _proj.text);
                        _autoNo = true;
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                WjRow([
                  TextField(
                    controller: _proj,
                    textInputAction: TextInputAction.next,
                    // A hand-typed name is not a project of the app any more.
                    onChanged: (_) => _projectId = null,
                    decoration: _dec('Projekt', 'Project',
                        suffix: IconButton(
                          icon:
                              const Icon(Icons.folder_open_outlined, size: 20),
                          tooltip: context.tr(
                              pl: 'Wybierz projekt z listy',
                              en: 'Pick a project from the list'),
                          onPressed: _saving ? null : _pickProject,
                        )),
                  ),
                  _text(_line, 'Linia', 'Line', hint: '2"-WFI-101'),
                ]),
                WjRow([
                  _text(_iso, 'Nr ISO / rysunku', 'ISO / drawing no.'),
                  _text(_isoRev, 'Rewizja', 'Revision', hint: 'A'),
                ]),
                TextField(
                  controller: _date,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: context.tr(pl: 'Data spawania', en: 'Weld date'),
                    hintText: 'RRRR-MM-DD',
                    errorText: _dateError,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month_outlined, size: 20),
                      tooltip: context.tr(pl: 'Wybierz datę', en: 'Pick date'),
                      onPressed: () => _pickDate(_date),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _label(context.tr(pl: 'Status', en: 'Status')),
                _chips<String>([
                  for (final s in WeldStatus.values)
                    (s, weldStatusShort(context, s), weldStatusColor(s)),
                  if (!WeldStatus.values.contains(_status))
                    (_status, _status, kTextSec),
                ], _status, (v) => _status = v),

                // ── Joint & material ──────────────────────────────────────────────
                WjSection(
                  title: context.tr(
                      pl: 'Złącze i materiał', en: 'Joint and material'),
                  icon: Icons.join_inner,
                  expanded: _open.contains('joint'),
                  onToggle: () => _toggle('joint'),
                  badge: [e.jointType, e.position, e.material]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  children: [
                    WjRow([
                      _text(_spool, 'Spool', 'Spool'),
                      _text(_pkg, 'Pakiet testowy', 'Test package'),
                    ]),
                    _label(context.tr(pl: 'Typ złącza', en: 'Joint type')),
                    _chips<String>([
                      ('', '—', kTextSec),
                      (
                        WeldJointType.butt,
                        context.tr(pl: 'BW doczołowe', en: 'BW butt'),
                        kArc
                      ),
                      (
                        WeldJointType.socket,
                        context.tr(pl: 'SW kielichowe', en: 'SW socket'),
                        kArc
                      ),
                      (
                        WeldJointType.branch,
                        context.tr(pl: 'Odgałęzienie', en: 'Branch'),
                        kArc
                      ),
                      (
                        WeldJointType.fillet,
                        context.tr(pl: 'FW pachwinowe', en: 'FW fillet'),
                        kArc
                      ),
                    ], _jointType, (v) => _jointType = v),
                    _chips<String>([
                      ('', '—', kTextSec),
                      (
                        WeldLocation.shop,
                        context.tr(pl: 'Warsztatowa', en: 'Shop'),
                        kArc
                      ),
                      (
                        WeldLocation.field,
                        context.tr(pl: 'Montażowa', en: 'Field'),
                        kArc
                      ),
                    ], _shopField, (v) => _shopField = v),
                    WjRow([
                      _dropdown('Pozycja', 'Position', _position,
                          kWeldPositions, (v) => _position = v),
                      _dropdown('Typ spawania', 'Weld type', _weldType,
                          _kWeldTypes, (v) => _weldType = v,
                          labels: {
                            'ORBITAL':
                                context.tr(pl: 'Orbitalna', en: 'Orbital'),
                            'AUTO':
                                context.tr(pl: 'Automatyczna', en: 'Automatic'),
                            'MANUAL': context.tr(pl: 'Ręczna', en: 'Manual'),
                          }),
                    ]),
                    _text(_mat, 'Materiał', 'Material', hint: '316L / P265GH'),
                    const SizedBox(height: 10),
                    WjRow([
                      _text(_od, 'OD (mm)', 'OD (mm)',
                          hint: '60.3', numeric: true),
                      _text(_t, 't (mm)', 't (mm)', hint: '2.0', numeric: true),
                    ]),
                    WjRow([
                      _text(_heat1, 'Nr wytopu 1', 'Heat no. 1', hint: 'MTR'),
                      _text(_heat2, 'Nr wytopu 2', 'Heat no. 2', hint: 'MTR'),
                    ]),
                  ],
                ),

                // ── Process, filler, actual parameters ────────────────────────────
                WjSection(
                  title: context.tr(
                      pl: 'Proces, WPS, spoiwo, parametry',
                      en: 'Process, WPS, filler, parameters'),
                  icon: Icons.bolt_outlined,
                  expanded: _open.contains('process'),
                  onToggle: () => _toggle('process'),
                  badge: [e.method, e.wpsRef]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  children: [
                    WjRow([
                      _dropdown('Proces', 'Process', _method, _kMethods,
                          (v) => _method = v,
                          labels: const {'Tandem': 'Tandem TIG'}),
                      TextField(
                        controller: _wps,
                        textInputAction: TextInputAction.next,
                        // A hand-typed number is matched to the library by text.
                        onChanged: (_) {
                          if (_wpsId != null) setState(() => _wpsId = null);
                        },
                        decoration: _dec('Nr WPS / pWPS', 'WPS / pWPS no.',
                            suffix: IconButton(
                              icon: const Icon(Icons.library_books_outlined,
                                  size: 20),
                              tooltip: context.tr(
                                  pl: 'Wybierz z Biblioteki WPS',
                                  en: 'Pick from the WPS library'),
                              onPressed: _saving ? null : _pickWps,
                            )),
                      ),
                    ]),
                    if (_wpsId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.tr(
                              pl: 'Z Biblioteki WPS — zakres sprawdzany przy zapisie',
                              en: 'From the WPS library — range checked on save'),
                          style: const TextStyle(fontSize: 11, color: kPass),
                        ),
                      ),
                    WjRow([
                      _text(_fillerClass, 'Spoiwo — klasyfikacja',
                          'Filler class.',
                          hint: 'ER316LSi'),
                      _text(_fillerBatch, 'Spoiwo — nr partii', 'Filler batch'),
                    ]),
                    _label(context.tr(
                        pl: 'Wartości rzeczywiste (zmierzone)',
                        en: 'Actual (measured) values')),
                    WjRow([
                      _text(_preheat, 'Podgrzanie °C', 'Preheat °C',
                          numeric: true),
                      _text(_interpass, 'Międzyścieg. °C', 'Interpass °C',
                          numeric: true),
                      _text(_heatInput, 'kJ/mm', 'kJ/mm', numeric: true),
                    ]),
                    _label(context.tr(
                        pl: 'Energia liniowa liczona wg',
                        en: 'Heat input per')),
                    _chips<HeatInputStandard?>([
                      (null, '—', kTextSec),
                      (HeatInputStandard.en1011, 'EN 1011-1 (k)', kArc),
                      (
                        HeatInputStandard.asmeIx,
                        context.tr(pl: 'ASME IX (bez k)', en: 'ASME IX (no k)'),
                        kArc
                      ),
                    ], _hiMethod, (v) => _hiMethod = v),
                  ],
                ),

                // ── Welders ───────────────────────────────────────────────────────
                WjSection(
                  title: context.tr(
                      pl: 'Spawacze i monter', en: 'Welders and fitter'),
                  icon: Icons.badge_outlined,
                  expanded: _open.contains('welders'),
                  onToggle: () => _toggle('welders'),
                  badge: e.stamps.join(' · '),
                  children: [
                    _text(_welder, 'Spawacz (stempel)', 'Welder (stamp)'),
                    const SizedBox(height: 10),
                    WjRow([
                      _text(_root, 'Stempel graniówki', 'Root stamp'),
                      _text(_cap, 'Stempel lica', 'Cap stamp'),
                    ]),
                    _text(_fitter, 'Monter (fit-up)', 'Fitter (fit-up)'),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── NDT & coupon ──────────────────────────────────────────────────
        WjSection(
          title: context.tr(pl: 'Badania NDT i kupon', en: 'NDT and coupon'),
          icon: Icons.fact_check_outlined,
          expanded: _open.contains('ndt'),
          onToggle: () => _toggle('ndt'),
          badge: [
            for (final m in NdtMethod.values)
              if (e.ndtOf(m).hasResult)
                '${m.code} ${e.ndtOf(m).result}'
              else if (e.ndtOf(m).isAwaiting)
                '${m.code} …',
          ].join(' · '),
          children: [
            WeldNdtEditor(
              initial: _ndt,
              onChanged: (v) => setState(() => _ndt = v),
            ),
            _text(_exam, 'Uwagi z badań', 'Examination remarks',
                hint: context.tr(
                    pl: 'np. boroskop poz. 2', en: 'e.g. borescope lvl 2')),
            const SizedBox(height: 10),
            TextField(
              controller: _coupon,
              // Typing by hand unlinks the coupon from the log.
              onChanged: (_) => _couponId = null,
              decoration: _dec('Kupon próbny', 'Test coupon',
                  hint: context.tr(
                      pl: 'wybierz z logu albo wpisz',
                      en: 'pick from the log or type'),
                  suffix: IconButton(
                    icon: const Icon(Icons.science_outlined, size: 20),
                    tooltip: context.tr(
                        pl: 'Wybierz z logu kuponów',
                        en: 'Pick from the coupon log'),
                    onPressed: _pickCoupon,
                  )),
            ),
            if (_couponId != null) _couponLinkRow(context),
          ],
        ),

        // ── PWHT & acceptance ─────────────────────────────────────────────
        WjSection(
          title: context.tr(pl: 'PWHT i odbiór', en: 'PWHT and acceptance'),
          icon: Icons.verified_outlined,
          expanded: _open.contains('acceptance'),
          onToggle: () => _toggle('acceptance'),
          badge: e.inspector,
          children: [
            _label(context.tr(pl: 'PWHT wymagane', en: 'PWHT required')),
            _chips<bool?>([
              (null, '—', kTextSec),
              (true, context.tr(pl: 'TAK', en: 'YES'), kArc),
              (false, context.tr(pl: 'NIE', en: 'NO'), kArc),
            ], _pwht, (v) => _pwht = v),
            WjRow([
              _text(_pwhtChart, 'Nr wykresu PWHT', 'PWHT chart no.'),
              _text(_hardness, 'Twardość', 'Hardness', hint: 'HB / HV10'),
            ]),
            WjRow([
              _text(_inspector, 'Odbiór — inspektor', 'Accepted by'),
              TextField(
                controller: _inspectedAt,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Data odbioru', en: 'Accepted on'),
                  errorText: _inspectedError,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month_outlined, size: 20),
                    tooltip: context.tr(pl: 'Wybierz datę', en: 'Pick date'),
                    onPressed: () => _pickDate(_inspectedAt),
                  ),
                ),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: _dec('Uwagi', 'Notes',
              hint: context.tr(
                  pl: 'Np. grań OK, lico do szlifowania',
                  en: 'E.g. root OK, cap to grind')),
        ),

        // ── Repairs and history (existing welds) ─────────────────────────
        if (!widget.isNew) ...[
          WjSection(
            title: context.tr(pl: 'Naprawy', en: 'Repairs'),
            icon: Icons.build_outlined,
            expanded: _open.contains('repairs'),
            onToggle: () => _toggle('repairs'),
            badge: e.repairs.map((r) => r.label).join(', '),
            children: [
              if (e.repairs.isEmpty)
                Text(
                  context.tr(
                      pl: 'Brak napraw. Naprawę R1/R2 dodasz z menu spoiny '
                          'na liście (⋮ → Naprawa).',
                      en: 'No repairs. Add repair R1/R2 from the weld menu '
                          'on the list (⋮ → Repair).'),
                  style: const TextStyle(fontSize: 12, color: kTextMut),
                )
              else
                for (final r in e.repairs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(r.summary(),
                        style: const TextStyle(fontSize: 13, color: kText)),
                  ),
            ],
          ),
          WjSection(
            title: context.tr(pl: 'Historia zmian', en: 'Change history'),
            icon: Icons.history,
            expanded: _open.contains('history'),
            onToggle: () => _toggle('history'),
            badge: _history == null
                ? ''
                : context.tr(
                    pl: 'wpisów: ${_history!.length}',
                    en: 'entries: ${_history!.length}'),
            children: [
              if (_history == null)
                const Center(child: CircularProgressIndicator(color: kArc))
              else
                WeldHistoryList(entries: _history!),
            ],
          ),
        ],
      ],
    );
  }

  Widget _lockBanner(BuildContext context) => Container(
        key: const ValueKey('weld-locked-banner'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: kPass.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kPass.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 18, color: kPass),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(
                  pl: 'Spoina odebrana — dane wykonania zablokowane. NDT, '
                      'odbiór i uwagi można uzupełniać.',
                  en: 'Weld accepted — execution data locked. NDT, acceptance '
                      'and notes stay editable.'),
              style: const TextStyle(fontSize: 12, color: kText),
            ),
          ),
          TextButton(
            onPressed: _unlock,
            child: Text(context.tr(pl: 'Odblokuj', en: 'Unlock')),
          ),
        ]),
      );

  Widget _couponLinkRow(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    final state = _couponKnown
        ? couponLinkState(_build(), _couponRow)
        : CouponLinkState.none;
    final label = state == CouponLinkState.none
        ? context.tr(
            pl: 'Powiązany z logiem kuponów', en: 'Linked to the coupon log')
        : couponLinkLabel(state, en: en);
    final color = couponLinkIsBad(state)
        ? kFail
        : state == CouponLinkState.pending
            ? kWarn
            : kPass;
    final live = _couponRow?.reference;
    return Padding(
      key: const ValueKey('weld-coupon-link'),
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        [
          label,
          if (live != null && live != _coupon.text.trim()) live,
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
