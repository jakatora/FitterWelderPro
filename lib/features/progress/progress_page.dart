// Postęp robót i wydajność — z dziennika spoin: ile zrobione dziś / w tym
// tygodniu / w miesiącu, DI dzień po dniu, spawacze i naprawy, prognoza
// końca pakietu i raport dla szefa. Ekran tylko CZYTA dziennik; zakres
// pakietu (spoiny / DI do wykonania) trzyma w SharedPreferences.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/weld_journal_dao.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/progress/progress_filter.dart';
import '../../domain/progress/progress_forecast.dart';
import '../../domain/progress/progress_report.dart';
import '../../domain/progress/weld_progress.dart';
import '../../domain/progress/work_calendar.dart';
import '../../domain/weld_journal/weld_dates.dart';
import '../../domain/weld_journal/weld_defaults.dart' show loadLastWeldProject;
import '../../domain/weld_journal/weld_entry.dart';
import '../../i18n/app_language.dart';
import '../../screens/weld_journal_screen.dart' show WeldJournalScreen;
import '../../services/progress_export.dart';
import '../../services/progress_scope_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/help_button.dart';
import '../../widgets/local_record_scope.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'progress_chart.dart';
import 'progress_help.dart';

class ProgressPage extends StatelessWidget {
  final WeldJournalDao? dao;
  final ProgressScopeStore? store;

  /// Zegar — w testach stały dzień.
  final DateTime Function()? clock;

  const ProgressPage({
    super.key,
    this.dao,
    this.store,
    this.clock,
  });

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _ProgressBody(
          session: session,
          dao: dao ?? WeldJournalDao(owner: session.captureOwner),
          store:
              store ?? ProgressScopeStore(captureOwner: session.captureOwner),
          clock: clock,
        ),
      );
}

class _ProgressBody extends StatefulWidget {
  final LocalRecordSession session;
  final WeldJournalDao dao;
  final ProgressScopeStore store;
  final DateTime Function()? clock;

  const _ProgressBody({
    required this.session,
    required this.dao,
    required this.store,
    this.clock,
  });

  @override
  State<_ProgressBody> createState() => _ProgressPageState();
}

/// Wszystko, co ekran pokazuje — liczone raz na przebudowę.
class _View {
  final DateTime today;
  final DayRange? range;
  final ProgressSummary summary;
  final ProgressPace? pace;
  final ProgressForecast? forecast;
  final DayRange chartRange;
  final List<DayProgress> chart;
  final DayProgress todayOutput;
  final WorkWeek week;

  const _View({
    required this.today,
    required this.range,
    required this.summary,
    required this.pace,
    required this.forecast,
    required this.chartRange,
    required this.chart,
    required this.todayOutput,
    required this.week,
  });
}

class _ProgressPageState extends State<_ProgressBody>
    with ToolHandleHost<_ProgressBody> {
  @override
  String get toolId => 'work_progress';
  @override
  Set<String> get supportedFields => const {'project', 'period'};

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.length != 2 ||
        !fields.keys.toSet().containsAll(supportedFields) ||
        fields['project'] is! String ||
        fields['period'] != 'today') {
      return fields.keys.toSet();
    }
    final all = (await _dao.listAll()).where((e) => !e.isDeleted).toList();
    final requested = (fields['project'] as String).trim();
    var project = '';
    if (requested.isNotEmpty) {
      final matches = progressProjects(all)
          .where((p) => p.toLowerCase() == requested.toLowerCase());
      if (matches.isEmpty) return {'project'};
      project = matches.first;
    }
    final scope = await widget.store.load(project, '');
    if (!mounted) return fields.keys.toSet();
    setState(() {
      _all = all;
      _filter = ProgressFilter(project: project, period: ProgressPeriod.today);
      _scope = scope;
      _failed = false;
    });
    return {};
  }

  late final WeldJournalDao _dao = widget.dao;

  /// Nieusunięte wpisy dziennika.
  List<WeldEntry> _all = const [];
  ProgressFilter _filter = const ProgressFilter();
  ProgressScope _scope = const ProgressScope();
  int _paceDays = 10;
  bool _chartDi = true;
  bool _sortByRepairs = false;
  bool _loading = true;
  bool _failed = false;
  bool _exporting = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  DateTime get _today => dayOnly(_now);
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
      all = (await _dao.listAll()).where((e) => !e.isDeleted).toList();
    } catch (e) {
      debugPrint('[work_progress] journal load failed: $e');
      failed = true;
    }
    final projects = progressProjects(all);
    var filter = _filter;
    if ((first || _all.isEmpty) && filter.project.isEmpty) {
      final last = (await loadLastWeldProject()).toLowerCase();
      final match = projects.where((p) => p.toLowerCase() == last);
      if (match.isNotEmpty) {
        filter = filter.copyWith(project: match.first);
      } else if (projects.length == 1) {
        filter = filter.copyWith(project: projects.single);
      }
    }
    filter = _validated(filter, all);
    final scope = await widget.store.load(filter.project, filter.testPackage);
    if (!mounted || !widget.session.isCurrent) return;
    setState(() {
      _all = all;
      _failed = failed;
      _filter = filter;
      _scope = scope;
      _loading = false;
    });
    if (!failed) markReady();
  }

  /// Projekt / pakiet, którego już nie ma w dzienniku (zmieniona nazwa,
  /// usunięte spoiny) — wraca do „wszystkie", w pisowni z dziennika.
  ProgressFilter _validated(ProgressFilter f, List<WeldEntry> all) {
    String canon(String v, List<String> options) {
      final t = v.trim().toLowerCase();
      if (t.isEmpty) return '';
      for (final o in options) {
        if (o.toLowerCase() == t) return o;
      }
      return '';
    }

    final project = canon(f.project, progressProjects(all));
    final pkg = canon(f.testPackage, progressPackages(all, project));
    return f.copyWith(project: project, testPackage: pkg);
  }

  Future<void> _changeScope({String? project, String? testPackage}) async {
    if (!widget.session.isCurrent) return;
    final next = _validated(
        _filter.copyWith(
          project: project ?? _filter.project,
          testPackage: testPackage ?? _filter.testPackage,
        ),
        _all);
    setState(() => _filter = next);
    final scope = await widget.store.load(next.project, next.testPackage);
    if (!mounted || !widget.session.isCurrent || _filter != next) return;
    setState(() => _scope = scope);
  }

  void _saveScope(ProgressScope s) {
    if (!widget.session.isCurrent) return;
    setState(() => _scope = s);
    final f = _filter;
    unawaited(widget.store.save(f.project, f.testPackage, s).catchError(
        (Object e) => debugPrint('[work_progress] save scope failed: $e')));
  }

  Future<void> _openJournal() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WeldJournalScreen()));
    if (!mounted || !widget.session.isCurrent) return;
    await _load();
  }

  Future<void> _pickCustom() async {
    final today = _today;
    final r = _filter.rangeFor(today) ?? DayRange(addDays(today, -6), today);
    final first = DateTime(kMinWeldYear);
    final last = DateTime(today.year + 1, 12, 31);
    final picked = await showDateRangePicker(
      context: context,
      builder: (_, child) => LocalRecordScope(
        restartOnAccountChange: false,
        originSession: widget.session,
        builder: (_, __) => child!,
      ),
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: r.from, end: r.to),
    );
    if (picked == null || !mounted || !widget.session.isCurrent) return;
    setState(() => _filter = _filter.copyWith(
          period: ProgressPeriod.custom,
          customFrom: dayOnly(picked.start),
          customTo: dayOnly(picked.end),
        ));
  }

  Future<void> _pickDue() async {
    final today = _today;
    final first = DateTime(today.year - 1);
    final last = DateTime(today.year + 6, 12, 31);
    var initial = _scope.dueDate ?? addDays(today, 30);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      builder: (_, child) => LocalRecordScope(
        restartOnAccountChange: false,
        originSession: widget.session,
        builder: (_, __) => child!,
      ),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted || !widget.session.isCurrent) return;
    _saveScope(_scope.copyWith(due: isoDate(picked)));
  }

  _View _compute() {
    final today = _today;
    final scope = _filter.scopeOf(_all);
    final range = _filter.rangeFor(today);
    final week = _scope.week;
    final summary = summarizeProgress(_filter.apply(_all, today));
    final scopeSummary = summarizeProgress(scope);
    final pace =
        computePace(scope, today: today, week: week, workingDays: _paceDays);
    final s = _scope;
    ProgressForecast? forecast;
    if (s.hasTotal) {
      final di = s.unit == ScopeUnit.di;
      forecast = computeForecast(
        unit: s.unit,
        done: di ? scopeSummary.di : scopeSummary.welds.toDouble(),
        total: s.total!,
        pacePerDay:
            pace == null ? null : (di ? pace.diPerDay : pace.weldsPerDay),
        today: today,
        todayLogged: isTodayLogged(scope, today),
        week: week,
        due: s.dueDate,
      );
    }
    final chartRange = chartWindow(
      range: range,
      today: today,
      firstWeld: scopeSummary.days.isEmpty ? null : scopeSummary.days.first.day,
    );
    return _View(
      today: today,
      range: range,
      summary: summary,
      pace: pace,
      forecast: forecast,
      chartRange: chartRange,
      chart: dailySeries(scope, chartRange),
      todayOutput: scopeSummary.dayOf(today),
      week: week,
    );
  }

  ProgressReport _report(_View v) => ProgressReport(
        filter: _filter,
        range: v.range,
        summary: v.summary,
        pace: v.pace,
        forecast: v.forecast,
        generatedAt: _now,
      );

  Future<void> _shareText(ProgressReport r) async {
    if (!widget.session.isCurrent) return;
    final en = context.language == AppLanguage.en;
    final text = buildProgressReportText(r, en: en);
    final copied = _tr('Skopiowano raport.', 'Report copied.');
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || !widget.session.isCurrent) return;
      unawaited(Haptic.copied());
      messenger.showSnackBar(SnackBar(content: Text(copied)));
      return;
    }
    try {
      await ProgressExport.shareText(r, en: en);
    } catch (_) {
      if (!mounted || !widget.session.isCurrent) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || !widget.session.isCurrent) return;
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    }
  }

  Future<void> _sharePdf(ProgressReport r) async {
    if (_exporting || !widget.session.isCurrent) return;
    final en = context.language == AppLanguage.en;
    final failed =
        _tr('Nie udało się przygotować PDF.', 'Could not prepare the PDF.');
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      await ProgressExport.sharePdf(r,
          en: en, mayShare: () => widget.session.isCurrent);
    } catch (e) {
      debugPrint('[work_progress] pdf failed: $e');
      if (mounted && widget.session.isCurrent) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Postęp robót', 'Work progress')),
        actions: [
          const HelpButton(help: kHelpProgress),
          IconButton(
            key: const ValueKey('progress-journal'),
            tooltip: _tr('Dziennik spoin', 'Weld journal'),
            icon: const Icon(Icons.article_outlined),
            onPressed: _loading ? null : _openJournal,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : (_failed
              ? _error()
              : (_all.isEmpty ? _empty() : _content(_compute(), en))),
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

  Widget _empty() => ListView(
        key: const ValueKey('progress-empty'),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          const Icon(Icons.insights_outlined, size: 56, color: kTextMut),
          const SizedBox(height: 12),
          Text(
            _tr('Dziennik spoin jest pusty', 'The weld journal is empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              'Postęp liczy się sam ze spoin wpisanych w dzienniku: ile spoin '
                  'i cali-średnic (DI) dziennie, kto ile zespawał, ile było '
                  'napraw i kiedy skończycie pakiet. Wpisz spoiny w dzienniku — '
                  'tu niczego nie przepisujesz.',
              'Progress is worked out from the welds in the journal: how many '
                  'welds and dia-inches (DI) a day, who welded what, how many '
                  'repairs and when the package will be done. Log the welds in '
                  'the journal — nothing is typed twice.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSec, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('progress-open-journal'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
            onPressed: _openJournal,
            icon: const Icon(Icons.article_outlined),
            label: Text(_tr('Otwórz dziennik spoin', 'Open the weld journal'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      );

  Widget _content(_View v, bool en) {
    final report = _report(v);
    return ListView(
      key: const ValueKey('progress-list'),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _filters(v, en),
        _done(v, report, en),
        _chartSection(v, en),
        if (v.summary.welders.isNotEmpty) _welders(v, en),
        _forecastSection(v, en),
        _reportSection(report, en),
        Text(
          definitionLines(en: en).join('\n'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
        ),
      ],
    );
  }

  // ─── Zakres ────────────────────────────────────────────────────────────

  Widget _chip<T>(T value, T selected, String label, ValueChanged<T> onTap,
          {Key? key}) =>
      ChoiceChip(
        key: key,
        label: Text(label),
        selected: value == selected,
        onSelected: (_) => onTap(value),
      );

  Widget _filters(_View v, bool en) {
    final projects = progressProjects(_all);
    final packages = progressPackages(_all, _filter.project);
    final r = v.range;
    return QuoteSection(
      title: _tr('Zakres', 'Scope'),
      children: [
        KeyedSubtree(
          key: const ValueKey('progress-project'),
          child: DropdownButtonFormField<String>(
            key: ValueKey('progress-project-${_filter.project}'),
            initialValue: _filter.project,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _tr('Projekt', 'Project'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                  value: '',
                  child: Text(_tr('Wszystkie projekty', 'All projects'))),
              for (final p in projects)
                DropdownMenuItem(
                    value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (p) =>
                unawaited(_changeScope(project: p ?? '', testPackage: '')),
          ),
        ),
        const SizedBox(height: 10),
        if (packages.isEmpty)
          Text(
            _tr('Brak pakietów testowych w dzienniku (pole „Pakiet testowy" spoiny).',
                'No test packages in the journal (the weld\'s "Test package" field).'),
            style: const TextStyle(fontSize: 12, color: kTextMut),
          )
        else
          KeyedSubtree(
            key: const ValueKey('progress-package'),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                  'progress-package-${_filter.project}-${_filter.testPackage}'),
              initialValue: _filter.testPackage,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr('Pakiet testowy', 'Test package'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                    value: '',
                    child: Text(_tr('Wszystkie pakiety', 'All packages'))),
                for (final p in packages)
                  DropdownMenuItem(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (p) => unawaited(_changeScope(testPackage: p ?? '')),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in ProgressLocation.values)
              _chip<ProgressLocation>(
                l,
                _filter.location,
                progressLocationLabel(l, en: en),
                (x) => setState(() => _filter = _filter.copyWith(location: x)),
                key: ValueKey('progress-loc-${l.name}'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in ProgressPeriod.values)
              ChoiceChip(
                key: ValueKey('progress-period-${p.name}'),
                label: Text(p == ProgressPeriod.custom &&
                        _filter.period == ProgressPeriod.custom &&
                        r != null
                    ? '${isoDate(r.from)} – ${isoDate(r.to)}'
                    : progressPeriodLabel(p, en: en)),
                selected: _filter.period == p,
                onSelected: (_) {
                  if (p == ProgressPeriod.custom) {
                    unawaited(_pickCustom());
                  } else {
                    setState(() => _filter = _filter.copyWith(period: p));
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  // ─── Wykonano ──────────────────────────────────────────────────────────

  Widget _done(_View v, ProgressReport report, bool en) {
    final s = v.summary;
    final pace = v.pace;
    final notes = dataNotes(s, en: en);
    final showToday = _filter.period != ProgressPeriod.today;
    final daysWithWork = s.days.length;
    return QuoteSection(
      title: _tr('Wykonano', 'Done'),
      subtitle: '${report.title(en: en)} · ${report.periodText(en: en)}',
      children: [
        if (s.isEmpty)
          QuoteNotice(
            text: _tr(
                'Brak spoin w tym okresie i zakresie. Zmień okres albo filtr — '
                    'albo wpisz spoiny w dzienniku.',
                'No welds in this period and scope. Change the period or the '
                    'filter — or log welds in the journal.'),
          ),
        Readout(
          key: const ValueKey('progress-total'),
          label: _tr('Cale-średnice (DI)', 'Dia-inches (DI)'),
          value: '${s.diApprox ? '≈ ' : ''}${progressNum(s.di, en: en)}',
          unit: '${weldsCount(s.welds, en: en)} · ${report.periodText(en: en)}',
          hot: true,
        ),
        const SizedBox(height: 12),
        _TileRows(
          columns: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
          children: [
            FactTile(
              key: const ValueKey('progress-welds'),
              icon: Icons.adjust,
              label: _tr('Spoiny', 'Welds'),
              value: '${s.welds}',
              sub: 'OK ${s.statusOk} · NOK ${s.statusNok} · '
                  '${_tr('czeka', 'awaiting')} ${s.statusPending}',
            ),
            FactTile(
              key: const ValueKey('progress-pace'),
              icon: Icons.speed,
              label: _tr('Tempo DI / dzień rob.', 'Pace DI / working day'),
              value: pace == null ? '—' : progressNum(pace.diPerDay, en: en),
              sub: pace == null
                  ? _tr('brak spoin z datą', 'no dated welds')
                  : '${progressNum(pace.weldsPerDay, en: en)} '
                      '${_tr('spoin/dzień', 'welds/day')} · '
                      '${pace.workingDays} ${_tr('dni rob.', 'w. days')}',
            ),
            if (showToday)
              FactTile(
                key: const ValueKey('progress-today'),
                icon: Icons.today,
                label: _tr('Dziś', 'Today'),
                value: '${progressNum(v.todayOutput.di, en: en)} DI',
                sub: weldsCount(v.todayOutput.welds, en: en),
              ),
            FactTile(
              icon: Icons.event_available,
              label: _tr('Dni z wpisami', 'Days with entries'),
              value: '$daysWithWork',
              sub: daysWithWork == 0
                  ? null
                  : '${_tr('śr.', 'avg')} '
                      '${progressNum(s.di / daysWithWork, en: en)} DI '
                      '${_tr('na taki dzień', 'per such day')}',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_tr('Tempo z ostatnich:', 'Pace from the last:'),
                style: const TextStyle(color: kTextSec, fontSize: 12.5)),
            for (final n in const [5, 10, 20])
              _chip<int>(
                n,
                _paceDays,
                '$n ${_tr('dni rob.', 'w. days')}',
                (x) => setState(() => _paceDays = x),
                key: ValueKey('progress-pace-$n'),
              ),
          ],
        ),
        if (pace != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${paceWindowLine(pace, en: en)} · '
              '${_tr('dziś liczy się, gdy ma już wpisy', 'today counts once it has entries')}',
              style: const TextStyle(fontSize: 11.5, color: kTextMut),
            ),
          ),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(n, style: const TextStyle(fontSize: 12, color: kWarn)),
          ),
      ],
    );
  }

  // ─── Wykres ────────────────────────────────────────────────────────────

  Widget _chartSection(_View v, bool en) {
    final avg = v.pace == null
        ? null
        : (_chartDi ? v.pace!.diPerDay : v.pace!.weldsPerDay);
    return QuoteSection(
      title: _tr('Dzień po dniu', 'Day by day'),
      subtitle: '${dayLabel(v.chartRange.from, en: en)} – '
          '${dayLabel(v.chartRange.to, en: en)}'
          '${avg == null ? '' : ' · ${_tr('linia przerywana = tempo', 'dashed line = pace')} ${progressNum(avg, en: en)}'}',
      children: [
        Wrap(
          spacing: 6,
          children: [
            _chip<bool>(
                true, _chartDi, 'DI', (x) => setState(() => _chartDi = x),
                key: const ValueKey('progress-chart-di')),
            _chip<bool>(false, _chartDi, _tr('Spoiny', 'Welds'),
                (x) => setState(() => _chartDi = x),
                key: const ValueKey('progress-chart-welds')),
          ],
        ),
        const SizedBox(height: 10),
        ProgressDailyChart(
          key: const ValueKey('progress-chart'),
          days: v.chart,
          showDi: _chartDi,
          average: avg,
          highlight: v.range,
          week: v.week,
          en: en,
        ),
      ],
    );
  }

  // ─── Spawacze ──────────────────────────────────────────────────────────

  Widget _welders(_View v, bool en) {
    final s = v.summary;
    final list = [...s.welders];
    if (_sortByRepairs) {
      list.sort((a, b) {
        final ra = a.quality.repairRatePct ?? -1;
        final rb = b.quality.repairRatePct ?? -1;
        final byRate = rb.compareTo(ra);
        if (byRate != 0) return byRate;
        return b.quality.repairs.compareTo(a.quality.repairs);
      });
    }
    return QuoteSection(
      title: _tr('Spawacze', 'Welders'),
      subtitle: _tr(
          'Spoina z dwoma spawaczami (grań / lico) jest u obu, DI dzielone po '
              'równo — suma brygady liczy ją raz. Odsetek napraw = spoiny '
              'odrzucone w RT/UT ÷ spoiny zbadane RT/UT (także wynik sprzed '
              'naprawy).',
          'A weld with two welders (root / cap) shows under both, DI split '
              'equally — the crew total counts it once. Repair rate = welds '
              'rejected by RT/UT ÷ welds examined by RT/UT (including the '
              'result before a repair).'),
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_tr('Kolejność:', 'Order:'),
                style: const TextStyle(color: kTextSec, fontSize: 12.5)),
            _chip<bool>(false, _sortByRepairs, _tr('najwięcej DI', 'most DI'),
                (x) => setState(() => _sortByRepairs = x),
                key: const ValueKey('progress-sort-di')),
            _chip<bool>(
                true,
                _sortByRepairs,
                _tr('najwięcej napraw', 'most repairs'),
                (x) => setState(() => _sortByRepairs = x),
                key: const ValueKey('progress-sort-repairs')),
          ],
        ),
        const SizedBox(height: 8),
        for (final w in list) _WelderRow(w: w, en: en),
        _CrewRow(s: s, en: en),
      ],
    );
  }

  // ─── Prognoza ──────────────────────────────────────────────────────────

  Widget _forecastSection(_View v, bool en) {
    final s = _scope;
    final f = v.forecast;
    final key = ProgressScope.keyFor(_filter.project, _filter.testPackage);
    final who = _filter.describeScope(en: en);
    return QuoteSection(
      title: _tr('Prognoza', 'Forecast'),
      subtitle: _tr(
          'Zakres pracy dla: $who. % wykonania liczy się ze wszystkich spoin '
              'tego projektu i pakietu (i miejsca), niezależnie od okresu u góry.',
          'Scope of work for: $who. % done counts every weld of this project '
              'and package (and location), whatever the period above.'),
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_tr('Zakres w:', 'Scope in:'),
                style: const TextStyle(color: kTextSec, fontSize: 12.5)),
            for (final u in ScopeUnit.values)
              _chip<ScopeUnit>(
                u,
                s.unit,
                u == ScopeUnit.di ? 'DI' : _tr('spoinach', 'welds'),
                (x) {
                  if (x == s.unit) return;
                  // Inna jednostka = inna liczba; stara nic tu nie znaczy.
                  _saveScope(s.copyWith(unit: x, total: null));
                },
                key: ValueKey('progress-unit-${u.name}'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        QuoteNumberField(
          key: ValueKey('progress-scope-total-$key-${s.unit.name}'),
          label: _tr('Zakres do wykonania', 'Scope to do'),
          unit: s.unit == ScopeUnit.di ? 'DI' : _tr('spoin', 'welds'),
          value: s.total,
          decimal: s.unit == ScopeUnit.di,
          decimals: 1,
          helper: _tr(
              'Cały pakiet / projekt — np. suma DI z listy spoin albo z ISO.',
              'The whole package / project — e.g. total DI from the weld list or the ISOs.'),
          validate: (x) => x != null && x <= 0
              ? _tr('Wpisz liczbę większą od zera', 'Enter a number above zero')
              : null,
          onChanged: (x) =>
              _saveScope(s.copyWith(total: x != null && x > 0 ? x : null)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('progress-due'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget)),
                onPressed: () => unawaited(_pickDue()),
                icon: const Icon(Icons.event_outlined),
                label: Text(s.due.isEmpty
                    ? _tr('Termin: ustaw (opcjonalnie)',
                        'Deadline: set (optional)')
                    : '${_tr('Termin', 'Deadline')}: ${dayLabel(s.dueDate!, en: en)}'),
              ),
            ),
            if (s.due.isNotEmpty)
              IconButton(
                key: const ValueKey('progress-due-clear'),
                tooltip: _tr('Usuń termin', 'Clear the deadline'),
                icon: const Icon(Icons.clear),
                onPressed: () => _saveScope(s.copyWith(due: '')),
              ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('progress-saturdays'),
          contentPadding: EdgeInsets.zero,
          title: Text(_tr('Pracujemy w soboty', 'We work on Saturdays')),
          subtitle: Text(
            _tr('Dni robocze: pn–sob. Bez świąt — wpisz termin z ich uwzględnieniem.',
                'Working days: Mon–Sat. No public holidays — allow for them in the deadline.'),
            style: const TextStyle(fontSize: 12, color: kTextMut),
          ),
          value: s.saturdays,
          onChanged: (x) => _saveScope(s.copyWith(saturdays: x)),
        ),
        if (f == null)
          Text(
            _tr(
                'Wpisz zakres, a pokażę % wykonania, datę końca przy obecnym '
                    'tempie i ile trzeba robić dziennie na termin.',
                'Enter the scope to see % done, the finish date at the current '
                    'pace and the daily output needed for the deadline.'),
            style: const TextStyle(fontSize: 12.5, color: kTextSec),
          )
        else
          _ForecastView(f: f, en: en),
      ],
    );
  }

  // ─── Raport ────────────────────────────────────────────────────────────

  Widget _reportSection(ProgressReport report, bool en) => QuoteSection(
        title: _tr('Raport dla szefa', 'Report for the boss'),
        subtitle: '${report.title(en: en)} · ${report.periodText(en: en)} · '
            '${_filter.describeScope(en: en)}',
        children: [
          OutlinedButton.icon(
            key: const ValueKey('progress-share-text'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: () => unawaited(_shareText(report)),
            icon: const Icon(Icons.sms_outlined),
            label: Text(_tr('Wyślij tekstem (SMS, WhatsApp)',
                'Send as text (SMS, WhatsApp)')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('progress-share-pdf'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _exporting ? null : () => unawaited(_sharePdf(report)),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_tr('Raport PDF', 'PDF report')),
          ),
          const SizedBox(height: 6),
          Text(
            _tr('Okres wybierasz u góry: „Dziś" = raport dzienny, „Ten tydzień" = tygodniowy.',
                'Pick the period at the top: "Today" = daily report, "This week" = weekly.'),
            style: const TextStyle(fontSize: 11.5, color: kTextMut),
          ),
        ],
      );
}

/// Kafelki po [columns] w wierszu; wysokość wiersza z treści (najwyższy
/// kafelek), nie ze sztywnych proporcji — na wąskim telefonie podpis
/// zawija się do dwóch linii i nie może się przepełnić.
class _TileRows extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  const _TileRows({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: 8));
        final k = i + c;
        cells.add(Expanded(
            child: k < children.length ? children[k] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(IntrinsicHeight(
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _WelderRow extends StatelessWidget {
  final WelderProgress w;
  final bool en;
  const _WelderRow({required this.w, required this.en});

  @override
  Widget build(BuildContext context) {
    final q = w.quality;
    final warn = q.toExamine > 0 || q.r2plus > 0;
    final name =
        w.isUnstamped ? context.tr(pl: 'bez stempla', en: 'no stamp') : w.stamp;
    final rate = q.repairRatePct;
    return Container(
      key: ValueKey('progress-welder-${w.stamp}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warn ? kWarn : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kText)),
              ),
              Text(
                progressDi(w.diShare, en: en, approx: w.diApprox),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kText,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              weldsCount(w.welds, en: en),
              if (w.sharedWelds > 0)
                '${sharedCount(w.sharedWelds, en: en)} · '
                    '${context.tr(pl: 'udział', en: 'share')} '
                    '${progressNum(w.weldsShare, en: en)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, color: kTextSec),
          ),
          Text(
            [
              repairsText(q, en: en),
              rate == null
                  ? (q.repairs > 0
                      ? context.tr(
                          pl:
                              'brak wyników RT/UT — naprawiane ${q.repairedWelds} z ${q.welds}',
                          en:
                              'no RT/UT results — repaired ${q.repairedWelds} of ${q.welds}')
                      : context.tr(
                          pl: 'odsetek napraw: brak wyników RT/UT',
                          en: 'repair rate: no RT/UT results'))
                  : '${context.tr(pl: 'odsetek napraw', en: 'repair rate')} '
                      '${repairRateText(q, en: en)}',
            ].join(' · '),
            style: TextStyle(
                fontSize: 12.5,
                color: rate != null && rate > 0 ? kText : kTextSec),
          ),
          if (q.toExamine > 0)
            Text(
              context.tr(
                  pl: 'Do dobadania (B31.3 §341.3.4): ${q.toExamine}',
                  en: 'To examine (B31.3 §341.3.4): ${q.toExamine}'),
              style: const TextStyle(fontSize: 12, color: kWarn),
            ),
        ],
      ),
    );
  }
}

class _CrewRow extends StatelessWidget {
  final ProgressSummary s;
  final bool en;
  const _CrewRow({required this.s, required this.en});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('progress-crew'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kTextMut),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                pl: 'Brygada razem (każda spoina raz)',
                en: 'Crew total (each weld once)'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kText),
          ),
          Text(
            doneLine(s, en: en),
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: kText,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          Text(
            '${repairsText(s.crew, en: en)} · '
            '${context.tr(pl: 'odsetek napraw', en: 'repair rate')} '
            '${repairRateText(s.crew, en: en)}',
            style: const TextStyle(fontSize: 12.5, color: kTextSec),
          ),
          if (s.crew.toExamine > 0)
            Text(
              context.tr(
                  pl: 'Do dobadania (B31.3 §341.3.4): ${s.crew.toExamine}',
                  en: 'To examine (B31.3 §341.3.4): ${s.crew.toExamine}'),
              style: const TextStyle(fontSize: 12, color: kWarn),
            ),
        ],
      ),
    );
  }
}

class _ForecastView extends StatelessWidget {
  final ProgressForecast f;
  final bool en;
  const _ForecastView({required this.f, required this.en});

  @override
  Widget build(BuildContext context) {
    final verdictColor = f.isDone
        ? kPass
        : (f.dueMissed
            ? kFail
            : switch (f.onTrack) {
                true => kPass,
                false => kWarn,
                null => kTextSec,
              });
    final lines = forecastLines(f, en: en);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              progressPct(f.pct, en: en),
              key: const ValueKey('progress-forecast-pct'),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kText,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${scopeAmount(f.done, f.unit, en: en)} / '
                '${scopeAmount(f.total, f.unit, en: en)}',
                style: const TextStyle(fontSize: 13, color: kTextSec),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (f.pct / 100).clamp(0.0, 1.0),
            minHeight: 10,
            color: kPass,
            backgroundColor: kBorder,
          ),
        ),
        const SizedBox(height: 10),
        _TileRows(
          columns: 2,
          children: [
            FactTile(
              key: const ValueKey('progress-forecast-finish'),
              icon: Icons.flag_outlined,
              label: context.tr(
                  pl: 'Koniec przy obecnym tempie',
                  en: 'Finish at the current pace'),
              value: f.isDone
                  ? context.tr(pl: 'gotowe', en: 'done')
                  : (f.finish == null ? '—' : isoDate(f.finish!)),
              sub: f.finish == null
                  ? (f.isDone
                      ? null
                      : context.tr(pl: 'brak tempa', en: 'no pace yet'))
                  : '${weekdayShort(f.finish!, en: en)} · '
                      '${f.workingDaysNeeded} ${context.tr(pl: 'dni rob.', en: 'w. days')}',
            ),
            FactTile(
              key: const ValueKey('progress-forecast-required'),
              icon: Icons.trending_up,
              label: context.tr(
                  pl: 'Na termin trzeba / dzień', en: 'Needed per day'),
              value: f.requiredPerDay == null
                  ? '—'
                  : scopeAmount(f.requiredPerDay!, f.unit, en: en),
              sub: f.due == null
                  ? context.tr(pl: 'termin nieustawiony', en: 'no deadline')
                  : (f.dueMissed
                      ? context.tr(
                          pl: 'nie zostały dni robocze',
                          en: 'no working days left')
                      : '${context.tr(pl: 'do', en: 'until')} ${isoDate(f.due!)} · '
                          '${f.workingDaysToDue} ${context.tr(pl: 'dni rob.', en: 'w. days')}'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final l in lines.skip(1))
          Text(l,
              style: TextStyle(
                  fontSize: 12.5,
                  color: verdictColor,
                  fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          context.tr(
              pl: 'Dni liczone od ${dayLabel(f.firstDay, en: en)} (dziś, jeśli '
                  'nie ma jeszcze dzisiejszych wpisów, inaczej od jutra).',
              en: 'Days counted from ${dayLabel(f.firstDay, en: en)} (today if '
                  'nothing is logged yet today, otherwise from tomorrow).'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut),
        ),
      ],
    );
  }
}
