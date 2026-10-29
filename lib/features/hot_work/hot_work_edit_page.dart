// Prace pożarowo niebezpieczne — protokół jednej pracy: dane zezwolenia,
// lista kontrolna (przed / w trakcie / po), pomiar atmosfery, udostępnianie
// (tekst, PDF). Zapisuje się sam przy każdej zmianie.
//
// MODUŁ BEZPIECZEŃSTWA: zielony stan tylko przy odhaczonych punktach
// „przed rozpoczęciem”, wpisanym pomiarze i dopuszczalnym % DGW z
// zezwolenia (lib/domain/hot_work/hot_work_permit.dart). Ekran mówi na
// górze i na dole, że wiążące jest zezwolenie zakładu.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/hot_work/hot_work_checklist.dart';
import '../../domain/hot_work/hot_work_permit.dart';
import '../../domain/hot_work/hot_work_sources.dart';
import '../../domain/hot_work/hot_work_text.dart';
import '../../i18n/app_language.dart';
import '../../services/hot_work_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart' show FieldPair, QuoteNotice, QuoteSection;
import 'hot_work_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef HotWorkShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef HotWorkSharePdf = Future<void> Function(
    HotWorkPermit permit, bool english);

Future<void> hotWorkDefaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> hotWorkDefaultSharePdf(HotWorkPermit permit, bool english) =>
    HotWorkExport.sharePdf(permit, english: english);

/// Wybór godziny — wstrzykiwany w testach (domyślnie zegar Material).
typedef HotWorkPickTime = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay initial);

Future<TimeOfDay?> hotWorkDefaultPickTime(
        BuildContext context, TimeOfDay initial) =>
    showTimePicker(context: context, initialTime: initial);

/// Kolor stanu: czerwony tylko „STOP”, zielony tylko gotowe / zamknięte
/// DZIŚ; protokół z innego dnia — szary (nigdy zielony).
Color hotWorkReadinessColor(HotWorkAssessment a) {
  if (a.readiness == HotWorkReadiness.overLimit) return kFail;
  if (a.otherDay) return kTextSec;
  if (a.readyToStart || a.closed) return kPass;
  return kWarn;
}

IconData hotWorkReadinessIcon(HotWorkAssessment a) {
  if (a.readiness == HotWorkReadiness.overLimit) {
    return Icons.dangerous_outlined;
  }
  if (a.otherDay) return Icons.history;
  if (a.readyToStart || a.closed) return Icons.verified_outlined;
  return Icons.pending_actions_outlined;
}

class HotWorkEditPage extends StatefulWidget {
  const HotWorkEditPage({
    super.key,
    required this.initial,
    this.store = const HotWorkStore(),
    this.now = DateTime.now,
    this.shareText = hotWorkDefaultShareText,
    this.sharePdf = hotWorkDefaultSharePdf,
    this.pickTime = hotWorkDefaultPickTime,
  });

  final HotWorkPermit initial;
  final HotWorkStore store;
  final DateTime Function() now;
  final HotWorkShareText shareText;
  final HotWorkSharePdf sharePdf;
  final HotWorkPickTime pickTime;

  @override
  State<HotWorkEditPage> createState() => _HotWorkEditPageState();
}

class _HotWorkEditPageState extends State<HotWorkEditPage> {
  late HotWorkPermit _p = widget.initial;
  bool _busy = false;

  /// Magazyn z zegarem ekranu (pomiary „z przyszłości” przy odczycie).
  late final HotWorkStore _store = widget.store.withClock(widget.now);

  /// Licznik do identyfikatorów pomiarów wpisanych w tej samej milisekundzie.
  int _seq = 0;

  late final _maxAge = TextEditingController(
      text: _p.measurementMaxAgeMin?.toString() ?? '');

  /// Ocena teraz (wiek pomiaru, data protokołu).
  HotWorkAssessment _assess() => _p.assess(now: widget.now());

  static bool get _enNow => AppLanguageController.isEnglish;

  late final _permitNo = TextEditingController(text: _p.permitNo);
  late final _location = TextEditingController(text: _p.location);
  late final _description = TextEditingController(text: _p.description);
  late final _contractor = TextEditingController(text: _p.contractor);
  late final _securedBy = TextEditingController(text: _p.securedBy);
  late final _fireWatch = TextEditingController(text: _p.fireWatch);
  late final _issuer = TextEditingController(text: _p.issuer);
  late final _notes = TextEditingController(text: _p.notes);
  late final _limit = TextEditingController(
      text: _p.dgwLimitPct == null
          ? ''
          : formatHotWorkNumber(_p.dgwLimitPct!, en: _enNow));
  late final _watchMin =
      TextEditingController(text: _p.fireWatchAfterMin?.toString() ?? '');
  final _measDgw = TextEditingController();
  final _measNote = TextEditingController();

  /// Godzina nowego pomiaru wybrana ręcznie; `null` = chwila dodania.
  String? _measTime;

  /// Co minutę przelicz stan — pomiar starzeje się bez dotykania ekranu
  /// (zielony nie może wisieć po upływie ważności pomiaru).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [
      _permitNo,
      _location,
      _description,
      _contractor,
      _securedBy,
      _fireWatch,
      _issuer,
      _notes,
      _limit,
      _watchMin,
      _measDgw,
      _measNote,
      _maxAge,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Zmiany i zapis ─────────────────────────────────────────────────────

  void _set(HotWorkPermit Function(HotWorkPermit p) change) {
    setState(() => _p = change(_p)
        .copyWith(updatedAt: widget.now().millisecondsSinceEpoch));
    final snapshot = _p;
    unawaited(_store.upsert(snapshot).catchError((Object e) {
      debugPrint('[hot_work] save failed: $e');
      _reportSaveFailure(full: e is HotWorkStoreFull);
    }));
  }

  bool _saveFailureShown = false;

  /// Raz na ekran: protokół bezpieczeństwa, który się nie zapisuje, nie może
  /// tego robić po cichu.
  void _reportSaveFailure({bool full = false}) {
    if (!mounted || _saveFailureShown) return;
    _saveFailureShown = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: ValueKey(full ? 'hw-store-full' : 'hw-save-failed'),
      content: Text(full
          ? context.tr(
              pl: 'Historia pełna (${HotWorkStore.maxEntries} protokołów) — '
                  'ten protokół NIE jest zapisany. Udostępnij go (tekst/PDF) '
                  'i usuń stare protokoły z historii.',
              en: 'History full (${HotWorkStore.maxEntries} records) — this '
                  'record is NOT saved. Share it (text/PDF) and delete old '
                  'records from the history.')
          : context.tr(
              pl: 'Nie udało się zapisać protokołu w telefonie — udostępnij '
                  'go (tekst/PDF), żeby nie przepadł.',
              en: 'Could not save the record on this phone — share it '
                  '(text/PDF) so it is not lost.',
            )),
    ));
  }

  void _toggle(HotWorkCheck c) {
    final wasReady = _assess().readyToStart;
    final willCheck = !_p.isChecked(c);
    _set((p) => p.toggleChecked(c.id));
    if (willCheck) unawaited(Haptic.tap());
    if (!wasReady && _assess().readyToStart) unawaited(Haptic.saved());
  }

  void _toggleNa(HotWorkCheck c) => _set((p) => p.toggleNa(c.id));

  /// Liczba 0–100 % DGW z pola albo `null`. 100 % DGW to z definicji
  /// stężenie równe dolnej granicy wybuchowości — koniec skali
  /// eksplozymetru; większa wartość to błąd wpisu.
  static double? _pct(String raw) {
    final v = parseDecimal(raw);
    if (v == null || !v.isFinite || v < 0 || v > 100) return null;
    return v;
  }

  String? _pctError(String raw) {
    if (raw.trim().isEmpty) return null;
    return _pct(raw) == null
        ? context.tr(pl: 'Wpisz liczbę 0–100', en: 'Enter a number 0–100')
        : null;
  }

  /// Dopuszczalne % DGW: 0–10 (więcej przepis nie pozwala — zob.
  /// [hotWorkLimitValid]); poza zakresem `null`, czyli „brak progu”.
  static double? _limitPct(String raw) {
    final v = parseDecimal(raw);
    if (v == null || !hotWorkLimitValid(v)) return null;
    return v;
  }

  String? _limitError(String raw) {
    if (raw.trim().isEmpty) return null;
    return _limitPct(raw) == null
        ? context.tr(
            pl: 'Wpisz 0–10 — przepis nie pozwala na więcej niż 10 % DGW',
            en: 'Enter 0–10 — the regulation allows no more than 10 % LEL')
        : null;
  }

  /// Ważność 1…30 min (dłużej niż przyjęta w aplikacji nie wolno).
  static int? _parseMaxAge(String raw) {
    final v = int.tryParse(raw.trim());
    return v != null && hotWorkMaxAgeValid(v) ? v : null;
  }

  /// Puste pole — wartość przyjęta w aplikacji; poprawne — zapis; błędne —
  /// NIE zmienia zapisanej wartości.
  void _onMaxAgeText(String raw) {
    if (raw.trim().isEmpty) {
      _set((p) => p.copyWith(measurementMaxAgeMin: null));
      return;
    }
    final v = _parseMaxAge(raw);
    if (v == null) {
      setState(() {});
      return;
    }
    if (v == _p.measurementMaxAgeMin) return;
    _set((p) => p.copyWith(measurementMaxAgeMin: v));
  }

  String? _maxAgeError(bool en) {
    final raw = _maxAge.text;
    if (raw.trim().isEmpty || _parseMaxAge(raw) != null) return null;
    final keep = _p.effectiveMaxAgeMin;
    return en
        ? 'Enter 1–$kHotWorkMeasurementMaxAgeMin — it can only be shortened. '
            'Still in force: $keep min.'
        : 'Wpisz 1–$kHotWorkMeasurementMaxAgeMin — można tylko skrócić. '
            'Obowiązuje nadal: $keep min.';
  }

  /// Ręcznie wpisana godzina, która wypada wczoraj — pytanie, czy to na
  /// pewno wczoraj. `true` = potwierdzone.
  Future<bool> _confirmYesterday(String time, DateTime at) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr(
            pl: 'Pomiar wczoraj?', en: 'Reading from yesterday?')),
        content: Text(context.tr(
          pl: 'Godzina $time jest późniejsza niż teraz, więc pomiar byłby '
              'z wczoraj (${hotWorkDate(at)}). Czy to na pewno wczoraj?',
          en: '$time is later than now, so the reading would be from '
              'yesterday (${hotWorkDate(at)}). Is it really from yesterday?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('hw-yesterday-confirm'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Tak, wczoraj', en: 'Yes, yesterday')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addMeasurement() async {
    final v = _pct(_measDgw.text);
    if (v == null) return;
    var now = widget.now();
    final time = _measTime ?? hotWorkTime(now);
    if (_measTime != null) {
      final at = hotWorkMeasurementAt(time, now);
      // Godzina z przyszłości (w zapasie 5 min funkcji) — nie wolno: taki
      // wpis przykryłby prawdziwe, późniejsze pomiary.
      if (at.isAfter(now)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            key: const ValueKey('hw-meas-future'),
            content: Text(context.tr(
              pl: 'Godzina pomiaru $time jest późniejsza niż teraz '
                  '(${hotWorkTime(now)}) — wpisz godzinę, o której '
                  'zmierzono.',
              en: 'The reading time $time is later than now '
                  '(${hotWorkTime(now)}) — enter the time it was measured.',
            )),
          ));
        return;
      }
      if (hotWorkDate(at) != hotWorkDate(now)) {
        if (!await _confirmYesterday(time, at)) return;
        if (!mounted) return;
        now = widget.now();
      }
    }
    final at = _measTime == null ? now : hotWorkMeasurementAt(time, now);
    final m = HotWorkMeasurement(
      id: 'm${now.millisecondsSinceEpoch}-${_seq++}',
      time: time,
      at: at.millisecondsSinceEpoch,
      enteredAt: now.millisecondsSinceEpoch,
      dgwPct: v,
      note: _measNote.text.trim(),
    );
    final latestBefore = _assess().latestMeasurement;
    _set((p) => p.addMeasurement(m));
    _measDgw.clear();
    _measNote.clear();
    setState(() => _measTime = null);
    unawaited(Haptic.tap());
    final after = _assess();
    final minute = m.at! ~/ 60000;
    // Remis w tej samej minucie — mówimy wprost, że decyduje gorszy.
    if (after.tie && after.latestMeasurement?.at != null &&
        after.latestMeasurement!.at! ~/ 60000 == minute) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('hw-meas-tie'),
          content: Text(
              hotWorkTieText(after, en: context.language == AppLanguage.en)),
        ));
      return;
    }
    // Zaległy pomiar nie zmienia stanu — mówimy to wprost, żeby nikt nie
    // myślał, że „0 %” dopisane później zdjęło STOP.
    if (latestBefore != null &&
        !identical(after.latestMeasurement, m)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('hw-meas-backdated'),
          content: Text(context.tr(
            pl: 'Pomiar z $time jest wcześniejszy niż ostatni '
                '(${latestBefore.time}) — stan ocenia najpóźniejszy pomiar.',
            en: 'The $time reading is earlier than the latest one '
                '(${latestBefore.time}) — the status uses the latest reading.',
          )),
        ));
    }
  }

  /// Usunięcie z „Cofnij”. Cofnięcie zapisuje przez magazyn po id
  /// protokołu i pomiaru — działa także po zamknięciu ekranu; stan ekranu
  /// poprawia tylko, gdy ekran istnieje.
  void _removeMeasurement(HotWorkMeasurement removed) {
    final before = _p;
    _set((p) => p.removeMeasurement(removed));
    final store = _store;
    final id = _p.id;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Pomiar usunięty.', en: 'Reading removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () {
            unawaited(store
                .update(id, (p) => p.restoreMeasurement(removed),
                    orElse: before)
                .catchError((Object e) {
              debugPrint('[hot_work] undo failed: $e');
            }));
            if (mounted) {
              setState(() => _p = _p.restoreMeasurement(removed));
            }
          },
        ),
      ));
  }

  Future<void> _pickDate() async {
    final first = DateTime(2020);
    final last = DateTime(2100);
    var current = DateTime.tryParse(_p.date) ?? widget.now();
    // Imported or older records may be outside the calendar's range.
    if (current.isBefore(first)) current = first;
    if (current.isAfter(last)) current = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    _set((p) => p.copyWith(date: hotWorkDate(picked)));
  }

  /// Wybór godziny; `null` = anulowano.
  Future<String?> _pickTime(String current) async {
    TimeOfDay initial = TimeOfDay.fromDateTime(widget.now());
    final parts = current.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
    }
    final picked = await widget.pickTime(context, initial);
    if (picked == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _shareText() async {
    final en = context.language == AppLanguage.en;
    unawaited(Haptic.tap());
    await widget.shareText(hotWorkProtocolText(_p, en: en, now: widget.now()),
        hotWorkSubject(english: en));
  }

  Future<void> _sharePdf() async {
    if (_busy) return;
    final en = context.language == AppLanguage.en;
    setState(() => _busy = true);
    try {
      await widget.sharePdf(_p, en);
    } catch (e) {
      debugPrint('[hot_work] pdf export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się przygotować PDF.',
              en: 'Could not prepare the PDF.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Ekran ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final a = _assess();
    final today = hotWorkDate(widget.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Protokół prac pożarowych', en: 'Hot work record')),
        actions: [
          IconButton(
            key: const ValueKey('hw-share-text'),
            tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share as text'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            key: const ValueKey('hw-share-pdf'),
            tooltip: context.tr(pl: 'PDF protokołu', en: 'Record PDF'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _busy ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('hw-edit-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _StatusCard(assessment: a, en: en),
          const SizedBox(height: 12),
          if (_p.date != today)
            QuoteNotice(
              key: const ValueKey('hw-old-notice'),
              icon: Icons.history,
              text: context.tr(
                pl: 'Protokół z dnia ${_p.date}. Do nowej pracy użyj „Jak '
                    'wczoraj” na liście — zaznaczeń i pomiarów nie przenosi '
                    'się na inny dzień.',
                en: 'Record dated ${_p.date}. For new work use “Same as '
                    'yesterday” on the list — ticks and gas readings never '
                    'carry over to another day.',
              ),
            ),
          if (_p.droppedOnLoad > 0)
            QuoteNotice(
              key: const ValueKey('hw-damaged-notice'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: context.tr(
                pl: 'W zapisie tego protokołu było ${_p.droppedOnLoad} '
                    'nieczytelnych pomiarów — pominięto je, kopia surowego '
                    'zapisu została w telefonie. Zmierz ponownie.',
                en: '${_p.droppedOnLoad} unreadable reading(s) in this record '
                    'were skipped — a raw copy is kept on the phone. Test '
                    'again.',
              ),
            ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: hotWorkDisclaimer(en: en),
          ),
          _permitSection(en),
          _phaseSection(HotWorkPhase.before, en),
          _gasSection(en),
          _phaseSection(HotWorkPhase.during, en),
          _phaseSection(HotWorkPhase.after, en, extra: [
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('hw-f-watchMin'),
              controller: _watchMin,
              keyboardType: numberKeyboard(decimal: false),
              inputFormatters: numberInputFormatters(decimal: false),
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Dozór po zakończeniu wg zezwolenia',
                    en: 'Post-work fire watch per the permit'),
                suffixText: 'min',
                helperText: context.tr(
                    pl: 'Czas z zezwolenia / instrukcji zakładu.',
                    en: 'Time from the permit / site procedure.'),
              ),
              onChanged: (t) {
                final v = int.tryParse(t.trim());
                _set((p) => p.copyWith(
                    fireWatchAfterMin: v != null && v >= 0 ? v : null));
              },
            ),
          ]),
          QuoteSection(
            title: context.tr(pl: 'Uwagi', en: 'Notes'),
            children: [
              TextField(
                key: const ValueKey('hw-f-notes'),
                controller: _notes,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Dodatkowe zabezpieczenia, ustalenia',
                      en: 'Extra precautions, arrangements'),
                ),
                onChanged: (t) => _set((p) => p.copyWith(notes: t)),
              ),
            ],
          ),
          _sourcesSection(en),
          _shareButtons(),
          const SizedBox(height: 12),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: hotWorkDisclaimer(en: en),
          ),
        ],
      ),
    );
  }

  Widget _text(String key, TextEditingController c, String label,
      ValueChanged<String> onChanged,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('hw-f-$key'),
        controller: c,
        minLines: 1,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _permitSection(bool en) {
    return QuoteSection(
      title: context.tr(pl: 'Zezwolenie', en: 'Permit'),
      subtitle: context.tr(
          pl: 'Dane z zezwolenia zakładu. Protokół zapisuje się sam.',
          en: 'Details from the site permit. The record saves itself.'),
      children: [
        _text('permitNo', _permitNo,
            context.tr(pl: 'Nr zezwolenia', en: 'Permit no.'),
            (t) => _set((p) => p.copyWith(permitNo: t))),
        _text('location', _location,
            context.tr(
                pl: 'Miejsce (zakład, instalacja, stanowisko)',
                en: 'Location (site, unit, work point)'),
            (t) => _set((p) => p.copyWith(location: t))),
        _text('description', _description,
            context.tr(pl: 'Opis pracy', en: 'Work description'),
            (t) => _set((p) => p.copyWith(description: t)),
            maxLines: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in HotWorkType.values)
              FilterChip(
                key: ValueKey('hw-type-${t.name}'),
                label: Text(t.label(en: en)),
                selected: _p.workTypes.contains(t),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (on) => _set((p) => p.copyWith(
                    workTypes: on
                        ? {...p.workTypes, t}
                        : ({...p.workTypes}..remove(t)))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _PickButton(
          key: const ValueKey('hw-date'),
          icon: Icons.event_outlined,
          label: context.tr(pl: 'Data', en: 'Date'),
          value: _p.date,
          onTap: _pickDate,
        ),
        const SizedBox(height: 8),
        FieldPair(
          left: _PickButton(
            key: const ValueKey('hw-from'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Ważne od', en: 'Valid from'),
            value: _p.validFrom.isEmpty ? '—' : _p.validFrom,
            onTap: () async {
              final t = await _pickTime(_p.validFrom);
              if (t != null && mounted) {
                _set((p) => p.copyWith(validFrom: t));
              }
            },
          ),
          right: _PickButton(
            key: const ValueKey('hw-to'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Ważne do', en: 'Valid until'),
            value: _p.validTo.isEmpty ? '—' : _p.validTo,
            onTap: () async {
              final t = await _pickTime(_p.validTo);
              if (t != null && mounted) _set((p) => p.copyWith(validTo: t));
            },
          ),
        ),
        const SizedBox(height: 12),
        _text('contractor', _contractor,
            context.tr(pl: 'Wykonawca', en: 'Performed by'),
            (t) => _set((p) => p.copyWith(contractor: t))),
        _text('securedBy', _securedBy,
            context.tr(
                pl: 'Odpowiedzialny za zabezpieczenie',
                en: 'Responsible for securing the area'),
            (t) => _set((p) => p.copyWith(securedBy: t))),
        _text('fireWatch', _fireWatch,
            context.tr(pl: 'Dozorujący', en: 'Fire watch'),
            (t) => _set((p) => p.copyWith(fireWatch: t))),
        _text('issuer', _issuer,
            context.tr(
                pl: 'Wystawiający zezwolenie', en: 'Permit issuer'),
            (t) => _set((p) => p.copyWith(issuer: t))),
      ],
    );
  }

  Widget _phaseSection(HotWorkPhase phase, bool en,
      {List<Widget> extra = const []}) {
    final checks = hotWorkChecksIn(phase);
    final done = checks.where(_p.isSettled).length;
    return QuoteSection(
      key: ValueKey('hw-phase-${phase.name}'),
      title: phase.label(en: en),
      trailing: Text(
        '$done/${checks.length}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: done == checks.length ? kPass : kArc,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      children: [
        for (final g in hotWorkGroupsIn(phase)) ...[
          if (hotWorkGroupsIn(phase).length > 1) _GroupLabel(g.label(en: en)),
          for (final c in hotWorkChecksInGroup(g))
            _CheckTile(
              check: c,
              checked: _p.isChecked(c),
              na: _p.isNa(c),
              en: en,
              onToggle: () => _toggle(c),
              onNa: () => _toggleNa(c),
            ),
        ],
        ...extra,
      ],
    );
  }

  Widget _gasSection(bool en) {
    final limit = _p.dgwLimitPct;
    final newValue = _pct(_measDgw.text);
    final unit = en ? '% LEL' : '% DGW';
    return QuoteSection(
      key: const ValueKey('hw-gas'),
      title: context.tr(pl: 'Pomiar atmosfery', en: 'Gas test'),
      subtitle: context.tr(
          pl: 'Eksplozymetr: wynik w % DGW (dolnej granicy wybuchowości). '
              'Dopuszczalną wartość podaje zezwolenie / instrukcja zakładu. '
              'Stan ocenia ostatni pomiar.',
          en: 'Gas detector: reading in % LEL (lower explosive limit). The '
              'permitted value comes from the permit / site procedure. The '
              'latest reading decides the status.'),
      children: [
        TextField(
          key: const ValueKey('hw-limit'),
          controller: _limit,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Dopuszczalne wg zezwolenia',
                en: 'Permitted per the permit'),
            suffixText: unit,
            // 10 % DGW — rozp. MSWiA z 7.06.2010, § 36 ust. 2; 0–5 % —
            // progi spotykane w instrukcjach zakładów (hot_work_sources.dart).
            helperText: context.tr(
                pl: 'Wynik nie może przekraczać tej wartości. Przepis: nie '
                    'więcej niż 10 % DGW (§ 36 ust. 2 rozp. MSWiA); zakład '
                    'może wymagać mniej (0–5 %).',
                en: 'Readings must not exceed this value. Polish regulation: '
                    'not above 10 % LEL (§ 36(2)); sites may require less '
                    '(0–5 %).'),
            helperMaxLines: 4,
            errorText: _limitError(_limit.text),
          ),
          onChanged: (t) =>
              _set((p) => p.copyWith(dgwLimitPct: _limitPct(t))),
        ),
        const SizedBox(height: 12),
        if (_p.measurements.isEmpty)
          Padding(
            key: const ValueKey('hw-meas-empty'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr(
                  pl: 'Brak pomiaru — bez wyniku stan nie będzie zielony.',
                  en: 'No reading — without one the status cannot turn '
                      'green.'),
              style: const TextStyle(
                  color: kWarn, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: const ValueKey('hw-maxage'),
            controller: _maxAge,
            keyboardType: numberKeyboard(decimal: false),
            inputFormatters: numberInputFormatters(decimal: false),
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Pomiar ważny przez', en: 'Gas test valid for'),
              suffixText: 'min',
              hintText: '$kHotWorkMeasurementMaxAgeMin',
              helperText: context.tr(
                  pl: 'Puste = $kHotWorkMeasurementMaxAgeMin min (wartość '
                      'przyjęta w aplikacji). Starszy pomiar = brak pomiaru.',
                  en: 'Empty = $kHotWorkMeasurementMaxAgeMin min (value '
                      'adopted by the app). An older reading counts as none.'),
              helperMaxLines: 3,
              errorText: _maxAgeError(en),
              errorMaxLines: 3,
            ),
            onChanged: _onMaxAgeText,
          ),
        ),
        for (final (i, m) in _p.measurements.indexed)
          _MeasurementRow(
            key: ValueKey('hw-meas-$i'),
            text: hotWorkMeasurementLine(m, limit, en: en, recordDate: _p.date),
            color: hotWorkMeasurementOk(
                    m.dgwPct, limit ?? kHotWorkDefaultDgwLimitPct)
                ? (limit == null ? kTextSec : kPass)
                : kFail,
            deleteKey: ValueKey('hw-meas-del-$i'),
            deleteTooltip: context.tr(pl: 'Usuń pomiar', en: 'Remove reading'),
            onDelete: () => _removeMeasurement(m),
          ),
        const SizedBox(height: 4),
        FieldPair(
          left: TextField(
            key: const ValueKey('hw-meas-dgw'),
            controller: _measDgw,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            decoration: InputDecoration(
              labelText: context.tr(pl: 'Wynik pomiaru', en: 'Reading'),
              suffixText: unit,
              errorText: _pctError(_measDgw.text),
            ),
            onChanged: (_) => setState(() {}),
          ),
          right: _PickButton(
            key: const ValueKey('hw-meas-time'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Godzina', en: 'Time'),
            value: _measTime ?? context.tr(pl: 'teraz', en: 'now'),
            onTap: () async {
              final t = await _pickTime(_measTime ?? '');
              if (t != null && mounted) setState(() => _measTime = t);
            },
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('hw-meas-note'),
          controller: _measNote,
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Miejsce / uwagi (np. studzienka, O₂)',
                en: 'Place / notes (e.g. drain, O₂)'),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('hw-meas-add'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget)),
          onPressed: newValue == null ? null : _addMeasurement,
          icon: const Icon(Icons.add),
          label: Text(context.tr(pl: 'Dodaj pomiar', en: 'Add reading')),
        ),
      ],
    );
  }

  Widget _sourcesSection(bool en) {
    return QuoteSection(
      key: const ValueKey('hw-sources'),
      title: context.tr(
          pl: 'Źródła i wartości odniesienia',
          en: 'Sources and reference values'),
      subtitle: context.tr(
          pl: 'Dla orientacji — obowiązują wartości z zezwolenia.',
          en: 'For orientation — the permit values apply.'),
      children: [
        for (final s in kHotWorkSources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '• ${s.label(en: en)}',
              style: const TextStyle(
                  fontSize: 12.5, color: kTextSec, height: 1.4),
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
            key: const ValueKey('hw-share-text-btn'),
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
            key: const ValueKey('hw-share-pdf-btn'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: _busy ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(context.tr(pl: 'PDF dla nadzoru', en: 'PDF')),
          ),
        ),
      ],
    );
  }
}

// ── Widżety ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.assessment, required this.en});

  final HotWorkAssessment assessment;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final color = hotWorkReadinessColor(a);
    final total = {
      for (final p in HotWorkPhase.values) p: hotWorkChecksIn(p).length,
    };
    final open = {
      HotWorkPhase.before: a.openBefore.length,
      HotWorkPhase.during: a.openDuring.length,
      HotWorkPhase.after: a.openAfter.length,
    };
    final counts = [
      for (final p in HotWorkPhase.values)
        '${p.label(en: en)}: ${total[p]! - open[p]!}/${total[p]}',
    ].join(' · ');
    final blockers = [
      if (a.overLimit)
        en ? 'gas reading above the limit' : 'pomiar przekracza limit',
      if (a.otherDay)
        en
            ? 'record dated ${a.recordDate} — out of date'
            : 'protokół z dnia ${a.recordDate} — nieaktualny',
      if (a.measurementMissing) en ? 'no gas reading' : 'brak pomiaru atmosfery',
      if (!a.measurementMissing && a.measurementStale && !a.overLimit)
        en
            ? 'gas test out of date (over ${a.maxAgeMin} min)'
            : 'pomiar nieaktualny (ponad ${a.maxAgeMin} min)',
      if (a.limitMissing)
        en ? 'no permitted % LEL' : 'brak dopuszczalnego % DGW',
      if (a.openBefore.isNotEmpty)
        en
            ? '${a.openBefore.length} item(s) before start'
            : 'do odhaczenia przed rozpoczęciem: ${a.openBefore.length}',
    ];
    final icon = hotWorkReadinessIcon(a);
    return Material(
      key: const ValueKey('hw-status'),
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
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hotWorkReadinessText(a, en: en),
                    key: const ValueKey('hw-status-text'),
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w800),
                  ),
                  if (a.tie)
                    Padding(
                      key: const ValueKey('hw-tie'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('⚠ ${hotWorkTieText(a, en: en)}',
                          style: const TextStyle(
                              color: kWarn,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600)),
                    ),
                  if (blockers.length > 1) ...[
                    const SizedBox(height: 6),
                    for (final b in blockers)
                      Text('• $b',
                          style: const TextStyle(
                              color: kText, fontSize: 13, height: 1.35)),
                  ],
                  const SizedBox(height: 6),
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(
        text,
        style: const TextStyle(
            color: kArc,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3),
      ),
    );
  }
}

/// Duży punkt listy: cały wiersz przełącza „sprawdzone”, osobny przycisk
/// „n/d” tylko przy punktach, które na to pozwalają. Material (nie
/// kolorowy Container) — atrament kliknięcia ma na czym się malować.
class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.check,
    required this.checked,
    required this.na,
    required this.en,
    required this.onToggle,
    required this.onNa,
  });

  final HotWorkCheck check;
  final bool checked;
  final bool na;
  final bool en;
  final VoidCallback onToggle;
  final VoidCallback onNa;

  @override
  Widget build(BuildContext context) {
    final borderColor = checked
        ? kPass.withValues(alpha: 0.6)
        : na
            ? kTextMut.withValues(alpha: 0.5)
            : kBorder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          checked: checked,
          child: InkWell(
            key: ValueKey('hw-check-${check.id}'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    Icon(
                      na
                          ? Icons.indeterminate_check_box_outlined
                          : checked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                      size: 30,
                      color: checked
                          ? kPass
                          : na
                              ? kTextSec
                              : kTextMut,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            check.label(en: en),
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.35,
                              color: checked || na ? kTextSec : kText,
                              decoration:
                                  na ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (check.source != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                check.source!,
                                style: const TextStyle(
                                    fontSize: 11.5, color: kTextMut),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (check.naAllowed)
                      TextButton(
                        key: ValueKey('hw-na-${check.id}'),
                        style: TextButton.styleFrom(
                          minimumSize:
                              const Size(kMinTapTarget, kMinTapTarget),
                          foregroundColor: na ? kArc : kTextSec,
                        ),
                        onPressed: onNa,
                        child: Text(en ? 'n/a' : 'n/d'),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    super.key,
    required this.text,
    required this.color,
    required this.deleteKey,
    required this.deleteTooltip,
    required this.onDelete,
  });

  final String text;
  final Color color;
  final Key deleteKey;
  final String deleteTooltip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Icon(Icons.speed, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: color == kTextSec ? kText : color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              IconButton(
                key: deleteKey,
                tooltip: deleteTooltip,
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

/// Przycisk wyboru daty / godziny: etykieta nad wartością, 48 dp.
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
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11.5, color: kTextMut)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
