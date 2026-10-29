import '../../widgets/local_record_scope.dart';
// Temperatura podgrzania i międzyściegowa — jedna spoina: ustawienia (nr,
// opis, WPS, limity z WPS, metoda, liczba ściegów), pomiary przed ściegami,
// werdykt i udostępnianie (tekst, PDF). Zapisuje się sam przy każdej
// zmianie.
//
// Wartości kanoniczne w °C; °F to tylko wyświetlanie — przełączenie
// jednostki przepisuje pola z zapisanych wartości, nie zmienia danych ani
// werdyktu (lib/domain/welding/interpass_log.dart).

import 'dart:async';
import 'dart:convert';
import '../../assistant/core/tool_bridge.dart';

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_entry.dart';
import '../../domain/welding/interpass_log.dart';
import '../../domain/welding/interpass_text.dart';
import '../../i18n/app_language.dart';
import '../../services/interpass_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart' show FieldPair, QuoteNotice, QuoteSection;
import 'interpass_page.dart';
import 'interpass_store.dart';

class InterpassWeldPage extends StatelessWidget {
  const InterpassWeldPage({
    super.key,
    this.originSession,
    required this.initial,
    this.unit = InterpassUnit.c,
    this.store = const InterpassStore(),
    this.now = DateTime.now,
    this.shareText = interpassDefaultShareText,
    this.sharePdf = interpassDefaultSharePdf,
    this.loadWelds = interpassDefaultJournalWelds,
    this.onStoreChanged,
  });

  final LocalRecordSession? originSession;
  final InterpassWeld initial;
  final InterpassUnit unit;
  final InterpassStore store;
  final DateTime Function() now;
  final InterpassShareText shareText;
  final InterpassSharePdf sharePdf;
  final InterpassJournalSource loadWelds;

  /// Wołane po zmianie zapisu, gdy ekranu już nie ma (np. „Cofnij” kliknięte
  /// na liście spoin) — lista się odświeża.
  final Future<void> Function()? onStoreChanged;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      restartOnAccountChange: false,
      originSession: originSession,
      builder: (context, session) => _OwnedInterpassWeldPage(
          session: session,
          initial: initial,
          unit: unit,
          store: store.scoped(session.captureOwner),
          now: now,
          shareText: (text, subject) async {
            session.requireCurrent();
            await shareText(text, subject);
            session.requireCurrent();
          },
          sharePdf: (weld, english, unit) async {
            session.requireCurrent();
            if (identical(sharePdf, interpassDefaultSharePdf)) {
              await InterpassExport.sharePdf(weld,
                  english: english,
                  unit: unit,
                  validateOwner: session.requireCurrent);
            } else {
              await sharePdf(weld, english, unit);
            }
            session.requireCurrent();
          },
          loadWelds: loadWelds,
          onStoreChanged: onStoreChanged));
}

class _OwnedInterpassWeldPage extends StatefulWidget {
  const _OwnedInterpassWeldPage({
    required this.session,
    required this.initial,
    this.unit = InterpassUnit.c,
    this.store = const InterpassStore(),
    this.now = DateTime.now,
    this.shareText = interpassDefaultShareText,
    this.sharePdf = interpassDefaultSharePdf,
    this.loadWelds = interpassDefaultJournalWelds,
    this.onStoreChanged,
  });

  final LocalRecordSession session;
  final InterpassWeld initial;
  final InterpassUnit unit;
  final InterpassStore store;
  final DateTime Function() now;
  final InterpassShareText shareText;
  final InterpassSharePdf sharePdf;
  final InterpassJournalSource loadWelds;

  /// Wołane po zmianie zapisu, gdy ekranu już nie ma (np. „Cofnij” kliknięte
  /// na liście spoin) — lista się odświeża.
  final Future<void> Function()? onStoreChanged;

  @override
  State<_OwnedInterpassWeldPage> createState() => _InterpassWeldPageState();
}

class _InterpassWeldPageState extends State<_OwnedInterpassWeldPage>
    with ToolHandleHost<_OwnedInterpassWeldPage>
    implements RecordToolHandle {
  @override
  String get toolId => 'interpass';
  @override
  String? get selectedRecordId => _w.id;
  @override
  Set<String> get supportedFields => const {'weld_id'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.length != 1 || fields['weld_id'] != _w.id) {
      return fields.keys.toSet();
    }
    return await _reloadRecord() ? {} : {'weld_id'};
  }

  Future<bool> _reloadRecord() async {
    final before = jsonEncode(_w.toJson());
    final load = await widget.store.load();
    final found = load.welds.where((w) => w.id == _w.id).toList();
    if (!mounted ||
        load.corrupt ||
        found.length != 1 ||
        before != jsonEncode(_w.toJson())) {
      return false;
    }
    setState(() => _w = found.single);
    return true;
  }

  void _onStoreChanged() {
    unawaited(_reloadRecord().catchError((Object _) => false));
  }

  late InterpassWeld _w = widget.initial;
  late InterpassUnit _unit = widget.unit;
  bool _busy = false;
  bool _saveFailureShown = false;

  static bool get _enNow => AppLanguageController.isEnglish;

  late final _weldNo = TextEditingController(text: _w.weldNo);
  late final _desc = TextEditingController(text: _w.description);
  late final _wps = TextEditingController(text: _w.wpsRef);
  late final _preMin =
      TextEditingController(text: _tempText(_w.limits.preheatMin));
  late final _intMax =
      TextEditingController(text: _tempText(_w.limits.interpassMax));
  late final _intMin =
      TextEditingController(text: _tempText(_w.limits.interpassMin));
  late final _passes =
      TextEditingController(text: _w.passCount?.toString() ?? '');
  late final _mPass = TextEditingController(text: '${_w.nextPass}');
  final _mTemp = TextEditingController();
  final _mNote = TextEditingController();

  /// Data / godzina nowego pomiaru wybrane ręcznie; `null` = chwila dodania.
  DateTime? _mDate;
  String? _mTime;

  /// Kredka: stopiła się (`true`), nie stopiła się (`false`), nie wybrano.
  bool? _mMelted;

  @override
  void initState() {
    super.initState();
    InterpassStore.changes.addListener(_onStoreChanged);
    markReady();
  }

  @override
  void dispose() {
    InterpassStore.changes.removeListener(_onStoreChanged);
    for (final c in [
      _weldNo,
      _desc,
      _wps,
      _preMin,
      _intMax,
      _intMin,
      _passes,
      _mPass,
      _mTemp,
      _mNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Liczby i jednostki ─────────────────────────────────────────────────

  /// Liczba do pola: wpisana w tej jednostce — dokładnie tak, jak wpisana
  /// (400 °F zostaje „400”); w innej — przeliczona.
  String _tempText(InterpassTemp? t) =>
      t == null ? '' : formatInterpassTempNumber(t, _unit, en: _enNow);

  /// Liczba z pola w bieżącej jednostce albo `null` (puste / zła / poza
  /// zakresem).
  InterpassTemp? _parseTemp(String raw) {
    final v = parseDecimal(raw);
    if (v == null) return null;
    final t = InterpassTemp.entered(v, _unit);
    return t.valid ? t : null;
  }

  String _range() {
    final en = context.language == AppLanguage.en;
    String f(double c) =>
        formatInterpassNumber(interpassFromC(c, _unit), en: en);
    return '${f(kInterpassMinTempC)}…${f(kInterpassMaxTempC)} ${_unit.symbol}';
  }

  String? _tempError(String raw) {
    if (raw.trim().isEmpty || _parseTemp(raw) != null) return null;
    return context.tr(pl: 'Wpisz ${_range()}', en: 'Enter ${_range()}');
  }

  /// Błąd pola limitu: zły tekst NIE kasuje zapisanego limitu — mówimy, co
  /// zostało zapisane.
  String? _limitError(String raw, InterpassTemp? saved) {
    final e = _tempError(raw);
    if (e == null) return null;
    if (saved == null) {
      return context.tr(
          pl: '$e — limit niezapisany', en: '$e — limit not saved');
    }
    final s = formatInterpassTemp(saved, _unit, en: _enNow);
    return context.tr(
        pl: '$e — zapisany limit bez zmian: $s',
        en: '$e — saved limit unchanged: $s');
  }

  static int? _passNo(String raw) {
    final v = int.tryParse(raw.trim());
    return v != null && v >= 1 && v <= kInterpassMaxPass ? v : null;
  }

  String? _passError(String raw) {
    if (raw.trim().isEmpty || _passNo(raw) != null) return null;
    return context.tr(
        pl: 'Wpisz 1–$kInterpassMaxPass', en: 'Enter 1–$kInterpassMaxPass');
  }

  String? _passCountError(String raw) {
    final e = _passError(raw);
    final saved = _w.passCount;
    if (e == null || saved == null) return e;
    return context.tr(
        pl: '$e — zapisane bez zmian: $saved',
        en: '$e — saved value unchanged: $saved');
  }

  /// Przełączenie jednostki: pola przepisane z zapisanych wartości — dane
  /// i werdykt bez zmian. Wpisywany pomiar przeliczony.
  void _setUnit(InterpassUnit u) {
    if (u == _unit) return;
    final typed = _parseTemp(_mTemp.text);
    setState(() {
      _unit = u;
      _preMin.text = _tempText(_w.limits.preheatMin);
      _intMax.text = _tempText(_w.limits.interpassMax);
      _intMin.text = _tempText(_w.limits.interpassMin);
      if (typed != null) _mTemp.text = _tempText(typed);
    });
    unawaited(widget.store.saveUnit(u).catchError((Object e) {
      debugPrint('[interpass] unit save failed: $e');
    }));
  }

  // ── Zmiany i zapis ─────────────────────────────────────────────────────

  void _set(InterpassWeld Function(InterpassWeld w) change) {
    setState(() => _w =
        change(_w).copyWith(updatedAt: widget.now().millisecondsSinceEpoch));
    final snapshot = _w;
    unawaited(widget.store.upsert(snapshot).catchError((Object e) {
      debugPrint('[interpass] save failed: $e');
      _reportSaveFailure(full: e is InterpassStoreFull);
    }));
  }

  /// Raz na ekran: dowód dla QC, który się nie zapisuje, nie może tego robić
  /// po cichu.
  void _reportSaveFailure({required bool full}) {
    if (!mounted || _saveFailureShown) return;
    _saveFailureShown = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('ip-save-failed'),
      duration: const Duration(seconds: 8),
      content: Text(full
          ? context.tr(
              pl: 'Rejestr pełny (${InterpassStore.maxWelds} spoin) — ta '
                  'spoina NIE została zapisana. Udostępnij protokół i usuń '
                  'stare spoiny.',
              en: 'The log is full (${InterpassStore.maxWelds} welds) — '
                  'this weld was NOT saved. Share the record and delete old '
                  'welds.')
          : context.tr(
              pl: 'Nie udało się zapisać pomiarów w telefonie — udostępnij '
                  'protokół (tekst/PDF), żeby nie przepadł.',
              en: 'Could not save the readings on this phone — share the '
                  'record (text/PDF) so it is not lost.')),
    ));
  }

  /// Zmiana tekstu pola limitu: puste pole kasuje limit, poprawna liczba go
  /// zapisuje, a niepusty ZŁY tekst („2500”, „-”) niczego nie zmienia —
  /// zapisany limit zostaje (pole pokazuje błąd). Inaczej literówka
  /// zamieniałaby czerwony pomiar w „brak limitu”.
  void _limitChanged(
      String text, InterpassLimits Function(InterpassTemp? t) apply) {
    if (text.trim().isEmpty) {
      _set((w) => w.copyWith(limits: apply(null)));
      return;
    }
    final t = _parseTemp(text);
    if (t == null) {
      setState(() {}); // tylko komunikat błędu
      return;
    }
    _set((w) => w.copyWith(limits: apply(t)));
  }

  /// Liczba ściegów — te same zasady co przy limitach.
  void _passCountChanged(String text) {
    if (text.trim().isEmpty) {
      _set((w) => w.copyWith(passCount: null));
      return;
    }
    final n = _passNo(text);
    if (n == null) {
      setState(() {});
      return;
    }
    _set((w) => w.copyWith(passCount: n));
  }

  /// „Ustaw = min. podgrzania”: min. międzyściegowa równa podgrzaniu (ta sama
  /// wpisana wartość i jednostka).
  void _interpassMinFromPreheat() {
    final pre = _w.limits.preheatMin;
    if (pre == null) return;
    _set((w) => w.copyWith(limits: w.limits.copyWith(interpassMin: pre)));
    setState(() => _intMin.text = _tempText(pre));
  }

  void _confirmLost() {
    _set((w) => w.confirmLostReadings());
  }

  // ── Nowy pomiar ────────────────────────────────────────────────────────

  bool get _crayon => _w.method == InterpassMethod.crayon;

  DateTime _resolvedAt(DateTime now) =>
      interpassResolveAt(date: _mDate, hhmm: _mTime, now: now);

  bool get _atFuture {
    final now = widget.now();
    return interpassAtInFuture(_resolvedAt(now), now);
  }

  bool get _canAdd =>
      _passNo(_mPass.text) != null &&
      _parseTemp(_mTemp.text) != null &&
      (!_crayon || _mMelted != null) &&
      !_atFuture;

  void _addReading() {
    final pass = _passNo(_mPass.text);
    final t = _parseTemp(_mTemp.text);
    if (pass == null || t == null || (_crayon && _mMelted == null)) return;
    final now = widget.now();
    final at = _resolvedAt(now);
    if (interpassAtInFuture(at, now)) return;
    final r = InterpassReading(
      pass: pass,
      temp: t,
      bound: !_crayon
          ? InterpassBound.exact
          : _mMelted!
              ? InterpassBound.atLeast
              : InterpassBound.below,
      method: _w.method,
      at: at.millisecondsSinceEpoch,
      recordedAt: now.millisecondsSinceEpoch,
      note: _mNote.text.trim(),
    );
    final before = _w.readingsChrono;
    final latestBefore = before.isEmpty ? null : before.last;
    _set((w) => w.addReading(r));
    final check = _w.assess().checkOf(r);
    setState(() {
      _mTemp.clear();
      _mNote.clear();
      _mMelted = null;
      _mDate = null;
      _mTime = null;
      _mPass.text = '${_w.nextPass}';
    });
    unawaited(check == InterpassCheck.low || check == InterpassCheck.high
        ? Haptic.error()
        : Haptic.tap());
    // Wpis wsteczny nie zmienia oceny ściegu, którą dał późniejszy pomiar —
    // mówimy to wprost.
    if (latestBefore != null && r.at < latestBefore.at) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('ip-backdated'),
          content: Text(context.tr(
            pl: 'Pomiar z ${interpassDateTime(r.at)} jest wcześniejszy niż '
                'ostatni (${interpassDateTime(latestBefore.at)}) — lista '
                'ułożona wg czasu; o ściegu decyduje najpóźniejszy pomiar '
                'przed nim.',
            en: 'The ${interpassDateTime(r.at)} reading is earlier than the '
                'latest one (${interpassDateTime(latestBefore.at)}) — the '
                'list is in time order; the latest reading before a run '
                'decides.',
          )),
        ));
    }
  }

  void _removeReading(int index) {
    final chrono = _w.readingsChrono;
    if (index < 0 || index >= chrono.length) return;
    final removed = chrono[index];
    _set((w) => w.removeReadingAt(index));
    final undo = _undoRemoval(removed, index);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('ip-removed'),
        content:
            Text(context.tr(pl: 'Pomiar usunięty.', en: 'Reading removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () => unawaited(undo()),
        ),
      ));
  }

  /// „Cofnij” przygotowane z góry: snackbar żyje dalej po zamknięciu ekranu
  /// (wisi na liście spoin), więc zależności zbieramy teraz. Ekran otwarty —
  /// zmiana w stanie i zapis; zamknięty — wprost w zapisie, potem lista się
  /// odświeża. Pomiar wraca na dawne miejsce (ważne przy tej samej chwili).
  Future<void> Function() _undoRemoval(InterpassReading removed, int index) {
    final store = widget.store;
    final id = _w.id;
    final now = widget.now;
    final refresh = widget.onStoreChanged;
    return () async {
      if (mounted) {
        _set((w) => w.restoreReadingAt(removed, index));
        return;
      }
      try {
        await store.update(
            id,
            (w) => w
                .restoreReadingAt(removed, index)
                .copyWith(updatedAt: now().millisecondsSinceEpoch));
        await refresh?.call();
      } catch (e) {
        // Cofnięcie po wyjściu z ekranu to wygoda — błąd nie może wywalić
        // aplikacji.
        debugPrint('[interpass] undo after close failed: $e');
      }
    };
  }

  Future<void> _pickDate() async {
    final now = widget.now();
    final last = DateTime(now.year, now.month, now.day);
    final lowerBound = DateTime(2020);
    final first = last.isBefore(lowerBound) ? last : lowerBound;
    var initial = _mDate ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      builder: (context, child) => LocalRecordScope(
          restartOnAccountChange: false,
          originSession: widget.session,
          builder: (_, __) => child!),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() => _mDate = picked);
  }

  Future<void> _pickTime() async {
    final now = widget.now();
    var initial = TimeOfDay.fromDateTime(now);
    final parts = (_mTime ?? '').split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
    }
    final picked = await showTimePicker(
        context: context,
        initialTime: initial,
        builder: (context, child) => LocalRecordScope(
            restartOnAccountChange: false,
            originSession: widget.session,
            builder: (_, __) => child!));
    if (picked == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(() => _mTime = '${two(picked.hour)}:${two(picked.minute)}');
  }

  // ── Dziennik spoin ─────────────────────────────────────────────────────

  Future<void> _pickFromJournal() async {
    List<WeldEntry> welds;
    try {
      welds = (await widget.loadWelds()).where((e) => !e.isDeleted).toList();
    } catch (e) {
      debugPrint('[interpass] journal load failed: $e');
      if (!mounted) return;
      _snack('ip-journal-failed',
          pl: 'Nie udało się wczytać dziennika spoin — wpisz numer ręcznie.',
          en: 'Could not load the weld log — type the number.');
      return;
    }
    if (!mounted) return;
    if (welds.isEmpty) {
      _snack('ip-journal-empty',
          pl: 'Dziennik spoin jest pusty — wpisz numer ręcznie.',
          en: 'The weld log is empty — type the number.');
      return;
    }
    final picked = await showModalBottomSheet<WeldEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      builder: (_) => LocalRecordScope(
          restartOnAccountChange: false,
          originSession: widget.session,
          builder: (_, __) => _JournalPicker(welds: welds)),
    );
    if (picked == null || !mounted) return;
    final desc = [
      picked.projectName,
      picked.isoDrawing.isNotEmpty ? picked.isoDrawing : picked.pipeName,
      picked.material,
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');
    final fillDesc = _w.description.trim().isEmpty && desc.isNotEmpty;
    final fillWps = _w.wpsRef.trim().isEmpty && picked.wpsRef.trim().isNotEmpty;
    _set((w) => w.copyWith(
          weldNo: picked.weldNo,
          journalWeldId: picked.id,
          description: fillDesc ? desc : null,
          wpsRef: fillWps ? picked.wpsRef.trim() : null,
        ));
    setState(() {
      _weldNo.text = _w.weldNo;
      _desc.text = _w.description;
      _wps.text = _w.wpsRef;
    });
  }

  void _snack(String key, {required String pl, required String en}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          key: ValueKey(key), content: Text(context.tr(pl: pl, en: en))));
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _shareText() async {
    final en = context.language == AppLanguage.en;
    unawaited(Haptic.tap());
    try {
      await widget.shareText(interpassProtocolText(_w, _unit, en: en),
          interpassSubject(english: en));
    } catch (e) {
      debugPrint('[interpass] share text failed: $e');
    }
  }

  Future<void> _sharePdf() async {
    if (_busy) return;
    final en = context.language == AppLanguage.en;
    setState(() => _busy = true);
    try {
      await widget.sharePdf(_w, en, _unit);
    } catch (e) {
      debugPrint('[interpass] pdf export failed: $e');
      if (mounted) {
        _snack('ip-pdf-failed',
            pl: 'Nie udało się przygotować PDF.',
            en: 'Could not prepare the PDF.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Ekran ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final a = _w.assess();
    final title = _w.weldNo.trim().isEmpty
        ? context.tr(pl: 'Pomiary temperatury', en: 'Temperature readings')
        : '${context.tr(pl: 'Spoina', en: 'Weld')} ${_w.weldNo.trim()}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: const ValueKey('ip-share-text'),
            tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share as text'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            key: const ValueKey('ip-share-pdf'),
            tooltip: context.tr(pl: 'PDF protokołu', en: 'Record PDF'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _busy ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('ip-edit-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _StatusCard(
            assessment: a,
            en: en,
            unit: _unit,
            onConfirmLost: _confirmLost,
          ),
          const SizedBox(height: 10),
          _unitToggle(),
          const SizedBox(height: 12),
          _weldSection(en),
          _limitsSection(en),
          _readingsSection(a, en),
          _addSection(en),
          _rulesSection(en),
          _shareButtons(),
          const SizedBox(height: 12),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: interpassDisclaimer(en: en),
          ),
        ],
      ),
    );
  }

  Widget _unitToggle() {
    return Row(
      children: [
        Expanded(
          child: Text(
            context.tr(pl: 'Jednostka', en: 'Unit'),
            style: const TextStyle(color: kTextSec, fontSize: 13.5),
          ),
        ),
        SegmentedButton<InterpassUnit>(
          key: const ValueKey('ip-unit'),
          style: SegmentedButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: InterpassUnit.c,
                label: Text('°C', key: ValueKey('ip-unit-c'))),
            ButtonSegment(
                value: InterpassUnit.f,
                label: Text('°F', key: ValueKey('ip-unit-f'))),
          ],
          selected: {_unit},
          onSelectionChanged: (s) => _setUnit(s.first),
        ),
      ],
    );
  }

  Widget _text(String key, TextEditingController c, String label,
      ValueChanged<String> onChanged,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('ip-f-$key'),
        controller: c,
        minLines: 1,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _weldSection(bool en) {
    return QuoteSection(
      key: const ValueKey('ip-weld'),
      title: context.tr(pl: 'Spoina', en: 'Weld'),
      subtitle: context.tr(
          pl: 'Numer i opis spoiny. Zapisuje się samo.',
          en: 'Weld number and description. Saves itself.'),
      children: [
        _text('weldNo', _weldNo, context.tr(pl: 'Nr spoiny', en: 'Weld no.'),
            (t) => _set((w) => w.copyWith(weldNo: t))),
        OutlinedButton.icon(
          key: const ValueKey('ip-pick-journal'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget)),
          onPressed: _pickFromJournal,
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(context.tr(
              pl: 'Wybierz z dziennika spoin', en: 'Pick from the weld log')),
        ),
        const SizedBox(height: 10),
        _text(
            'desc',
            _desc,
            context.tr(
                pl: 'Opis (linia, izometria, materiał)',
                en: 'Description (line, isometric, material)'),
            (t) => _set((w) => w.copyWith(description: t)),
            maxLines: 3),
        _text(
            'wps',
            _wps,
            context.tr(pl: 'WPS (nr / rew.)', en: 'WPS (no. / rev.)'),
            (t) => _set((w) => w.copyWith(wpsRef: t))),
      ],
    );
  }

  Widget _tempField(
      String key,
      TextEditingController c,
      String label,
      String helper,
      InterpassTemp? saved,
      InterpassLimits Function(InterpassTemp? t) apply) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('ip-f-$key'),
        controller: c,
        keyboardType: numberKeyboard(signed: true),
        inputFormatters: numberInputFormatters(signed: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: _unit.symbol,
          helperText: helper,
          helperMaxLines: 4,
          errorText: _limitError(c.text, saved),
          errorMaxLines: 3,
        ),
        onChanged: (t) => _limitChanged(t, apply),
      ),
    );
  }

  Widget _limitsSection(bool en) {
    final l = _w.limits;
    final minUnset = l.interpassMinUnset;
    return QuoteSection(
      key: const ValueKey('ip-limits'),
      title: context.tr(pl: 'Limity z WPS', en: 'WPS limits'),
      subtitle: interpassBoundaryNote(en: en),
      children: [
        _tempField(
          'preMin',
          _preMin,
          context.tr(pl: 'Min. temperatura podgrzania', en: 'Minimum preheat'),
          context.tr(
              pl: 'Wg WPS. Ocenia pomiar przed ściegiem 1.',
              en: 'Per the WPS. Judges the reading before pass 1.'),
          l.preheatMin,
          (t) => _w.limits.copyWith(preheatMin: t),
        ),
        _tempField(
          'intMax',
          _intMax,
          context.tr(
              pl: 'Maks. temperatura międzyściegowa', en: 'Maximum interpass'),
          context.tr(
              pl: 'Wg WPS. Ocenia pomiary przed ściegiem 2 i dalej.',
              en: 'Per the WPS. Judges readings before pass 2 onwards.'),
          l.interpassMax,
          (t) => _w.limits.copyWith(interpassMax: t),
        ),
        _tempField(
          'intMin',
          _intMin,
          context.tr(
              pl: 'Min. międzyściegowa (opcjonalnie)',
              en: 'Minimum interpass (optional)'),
          minUnset
              ? context.tr(
                  pl: 'Puste = spadek poniżej podgrzania między ściegami NIE '
                      'jest kontrolowany (np. 60 °C przy podgrzaniu 150 °C '
                      'da OK). Wpisz, jeśli WPS ją podaje (np. P91).',
                  en: 'Empty = a drop below the preheat between runs is NOT '
                      'checked (e.g. 60 °C with a 150 °C preheat shows OK). '
                      'Enter it if the WPS gives one (e.g. P91).')
              : context.tr(
                  pl: 'Tylko jeśli WPS ją podaje (np. P91 — wg WPS).',
                  en: 'Only if the WPS gives one (e.g. P91 — per the WPS).'),
          l.interpassMin,
          (t) => _w.limits.copyWith(interpassMin: t),
        ),
        if (minUnset)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              key: const ValueKey('ip-intmin-from-preheat'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, kMinTapTarget)),
              onPressed: _interpassMinFromPreheat,
              icon: const Icon(Icons.south_outlined),
              label: Text(context.tr(
                  pl: 'Ustaw min. międzyściegową = min. podgrzania',
                  en: 'Set minimum interpass = minimum preheat')),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            key: const ValueKey('ip-f-passes'),
            controller: _passes,
            keyboardType: numberKeyboard(decimal: false),
            inputFormatters: numberInputFormatters(decimal: false),
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Liczba ściegów spoiny', en: 'Number of passes'),
              helperText: context.tr(
                  pl: 'Bez niej werdykt nie będzie zielony — nie wiadomo, '
                      'czy każdy ścieg ma pomiar.',
                  en: 'Without it the verdict cannot turn green — nobody '
                      'can tell whether every pass has a reading.'),
              helperMaxLines: 3,
              errorText: _passCountError(_passes.text),
              errorMaxLines: 2,
            ),
            onChanged: _passCountChanged,
          ),
        ),
        Text(
          context.tr(pl: 'Metoda pomiaru', en: 'Measuring method'),
          style: const TextStyle(color: kTextSec, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final m in InterpassMethod.values)
              ChoiceChip(
                key: ValueKey('ip-method-${m.name}'),
                label: Text(m.label(en: en)),
                selected: _w.method == m,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  if (_w.method == m) return;
                  setState(() => _mMelted = null);
                  _set((w) => w.copyWith(method: m));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          interpassMethodNote(_w.method, en: en),
          key: const ValueKey('ip-method-note'),
          style: const TextStyle(color: kTextMut, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _readingsSection(InterpassAssessment a, bool en) {
    final chrono = a.chrono;
    return QuoteSection(
      key: const ValueKey('ip-readings'),
      title: context.tr(
          pl: 'Pomiary (${chrono.length})', en: 'Readings (${chrono.length})'),
      subtitle: interpassPassRule(en: en),
      children: [
        if (chrono.isEmpty)
          Text(
            context.tr(
                pl: 'Brak pomiarów — bez nich werdykt nie będzie zielony.',
                en: 'No readings — without them the verdict cannot turn '
                    'green.'),
            key: const ValueKey('ip-readings-empty'),
            style: const TextStyle(
                color: kWarn, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        for (final (i, r) in chrono.indexed)
          _ReadingRow(
            key: ValueKey('ip-r-$i'),
            index: i,
            reading: r,
            assessment: a,
            unit: _unit,
            en: en,
            onDelete: () => _removeReading(i),
          ),
      ],
    );
  }

  Widget _addSection(bool en) {
    final now = widget.now();
    final custom = _mDate != null || _mTime != null;
    final at = _resolvedAt(now);
    final future = interpassAtInFuture(at, now);
    final pass = _passNo(_mPass.text);
    return QuoteSection(
      key: const ValueKey('ip-add'),
      title: context.tr(pl: 'Nowy pomiar', en: 'New reading'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              key: const ValueKey('ip-m-pass-minus'),
              tooltip: context.tr(pl: 'Poprzedni ścieg', en: 'Previous pass'),
              constraints: const BoxConstraints(
                  minWidth: kMinTapTarget, minHeight: kMinTapTarget),
              onPressed: pass != null && pass > 1
                  ? () => setState(() => _mPass.text = '${pass - 1}')
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('ip-m-pass'),
                controller: _mPass,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Przed ściegiem nr', en: 'Before pass no.'),
                  helperText:
                      pass == null ? null : interpassPassLabel(pass, en: en),
                  helperMaxLines: 2,
                  errorText: _passError(_mPass.text),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              key: const ValueKey('ip-m-pass-plus'),
              tooltip: context.tr(pl: 'Następny ścieg', en: 'Next pass'),
              constraints: const BoxConstraints(
                  minWidth: kMinTapTarget, minHeight: kMinTapTarget),
              onPressed: pass != null && pass < kInterpassMaxPass
                  ? () => setState(() => _mPass.text = '${pass + 1}')
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('ip-m-temp'),
          controller: _mTemp,
          keyboardType: numberKeyboard(signed: true),
          inputFormatters: numberInputFormatters(signed: true),
          decoration: InputDecoration(
            labelText: _crayon
                ? context.tr(pl: 'Próg kredki', en: 'Crayon rating')
                : context.tr(pl: 'Temperatura', en: 'Temperature'),
            suffixText: _unit.symbol,
            errorText: _tempError(_mTemp.text),
            errorMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_crayon) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const ValueKey('ip-m-melted'),
                label: Text(context.tr(
                    pl: 'Stopiła się (≥ próg)', en: 'Melted (≥ rating)')),
                selected: _mMelted == true,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => setState(() => _mMelted = true),
              ),
              ChoiceChip(
                key: const ValueKey('ip-m-notmelted'),
                label: Text(context.tr(
                    pl: 'Nie stopiła się (< próg)',
                    en: 'Not melted (< rating)')),
                selected: _mMelted == false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => setState(() => _mMelted = false),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        FieldPair(
          left: _PickButton(
            key: const ValueKey('ip-m-date'),
            icon: Icons.event_outlined,
            label: context.tr(pl: 'Data', en: 'Date'),
            value: _mDate == null
                ? context.tr(pl: 'auto', en: 'auto')
                : interpassDate(_mDate!),
            onTap: _pickDate,
          ),
          right: _PickButton(
            key: const ValueKey('ip-m-time'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Godzina', en: 'Time'),
            value: _mTime ?? context.tr(pl: 'teraz', en: 'now'),
            onTap: _pickTime,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                custom
                    ? '${context.tr(pl: 'Chwila pomiaru', en: 'Reading time')}: '
                        '${interpassDateTime(at.millisecondsSinceEpoch)}'
                    : context.tr(
                        pl: 'Chwila pomiaru: teraz (przy dodaniu). Sama '
                            'godzina = najbliższe wcześniejsze wystąpienie.',
                        en: 'Reading time: now (when added). A time alone = '
                            'its latest past occurrence.'),
                key: const ValueKey('ip-m-at'),
                style: TextStyle(
                    color: future ? kFail : kTextSec,
                    fontSize: 12.5,
                    fontWeight: future ? FontWeight.w700 : null),
              ),
            ),
            if (custom)
              TextButton(
                key: const ValueKey('ip-m-now'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                onPressed: () => setState(() {
                  _mDate = null;
                  _mTime = null;
                }),
                child: Text(context.tr(pl: 'Teraz', en: 'Now')),
              ),
          ],
        ),
        if (future)
          Text(
            context.tr(
                pl: 'Chwila w przyszłości — popraw datę lub godzinę.',
                en: 'That time is in the future — fix the date or time.'),
            key: const ValueKey('ip-m-future'),
            style: const TextStyle(
                color: kFail, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('ip-m-note'),
          controller: _mNote,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Uwagi (miejsce, odczekano…)', en: 'Notes (spot, waited…)'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('ip-m-add'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 60)),
          onPressed: _canAdd ? _addReading : null,
          icon: const Icon(Icons.add, size: 26),
          label: Text(
            context.tr(pl: 'Dodaj pomiar', en: 'Add reading'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _rulesSection(bool en) {
    return QuoteSection(
      key: const ValueKey('ip-rules'),
      title: context.tr(
          pl: 'Miejsce pomiaru i źródła', en: 'Where to measure — sources'),
      subtitle: context.tr(
          pl: 'Skrót wg źródeł streszczających EN ISO 13916. Obowiązuje WPS.',
          en: 'Summary from sources on EN ISO 13916. The WPS applies.'),
      children: [
        for (final t in interpassPlaceNotes(en: en))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $t',
                style:
                    const TextStyle(fontSize: 12.5, color: kText, height: 1.4)),
          ),
        const SizedBox(height: 4),
        for (final s in kInterpassSources)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '— ${s.label(en: en)}',
              style:
                  const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _shareButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('ip-share-text-btn'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
            label: Text(context.tr(pl: 'Tekst', en: 'Text')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('ip-share-pdf-btn'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: _busy ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(context.tr(pl: 'PDF dla QC', en: 'PDF for QC')),
          ),
        ),
      ],
    );
  }
}

// ── Widżety ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.assessment,
    required this.en,
    required this.unit,
    required this.onConfirmLost,
  });

  final InterpassAssessment assessment;
  final bool en;
  final InterpassUnit unit;
  final VoidCallback onConfirmLost;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final color = interpassStatusColor(a);
    final blockers = interpassBlockers(a, en: en);
    final superseded = a.supersededOutOfLimits.length;
    final minNote = interpassMinUnsetNote(a, unit, en: en);
    final icon = a.status == InterpassWeldStatus.outOfLimits
        ? Icons.dangerous_outlined
        : a.ok
            ? Icons.verified_outlined
            : Icons.thermostat_outlined;
    return Material(
      key: const ValueKey('ip-status'),
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                key: const ValueKey('ip-status-icon'), color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    interpassStatusText(a, en: en),
                    key: const ValueKey('ip-status-text'),
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w800),
                  ),
                  if (blockers.length > 1) ...[
                    const SizedBox(height: 6),
                    for (final b in blockers)
                      Text('• $b',
                          style: const TextStyle(
                              color: kText, fontSize: 13, height: 1.35)),
                  ],
                  if (superseded > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      en
                          ? '$superseded out-of-limit reading(s) superseded '
                              'by a later reading before the same pass — '
                              'kept in the record.'
                          : 'Pomiarów poza limitem zastąpionych późniejszym '
                              'pomiarem przed tym samym ściegiem: '
                              '$superseded — zostają w protokole.',
                      key: const ValueKey('ip-status-superseded'),
                      style: const TextStyle(
                          color: kTextSec, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                  if (minNote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      minNote,
                      key: const ValueKey('ip-status-nomin'),
                      style: TextStyle(
                          color: a.belowPreheatUnchecked.isEmpty
                              ? kTextSec
                              : kWarn,
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: a.belowPreheatUnchecked.isEmpty
                              ? null
                              : FontWeight.w700),
                    ),
                  ],
                  if (a.lostReadings > 0) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('ip-lost-confirm'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, kMinTapTarget)),
                      onPressed: onConfirmLost,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(en
                          ? 'Checked against the paper record — confirm'
                          : 'Sprawdzone z zapisem papierowym — potwierdzam'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    super.key,
    required this.index,
    required this.reading,
    required this.assessment,
    required this.unit,
    required this.en,
    required this.onDelete,
  });

  final int index;
  final InterpassReading reading;
  final InterpassAssessment assessment;
  final InterpassUnit unit;
  final bool en;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final a = assessment;
    final check = a.checkOf(r);
    final decisive = a.isDecisive(r);
    final base = switch (check) {
      InterpassCheck.ok => kPass,
      InterpassCheck.low || InterpassCheck.high => kFail,
      InterpassCheck.unconfirmed => kWarn,
      InterpassCheck.noLimit => kTextSec,
    };
    final color = decisive ? base : kTextMut;
    final head = [
      '${en ? 'Pass' : 'Ścieg'} ${r.pass}',
      interpassReadingValue(r, unit, en: en),
      interpassCheckLabel(check, en: en),
    ].join(' · ');
    final flags = interpassReadingFlags(r, a, en: en);
    final sub = [
      interpassDateTime(r.at),
      r.method.short(en: en),
      if (r.note.trim().isNotEmpty) r.note.trim(),
      if (flags.isNotEmpty) flags,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(Icons.thermostat, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head,
                        key: ValueKey('ip-r-head-$index'),
                        style: TextStyle(
                            color: color == kTextSec ? kText : color,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            decoration:
                                decisive ? null : TextDecoration.lineThrough)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            color: kTextSec, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('ip-r-del-$index'),
                tooltip: en ? 'Remove reading' : 'Usuń pomiar',
                constraints: const BoxConstraints(
                    minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: kTextSec),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Przycisk wyboru daty / godziny: etykieta nad wartością, 56 dp.
class _PickButton extends StatelessWidget {
  const _PickButton({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 56),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        foregroundColor: kText,
        side: const BorderSide(color: kBorder),
      ),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: kTextSec),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11.5, color: kTextMut)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista wyboru spoiny z dziennika (z wyszukiwaniem).
class _JournalPicker extends StatefulWidget {
  const _JournalPicker({required this.welds});

  final List<WeldEntry> welds;

  @override
  State<_JournalPicker> createState() => _JournalPickerState();
}

class _JournalPickerState extends State<_JournalPicker> {
  String _q = '';

  String _sub(WeldEntry e) => [
        e.projectName,
        e.isoDrawing.isNotEmpty ? e.isoDrawing : e.pipeName,
        e.material,
        if (e.wpsRef.trim().isNotEmpty) 'WPS ${e.wpsRef.trim()}',
      ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.welds
        : widget.welds
            .where((e) =>
                e.weldNo.toLowerCase().contains(q) ||
                _sub(e).toLowerCase().contains(q))
            .toList();
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const ValueKey('ip-journal-search'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.tr(
                        pl: 'Szukaj spoiny (nr, projekt, ISO)',
                        en: 'Search weld (no., project, ISO)'),
                  ),
                  onChanged: (t) => setState(() => _q = t),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey('ip-journal-list'),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final e = list[i];
                    final sub = _sub(e);
                    return ListTile(
                      key: ValueKey('ip-journal-${e.id}'),
                      minVerticalPadding: 10,
                      leading: const Icon(Icons.adjust, color: kArc),
                      title: Text(
                          e.weldNo.trim().isEmpty ? '—' : e.weldNo.trim(),
                          style: const TextStyle(
                              color: kText, fontWeight: FontWeight.w700)),
                      subtitle: sub.isEmpty
                          ? null
                          : Text(sub,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kTextSec)),
                      onTap: () => Navigator.pop(context, e),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
