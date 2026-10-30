// Tarcze i szlifierki: zgodność tarcza ↔ szlifierka ↔ praca (prędkość
// w m/s albo obr./min, średnica, mocowanie, data ważności, typ wobec
// operacji, osłona do cięcia, nierdzewka i aluminium), lista kontrolna
// przed pracą i źródła. „Moje szlifierki” w SharedPreferences (bez zmian
// schematu bazy).
//
// MODUŁ BEZPIECZEŃSTWA: aplikacja jest pomocą — decyduje nadruk na
// tarczy, tabliczka i instrukcja szlifierki (zastrzeżenie na górze).
// Logika i źródła: lib/domain/grinding/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/grinding/grinder_profile.dart';
import '../../domain/grinding/grinding_check.dart';
import '../../domain/grinding/stripe_reference.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/grinding/grinding_checklist.dart';
import '../../i18n/app_language.dart';
import '../../services/owned_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/local_record_scope.dart';
import '../flange_check/flange_check_widgets.dart' show ChoiceRow;
import '../quotes/quote_widgets.dart'
    show FieldPair, QuoteNotice, QuoteNumberField, QuoteSection;
import 'grinding_store.dart';
import 'grinding_widgets.dart';

class GrindingPage extends StatelessWidget {
  const GrindingPage({
    super.key,
    this.store,
    this.now = DateTime.now,
    this.newId,
  });

  /// „Moje szlifierki” — test podmienia klucze.
  final GrinderStore? store;

  /// „Dziś” — do sprawdzenia daty ważności (wstrzykiwane w testach).
  final DateTime Function() now;

  /// Identyfikator nowej szlifierki — wstrzykiwany w testach.
  final String Function()? newId;

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _GrindingBody(
          session: session,
          store: store ??
              GrinderStore(
                  openPrefs: () => OwnedPrefs.instance(session.captureOwner)),
          now: now,
          newId: newId,
        ),
      );
}

class _GrindingBody extends StatefulWidget {
  const _GrindingBody({
    required this.session,
    required this.store,
    required this.now,
    required this.newId,
  });

  final LocalRecordSession session;
  final GrinderStore store;
  final DateTime Function() now;
  final String Function()? newId;

  @override
  State<_GrindingBody> createState() => _GrindingPageState();
}

class _GrindingPageState extends State<_GrindingBody>
    with SingleTickerProviderStateMixin, ToolHandleHost<_GrindingBody> {
  SpeedStripe? _referenceStripe;
  final _checkScroll = ScrollController();
  @override
  String get toolId => 'grinding';
  @override
  Set<String> get supportedFields => const {'reference_stripe'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || !widget.session.isCurrent) return fields.keys.toSet();
    final stripe = SpeedStripe.values
        .where((v) => v.name == fields['reference_stripe'])
        .firstOrNull;
    if (fields.length != 1 || stripe == null) return fields.keys.toSet();
    setState(() {
      _referenceStripe = stripe;
      _tabs.index = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.session.isCurrent && _checkScroll.hasClients) {
        _checkScroll.jumpTo(0);
      }
    });
    return {};
  }

  static int _seq = 0;

  late final TabController _tabs = TabController(length: 3, vsync: this);

  // Szlifierka.
  int? _grinderRpm;
  double? _grinderD;
  SpindleThread? _thread;

  // Tarcza.
  DiscType? _type;
  double? _discD;
  double? _discV;
  int? _discN;
  DiscMount? _mount;
  bool? _boreFits;
  final _expiry = TextEditingController();
  bool _noExpiry = false;
  SpeedStripe? _stripe;

  // Praca.
  GrindingOperation? _op;
  bool? _guard;
  WorkMaterial? _material;
  bool? _marked;
  bool? _usedOnCarbon;

  // Lista kontrolna (tylko na czas ekranu).
  final Set<String> _checked = {};

  // Moje szlifierki.
  List<GrinderProfile> _grinders = const [];
  bool _grindersDamaged = false;
  bool _grindersUnavailable = false;
  bool _grindersLoaded = false;

  /// Szlifierka wczytana do formularza — „Zapisz zmiany” nadpisuje ją po id.
  String? _loadedId;

  GrinderProfile? get _loaded {
    final id = _loadedId;
    if (id == null) return null;
    for (final g in _grinders) {
      if (g.id == id) return g;
    }
    return null;
  }

  bool get _en => context.language == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGrinders());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _checkScroll.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _loadGrinders() async {
    final r = await widget.store.load();
    if (!mounted || !widget.session.isCurrent) return;
    setState(() {
      _grinders = r.grinders;
      // Uszkodzony zapis zostaje zgłoszony do końca wizyty na ekranie.
      _grindersDamaged = _grindersDamaged || r.damaged;
      _grindersUnavailable = r.unavailable;
      _grindersLoaded = true;
    });
    markReady();
  }

  String _newId() =>
      widget.newId?.call() ??
      'gr-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  static int? _toInt(double? v) =>
      v == null || v != v.roundToDouble() ? null : v.toInt();

  GrindingInput get _input => GrindingInput(
        grinderRpm: _grinderRpm,
        grinderDiameterMm: _grinderD,
        spindleThread: _thread,
        discType: _type,
        discDiameterMm: _discD,
        discSpeedMs: _discV,
        discRpm: _discN,
        discMount: _mount,
        boreFitsFlange: _boreFits,
        discExpiry: _noExpiry ? null : parseExpiry(_expiry.text),
        expiryUnreadable: !_noExpiry &&
            _expiry.text.trim().isNotEmpty &&
            parseExpiry(_expiry.text) == null,
        discNoExpiry: _noExpiry,
        stripe: _stripe,
        operation: _op,
        cuttingGuard: _guard,
        material: _material,
        markedForMaterial: _marked,
        usedOnCarbonSteel: _usedOnCarbon,
      );

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted || !widget.session.isCurrent) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  // ── Moje szlifierki ───────────────────────────────────────────────────

  bool get _grinderComplete =>
      _grinderRpm != null &&
      _grinderRpm! >= kMinRpm &&
      _grinderRpm! <= kMaxRpm &&
      _grinderD != null &&
      _grinderD! >= kMinDiameterMm &&
      _grinderD! <= kMaxDiameterMm;

  void _useGrinder(GrinderProfile g) {
    if (!mounted || !widget.session.isCurrent) return;
    // Pole z fokusem nie przyjmuje wartości z zewnątrz (QuoteNumberField) —
    // zdejmujemy fokus, zanim wczytamy szlifierkę.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _grinderRpm = g.maxRpm;
      _grinderD = g.diameterMm;
      _thread = g.thread;
      _loadedId = g.id;
      // Inna szlifierka = inne kołnierze — odpowiedź o otworze od nowa.
      _boreFits = null;
    });
    _snack(context.tr(pl: 'Wczytano: ${g.name}', en: 'Loaded: ${g.name}'));
  }

  void _saveFailed(Object e) {
    debugPrint('[grinding] save failed: $e');
    if (!mounted || !widget.session.isCurrent) return;
    _snack(e is GrinderStoreFull
        ? context.tr(
            pl: 'Najwyżej $kMaxGrinders szlifierek — usuń którąś.',
            en: 'At most $kMaxGrinders grinders — delete one first.')
        : context.tr(
            pl: 'Nie udało się zapisać szlifierek — istniejące dane zachowano.',
            en: 'Could not save the grinders — existing data was preserved.'));
  }

  Future<String?> _askName(String initial) => showDialog<String>(
        context: context,
        builder: (_) => LocalRecordScope(
          originSession: widget.session,
          restartOnAccountChange: false,
          builder: (_, __) => _NameDialog(initial: initial),
        ),
      );

  bool _requireComplete() {
    if (_grinderComplete) return true;
    _snack(context.tr(
        pl: 'Najpierw wpisz obroty i średnicę szlifierki.',
        en: 'Enter the grinder speed and diameter first.'));
    return false;
  }

  /// Nowa szlifierka (nowe id) — dopisana na końcu zapisanej listy.
  Future<void> _saveGrinder() async {
    if (!_requireComplete()) return;
    if (_grinders.length >= kMaxGrinders) {
      _saveFailed(const GrinderStoreFull());
      return;
    }
    final suggested =
        GrinderProfile.defaultName(_grinderD!, _grinderRpm!, en: _en);
    final name = await _askName(suggested);
    if (name == null || !mounted || !widget.session.isCurrent) return;
    final g = GrinderProfile(
      id: _newId(),
      name: name.trim().isEmpty ? suggested : name.trim(),
      maxRpm: _grinderRpm!,
      diameterMm: _grinderD!,
      thread: _thread,
    );
    await _upsert(g,
        done: context.tr(pl: 'Zapisano: ${g.name}', en: 'Saved: ${g.name}'));
  }

  /// „Zapisz zmiany” we wczytanej szlifierce — po id, bez duplikatu.
  Future<void> _updateGrinder() async {
    final loaded = _loaded;
    if (loaded == null || !_requireComplete()) return;
    final name = await _askName(loaded.name);
    if (name == null || !mounted || !widget.session.isCurrent) return;
    final g = GrinderProfile(
      id: loaded.id,
      name: name.trim().isEmpty ? loaded.name : name.trim(),
      maxRpm: _grinderRpm!,
      diameterMm: _grinderD!,
      thread: _thread,
    );
    await _upsert(g,
        done: context.tr(
            pl: 'Zapisano zmiany: ${g.name}', en: 'Changes saved: ${g.name}'));
  }

  Future<void> _upsert(GrinderProfile g, {required String done}) async {
    if (!widget.session.isCurrent) return;
    try {
      final list = await widget.store.upsert(g);
      if (!mounted || !widget.session.isCurrent) return;
      setState(() {
        _grinders = list;
        _grindersUnavailable = false;
        _loadedId = g.id;
      });
      _snack(done);
    } catch (e) {
      _saveFailed(e);
    }
  }

  Future<void> _deleteGrinder(GrinderProfile g) async {
    if (!widget.session.isCurrent) return;
    // Magazyn liczy zmianę od listy zapisanej w chwili zapisu (kolejka) —
    // dwa szybkie usunięcia nie wskrzeszają pierwszego.
    final store = widget.store;
    final GrinderRemoval? removal;
    try {
      removal = await store.delete(g.id);
    } catch (e) {
      _saveFailed(e);
      return;
    }
    if (!mounted || !widget.session.isCurrent) return;
    setState(() {
      if (removal != null) _grinders = removal.remaining;
      if (_loadedId == g.id) _loadedId = null;
    });
    final r = removal;
    if (r == null) return;
    _snack(
      context.tr(pl: 'Usunięto: ${g.name}', en: 'Deleted: ${g.name}'),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        // Przez magazyn, nie przez stan ekranu — działa też po jego
        // zamknięciu; przywraca TYLKO ten wpis, na dawne miejsce.
        onPressed: () => unawaited(_undoDelete(store, r)),
      ),
    );
  }

  Future<void> _undoDelete(GrinderStore store, GrinderRemoval r) async {
    if (!widget.session.isCurrent) return;
    try {
      final list = await store.restore(r.profile, r.index);
      if (!mounted || !widget.session.isCurrent) return;
      setState(() => _grinders = list);
    } catch (e) {
      _saveFailed(e);
    }
  }

  // ── Budowa ekranu ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            context.tr(pl: 'Tarcze i szlifierki', en: 'Discs and grinders')),
        // Stałe zakładki (po 1/3 szerokości) z krótkimi etykietami, a gdyby
        // przy dużej czcionce etykieta i tak się nie mieściła — pomniejszona,
        // nigdy ucięta: wszystkie trzy widać w całości nawet na 360 dp przy
        // czcionce ×1,5 (przewijany pasek chował „Źródła” za krawędzią).
        bottom: TabBar(
          controller: _tabs,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: [
            _tab('gr-tab-check', context.tr(pl: 'Sprawdź', en: 'Check')),
            _tab('gr-tab-list', context.tr(pl: 'Lista', en: 'List')),
            _tab('gr-tab-sources', context.tr(pl: 'Źródła', en: 'Sources')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _checkTab(),
          _checklistTab(),
          _sourcesTab(),
        ],
      ),
    );
  }

  static Widget _tab(String key, String label) => Tab(
        key: ValueKey(key),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false),
        ),
      );

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(
      12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom);

  Widget _checkTab() {
    final en = _en;
    final eval = evaluateGrinding(_input, now: widget.now());
    final status = evaluateChecklist(_checked);
    // Najgorsze na górze; w obrębie poziomu kolejność z oceny (sort Darta
    // nie gwarantuje stabilności — stąd indeks jako drugi klucz).
    final order = {
      for (final (i, f) in eval.findings.indexed) f: i,
    };
    final sorted = [...eval.findings]..sort((a, b) {
        final byLevel = a.level.index.compareTo(b.level.index);
        return byLevel != 0 ? byLevel : order[a]!.compareTo(order[b]!);
      });
    return ListView(
      key: const ValueKey('gr-check-list'),
      controller: _checkScroll,
      padding: _listPadding,
      children: [
        if (_referenceStripe != null)
          Card(
              key: const ValueKey('gr-assistant-reference'),
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(grindingStripeReference(
                            _referenceStripe!,
                            en: _en)),
                        TextButton(
                            onPressed: () =>
                                setState(() => _referenceStripe = null),
                            child: Text(context.tr(
                                pl: 'Zamknij informację o pasku',
                                en: 'Close stripe reference'))),
                      ]))),
        QuoteNotice(
          icon: Icons.gavel_outlined,
          text: context.tr(
            pl: 'Pomoc w sprawdzeniu, nie zastępuje instrukcji. Decyduje '
                'nadruk na tarczy, tabliczka i instrukcja szlifierki. Brak '
                'danych to nie „OK”.',
            en: 'A checking aid, not a substitute for the manual. The disc '
                'label, the nameplate and the grinder manual decide. Missing '
                'data is not “OK”.',
          ),
        ),
        GrindingVerdictBanner(
          evaluation: eval,
          checklistChecked: status.checked,
          checklistTotal: status.total,
        ),
        _grinderSection(en),
        _discSection(en),
        _jobSection(en),
        QuoteSection(
          title: context.tr(pl: 'Wynik sprawdzenia', en: 'Check result'),
          children: [
            if (eval.allowedRpm != null)
              _factLine(
                key: 'gr-allowed-rpm',
                label: context.tr(
                    pl: 'Dopuszczalne obroty tarczy',
                    en: 'Permitted disc speed'),
                value: en
                    ? '${fmtRpm(eval.allowedRpm!, en: true)} rpm'
                    : '${fmtRpm(eval.allowedRpm!, en: false)} obr./min',
              ),
            if (eval.grinderSpeedUpMs != null)
              _factLine(
                key: 'gr-rim-speed',
                label: context.tr(
                    pl: 'Prędkość na obwodzie przy obrotach szlifierki',
                    en: 'Rim speed at the grinder speed'),
                value: '${fmtNum(eval.grinderSpeedUpMs!, en: en)} m/s',
              ),
            if (eval.allowedRpm != null || eval.grinderSpeedUpMs != null)
              const SizedBox(height: 8),
            for (final (i, f) in sorted.indexed)
              GrindingFindingTile(
                key: ValueKey('gr-finding-${f.kind.name}-$i'),
                finding: f,
              ),
          ],
        ),
      ],
    );
  }

  Widget _factLine(
      {required String key, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: kTextSec)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              key: ValueKey(key),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: kArc,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String text) => Text(text);

  // ── Szlifierka ──

  Widget _grinderSection(bool en) {
    return QuoteSection(
      title: context.tr(pl: 'Szlifierka', en: 'Grinder'),
      subtitle: context.tr(
          pl: 'Z tabliczki znamionowej i instrukcji.',
          en: 'From the nameplate and the manual.'),
      children: [
        if (_grindersDamaged)
          QuoteNotice(
            key: const ValueKey('gr-grinders-damaged'),
            color: kFail,
            icon: Icons.report_gmailerrorred_outlined,
            text: context.tr(
              pl: 'Zapis „Moje szlifierki” był uszkodzony — wczytano '
                  '${_grinders.length}. Surowa kopia zapisu została zachowana '
                  'w pamięci aplikacji; nic nie usunięto po cichu.',
              en: 'The “My grinders” record was damaged — '
                  '${_grinders.length} loaded. A raw copy was kept in the '
                  'app storage; nothing was silently deleted.',
            ),
          ),
        if (_grindersUnavailable) ...[
          QuoteNotice(
            key: const ValueKey('gr-grinders-unavailable'),
            icon: Icons.sd_card_alert_outlined,
            text: context.tr(
              pl: 'Pamięć aplikacji jest teraz niedostępna — „Moje '
                  'szlifierki” nie zostały wczytane. Niczego nie usunięto '
                  'ani nie nadpisano; sprawdzenie tarczy działa normalnie.',
              en: 'App storage is unavailable right now — “My grinders” '
                  'were not loaded. Nothing was deleted or overwritten; the '
                  'disc check works as usual.',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('gr-grinders-retry'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, kMinTapTarget)),
              onPressed: () => unawaited(_loadGrinders()),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr(pl: 'Spróbuj ponownie', en: 'Try again')),
            ),
          ),
        ],
        if (_grinders.isNotEmpty) ...[
          Text(context.tr(pl: 'Moje szlifierki', en: 'My grinders'),
              style: const TextStyle(
                  fontSize: 13, color: kTextSec, fontWeight: FontWeight.w700)),
          for (final g in _grinders) _grinderTile(g, en),
          const SizedBox(height: 8),
        ],
        FieldPair(
          left: QuoteNumberField(
            key: const ValueKey('gr-grinder-rpm'),
            label: context.tr(pl: 'Maks. obroty', en: 'Max speed'),
            unit: en ? 'rpm' : 'obr./min',
            helper: context.tr(pl: 'bieg jałowy', en: 'no-load'),
            value: _grinderRpm?.toDouble(),
            decimal: false,
            decimals: 0,
            allowEmpty: true,
            validate: (v) => _toInt(v) == null ||
                    _toInt(v)! < kMinRpm ||
                    _toInt(v)! > kMaxRpm
                ? context.tr(
                    pl: 'Zakres ${fmtRpm(kMinRpm, en: false)}–'
                        '${fmtRpm(kMaxRpm, en: false)}',
                    en: 'Range ${fmtRpm(kMinRpm, en: true)}–'
                        '${fmtRpm(kMaxRpm, en: true)}')
                : null,
            onChanged: (v) => setState(() => _grinderRpm = _toInt(v)),
          ),
          right: QuoteNumberField(
            key: const ValueKey('gr-grinder-d'),
            label: context.tr(pl: 'Średnica tarczy', en: 'Disc diameter'),
            unit: 'mm',
            helper: context.tr(
                pl: 'przewidziana dla szlifierki i osłony',
                en: 'the grinder and guard are made for'),
            value: _grinderD,
            decimals: 1,
            allowEmpty: true,
            validate: _diameterError,
            onChanged: (v) => setState(() => _grinderD = v),
          ),
        ),
        const SizedBox(height: 10),
        Text(context.tr(pl: 'Gwint wrzeciona', en: 'Spindle thread'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in SpindleThread.values)
              ChoiceChip(
                key: ValueKey('gr-thread-${t.name}'),
                label: _chipLabel(t.label),
                selected: _thread == t,
                onSelected: (s) => setState(() => _thread = s ? t : null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loaded case final loaded?) ...[
          FilledButton.icon(
            key: const ValueKey('gr-update-grinder'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget)),
            onPressed: _grindersLoaded ? _updateGrinder : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              context.tr(
                  pl: 'Zapisz zmiany: ${loaded.name}',
                  en: 'Save changes: ${loaded.name}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const ValueKey('gr-save-grinder'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget)),
          onPressed: _grindersLoaded ? _saveGrinder : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(
            _loaded == null
                ? context.tr(
                    pl: 'Zapisz jako moją szlifierkę', en: 'Save as my grinder')
                : context.tr(
                    pl: 'Zapisz jako nową szlifierkę',
                    en: 'Save as a new grinder'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String? _diameterError(double? v) =>
      v == null || v < kMinDiameterMm || v > kMaxDiameterMm
          ? context.tr(
              pl: 'Zakres ${fmtNum(kMinDiameterMm, en: false)}–'
                  '${fmtNum(kMaxDiameterMm, en: false)} mm',
              en: 'Range ${fmtNum(kMinDiameterMm, en: true)}–'
                  '${fmtNum(kMaxDiameterMm, en: true)} mm')
          : null;

  Widget _grinderTile(GrinderProfile g, bool en) {
    final sub = [
      'Ø${fmtNum(g.diameterMm, en: en)} mm',
      en
          ? '${fmtRpm(g.maxRpm, en: true)} rpm'
          : '${fmtRpm(g.maxRpm, en: false)} obr./min',
      if (g.thread != null) g.thread!.label,
    ].join(' · ');
    final selected = g.id == _loadedId;
    return ListTile(
      key: ValueKey('gr-grinder-${g.id}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: kMinTapTarget,
      selected: selected,
      selectedColor: kArc,
      leading: Icon(
          selected ? Icons.check_circle_outline : Icons.handyman_outlined,
          color: selected ? kArc : kTextSec),
      title: Text(g.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle:
          Text(sub, style: const TextStyle(fontSize: 12, color: kTextMut)),
      onTap: () => _useGrinder(g),
      trailing: IconButton(
        key: ValueKey('gr-grinder-del-${g.id}'),
        tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_deleteGrinder(g)),
      ),
    );
  }

  // ── Tarcza ──

  Widget _discSection(bool en) {
    final expiryText = _expiry.text.trim();
    final expiryParsed = parseExpiry(expiryText);
    final stripe = _stripe;
    return QuoteSection(
      title: context.tr(pl: 'Tarcza', en: 'Disc'),
      subtitle: context.tr(
          pl: 'Z etykiety i metalowego pierścienia tarczy.',
          en: 'From the disc label and the metal ring.'),
      children: [
        Text(context.tr(pl: 'Typ', en: 'Type'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        for (final t in DiscType.values)
          ChoiceRow(
            key: ValueKey('gr-type-${t.name}'),
            selected: _type == t,
            label: t.label(en: en),
            onTap: () => setState(() {
              final next = _type == t ? null : t;
              // Szczotka ↔ tarcza: pytanie o oznaczenie zmienia treść
              // („drut nierdzewny” / „INOX”) — stara odpowiedź nie przechodzi.
              if ((next == DiscType.wire) != (_type == DiscType.wire)) {
                _marked = null;
              }
              _type = next;
            }),
          ),
        const SizedBox(height: 8),
        QuoteNumberField(
          key: const ValueKey('gr-disc-d'),
          label: context.tr(pl: 'Średnica tarczy', en: 'Disc diameter'),
          unit: 'mm',
          value: _discD,
          decimals: 1,
          allowEmpty: true,
          validate: _diameterError,
          onChanged: (v) => setState(() => _discD = v),
        ),
        const SizedBox(height: 10),
        FieldPair(
          left: QuoteNumberField(
            key: const ValueKey('gr-disc-v'),
            label: context.tr(pl: 'Maks. prędkość', en: 'Max speed'),
            unit: 'm/s',
            helper: context.tr(pl: 'z etykiety', en: 'from the label'),
            value: _discV,
            decimals: 1,
            allowEmpty: true,
            validate: (v) => v == null || v < kMinSpeedMs || v > kMaxSpeedMs
                ? context.tr(
                    pl: 'Zakres ${fmtNum(kMinSpeedMs, en: false)}–'
                        '${fmtNum(kMaxSpeedMs, en: false)} m/s',
                    en: 'Range ${fmtNum(kMinSpeedMs, en: true)}–'
                        '${fmtNum(kMaxSpeedMs, en: true)} m/s')
                : null,
            onChanged: (v) => setState(() => _discV = v),
          ),
          right: QuoteNumberField(
            key: const ValueKey('gr-disc-n'),
            label: context.tr(pl: 'Maks. obroty', en: 'Max rpm'),
            unit: en ? 'rpm' : 'obr./min',
            helper: context.tr(
                pl: 'z etykiety (wystarczy jedno)',
                en: 'from the label (one is enough)'),
            value: _discN?.toDouble(),
            decimal: false,
            decimals: 0,
            allowEmpty: true,
            validate: (v) => _toInt(v) == null ||
                    _toInt(v)! < kMinRpm ||
                    _toInt(v)! > kMaxRpm
                ? context.tr(
                    pl: 'Zakres ${fmtRpm(kMinRpm, en: false)}–'
                        '${fmtRpm(kMaxRpm, en: false)}',
                    en: 'Range ${fmtRpm(kMinRpm, en: true)}–'
                        '${fmtRpm(kMaxRpm, en: true)}')
                : null,
            onChanged: (v) => setState(() => _discN = _toInt(v)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
            context.tr(
                pl: 'Pasek barwny (podpowiedź — decyduje nadruk)',
                en: 'Colour stripe (a hint — the print decides)'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in SpeedStripe.values)
              ChoiceChip(
                key: ValueKey('gr-stripe-${s.name}'),
                avatar: StripeSwatch(stripe: s),
                label: _chipLabel('${fmtNum(s.speedMs, en: en)} m/s'),
                tooltip: s.colour(en: en),
                selected: stripe == s,
                onSelected: (sel) => setState(() => _stripe = sel ? s : null),
              ),
          ],
        ),
        // Kolor to tylko podpowiedź: nie ma przycisku, który przepisałby go
        // do pola prędkości — do obliczeń idzie wyłącznie nadruk, a pasek
        // niezgodny z nadrukiem daje ostrzeżenie.
        if (stripe != null) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Pasek ${stripe.colourPl} zwykle oznacza '
                    '${fmtNum(stripe.speedMs, en: false)} m/s '
                    '(EN 12413 zał. D, informacyjny). Kod barwny nie jest '
                    'obowiązkowy — do obliczeń wpisz prędkość z nadruku.',
                en: 'A ${stripe.colourEn} stripe usually means '
                    '${fmtNum(stripe.speedMs, en: true)} m/s '
                    '(EN 12413 Annex D, informative). The colour code is not '
                    'mandatory — enter the printed speed for the check.'),
            key: const ValueKey('gr-stripe-note'),
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35),
          ),
        ],
        const SizedBox(height: 10),
        Text(context.tr(pl: 'Mocowanie', en: 'Mounting'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in DiscMount.values)
              ChoiceChip(
                key: ValueKey('gr-mount-${m.name}'),
                label: _chipLabel(m.label(en: en)),
                selected: _mount == m,
                // Inny otwór = inne pytanie: stare „pasuje” nie przechodzi
                // na nowe mocowanie.
                onSelected: (s) => setState(() {
                  _mount = s ? m : null;
                  _boreFits = null;
                }),
              ),
          ],
        ),
        if (_mount != null && !_mount!.isThreaded) ...[
          const SizedBox(height: 6),
          YesNoChips(
            keyPrefix: 'gr-bore',
            question: context.tr(
                pl: 'Otwór tarczy (${_mount!.labelPl} mm) pasuje do kołnierza '
                    'szlifierki?',
                en: 'Does the disc bore (${_mount!.labelEn} mm) fit the '
                    'grinder flange?'),
            value: _boreFits,
            onChanged: (v) => setState(() => _boreFits = v),
          ),
        ],
        const SizedBox(height: 12),
        // Bez filtra znaków: wycięcie litery z „1O/2027” dałoby inną,
        // poprawnie wyglądającą datę („1/2027”). Nieczytelny wpis zostaje
        // i daje brak werdyktu.
        TextField(
          key: const ValueKey('gr-expiry'),
          controller: _expiry,
          enabled: !_noExpiry,
          keyboardType: TextInputType.datetime,
          inputFormatters: [LengthLimitingTextInputFormatter(12)],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Data ważności (MM/RRRR)', en: 'Expiry (MM/YYYY)'),
            helperText: context.tr(
                pl: 'Z pierścienia, np. V 07/2027. Wymagana dla 41, 42, 27. '
                    'Przyjęto: ważna do końca miesiąca przed nadrukiem.',
                en: 'From the ring, e.g. V 07/2027. Required for 41, 42, 27. '
                    'Taken as: valid until the end of the month before it.'),
            helperMaxLines: 4,
            errorText:
                !_noExpiry && expiryText.isNotEmpty && expiryParsed == null
                    ? context.tr(
                        pl: 'Nie rozpoznano daty — wpisz MM/RRRR',
                        en: 'Date not recognised — enter MM/YYYY')
                    : null,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('gr-no-expiry'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _noExpiry,
          onChanged: (v) => setState(() => _noExpiry = v ?? false),
          title: Text(
            context.tr(
                pl: 'Na tarczy nie ma daty ważności',
                en: 'There is no expiry date on the disc'),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  // ── Praca ──

  Widget _jobSection(bool en) {
    final m = _material;
    final wire = _type == DiscType.wire;
    final showGuard = _op == GrindingOperation.cutting &&
        (_type == null || _type!.isCutOff || _type == DiscType.t27);
    return QuoteSection(
      title: context.tr(pl: 'Praca', en: 'Job'),
      children: [
        for (final o in GrindingOperation.values)
          ChoiceRow(
            key: ValueKey('gr-op-${o.name}'),
            selected: _op == o,
            label: o.label(en: en),
            onTap: () => setState(() => _op = _op == o ? null : o),
          ),
        if (showGuard) ...[
          const SizedBox(height: 6),
          YesNoChips(
            keyPrefix: 'gr-guard',
            question: context.tr(
                pl: 'Osłona do cięcia (zamknięta) albo osłona do szlifowania '
                    'z nakładką do cięcia założona?',
                en: 'Cutting guard (closed) or grinding guard with the cutting '
                    'cover fitted?'),
            value: _guard,
            onChanged: (v) => setState(() => _guard = v),
          ),
        ],
        const SizedBox(height: 8),
        Text(context.tr(pl: 'Materiał', en: 'Material'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final w in WorkMaterial.values)
              ChoiceChip(
                key: ValueKey('gr-material-${w.name}'),
                label: _chipLabel(w.label(en: en)),
                selected: _material == w,
                // Nierdzewka ↔ aluminium: inne pytania („INOX” / „do
                // aluminium”) — odpowiedzi od nowa.
                onSelected: (s) => setState(() {
                  final next = s ? w : null;
                  if (next != _material) {
                    _marked = null;
                    _usedOnCarbon = null;
                  }
                  _material = next;
                }),
              ),
          ],
        ),
        if (m == WorkMaterial.stainless || m == WorkMaterial.aluminium) ...[
          const SizedBox(height: 8),
          YesNoChips(
            keyPrefix: 'gr-marked',
            question: m == WorkMaterial.stainless
                ? (wire
                    ? context.tr(
                        pl: 'Szczotka z drutu ze stali nierdzewnej?',
                        en: 'Is the brush wire stainless steel?')
                    : context.tr(
                        pl: 'Tarcza oznaczona INOX (bez Fe, S, Cl)?',
                        en: 'Disc marked INOX (free of Fe, S, Cl)?'))
                : context.tr(
                    pl: 'Narzędzie do aluminium / metali nieżelaznych?',
                    en: 'Tool made for aluminium / non-ferrous metals?'),
            value: _marked,
            onChanged: (v) => setState(() => _marked = v),
          ),
          YesNoChips(
            keyPrefix: 'gr-carbon',
            question: context.tr(
                pl: 'Narzędzie używane wcześniej na stali węglowej?',
                en: 'Tool used before on carbon steel?'),
            value: _usedOnCarbon,
            onChanged: (v) => setState(() => _usedOnCarbon = v),
          ),
          Text(
            m == WorkMaterial.stainless
                ? context.tr(
                    pl: 'Do nierdzewki tylko tarcze INOX i szczotki ze stali '
                        'nierdzewnej, nieużywane na stali węglowej — inaczej '
                        'żelazo daje rdzawe naloty. Po pracy: moduły '
                        '„Przebarwienia” oraz „Trawienie i pasywacja”.',
                    en: 'For stainless use only INOX discs and stainless wire '
                        'brushes never used on carbon steel — otherwise iron '
                        'leaves rust stains. After the job see the “Heat '
                        'tint” and “Pickling and passivation” modules.')
                : context.tr(
                    pl: 'Do aluminium osobne tarcze i szczotki — nie te same '
                        'co do stali.',
                    en: 'Keep separate discs and brushes for aluminium — not '
                        'the ones used on steel.'),
            key: const ValueKey('gr-material-note'),
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35),
          ),
        ],
      ],
    );
  }

  // ── Lista kontrolna ──

  Widget _checklistTab() {
    final en = _en;
    final status = evaluateChecklist(_checked);
    final color = status.complete ? kPass : kWarn;
    return ListView(
      key: const ValueKey('gr-list-list'),
      padding: _listPadding,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Text(
            status.complete
                ? context.tr(
                    pl: 'Gotowe: ${status.checked}/${status.total}',
                    en: 'Ready: ${status.checked}/${status.total}')
                : context.tr(
                    pl: 'Niekompletna: ${status.checked}/${status.total} — '
                        'niezaznaczony punkt to nie „OK”',
                    en: 'Incomplete: ${status.checked}/${status.total} — an '
                        'unticked item is not “OK”'),
            key: const ValueKey('gr-checklist-status'),
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
        QuoteSection(
          title: context.tr(pl: 'Przed włączeniem', en: 'Before switching on'),
          trailing: TextButton(
            key: const ValueKey('gr-checklist-clear'),
            style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
            onPressed: _checked.isEmpty ? null : () => setState(_checked.clear),
            child: Text(context.tr(pl: 'Wyczyść', en: 'Clear')),
          ),
          children: [
            for (final c in kGrindingChecks)
              CheckboxListTile(
                key: ValueKey('gr-check-${c.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _checked.contains(c.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _checked.add(c.id);
                  } else {
                    _checked.remove(c.id);
                  }
                }),
                title: Text(c.label(en: en),
                    style: const TextStyle(fontSize: 13.5, height: 1.35)),
                subtitle: c.sourceLabel(en: en) == null
                    ? null
                    : Text(c.sourceLabel(en: en)!,
                        style: const TextStyle(
                            fontSize: 11.5, color: kTextMut, height: 1.3)),
              ),
          ],
        ),
      ],
    );
  }

  // ── Źródła ──

  Widget _sourcesTab() {
    final en = _en;
    Widget item(GrindingSource s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s.label(en: en),
              style: const TextStyle(fontSize: 13, height: 1.4, color: kText)),
        );
    return ListView(
      key: const ValueKey('gr-sources-list'),
      padding: _listPadding,
      children: [
        QuoteSection(
          title: context.tr(
              pl: 'Źródła i wartości odniesienia',
              en: 'Sources and reference values'),
          children: [for (final s in kGrindingSources) item(s)],
        ),
        QuoteSection(
          title: context.tr(pl: 'Przyjęte w aplikacji', en: 'App rules'),
          subtitle: context.tr(
              pl: 'Tego źródła nie rozstrzygają — przyjęto wariant '
                  'bezpieczniejszy.',
              en: 'The sources do not settle these — the safer reading is '
                  'used.'),
          children: [for (final s in kGrindingAppRules) item(s)],
        ),
      ],
    );
  }
}

/// Nazwa zapisywanej szlifierki (kontroler żyje razem z oknem).
class _NameDialog extends StatefulWidget {
  final String initial;
  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(pl: 'Moja szlifierka', en: 'My grinder')),
      content: TextField(
        key: const ValueKey('gr-grinder-name'),
        controller: _c,
        autofocus: true,
        maxLength: kMaxGrinderNameLength,
        decoration: InputDecoration(
          labelText: context.tr(pl: 'Nazwa', en: 'Name'),
          hintText: widget.initial,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('gr-grinder-name-save'),
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}
