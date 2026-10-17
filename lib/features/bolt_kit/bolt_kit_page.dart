// Śruby do kołnierzy: długość szpilek (ASME B16.5 z tabeli albo z wymiarów
// dowolnych kołnierzy) i komplet do zamówienia — szpilki, nakrętki (2 na
// szpilkę), uszczelki, zapas % w górę. Lista połączeń w SharedPreferences
// (bez zmian w bazie), udostępnianie tekst / PDF, przejście do „Moment śrub”.
//
// Liczby i źródła tabel: lib/domain/bolting/stud_length.dart i bolt_kit.dart.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/bolting/bolt_kit.dart';
import '../../i18n/app_language.dart';
import '../../screens/bolt_torque_screen.dart';
import '../../services/bolt_kit_export.dart';
import '../../services/flange_catalog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart';
import 'bolt_kit_store.dart';

/// Otwarcie „Moment śrub” dla [joint] (z listy albo wybranego w zakładce
/// „Długość”).
typedef BoltKitTorqueFn = void Function(
    BuildContext context, BoltKitJoint joint);

enum _LengthMode { asme, dims }

class BoltKitPage extends StatefulWidget {
  /// Udostępnianie zamówienia — test podmienia, żeby nie wołać platformy.
  final BoltKitShareFn share;
  final BoltKitStore store;

  /// Przejście do „Moment śrub”. Domyślnie [BoltTorqueScreen] — jego
  /// konstruktor nie przyjmuje parametrów, więc DN / klasę / gatunek
  /// podpowiada komunikat.
  final BoltKitTorqueFn? openTorque;

  const BoltKitPage({
    super.key,
    this.share = shareBoltKit,
    this.store = const BoltKitStore(),
    this.openTorque,
  });

  @override
  State<BoltKitPage> createState() => _BoltKitPageState();
}

class _BoltKitPageState extends State<BoltKitPage>
    with SingleTickerProviderStateMixin {
  static int _seq = 0;

  late final TabController _tabs = TabController(length: 2, vsync: this);

  _LengthMode _mode = _LengthMode.asme;

  // ── ASME B16.5 ────────────────────────────────────────────────────────────
  int _dn = 100;
  int _cls = 150;
  FlangeFacing _facing = FlangeFacing.rf;
  BoltMaterial _material = BoltMaterial.b7;
  RfGasket _gasket = RfGasket.spiralWound;
  final _count = TextEditingController(text: '1');

  // ── Z wymiarów ────────────────────────────────────────────────────────────
  final _f1 = TextEditingController();
  final _f2 = TextEditingController();
  final _gasketT = TextEditingController();
  final _nut = TextEditingController();
  final _protrusion = TextEditingController();
  final _washerT = TextEditingController();
  int _washers = 0;
  LengthSeries _series = LengthSeries.mm5;

  // ── Komplet ───────────────────────────────────────────────────────────────
  List<BoltKitJoint> _joints = [];
  int _spare = 0;
  bool _loading = true;
  bool _damaged = false;
  bool _sharing = false;
  Future<void> _saveChain = Future<void>.value();

  bool get _en => context.language == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final loaded = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _joints = [...loaded.state.joints];
      _spare = loaded.state.sparePercent;
      _damaged = loaded.damaged;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_count, _f1, _f2, _gasketT, _nut, _protrusion, _washerT]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Akcje ─────────────────────────────────────────────────────────────────

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Zapis po każdej zmianie listy; zapisy idą po kolei (nowszy nigdy nie
  /// zostanie nadpisany starszym).
  void _persist() {
    final snapshot =
        BoltKitState(joints: List.unmodifiable(_joints), sparePercent: _spare);
    _saveChain = _saveChain.then((_) async {
      try {
        await widget.store.save(snapshot);
      } catch (_) {
        if (mounted) {
          _snack(context.tr(
              pl: 'Nie udało się zapisać listy na telefonie.',
              en: 'Could not save the list on the phone.'));
        }
      }
    });
  }

  void _setJoints(List<BoltKitJoint> next) {
    setState(() => _joints = next);
    _persist();
  }

  int? get _countValue {
    final n = int.tryParse(_count.text.trim());
    return n != null && isValidJointCount(n) ? n : null;
  }

  String _newId() => 'bk-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  void _add() {
    final n = _countValue;
    if (n == null || _loading) return;
    final draft = BoltKitJoint(
      id: _newId(),
      dn: _dn,
      cls: _cls,
      facing: _facing,
      material: _material,
      gasket: _gasket,
      count: n,
    );
    if (draft.stud == null) return;
    final next = [..._joints];
    final i = next.indexWhere((j) => j.sameKindAs(draft));
    if (i >= 0) {
      final total = next[i].count + n;
      if (!isValidJointCount(total)) {
        _snack(context.tr(
            pl: 'Za dużo połączeń jednego rodzaju (najwyżej $kMaxJointCount).',
            en: 'Too many joints of one kind (at most $kMaxJointCount).'));
        return;
      }
      next[i] = next[i].copyWith(count: total);
    } else {
      next.add(draft);
    }
    _setJoints(next);
    _snack(
      context.tr(
          pl: 'Dodano: $n × ${jointTitle(draft)}',
          en: 'Added: $n × ${jointTitle(draft)}'),
      action: SnackBarAction(
        label: context.tr(pl: 'Pokaż', en: 'Show'),
        onPressed: () => _tabs.animateTo(1),
      ),
    );
  }

  void _changeCount(BoltKitJoint j, int delta) {
    final n = j.count + delta;
    if (!isValidJointCount(n)) return;
    _setJoints([
      for (final x in _joints) x.id == j.id ? x.copyWith(count: n) : x,
    ]);
  }

  void _delete(BoltKitJoint j) {
    final index = _joints.indexWhere((x) => x.id == j.id);
    if (index < 0) return;
    _setJoints([..._joints]..removeAt(index));
    _snack(
      context.tr(
          pl: 'Usunięto: ${jointTitle(j)}', en: 'Removed: ${jointTitle(j)}'),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        onPressed: () {
          if (!mounted || _joints.any((x) => x.id == j.id)) return;
          _setJoints([..._joints]..insert(index.clamp(0, _joints.length), j));
        },
      ),
    );
  }

  void _setSpare(int p) {
    if (p == _spare) return;
    setState(() => _spare = p);
    _persist();
  }

  Future<void> _share(BoltKitOrder o, BoltKitShareFormat f) async {
    if (_sharing || o.isEmpty) return;
    setState(() => _sharing = true);
    try {
      await widget.share(o, f, _en);
    } catch (_) {
      if (mounted) {
        _snack(context.tr(
            pl: 'Nie udało się udostępnić zamówienia.',
            en: 'Could not share the order.'));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openTorque(BoltKitJoint j) {
    final custom = widget.openTorque;
    if (custom != null) {
      custom(context, j);
      return;
    }
    final grade = j.material.torqueGrade;
    final what = '${jointSizeLabel(j.dn)} · Class ${j.cls}'
        '${grade == null ? '' : ' · $grade'}';
    _snack(grade == null
        ? context.tr(
            pl: 'W „Moment śrub” ustaw: $what (gatunku ${j.material.stud} '
                'nie ma w kalkulatorze).',
            en: 'In “Bolt torque” set: $what (${j.material.stud} is not in '
                'the calculator).')
        : context.tr(
            pl: 'W „Moment śrub” ustaw: $what.',
            en: 'In “Bolt torque” set: $what.'));
    unawaited(Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BoltTorqueScreen())));
  }

  BoltKitJoint get _selectedJoint => BoltKitJoint(
        id: 'selected',
        dn: _dn,
        cls: _cls,
        facing: _facing,
        material: _material,
        gasket: _gasket,
        count: _countValue ?? 1,
      );

  // ── Budowa ekranu ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final total = _joints.fold<int>(0, (s, j) => s + j.count);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(pl: 'Śruby do kołnierzy', en: 'Flange bolting'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: kArc,
          labelColor: kText,
          unselectedLabelColor: kTextSec,
          tabs: [
            Tab(
                key: const ValueKey('bk-tab-length'),
                text: context.tr(pl: 'Długość', en: 'Length')),
            Tab(
                key: const ValueKey('bk-tab-kit'),
                text: context.tr(pl: 'Komplet ($total)', en: 'Kit ($total)')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_lengthTab(), _kitTab()],
      ),
    );
  }

  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(
      16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom);

  TextStyle get _hint =>
      const TextStyle(fontSize: 12, color: kTextMut, height: 1.35);

  Widget _lengthTab() {
    return ListView(
      key: const ValueKey('bk-length-list'),
      padding: _pagePadding,
      children: [
        SegmentedButton<_LengthMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: _LengthMode.asme,
                label: Text('ASME B16.5', key: const ValueKey('bk-mode-asme'))),
            ButtonSegment(
                value: _LengthMode.dims,
                label: Text(context.tr(pl: 'Z wymiarów', en: 'Dimensions'),
                    key: const ValueKey('bk-mode-dims'))),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        if (_mode == _LengthMode.asme) ...[
          _asmeSection(),
          _addSection(),
        ] else
          ..._dimsSections(),
      ],
    );
  }

  // ── ASME B16.5 ────────────────────────────────────────────────────────────

  Widget _asmeSection() {
    final en = _en;
    final lookup = lookupAsmeStud(_dn, _cls, _facing);
    return QuoteSection(
      title: context.tr(pl: 'Połączenie ASME B16.5', en: 'ASME B16.5 joint'),
      subtitle: context.tr(
          pl: 'Liczba i średnica szpilek z ASME B16.5 (jak w „Moment śrub”), '
              'długość z tabel B16.5.',
          en: 'Stud count and diameter per ASME B16.5 (as in “Bolt torque”), '
              'length from the B16.5 tables.'),
      children: [
        KeyedSubtree(
          key: const ValueKey('bk-dn'),
          child: DropdownButtonFormField<int>(
            key: ValueKey('bk-dn-$_dn'),
            initialValue: _dn,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'DN / NPS', border: OutlineInputBorder()),
            items: [
              for (final dn in FlangeCatalog.dns)
                DropdownMenuItem(value: dn, child: Text(jointSizeLabel(dn))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _dn = v);
            },
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: const ValueKey('bk-class'),
          child: DropdownButtonFormField<int>(
            key: ValueKey('bk-class-$_cls'),
            initialValue: _cls,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: context.tr(pl: 'Klasa', en: 'Class'),
                border: const OutlineInputBorder()),
            items: [
              for (final c in FlangeCatalog.classes)
                DropdownMenuItem(value: c, child: Text('Class $c')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _cls = v);
            },
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<FlangeFacing>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: FlangeFacing.rf,
                label: Text(context.tr(pl: 'RF (przylga)', en: 'RF'),
                    key: const ValueKey('bk-facing-rf'))),
            ButtonSegment(
                value: FlangeFacing.rtj,
                label: Text('RTJ', key: const ValueKey('bk-facing-rtj'))),
          ],
          selected: {_facing},
          onSelectionChanged: (s) => setState(() => _facing = s.first),
        ),
        const SizedBox(height: 14),
        switch (lookup) {
          StudFound(:final stud) => _asmeResult(stud, en),
          StudNotFound(:final problem) => QuoteNotice(
              key: const ValueKey('bk-asme-problem'),
              color: kFail,
              icon: Icons.block,
              text: switch (problem) {
                StudLookupProblem.notInCatalog => context.tr(
                    pl: 'DN$_dn × Class $_cls nie ma w tabeli aplikacji '
                        '(DN15–DN300, Class 150–1500) — policz długość '
                        'z wymiarów.',
                    en: 'DN$_dn × Class $_cls is not in the app table '
                        '(DN15–DN300, Class 150–1500) — calculate the length '
                        'from dimensions.'),
                StudLookupProblem.noRtj => context.tr(
                    pl: 'ASME B16.5 nie przewiduje RTJ dla Class 150 NPS ½ '
                        'i ¾ — wybierz RF.',
                    en: 'ASME B16.5 has no RTJ for Class 150 NPS ½ and ¾ — '
                        'choose RF.'),
              },
            ),
        },
      ],
    );
  }

  Widget _asmeResult(AsmeStud s, bool en) {
    final ring =
        s.facing == FlangeFacing.rtj ? ringJointNumber(s.dn, s.cls) : null;
    final note = studLengthSourceNote(s.dn, s.cls, s.facing, en: en);
    return Material(
      key: const ValueKey('bk-asme-result'),
      color: kBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: kGold.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                  pl: 'Szpilka (średnica × długość)',
                  en: 'Stud (diameter × length)'),
              style: const TextStyle(fontSize: 12, color: kTextSec),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                studDesignation(s.size, s.lengthQuarterIn),
                key: const ValueKey('bk-asme-length'),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900, color: kGold),
              ),
            ),
            Text(
              context.tr(
                  pl: 'długość ${formatMm(s.lengthMm, decimals: 2, en: en)}',
                  en: 'length ${formatMm(s.lengthMm, decimals: 2, en: en)}'),
              key: const ValueKey('bk-asme-mm'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: kText),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                  pl: 'Szpilki: ${s.boltCount} szt. · nakrętki heavy hex: '
                      '${s.nutCount} szt. · gwint ${s.size.threadDesignation}',
                  en: '${s.boltCount} studs · ${s.nutCount} heavy hex nuts · '
                      'thread ${s.size.threadDesignation}'),
              key: const ValueKey('bk-asme-count'),
              style: const TextStyle(fontSize: 13.5, color: kText),
            ),
            if (ring != null)
              Text(
                context.tr(pl: 'Pierścień $ring', en: 'Ring $ring'),
                key: const ValueKey('bk-asme-ring'),
                style: const TextStyle(fontSize: 13.5, color: kText),
              ),
            const SizedBox(height: 6),
            Text(
              s.facing == FlangeFacing.rf
                  ? context.tr(
                      pl: 'Tabela B16.5 zakłada przylgę '
                          '${assumedRaisedFaceInch(s.cls)} '
                          '(${fmtStudNum(assumedRaisedFaceMm(s.cls), en: en)} mm) '
                          'i typową uszczelkę. Długość bez ścięć (końcówek).',
                      en: 'The B16.5 table assumes a '
                          '${assumedRaisedFaceInch(s.cls)} '
                          '(${fmtStudNum(assumedRaisedFaceMm(s.cls), en: en)} mm) '
                          'raised face and a typical gasket. Length without '
                          'points.')
                  : context.tr(
                      pl: 'Długość B16.5 dla połączenia RTJ (pierścień w '
                          'rowkach). Długość bez ścięć (końcówek).',
                      en: 'B16.5 length for an RTJ joint (ring in the '
                          'grooves). Length without points.'),
              style: _hint,
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              QuoteNotice(
                key: const ValueKey('bk-asme-source-note'),
                text: note,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addSection() {
    final countInvalid = _count.text.trim().isNotEmpty && _countValue == null;
    final canAdd = !_loading &&
        _countValue != null &&
        lookupAsmeStud(_dn, _cls, _facing) is StudFound;
    final en = _en;
    return QuoteSection(
      title: context.tr(pl: 'Do kompletu', en: 'To the kit'),
      children: [
        KeyedSubtree(
          key: const ValueKey('bk-material'),
          child: DropdownButtonFormField<BoltMaterial>(
            key: ValueKey('bk-material-${_material.name}'),
            initialValue: _material,
            isExpanded: true,
            decoration: InputDecoration(
                labelText:
                    context.tr(pl: 'Szpilki / nakrętki', en: 'Studs / nuts'),
                border: const OutlineInputBorder()),
            items: [
              for (final m in BoltMaterial.values)
                DropdownMenuItem(
                    value: m,
                    child: Text(m.pair,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _material = v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(_materialHint(_material), style: _hint),
        ),
        if (_facing == FlangeFacing.rf) ...[
          KeyedSubtree(
            key: const ValueKey('bk-gasket'),
            child: DropdownButtonFormField<RfGasket>(
              key: ValueKey('bk-gasket-${_gasket.name}'),
              initialValue: _gasket,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: context.tr(pl: 'Uszczelka', en: 'Gasket'),
                  border: const OutlineInputBorder()),
              items: [
                for (final g in RfGasket.values)
                  DropdownMenuItem(
                      value: g,
                      child: Text(rfGasketLabel(g, en: en),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _gasket = v);
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const ValueKey('bk-count'),
          controller: _count,
          keyboardType: numberKeyboard(decimal: false),
          inputFormatters: numberInputFormatters(decimal: false),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Liczba takich połączeń', en: 'Number of such joints'),
            errorText: countInvalid || _count.text.trim().isEmpty
                ? context.tr(
                    pl: 'Wpisz liczbę 1–$kMaxJointCount',
                    en: 'Enter a number 1–$kMaxJointCount')
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('bk-add'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: kArc,
            foregroundColor: kOnArc,
          ),
          onPressed: canAdd ? _add : null,
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(context.tr(pl: 'Dodaj do kompletu', en: 'Add to the kit'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('bk-torque'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: () => _openTorque(_selectedJoint),
          icon: const Icon(Icons.build_outlined),
          label: Text(context.tr(
              pl: 'Moment śrub — kalkulator', en: 'Bolt torque — calculator')),
        ),
      ],
    );
  }

  String _materialHint(BoltMaterial m) => switch (m) {
        BoltMaterial.b7 => context.tr(
            pl: 'Stal stopowa — ogólne zastosowanie.',
            en: 'Alloy steel — general service.'),
        BoltMaterial.b7m => context.tr(
            pl: 'Obniżona twardość — środowisko kwaśne (NACE).',
            en: 'Reduced hardness — sour service (NACE).'),
        BoltMaterial.b8m => context.tr(
            pl: 'Nierdzewna 316 — korozja, niższa wytrzymałość.',
            en: 'Stainless 316 — corrosion, lower strength.'),
        BoltMaterial.l7 =>
          context.tr(pl: 'Niskie temperatury.', en: 'Low temperature service.'),
      };

  // ── Z wymiarów ────────────────────────────────────────────────────────────

  StudDimensionsOutcome get _dimsOutcome => computeStudLength(
        flange1Mm: parseDecimal(_f1.text),
        flange2Mm: parseDecimal(_f2.text),
        gasketMm: parseDecimal(_gasketT.text),
        nutMm: parseDecimal(_nut.text),
        protrusionMm: parseDecimal(_protrusion.text),
        washers: _washers,
        washerMm: parseDecimal(_washerT.text),
        series: _series,
      );

  String _fieldName(StudInputField f) => switch (f) {
        StudInputField.flange1 =>
          context.tr(pl: 'grubość kołnierza 1', en: 'flange 1 thickness'),
        StudInputField.flange2 =>
          context.tr(pl: 'grubość kołnierza 2', en: 'flange 2 thickness'),
        StudInputField.gasket =>
          context.tr(pl: 'grubość uszczelki', en: 'gasket thickness'),
        StudInputField.nut =>
          context.tr(pl: 'wysokość nakrętki', en: 'nut height'),
        StudInputField.protrusion =>
          context.tr(pl: 'wystawanie gwintu', en: 'thread protrusion'),
        StudInputField.washer =>
          context.tr(pl: 'grubość podkładki', en: 'washer thickness'),
      };

  /// Błąd pola: tylko gdy coś wpisano i jest złe (puste pole nie świeci na
  /// czerwono — ale też nie daje wyniku).
  String? _fieldError(
      TextEditingController c, StudInputField f, StudDimensionsOutcome o) {
    if (c.text.trim().isEmpty) return null;
    if (o is! StudDimensionsInvalid || !o.fields.contains(f)) return null;
    if (parseDecimal(c.text) == null) {
      return context.tr(pl: 'Wpisz liczbę', en: 'Enter a number');
    }
    final en = _en;
    String mm(double v) => fmtStudNum(v, en: en);
    return switch (f) {
      StudInputField.flange1 || StudInputField.flange2 => context.tr(
          pl: 'Wpisz wartość > 0, najwyżej ${mm(kMaxFlangeMm)} mm',
          en: 'Enter a value > 0, at most ${mm(kMaxFlangeMm)} mm'),
      StudInputField.gasket => context.tr(
          pl: 'Wpisz 0–${mm(kMaxGasketMm)} mm',
          en: 'Enter 0–${mm(kMaxGasketMm)} mm'),
      StudInputField.nut => context.tr(
          pl: 'Wpisz wartość > 0, najwyżej ${mm(kMaxNutMm)} mm',
          en: 'Enter a value > 0, at most ${mm(kMaxNutMm)} mm'),
      StudInputField.protrusion => context.tr(
          pl: 'Wpisz 0–${mm(kMaxProtrusionMm)} mm',
          en: 'Enter 0–${mm(kMaxProtrusionMm)} mm'),
      StudInputField.washer => context.tr(
          pl: 'Wpisz wartość > 0, najwyżej ${mm(kMaxWasherMm)} mm',
          en: 'Enter a value > 0, at most ${mm(kMaxWasherMm)} mm'),
    };
  }

  Widget _mmField(
    TextEditingController c,
    String label, {
    required Key key,
    required StudInputField field,
    required StudDimensionsOutcome outcome,
    String? helper,
  }) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          helperText: helper,
          helperMaxLines: 5,
          errorText: _fieldError(c, field, outcome),
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      );

  List<Widget> _dimsSections() {
    final o = _dimsOutcome;
    final en = _en;
    return [
      QuoteSection(
        title:
            context.tr(pl: 'Długość z wymiarów', en: 'Length from dimensions'),
        subtitle: context.tr(
            pl: 'Dowolne kołnierze (np. EN 1092-1). Wymiary w mm.\n'
                'L = t1 + t2 + g + 2·m + 2·p + podkładki',
            en: 'Any flanges (e.g. EN 1092-1). Dimensions in mm.\n'
                'L = t1 + t2 + g + 2·m + 2·p + washers'),
        children: [
          _mmField(
              _f1,
              context.tr(
                  pl: 'Grubość kołnierza 1 (t1)',
                  en: 'Flange 1 thickness (t1)'),
              key: const ValueKey('bk-f1'),
              field: StudInputField.flange1,
              outcome: o,
              helper: context.tr(
                  pl: 'W miejscu otworów śrub, razem z przylgą.',
                  en: 'At the bolt holes, including the raised face.')),
          const SizedBox(height: 12),
          _mmField(
              _f2,
              context.tr(
                  pl: 'Grubość kołnierza 2 (t2)',
                  en: 'Flange 2 thickness (t2)'),
              key: const ValueKey('bk-f2'),
              field: StudInputField.flange2,
              outcome: o),
          const SizedBox(height: 12),
          _mmField(
              _gasketT,
              context.tr(
                  pl: 'Grubość uszczelki (g)', en: 'Gasket thickness (g)'),
              key: const ValueKey('bk-gasket-t'),
              field: StudInputField.gasket,
              outcome: o,
              helper: context.tr(
                  pl: 'Nominalna, przed ściśnięciem — szpilka wyjdzie dłuższa '
                      'o ściśnięcie (spiralna 4,5 mm → ok. 3 mm), to zapas. '
                      'Przekładkę lub zaślepkę okularową dolicz tutaj.',
                  en: 'Nominal, uncompressed — the stud comes out longer by '
                      'the compression (spiral-wound 4.5 mm → about 3 mm), '
                      'that is margin. Add a spacer or spectacle blind here.')),
          const SizedBox(height: 12),
          _mmField(_nut,
              context.tr(pl: 'Wysokość nakrętki (m)', en: 'Nut height (m)'),
              key: const ValueKey('bk-nut'),
              field: StudInputField.nut,
              outcome: o,
              helper: context.tr(
                  pl: 'Heavy hex 2H (ASME B18.2.2): ≈ d (3/4" → 19,1 mm). '
                      'ISO 4032: ≈ 0,9·d (M20 → 18 mm).',
                  en: 'Heavy hex 2H (ASME B18.2.2): ≈ d (3/4" → 19.1 mm). '
                      'ISO 4032: ≈ 0.9·d (M20 → 18 mm).')),
          const SizedBox(height: 12),
          _mmField(
              _protrusion,
              context.tr(
                  pl: 'Wystawanie za nakrętką (p), z każdej strony',
                  en: 'Protrusion past the nut (p), each side'),
              key: const ValueKey('bk-protrusion'),
              field: StudInputField.protrusion,
              outcome: o,
              helper: context.tr(
                  pl: 'Min. 1 pełny zwój (ASME B31.3 §335.2.3 dopuszcza brak '
                      'najwyżej 1 zwoju; zakłady 1–3 zwoje). Skok: M16 2 mm, '
                      'M20 2,5, M24 3, M30 3,5; 3/4"-10 UNC 2,54 mm.',
                  en: 'At least 1 full thread (ASME B31.3 §335.2.3 accepts '
                      'at most 1 thread short; plants 1–3 threads). Pitch: '
                      'M16 2 mm, M20 2.5, M24 3, M30 3.5; 3/4"-10 UNC 2.54 mm.')),
          const SizedBox(height: 14),
          Text(context.tr(pl: 'Podkładki na szpilkę', en: 'Washers per stud'),
              style: const TextStyle(fontSize: 13.5, color: kTextSec)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final n in kWasherCounts)
                ChoiceChip(
                  key: ValueKey('bk-washers-$n'),
                  label: Text('$n'),
                  selected: _washers == n,
                  onSelected: (_) => setState(() => _washers = n),
                ),
            ],
          ),
          if (_washers > 0) ...[
            const SizedBox(height: 12),
            _mmField(
                _washerT,
                context.tr(
                    pl: 'Grubość podkładki (w)', en: 'Washer thickness (w)'),
                key: const ValueKey('bk-washer-t'),
                field: StudInputField.washer,
                outcome: o,
                helper: context.tr(
                    pl: 'Grubość z dostawy albo z normy podkładki.',
                    en: 'Thickness from the delivery or the washer standard.')),
          ],
          const SizedBox(height: 14),
          Text(
              context.tr(
                  pl: 'Zaokrąglenie w górę do długości handlowej',
                  en: 'Round up to the stock length'),
              style: const TextStyle(fontSize: 13.5, color: kTextSec)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in LengthSeries.values)
                ChoiceChip(
                  key: ValueKey('bk-series-${s.name}'),
                  label: Text(_seriesLabel(s)),
                  selected: _series == s,
                  onSelected: (_) => setState(() => _series = s),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                context.tr(
                    pl: 'Co 5 mm — szpilki cięte z pręta na wymiar; co 10 mm — '
                        'długości katalogowe hurtowni; co 1/4" — szpilki calowe '
                        '(jak tabele ASME B16.5). Zawsze w górę, nigdy w dół.',
                    en: 'Every 5 mm — studs cut from bar to length; every 10 mm '
                        '— stockist catalogue lengths; every 1/4" — inch studs '
                        '(as the ASME B16.5 tables). Always up, never down.'),
                style: _hint),
          ),
        ],
      ),
      switch (o) {
        StudDimensionsOk(:final result) => _dimsResult(result, en),
        StudDimensionsInvalid(:final fields) => QuoteNotice(
            key: const ValueKey('bk-dims-missing'),
            text: context.tr(
                pl: 'Brak wyniku — uzupełnij lub popraw: '
                    '${fields.map(_fieldName).join(', ')}.',
                en: 'No result — fill in or correct: '
                    '${fields.map(_fieldName).join(', ')}.'),
          ),
      },
    ];
  }

  String _seriesLabel(LengthSeries s) => switch (s) {
        LengthSeries.mm5 => context.tr(pl: 'co 5 mm', en: 'every 5 mm'),
        LengthSeries.mm10 => context.tr(pl: 'co 10 mm', en: 'every 10 mm'),
        LengthSeries.quarterInch => context.tr(pl: 'co 1/4"', en: 'every 1/4"'),
      };

  Widget _dimsResult(StudDimensionsResult r, bool en) {
    String n(double v) => fmtStudNum(v, decimals: 2, en: en);
    final q = r.orderQuarterIn;
    final order = q == null
        ? formatMm(r.orderMm, decimals: 0, en: en)
        : '${formatQuarterInch(q)} (${formatMm(r.orderMm, decimals: 2, en: en)})';
    final washers = r.washers == 0 ? '' : ' + ${r.washers} × ${n(r.washerMm)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const ValueKey('bk-dims-result'),
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: kGold.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  context.tr(
                      pl: 'Zamów szpilki o długości',
                      en: 'Order studs of length'),
                  style: const TextStyle(fontSize: 12, color: kTextSec)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(order,
                    key: const ValueKey('bk-dims-order'),
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: kGold)),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                    pl: 'Obliczona: ${formatMm(r.requiredMm, decimals: 2, en: en)} '
                        '→ w górę ${_seriesLabel(r.series)}',
                    en: 'Calculated: ${formatMm(r.requiredMm, decimals: 2, en: en)} '
                        '→ up to ${_seriesLabel(r.series)}'),
                key: const ValueKey('bk-dims-required'),
                style: const TextStyle(fontSize: 13.5, color: kText),
              ),
              const SizedBox(height: 4),
              Text(
                '${n(r.flange1Mm)} + ${n(r.flange2Mm)} + ${n(r.gasketMm)} + '
                '2 × ${n(r.nutMm)} + 2 × ${n(r.protrusionMm)}$washers',
                key: const ValueKey('bk-dims-breakdown'),
                style: _hint,
              ),
              const SizedBox(height: 4),
              Text(
                  context.tr(
                      pl: 'Długość bez ścięć (końcówek) — wystawanie liczone '
                          'do pełnego zwoju.',
                      en: 'Length without points — protrusion counted to a '
                          'full thread.'),
                  style: _hint),
            ],
          ),
        ),
      ),
    );
  }

  // ── Komplet ───────────────────────────────────────────────────────────────

  Widget _kitTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kArc));
    }
    final en = _en;
    final order = buildBoltKitOrder(_joints, sparePercent: _spare);
    return ListView(
      key: const ValueKey('bk-kit-list'),
      padding: _pagePadding,
      children: [
        if (_damaged)
          QuoteNotice(
            key: const ValueKey('bk-damaged'),
            color: kFail,
            icon: Icons.report_problem_outlined,
            text: context.tr(
                pl: 'Zapisana lista była częściowo nieczytelna — pokazano to, '
                    'co dało się odczytać. Przed następnym zapisem aplikacja '
                    'zachowa kopię surowych danych.',
                en: 'The saved list was partly unreadable — showing what could '
                    'be read. Before the next save the app keeps a copy of the '
                    'raw data.'),
          ),
        if (_joints.isEmpty)
          Padding(
            key: const ValueKey('bk-kit-empty'),
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Text(
              context.tr(
                  pl: 'Lista jest pusta. W zakładce „Długość” wybierz DN, klasę '
                      'i przylgę, potem „Dodaj do kompletu”.',
                  en: 'The list is empty. On the “Length” tab pick DN, class '
                      'and facing, then “Add to the kit”.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSec),
            ),
          )
        else ...[
          QuoteSection(
            title: context.tr(pl: 'Połączenia', en: 'Joints'),
            children: [for (final j in _joints) _jointCard(j, en)],
          ),
          QuoteSection(
            title: context.tr(pl: 'Zapas', en: 'Spare'),
            subtitle: context.tr(
                pl: 'Doliczany do każdej pozycji, zaokrąglony w górę.',
                en: 'Added to every line, rounded up.'),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in kSpareOptions)
                    ChoiceChip(
                      key: ValueKey('bk-spare-$p'),
                      label: Text('$p %'),
                      selected: _spare == p,
                      onSelected: (_) => _setSpare(p),
                    ),
                ],
              ),
            ],
          ),
          _orderSection(order, en),
        ],
      ],
    );
  }

  Widget _jointCard(BoltKitJoint j, bool en) {
    final s = j.stud;
    return Padding(
      key: ValueKey('bk-j-${j.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(jointTitle(j),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: kText)),
              const SizedBox(height: 2),
              Text(
                [
                  j.material.pair,
                  jointGasketLabel(j, en: en),
                  if (s != null)
                    '${s.boltCount} × ${studDesignation(s.size, s.lengthQuarterIn)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: kTextSec),
              ),
              // Wąski ekran + duży tekst: przyciski „moment / usuń”
              // przechodzą do następnej linii zamiast wychodzić poza kartę.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('bk-j-minus-${j.id}'),
                        tooltip: context.tr(pl: 'Mniej', en: 'Fewer'),
                        onPressed:
                            j.count > 1 ? () => _changeCount(j, -1) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${j.count} ×',
                        key: ValueKey('bk-j-count-${j.id}'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: kText),
                      ),
                      IconButton(
                        key: ValueKey('bk-j-plus-${j.id}'),
                        tooltip: context.tr(pl: 'Więcej', en: 'More'),
                        onPressed: j.count < kMaxJointCount
                            ? () => _changeCount(j, 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('bk-j-torque-${j.id}'),
                        tooltip:
                            context.tr(pl: 'Moment śrub', en: 'Bolt torque'),
                        onPressed: () => _openTorque(j),
                        icon: const Icon(Icons.build_outlined),
                      ),
                      IconButton(
                        key: ValueKey('bk-j-del-${j.id}'),
                        tooltip: context.tr(pl: 'Usuń', en: 'Remove'),
                        onPressed: () => _delete(j),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderSection(BoltKitOrder o, bool en) {
    Widget line(Key key, String label, int qty) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: const TextStyle(fontSize: 13.5, color: kText)),
              Text(qtyLabel(qty, o.sparePercent, en: en),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: kGold)),
            ],
          ),
        );
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kTextSec)),
        );
    return QuoteSection(
      key: const ValueKey('bk-order'),
      title: context.tr(pl: 'Zamówienie', en: 'Order'),
      children: [
        head(context.tr(
            pl: 'Szpilki (${o.totalStuds} szt.)',
            en: 'Stud bolts (${o.totalStuds} pcs)')),
        for (final (i, l) in o.studs.indexed)
          line(ValueKey('bk-order-stud-$i'), studLineLabel(l, en: en), l.qty),
        head(context.tr(
            pl: 'Nakrętki — 2 na szpilkę (${o.totalNuts} szt.)',
            en: 'Nuts — 2 per stud (${o.totalNuts} pcs)')),
        for (final (i, l) in o.nuts.indexed)
          line(ValueKey('bk-order-nut-$i'), nutLineLabel(l, en: en), l.qty),
        head(context.tr(
            pl: 'Uszczelki (${o.totalGaskets} szt.)',
            en: 'Gaskets (${o.totalGaskets} pcs)')),
        for (final (i, l) in o.gaskets.indexed)
          line(ValueKey('bk-order-gasket-$i'), gasketLineLabel(l, en: en),
              l.qty),
        const SizedBox(height: 8),
        Text(boltKitAssumptionsNote(en: en), style: _hint),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('bk-share-text'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _sharing || o.isEmpty
                    ? null
                    : () => _share(o, BoltKitShareFormat.text),
                icon: const Icon(Icons.share_outlined),
                label: Text(context.tr(pl: 'Tekst', en: 'Text')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('bk-share-pdf'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _sharing || o.isEmpty
                    ? null
                    : () => _share(o, BoltKitShareFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
