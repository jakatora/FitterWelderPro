// Przestrzeń zamknięta — protokół jednego wejścia: dane pozwolenia, rodzaj
// pracy i ostrzeżenia dla spawacza, progi i pomiary atmosfery, lista
// kontrolna (przed / w trakcie / po), udostępnianie (tekst, PDF). Zapisuje
// się sam przy każdej zmianie.
//
// MODUŁ BEZPIECZEŃSTWA: zielony stan tylko przy odhaczonych punktach
// „przed wejściem” i najpóźniejszym odczycie KAŻDEGO wymaganego gazu
// w progach (lib/domain/confined_space/confined_space_record.dart). Ekran
// mówi na górze i na dole, że wiąże pozwolenie zakładu.
//
// Lekcje z przeglądów kodu (stosowane od początku):
// * błędny tekst w polu progu NIE kasuje zapisanego progu — kasuje tylko
//   puste pole; pole pokazuje błąd i to, co obowiązuje;
// * odczyt i próg wpisane w mg/m³ są pokazywane w mg/m³ (bez przeliczeń
//   tam i z powrotem), ocena liczy się w ppm;
// * „Cofnij” usunięcia pomiaru zapisuje przez magazyn — działa także po
//   zamknięciu ekranu;
// * odczyty z tej samej minuty to remis — ekran mówi o nim wprost.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/confined_space/confined_space_checklist.dart';
import '../../domain/confined_space/confined_space_gas.dart';
import '../../domain/confined_space/confined_space_record.dart';
import '../../domain/confined_space/confined_space_sources.dart';
import '../../domain/confined_space/confined_space_text.dart';
import '../../domain/hot_work/hot_work_permit.dart'
    show hotWorkDate, hotWorkMeasurementAt, hotWorkTime;
import '../../i18n/app_language.dart';
import '../../services/confined_space_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart' show FieldPair, QuoteNotice, QuoteSection;
import 'confined_space_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef ConfinedSpaceShareText = Future<void> Function(
    String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef ConfinedSpaceSharePdf = Future<void> Function(
    ConfinedSpaceRecord record, bool english);

Future<void> confinedSpaceDefaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> confinedSpaceDefaultSharePdf(
        ConfinedSpaceRecord record, bool english) =>
    ConfinedSpaceExport.sharePdf(record, english: english);

/// Kolor stanu: czerwony tylko „STOP”, zielony tylko gotowe / zamknięte.
Color confinedSpaceReadinessColor(CsAssessment a) {
  if (a.readiness == CsReadiness.stop) return kFail;
  if (a.readyToEnter) return kPass;
  return kWarn;
}

IconData confinedSpaceReadinessIcon(CsAssessment a) {
  if (a.readiness == CsReadiness.stop) return Icons.dangerous_outlined;
  if (a.readyToEnter) return Icons.verified_outlined;
  return Icons.pending_actions_outlined;
}

/// Kolor oceny jednego odczytu.
Color csStateColor(CsReadingState? s) => switch (s) {
      CsReadingState.ok => kPass,
      CsReadingState.low || CsReadingState.high => kFail,
      _ => kTextSec,
    };

class ConfinedSpaceEditPage extends StatefulWidget {
  const ConfinedSpaceEditPage({
    super.key,
    required this.initial,
    this.store = const ConfinedSpaceStore(),
    this.now = DateTime.now,
    this.shareText = confinedSpaceDefaultShareText,
    this.sharePdf = confinedSpaceDefaultSharePdf,
  });

  final ConfinedSpaceRecord initial;
  final ConfinedSpaceStore store;
  final DateTime Function() now;
  final ConfinedSpaceShareText shareText;
  final ConfinedSpaceSharePdf sharePdf;

  @override
  State<ConfinedSpaceEditPage> createState() => _ConfinedSpaceEditPageState();
}

/// Progi z przełącznikiem jednostki (CO, H₂S).
bool _hasUnits(CsBound b) => b.gas.units.length > 1;

class _ConfinedSpaceEditPageState extends State<ConfinedSpaceEditPage> {
  late ConfinedSpaceRecord _r = widget.initial;
  bool _busy = false;

  static bool get _enNow => AppLanguageController.isEnglish;

  late final _permitNo = TextEditingController(text: _r.permitNo);
  late final _location = TextEditingController(text: _r.location);
  late final _description = TextEditingController(text: _r.description);
  late final _entrants = TextEditingController(text: _r.entrants);
  late final _attendant = TextEditingController(text: _r.attendant);
  late final _supervisor = TextEditingController(text: _r.supervisor);
  late final _issuer = TextEditingController(text: _r.issuer);
  late final _rescue = TextEditingController(text: _r.rescue);
  late final _notes = TextEditingController(text: _r.notes);

  late final Map<CsBound, TextEditingController> _limit = {
    for (final b in CsBound.values)
      b: TextEditingController(
          text: _r.limits[b] == null
              ? ''
              : formatCsNumber(_r.limits[b]!.value, en: _enNow)),
  };

  /// Jednostka, w której wpisuje się próg CO / H₂S.
  late final Map<CsBound, CsUnit> _limitUnit = {
    for (final b in CsBound.values) b: _r.limits[b]?.unit ?? b.gas.canonical,
  };

  final Map<CsGas, TextEditingController> _meas = {
    for (final g in CsGas.values) g: TextEditingController(),
  };
  final Map<CsGas, CsUnit> _measUnit = {
    for (final g in CsGas.values) g: g.canonical,
  };
  final _measPlace = TextEditingController();

  /// Godzina nowego pomiaru wybrana ręcznie; `null` = chwila dodania.
  String? _measTime;

  @override
  void dispose() {
    for (final c in [
      _permitNo,
      _location,
      _description,
      _entrants,
      _attendant,
      _supervisor,
      _issuer,
      _rescue,
      _notes,
      _measPlace,
      ..._limit.values,
      ..._meas.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Zmiany i zapis ─────────────────────────────────────────────────────

  void _set(ConfinedSpaceRecord Function(ConfinedSpaceRecord r) change) {
    setState(() => _r = change(_r)
        .copyWith(updatedAt: widget.now().millisecondsSinceEpoch));
    final snapshot = _r;
    unawaited(widget.store.upsert(snapshot).catchError((Object e) {
      debugPrint('[confined_space] save failed: $e');
      _reportSaveFailure();
    }));
  }

  bool _saveFailureShown = false;

  /// Raz na ekran: protokół bezpieczeństwa, który się nie zapisuje, nie może
  /// tego robić po cichu.
  void _reportSaveFailure() {
    if (!mounted || _saveFailureShown) return;
    _saveFailureShown = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('cs-save-failed'),
      content: Text(context.tr(
        pl: 'Nie udało się zapisać protokołu w telefonie — udostępnij go '
            '(tekst/PDF), żeby nie przepadł.',
        en: 'Could not save the record on this phone — share it '
            '(text/PDF) so it is not lost.',
      )),
    ));
  }

  void _toggle(ConfinedSpaceCheck c) {
    final wasReady = _r.assess().readyToEnter;
    final willCheck = !_r.isChecked(c);
    _set((r) => r.toggleChecked(c.id));
    if (willCheck) unawaited(Haptic.tap());
    if (!wasReady && _r.assess().readyToEnter) unawaited(Haptic.saved());
  }

  void _toggleNa(ConfinedSpaceCheck c) => _set((r) => r.toggleNa(c.id));

  // ── Progi ──────────────────────────────────────────────────────────────

  CsQty? _parseLimit(CsBound b, String raw) {
    final v = parseDecimal(raw);
    if (v == null || !v.isFinite) return null;
    final q = CsQty(csRound(v), _limitUnit[b]!);
    return csLimitValid(b, q) ? q : null;
  }

  /// Puste pole kasuje próg; poprawny — zapisuje; błędny — NIE zmienia
  /// zapisanego progu (pole pokazuje błąd i to, co obowiązuje).
  void _onLimitText(CsBound b, String raw) {
    if (raw.trim().isEmpty) {
      _set((r) => r.copyWith(limits: r.limits.withLimit(b, null)));
      return;
    }
    final q = _parseLimit(b, raw);
    if (q == null) {
      setState(() {});
      return;
    }
    if (q == _r.limits[b]) return;
    _set((r) => r.copyWith(limits: r.limits.withLimit(b, q)));
  }

  String _limitRange(CsBound b, bool en) {
    String n(double v) => formatCsNumber(v, en: en);
    return switch (b) {
      CsBound.o2Min => en
          ? 'Enter ${n(kCsO2MinPct)}–${n(kCsO2AirPct)} — this limit can only '
              'be raised'
          : 'Wpisz ${n(kCsO2MinPct)}–${n(kCsO2AirPct)} — ten próg można '
              'tylko podnieść',
      CsBound.o2Max => en
          ? 'Enter ${n(kCsO2AirPct)}–${n(kCsO2MaxPct)} — this limit can only '
              'be lowered'
          : 'Wpisz ${n(kCsO2AirPct)}–${n(kCsO2MaxPct)} — ten próg można '
              'tylko obniżyć',
      CsBound.lelMax => en
          ? 'Enter 0–${n(kCsLelMaxPct)} — no more than ${n(kCsLelMaxPct)} % '
              'LEL is allowed'
          : 'Wpisz 0–${n(kCsLelMaxPct)} — więcej niż ${n(kCsLelMaxPct)} % '
              'DGW nie wolno',
      CsBound.coMax => en
          ? 'At most the OEL ${n(kCsCoNdsPpm)} ppm (${n(kCsCoNdsMgM3)} mg/m³) '
              '— can only be lowered'
          : 'Najwyżej NDS ${n(kCsCoNdsPpm)} ppm (${n(kCsCoNdsMgM3)} mg/m³) — '
              'można tylko obniżyć',
      CsBound.h2sMax => en
          ? 'At most the OEL ${formatCsLimit(b, b.hardLimit, en: en)} — can '
              'only be lowered'
          : 'Najwyżej NDS ${formatCsLimit(b, b.hardLimit, en: en)} — można '
              'tylko obniżyć',
    };
  }

  String? _limitError(CsBound b, bool en) {
    final raw = _limit[b]!.text;
    if (raw.trim().isEmpty || _parseLimit(b, raw) != null) return null;
    final stored = _r.limits[b];
    final keep = stored == null
        ? (en ? 'No limit saved.' : 'Brak zapisanego progu.')
        : (en
            ? 'Still in force: ${formatCsLimit(b, stored, en: en)}.'
            : 'Obowiązuje nadal: ${formatCsLimit(b, stored, en: en)}.');
    return '${_limitRange(b, en)}. $keep';
  }

  void _toggleLimitUnit(CsBound b) {
    final units = b.gas.units;
    final next = units[(units.indexOf(_limitUnit[b]!) + 1) % units.length];
    setState(() => _limitUnit[b] = next);
    _onLimitText(b, _limit[b]!.text);
  }

  // ── Pomiary ────────────────────────────────────────────────────────────

  CsQty? _parseReading(CsGas g, String raw) {
    final v = parseDecimal(raw);
    if (v == null || !v.isFinite) return null;
    final q = CsQty(csRound(v), _measUnit[g]!);
    return csQtyInRange(g, q) ? q : null;
  }

  String? _readingError(CsGas g, bool en) {
    final raw = _meas[g]!.text;
    if (raw.trim().isEmpty || _parseReading(g, raw) != null) return null;
    return switch (g) {
      CsGas.o2 || CsGas.lel =>
        en ? 'Enter a number 0–100' : 'Wpisz liczbę 0–100',
      _ => en ? 'Enter a number ≥ 0' : 'Wpisz liczbę ≥ 0',
    };
  }

  /// Odczyty z formularza; `null`, gdy nic nie wpisano albo coś jest błędne.
  Map<CsGas, CsQty>? _formValues() {
    final values = <CsGas, CsQty>{};
    for (final g in CsGas.values) {
      final raw = _meas[g]!.text;
      if (raw.trim().isEmpty) continue;
      final q = _parseReading(g, raw);
      if (q == null) return null;
      values[g] = q;
    }
    return values.isEmpty ? null : values;
  }

  void _toggleMeasUnit(CsGas g) {
    final units = g.units;
    setState(() => _measUnit[g] =
        units[(units.indexOf(_measUnit[g]!) + 1) % units.length]);
  }

  void _addMeasurement() {
    final values = _formValues();
    if (values == null) return;
    final now = widget.now();
    final time = _measTime ?? hotWorkTime(now);
    final at = _measTime == null ? now : hotWorkMeasurementAt(time, now);
    final m = CsMeasurement(
      time: time,
      at: at.millisecondsSinceEpoch,
      values: values,
      place: _measPlace.text.trim(),
    );
    final before = _r.assess();
    _set((r) => r.addMeasurement(m));
    for (final c in _meas.values) {
      c.clear();
    }
    _measPlace.clear();
    setState(() => _measTime = null);
    final after = _r.assess();
    unawaited(after.readiness == CsReadiness.stop &&
            before.readiness != CsReadiness.stop
        ? Haptic.error()
        : Haptic.tap());

    // Remis w tej samej minucie — mówimy wprost, że decyduje gorszy.
    final tied = [
      for (final g in values.keys)
        if (after.verdict(g).tie && after.verdict(g).latest.contains(m))
          after.verdict(g),
    ];
    String? message;
    Key? key;
    if (tied.isNotEmpty) {
      message = csTieText(tied.first, en: context.language == AppLanguage.en);
      key = const ValueKey('cs-meas-tie');
    } else {
      // Zaległy pomiar nie zmienia stanu — żeby nikt nie myślał, że wpisane
      // później „w normie” zdjęło STOP.
      for (final g in values.keys) {
        final latest = before.verdict(g).decisive;
        if (latest != null && m.minute < latest.minute) {
          message = context.tr(
            pl: 'Pomiar z $time jest wcześniejszy niż ostatni '
                '(${latest.time}) — stan ocenia najpóźniejszy pomiar.',
            en: 'The $time reading is earlier than the latest one '
                '(${latest.time}) — the status uses the latest reading.',
          );
          key = const ValueKey('cs-meas-backdated');
          break;
        }
      }
    }
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(key: key, content: Text(message)));
    }
  }

  /// Usunięcie z „Cofnij”. Cofnięcie zapisuje przez magazyn (działa także
  /// po zamknięciu ekranu); stan ekranu poprawia tylko, gdy ekran istnieje.
  void _removeMeasurement(CsMeasurement m) {
    final before = _r;
    _set((r) => r.removeMeasurement(m));
    final store = widget.store;
    final id = _r.id;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Pomiar usunięty.', en: 'Reading removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () {
            unawaited(store
                .update(id, (r) => r.restoreMeasurement(m), orElse: before)
                .catchError((Object e) {
              debugPrint('[confined_space] undo failed: $e');
            }));
            if (mounted) setState(() => _r = _r.restoreMeasurement(m));
          },
        ),
      ));
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_r.date) ?? widget.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _set((r) => r.copyWith(date: hotWorkDate(picked)));
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
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _shareText() async {
    final en = context.language == AppLanguage.en;
    unawaited(Haptic.tap());
    await widget.shareText(confinedSpaceProtocolText(_r, en: en),
        confinedSpaceSubject(english: en));
  }

  Future<void> _sharePdf() async {
    if (_busy) return;
    final en = context.language == AppLanguage.en;
    setState(() => _busy = true);
    try {
      await widget.sharePdf(_r, en);
    } catch (e) {
      debugPrint('[confined_space] pdf export failed: $e');
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
    final a = _r.assess();
    final today = hotWorkDate(widget.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Protokół wejścia', en: 'Entry record')),
        actions: [
          IconButton(
            key: const ValueKey('cs-share-text'),
            tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share as text'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _shareText,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            key: const ValueKey('cs-share-pdf'),
            tooltip: context.tr(pl: 'PDF protokołu', en: 'Record PDF'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _busy ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('cs-edit-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _StatusCard(assessment: a, limits: _r.limits, en: en),
          const SizedBox(height: 12),
          if (_r.date != today)
            QuoteNotice(
              key: const ValueKey('cs-old-notice'),
              icon: Icons.history,
              text: context.tr(
                pl: 'Protokół z dnia ${_r.date}. Do nowego wejścia użyj „Jak '
                    'wczoraj” na liście — pomiarów i zaznaczeń nie przenosi '
                    'się na inny dzień.',
                en: 'Record dated ${_r.date}. For a new entry use “Same as '
                    'yesterday” on the list — readings and ticks never carry '
                    'over to another day.',
              ),
            ),
          if (_r.droppedOnLoad > 0)
            QuoteNotice(
              key: const ValueKey('cs-damaged-notice'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: context.tr(
                pl: 'W zapisie tego protokołu było ${_r.droppedOnLoad} '
                    'nieczytelnych pomiarów — pominięto je, kopia surowego '
                    'zapisu została w telefonie. Zmierz ponownie.',
                en: '${_r.droppedOnLoad} unreadable reading(s) in this record '
                    'were skipped — a raw copy is kept on the phone. Test '
                    'again.',
              ),
            ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: confinedSpaceDisclaimer(en: en),
          ),
          _permitSection(en),
          _warningsSection(en),
          _gasSection(en, a),
          _phaseSection(ConfinedSpacePhase.before, en),
          _phaseSection(ConfinedSpacePhase.during, en),
          _phaseSection(ConfinedSpacePhase.after, en),
          QuoteSection(
            title: context.tr(pl: 'Uwagi', en: 'Notes'),
            children: [
              TextField(
                key: const ValueKey('cs-f-notes'),
                controller: _notes,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Dodatkowe zabezpieczenia, ustalenia',
                      en: 'Extra precautions, arrangements'),
                ),
                onChanged: (t) => _set((r) => r.copyWith(notes: t)),
              ),
            ],
          ),
          _sourcesSection(en),
          _shareButtons(),
          const SizedBox(height: 12),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: confinedSpaceDisclaimer(en: en),
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
        key: ValueKey('cs-f-$key'),
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
      title: context.tr(pl: 'Pozwolenie', en: 'Permit'),
      subtitle: context.tr(
          pl: 'Dane z pisemnego pozwolenia. Protokół zapisuje się sam.',
          en: 'Details from the written permit. The record saves itself.'),
      children: [
        _text('permitNo', _permitNo,
            context.tr(pl: 'Nr pozwolenia', en: 'Permit no.'),
            (t) => _set((r) => r.copyWith(permitNo: t))),
        _text(
            'location',
            _location,
            context.tr(
                pl: 'Przestrzeń (zbiornik, aparat, rurociąg, studzienka; właz)',
                en: 'Space (tank, vessel, pipe, manhole; entry point)'),
            (t) => _set((r) => r.copyWith(location: t))),
        _text('description', _description,
            context.tr(pl: 'Opis pracy', en: 'Work description'),
            (t) => _set((r) => r.copyWith(description: t)),
            maxLines: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            context.tr(pl: 'Rodzaj pracy w środku', en: 'Work inside'),
            style: const TextStyle(color: kTextSec, fontSize: 12.5),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final p in CsProcess.values)
              FilterChip(
                key: ValueKey('cs-proc-${p.name}'),
                label: Text(p.label(en: en)),
                selected: _r.processes.contains(p),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (on) => _set((r) => r.copyWith(
                    processes: on
                        ? {...r.processes, p}
                        : ({...r.processes}..remove(p)))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _PickButton(
          key: const ValueKey('cs-date'),
          icon: Icons.event_outlined,
          label: context.tr(pl: 'Data', en: 'Date'),
          value: _r.date,
          onTap: _pickDate,
        ),
        const SizedBox(height: 8),
        FieldPair(
          left: _PickButton(
            key: const ValueKey('cs-from'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Ważne od', en: 'Valid from'),
            value: _r.validFrom.isEmpty ? '—' : _r.validFrom,
            onTap: () async {
              final t = await _pickTime(_r.validFrom);
              if (t != null && mounted) {
                _set((r) => r.copyWith(validFrom: t));
              }
            },
          ),
          right: _PickButton(
            key: const ValueKey('cs-to'),
            icon: Icons.schedule,
            label: context.tr(pl: 'Ważne do', en: 'Valid until'),
            value: _r.validTo.isEmpty ? '—' : _r.validTo,
            onTap: () async {
              final t = await _pickTime(_r.validTo);
              if (t != null && mounted) _set((r) => r.copyWith(validTo: t));
            },
          ),
        ),
        const SizedBox(height: 12),
        _text('entrants', _entrants,
            context.tr(pl: 'Wchodzący', en: 'Entrants'),
            (t) => _set((r) => r.copyWith(entrants: t))),
        _text(
            'attendant',
            _attendant,
            context.tr(
                pl: 'Asekurujący (na zewnątrz)', en: 'Attendant (outside)'),
            (t) => _set((r) => r.copyWith(attendant: t))),
        _text('supervisor', _supervisor,
            context.tr(pl: 'Nadzór / kierujący', en: 'Supervisor'),
            (t) => _set((r) => r.copyWith(supervisor: t))),
        _text('issuer', _issuer,
            context.tr(pl: 'Wydający pozwolenie', en: 'Permit issuer'),
            (t) => _set((r) => r.copyWith(issuer: t))),
        _text(
            'rescue',
            _rescue,
            context.tr(
                pl: 'Plan ratunkowy (kto, czym, numer alarmowy)',
                en: 'Rescue plan (who, with what, emergency number)'),
            (t) => _set((r) => r.copyWith(rescue: t)),
            maxLines: 3),
      ],
    );
  }

  Widget _warningsSection(bool en) {
    final warnings = confinedSpaceWarnings(_r.processes);
    return QuoteSection(
      key: const ValueKey('cs-warnings'),
      title: context.tr(
          pl: 'Ostrzeżenia dla spawacza', en: 'Warnings for the welder'),
      subtitle: _r.processes.isEmpty
          ? context.tr(
              pl: 'Zaznacz rodzaj pracy powyżej — ostrzeżenia dobiorą się do '
                  'procesu.',
              en: 'Pick the work type above — warnings follow the process.')
          : null,
      children: [
        for (final w in warnings)
          Padding(
            key: ValueKey('cs-warn-${w.id}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: kWarn, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.label(en: en),
                          style: const TextStyle(
                              color: kText, fontSize: 13.5, height: 1.35)),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(w.source,
                            style: const TextStyle(
                                fontSize: 11.5, color: kTextMut)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _phaseSection(ConfinedSpacePhase phase, bool en) {
    final checks = confinedSpaceChecksIn(phase);
    final done = checks.where(_r.isSettled).length;
    final groups = confinedSpaceGroupsIn(phase);
    return QuoteSection(
      key: ValueKey('cs-phase-${phase.name}'),
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
        for (final g in groups) ...[
          if (groups.length > 1) _GroupLabel(g.label(en: en)),
          for (final c in confinedSpaceChecksInGroup(g))
            _CheckTile(
              check: c,
              checked: _r.isChecked(c),
              na: _r.isNa(c),
              en: en,
              onToggle: () => _toggle(c),
              onNa: () => _toggleNa(c),
            ),
        ],
      ],
    );
  }

  Widget _unitButton(String key, String label, VoidCallback onTap) {
    return OutlinedButton(
      key: ValueKey(key),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kMinTapTarget + 16, 56),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: kArc,
        side: const BorderSide(color: kBorder),
      ),
      onPressed: onTap,
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _limitField(CsBound b, String label, bool en) {
    final unit = _limitUnit[b]!;
    final field = TextField(
      key: ValueKey('cs-limit-${b.name}'),
      controller: _limit[b],
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: _hasUnits(b) ? null : unit.label(en: en),
        errorText: _limitError(b, en),
        errorMaxLines: 4,
      ),
      onChanged: (t) => _onLimitText(b, t),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _hasUnits(b)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field),
                const SizedBox(width: 8),
                _unitButton('cs-limit-unit-${b.name}', unit.label(en: en),
                    () => _toggleLimitUnit(b)),
              ],
            )
          : field,
    );
  }

  Widget _readingField(CsGas g, bool en) {
    final unit = _measUnit[g]!;
    final field = TextField(
      key: ValueKey('cs-meas-${g.name}'),
      controller: _meas[g],
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: g.label(en: en),
        suffixText: g.units.length > 1 ? null : unit.label(en: en),
        errorText: _readingError(g, en),
      ),
      onChanged: (_) => setState(() {}),
    );
    if (g.units.length < 2) return field;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        _unitButton('cs-meas-unit-${g.name}', unit.label(en: en),
            () => _toggleMeasUnit(g)),
      ],
    );
  }

  Widget _gasSection(bool en, CsAssessment a) {
    final limits = _r.limits;
    final canAdd = _formValues() != null;
    final ms = _r.measurementsChrono;
    return QuoteSection(
      key: const ValueKey('cs-gas'),
      title: context.tr(pl: 'Pomiary atmosfery', en: 'Gas readings'),
      subtitle: context.tr(
          pl: 'Kolejność: tlen, gazy palne, toksyczne — przy włazie, w środku '
              'i przy dnie. O stanie decyduje najpóźniejszy odczyt każdego '
              'gazu; brak odczytu to nie „w normie”.',
          en: 'Order: oxygen, flammables, toxics — at the manhole, in the '
              'middle and at the bottom. The latest reading of each gas '
              'decides; a missing reading is never OK.'),
      children: [
        for (final v in a.gases) _GasSummary(verdict: v, limits: limits, en: en),
        const SizedBox(height: 6),
        _SubHeader(context.tr(
            pl: 'Progi wg pozwolenia (tylko ostrzej niż domyślne)',
            en: 'Limits per the permit (only stricter than the defaults)')),
        FieldPair(
          left: _limitField(CsBound.o2Min,
              context.tr(pl: 'O₂ co najmniej', en: 'O₂ at least'), en),
          right: _limitField(CsBound.o2Max,
              context.tr(pl: 'O₂ najwyżej', en: 'O₂ at most'), en),
        ),
        _limitField(CsBound.lelMax,
            context.tr(pl: 'Gazy palne najwyżej', en: 'Flammables at most'),
            en),
        _limitField(
            CsBound.coMax, context.tr(pl: 'CO najwyżej', en: 'CO at most'), en),
        _limitField(CsBound.h2sMax,
            context.tr(pl: 'H₂S najwyżej', en: 'H₂S at most'), en),
        for (final g in [CsGas.co, CsGas.h2s])
          SwitchListTile(
            key: ValueKey('cs-req-${g.name}'),
            contentPadding: EdgeInsets.zero,
            value: _r.requiredGases.contains(g),
            onChanged: (on) => _set((r) => r.withRequired(g, on)),
            title: Text(
              context.tr(
                  pl: '${g.label(en: false)}: odczyt wymagany',
                  en: '${g.label(en: true)}: reading required'),
              style: const TextStyle(fontSize: 14, color: kText),
            ),
            subtitle: Text(
              context.tr(
                  pl: 'Wyłącz tylko, gdy pozwolenie tego gazu nie wymaga.',
                  en: 'Switch off only if the permit does not require it.'),
              style: const TextStyle(fontSize: 12, color: kTextMut),
            ),
          ),
        const SizedBox(height: 6),
        _SubHeader(context.tr(pl: 'Odczyty', en: 'Readings')),
        if (ms.isEmpty)
          Padding(
            key: const ValueKey('cs-meas-empty'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr(
                  pl: 'Brak pomiaru — bez odczytów stan nie będzie zielony.',
                  en: 'No reading — without readings the status cannot turn '
                      'green.'),
              style: const TextStyle(
                  color: kWarn, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        for (final (i, m) in ms.indexed)
          _MeasurementRow(
            key: ValueKey('cs-meas-$i'),
            text: csMeasurementLine(m, limits, en: en),
            color: _rowColor(m, limits),
            deleteKey: ValueKey('cs-meas-del-$i'),
            deleteTooltip: context.tr(pl: 'Usuń pomiar', en: 'Remove reading'),
            onDelete: () => _removeMeasurement(m),
          ),
        const SizedBox(height: 4),
        _SubHeader(context.tr(pl: 'Nowy odczyt', en: 'New reading')),
        FieldPair(
          left: _readingField(CsGas.o2, en),
          right: _readingField(CsGas.lel, en),
        ),
        const SizedBox(height: 10),
        _readingField(CsGas.co, en),
        const SizedBox(height: 10),
        _readingField(CsGas.h2s, en),
        const SizedBox(height: 10),
        FieldPair(
          left: TextField(
            key: const ValueKey('cs-meas-place'),
            controller: _measPlace,
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Miejsce / poziom (np. dno)',
                  en: 'Place / level (e.g. bottom)'),
            ),
          ),
          right: _PickButton(
            key: const ValueKey('cs-meas-time'),
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
        FilledButton.icon(
          key: const ValueKey('cs-meas-add'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget)),
          onPressed: canAdd ? _addMeasurement : null,
          icon: const Icon(Icons.add),
          label: Text(context.tr(pl: 'Dodaj pomiar', en: 'Add reading')),
        ),
      ],
    );
  }

  Color _rowColor(CsMeasurement m, CsLimits limits) {
    final states = [
      for (final g in CsGas.values)
        if (m[g] != null) csReadingState(g, m[g]!, limits),
    ];
    if (states.any((s) => s.stop)) return kFail;
    if (states.every((s) => s == CsReadingState.ok)) return kPass;
    return kTextSec;
  }

  Widget _sourcesSection(bool en) {
    return QuoteSection(
      key: const ValueKey('cs-sources'),
      title: context.tr(
          pl: 'Źródła i wartości odniesienia',
          en: 'Sources and reference values'),
      subtitle: context.tr(
          pl: 'Dla orientacji — obowiązują wartości z pozwolenia.',
          en: 'For orientation — the permit values apply.'),
      children: [
        for (final s in kConfinedSpaceSources)
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
            key: const ValueKey('cs-share-text-btn'),
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
            key: const ValueKey('cs-share-pdf-btn'),
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
  const _StatusCard(
      {required this.assessment, required this.limits, required this.en});

  final CsAssessment assessment;
  final CsLimits limits;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final color = confinedSpaceReadinessColor(a);
    final total = {
      for (final p in ConfinedSpacePhase.values)
        p: confinedSpaceChecksIn(p).length,
    };
    final open = {
      ConfinedSpacePhase.before: a.openBefore.length,
      ConfinedSpacePhase.during: a.openDuring.length,
      ConfinedSpacePhase.after: a.openAfter.length,
    };
    final counts = [
      for (final p in ConfinedSpacePhase.values)
        '${p.label(en: en)}: ${total[p]! - open[p]!}/${total[p]}',
    ].join(' · ');
    final blockers = [
      for (final v in a.stops) 'STOP — ${csStopText(v, limits, en: en)}',
      if (a.missing.isNotEmpty)
        en
            ? 'no reading: ${a.missing.map((v) => v.gas.short(en: true)).join(', ')}'
            : 'brak odczytu: ${a.missing.map((v) => v.gas.short(en: false)).join(', ')}',
      if (a.noLimits.isNotEmpty)
        en
            ? 'no limit: ${a.noLimits.map((v) => v.gas.short(en: true)).join(', ')}'
            : 'brak progu: ${a.noLimits.map((v) => v.gas.short(en: false)).join(', ')}',
      if (a.openBefore.isNotEmpty)
        en
            ? '${a.openBefore.length} item(s) before entry'
            : 'do odhaczenia przed wejściem: ${a.openBefore.length}',
    ];
    return Material(
      key: const ValueKey('cs-status'),
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
            Icon(confinedSpaceReadinessIcon(a), color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    confinedSpaceReadinessText(a, limits, en: en),
                    key: const ValueKey('cs-status-text'),
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
                  for (final v in a.ties)
                    Padding(
                      key: ValueKey('cs-tie-${v.gas.name}'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('⚠ ${csTieText(v, en: en)}',
                          style: const TextStyle(
                              color: kWarn,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600)),
                    ),
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

/// Ostatni odczyt jednego gazu: „O₂ — 20,9 % o 10:30 — OK”.
class _GasSummary extends StatelessWidget {
  const _GasSummary(
      {required this.verdict, required this.limits, required this.en});

  final CsGasVerdict verdict;
  final CsLimits limits;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final String value;
    final Color color;
    if (v.missing) {
      value = v.isRequired
          ? (en ? 'no reading — required' : 'brak odczytu — wymagany')
          : (en ? 'no reading — not required' : 'brak odczytu — niewymagany');
      color = v.isRequired ? kWarn : kTextSec;
    } else {
      final state = csStateLabel(v.state!, v.gas, en: en);
      value = '${formatCsQty(v.gas, v.value!, en: en)} '
          '${en ? 'at' : 'o'} ${v.decisive!.time} — $state';
      color = csStateColor(v.state);
    }
    return Padding(
      key: ValueKey('cs-gas-${v.gas.name}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(v.gas.label(en: en),
                style: const TextStyle(
                    color: kTextSec, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    key: ValueKey('cs-gas-value-${v.gas.name}'),
                    style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                Text(
                    '${en ? 'limit' : 'próg'}: '
                    '${formatCsGasLimit(v.gas, limits, en: en)}',
                    style: const TextStyle(color: kTextMut, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
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

  final ConfinedSpaceCheck check;
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
            key: ValueKey('cs-check-${check.id}'),
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
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              check.source,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kTextMut),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (check.naAllowed)
                      TextButton(
                        key: ValueKey('cs-na-${check.id}'),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(text,
                      style: TextStyle(
                          color: color == kTextSec ? kText : color,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
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
