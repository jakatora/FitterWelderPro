// Akord: ile zarobiłem — zarobek z dziennika spoin za okres (dziś, tydzień,
// miesiąc, poprzedni miesiąc, własny zakres) dla spawacza albo brygady:
// podstawa (DI albo sztuki), dopłaty, potrącenia za naprawy, minimum
// dzienne, zł/dzień i zł/h, porównanie z „Ile brać za godzinę". Ekran tylko
// CZYTA dziennik; stawki trzyma w SharedPreferences.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/weld_journal_dao.dart';
import '../../domain/piecework/piecework.dart';
import '../../domain/progress/progress_report.dart' show progressNum, weldsCount;
import '../../domain/progress/work_calendar.dart';
import '../../domain/quotes/quote_calculator.dart' show formatPln, toGrosze;
import '../../domain/weld_journal/weld_dates.dart';
import '../../domain/weld_journal/weld_entry.dart';
import '../../i18n/app_language.dart';
import '../../screens/weld_journal_screen.dart' show WeldJournalScreen;
import '../../services/piecework_export.dart';
import '../../services/welder_identity.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/help_button.dart';
import '../quotes/quote_widgets.dart';
import 'piecework_help.dart';
import 'piecework_store.dart';

/// Źródło spoin (domyślnie dziennik spoin) — wstrzykiwane w testach.
typedef PieceworkWeldSource = Future<List<WeldEntry>> Function();

Future<List<WeldEntry>> _defaultWelds() => WeldJournalDao().listAll();

Future<String?> _defaultIdentity() async =>
    (await WelderIdentityService.instance.get())?.stamp;

Future<void> _defaultShareText(String text, String subject) =>
    PieceworkExport.shareText(text, subject);

class PieceworkPage extends StatefulWidget {
  const PieceworkPage({
    super.key,
    this.clock,
    this.loadWelds = _defaultWelds,
    this.loadIdentity = _defaultIdentity,
    this.loadHourlyMinimum = loadSavedHourlyMinimum,
    this.store = const PieceworkRatesStore(),
    this.shareText = _defaultShareText,
    this.sharePdf = PieceworkExport.sharePdf,
  });

  /// Zegar — w testach stały dzień.
  final DateTime Function()? clock;
  final PieceworkWeldSource loadWelds;

  /// Stempel „ja" (tożsamość spawacza na telefonie) albo null.
  final Future<String?> Function() loadIdentity;

  /// Minimalna stawka z „Ile brać za godzinę" w groszach albo null.
  final Future<int?> Function() loadHourlyMinimum;
  final PieceworkRatesStore store;
  final PieceworkShareText shareText;
  final PieceworkSharePdf sharePdf;

  @override
  State<PieceworkPage> createState() => _PieceworkPageState();
}

/// Wartość listy spawaczy oznaczająca całą brygadę.
const String _kCrew = '';

class _PieceworkPageState extends State<PieceworkPage> {
  /// Nieusunięte wpisy dziennika.
  List<WeldEntry> _all = const [];
  PieceworkRates _rates = const PieceworkRates();
  bool _ratesDamaged = false;
  PieceworkPeriod _period = PieceworkPeriod.month;
  DateTime? _customFrom;
  DateTime? _customTo;

  /// Stempel spawacza albo null — cała brygada.
  String? _welder;

  /// „Ja" w pisowni z dziennika (albo z profilu, gdy w dzienniku go nie ma).
  String? _me;
  int? _hourlyMin;
  double? _typedHours;
  int _hoursField = 0;
  bool _loading = true;
  bool _failed = false;
  bool _exporting = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true));
  }

  Future<void> _load({bool first = false}) async {
    var failed = false;
    var all = const <WeldEntry>[];
    try {
      all = (await widget.loadWelds()).where((e) => !e.isDeleted).toList();
    } catch (e) {
      debugPrint('[piecework] journal load failed: $e');
      failed = true;
    }
    var rates = _rates;
    var damaged = _ratesDamaged;
    String? identity;
    var hourly = _hourlyMin;
    if (first) {
      final load = await widget.store.load();
      rates = load.rates;
      damaged = load.damaged;
      try {
        identity = (await widget.loadIdentity())?.trim();
      } catch (e) {
        debugPrint('[piecework] identity failed: $e');
      }
      try {
        hourly = await widget.loadHourlyMinimum();
      } catch (e) {
        debugPrint('[piecework] hourly rate failed: $e');
      }
    }
    if (!mounted) return;
    final stamps = pieceworkStamps(all);
    setState(() {
      _all = all;
      _failed = failed;
      _rates = rates;
      _ratesDamaged = damaged;
      _hourlyMin = hourly;
      if (first) {
        final id = identity == null || identity.isEmpty ? null : identity;
        _me = id == null
            ? null
            : defaultPieceworkWelder(identityStamp: id, stamps: stamps);
        _welder = defaultPieceworkWelder(identityStamp: id, stamps: stamps);
      } else if (_welder != null &&
          _welder!.toLowerCase() != _me?.toLowerCase() &&
          !stamps.any((s) => s.toLowerCase() == _welder!.toLowerCase())) {
        // Stempla nie ma już w dzienniku (poprawiony, usunięte spoiny).
        _welder = null;
      }
      _loading = false;
    });
  }

  void _setRates(PieceworkRates r) {
    if (r == _rates) return;
    setState(() => _rates = r);
    unawaited(widget.store.save(r).catchError(
        (Object e) => debugPrint('[piecework] save rates failed: $e')));
  }

  void _setPeriod(PieceworkPeriod p, {DateTime? from, DateTime? to}) {
    setState(() {
      _period = p;
      if (from != null) _customFrom = from;
      if (to != null) _customTo = to;
      // Wpisane godziny dotyczyły poprzedniego okresu.
      _typedHours = null;
      _hoursField++;
    });
  }

  Future<void> _pickCustom() async {
    final today = dayOnly(_now.toLocal());
    final r = pieceworkRange(_period, _now,
        customFrom: _customFrom, customTo: _customTo);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(kMinWeldYear),
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: r.from, end: r.to),
    );
    if (picked == null || !mounted) return;
    _setPeriod(PieceworkPeriod.custom,
        from: dayOnly(picked.start), to: dayOnly(picked.end));
  }

  Future<void> _openJournal() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WeldJournalScreen()));
    if (!mounted) return;
    await _load();
  }

  PieceworkReport _report() {
    final result = computePiecework(
      entries: _all,
      rates: _rates,
      range: pieceworkRange(_period, _now,
          customFrom: _customFrom, customTo: _customTo),
      welder: _welder,
    );
    return PieceworkReport(
      result: result,
      hours: pieceworkHours(
        typed: _typedHours,
        perDay: _rates.hoursPerDay,
        days: result.daysWorked,
      ),
      hourlyMinGrosze: _hourlyMin,
      generatedAt: _now,
    );
  }

  Future<void> _shareText(PieceworkReport r) async {
    final en = context.language == AppLanguage.en;
    final text = buildPieceworkText(r, en: en);
    final copied = _tr('Skopiowano zestawienie.', 'Summary copied.');
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
      return;
    }
    try {
      await widget.shareText(text, PieceworkExport.subject(r, en: en));
    } catch (e) {
      debugPrint('[piecework] share text failed: $e');
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    }
  }

  Future<void> _sharePdf(PieceworkReport r) async {
    if (_exporting) return;
    final en = context.language == AppLanguage.en;
    final failed =
        _tr('Nie udało się przygotować PDF.', 'Could not prepare the PDF.');
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      await widget.sharePdf(r, en);
    } catch (e) {
      debugPrint('[piecework] pdf failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Akord: ile zarobiłem', 'Piecework: what I earned')),
        actions: [
          const HelpButton(help: kHelpPiecework),
          IconButton(
            key: const ValueKey('piecework-journal'),
            tooltip: _tr('Dziennik spoin', 'Weld journal'),
            icon: const Icon(Icons.article_outlined),
            onPressed: _loading ? null : _openJournal,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : (_failed ? _error() : _content(_report(), en)),
    );
  }

  Widget _error() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _tr('Nie udało się odczytać dziennika spoin.',
                'Could not read the weld journal.'),
            style: const TextStyle(color: kFail, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('piecework-retry'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: () {
              setState(() => _loading = true);
              unawaited(_load());
            },
            icon: const Icon(Icons.refresh),
            label: Text(_tr('Spróbuj ponownie', 'Try again')),
          ),
        ],
      );

  Widget _content(PieceworkReport report, bool en) => ListView(
        key: const ValueKey('piecework-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _scopeSection(report, en),
          _resultSection(report, en),
          _ratesSection(en),
          _shareSection(report, en),
          Text(
            pieceworkDefinitions(en: en).map((d) => '• $d').join('\n'),
            style:
                const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
          ),
        ],
      );

  // ─── Okres i spawacz ───────────────────────────────────────────────────

  Widget _scopeSection(PieceworkReport report, bool en) {
    final stamps = pieceworkStamps(_all);
    final me = _me;
    final current = _welder ?? _kCrew;
    final others = [
      for (final s in stamps)
        if (s.toLowerCase() != me?.toLowerCase()) s,
    ];
    final known = {
      _kCrew,
      if (me != null) me,
      ...others,
    };
    final r = report.result.range;
    return QuoteSection(
      title: _tr('Okres i spawacz', 'Period and welder'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in PieceworkPeriod.values)
              ChoiceChip(
                key: ValueKey('piecework-period-${p.name}'),
                label: Text(p == PieceworkPeriod.custom &&
                        _period == PieceworkPeriod.custom
                    ? '${isoDate(r.from)} – ${isoDate(r.to)}'
                    : pieceworkPeriodLabel(p, en: en)),
                selected: _period == p,
                onSelected: (_) {
                  if (p == PieceworkPeriod.custom) {
                    unawaited(_pickCustom());
                  } else {
                    _setPeriod(p);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: const ValueKey('piecework-welder'),
          child: DropdownButtonFormField<String>(
            key: ValueKey('piecework-welder-$current'),
            initialValue: known.contains(current) ? current : _kCrew,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _tr('Spawacz', 'Welder'),
              border: const OutlineInputBorder(),
            ),
            items: [
              if (me != null)
                DropdownMenuItem(
                  value: me,
                  child: Text('${_tr('Ja', 'Me')} ($me)',
                      overflow: TextOverflow.ellipsis),
                ),
              DropdownMenuItem(
                value: _kCrew,
                child: Text(
                    _tr('Cała brygada (każda spoina raz)',
                        'Whole crew (each weld once)'),
                    overflow: TextOverflow.ellipsis),
              ),
              for (final s in others)
                DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(
                () => _welder = (v == null || v == _kCrew) ? null : v),
          ),
        ),
      ],
    );
  }

  // ─── Wynik ─────────────────────────────────────────────────────────────

  Widget _resultSection(PieceworkReport report, bool en) {
    final r = report.result;
    final cmp = hourlyCompareText(report, en: en);
    final perHour = report.perHourGrosze;
    final notes = pieceworkNotes(r, en: en);
    return QuoteSection(
      title: _tr('Zarobek', 'Earnings'),
      subtitle:
          '${report.periodText(en: en)} · ${report.welderText(en: en)}',
      children: [
        if (_all.isEmpty)
          QuoteNotice(
            key: const ValueKey('piecework-empty'),
            text: _tr(
                'Dziennik spoin jest pusty. Akord liczy się sam ze spoin '
                    'wpisanych w dzienniku — tu niczego nie przepisujesz.',
                'The weld journal is empty. Piecework is worked out from the '
                    'welds in the journal — nothing is typed twice.'),
          )
        else if (r.isEmpty && r.skippedNoOd.isEmpty)
          QuoteNotice(
            key: const ValueKey('piecework-none'),
            text: _tr(
                'Brak spoin w tym okresie dla wybranego spawacza. Zmień okres '
                    'albo spawacza.',
                'No welds in this period for the chosen welder. Change the '
                    'period or the welder.'),
          ),
        _TotalReadout(
          key: const ValueKey('piecework-total'),
          label: _tr('Akord brutto', 'Piecework, gross'),
          value: formatPln(r.totalGrosze),
          unit: '${weldsCount(r.welds, en: en)} · '
              '${r.approxWelds > 0 ? '≈ ' : ''}'
              '${progressNum(r.di, en: en, decimals: 2)} DI',
        ),
        const SizedBox(height: 12),
        for (final row in pieceworkRows(r, en: en))
          _AmountRow(
            key: ValueKey('piecework-row-${row.id}'),
            label: row.label,
            grosze: row.grosze,
          ),
        const Divider(color: kBorder, height: 16),
        _AmountRow(
          key: const ValueKey('piecework-row-total'),
          label: _tr('Razem (przed podatkiem)', 'Total (before tax)'),
          grosze: r.totalGrosze,
          strong: true,
        ),
        const SizedBox(height: 10),
        _Tiles(children: [
          FactTile(
            key: const ValueKey('piecework-per-day'),
            icon: Icons.today,
            label: _tr('Średnio na dzień', 'Average per day'),
            value: r.perDayGrosze == null ? '—' : formatPln(r.perDayGrosze!),
            sub: '${_tr('dni z wpisami', 'days with entries')}: '
                '${r.daysWorked}',
          ),
          FactTile(
            key: const ValueKey('piecework-per-hour'),
            icon: Icons.schedule,
            label: _tr('Na godzinę', 'Per hour'),
            value: perHour == null ? '—' : formatPln(perHour),
            sub: hoursText(report, en: en) ??
                _tr('wpisz godziny poniżej', 'enter the hours below'),
          ),
        ]),
        if (cmp != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              cmp,
              key: const ValueKey('piecework-hourly-compare'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: perHour! >= report.hourlyMinGrosze! ? kPass : kWarn,
              ),
            ),
          ),
        const SizedBox(height: 12),
        QuoteNumberField(
          key: ValueKey('piecework-hours-$_hoursField'),
          label: _tr('Godziny w okresie (opcjonalnie)',
              'Hours in the period (optional)'),
          unit: 'h',
          value: _typedHours,
          allowEmpty: true,
          decimals: 1,
          helper: _tr(
              'Z karty pracy. Puste = „godzin dziennie" ze stawek × dni z wpisami.',
              'From the timesheet. Empty = "hours per day" from the rates × days with entries.'),
          validate: (x) => x != null && x <= 0
              ? _tr('Wpisz liczbę większą od zera', 'Enter a number above zero')
              : null,
          onChanged: (x) =>
              setState(() => _typedHours = x != null && x > 0 ? x : null),
        ),
        if (r.skippedNoOd.isNotEmpty) _skipped(r, en),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(n, style: const TextStyle(fontSize: 12, color: kWarn)),
          ),
      ],
    );
  }

  Widget _skipped(PieceworkResult r, bool en) {
    final list = r.skippedNoOd;
    const shown = 30;
    return Padding(
      key: const ValueKey('piecework-skipped'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuoteNotice(
            color: kFail,
            icon: Icons.report_problem_outlined,
            text: _tr(
                'Pominięte — brak wymiaru (OD): ${weldsCount(list.length, en: en)}. '
                    'Kwota ich NIE zawiera. Uzupełnij OD w dzienniku spoin — '
                    'DI nie jest zgadywane.',
                'Skipped — no size (OD): ${weldsCount(list.length, en: en)}. '
                    'The amount does NOT include them. Fill in the OD in the '
                    'weld journal — DI is never guessed.'),
          ),
          for (final e in list.take(shown))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${skippedWeldLine(e)}',
                key: ValueKey('piecework-skipped-${e.id}'),
                style: const TextStyle(fontSize: 12.5, color: kText),
              ),
            ),
          if (list.length > shown)
            Text('… +${list.length - shown}',
                style: const TextStyle(fontSize: 12.5, color: kTextSec)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('piecework-fix-journal'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _openJournal,
            icon: const Icon(Icons.edit_note),
            label: Text(_tr('Uzupełnij w dzienniku spoin',
                'Fill in the weld journal')),
          ),
        ],
      ),
    );
  }

  // ─── Stawki ────────────────────────────────────────────────────────────

  String? _pctError(double? x, {double max = 1000}) => x != null &&
          (x < 0 || x > max)
      ? _tr('Od 0 do ${progressNum(max, en: false)} %',
          'From 0 to ${progressNum(max, en: true)} %')
      : null;

  Widget _pct(String key, String label, int bp, ValueChanged<int> onBp,
          {double max = 1000, String? helper}) =>
      QuoteNumberField(
        key: ValueKey(key),
        label: label,
        unit: '%',
        value: bp / 100,
        helper: helper,
        validate: (x) => _pctError(x, max: max),
        onChanged: (x) {
          if (x == null || _pctError(x, max: max) != null) return;
          onBp(bpFromPct(x));
        },
      );

  Widget _chip<T>(String key, T value, T selected, String label,
          ValueChanged<T> onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: value == selected,
        onSelected: (_) => onTap(value),
      );

  Widget _sub(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
      );

  Widget _ratesSection(bool en) {
    final r = _rates;
    return QuoteSection(
      key: const ValueKey('piecework-rates'),
      title: _tr('Stawki', 'Rates'),
      subtitle: _tr(
          'Zapamiętane na telefonie. Kwoty przed podatkiem.',
          'Kept on the phone. Amounts before tax.'),
      children: [
        if (_ratesDamaged)
          QuoteNotice(
            key: const ValueKey('piecework-rates-damaged'),
            color: kFail,
            text: _tr(
                'Zapisane stawki były uszkodzone — nieczytelne pola wróciły do '
                    'wartości domyślnych. Surowy zapis trafi pod '
                    '„${PieceworkRatesStore.corruptKey}" przy pierwszej zmianie.',
                'The saved rates were damaged — unreadable fields are back to '
                    'defaults. The raw record is kept under '
                    '"${PieceworkRatesStore.corruptKey}" on the first change.'),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('piecework-mode-di', PieceworkMode.di, r.mode,
                _tr('Za cal-średnicę (DI)', 'Per dia-inch (DI)'),
                (m) => _setRates(r.copyWith(mode: m))),
            _chip('piecework-mode-weld', PieceworkMode.weld, r.mode,
                _tr('Za spoinę', 'Per weld'),
                (m) => _setRates(r.copyWith(mode: m))),
          ],
        ),
        const SizedBox(height: 12),
        QuoteNumberField(
          key: ValueKey('piecework-rate-${r.mode.code}'),
          label: _tr('Stawka', 'Rate'),
          unit: pieceworkRateUnit(r.mode, en: en),
          value: r.rateGrosze / 100,
          validate: (x) => x != null && (x < 0 || toGrosze(x) > kPieceworkMaxRateGrosze)
              ? _tr('Wpisz kwotę od 0', 'Enter an amount from 0')
              : null,
          onChanged: (x) {
            if (x == null || x < 0) return;
            final g = toGrosze(x);
            if (g > kPieceworkMaxRateGrosze) return;
            _setRates(r.copyWith(rateGrosze: g));
          },
        ),
        _sub(_tr('Dopłaty — % podstawy, sumują się',
            'Surcharges — % of the base, they add up')),
        FieldPair(
          left: _pct('piecework-ss', _tr('Nierdzewna', 'Stainless'),
              r.stainlessBp, (v) => _setRates(r.copyWith(stainlessBp: v))),
          right: _pct(
              'piecework-other',
              _tr('Inne (Cr-Mo, Ni…)', 'Other (Cr-Mo, Ni…)'),
              r.otherMaterialBp,
              (v) => _setRates(r.copyWith(otherMaterialBp: v))),
        ),
        const SizedBox(height: 10),
        FieldPair(
          left: _pct('piecework-p2g', '${_tr('Pozycja', 'Position')} 2G',
              r.pos2gBp, (v) => _setRates(r.copyWith(pos2gBp: v))),
          right: _pct('piecework-p5g', '${_tr('Pozycja', 'Position')} 5G',
              r.pos5gBp, (v) => _setRates(r.copyWith(pos5gBp: v))),
        ),
        const SizedBox(height: 10),
        _pct('piecework-p6g', '${_tr('Pozycja', 'Position')} 6G', r.pos6gBp,
            (v) => _setRates(r.copyWith(pos6gBp: v)),
            helper: _tr('5G = też PF/PG/PH/PJ, 6G = H-L045/J-L045, 2G = PC.',
                '5G = also PF/PG/PH/PJ, 6G = H-L045/J-L045, 2G = PC.')),
        _sub(_tr('Gruba ścianka', 'Heavy wall')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('piecework-wall-none', WallRule.none, r.wallRule,
                _tr('Bez dopłaty', 'No surcharge'),
                (w) => _setRates(r.copyWith(wallRule: w))),
            _chip('piecework-wall-sch80', WallRule.sch80, r.wallRule,
                'Sch 80+', (w) => _setRates(r.copyWith(wallRule: w))),
            _chip('piecework-wall-mm', WallRule.mm, r.wallRule,
                _tr('Od grubości (mm)', 'From thickness (mm)'),
                (w) => _setRates(r.copyWith(wallRule: w))),
          ],
        ),
        if (r.wallRule != WallRule.none) ...[
          const SizedBox(height: 10),
          if (r.wallRule == WallRule.mm) ...[
            QuoteNumberField(
              key: const ValueKey('piecework-wall-mm-value'),
              label: _tr('Ścianka od', 'Wall from'),
              unit: 'mm',
              value: r.wallMm,
              validate: (x) => x != null && (x <= 0 || x > kPieceworkMaxWallMm)
                  ? _tr('Od 0 do 200 mm', 'From 0 to 200 mm')
                  : null,
              onChanged: (x) {
                if (x == null || x <= 0 || x > kPieceworkMaxWallMm) return;
                _setRates(r.copyWith(wallMm: x));
              },
            ),
            const SizedBox(height: 10),
          ],
          _pct('piecework-wall-pct', _tr('Dopłata', 'Surcharge'), r.wallBp,
              (v) => _setRates(r.copyWith(wallBp: v)),
              helper: r.wallRule == WallRule.sch80
                  ? _tr('Grubość t z dziennika ≥ ścianki Sch 80 dla OD (nierdzewna: 80S).',
                      'Wall t from the journal ≥ the Sch 80 wall for the OD (stainless: 80S).')
                  : null),
        ],
        _sub(_tr('Naprawy', 'Repairs')),
        _pct(
            'piecework-reject',
            _tr('Potrącenie za odrzuconą spoinę', 'Deduction for a rejected weld'),
            r.rejectBp,
            (v) => _setRates(r.copyWith(rejectBp: v)),
            max: 100,
            helper: _tr(
                '% wartości spoiny: 0 = płatna w całości, 100 = 0 zł. Odrzucona = '
                    'naprawa R1+ albo NOK.',
                '% of the weld value: 0 = paid in full, 100 = 0 zł. Rejected = '
                    'repair R1+ or NOK.')),
        SwitchListTile(
          key: const ValueKey('piecework-repair-paid'),
          contentPadding: EdgeInsets.zero,
          title: Text(_tr('Naprawa płatna osobno', 'Repair paid separately')),
          subtitle: Text(
            _tr('Za każdą naprawę (R1, R2…) % wartości spoiny.',
                'For each repair (R1, R2…) a % of the weld value.'),
            style: const TextStyle(fontSize: 12, color: kTextMut),
          ),
          value: r.repairPaid,
          onChanged: (x) => _setRates(r.copyWith(repairPaid: x)),
        ),
        if (r.repairPaid)
          _pct('piecework-repair-pct',
              _tr('Za naprawę', 'Per repair'), r.repairBp,
              (v) => _setRates(r.copyWith(repairBp: v))),
        _sub(_tr('Dzień pracy', 'Working day')),
        QuoteNumberField(
          key: const ValueKey('piecework-min-day'),
          label: _tr('Minimum dzienne (opcjonalnie)', 'Daily minimum (optional)'),
          unit: 'zł',
          value: r.minDayGrosze == null ? null : r.minDayGrosze! / 100,
          allowEmpty: true,
          helper: _tr(
              'Dzień ze spoinami poniżej minimum jest dopłacany. Tylko dla '
                  'jednego spawacza.',
              'A day with welds below the minimum is topped up. One welder '
                  'only.'),
          validate: (x) => x != null &&
                  (x < 0 || toGrosze(x) > kPieceworkMaxRateGrosze)
              ? _tr('Wpisz kwotę od 0', 'Enter an amount from 0')
              : null,
          onChanged: (x) {
            if (x == null) {
              _setRates(r.copyWith(minDayGrosze: null));
              return;
            }
            final g = toGrosze(x);
            if (x < 0 || g > kPieceworkMaxRateGrosze) return;
            _setRates(r.copyWith(minDayGrosze: g));
          },
        ),
        const SizedBox(height: 10),
        QuoteNumberField(
          key: const ValueKey('piecework-hpd'),
          label: _tr('Godzin dziennie (opcjonalnie)', 'Hours per day (optional)'),
          unit: 'h',
          value: r.hoursPerDay,
          allowEmpty: true,
          decimals: 1,
          helper: _tr('Do zł/godzinę, gdy nie wpiszesz godzin okresu.',
              'For the per-hour figure when the period hours are empty.'),
          validate: (x) =>
              x != null && (x <= 0 || x > kPieceworkMaxHoursPerDay)
                  ? _tr('Od 0 do 24 h', 'From 0 to 24 h')
                  : null,
          onChanged: (x) {
            if (x == null) {
              _setRates(r.copyWith(hoursPerDay: null));
              return;
            }
            if (x <= 0 || x > kPieceworkMaxHoursPerDay) return;
            _setRates(r.copyWith(hoursPerDay: x));
          },
        ),
      ],
    );
  }

  // ─── Udostępnianie ─────────────────────────────────────────────────────

  Widget _shareSection(PieceworkReport report, bool en) => QuoteSection(
        title: _tr('Zestawienie', 'Summary'),
        subtitle: _tr(
            'Do sprawdzenia rozliczenia z firmą. PDF zawiera listę spoina po spoinie.',
            'To check the settlement with the company. The PDF lists every weld.'),
        children: [
          OutlinedButton.icon(
            key: const ValueKey('piecework-share-text'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: () => unawaited(_shareText(report)),
            icon: const Icon(Icons.sms_outlined),
            label: Text(_tr('Wyślij tekstem (SMS, WhatsApp)',
                'Send as text (SMS, WhatsApp)')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('piecework-share-pdf'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _exporting ? null : () => unawaited(_sharePdf(report)),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_tr('Zestawienie PDF', 'PDF summary')),
          ),
        ],
      );
}

/// Kwota główna ekranu w stylu [Readout] — liczba zmniejsza się, zamiast
/// łamać się w pół na wąskim telefonie z dużym tekstem.
class _TotalReadout extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _TotalReadout({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kTextMut,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        CopyOnLongPress(
          value: value,
          label: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 36,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: kArc,
                  fontFeatures: [
                    FontFeature.tabularFigures(),
                    FontFeature.slashedZero(),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          unit.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: kTextMut,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kArc, kArc.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    );
  }
}

/// Wiersz „etykieta ........ 1 234,56 zł" jak [MoneyRow], ale kwota nie
/// rozpycha wiersza: zajmuje najwyżej połowę szerokości i w razie potrzeby
/// się zmniejsza (wąski telefon, duży tekst, kwota sześciocyfrowa).
/// Przytrzymanie kopiuje kwotę — cel dotyku ≥ 48 dp.
class _AmountRow extends StatelessWidget {
  final String label;
  final int grosze;
  final bool strong;

  const _AmountRow({
    super.key,
    required this.label,
    required this.grosze,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final value = formatPln(grosze);
    return CopyOnLongPress(
      value: value,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: strong ? 15 : 13.5,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                        color: strong ? kText : kTextSec,
                      )),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.5),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: strong ? 16 : 14,
                        fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                        color: strong ? kArc : kText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dwa kafelki obok siebie; na wąskim ekranie jeden pod drugim.
class _Tiles extends StatelessWidget {
  final List<Widget> children;
  const _Tiles({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
    });
  }
}
