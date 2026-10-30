// Tolerancje spoola — protokół jednego spoola: dane z izometrii, zestaw
// tolerancji (PFI ES-3 / EN 13480-4 / z projektu), pozycje pomiaru
// z werdyktem, kalkulatory (nachylenie czoła, skręt otworów), ściąga „jak
// mierzyć”, źródła i udostępnianie tekstu. Zapisuje się sam przy każdej
// zmianie.
//
// Zasady (lib/domain/spool_check/spool_check.dart): werdykt w mm, niezależny
// od jednostki wyświetlania; brak danych = brak werdyktu; spool „w
// tolerancji” tylko, gdy KAŻDA pozycja ma werdykt OK.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../domain/spool_check/spool_check.dart';
import '../../domain/spool_check/spool_check_text.dart';
import '../../i18n/app_language.dart';
import '../../services/owned_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/local_record_scope.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart' show FieldPair, QuoteNotice, QuoteSection;
import 'spool_check_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef SpoolCheckShareText = Future<void> Function(
    String text, String subject);

Future<void> spoolCheckDefaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Color spoolOverallColor(SpoolOverall o) => switch (o) {
      SpoolOverall.ok => kPass,
      SpoolOverall.out => kFail,
      SpoolOverall.incomplete => kWarn,
      SpoolOverall.empty => kTextSec,
    };

IconData spoolOverallIcon(SpoolOverall o) => switch (o) {
      SpoolOverall.ok => Icons.verified_outlined,
      SpoolOverall.out => Icons.report_outlined,
      SpoolOverall.incomplete => Icons.pending_actions_outlined,
      SpoolOverall.empty => Icons.straighten,
    };

Color spoolVerdictColor(SpoolVerdict v) => switch (v) {
      SpoolVerdict.ok => kPass,
      SpoolVerdict.out => kFail,
      SpoolVerdict.none => kWarn,
    };

/// Komunikat „pamięć niedostępna” — zapis uszkodzony, a kopii nie udało
/// się zrobić; magazyn nic nie zapisał ([SpoolCheckStoreUnavailable]).
String spoolStoreUnavailableText(BuildContext context) => context.tr(
      pl: 'Pamięć niedostępna — nic nie zapisano. Zapis historii jest '
          'uszkodzony, a jego kopii nie udało się zrobić, więc historii nie '
          'nadpisujemy. Udostępnij protokół tekstem.',
      en: 'Storage unavailable — nothing was saved. The saved history is '
          'damaged and its backup could not be made, so the history is not '
          'overwritten. Share the record as text.',
    );

class SpoolCheckEditPage extends StatefulWidget {
  const SpoolCheckEditPage({
    super.key,
    required this.initial,
    this.store,
    this.session,
    this.now = DateTime.now,
    this.shareText = spoolCheckDefaultShareText,
    this.newId,
  });

  final SpoolCheck initial;
  final SpoolCheckStore? store;
  final LocalRecordSession? session;
  final DateTime Function() now;
  final SpoolCheckShareText shareText;

  /// Identyfikator nowej pozycji — wstrzykiwany w testach.
  final String Function()? newId;

  @override
  State<SpoolCheckEditPage> createState() => _SpoolCheckEditPageState();
}

class _SpoolCheckEditPageState extends State<SpoolCheckEditPage> {
  late SpoolCheck _p = widget.initial;
  late final LocalRecordSession _session;
  late final SpoolCheckStore _store;

  late final _spoolNo = TextEditingController(text: _p.spoolNo);
  late final _isoNo = TextEditingController(text: _p.isoNo);
  late final _drawingNo = TextEditingController(text: _p.drawingNo);
  late final _revision = TextEditingController(text: _p.revision);
  late final _inspector = TextEditingController(text: _p.inspector);
  late final _dn = TextEditingController(text: _p.dn?.toString() ?? '');
  late final _enGrade = TextEditingController(text: _p.enGrade);
  late final _notes = TextEditingController(text: _p.notes);

  bool _saveFailureShown = false;

  /// Numery spooli innych protokołów z historii (do ostrzeżenia o
  /// duplikacie). `null` — jeszcze nie wczytano.
  Set<String>? _otherNos;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? LocalRecordSession.capture();
    _store = widget.store ??
        SpoolCheckStore(
            prefs: () => OwnedPrefs.instance(_session.captureOwner));
    unawaited(_loadOtherNos());
  }

  Future<void> _loadOtherNos() async {
    try {
      final all = await _store.load();
      if (!mounted || !_session.isCurrent) return;
      setState(() => _otherNos = {
            for (final c in all)
              if (c.id != _p.id && c.spoolNo.trim().isNotEmpty)
                spoolNoKey(c.spoolNo),
          });
    } catch (e) {
      debugPrint('[spool_check] history numbers: $e');
    }
  }

  /// Numer spoola jest już w historii (inny protokół) — ostrzeżenie, nie
  /// blokada.
  bool get _duplicateNo {
    final no = _p.spoolNo.trim();
    return no.isNotEmpty && (_otherNos?.contains(spoolNoKey(no)) ?? false);
  }

  @override
  void dispose() {
    for (final c in [
      _spoolNo,
      _isoNo,
      _drawingNo,
      _revision,
      _inspector,
      _dn,
      _enGrade,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _id() => widget.newId?.call() ?? const Uuid().v4();

  // ── Zmiany i zapis ─────────────────────────────────────────────────────

  void _set(SpoolCheck Function(SpoolCheck p) change) {
    if (!mounted || !_session.isCurrent) return;
    setState(() => _p =
        change(_p).copyWith(updatedAt: widget.now().millisecondsSinceEpoch));
    final snapshot = _p;
    unawaited(_store.upsert(snapshot).catchError((Object e) {
      debugPrint('[spool_check] save failed: $e');
      _reportSaveFailure(
          full: e is SpoolCheckStoreFull,
          unavailable: e is SpoolCheckStoreUnavailable);
    }));
  }

  /// Raz na ekran — protokół, który się nie zapisuje, nie może tego robić
  /// po cichu.
  void _reportSaveFailure({bool full = false, bool unavailable = false}) {
    if (!mounted || !_session.isCurrent || _saveFailureShown) return;
    _saveFailureShown = true;
    if (unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const ValueKey('sc-store-unavailable'),
        content: Text(spoolStoreUnavailableText(context)),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: ValueKey(full ? 'sc-store-full' : 'sc-save-failed'),
      content: Text(full
          ? context.tr(
              pl: 'Historia pełna (${SpoolCheckStore.maxEntries} protokołów) '
                  '— ten protokół NIE jest zapisany. Udostępnij go i usuń '
                  'stare protokoły z historii.',
              en: 'History full (${SpoolCheckStore.maxEntries} records) — '
                  'this record is NOT saved. Share it and delete old records '
                  'from the history.')
          : context.tr(
              pl: 'Nie udało się zapisać protokołu w telefonie — udostępnij '
                  'go, żeby nie przepadł.',
              en: 'Could not save the record on this phone — share it so it '
                  'is not lost.')),
    ));
  }

  void _setItem(SpoolItem item) => _set((p) => p.withItem(item));

  /// Nowa pozycja — ZAWSZE bez tolerancji: werdykt dopiero po świadomym
  /// wpisie (podpowiedź z poprzedniej pozycji to tylko przycisk w karcie).
  void _addItem(SpoolItemKind kind) {
    final item = SpoolItem(id: _id(), kind: kind);
    _set((p) => p.copyWith(items: [...p.items, item]));
  }

  /// Podpowiedź tolerancji dla pozycji [index]: najbliższa wcześniejsza
  /// pozycja tego samego rodzaju z wpisaną tolerancją ± — (nr poz., mm).
  /// Tylko przy zestawach wpisywanych.
  (int, double)? _suggestion(int index) {
    if (_p.toleranceSet == SpoolToleranceSet.pfiEs3) return null;
    final it = _p.items[index];
    if (it.toleranceMm != null || it.toleranceDamaged || it.hasAsymmetric) {
      return null;
    }
    for (var j = index - 1; j >= 0; j--) {
      final prev = _p.items[j];
      final t = prev.toleranceMm;
      if (prev.kind == it.kind && t != null && spoolToleranceValid(t)) {
        return (j + 1, t);
      }
    }
    return null;
  }

  void _removeItem(SpoolItem item) {
    if (!mounted || !_session.isCurrent) return;
    final index = _p.items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    _set((p) =>
        p.copyWith(items: [...p.items]..removeWhere((i) => i.id == item.id)));
    final store = _store;
    final checkId = _p.id;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sc-item-removed'),
        content: Text(context.tr(pl: 'Pozycja usunięta.', en: 'Item removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () {
            if (!_session.isCurrent) return;
            if (mounted) {
              if (_p.items.any((i) => i.id == item.id)) return;
              final list = [..._p.items]
                ..insert(index.clamp(0, _p.items.length), item);
              _set((p) => p.copyWith(items: list));
            } else {
              // Ekranu już nie ma — przywracamy w zapisie.
              unawaited(store.restoreItem(checkId, item, index));
            }
          },
        ),
      ));
  }

  Future<void> _pickDate() async {
    if (!_session.isCurrent) return;
    final first = DateTime(2000);
    final last = DateTime(2100);
    var current = DateTime.tryParse(_p.date) ?? widget.now();
    if (current.isBefore(first)) current = first;
    if (current.isAfter(last)) current = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: first,
      lastDate: last,
      builder: (_, child) => LocalRecordScope(
        originSession: _session,
        restartOnAccountChange: false,
        builder: (_, __) => child!,
      ),
    );
    if (picked == null || !mounted || !_session.isCurrent) return;
    _set((p) => p.copyWith(date: spoolDate(picked)));
  }

  String? get _dnError {
    final t = _dn.text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || !spoolDnValid(v)) {
      return context.tr(
          pl: 'Wpisz DN 1–$kSpoolMaxDn', en: 'Enter DN 1–$kSpoolMaxDn');
    }
    return null;
  }

  Future<void> _shareText() async {
    if (!_session.isCurrent) return;
    final en = context.language == AppLanguage.en;
    await widget.shareText(
        spoolCheckProtocolText(_p, en: en), spoolCheckSubject(en: en));
  }

  // ── Ekran ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final result = _p.evaluate();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Protokół spoola', en: 'Spool record')),
        actions: [
          IconButton(
            key: const ValueKey('sc-share-text'),
            tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share as text'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('sc-edit-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _StatusCard(check: _p, result: result, en: en),
          const SizedBox(height: 12),
          if (_p.damagedOnLoad > 0)
            QuoteNotice(
              key: const ValueKey('sc-damaged-notice'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: context.tr(
                pl: 'Zapis tego protokołu był częściowo nieczytelny '
                    '(${_p.damagedOnLoad}) — pominięte pola są puste, kopia '
                    'surowego zapisu została w telefonie. Sprawdź pozycje.',
                en: 'Part of this record could not be read '
                    '(${_p.damagedOnLoad}) — the skipped fields are empty, a '
                    'raw copy is kept on the phone. Check the items.',
              ),
            ),
          if (_p.spoolNo.trim().isEmpty && !_p.isBlank)
            QuoteNotice(
              key: const ValueKey('sc-spoolno-missing'),
              icon: Icons.edit_note,
              text: context.tr(
                  pl: 'Uzupełnij numer spoola — bez niego protokołu nie da się '
                      'przypisać do spoola na budowie.',
                  en: 'Fill in the spool number — without it the record cannot '
                      'be matched to the spool on site.'),
            ),
          if (_duplicateNo)
            QuoteNotice(
              key: const ValueKey('sc-spoolno-duplicate'),
              icon: Icons.copy_outlined,
              text: context.tr(
                  pl: 'Spool „${_p.spoolNo.trim()}” jest już w historii — '
                      'sprawdź numer (protokół zapisuje się mimo to).',
                  en: 'Spool “${_p.spoolNo.trim()}” is already in the history '
                      '— check the number (the record is saved anyway).'),
            ),
          _headerSection(en),
          _toleranceSection(en),
          _itemsSection(result, en),
          _addSection(en),
          QuoteSection(
            title: context.tr(pl: 'Uwagi', en: 'Notes'),
            children: [
              TextField(
                key: const ValueKey('sc-f-notes'),
                controller: _notes,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Ustalenia, decyzje, poprawki',
                      en: 'Findings, decisions, corrections'),
                ),
                onChanged: (t) => _set((p) => p.copyWith(notes: t)),
              ),
            ],
          ),
          _howToSection(en),
          _sourcesSection(en),
          OutlinedButton.icon(
            key: const ValueKey('sc-share-text-btn'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
            label: Text(context.tr(
                pl: 'Udostępnij protokół (tekst)',
                en: 'Share the record (text)')),
          ),
          const SizedBox(height: 12),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: spoolCheckDisclaimer(en: en),
          ),
        ],
      ),
    );
  }

  Widget _text(String key, TextEditingController c, String label,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('sc-f-$key'),
        controller: c,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }

  Widget _headerSection(bool en) {
    return QuoteSection(
      title: context.tr(pl: 'Spool', en: 'Spool'),
      subtitle: context.tr(
          pl: 'Dane z izometrii. Protokół zapisuje się sam.',
          en: 'Details from the isometric. The record saves itself.'),
      children: [
        _text('spoolNo', _spoolNo, context.tr(pl: 'Nr spoola', en: 'Spool no.'),
            (t) => _set((p) => p.copyWith(spoolNo: t))),
        _text(
            'isoNo',
            _isoNo,
            context.tr(pl: 'Nr izometrii / linii', en: 'Isometric / line no.'),
            (t) => _set((p) => p.copyWith(isoNo: t))),
        FieldPair(
          left: _text(
              'drawingNo',
              _drawingNo,
              context.tr(pl: 'Rysunek', en: 'Drawing'),
              (t) => _set((p) => p.copyWith(drawingNo: t))),
          right: _text(
              'revision',
              _revision,
              context.tr(pl: 'Rewizja', en: 'Revision'),
              (t) => _set((p) => p.copyWith(revision: t))),
        ),
        _text(
            'inspector',
            _inspector,
            context.tr(pl: 'Mierzył', en: 'Measured by'),
            (t) => _set((p) => p.copyWith(inspector: t))),
        OutlinedButton(
          key: const ValueKey('sc-date'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 56),
            alignment: Alignment.centerLeft,
            foregroundColor: kText,
            side: const BorderSide(color: kBorder),
          ),
          onPressed: _pickDate,
          child: Row(
            children: [
              const Icon(Icons.event_outlined, size: 20, color: kTextSec),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.tr(pl: 'Data pomiaru', en: 'Check date')}: '
                  '${_p.date}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('sc-f-dn'),
          controller: _dn,
          keyboardType: numberKeyboard(decimal: false),
          inputFormatters: numberInputFormatters(decimal: false),
          decoration: InputDecoration(
            labelText: context.tr(pl: 'DN spoola', en: 'Spool DN'),
            helperText: context.tr(
                pl: 'Pasmo tolerancji liniowej ES-3 (np. 150).',
                en: 'ES-3 linear tolerance band (e.g. 150).'),
            errorText: _dnError,
          ),
          onChanged: (t) {
            final v = int.tryParse(t.trim());
            _set(
                (p) => p.copyWith(dn: v != null && spoolDnValid(v) ? v : null));
          },
        ),
        const SizedBox(height: 12),
        Text(context.tr(pl: 'Jednostka', en: 'Units'),
            style: const TextStyle(fontSize: 12.5, color: kTextSec)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final u in SpoolUnit.values)
              ChoiceChip(
                key: ValueKey('sc-unit-${u.name}'),
                label: Text(u == SpoolUnit.mm
                    ? 'mm'
                    : context.tr(pl: 'cale (1/16″)', en: 'inches (1/16″)')),
                selected: _p.unit == u,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _set((p) => p.copyWith(unit: u)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
              pl: 'Zmiana jednostki zmienia tylko wyświetlanie — werdykt '
                  'liczy się w mm.',
              en: 'Changing units only changes the display — the verdict is '
                  'computed in mm.'),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      ],
    );
  }

  Widget _toleranceSection(bool en) {
    final set = _p.toleranceSet;
    final unit = _p.unit;
    String both(double mm) => spoolFormatBoth(mm, unit, en: en);
    final band = _p.dn == null ? null : es3LinearBandFor(_p.dn!);
    return QuoteSection(
      key: const ValueKey('sc-tolerances'),
      title: context.tr(pl: 'Tolerancje', en: 'Tolerances'),
      subtitle: context.tr(
          pl: 'Wobec czego oceniamy. Tolerancja wpisana przy pozycji '
              '(z rysunku) zastępuje zestaw.',
          en: 'What the items are judged against. A tolerance entered at an '
              'item (from the drawing) overrides the set.'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in SpoolToleranceSet.values)
              ChoiceChip(
                key: ValueKey('sc-set-${s.name}'),
                label: Text(s.label(en: en)),
                selected: set == s,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _set((p) => p.copyWith(toleranceSet: s)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (set == null)
          QuoteNotice(
            key: const ValueKey('sc-set-unreadable'),
            color: kFail,
            text: context.tr(
                pl: 'Zapisany zestaw tolerancji jest nieczytelny — wybierz '
                    'go ponownie. Do tego czasu pozycje nie mają werdyktu.',
                en: 'The saved tolerance set is unreadable — choose it '
                    'again. Until then the items have no verdict.'),
          ),
        if (set == SpoolToleranceSet.pfiEs3) ...[
          _infoLine(
            key: 'sc-es3-linear',
            text: band == null
                ? context.tr(
                    pl: 'Długości: ${_p.dn == null ? 'wpisz DN spoola' : 'DN ${_p.dn} ponad 900 — wartości ES-3 nie potwierdzono, wpisz tolerancję z projektu'}.',
                    en: 'Lengths: ${_p.dn == null ? 'enter the spool DN' : 'DN ${_p.dn} above 900 — ES-3 value not confirmed, enter the design tolerance'}.')
                : context.tr(
                    pl: 'Długości (F–F, C–F, C–C, położenie): ±${both(band.mm)} '
                        '— ${band.sizeLabel(en: false)}; norma: '
                        '${spoolInchFraction(band.inch)}″ / '
                        '${spoolNum(band.metricMm, en: false)} mm, '
                        'przyjęto ostrzejszą.',
                    en: 'Lengths (F–F, C–F, C–C, location): ±${both(band.mm)} '
                        '— ${band.sizeLabel(en: true)}; standard: '
                        '${spoolInchFraction(band.inch)}″ / '
                        '${spoolNum(band.metricMm, en: true)} mm, the '
                        'stricter one is used.'),
          ),
          _infoLine(
            key: 'sc-es3-rotation',
            text: context.tr(
                pl: 'Skręt otworów: ${both(kEs3RotationMm)} (1/16″; '
                    'ekwiwalenty metryczne w kopiach normy są łagodniejsze).',
                en: 'Bolt-hole rotation: ${both(kEs3RotationMm)} (1/16″; the '
                    'metric equivalents in the copies are looser).'),
          ),
          _infoLine(
            key: 'sc-es3-tilt',
            text: context.tr(
                pl: 'Nachylenie czoła: 3/64″ na stopę średnicy, nie mniej niż '
                    '1/32″ (${spoolFormatMm(es3FaceAlignmentLimitMm(0), en: false)}) '
                    '— granica liczona dla średnicy, na której zmierzono.',
                en: 'Face tilt: 3/64″ per foot of diameter, not less than '
                    '1/32″ (${spoolFormatMm(es3FaceAlignmentLimitMm(0), en: true)}) '
                    '— the limit uses the diameter measured across.'),
          ),
          _infoLine(
            key: 'sc-es3-none',
            text: context.tr(
                pl: 'Przesunięcie boczne odgałęzienia, prostoliniowość: ES-3 '
                    '(sprawdzone kopie) nie podaje — wpisz tolerancję '
                    'z projektu przy pozycji.',
                en: 'Branch lateral offset, straightness: not given in ES-3 '
                    '(checked copies) — enter the design tolerance at the '
                    'item.'),
          ),
        ],
        if (set == SpoolToleranceSet.en13480) ...[
          TextField(
            key: const ValueKey('sc-f-enGrade'),
            controller: _enGrade,
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Klasa (grade) zał. B uzgodniona przed prefabrykacją',
                  en: 'Annex B grade agreed before fabrication'),
            ),
            onChanged: (t) => _set((p) => p.copyWith(enGrade: t)),
          ),
          const SizedBox(height: 8),
          _infoLine(
            key: 'sc-en-info',
            text: context.tr(
                pl: 'EN 13480-4:2017 p. 5.6: tolerancje spooli — zał. B '
                    '(3 klasy). Wartości zał. B nie są wbudowane — wpisz je '
                    'przy każdej pozycji z egzemplarza normy.',
                en: 'EN 13480-4:2017 cl. 5.6: spool tolerances — Annex B '
                    '(3 grades). Annex B values are not built in — enter them '
                    'at each item from your copy of the standard.'),
          ),
        ],
        if (set == SpoolToleranceSet.project)
          _infoLine(
            key: 'sc-project-info',
            text: context.tr(
                pl: 'Wpisz tolerancję z projektu / specyfikacji przy każdej '
                    'pozycji: ± albo osobno + i − (np. +0 / −3) dla długości. '
                    'Puste pole = brak werdyktu; wartość z poprzedniej pozycji '
                    'tego rodzaju można przyjąć jednym stuknięciem.',
                en: 'Enter the design / specification tolerance at each item: '
                    '± or separate + and − (e.g. +0 / −3) for lengths. An '
                    'empty field = no verdict; the value from the previous '
                    'item of that kind can be taken with one tap.'),
          ),
      ],
    );
  }

  Widget _infoLine({required String key, required String text}) => Padding(
        key: ValueKey(key),
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('• $text',
            style: const TextStyle(fontSize: 13, color: kText, height: 1.35)),
      );

  Widget _itemsSection(SpoolCheckResult result, bool en) {
    return QuoteSection(
      key: const ValueKey('sc-items'),
      title: context.tr(
          pl: 'Pozycje pomiaru (${result.items.length})',
          en: 'Measurement items (${result.items.length})'),
      subtitle: context.tr(
          pl: 'Wymiar z rysunku i zmierzony → odchyłka, tolerancja, werdykt.',
          en: 'Drawing and measured dimension → deviation, tolerance, '
              'verdict.'),
      children: [
        if (result.items.isEmpty)
          Text(
            context.tr(
                pl: 'Brak pozycji — dodaj poniżej.',
                en: 'No items — add them below.'),
            key: const ValueKey('sc-items-empty'),
            style: const TextStyle(color: kTextSec, fontSize: 13.5),
          ),
        for (final (i, r) in result.items.indexed)
          _ItemCard(
            key: ValueKey('sc-card-${r.item.id}'),
            index: i,
            result: r,
            check: _p,
            en: en,
            suggestion: _suggestion(i),
            onChanged: _setItem,
            onDelete: () => _removeItem(r.item),
          ),
      ],
    );
  }

  Widget _addSection(bool en) {
    return QuoteSection(
      key: const ValueKey('sc-add'),
      title: context.tr(pl: 'Dodaj pozycję', en: 'Add item'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in SpoolItemKind.values)
              OutlinedButton.icon(
                key: ValueKey('sc-add-${k.name}'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: () => _addItem(k),
                icon: const Icon(Icons.add, size: 18),
                label: Text(k.label(en: en)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _howToSection(bool en) {
    return QuoteSection(
      key: const ValueKey('sc-howto'),
      title: context.tr(
          pl: 'Jak mierzyć — praktyka warsztatowa',
          en: 'How to measure — shop practice'),
      subtitle: context.tr(
          pl: 'Praktyka warsztatowa, nie wymagania normy.',
          en: 'Shop practice, not requirements of a standard.'),
      children: [
        for (final s in kSpoolHowToMeasure)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• ${s.label(en: en)}',
                style:
                    const TextStyle(fontSize: 13, color: kText, height: 1.4)),
          ),
      ],
    );
  }

  Widget _sourcesSection(bool en) {
    return QuoteSection(
      key: const ValueKey('sc-sources'),
      title: context.tr(
          pl: 'Źródła i wartości odniesienia',
          en: 'Sources and reference values'),
      children: [
        for (final s in kSpoolCheckSources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• ${s.label(en: en)}',
                style: const TextStyle(
                    fontSize: 12.5, color: kTextSec, height: 1.4)),
          ),
      ],
    );
  }
}

// ── Widżety ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard(
      {required this.check, required this.result, required this.en});

  final SpoolCheck check;
  final SpoolCheckResult result;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final o = result.overall;
    final color = spoolOverallColor(o);
    final counts = en
        ? 'Within: ${result.count(SpoolVerdict.ok)} · out: '
            '${result.count(SpoolVerdict.out)} · no verdict: '
            '${result.count(SpoolVerdict.none)}'
        : 'W tolerancji: ${result.count(SpoolVerdict.ok)} · poza: '
            '${result.count(SpoolVerdict.out)} · bez werdyktu: '
            '${result.count(SpoolVerdict.none)}';
    return Material(
      key: const ValueKey('sc-status'),
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
            Icon(spoolOverallIcon(o), color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spoolOverallText(result, en: en),
                    key: const ValueKey('sc-status-text'),
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${en ? 'Judged against' : 'Oceniono wobec'}: '
                    '${spoolSetBasisText(check, en: en)}',
                    key: const ValueKey('sc-status-basis'),
                    style: const TextStyle(
                        color: kText, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(counts,
                      style: const TextStyle(
                          color: kTextSec, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pole liczbowe pozycji: mm — klawiatura numeryczna; cale — tekstowa
/// (ułamki „98 1/2”, „3/16” potrzebują spacji i ukośnika).
final _inchFormatters = <TextInputFormatter>[
  CharsetInputFormatter(RegExp('[0-9.,/ \'"\\-]')),
];

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    super.key,
    required this.index,
    required this.result,
    required this.check,
    required this.en,
    required this.onChanged,
    required this.onDelete,
    this.suggestion,
  });

  final int index;
  final SpoolItemResult result;
  final SpoolCheck check;
  final bool en;

  /// Podpowiedź tolerancji: (nr pozycji, mm) — przyjmowana stuknięciem.
  final (int, double)? suggestion;
  final ValueChanged<SpoolItem> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  SpoolItem get _it => widget.result.item;
  SpoolUnit get _unit => widget.check.unit;
  bool get _en => widget.en;
  String get _k => 'sc-i-${widget.index}';

  late final _label = TextEditingController(text: _it.label);
  late final _drawing = TextEditingController();
  late final _measured = TextEditingController();
  late final _base = TextEditingController();
  late final _angle = TextEditingController(
      text: _it.angleDeg == null ? '' : spoolNum(_it.angleDeg!, en: _en));
  late final _dn = TextEditingController(text: _it.dn?.toString() ?? '');
  late final _tol = TextEditingController();
  late final _tolPlus = TextEditingController();
  late final _tolMinus = TextEditingController();
  late final _note = TextEditingController(text: _it.note);
  final _gapA = TextEditingController();
  final _gapB = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fillLengths();
  }

  /// Pola długości w jednostce protokołu z wartości zapisanych (mm).
  void _fillLengths() {
    _drawing.text = spoolFieldText(_it.drawingMm, _unit, en: _en);
    _measured.text = spoolFieldText(_it.measuredMm, _unit, en: _en);
    _base.text = spoolFieldText(_it.baseMm, _unit, en: _en);
    _tol.text = spoolFieldText(_it.toleranceMm, _unit, en: _en);
    _tolPlus.text = spoolFieldText(_it.tolPlusMm, _unit, en: _en);
    _tolMinus.text = spoolFieldText(_it.tolMinusMm, _unit, en: _en);
    _gapA.clear();
    _gapB.clear();
  }

  @override
  void didUpdateWidget(_ItemCard old) {
    super.didUpdateWidget(old);
    // Zmiana jednostki — tylko wyświetlanie; wartości w mm bez zmian.
    if (old.check.unit != widget.check.unit) _fillLengths();
  }

  @override
  void dispose() {
    for (final c in [
      _label,
      _drawing,
      _measured,
      _base,
      _angle,
      _dn,
      _tol,
      _tolPlus,
      _tolMinus,
      _note,
      _gapA,
      _gapB,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _change(SpoolItem Function(SpoolItem i) f) => widget.onChanged(f(_it));

  /// Tekst pola długości: puste → `null`; nieczytelny → `null` (brak
  /// werdyktu, błąd pola).
  double? _len(String t, {bool allowZero = true}) {
    final v = parseSpoolLength(t, _unit);
    if (v == null) return null;
    if (!allowZero && v <= 0) return null;
    return v;
  }

  String? _lenError(TextEditingController c, {bool allowZero = true}) {
    if (c.text.trim().isEmpty) return null;
    if (_len(c.text, allowZero: allowZero) != null) return null;
    return _unit == SpoolUnit.mm
        ? (_en ? 'Enter a number (mm)' : 'Wpisz liczbę (mm)')
        : (_en
            ? 'Enter inches, e.g. 98 1/2 or 3/16'
            : 'Wpisz cale, np. 98 1/2 albo 3/16');
  }

  /// Tolerancja: puste → zestaw protokołu; poprawna → zapis (w dół do
  /// siatki); błędna → NIE zmienia zapisanej wartości.
  void _onTolerance(String t) {
    if (t.trim().isEmpty) {
      _change((i) => i.copyWith(toleranceMm: null, toleranceDamaged: false));
      return;
    }
    final v = parseSpoolLength(t, _unit);
    if (v == null) {
      setState(() {});
      return;
    }
    final mm = spoolFloorMm(v);
    if (!spoolToleranceValid(mm)) {
      setState(() {});
      return;
    }
    if (mm == _it.toleranceMm) {
      // Ta sama wartość co zapisana (np. „300” → backspace → „30”) — nic do
      // zapisu, ale komunikat błędu musi zniknąć.
      setState(() {});
      return;
    }
    _change((i) => i.copyWith(toleranceMm: mm));
  }

  /// Część tolerancji niesymetrycznej (+ / −): puste → `null`; poprawna
  /// (0…50 mm) → zapis; błędna → NIE zmienia zapisanej wartości.
  void _onTolPart(String t, {required bool plus}) {
    if (t.trim().isEmpty) {
      _change((i) =>
          plus ? i.copyWith(tolPlusMm: null) : i.copyWith(tolMinusMm: null));
      return;
    }
    final v = parseSpoolLength(t, _unit);
    final mm = v == null ? null : spoolFloorMm(v);
    if (mm == null ||
        !spoolTolerancePartValid(mm) ||
        mm == (plus ? _it.tolPlusMm : _it.tolMinusMm)) {
      setState(() {});
      return;
    }
    _change(
        (i) => plus ? i.copyWith(tolPlusMm: mm) : i.copyWith(tolMinusMm: mm));
  }

  String? _tolPartError(TextEditingController c, double? keep) {
    final t = c.text;
    if (t.trim().isEmpty) return null;
    final v = parseSpoolLength(t, _unit);
    if (v != null && spoolTolerancePartValid(spoolFloorMm(v))) return null;
    final still = keep == null
        ? (_en ? 'none entered' : 'brak wpisanej')
        : spoolFormatBoth(keep, _unit, en: _en);
    return _en
        ? 'Enter 0–${kSpoolMaxToleranceMm.round()} mm. Still in force: $still.'
        : 'Wpisz 0–${kSpoolMaxToleranceMm.round()} mm. Obowiązuje nadal: '
            '$still.';
  }

  /// Przyjęcie podpowiedzi — świadomy wpis tolerancji.
  void _acceptSuggestion(double mm) {
    _tol.text = spoolFieldText(mm, _unit, en: _en);
    _change((i) => i.copyWith(toleranceMm: mm));
  }

  String? _tolError() {
    final t = _tol.text;
    if (t.trim().isEmpty) return null;
    final v = parseSpoolLength(t, _unit);
    if (v != null && spoolToleranceValid(spoolFloorMm(v))) return null;
    final keep = _it.toleranceMm;
    final still = keep == null
        ? (_en ? 'none entered' : 'brak wpisanej')
        : '±${spoolFormatBoth(keep, _unit, en: _en)}';
    final range = _unit == SpoolUnit.mm
        ? '0–${kSpoolMaxToleranceMm.round()} mm'
        : '0–${spoolNum(kSpoolMaxToleranceMm / kSpoolMmPerInch, en: _en, decimals: 2)}″';
    return _en
        ? 'Enter a tolerance above $range. Still in force: $still.'
        : 'Wpisz tolerancję w zakresie $range. Obowiązuje nadal: $still.';
  }

  String _tolLabel() {
    final set = widget.check.toleranceSet;
    final es3 = set == SpoolToleranceSet.pfiEs3;
    final es3Has = es3 &&
        _it.kind != SpoolItemKind.branchOffset &&
        _it.kind != SpoolItemKind.straightness;
    if (es3Has) {
      return _en
          ? 'Tolerance ± from the drawing (optional, overrides ES-3)'
          : 'Tolerancja ± z rysunku (opcjonalnie, zastępuje ES-3)';
    }
    if (es3) {
      return _en
          ? 'Tolerance ± from the design (ES-3 gives none)'
          : 'Tolerancja ± z projektu (ES-3 nie podaje)';
    }
    if (set == SpoolToleranceSet.en13480) {
      return _en
          ? 'Tolerance ± per EN 13480-4 Annex B'
          : 'Tolerancja ± wg EN 13480-4 zał. B';
    }
    return _en
        ? 'Tolerance ± from the design (empty = no verdict)'
        : 'Tolerancja ± z projektu (puste = brak werdyktu)';
  }

  Widget _lengthField(String key, TextEditingController c, String label,
      ValueChanged<String> onChanged,
      {String? error, String? helper}) {
    final mm = _unit == SpoolUnit.mm;
    return TextField(
      key: ValueKey('$_k-$key'),
      controller: c,
      keyboardType: mm ? numberKeyboard() : TextInputType.text,
      inputFormatters: mm ? numberInputFormatters() : _inchFormatters,
      decoration: InputDecoration(
        labelText: label,
        suffixText: spoolUnitSuffix(_unit),
        errorText: error,
        errorMaxLines: 3,
        helperText: helper,
        helperMaxLines: 3,
      ),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final it = _it;
    final en = _en;
    final color = spoolVerdictColor(r.verdict);
    final kind = it.kind;
    final children = <Widget>[];
    void gap() => children.add(const SizedBox(height: 10));

    children.add(TextField(
      key: ValueKey('$_k-label'),
      controller: _label,
      decoration: InputDecoration(
        labelText: en
            ? 'Mark on the isometric (e.g. F1–F2)'
            : 'Oznaczenie z izometrii (np. F1–F2)',
      ),
      onChanged: (t) => _change((i) => i.copyWith(label: t)),
    ));
    gap();

    if (kind.isLinear) {
      children.add(FieldPair(
        left: _lengthField(
          'drawing',
          _drawing,
          en ? 'Drawing' : 'Z rysunku',
          (t) =>
              _change((i) => i.copyWith(drawingMm: _len(t, allowZero: false))),
          error: _lenError(_drawing, allowZero: false),
        ),
        right: _lengthField(
          'measured',
          _measured,
          kind.measuredLabel(en: en),
          (t) =>
              _change((i) => i.copyWith(measuredMm: _len(t, allowZero: false))),
          error: _lenError(_measured, allowZero: false),
        ),
      ));
      gap();
      if (widget.check.toleranceSet == SpoolToleranceSet.pfiEs3) {
        children.add(TextField(
          key: ValueKey('$_k-dn'),
          controller: _dn,
          keyboardType: numberKeyboard(decimal: false),
          inputFormatters: numberInputFormatters(decimal: false),
          decoration: InputDecoration(
            labelText: en
                ? 'DN of this item (if not the spool DN)'
                : 'DN tej pozycji (gdy inny niż spoola)',
          ),
          onChanged: (t) {
            final v = int.tryParse(t.trim());
            _change(
                (i) => i.copyWith(dn: v != null && spoolDnValid(v) ? v : null));
          },
        ));
        gap();
      }
    } else if (kind == SpoolItemKind.boltRotation) {
      children.add(Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            key: ValueKey('$_k-mode-arc'),
            label:
                Text(en ? 'Offset along circle' : 'Przesunięcie po obwodzie'),
            selected: !it.rotationByAngle,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) =>
                _change((i) => i.copyWith(rotationByAngle: false)),
          ),
          ChoiceChip(
            key: ValueKey('$_k-mode-angle'),
            label: Text(en ? 'Angle' : 'Kąt'),
            selected: it.rotationByAngle,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) =>
                _change((i) => i.copyWith(rotationByAngle: true)),
          ),
        ],
      ));
      gap();
      if (it.rotationByAngle) {
        children.add(TextField(
          key: ValueKey('$_k-angle'),
          controller: _angle,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: en ? 'Rotation angle' : 'Kąt skrętu',
            suffixText: '°',
          ),
          onChanged: (t) {
            final v = parseDecimal(t);
            _change(
                (i) => i.copyWith(angleDeg: v != null && v >= 0 ? v : null));
          },
        ));
      } else {
        children.add(_lengthField(
          'measured',
          _measured,
          kind.measuredLabel(en: en),
          (t) => _change((i) => i.copyWith(measuredMm: _len(t))),
          error: _lenError(_measured),
        ));
      }
      gap();
      children.add(_lengthField(
        'base',
        _base,
        kind.baseLabel(en: en)!,
        (t) => _change((i) => i.copyWith(baseMm: _len(t, allowZero: false))),
        error: _lenError(_base, allowZero: false),
        helper: en
            ? 'From the flange catalogue (bolt circle).'
            : 'Z katalogu kołnierza (koło śrub).',
      ));
      final pcd = it.baseMm;
      final dev = it.measuredDeviationMm;
      if (pcd != null && dev != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            key: ValueKey('$_k-calc-rotation'),
            en
                ? '= ${spoolFormatBoth(dev, _unit, en: en)} along the circle '
                    '= ${spoolNum(boltAngleFromArc(dev, pcd), en: en, decimals: 3)}° '
                    'on PCD ${spoolFormatLength(pcd, _unit, en: en)}'
                : '= ${spoolFormatBoth(dev, _unit, en: en)} po obwodzie '
                    '= ${spoolNum(boltAngleFromArc(dev, pcd), en: en, decimals: 3)}° '
                    'na PCD ${spoolFormatLength(pcd, _unit, en: en)}',
            style: const TextStyle(fontSize: 13, color: kTextSec),
          ),
        ));
      }
      gap();
    } else {
      children.add(_lengthField(
        'measured',
        _measured,
        kind.measuredLabel(en: en),
        (t) => _change((i) => i.copyWith(measuredMm: _len(t))),
        error: _lenError(_measured),
      ));
      gap();
      final baseLabel = kind.baseLabel(en: en);
      if (baseLabel != null) {
        children.add(_lengthField(
          'base',
          _base,
          baseLabel,
          (t) => _change((i) => i.copyWith(baseMm: _len(t, allowZero: false))),
          error: _lenError(_base, allowZero: false),
          helper: kind == SpoolItemKind.faceTilt
              ? (en
                  ? 'Spacing of the two points (e.g. gasket face diameter).'
                  : 'Rozstaw dwóch punktów pomiaru (np. średnica przylgi).')
              : null,
        ));
        gap();
      }
      if (kind == SpoolItemKind.faceTilt) {
        children.add(_tiltCalculator());
        gap();
      }
    }

    children.add(_lengthField(
      'tol',
      _tol,
      _tolLabel(),
      _onTolerance,
      error: _tolError(),
    ));
    final sug = widget.suggestion;
    if (sug != null) {
      final (pos, mm) = sug;
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('$_k-tol-suggest'),
          style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
          onPressed: () => _acceptSuggestion(mm),
          icon: const Icon(Icons.content_paste_go, size: 18),
          label: Text(en
              ? 'As in item $pos: ±${spoolFormatLength(mm, _unit, en: en)} — '
                  'tap to use'
              : 'Jak w poz. $pos: ±${spoolFormatLength(mm, _unit, en: en)} — '
                  'stuknij, by przyjąć'),
        ),
      ));
    }
    gap();
    if (kind.isLinear &&
        widget.check.toleranceSet == SpoolToleranceSet.project) {
      children.add(FieldPair(
        left: _lengthField(
          'tolPlus',
          _tolPlus,
          en ? 'Tolerance + (longer)' : 'Tolerancja + (dłuższy)',
          (t) => _onTolPart(t, plus: true),
          error: _tolPartError(_tolPlus, it.tolPlusMm),
        ),
        right: _lengthField(
          'tolMinus',
          _tolMinus,
          en ? 'Tolerance − (shorter)' : 'Tolerancja − (krótszy)',
          (t) => _onTolPart(t, plus: false),
          error: _tolPartError(_tolMinus, it.tolMinusMm),
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          en
              ? 'Optional, unequal tolerance (e.g. +0 / −3): both fields '
                  'replace ±; one field alone gives no verdict.'
              : 'Opcjonalnie, tolerancja niesymetryczna (np. +0 / −3): oba '
                  'pola zastępują ±; jedno pole — brak werdyktu.',
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      ));
      gap();
    }
    children.add(TextField(
      key: ValueKey('$_k-note'),
      controller: _note,
      decoration: InputDecoration(labelText: en ? 'Note' : 'Uwaga'),
      onChanged: (t) => _change((i) => i.copyWith(note: t)),
    ));
    gap();
    children.add(_ResultBox(
      key: ValueKey('$_k-result'),
      result: r,
      unit: _unit,
      en: en,
      color: color,
      verdictKey: ValueKey('$_k-verdict'),
    ));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.index + 1}. ${kind.label(en: en)}',
                      style: const TextStyle(
                          color: kText,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('$_k-del'),
                    tooltip: en ? 'Remove item' : 'Usuń pozycję',
                    constraints: const BoxConstraints(
                        minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, color: kTextSec),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Nachylenie czoła z dwóch szczelin (kątownik + szczelinomierz).
  Widget _tiltCalculator() {
    final en = _en;
    final a = _len(_gapA.text);
    final b = _len(_gapB.text);
    final reading = faceTiltFromGaps(a, b, _it.baseMm);
    final dev = _it.measuredDeviationMm;
    final base = _it.baseMm;
    final lines = <String>[];
    if (reading != null) {
      lines.add(en
          ? 'Gap difference: ${spoolFormatBoth(reading.deviationMm, _unit, en: en)}'
          : 'Różnica szczelin: ${spoolFormatBoth(reading.deviationMm, _unit, en: en)}');
    }
    if (dev != null && base != null) {
      final angle = spoolTiltAngleDeg(dev, base);
      lines.add(en
          ? 'Tilt: ${spoolNum(angle, en: en, decimals: 3)}° = '
              '${spoolNum(dev / base * 1000, en: en, decimals: 2)} mm/m'
          : 'Nachylenie: ${spoolNum(angle, en: en, decimals: 3)}° = '
              '${spoolNum(dev / base * 1000, en: en, decimals: 2)} mm/m');
      if (widget.check.toleranceSet == SpoolToleranceSet.pfiEs3) {
        final lim = es3FaceAlignmentLimitMm(base);
        lines.add(en
            ? 'ES-3 limit on this diameter: ${spoolFormatBoth(lim, _unit, en: en)} '
                '(${spoolNum(spoolTiltAngleDeg(lim, base), en: en, decimals: 3)}°)'
            : 'Granica ES-3 na tej średnicy: ${spoolFormatBoth(lim, _unit, en: en)} '
                '(${spoolNum(spoolTiltAngleDeg(lim, base), en: en, decimals: 3)}°)');
      }
    }
    return Container(
      key: ValueKey('$_k-calc'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            en
                ? 'Calculator: gaps at two opposite points (square + feeler '
                    'gauge) on the diameter above'
                : 'Kalkulator: szczeliny w dwóch przeciwległych punktach '
                    '(kątownik + szczelinomierz) na średnicy powyżej',
            style: const TextStyle(fontSize: 12.5, color: kTextSec),
          ),
          const SizedBox(height: 8),
          FieldPair(
            left: _lengthField('gapA', _gapA, en ? 'Gap A' : 'Szczelina A',
                (_) => setState(() {}),
                error: _lenError(_gapA)),
            right: _lengthField('gapB', _gapB, en ? 'Gap B' : 'Szczelina B',
                (_) => setState(() {}),
                error: _lenError(_gapB)),
          ),
          if (base == null && (a != null || b != null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                en
                    ? 'Enter the diameter measured across.'
                    : 'Wpisz średnicę, na której zmierzono.',
                style: const TextStyle(fontSize: 12.5, color: kWarn),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: ValueKey('$_k-calc-apply'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: reading == null
                ? null
                : () {
                    _measured.text =
                        spoolFieldText(reading.deviationMm, _unit, en: en);
                    _change((i) => i.copyWith(measuredMm: reading.deviationMm));
                  },
            icon: const Icon(Icons.south),
            label: Text(en ? 'Use as deviation' : 'Wpisz jako odchyłkę'),
          ),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Text(l, style: const TextStyle(fontSize: 13, color: kText)),
            ),
        ],
      ),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({
    super.key,
    required this.result,
    required this.unit,
    required this.en,
    required this.color,
    required this.verdictKey,
  });

  final SpoolItemResult result;
  final SpoolUnit unit;
  final bool en;
  final Color color;
  final Key verdictKey;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final it = r.item;
    final dev = r.signedDeviationMm ?? r.deviationMm;
    final devText = dev == null
        ? '—'
        : it.kind.isLinear
            ? '${spoolFormatSigned(dev, unit, en: en)}'
                '${unit == SpoolUnit.inch ? ' (${spoolFormatMm(dev.abs(), en: en)})' : ''}'
            : spoolFormatBoth(dev, unit, en: en);
    final t = r.tolerance;
    final tolText = spoolToleranceText(t, unit, en: en);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${en ? 'Deviation' : 'Odchyłka'}: $devText',
              style: const TextStyle(fontSize: 13.5, color: kText)),
          Text('${en ? 'Tolerance' : 'Tolerancja'}: $tolText',
              style: const TextStyle(fontSize: 13.5, color: kText)),
          if (t.basis != null)
            Text('${en ? 'Against' : 'Wobec'}: ${spoolBasisText(t, en: en)}',
                style: const TextStyle(fontSize: 12.5, color: kTextSec)),
          const SizedBox(height: 4),
          Text(
            spoolVerdictText(r.verdict, en: en),
            key: verdictKey,
            style: TextStyle(
                color: color, fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          for (final g in r.gaps)
            Text('• ${spoolGapText(g, en: en)}',
                style: const TextStyle(fontSize: 12.5, color: kWarn)),
        ],
      ),
    );
  }
}
