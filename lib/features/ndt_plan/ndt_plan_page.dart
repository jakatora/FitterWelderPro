// Plan badań NDT — z dziennika spoin: ile spoin trzeba zbadać (losowy % na
// spawacza i linię), które zlecić, ile badań dodatkowych B31.3 §341.3.4 i
// czy linia jest gotowa do próby ciśnieniowej. Ekran tylko CZYTA dziennik;
// reguły trzyma w SharedPreferences, osobno dla każdego projektu.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../assistant/core/tool_bridge.dart';
import '../../database/weld_journal_dao.dart';
import '../../domain/ndt/ndt_plan.dart';
import '../../domain/progress/progress_report.dart' show weldsCount;
import '../../domain/weld_journal/weld_defaults.dart' show loadLastWeldProject;
import '../../domain/weld_journal/weld_entry.dart';
import '../../domain/weld_journal/weld_ndt.dart';
import '../../i18n/app_language.dart';
import '../../screens/weld_journal_screen.dart' show WeldJournalScreen;
import '../../services/ndt_plan_export.dart';
import '../../services/owned_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/help_button.dart';
import '../../widgets/local_record_scope.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart';
import 'ndt_plan_help.dart';
import 'ndt_plan_store.dart';

/// Źródło spoin (domyślnie dziennik spoin) — wstrzykiwane w testach.
typedef NdtWeldSource = Future<List<WeldEntry>> Function();

/// Cel RT/UT % z ustawień projektów dziennika: klucz projektu → %.
typedef NdtTargetSource = Future<Map<String, double?>> Function();

Future<void> _defaultShareText(String text, String subject) =>
    NdtPlanExport.shareText(text, subject);

class NdtPlanPage extends StatelessWidget {
  const NdtPlanPage({
    super.key,
    this.clock,
    this.loadWelds,
    this.loadTargets,
    this.loadLastProject = loadLastWeldProject,
    this.store,
    this.shareText = _defaultShareText,
    this.sharePdf,
  });

  /// Zegar — w testach stały dzień.
  final DateTime Function()? clock;
  final NdtWeldSource? loadWelds;
  final NdtTargetSource? loadTargets;

  /// Ostatni projekt z dziennika (domyślny wybór).
  final Future<String> Function() loadLastProject;
  final NdtPlanStore? store;
  final NdtShareText shareText;
  final NdtSharePdf? sharePdf;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _NdtPlanBody(
          session: session,
          clock: clock,
          loadWelds: loadWelds ??
              () => WeldJournalDao(owner: session.captureOwner).listAll(),
          loadTargets: loadTargets ??
              () async {
                final all =
                    await WeldJournalSettingsDao(owner: session.captureOwner)
                        .listAll();
                return {
                  for (final e in all.entries)
                    e.key: e.value.volumetricTargetPct
                };
              },
          loadLastProject: loadLastProject,
          store: store ??
              NdtPlanStore(
                prefs: () => OwnedPrefs.instance(session.captureOwner),
              ),
          shareText: shareText,
          sharePdf: sharePdf ??
              (report, english) => NdtPlanExport.sharePdf(report, english,
                  mayShare: () => session.isCurrent),
        ),
      );
}

class _NdtPlanBody extends StatefulWidget {
  const _NdtPlanBody({
    required this.session,
    required this.clock,
    required this.loadWelds,
    required this.loadTargets,
    required this.loadLastProject,
    required this.store,
    required this.shareText,
    required this.sharePdf,
  });
  final LocalRecordSession session;
  final DateTime Function()? clock;
  final NdtWeldSource loadWelds;
  final NdtTargetSource loadTargets;
  final Future<String> Function() loadLastProject;
  final NdtPlanStore store;
  final NdtShareText shareText;
  final NdtSharePdf sharePdf;

  @override
  State<_NdtPlanBody> createState() => _NdtPlanPageState();
}

class _NdtPlanPageState extends State<_NdtPlanBody>
    with ToolHandleHost<_NdtPlanBody>
    implements InputToolHandle {
  @override
  String get toolId => 'ndt_plan';
  @override
  Set<String> get supportedFields => const {'project'};
  @override
  Map<String, Object?> get inputFields =>
      Map.unmodifiable({'project': _project});

  /// Asystent wybiera projekt z dziennika — reguły wczytują się jak przy
  /// wyborze z listy. Gotowość dopiero po pierwszym odczycie dziennika.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final p = fields['project'];
    final match = p is String
        ? _projects.where((x) => x.toLowerCase() == p.toLowerCase()).firstOrNull
        : null;
    if (!mounted ||
        !widget.session.isCurrent ||
        fields.keys.any((k) => !supportedFields.contains(k)) ||
        match == null) {
      return fields.keys.toSet();
    }
    await _changeProject(match);
    return {};
  }

  /// Nieusunięte wpisy dziennika.
  List<WeldEntry> _all = const [];
  List<String> _projects = const [];
  String _project = '';
  NdtRuleSet _set = const NdtRuleSet();
  bool _rulesIntact = true;
  int _rulesDropped = 0;

  /// Odczyt reguł się nie udał — do udanego ponownego odczytu nic nie
  /// zapisujemy (nie wiadomo, co jest na telefonie).
  bool _readFailed = false;

  /// Reguły projektu właśnie się wczytują (zmiana projektu) — edycja
  /// poczeka, żeby stare reguły nie trafiły do nowego projektu.
  bool _rulesLoading = false;

  /// Zmiany reguł wpływają na gotowość dopiero po potwierdzonym zapisie.
  bool _rulesSaving = false;
  bool _rulesSaveFailed = false;
  int _saveRevision = 0;

  /// Szkic pozostaje przy swoim projekcie, gdy zapis skończy się błędem po
  /// przejściu na inny projekt. Numer chroni nowszą edycję przed starszą.
  final Map<String, ({NdtRuleSet set, int revision})> _drafts = {};
  final Set<String> _failedDrafts = {};

  /// Zapisy po kolei: późniejsza zmiana nigdy nie zostanie nadpisana
  /// wcześniejszą, która skończyła się później.
  Future<void> _saveChain = Future<void>.value();
  Map<String, double?> _targets = const {};
  int _round = 0;
  int _ruleSeq = 0;
  bool _loading = true;
  bool _failed = false;
  bool _exporting = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true).whenComplete(() {
      if (mounted && widget.session.isCurrent) markReady();
    }));
  }

  String? _match(String project, List<String> projects) {
    final t = project.trim().toLowerCase();
    for (final p in projects) {
      if (p.toLowerCase() == t) return p;
    }
    return null;
  }

  Future<void> _load({bool first = false}) async {
    var failed = false;
    var all = const <WeldEntry>[];
    try {
      all = (await widget.loadWelds()).where((e) => !e.isDeleted).toList();
    } catch (e) {
      debugPrint('[ndt_plan] journal load failed: $e');
      failed = true;
    }
    var targets = _targets;
    try {
      targets = await widget.loadTargets();
    } catch (e) {
      debugPrint('[ndt_plan] project settings failed: $e');
    }
    final projects = ndtProjects(all);
    var project = _match(_project, projects);
    if (first || project == null) {
      var last = '';
      if (first) {
        try {
          last = await widget.loadLastProject();
        } catch (e) {
          debugPrint('[ndt_plan] last project failed: $e');
        }
      }
      project =
          _match(last, projects) ?? (projects.isEmpty ? '' : projects.first);
    }
    final reloadRules =
        first || project.toLowerCase() != _project.toLowerCase();
    final rules = reloadRules ? await widget.store.load(project) : null;
    if (!mounted || !widget.session.isCurrent) return;
    setState(() {
      _all = all;
      _failed = failed;
      _targets = targets;
      _projects = projects;
      _project = project!;
      if (rules != null) _applyLoad(rules);
      _loading = false;
    });
  }

  void _applyLoad(NdtRuleSetDecode d) {
    _saveRevision++;
    final projectKey = NdtPlanStore.projectKey(_project);
    final draft = _drafts[projectKey];
    _set = draft?.set ?? d.set;
    _rulesIntact = d.intact;
    _rulesDropped = d.dropped;
    _readFailed = d.readFailed;
    _rulesLoading = false;
    _rulesSaveFailed =
        !d.readFailed && draft != null && _failedDrafts.contains(projectKey);
    _rulesSaving = !d.readFailed && draft != null && !_rulesSaveFailed;
    _round = 0;
  }

  Future<void> _changeProject(String p) async {
    if (!widget.session.isCurrent) return;
    if (p.toLowerCase() == _project.toLowerCase()) return;
    setState(() {
      _project = p;
      _rulesLoading = true;
    });
    // Powrót do projektu musi zobaczyć jego ostatni zapis, także gdy zmiana
    // projektu nastąpiła przed zakończeniem poprzedniej operacji.
    await _saveChain;
    if (!mounted || !widget.session.isCurrent || _project != p) return;
    final rules = await widget.store.load(p);
    if (!mounted || !widget.session.isCurrent || _project != p) return;
    setState(() => _applyLoad(rules));
  }

  /// Ponowny odczyt reguł bieżącego projektu (po błędzie odczytu).
  Future<void> _retryRules() async {
    if (!widget.session.isCurrent) return;
    final p = _project;
    setState(() => _rulesLoading = true);
    final rules = await widget.store.load(p);
    if (!mounted || !widget.session.isCurrent || _project != p) return;
    setState(() => _applyLoad(rules));
    if (rules.readFailed) {
      _snack(_tr('Nadal nie udało się odczytać reguł.',
          'Still could not read the rules.'));
    }
  }

  /// Komunikat od razu — bez kolejki za wcześniejszym „Cofnij".
  void _snack(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  bool get _canEdit => !_readFailed && !_rulesLoading;

  void _setRules(NdtRuleSet s) {
    if (!widget.session.isCurrent) return;
    if (!_canEdit) {
      _snack(_tr('Najpierw trzeba odczytać zapisane reguły.',
          'The saved rules have to be read first.'));
      return;
    }
    final project = _project;
    final projectKey = NdtPlanStore.projectKey(project);
    final revision = ++_saveRevision;
    _drafts[projectKey] = (set: s, revision: revision);
    _failedDrafts.remove(projectKey);
    setState(() {
      _set = s;
      _rulesSaving = true;
      _rulesSaveFailed = false;
    });
    _saveChain = _saveChain.then((_) async {
      try {
        await widget.store.save(project, s);
        if (_drafts[projectKey]?.revision == revision) {
          _drafts.remove(projectKey);
          _failedDrafts.remove(projectKey);
        }
        if (mounted &&
            widget.session.isCurrent &&
            project == _project &&
            revision == _saveRevision) {
          setState(() {
            _rulesIntact = true;
            _rulesDropped = 0;
            _rulesSaving = false;
            _rulesSaveFailed = false;
          });
        }
      } catch (e) {
        debugPrint('[ndt_plan] save rules failed: $e');
        if (_drafts[projectKey]?.revision == revision) {
          _failedDrafts.add(projectKey);
        }
        if (mounted && widget.session.isCurrent) {
          if (project == _project && revision == _saveRevision) {
            setState(() {
              _rulesSaving = false;
              _rulesSaveFailed = true;
            });
            _snack(_tr('Nie udało się zapisać reguł na telefonie.',
                'Could not save the rules on the phone.'));
          } else if (_drafts[projectKey]?.revision == revision) {
            _snack(_tr(
                'Nie udało się zapisać reguł projektu $project. Wróć do '
                    'projektu, aby ponowić zapis.',
                'Could not save rules for project $project. Return to the '
                    'project to retry.'));
          }
        }
      }
    });
  }

  void _applyPreset(String preset) {
    final before = _set;
    if (!_canEdit) return _setRules(before);
    if (preset == NdtPreset.custom) {
      _setRules(NdtRuleSet(rules: before.rules));
      return;
    }
    final next = NdtRuleSet.fromPreset(preset);
    if (next == before) return;
    _setRules(next);
    if (before.rules.isNotEmpty) {
      _undoSnack(before, _tr('Zastosowano preset.', 'Preset applied.'));
    }
  }

  void _undoSnack(NdtRuleSet before, String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: _tr('Cofnij', 'Undo'),
          onPressed: () {
            if (mounted && widget.session.isCurrent) _setRules(before);
          },
        ),
      ));
  }

  String _newRuleId() {
    final used = {for (final r in _set.rules) r.id};
    String id;
    do {
      id = 'r${++_ruleSeq}';
    } while (used.contains(id));
    return id;
  }

  Future<void> _editRule(NdtRule? rule) async {
    if (!widget.session.isCurrent) return;
    final initial = rule ??
        NdtRule(
          id: _newRuleId(),
          method: NdtMethod.rt,
          bp: 1000,
          joints: const [WeldJointType.butt],
        );
    final edited = await showModalBottomSheet<NdtRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: kCard,
      builder: (_) => LocalRecordScope(
        restartOnAccountChange: false,
        originSession: widget.session,
        builder: (_, __) => _RuleEditor(rule: initial, isNew: rule == null),
      ),
    );
    if (edited == null || !mounted || !widget.session.isCurrent) return;
    final rules = [..._set.rules];
    final i = rules.indexWhere((r) => r.id == edited.id);
    if (i < 0) {
      rules.add(edited);
    } else {
      if (rules[i] == edited) return;
      rules[i] = edited;
    }
    _setRules(NdtRuleSet(rules: rules));
  }

  void _deleteRule(NdtRule rule) {
    final before = _set;
    if (!_canEdit) return _setRules(before);
    _setRules(NdtRuleSet(rules: [
      for (final r in before.rules)
        if (r.id != rule.id) r
    ]));
    _undoSnack(before, _tr('Usunięto regułę.', 'Rule deleted.'));
  }

  Future<void> _openJournal() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WeldJournalScreen()));
    if (!mounted || !widget.session.isCurrent) return;
    await _load();
  }

  NdtPlan _plan() => computeNdtPlan(
        _all,
        rules: _set.rules,
        rulesIntact: _rulesIntact &&
            !_rulesLoading &&
            !_rulesSaving &&
            !_rulesSaveFailed,
        project: _project,
        round: _round,
      );

  NdtOrderReport _report(NdtPlan plan) => NdtOrderReport(
        project: _project,
        plan: plan,
        generatedAt: _now,
      );

  Future<void> _shareText(NdtOrderReport r) async {
    if (!widget.session.isCurrent) return;
    final en = context.language == AppLanguage.en;
    final text = buildNdtOrderText(r, en: en);
    final copied = _tr('Skopiowano zlecenie.', 'Order copied.');
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || !widget.session.isCurrent) return;
      messenger.showSnackBar(SnackBar(content: Text(copied)));
      return;
    }
    try {
      await widget.shareText(text, r.subject(en: en));
    } catch (e) {
      debugPrint('[ndt_plan] share text failed: $e');
      if (!mounted || !widget.session.isCurrent) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || !widget.session.isCurrent) return;
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    }
  }

  Future<void> _sharePdf(NdtOrderReport r) async {
    if (_exporting || !widget.session.isCurrent) return;
    final en = context.language == AppLanguage.en;
    final failed =
        _tr('Nie udało się przygotować PDF.', 'Could not prepare the PDF.');
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      await widget.sharePdf(r, en);
    } catch (e) {
      debugPrint('[ndt_plan] pdf failed: $e');
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
        title: Text(_tr('Plan badań NDT', 'NDT plan')),
        actions: [
          const HelpButton(help: kHelpNdtPlan),
          IconButton(
            key: const ValueKey('ndt-journal'),
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
              : (_all.isEmpty ? _empty() : _content(_plan(), en))),
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
            key: const ValueKey('ndt-retry'),
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
        key: const ValueKey('ndt-empty'),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          const Icon(Icons.rule_outlined, size: 56, color: kTextMut),
          const SizedBox(height: 12),
          Text(
            _tr('Dziennik spoin jest pusty', 'The weld journal is empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
                'Plan badań liczy się sam ze spoin wpisanych w dzienniku: ile '
                    'trzeba zbadać na spawacza i linię, które spoiny zlecić i '
                    'czy linia jest gotowa do próby. Wpisz spoiny i wyniki '
                    'badań w dzienniku — tu niczego nie przepisujesz.',
                'The plan is worked out from the welds in the journal: how many '
                    'to examine per welder and line, which welds to order and '
                    'whether a line is ready for the test. Log the welds and '
                    'the results in the journal — nothing is typed twice.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSec, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('ndt-open-journal'),
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

  Widget _content(NdtPlan plan, bool en) {
    final report = _report(plan);
    return ListView(
      key: const ValueKey('ndt-list'),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _scopeSection(en),
        _rulesSection(en),
        _linesSection(plan, en),
        _orderSection(plan, report, en),
        if (plan.issues.isNotEmpty || plan.shortfalls.isNotEmpty)
          _issuesSection(plan, en),
        Text(
          ndtDefinitions(en: en).map((d) => '• $d').join('\n'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
        ),
      ],
    );
  }

  // ─── Projekt ───────────────────────────────────────────────────────────

  Widget _scopeSection(bool en) {
    final target = _targets[NdtPlanStore.projectKey(_project)];
    final bp = ndtBpFromPct(target);
    return QuoteSection(
      title: _tr('Projekt', 'Project'),
      children: [
        if (_projects.length > 1)
          KeyedSubtree(
            key: const ValueKey('ndt-project'),
            child: DropdownButtonFormField<String>(
              key: ValueKey('ndt-project-$_project'),
              initialValue: _project,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr('Projekt', 'Project'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final p in _projects)
                  DropdownMenuItem(
                    value: p,
                    child: Text(ndtProjectName(p, en: en),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (p) {
                if (p != null) unawaited(_changeProject(p));
              },
            ),
          )
        else
          Text(
            ndtProjectName(_project, en: en),
            key: const ValueKey('ndt-project-name'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kText),
          ),
        const SizedBox(height: 6),
        Text(
          _tr('Reguły zapamiętane osobno dla każdego projektu.',
              'Rules are kept separately for each project.'),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
        if (bp != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _tr(
                  'W ustawieniach projektu w dzienniku: cel RT/UT '
                      '${ndtPctText(bp, en: false)} — to tylko podgląd, plan '
                      'liczy się z reguł poniżej.',
                  'In the journal\'s project settings: RT/UT target '
                      '${ndtPctText(bp, en: true)} — for reference only, the '
                      'plan uses the rules below.'),
              key: const ValueKey('ndt-target'),
              style: const TextStyle(fontSize: 12, color: kTextSec),
            ),
          ),
      ],
    );
  }

  // ─── Wymagania ─────────────────────────────────────────────────────────

  Widget _rulesSection(bool en) {
    final s = _set;
    final title = _tr('Wymagania', 'Requirements');
    final subtitle = _tr(
        'Ze specyfikacji projektu. Wymagane = spoiny × %, zawsze w górę.',
        'From the project specification. Required = welds × %, always '
            'rounded up.');
    if (_rulesLoading) {
      return QuoteSection(
        key: const ValueKey('ndt-rules'),
        title: title,
        subtitle: subtitle,
        children: [
          QuoteNotice(
            key: const ValueKey('ndt-rules-loading'),
            text: _tr('Ładowanie reguł wybranego projektu…',
                'Loading rules for the selected project…'),
          ),
        ],
      );
    }
    return QuoteSection(
      key: const ValueKey('ndt-rules'),
      title: title,
      subtitle: subtitle,
      children: [
        if (_rulesSaving)
          QuoteNotice(
            key: const ValueKey('ndt-rules-saving'),
            text: _tr('Zapisywanie reguł. Gotowość linii czeka na zapis.',
                'Saving rules. Line readiness waits for confirmation.'),
          ),
        if (_rulesSaveFailed) ...[
          QuoteNotice(
            key: const ValueKey('ndt-rules-save-failed'),
            color: kFail,
            icon: Icons.save_outlined,
            text: _tr(
                'Nie udało się zapisać reguł. Żadna linia nie jest gotowa '
                    'według niezapisanych zmian. Ponów zapis przed użyciem planu.',
                'Rules could not be saved. No line is ready under unsaved '
                    'changes. Retry saving before using the plan.'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('ndt-rules-save-retry'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: () => _setRules(_set),
            icon: const Icon(Icons.refresh),
            label: Text(_tr('Ponów zapis reguł', 'Retry saving rules')),
          ),
          const SizedBox(height: 12),
        ],
        if (_readFailed) ...[
          QuoteNotice(
            key: const ValueKey('ndt-rules-read-failed'),
            color: kFail,
            icon: Icons.report_problem_outlined,
            text: _tr(
                'Nie udało się odczytać zapisanych reguł tego projektu. Nic '
                    'nie zapiszę, dopóki odczyt się nie uda — żeby nie nadpisać '
                    'reguł, których nie widać. Żadna linia nie jest gotowa.',
                'Could not read the saved rules of this project. Nothing is '
                    'saved until the read succeeds — so rules you cannot see '
                    'are not overwritten. No line is ready.'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('ndt-rules-retry'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _rulesLoading ? null : () => unawaited(_retryRules()),
            icon: const Icon(Icons.refresh),
            label:
                Text(_tr('Odczytaj reguły ponownie', 'Read the rules again')),
          ),
          const SizedBox(height: 12),
        ] else if (!_rulesIntact) ...[
          QuoteNotice(
            key: const ValueKey('ndt-rules-damaged'),
            color: kFail,
            icon: Icons.report_problem_outlined,
            text: _tr(
                'Zapisane reguły były uszkodzone'
                    '${_rulesDropped > 0 ? ' (pominięto: $_rulesDropped)' : ''}. '
                    'Do czasu potwierdzenia żadna linia nie jest gotowa. '
                    'Surowy zapis trafi pod '
                    '„${NdtPlanStore.corruptKeyFor(_project)}".',
                'The saved rules were damaged'
                    '${_rulesDropped > 0 ? ' ($_rulesDropped skipped)' : ''}. '
                    'Until you confirm them no line is ready. The raw record '
                    'is kept under "${NdtPlanStore.corruptKeyFor(_project)}".'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('ndt-rules-confirm'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: () => _setRules(_set),
            icon: const Icon(Icons.done_all),
            label: Text(_tr('Sprawdziłem — potwierdź reguły',
                'Checked — confirm the rules')),
          ),
          const SizedBox(height: 12),
        ],
        Text(_tr('Preset', 'Preset'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in NdtPreset.values)
              ChoiceChip(
                key: ValueKey('ndt-preset-$p'),
                label: Text(ndtPresetChip(p, en: en)),
                selected: s.preset == p &&
                    (s.rules.isNotEmpty || p == NdtPreset.custom),
                onSelected: _canEdit ? (_) => _applyPreset(p) : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          ndtPresetLabel(s.preset, en: en),
          key: const ValueKey('ndt-preset-name'),
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: kText),
        ),
        const SizedBox(height: 2),
        Text(
          ndtPresetNote(s.preset, en: en),
          key: const ValueKey('ndt-preset-note'),
          style: const TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (s.rules.isEmpty)
          QuoteNotice(
            key: const ValueKey('ndt-no-rules'),
            text: _tr(
                'Brak reguł — wybierz preset albo dodaj regułę. Bez reguł żadna '
                    'linia nie jest gotowa.',
                'No rules — pick a preset or add a rule. Without rules no line '
                    'is ready.'),
          ),
        for (final r in s.rules) _ruleCard(r, en),
        OutlinedButton.icon(
          key: const ValueKey('ndt-rule-add'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: _canEdit ? () => unawaited(_editRule(null)) : null,
          icon: const Icon(Icons.add),
          label: Text(_tr('Dodaj regułę', 'Add a rule')),
        ),
      ],
    );
  }

  Widget _ruleCard(NdtRule r, bool en) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          key: ValueKey('ndt-rule-${r.id}'),
          color: kBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: kBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      ndtRuleText(r, en: en),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: kText,
                          height: 1.35),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('ndt-rule-edit-${r.id}'),
                  tooltip: _tr('Zmień regułę', 'Edit the rule'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _canEdit ? () => unawaited(_editRule(r)) : null,
                ),
                IconButton(
                  key: ValueKey('ndt-rule-delete-${r.id}'),
                  tooltip: _tr('Usuń regułę', 'Delete the rule'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _canEdit ? () => _deleteRule(r) : null,
                ),
              ],
            ),
          ),
        ),
      );

  // ─── Gotowość linii ────────────────────────────────────────────────────

  Widget _linesSection(NdtPlan plan, bool en) => QuoteSection(
        key: const ValueKey('ndt-lines'),
        title: _tr('Gotowość do próby ciśnieniowej', 'Pressure test readiness'),
        subtitle: _tr(
            'Linia = pole „Rura / linia" spoiny, a bez niego numer ISO.',
            'Line = the weld\'s "Pipe / line" field, otherwise the ISO number.'),
        children: [
          Text(
            _tr('Gotowe: ${plan.readyLines} z ${plan.lines.length} linii',
                'Ready: ${plan.readyLines} of ${plan.lines.length} lines'),
            key: const ValueKey('ndt-ready-count'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color:
                  plan.lines.isNotEmpty && plan.readyLines == plan.lines.length
                      ? kPass
                      : kText,
            ),
          ),
          const SizedBox(height: 10),
          if (plan.lines.isEmpty)
            Text(
              _tr('Brak spoin w tym projekcie.', 'No welds in this project.'),
              style: const TextStyle(color: kTextSec),
            ),
          for (final l in plan.lines) _LineCard(line: l, en: en),
        ],
      );

  // ─── Zlecenie ──────────────────────────────────────────────────────────

  Widget _orderSection(NdtPlan plan, NdtOrderReport report, bool en) {
    final toOrder = plan.toOrder;
    final ordered = plan.ordered;
    final prog = plan.progressiveGroups;
    const itemStyle = TextStyle(fontSize: 13, color: kText, height: 1.35);
    const subStyle = TextStyle(fontSize: 11.5, color: kTextMut);
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: kText)),
        );
    return QuoteSection(
      key: const ValueKey('ndt-order'),
      title: _tr('Zlecenie badań', 'Examination order'),
      subtitle: _tr(
          'Propozycja jest powtarzalna (te same dane = ta sama lista) i woli '
              'spoiny jeszcze nie badane innymi metodami.',
          'The proposal is repeatable (same data = same list) and prefers '
              'welds not examined by other methods yet.'),
      children: [
        if (toOrder.isEmpty)
          Text(
            _tr('Nic nowego do zlecenia.', 'Nothing new to order.'),
            key: const ValueKey('ndt-order-none'),
            style: const TextStyle(fontSize: 13.5, color: kTextSec),
          ),
        for (final m in NdtMethod.values)
          if (toOrder[m] != null) ...[
            head('${m.code} — ${_tr('do zlecenia', 'to order')}: '
                '${weldsCount(toOrder[m]!.length, en: en)}'),
            for (final i in toOrder[m]!)
              Padding(
                key: ValueKey('ndt-order-${m.code}-${i.weld.id}'),
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${ndtWeldLabel(i.weld, en: en)}', style: itemStyle),
                    Text('   ${ndtOrderReason(i, en: en)}', style: subStyle),
                  ],
                ),
              ),
          ],
        if (ordered.isNotEmpty) ...[
          head(_tr('Zlecone wcześniej, bez wyniku',
              'Ordered earlier, no result yet')),
          for (final m in NdtMethod.values)
            for (final i in ordered[m] ?? const <NdtOrderItem>[])
              Padding(
                key: ValueKey('ndt-ordered-${m.code}-${i.weld.id}'),
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${m.code}: ${ndtWeldLabel(i.weld, en: en)}',
                        style: itemStyle),
                    Text('   ${ndtOrderedReason(i, en: en)}', style: subStyle),
                  ],
                ),
              ),
        ],
        if (prog.isNotEmpty) ...[
          head(_tr('Badania dodatkowe (B31.3 §341.3.4)',
              'Additional examinations (B31.3 §341.3.4)')),
          Text(
            _tr(
                'Wybiera inspektor: ten sam spawacz, ta sama metoda. Oznacz je w '
                    'dzienniku jako „dod.".',
                'Picked by the inspector: same welder, same method. Mark them '
                    'in the journal as "add.".'),
            style: subStyle,
          ),
          for (final g in prog)
            Text(
              '• ${ndtGroupTitle(g, en: en)}: ${g.progressive}',
              key: ValueKey('ndt-progressive-${g.key}'),
              style: const TextStyle(fontSize: 13, color: kWarn),
            ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('ndt-reroll'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: toOrder.isEmpty ? null : () => setState(() => _round++),
          icon: const Icon(Icons.casino_outlined),
          label: Text(_round == 0
              ? _tr('Losuj ponownie', 'Draw again')
              : _tr('Losuj ponownie (runda ${_round + 1})',
                  'Draw again (round ${_round + 1})')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('ndt-share-text'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed:
              _readFailed || _rulesLoading || _rulesSaving || _rulesSaveFailed
                  ? null
                  : () => unawaited(_shareText(report)),
          icon: const Icon(Icons.sms_outlined),
          label: Text(_tr('Wyślij zlecenie tekstem', 'Send the order as text')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('ndt-share-pdf'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: _exporting ||
                  _readFailed ||
                  _rulesLoading ||
                  _rulesSaving ||
                  _rulesSaveFailed
              ? null
              : () => unawaited(_sharePdf(report)),
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_tr('Zlecenie PDF', 'Order as PDF')),
        ),
      ],
    );
  }

  // ─── Brak danych ───────────────────────────────────────────────────────

  Widget _issuesSection(NdtPlan plan, bool en) {
    const shown = 40;
    final list = plan.issues;
    return QuoteSection(
      key: const ValueKey('ndt-issues'),
      title: _tr('Nieprzypisane i brak danych', 'Unassigned and missing data'),
      subtitle: _tr(
          'Te spoiny blokują gotowość swojej linii — uzupełnij je w dzienniku.',
          'These welds block their line — fill them in the journal.'),
      children: [
        for (final g in plan.shortfalls)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• ${ndtShortfallText(g, en: en)}',
              key: ValueKey('ndt-shortfall-${g.key}'),
              style: const TextStyle(fontSize: 13, color: kWarn),
            ),
          ),
        for (final i in list.take(shown))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• ${ndtIssueLine(i, en: en)}',
              key: ValueKey('ndt-issue-${i.weld.id}'),
              style: const TextStyle(fontSize: 13, color: kText),
            ),
          ),
        if (list.length > shown)
          Text('… +${list.length - shown}',
              style: const TextStyle(fontSize: 12.5, color: kTextSec)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('ndt-fix-journal'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: _openJournal,
          icon: const Icon(Icons.edit_note),
          label: Text(
              _tr('Uzupełnij w dzienniku spoin', 'Fill in the weld journal')),
        ),
      ],
    );
  }
}

/// Karta linii: werdykt, liczby, co blokuje i grupy. Bez elementów
/// klikalnych — dekorowany Container jest tu bezpieczny.
class _LineCard extends StatelessWidget {
  final NdtLine line;
  final bool en;
  const _LineCard({required this.line, required this.en});

  @override
  Widget build(BuildContext context) {
    final l = line;
    final color = l.ready ? kPass : kWarn;
    const small = TextStyle(fontSize: 12.5, color: kTextSec, height: 1.35);
    return Container(
      key: ValueKey('ndt-line-${l.key}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ndtLineName(l.line, en: en),
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: kText),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(l.ready ? Icons.check_circle : Icons.error_outline,
                  size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ndtVerdictText(l, en: en),
                  key: ValueKey('ndt-verdict-${l.key}'),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(ndtLineNumbers(l, en: en),
              key: ValueKey('ndt-line-numbers-${l.key}'), style: small),
          for (final b in l.blockers.keys)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '• ${ndtBlockerText(b, l, en: en)}',
                key: ValueKey('ndt-blocker-${l.key}-${b.name}'),
                style: const TextStyle(fontSize: 12.5, color: kWarn),
              ),
            ),
          for (final (i, n) in ndtLineNotes(l, en: en).indexed)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                n,
                key: ValueKey('ndt-note-${l.key}-$i'),
                style: small,
              ),
            ),
          if (l.groups.isNotEmpty) ...[
            const Divider(color: kBorder, height: 18),
            for (final g in l.groups) _GroupRow(group: g, en: en),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final NdtGroup group;
  final bool en;
  const _GroupRow({required this.group, required this.en});

  @override
  Widget build(BuildContext context) {
    final g = group;
    final color = switch (g.status) {
      NdtGroupStatus.complete => kPass,
      NdtGroupStatus.missing => kWarn,
      NdtGroupStatus.awaiting => kWarn,
      NdtGroupStatus.repairsOpen => kFail,
      NdtGroupStatus.unassigned => kFail,
    };
    return Padding(
      key: ValueKey('ndt-group-${g.key}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ndtGroupTitle(g, en: en),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
          Text(ndtGroupNumbers(g, en: en),
              style: const TextStyle(fontSize: 12, color: kTextSec)),
          Text(
            ndtGroupStatusText(g, en: en),
            key: ValueKey('ndt-group-status-${g.key}'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Edycja reguły w arkuszu od dołu. Zwraca regułę dopiero, gdy jest poprawna
/// (procent 0–100, co najmniej jeden rodzaj spoiny).
class _RuleEditor extends StatefulWidget {
  final NdtRule rule;
  final bool isNew;
  const _RuleEditor({required this.rule, required this.isNew});

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late NdtMethod _method = widget.rule.method;
  late final TextEditingController _pct = TextEditingController(
      text: ndtPctText(widget.rule.bp, en: AppLanguageController.isEnglish)
          .replaceAll(' %', ''));
  late final TextEditingController _material =
      TextEditingController(text: widget.rule.material);
  late Set<String> _joints = {...widget.rule.joints};
  late bool _perWelder = widget.rule.perWelder;
  late bool _perLine = widget.rule.perLine;

  @override
  void dispose() {
    _pct.dispose();
    _material.dispose();
    super.dispose();
  }

  int? get _bp => ndtBpFromPct(parseDecimal(_pct.text));

  NdtRule? get _result {
    final bp = _bp;
    if (bp == null || _joints.isEmpty) return null;
    final r = widget.rule.copyWith(
      method: _method,
      bp: bp,
      joints: ndtJoints(_joints),
      material: _material.text.trim(),
      perWelder: _perWelder,
      perLine: _perLine,
    );
    return r.isValid ? r : null;
  }

  @override
  Widget build(BuildContext context) {
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    final pctError = _pct.text.trim().isEmpty
        ? tr('Wpisz procent', 'Enter a percentage')
        : (_bp == null ? tr('Od 0 do 100 %', 'From 0 to 100 %') : null);
    final result = _result;
    // Więcej niż dwa miejsca po przecinku — procent liczony w górę do
    // 0,01 % (nigdy w dół: „0,004" to nie 0 %).
    final typed = parseDecimal(_pct.text);
    final bp = _bp;
    final rounded =
        bp != null && typed != null && (typed * 100 - bp).abs() > 1e-6;
    final pctHelper = rounded
        ? tr('Liczone jako ${ndtPctText(bp, en: false)} (w górę do 0,01 %).',
            'Counted as ${ndtPctText(bp, en: true)} (rounded up to 0.01 %).')
        : tr('0–100; wymagane = spoiny × %, w górę.',
            '0–100; required = welds × %, rounded up.');
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('ndt-editor'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isNew
                  ? tr('Nowa reguła', 'New rule')
                  : tr('Zmień regułę', 'Edit the rule'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: kText),
            ),
            label(tr('Metoda', 'Method')),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in NdtMethod.values)
                  ChoiceChip(
                    key: ValueKey('ndt-edit-method-${m.code}'),
                    label: Text(m.code),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ndt-edit-pct'),
              controller: _pct,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Procent spoin do zbadania',
                    'Percentage of welds to examine'),
                suffixText: '%',
                helperText: pctHelper,
                helperMaxLines: 2,
                errorText: pctError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            label(tr('Rodzaj spoiny', 'Joint type')),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final j in WeldJointType.values)
                  FilterChip(
                    key: ValueKey('ndt-edit-joint-$j'),
                    label: Text(j),
                    selected: _joints.contains(j),
                    onSelected: (on) => setState(() {
                      _joints = {..._joints};
                      on ? _joints.add(j) : _joints.remove(j);
                    }),
                  ),
              ],
            ),
            if (_joints.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('Wybierz co najmniej jeden rodzaj.',
                      'Pick at least one type.'),
                  style: const TextStyle(fontSize: 12, color: kFail),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('BW doczołowa · FW pachwinowa · SW mufowa · BR odgałęzienie',
                    'BW butt · FW fillet · SW socket · BR branch'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ndt-edit-material'),
              controller: _material,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Materiał (opcjonalnie)', 'Material (optional)'),
                helperText: tr(
                    'Spoina musi go zawierać, np. „316" = 316L. Puste = każdy.',
                    'The weld must contain it, e.g. "316" = 316L. Empty = any.'),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              key: const ValueKey('ndt-edit-per-welder'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Każdy spawacz osobno', 'Each welder separately')),
              subtitle: Text(
                tr('Praca każdego spawacza w próbce (B31.3 §341.4.1).',
                    'Each welder\'s work in the sample (B31.3 §341.4.1).'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
              value: _perWelder,
              onChanged: (x) => setState(() => _perWelder = x),
            ),
            SwitchListTile(
              key: const ValueKey('ndt-edit-per-line'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Każda linia osobno', 'Each line separately')),
              subtitle: Text(
                tr('Wyłączone: partią jest cały projekt.',
                    'Off: the lot is the whole project.'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
              value: _perLine,
              onChanged: (x) => setState(() => _perLine = x),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('ndt-edit-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: result == null
                  ? null
                  : () => Navigator.of(context).pop(result),
              child: Text(tr('Zapisz regułę', 'Save the rule'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('ndt-edit-cancel'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinTapTarget)),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Anuluj', 'Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}
