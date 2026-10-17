// Odbiór połączenia kołnierzowego przed skręceniem: pomiary osiowania
// z werdyktem wg ASME PCC-1-2019 zał. E (tolerancje edytowalne, „przywróć
// PCC-1”), lista kontrolna montażu, dane połączenia, przejście do „Moment
// śrub”, historia protokołów (SharedPreferences, bez zmian w bazie)
// i udostępnianie protokołu jako tekst lub PDF.
//
// Logika i źródła wartości: lib/domain/flange/ (flange_pcc1.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/flange/flange_check.dart';
import '../../domain/flange/flange_labels.dart';
import '../../i18n/app_language.dart';
import '../../screens/bolt_torque_screen.dart';
import '../../services/flange_catalog.dart';
import '../../services/flange_check_export.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart';
import 'flange_check_store.dart';
import 'flange_check_widgets.dart';

class FlangeCheckPage extends StatefulWidget {
  /// Udostępnianie protokołu — test podmienia, żeby nie wołać platformy.
  final FlangeShareFn share;
  final FlangeCheckStore store;

  /// „Dziś” — do testów.
  final DateTime Function()? clock;

  const FlangeCheckPage({
    super.key,
    this.share = shareFlangeCheck,
    this.store = const FlangeCheckStore(),
    this.clock,
  });

  @override
  State<FlangeCheckPage> createState() => _FlangeCheckPageState();
}

class _FlangeCheckPageState extends State<FlangeCheckPage>
    with SingleTickerProviderStateMixin {
  static int _seq = 0;

  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<FlangeCheck> _history = [];
  bool _loading = true;
  late FlangeCheck _draft;
  bool _dirty = false;
  bool _tagError = false;
  bool _sharing = false;
  String _profileName = '';

  final _tag = TextEditingController();
  final _rating = TextEditingController();
  final _gasketType = TextEditingController();
  final _gasketT = TextEditingController();
  final _boltGrade = TextEditingController();
  final _boltCount = TextEditingController();
  final _location = TextEditingController();
  final _fitter = TextEditingController();
  final _notes = TextEditingController();
  final _centerline = TextEditingController();
  final _rotation = TextEditingController();
  final _gaps = List.generate(8, (_) => TextEditingController());
  final _tolCenter = TextEditingController();
  final _tolPar = TextEditingController();
  final _tolRot = TextEditingController();
  final _tolFactor = TextEditingController();

  List<TextEditingController> get _allControllers => [
        _tag,
        _rating,
        _gasketType,
        _gasketT,
        _boltGrade,
        _boltCount,
        _location,
        _fitter,
        _notes,
        _centerline,
        _rotation,
        ..._gaps,
        _tolCenter,
        _tolPar,
        _tolRot,
        _tolFactor,
      ];

  DateTime get _now => (widget.clock ?? DateTime.now)();

  String get _todayIso {
    final d = _now;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  bool get _en => context.language == AppLanguage.en;

  String _newId() => 'fc-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  FlangeCheck _newDraft() {
    final latest = _latest;
    final now = _now.millisecondsSinceEpoch;
    return FlangeCheck(
      id: _newId(),
      joint: FlangeJoint(date: _todayIso, fitter: _profileName),
      measurements: FlangeMeasurements.empty(),
      unit: latest?.unit ?? LengthUnit.mm,
      tolerances: latest?.tolerances ?? FlangeTolerances.pcc1,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Ostatnio zmieniany protokół — od niego nowy bierze jednostkę
  /// i tolerancje (zakład z ostrzejszą specyfikacją nie wpisuje ich co raz).
  FlangeCheck? get _latest => _history.isEmpty
      ? null
      : _history.reduce((a, b) => a.updatedAt >= b.updatedAt ? a : b);

  @override
  void initState() {
    super.initState();
    _draft = _newDraft();
    _bind();
    unawaited(_load());
  }

  Future<void> _load() async {
    final history = await widget.store.load();
    var name = '';
    try {
      name = (await UserProfileService.instance.get())?.fullName ?? '';
    } catch (_) {
      name = '';
    }
    if (!mounted) return;
    setState(() {
      _history = history;
      _profileName = name;
      _loading = false;
      if (!_dirty) {
        _draft = _newDraft();
        _bind();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Wiązanie pól z modelem ────────────────────────────────────────────────

  /// Pola tekstowe z [_draft] (otwarcie, duplikat, zmiana jednostki).
  void _bind() {
    final d = _draft;
    final j = d.joint;
    _tag.text = j.tag;
    _rating.text = j.rating;
    _gasketType.text = j.gasketType;
    _boltGrade.text = j.boltGrade;
    _boltCount.text = j.boltCount?.toString() ?? '';
    _location.text = j.location;
    _fitter.text = j.fitter;
    _notes.text = d.notes;
    _bindLengths();
  }

  /// Pola długości w jednostce protokołu (zmiana mm ↔ cale nie zmienia
  /// zapisanych wartości — tylko to, jak je widać).
  void _bindLengths() {
    final d = _draft;
    final u = d.unit;
    final en = AppLanguageController.isEnglish;
    _gasketT.text = fieldText(d.joint.gasketThicknessMm, u, en: en);
    _centerline.text = fieldText(d.measurements.centerlineMm, u, en: en);
    _rotation.text = fieldText(d.measurements.rotationMm, u, en: en);
    for (var i = 0; i < _gaps.length; i++) {
      final g = d.measurements.gapsMm;
      _gaps[i].text = i < g.length ? fieldText(g[i], u, en: en) : '';
    }
    _bindTolerances();
  }

  void _bindTolerances() {
    final t = _draft.tolerances;
    final u = _draft.unit;
    final en = AppLanguageController.isEnglish;
    String lim(DualLimit l) =>
        l.isValid ? fmtNum(l.inUnit(u), decimals: 4, en: en) : '';
    _tolCenter.text = lim(t.centerline);
    _tolPar.text = lim(t.parallelism);
    _tolRot.text = lim(t.rotation);
    _tolFactor.text =
        t.gapFactor > 0 ? fmtNum(t.gapFactor, decimals: 2, en: en) : '';
  }

  void _update(FlangeCheck next) => setState(() {
        _draft = next;
        _dirty = true;
      });

  void _updateJoint(FlangeJoint j) => _update(_draft.copyWith(joint: j));

  void _updateMeasurements(FlangeMeasurements m) =>
      _update(_draft.copyWith(measurements: m));

  double? _mm(String text) {
    final v = parseDecimal(text);
    return v == null ? null : unitToMm(v, _draft.unit);
  }

  void _setUnit(LengthUnit u) {
    if (u == _draft.unit) return;
    setState(() {
      _draft = _draft.copyWith(unit: u);
      _dirty = true;
      _bindLengths();
    });
  }

  void _setGapPoints(int n) {
    setState(() {
      _draft =
          _draft.copyWith(measurements: _draft.measurements.withGapPoints(n));
      _dirty = true;
      _bindLengths();
    });
  }

  /// Klasa ASME z pola „Klasa / PN” („300”, „CL300”, „Class 300 #”).
  int? get _asmeClass {
    final m = RegExp(r'^\s*(?:cl(?:ass)?\.?\s*)?(\d{3,4})\s*(?:#|lb)?\s*$',
            caseSensitive: false)
        .firstMatch(_rating.text);
    final cls = m == null ? null : int.tryParse(m.group(1)!);
    return cls != null && FlangeCatalog.classes.contains(cls) ? cls : null;
  }

  /// Liczba śrub z ASME B16.5 dla DN + klasy (gdy jest w katalogu).
  int? get _catalogBolts {
    final dn = _draft.joint.dn;
    final cls = _asmeClass;
    if (dn == null || cls == null) return null;
    return FlangeCatalog.lookup(dn, cls)?.boltCount;
  }

  /// Puste pole liczby śrub dostaje wartość z B16.5 po wyborze DN i klasy.
  void _autofillBolts() {
    final n = _catalogBolts;
    if (n == null || _boltCount.text.trim().isNotEmpty) return;
    _boltCount.text = '$n';
    _draft = _draft.copyWith(joint: _draft.joint.copyWith(boltCount: () => n));
  }

  void _setDn(int? dn) {
    setState(() {
      var m = _draft.measurements;
      // Bez odczytów szczeliny: liczba punktów idzie za średnicą.
      if (m.gapsMm.every((g) => g == null)) {
        m = m.withGapPoints(recommendedGapPoints(dn));
      }
      _draft = _draft.copyWith(
          joint: _draft.joint.copyWith(dn: () => dn), measurements: m);
      _dirty = true;
      _autofillBolts();
    });
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_draft.joint.date) ?? _now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final iso = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _updateJoint(_draft.joint.copyWith(date: iso));
  }

  // ── Akcje ─────────────────────────────────────────────────────────────────

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<bool> _persist() async {
    try {
      await widget.store.save(_history);
      return true;
    } catch (_) {
      if (mounted) {
        _snack(context.tr(
            pl: 'Nie udało się zapisać na telefonie.',
            en: 'Could not save on the phone.'));
      }
      return false;
    }
  }

  Future<void> _save() async {
    if (_draft.joint.tag.trim().isEmpty) {
      setState(() => _tagError = true);
      _tabs.animateTo(0);
      Haptic.error();
      _snack(context.tr(
          pl: 'Podaj oznaczenie połączenia (nr linii / kołnierza).',
          en: 'Enter the joint tag (line / flange no.).'));
      return;
    }
    final saved = _draft.copyWith(updatedAt: _now.millisecondsSinceEpoch);
    setState(() {
      final i = _history.indexWhere((c) => c.id == saved.id);
      if (i >= 0) {
        _history[i] = saved;
      } else {
        _history.insert(0, saved);
      }
      _draft = saved;
      _dirty = false;
      _tagError = false;
    });
    if (!await _persist() || !mounted) return;
    Haptic.saved();
    _snack(context.tr(pl: 'Zapisano protokół.', en: 'Protocol saved.'));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(context.tr(pl: 'Niezapisane zmiany', en: 'Unsaved changes')),
        content: Text(context.tr(
            pl: 'Protokół nie jest zapisany. Odrzucić zmiany?',
            en: 'The protocol is not saved. Discard the changes?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          TextButton(
              key: const ValueKey('flange-discard'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr(pl: 'Odrzuć', en: 'Discard'))),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _openDraft(FlangeCheck next) async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _draft = next;
      _dirty = false;
      _tagError = false;
      _bind();
    });
    _tabs.animateTo(0);
  }

  Future<void> _newProtocol() => _openDraft(_newDraft());

  Future<void> _duplicate(FlangeCheck source) async {
    final copy = source.duplicate(
      id: _newId(),
      date: _todayIso,
      now: _now.millisecondsSinceEpoch,
    );
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _draft = copy;
      // Kopia nie jest jeszcze zapisana — wyjście bez zapisu pyta.
      _dirty = true;
      _tagError = false;
      _bind();
    });
    _tabs.animateTo(0);
    final tag = source.joint.tag.trim();
    _snack(tag.isEmpty
        ? context.tr(
            pl: 'Kopia protokołu — wpisz pomiary i odhacz listę.',
            en: 'Protocol copy — enter measurements and tick the list.')
        : context.tr(
            pl: 'Kopia jak „$tag” — wpisz pomiary i odhacz listę.',
            en: 'Copy like “$tag” — enter measurements and tick the list.'));
  }

  Future<void> _delete(FlangeCheck c) async {
    final index = _history.indexWhere((h) => h.id == c.id);
    if (index < 0) return;
    setState(() {
      _history.removeAt(index);
      if (_draft.id == c.id) _dirty = true;
    });
    await _persist();
    if (!mounted) return;
    _snack(
      context.tr(pl: 'Usunięto protokół.', en: 'Protocol deleted.'),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        onPressed: () {
          if (!mounted) return;
          setState(() {
            if (_history.every((h) => h.id != c.id)) {
              _history.insert(index.clamp(0, _history.length), c);
            }
            if (_draft.id == c.id) _dirty = false;
          });
          unawaited(_persist());
        },
      ),
    );
  }

  Future<void> _share(FlangeCheck c, FlangeShareFormat f) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await widget.share(c, f, _en);
    } catch (_) {
      if (mounted) {
        _snack(context.tr(
            pl: 'Nie udało się udostępnić protokołu.',
            en: 'Could not share the protocol.'));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openBoltTorque() {
    unawaited(Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BoltTorqueScreen())));
  }

  // ── Budowa ekranu ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          setState(() => _dirty = false);
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(pl: 'Odbiór kołnierza', en: 'Flange check')),
          actions: [
            IconButton(
              key: const ValueKey('flange-new'),
              tooltip: context.tr(pl: 'Nowy protokół', en: 'New protocol'),
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _newProtocol,
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: kArc,
            labelColor: kText,
            unselectedLabelColor: kTextSec,
            tabs: [
              Tab(
                  key: const ValueKey('flange-tab-check'),
                  text: context.tr(pl: 'Protokół', en: 'Protocol')),
              Tab(
                  key: const ValueKey('flange-tab-history'),
                  text: context.tr(
                      pl: 'Historia (${_history.length})',
                      en: 'History (${_history.length})')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [_checkTab(), _historyTab()],
        ),
      ),
    );
  }

  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(
      16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom);

  String get _unitSuffix => _draft.unit == LengthUnit.mm ? 'mm' : 'in';

  Widget _textField(
    TextEditingController c,
    String label, {
    required Key key,
    required ValueChanged<String> onChanged,
    String? helper,
    String? error,
    int maxLines = 1,
  }) =>
      TextField(
        key: key,
        controller: c,
        maxLines: maxLines,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _numField(
    TextEditingController c,
    String label, {
    required Key key,
    required ValueChanged<String> onChanged,
    String? unit,
    String? helper,
    String? error,
    bool decimal = true,
  }) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(decimal: decimal),
        inputFormatters: numberInputFormatters(decimal: decimal),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _checkTab() {
    final en = _en;
    final e = _draft.evaluate();
    return ListView(
      key: const ValueKey('flange-check-list'),
      padding: _pagePadding,
      children: [
        FlangeVerdictBanner(evaluation: e),
        _jointSection(),
        _alignmentSection(e, en),
        _tolerancesSection(en),
        _checklistSection(e, en),
        QuoteSection(
          title: context.tr(pl: 'Uwagi', en: 'Notes'),
          children: [
            _textField(
              _notes,
              context.tr(pl: 'Uwagi do protokołu', en: 'Protocol notes'),
              key: const ValueKey('flange-notes'),
              maxLines: 4,
              onChanged: (v) => _update(_draft.copyWith(notes: v)),
            ),
          ],
        ),
        _actionsSection(),
      ],
    );
  }

  Widget _jointSection() {
    final j = _draft.joint;
    final boltsInvalid =
        j.boltCount != null && !isValidBoltCount(j.boltCount!) ||
            (_boltCount.text.trim().isNotEmpty && j.boltCount == null);
    final gasketInvalid =
        j.gasketThicknessMm != null && !(j.gasketThicknessMm! > 0);
    final catalog = _catalogBolts;
    return QuoteSection(
      title: context.tr(pl: 'Dane połączenia', en: 'Joint data'),
      children: [
        _textField(
          _tag,
          context.tr(
              pl: 'Oznaczenie (nr linii / kołnierza)',
              en: 'Tag (line / flange no.)'),
          key: const ValueKey('flange-tag'),
          error: _tagError && j.tag.trim().isEmpty
              ? context.tr(pl: 'Wymagane do zapisu', en: 'Required to save')
              : null,
          onChanged: (v) => _updateJoint(_draft.joint.copyWith(tag: v)),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: const ValueKey('flange-dn'),
          child: DropdownButtonFormField<int?>(
            // Nowy klucz przy zmianie protokołu/DN — pole pokazuje wartość
            // z modelu (initialValue czytane tylko przy tworzeniu).
            key: ValueKey('flange-dn-${_draft.id}-${j.dn ?? 0}'),
            initialValue: j.dn,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'DN / NPS', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('—')),
              for (final (dn, _) in kFlangeSizes)
                DropdownMenuItem<int?>(
                    value: dn, child: Text(flangeSizeLabel(dn))),
            ],
            onChanged: _setDn,
          ),
        ),
        const SizedBox(height: 12),
        _textField(
          _rating,
          context.tr(pl: 'Klasa / PN', en: 'Class / PN'),
          key: const ValueKey('flange-rating'),
          helper: context.tr(
              pl: 'np. 300, CL600, PN40', en: 'e.g. 300, CL600, PN40'),
          onChanged: (v) => setState(() {
            _draft = _draft.copyWith(joint: _draft.joint.copyWith(rating: v));
            _dirty = true;
            _autofillBolts();
          }),
        ),
        const SizedBox(height: 12),
        _textField(
          _gasketType,
          context.tr(pl: 'Typ uszczelki', en: 'Gasket type'),
          key: const ValueKey('flange-gasket-type'),
          helper: context.tr(
              pl: 'np. spiralna z pierścieniem wewn., płaska 3 mm',
              en: 'e.g. spiral-wound with inner ring, 3 mm sheet'),
          onChanged: (v) => _updateJoint(_draft.joint.copyWith(gasketType: v)),
        ),
        const SizedBox(height: 12),
        _numField(
          _gasketT,
          context.tr(pl: 'Grubość uszczelki', en: 'Gasket thickness'),
          key: const ValueKey('flange-gasket-t'),
          unit: _unitSuffix,
          helper: context.tr(
              pl: 'Przed ściśnięciem — do kryterium nadmiernej szczeliny.',
              en: 'Uncompressed — for the excessive spacing check.'),
          error: gasketInvalid
              ? problemLabel(FlangeDataProblem.gasketThickness, en: _en)
              : null,
          onChanged: (v) => _updateJoint(
              _draft.joint.copyWith(gasketThicknessMm: () => _mm(v))),
        ),
        const SizedBox(height: 12),
        _textField(
          _boltGrade,
          context.tr(pl: 'Gatunek śrub / nakrętek', en: 'Stud / nut grade'),
          key: const ValueKey('flange-bolt-grade'),
          helper: context.tr(
              pl: 'np. A193 B7 / A194 2H', en: 'e.g. A193 B7 / A194 2H'),
          onChanged: (v) => _updateJoint(_draft.joint.copyWith(boltGrade: v)),
        ),
        const SizedBox(height: 12),
        _numField(
          _boltCount,
          context.tr(pl: 'Liczba śrub', en: 'Number of bolts'),
          key: const ValueKey('flange-bolt-count'),
          decimal: false,
          helper: catalog == null
              ? context.tr(
                  pl: '$kMinBolts–$kMaxBolts, wielokrotność 4',
                  en: '$kMinBolts–$kMaxBolts, a multiple of 4')
              : context.tr(
                  pl: 'ASME B16.5 dla tego DN i klasy: $catalog',
                  en: 'ASME B16.5 for this DN and class: $catalog'),
          error: boltsInvalid
              ? problemLabel(FlangeDataProblem.boltCount, en: _en)
              : null,
          onChanged: (v) => _updateJoint(
              _draft.joint.copyWith(boltCount: () => int.tryParse(v))),
        ),
        const SizedBox(height: 12),
        _textField(
          _location,
          context.tr(pl: 'Miejsce / projekt', en: 'Location / project'),
          key: const ValueKey('flange-location'),
          onChanged: (v) => _updateJoint(_draft.joint.copyWith(location: v)),
        ),
        const SizedBox(height: 12),
        _textField(
          _fitter,
          context.tr(pl: 'Monter', en: 'Fitter'),
          key: const ValueKey('flange-fitter'),
          onChanged: (v) => _updateJoint(_draft.joint.copyWith(fitter: v)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('flange-date'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(kMinTapTarget),
            foregroundColor: kText,
            side: const BorderSide(color: kBorder),
            alignment: Alignment.centerLeft,
          ),
          onPressed: _pickDate,
          icon: const Icon(Icons.event_outlined),
          label: Text('${context.tr(pl: 'Data', en: 'Date')}: '
              '${j.date.isEmpty ? '—' : j.date}'),
        ),
      ],
    );
  }

  Widget _alignmentSection(FlangeEvaluation e, bool en) {
    final m = _draft.measurements;
    final u = _draft.unit;
    String line(FlangeCriterion c) =>
        criterionValueLine(_draft, e.of(c), en: en);
    return QuoteSection(
      title: context.tr(pl: 'Pomiary osiowania', en: 'Alignment checks'),
      subtitle: context.tr(
          pl: 'Przed skręceniem, kołnierze w spoczynku. Wg $kPcc1Edition zał. E.',
          en: 'Before bolting up, flanges at rest. Per $kPcc1Edition Appendix E.'),
      children: [
        SegmentedButton<LengthUnit>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: LengthUnit.mm,
                label: Text('mm', key: const ValueKey('flange-unit-mm'))),
            ButtonSegment(
                value: LengthUnit.inch,
                label: Text(context.tr(pl: 'cale', en: 'inches'),
                    key: const ValueKey('flange-unit-inch'))),
          ],
          selected: {u},
          onSelectionChanged: (s) => _setUnit(s.first),
        ),
        const SizedBox(height: 14),
        CriterionTile(
          result: e.of(FlangeCriterion.centerline),
          valueLine: line(FlangeCriterion.centerline),
          input: _numField(
            _centerline,
            context.tr(pl: 'Przesunięcie osi', en: 'Centerline offset'),
            key: const ValueKey('flange-centerline'),
            unit: _unitSuffix,
            onChanged: (v) => _updateMeasurements(
                _draft.measurements.copyWith(centerlineMm: () => _mm(v))),
          ),
        ),
        CriterionTile(
          result: e.of(FlangeCriterion.rotation),
          valueLine: line(FlangeCriterion.rotation),
          input: _numField(
            _rotation,
            context.tr(pl: 'Przesunięcie otworów', en: 'Bolt-hole offset'),
            key: const ValueKey('flange-rotation'),
            unit: _unitSuffix,
            onChanged: (v) => _updateMeasurements(
                _draft.measurements.copyWith(rotationMm: () => _mm(v))),
          ),
        ),
        const Divider(height: 20),
        Text(
          context.tr(
              pl: 'Szczelina między powierzchniami — punkty po obwodzie',
              en: 'Gap between the faces — points round the circumference'),
          style: const TextStyle(
              fontSize: 14.5, fontWeight: FontWeight.w700, color: kText),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final n in kGapPointCounts)
              ButtonSegment(
                  value: n,
                  label: Text(context.tr(pl: '$n punktów', en: '$n points'),
                      key: ValueKey('flange-points-$n'))),
          ],
          selected: {m.gapPointCount},
          onSelectionChanged: (s) => _setGapPoints(s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            context.tr(
                pl: '0° = góra (godz. 12), dalej zgodnie z zegarem. Dla DN ≥ '
                    '$kEightPointMinDn — 8 punktów (PCC-1 §11.3: przy '
                    'dokręcaniu ≥ 8 miejsc).',
                en: '0° = top (12 o’clock), then clockwise. For DN ≥ '
                    '$kEightPointMinDn — 8 points (PCC-1 §11.3: ≥ 8 places '
                    'while tightening).'),
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35),
          ),
        ),
        _gapGrid(m),
        const SizedBox(height: 12),
        CriterionTile(
          result: e.of(FlangeCriterion.parallelism),
          valueLine: line(FlangeCriterion.parallelism),
        ),
        CriterionTile(
          result: e.of(FlangeCriterion.spacing),
          valueLine: line(FlangeCriterion.spacing),
        ),
        const Divider(height: 20),
        CriterionTile(
          result: e.of(FlangeCriterion.force),
          valueLine: line(FlangeCriterion.force),
          input: Column(
            children: [
              for (final f in AlignmentForce.values)
                ChoiceRow(
                  key: ValueKey('flange-force-${f.name}'),
                  selected: m.force == f,
                  color: f == AlignmentForce.light ? kPass : kFail,
                  label: forceLabel(f, en: en),
                  onTap: () => _updateMeasurements(_draft.measurements.copyWith(
                      force: () => _draft.measurements.force == f ? null : f)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gapGrid(FlangeMeasurements m) {
    final n = m.gapPointCount;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 440 ? 4 : 2;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 10,
        children: [
          for (var i = 0; i < n; i++)
            SizedBox(
              width: w,
              child: _numField(
                _gaps[i],
                '${fmtNum(gapPointAngle(i, n), decimals: 0, en: _en)}°',
                key: ValueKey('flange-gap-$i'),
                unit: _unitSuffix,
                onChanged: (v) =>
                    _updateMeasurements(_draft.measurements.withGap(i, _mm(v))),
              ),
            ),
        ],
      );
    });
  }

  Widget _tolerancesSection(bool en) {
    final t = _draft.tolerances;
    final u = _draft.unit;
    void setLimit(String v, FlangeTolerances Function(DualLimit) apply) {
      final value = parseDecimal(v) ?? 0;
      _update(_draft.copyWith(tolerances: apply(DualLimit.entered(value, u))));
    }

    String? err(DualLimit l) => l.isValid
        ? null
        : context.tr(pl: 'Wpisz wartość > 0', en: 'Enter a value > 0');
    return QuoteSection(
      title: context.tr(pl: 'Tolerancje', en: 'Tolerances'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      children: [
        ExpansionTile(
          key: const ValueKey('flange-tol-tile'),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          title: Text(
            t.isPcc1
                ? context.tr(
                    pl: '$kPcc1Edition zał. E', en: '$kPcc1Edition Appendix E')
                : context.tr(
                    pl: 'Własne (specyfikacja zakładu)',
                    en: 'Custom (plant specification)'),
            key: const ValueKey('flange-tol-title'),
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: t.isPcc1 ? kText : kWarn),
          ),
          subtitle: Text(
            '${formatLimit(t.centerline, u, en: en)} · '
            '${formatLimit(t.parallelism, u, en: en)} · '
            '${formatLimit(t.rotation, u, en: en)} · '
            '${fmtNum(t.gapFactor, en: en)} × ${context.tr(pl: 'uszczelka', en: 'gasket')}',
            style: const TextStyle(fontSize: 12, color: kTextSec),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            Text(
              context.tr(
                  pl: 'Domyślnie $kPcc1Edition zał. E. Wydanie 2022 przebudowało '
                      'załącznik — źródła podają te same liczby, ale aplikacja '
                      'trzyma się wydania 2019. Specyfikacja zakładu bywa '
                      'ostrzejsza: wpisz jej wartości. Granice w mm i calach są '
                      'jak w normie (1/16" to nie dokładnie 1,5 mm) — ocena '
                      'w jednostce pomiaru.',
                  en: 'Default: $kPcc1Edition Appendix E. The 2022 edition '
                      'restructured the appendix — sources give the same '
                      'numbers, but the app follows the 2019 edition. A plant '
                      'specification may be stricter: enter its values. mm and '
                      'inch limits are as in the standard (1/16" is not exactly '
                      '1.5 mm) — judged in the unit measured.'),
              style:
                  const TextStyle(fontSize: 12, color: kTextMut, height: 1.35),
            ),
            const SizedBox(height: 12),
            _numField(
              _tolCenter,
              criterionTitle(FlangeCriterion.centerline, en: en),
              key: const ValueKey('flange-tol-centerline'),
              unit: _unitSuffix,
              error: err(t.centerline),
              onChanged: (v) =>
                  setLimit(v, (l) => _draft.tolerances.copyWith(centerline: l)),
            ),
            const SizedBox(height: 10),
            _numField(
              _tolPar,
              criterionTitle(FlangeCriterion.parallelism, en: en),
              key: const ValueKey('flange-tol-parallelism'),
              unit: _unitSuffix,
              error: err(t.parallelism),
              onChanged: (v) => setLimit(
                  v, (l) => _draft.tolerances.copyWith(parallelism: l)),
            ),
            const SizedBox(height: 10),
            _numField(
              _tolRot,
              criterionTitle(FlangeCriterion.rotation, en: en),
              key: const ValueKey('flange-tol-rotation'),
              unit: _unitSuffix,
              error: err(t.rotation),
              onChanged: (v) =>
                  setLimit(v, (l) => _draft.tolerances.copyWith(rotation: l)),
            ),
            const SizedBox(height: 10),
            _numField(
              _tolFactor,
              context.tr(
                  pl: 'Największa szczelina ≤ … × grubość uszczelki',
                  en: 'Largest gap ≤ … × gasket thickness'),
              key: const ValueKey('flange-tol-factor'),
              unit: '×',
              error: t.gapFactor > 0
                  ? null
                  : context.tr(
                      pl: 'Wpisz wartość > 0', en: 'Enter a value > 0'),
              onChanged: (v) => _update(_draft.copyWith(
                  tolerances: _draft.tolerances
                      .copyWith(gapFactor: parseDecimal(v) ?? 0))),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('flange-tol-reset'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinTapTarget)),
              onPressed: t.isPcc1
                  ? null
                  : () => setState(() {
                        _draft =
                            _draft.copyWith(tolerances: FlangeTolerances.pcc1);
                        _dirty = true;
                        _bindTolerances();
                      }),
              icon: const Icon(Icons.restore),
              label:
                  Text(context.tr(pl: 'Przywróć PCC-1', en: 'Restore PCC-1')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _checklistSection(FlangeEvaluation e, bool en) {
    return QuoteSection(
      title:
          context.tr(pl: 'Lista kontrolna montażu', en: 'Assembly checklist'),
      subtitle: context.tr(
          pl: 'Odhacz dopiero, gdy sprawdzone na obiekcie.',
          en: 'Tick only once checked on site.'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      children: [
        for (final i in FlangeChecklistItem.values)
          CheckboxListTile(
            key: ValueKey('flange-item-${i.name}'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            value: _draft.checked.contains(i),
            activeColor: kPass,
            checkColor: Colors.black,
            onChanged: (v) {
              final next = {..._draft.checked};
              if (v ?? false) {
                next.add(i);
              } else {
                next.remove(i);
              }
              _update(_draft.copyWith(checked: next));
            },
            title: Text(checklistTitle(i, en: en),
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text(checklistHint(i, en: en),
                style: const TextStyle(
                    fontSize: 12, color: kTextMut, height: 1.35)),
          ),
        ExpansionTile(
          key: const ValueKey('flange-defects'),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          title: Text(
              context.tr(
                  pl: 'PCC-1 zał. D — dopuszczalne rysy i wżery',
                  en: 'PCC-1 Appendix D — allowable scratches and pits'),
              style: const TextStyle(fontSize: 13.5, color: kTextSec)),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: const [DefectDepthTable()],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(
            key: const ValueKey('flange-torque'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _openBoltTorque,
            icon: const Icon(Icons.build_outlined),
            label: Text(context.tr(
                pl: 'Moment śrub — kalkulator',
                en: 'Bolt torque — calculator')),
          ),
        ),
      ],
    );
  }

  Widget _actionsSection() {
    return QuoteSection(
      title: context.tr(pl: 'Protokół', en: 'Protocol'),
      children: [
        FilledButton.icon(
          key: const ValueKey('flange-save'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: kArc,
            foregroundColor: kOnArc,
          ),
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(context.tr(pl: 'Zapisz protokół', en: 'Save protocol'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('flange-share-text'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _sharing
                    ? null
                    : () => _share(_draft, FlangeShareFormat.text),
                icon: const Icon(Icons.share_outlined),
                label: Text(context.tr(pl: 'Tekst', en: 'Text')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('flange-share-pdf'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _sharing
                    ? null
                    : () => _share(_draft, FlangeShareFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _historyTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kArc));
    }
    final sorted = [..._history]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ListView(
      key: const ValueKey('flange-history-list'),
      padding: _pagePadding,
      children: [
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              context.tr(
                  pl: 'Brak zapisanych protokołów. Wypełnij protokół i dotknij '
                      '„Zapisz protokół”.',
                  en: 'No saved protocols yet. Fill in the protocol and tap '
                      '“Save protocol”.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSec),
            ),
          ),
        for (final c in sorted)
          FlangeHistoryCard(
            key: ValueKey('flange-h-${c.id}'),
            check: c,
            onOpen: () => unawaited(_openDraft(c)),
            onDuplicate: () => unawaited(_duplicate(c)),
            onShareText: () => unawaited(_share(c, FlangeShareFormat.text)),
            onSharePdf: () => unawaited(_share(c, FlangeShareFormat.pdf)),
            onDelete: () => unawaited(_delete(c)),
          ),
      ],
    );
  }
}
