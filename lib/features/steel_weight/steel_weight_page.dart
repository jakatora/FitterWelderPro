import '../../assistant/core/skill.dart' show PreparedModuleRecord, ModuleRecordUndo, AssistantText, ModuleActionResult;
// Ciężar stali — profile, blachy, pręty.
//
// Monter / spawacz konstrukcji sprawdza, ile waży belka (dźwig, wciągarka,
// ręczne przenoszenie, transport), składa listę materiałową na zlecenie
// (profil × długość × sztuki), dolicza zapas na odpady i koszt — i wysyła
// listę hurtowni albo szefowi.
//
// Liczby: tabele w lib/domain/steel_weight/steel_sections.dart (każda seria
// ze źródłem), logika w steel_weight.dart. Rury NIE są tutaj — ich ciężar
// liczy zakładka „Ciężar rury" (fitter_tools_screen.dart).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:uuid/uuid.dart';
import '../../assistant/assistant_validator.dart' show assistantNumber;
import '../../database/local_record_owner.dart';
import '../../services/account_service.dart';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/quotes/quote_calculator.dart' show formatPln;
import '../../domain/steel_weight/steel_order_text.dart';
import '../../domain/steel_weight/steel_sections.dart';
import '../../domain/steel_weight/steel_weight.dart';
import '../../domain/steel_weight/steel_draft_fields.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'steel_weight_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef SteelShareText = Future<void> Function(String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class SteelWeightPage extends StatefulWidget {
  const SteelWeightPage({
    super.key,
    this.store,
    this.shareText = _defaultShareText,
  });

  final SteelOrderStore? store;
  final SteelShareText shareText;

  @override
  State<SteelWeightPage> createState() => _SteelWeightPageState();
}

class _SteelWeightPageState extends State<SteelWeightPage>
    with SingleTickerProviderStateMixin, ToolHandleHost<SteelWeightPage>
    implements InputToolHandle, RecordActionHandle, ModuleActionHandle {
  @override
  Future<ModuleActionResult> performAction(String action,
      {String? field}) async {
    const unavailable = ModuleActionResult(
        false,
        AssistantText(
            'Otwórz Ciężar stali i poczekaj na zakończenie zapisu listy. Jeśli zapis się nie udał, ponów go albo wczytaj listę.',
            'Open Steel weight and wait for the list to finish saving. If saving failed, retry or reload the list.'));
    bool available() =>
        mounted &&
        !_loading &&
        !_loadError &&
        !_sessionFrozen &&
        !_dirty &&
        !_saveError &&
        _hasCurrentOwner &&
        _store != null &&
        ModalRoute.of(context)?.isCurrent == true;
    if (action != 'summarize_list' || field != null || !available()) {
      return unavailable;
    }
    final generation = _loadGeneration;
    final owner = _owner!;
    try {
      // Read durable account-scoped data; a summary never writes or rebases it.
      final saved = await _store!.readLatest();
      owner.requireCurrent();
      if (generation != _loadGeneration || !available()) return unavailable;
      return ModuleActionResult(
          true,
          AssistantText(steelOrderSummaryText(saved),
              steelOrderSummaryText(saved, english: true)));
    } catch (_) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Nie udało się odczytać zapisanej listy stali. Sprawdź listę w module; nie podaję niepewnego wyniku.',
              'The saved steel list could not be read. Check the list in the module; no uncertain result is reported.'));
    }
  }

  @override
  Map<String, Object?> get inputFields {
    if (!mounted ||
        _loading ||
        _sessionFrozen ||
        !_hasCurrentOwner ||
        _tabs.index != 0 ||
        ModalRoute.of(context)?.isCurrent != true) {
      return const {};
    }
    return _draftFields;
  }

  Map<String, Object?> get _draftFields {
    final item = _draft;
    return {
      'shape': item.shape.name,
      'material': item.material.name,
      if (item.section != null) 'section': item.section,
      'a_mm': item.a,
      'b_mm': item.b,
      't_mm': item.t,
      'length_mm': item.lengthMm,
      // Expose the actual input, not _draft's rounded display count.
      'quantity': _count,
    };
  }

  int _assistantGen = 0;
  @override
  String get toolId => 'steel_weight';
  @override
  Set<String> get supportedFields => steelDraftFields;
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final item = steelDraftFromFields(fields);
    if (item == null ||
        !mounted ||
        _loading ||
        _sessionFrozen ||
        !_hasCurrentOwner ||
        ModalRoute.of(context)?.isCurrent != true) {
      return fields.isEmpty ? supportedFields : fields.keys.toSet();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _shape = item.shape;
      _material = item.material;
      if (item.shape.tabulated) _picked[item.shape] = item.section!;
      _lengthMm = item.lengthMm;
      _count = item.count.toDouble();
      switch (item.shape) {
        case SteelShape.hollow:
          _hollowCustom = true;
          _hollowH = item.a;
          _hollowB = item.b;
          _hollowT = item.t;
        case SteelShape.flat:
          _flatW = item.a;
          _flatT = item.t;
        case SteelShape.roundBar:
          _roundD = item.a;
        case SteelShape.squareBar:
          _squareA = item.a;
        case SteelShape.plate:
          _plateW = item.a;
          _plateL = item.lengthMm;
          _plateT = item.t;
        default:
          break;
      }
      _assistantGen++;
      _tabs.index = 0;
    });
    return {};
  }

  late final TabController _tabs = TabController(length: 2, vsync: this);

  // ── Lista (zapisywana) ──────────────────────────────────────────────────
  SteelOrder _order = const SteelOrder();
  bool _loading = true;
  Timer? _save;

  /// Zmiana klucza pól ceny / zapasu — wymusza odświeżenie po wczytaniu
  /// albo po kliknięciu gotowej wartości.
  int _listGen = 0;

  // ── Pozycja w budowie (zakładka Profil) ─────────────────────────────────
  SteelShape _shape = SteelShape.heb;
  static const _defaultPicked = {
    SteelShape.ipe: 'IPE 200',
    SteelShape.hea: 'HEA 200',
    SteelShape.heb: 'HEB 200',
    SteelShape.hem: 'HEM 200',
    SteelShape.upn: 'UPN 200',
    SteelShape.upe: 'UPE 200',
    SteelShape.angleEqual: 'L 50×50×5',
    SteelShape.angleUnequal: 'L 60×40×5',
  };
  final Map<SteelShape, String> _picked = Map.of(_defaultPicked);
  SteelMaterial _material = SteelMaterial.carbon;
  double? _lengthMm = 6000;
  double? _count = 1;
  double? _flatW = 80;
  double? _flatT = 10;
  double? _roundD = 20;
  double? _squareA = 20;
  double? _plateT = 10;
  double? _plateW = 1500;
  double? _plateL = 3000;
  bool _hollowCustom = false;
  (double, double, double) _hollowStd = (100, 100, 4);
  double? _hollowH = 100;
  double? _hollowB = 100;
  double? _hollowT = 4;

  /// Zmiana klucza pola długości — po kliknięciu „6 m" / „12 m".
  int _draftGen = 0;

  late final AccountService _sessionAccount = AccountService.instance;
  late final Future<VoidCallback> Function() _sessionPreparer =
      _prepareSessionChange;
  late int _sessionRevision;
  LocalRecordOwner? _owner;
  SteelOrderStore? _store;
  int _loadGeneration = 0, _editRevision = 0, _freezeDepth = 0;
  bool _dirty = false, _saveError = false, _saveConflict = false, _loadError = false, _popPending = false;
  Future<void>? _recordTask;
  Future<void>? _saveTail;
  Route<dynamic>? _orderDialogRoute;
  bool get _sessionFrozen => _freezeDepth > 0 || _recordTask != null;
  bool get _hasCurrentOwner {
    try {
      _owner?.requireCurrent();
      return _owner != null;
    } catch (_) {
      return false;
    }
  }

  void _resetDraft() {
    _shape = SteelShape.heb;
    _picked
      ..clear()
      ..addAll(_defaultPicked);
    _material = SteelMaterial.carbon;
    _lengthMm = 6000;
    _count = 1;
    _flatW = 80;
    _flatT = 10;
    _roundD = 20;
    _squareA = 20;
    _plateT = 10;
    _plateW = 1500;
    _plateL = 3000;
    _hollowCustom = false;
    _hollowStd = (100, 100, 4);
    _hollowH = 100;
    _hollowB = 100;
    _hollowT = 4;
    _assistantGen++;
    _draftGen++;
    _tabs.index = 0;
  }

  @override
  void initState() {
    super.initState();
    _sessionRevision = _sessionAccount.sessionRevision;
    _sessionAccount.addListener(_accountChanged);
    _sessionAccount.addSessionPreparer(_sessionPreparer);
    unawaited(_load());
  }

  void _accountChanged() {
    if (!mounted) return;
    if (_sessionRevision == _sessionAccount.sessionRevision) {
      if (_loadError) unawaited(_load());
      return;
    }
    _sessionRevision = _sessionAccount.sessionRevision;
    final dialog = _orderDialogRoute;
    if (dialog != null && dialog.isActive) dialog.navigator?.removeRoute(dialog);
    _save?.cancel();
    setState(() {
      _loadGeneration++;
      _owner = null;
      _store = null;
      _order = const SteelOrder();
      _dirty = false;
      _saveError = false;
      _loadError = false;
      _saveTail = null;
      _recordTask = null;
      _saveConflict = false;
      _freezeDepth = 0;
      _loading = true;
      _resetDraft();
    });
    unawaited(_load());
  }

  Future<VoidCallback> _prepareSessionChange() async {
    if (!mounted) return () {};
    final revision = _sessionAccount.sessionRevision;
    final pendingRecord = _recordTask;
    if (pendingRecord != null) {
      try {
        await pendingRecord;
      } catch (_) {
        throw AccountException(
            'Nie udało się potwierdzić zapisu pozycji stali. Ponów operację przed zmianą konta. / Could not confirm the steel record. Retry before switching accounts.');
      }
    }
    if (!mounted) return () {};
    setState(() => _freezeDepth++);
    var released = false;
    void release() {
      if (released) return;
      released = true;
      if (mounted && revision == _sessionAccount.sessionRevision) {
        setState(() => _freezeDepth--);
      }
    }

    try {
      await _flushOrder();
    } catch (_) {
      release();
      throw AccountException(
          'Nie udało się zapisać listy stali. Ponów zapis przed zmianą konta. / Could not save the steel list. Retry saving before switching accounts.');
    }
    return release;
  }

  @override
  void dispose() {
    _sessionAccount.removeListener(_accountChanged);
    _sessionAccount.removeSessionPreparer(_sessionPreparer);
    _save?.cancel();
    if (_dirty) unawaited(_flushOrder().catchError((Object _) {}));
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final owner = await LocalRecordOwner.capture();
      owner.requireCurrent();
      final store = widget.store ?? SteelOrderStore.forOwner(owner);
      final order = await store.load();
      owner.requireCurrent();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _owner = owner;
        _store = store;
        _order = order;
        _loading = false;
        _loadError = false;
        _listGen++;
      });
      markReady();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  Future<void> _flushOrder() {
    _save?.cancel();
    if (!_dirty) return Future.value();
    final owner = _owner, store = _store, order = _order;
    final generation = _loadGeneration, edit = _editRevision;
    Future<void> write() async {
      try {
        if (owner == null || store == null) {
          throw StateError('No steel list owner');
        }
        owner.requireCurrent();
        await store.save(order);
        owner.requireCurrent();
        if (mounted && generation == _loadGeneration && edit == _editRevision) {
          setState(() {
            _dirty = false;
            _saveError = false;
            _saveConflict = false;
          });
        }
      } catch (error) {
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _saveError = true;
            _saveConflict = error is SteelOrderConflict;
          });
        }
        rethrow;
      }
    }

    final tail = _saveTail;
    final result =
        tail == null ? Future<void>.sync(write) : tail.then((_) => write());
    _saveTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _flushAndPop() async {
    if (_popPending || !mounted) return;
    _popPending = true;
    final route = ModalRoute.of(context), generation = _loadGeneration;
    try {
      final record = _recordTask;
      if (record != null) await record;
      await _flushOrder();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted &&
          generation == _loadGeneration &&
          !_dirty &&
          route?.isCurrent == true) {
        await Navigator.of(context).maybePop();
      }
    } catch (_) {/* The save banner remains available for retry. */} finally {
      _popPending = false;
    }
  }

  void _setOrder(SteelOrder order) {
    if (_loading || _loadError || _sessionFrozen || !_hasCurrentOwner) return;
    setState(() {
      _order = order;
      _dirty = true;
      _editRevision++;
    });
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400),
        () => unawaited(_flushOrder().catchError((Object _) {})));
  }

  Future<T> _recordOperation<T>(Future<T> Function() operation) {
    if (!mounted ||
        !_hasCurrentOwner ||
        _recordTask != null ||
        _freezeDepth > 0) {
      throw StateError('Steel list is busy');
    }
    final generation = _loadGeneration;
    final result = Future<T>.sync(operation);
    final drain = result.then<void>((_) {});
    setState(() {
      _recordTask = drain;
    });
    void release() {
      if (mounted &&
          generation == _loadGeneration &&
          identical(_recordTask, drain)) {
        setState(() => _recordTask = null);
      }
    }

    unawaited(
        drain.then<void>((_) => release(), onError: (Object _) => release()));
    return result;
  }

  void _requireRecordOwner(LocalRecordOwner owner, int generation,
      {bool visible = true}) {
    owner.requireCurrent();
    if (!mounted ||
        generation != _loadGeneration ||
        _loading ||
        _loadError ||
        visible && ModalRoute.of(context)?.isCurrent != true) {
      throw StateError('The steel record context changed');
    }
  }

  void _showRecordFailure(SteelOrder before, int generation, Object error,
      {required bool restore}) {
    if (!mounted || generation != _loadGeneration || !_hasCurrentOwner) return;
    _save?.cancel();
    setState(() {
      if (restore) {
        _order = before;
        _dirty = false;
        _editRevision++;
      }
      _saveError = restore || error is SteelOrderConflict;
      _saveConflict = _saveError;
    });
  }

  @override
  PreparedModuleRecord? prepareRecordAction(String action) {
    if (action != 'add_draft' ||
        _sessionFrozen ||
        inputFields.isEmpty ||
        _store == null) {
      return null;
    }
    final parsed = steelDraftFromFields(_draftFields);
    if (parsed == null) return null;
    final owner = _owner!, store = _store!, generation = _loadGeneration;
    final snapshot = Map<String, Object?>.of(_draftFields);
    final item = parsed.copyWith(recordId: const Uuid().v4());
    var expectedEdit = _editRevision, committed = false;
    Future<ModuleRecordUndo?>? pending;
    void validate() {
      _requireRecordOwner(owner, generation);
      if (_tabs.index != 0 ||
          !mapEquals(snapshot, _draftFields) ||
          expectedEdit != _editRevision) {
        throw StateError('The item or list changed after preparation');
      }
    }

    Future<void> undo() => _recordOperation<void>(() async {
          _requireRecordOwner(owner, generation);
          await _flushOrder();
          _requireRecordOwner(owner, generation);
          var before = _order;
          var changed = false;
          try {
            final latest = await store.readLatest();
            _requireRecordOwner(owner, generation);
            final matches = latest.items
                .where((row) => row.recordId == item.recordId)
                .toList();
            if (matches.length > 1 ||
                matches.isNotEmpty &&
                    jsonEncode(matches.single.toJson()) !=
                        jsonEncode(item.toJson())) {
              throw StateError('The added record was edited');
            }
            await store.save(
                latest); // Acknowledge the fresh base without overwriting other records.
            _requireRecordOwner(owner, generation);
            before = latest;
            setState(() {
              _order = latest;
              _dirty = false;
            });
            final next = latest.copyWith(
                items: latest.items
                    .where((row) => row.recordId != item.recordId)
                    .toList());
            setState(() {
              _order = next;
              _dirty = true;
              _editRevision++;
            });
            changed = true;
            await _flushOrder();
            _requireRecordOwner(owner, generation, visible: false);
            if ((await store.readLatest())
                .items
                .any((row) => row.recordId == item.recordId)) {
              throw StateError('Undo could not be verified');
            }
          } catch (error) {
            _showRecordFailure(before, generation, error, restore: changed);
            rethrow;
          }
        });
    Future<ModuleRecordUndo?> commit() async {
      validate();
      await _flushOrder();
      validate();
      var before = _order;
      var changed = false;
      try {
        final latest = await store.readLatest();
        validate();
        final existing =
            latest.items.where((row) => row.recordId == item.recordId).toList();
        if (existing.isNotEmpty &&
            (existing.length != 1 ||
                jsonEncode(existing.single.toJson()) !=
                    jsonEncode(item.toJson()))) {
          throw StateError('Record identity conflict');
        }
        await store.save(
            latest); // Merge into the persisted list, retaining its price and allowance.
        _requireRecordOwner(owner, generation, visible: false);
        before = latest;
        setState(() {
          _order = latest;
          _dirty = false;
        });
        validate();
        final next = existing.isNotEmpty
            ? latest
            : latest.copyWith(items: [...latest.items, item]);
        setState(() {
          _order = next;
          _dirty = true;
          _editRevision++;
        });
        changed = true;
        expectedEdit = _editRevision;
        await _flushOrder();
        _requireRecordOwner(owner, generation, visible: false);
        final verified = await store.readLatest();
        if (verified.items
                .where((row) =>
                    row.recordId == item.recordId &&
                    jsonEncode(row.toJson()) == jsonEncode(item.toJson()))
                .length !=
            1) {
          throw StateError('Record persistence could not be verified');
        }
        committed = true;
        return undo;
      } catch (error) {
        _showRecordFailure(before, generation, error, restore: changed);
        expectedEdit = _editRevision;
        rethrow;
      }
    }

    final quantity = item.count,
        length = assistantNumber(item.lengthMm, context.language);
    final mass = assistantNumber(item.totalKg, context.language);
    return PreparedModuleRecord(
        AssistantText(
            'Dodać ${item.label()} (${item.material.label(false)}) do listy: $quantity szt., każda $length mm, razem $mass kg? Cena i zapas pozostaną z bieżącej listy.',
            'Add ${item.label(english: true)} (${item.material.label(true)}) to the list: $quantity pieces, $length mm each, $mass kg total? The current list price and allowance will be kept.'),
        () {
      validate();
      if (committed) return Future.value(undo);
      return pending ??= _recordOperation<ModuleRecordUndo?>(commit)
          .whenComplete(() => pending = null);
    });
  }

  Future<void> _reloadConflictingList() async {
    final generation = _loadGeneration;
    if (_dirty) {
      final accepted = await _showOrderDialog<bool>((ctx) => AlertDialog(
              title: Text(context.tr(
                  pl: 'Wczytać zapisaną listę?', en: 'Reload saved list?')),
              content: Text(context.tr(
                  pl: 'Niezapisane zmiany tego ekranu zostaną odrzucone.',
                  en: 'Unsaved changes on this screen will be discarded.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(context.tr(pl: 'Wczytaj', en: 'Reload')))
              ]));
      if (accepted != true) return;
    }
    if (!mounted || generation != _loadGeneration || !_hasCurrentOwner) return;
    _save?.cancel();
    setState(() {
      _dirty = false;
      _saveError = false;
      _saveConflict = false;
      _loading = true;
    });
    await _load();
  }

  Widget _protectBack(Widget child) => PopScope(
      canPop: !_dirty && _recordTask == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_flushAndPop());
      },
      child: child);

  bool get _en => context.language == AppLanguage.en;

  // ── Pozycja w budowie ───────────────────────────────────────────────────

  SteelItem get _draft {
    final n = (_count ?? 0).isFinite ? (_count ?? 0).round() : 0;
    final len = _lengthMm ?? 0;
    return switch (_shape) {
      SteelShape.hollow => _hollowCustom
          ? SteelItem(
              shape: _shape,
              a: _hollowH ?? 0,
              b: _hollowB ?? 0,
              t: _hollowT ?? 0,
              lengthMm: len,
              count: n,
              material: _material)
          : SteelItem(
              shape: _shape,
              a: _hollowStd.$1,
              b: _hollowStd.$2,
              t: _hollowStd.$3,
              lengthMm: len,
              count: n,
              material: _material),
      SteelShape.flat => SteelItem(
          shape: _shape,
          a: _flatW ?? 0,
          t: _flatT ?? 0,
          lengthMm: len,
          count: n,
          material: _material),
      SteelShape.roundBar => SteelItem(
          shape: _shape,
          a: _roundD ?? 0,
          lengthMm: len,
          count: n,
          material: _material),
      SteelShape.squareBar => SteelItem(
          shape: _shape,
          a: _squareA ?? 0,
          lengthMm: len,
          count: n,
          material: _material),
      SteelShape.plate => SteelItem(
          shape: _shape,
          a: _plateW ?? 0,
          t: _plateT ?? 0,
          lengthMm: _plateL ?? 0,
          count: n,
          material: _material),
      _ => SteelItem(
          shape: _shape,
          section: _picked[_shape],
          lengthMm: len,
          count: n,
          material: _material),
    };
  }

  void _add(SteelItem item) {
    if (!item.isValid) return;
    unawaited(Haptic.saved());
    _setOrder(_order.copyWith(items: [..._order.items, item]));
    final en = _en;
    final what = item.shape == SteelShape.plate
        ? '${item.label(english: en)} × ${item.count}'
        : '${item.label(english: en)} · ${item.count} × '
            '${fmtDim(item.lengthMm)} mm';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Dodano: $what', en: 'Added: $what')),
        action: SnackBarAction(
          label: context.tr(pl: 'Lista', en: 'List'),
          onPressed: () => _tabs.animateTo(1),
        ),
      ));
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _share() async {
    if (_order.items.isEmpty) return;
    unawaited(Haptic.tap());
    final text = steelOrderText(_order, english: _en, date: DateTime.now());
    await widget.shareText(text,
        context.tr(pl: 'Lista materiałowa — stal', en: 'Steel material list'));
  }

  Future<T?> _showOrderDialog<T>(WidgetBuilder builder) async {
    if (_orderDialogRoute != null || !_hasCurrentOwner) return null;
    final route = DialogRoute<T>(context: context, builder: builder);
    _orderDialogRoute = route;
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      if (identical(_orderDialogRoute, route)) _orderDialogRoute = null;
    }
  }

  Future<void> _confirmClear() async {
    final generation = _loadGeneration;
    final ok = await _showOrderDialog<bool>(
      (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Wyczyścić listę?', en: 'Clear the list?')),
        content: Text(context.tr(
            pl: 'Usuniesz wszystkie pozycje. Cena i zapas zostają.',
            en: 'All items will be removed. Price and allowance stay.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('sw-clear-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr(pl: 'Wyczyść', en: 'Clear')),
          ),
        ],
      ),
    );
    if (ok == true && mounted && generation == _loadGeneration) {
      _setOrder(_order.copyWith(items: const []));
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = context.tr(pl: 'Ciężar stali', en: 'Steel weight');
    if (_loading || _loadError || _sessionFrozen) {
      return _protectBack(Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
            child: _loadError
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.tr(
                        pl: 'Nie udało się wczytać listy dla bieżącego konta.',
                        en: 'Could not load the list for the current account.')),
                    TextButton(
                        onPressed: () {
                          setState(() {
                            _loadError = false;
                            _loading = true;
                          });
                          unawaited(_load());
                        },
                        child: Text(
                            context.tr(pl: 'Spróbuj ponownie', en: 'Retry'))),
                  ])
                : const CircularProgressIndicator(color: kArc)),
      ));
    }
    final n = _order.items.length;
    return _protectBack(Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: const ValueKey('sw-appbar-share'),
            tooltip: context.tr(pl: 'Udostępnij listę', en: 'Share list'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: n == 0 ? null : _share,
            icon: const Icon(Icons.ios_share),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: kArc,
          labelColor: kText,
          unselectedLabelColor: kTextSec,
          tabs: [
            Tab(
                key: const ValueKey('sw-tab-profile'),
                text: context.tr(pl: 'Profil', en: 'Section')),
            Tab(
                key: const ValueKey('sw-tab-list'),
                text: context.tr(pl: 'Lista ($n)', en: 'List ($n)')),
          ],
        ),
      ),
      body: Column(children: [
        if (_saveError)
          MaterialBanner(
              content: Text(context.tr(
                  pl: _saveConflict
                      ? 'Nie udało się potwierdzić aktualnej listy. Wczytaj zapisaną wersję.'
                      : 'Lista nie została zapisana. Ponów zapis przed zmianą konta.',
                  en: _saveConflict
                      ? 'The current list could not be confirmed. Reload the saved version.'
                      : 'The list was not saved. Retry before switching accounts.')),
              actions: [
                TextButton(
                    key: const ValueKey('sw-retry-save'),
                    onPressed: () => _saveConflict
                        ? unawaited(_reloadConflictingList())
                        : unawaited(_flushOrder().catchError((Object _) {})),
                    child: Text(context.tr(
                        pl: _saveConflict ? 'Wczytaj listę' : 'Ponów zapis',
                        en: _saveConflict ? 'Reload list' : 'Retry save')))
              ]),
        Expanded(
            child: TabBarView(
          controller: _tabs,
          children: [
            KeyedSubtree(
                key: ValueKey('sw-assistant-$_assistantGen'),
                child: _profileTab()),
            _listTab()
          ],
        )),
      ]),
    ));
  }

  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(
      16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom);

  // ═══ Zakładka: Profil ═══════════════════════════════════════════════════

  Widget _profileTab() {
    final item = _draft;
    return ListView(
      key: const ValueKey('sw-profile-list'),
      padding: _pagePadding,
      children: [
        QuoteSection(
          title: context.tr(pl: 'Rodzaj', en: 'Type'),
          children: [_shapeChips()],
        ),
        QuoteSection(
          title: context.tr(pl: 'Wymiar', en: 'Size'),
          children: [_sizeInputs()],
        ),
        QuoteSection(
          title: _shape == SteelShape.plate
              ? context.tr(pl: 'Arkusze', en: 'Sheets')
              : context.tr(pl: 'Długość i sztuki', en: 'Length and pieces'),
          children: [_lengthInputs()],
        ),
        QuoteSection(
          title: context.tr(pl: 'Materiał', en: 'Material'),
          children: [_materialChips()],
        ),
        _resultSection(item),
      ],
    );
  }

  String _shapeLabel(SteelShape s) => switch (s) {
        SteelShape.ipe => 'IPE',
        SteelShape.hea => 'HEA',
        SteelShape.heb => 'HEB',
        SteelShape.hem => 'HEM',
        SteelShape.upn => 'UPN',
        SteelShape.upe => 'UPE',
        SteelShape.angleEqual =>
          context.tr(pl: 'Kątownik równoramienny', en: 'Equal angle'),
        SteelShape.angleUnequal =>
          context.tr(pl: 'Kątownik nierównoramienny', en: 'Unequal angle'),
        SteelShape.hollow =>
          context.tr(pl: 'Profil zamknięty', en: 'Hollow section'),
        SteelShape.flat => context.tr(pl: 'Płaskownik', en: 'Flat bar'),
        SteelShape.roundBar => context.tr(pl: 'Pręt okrągły', en: 'Round bar'),
        SteelShape.squareBar =>
          context.tr(pl: 'Pręt kwadratowy', en: 'Square bar'),
        SteelShape.plate => context.tr(pl: 'Blacha', en: 'Plate'),
      };

  Widget _shapeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in SteelShape.values)
          ChoiceChip(
            key: ValueKey('sw-shape-${s.name}'),
            label: Text(_shapeLabel(s)),
            selected: _shape == s,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) {
              unawaited(Haptic.tap());
              setState(() => _shape = s);
            },
          ),
      ],
    );
  }

  Widget _num(String id, String label, double? value, ValueChanged<double?> set,
      {String unit = 'mm',
      String? helper,
      bool decimal = true,
      int decimals = 2}) {
    return QuoteNumberField(
      key: ValueKey('sw-$id'),
      label: label,
      value: value,
      unit: unit,
      helper: helper,
      decimal: decimal,
      decimals: decimals,
      validate: (v) => v != null && v <= 0
          ? context.tr(pl: 'Wartość musi być > 0', en: 'Value must be > 0')
          : null,
      onChanged: (v) => setState(() => set(v)),
    );
  }

  InputDecoration _dropDecoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _sizeInputs() {
    switch (_shape) {
      case SteelShape.angleEqual:
      case SteelShape.angleUnequal:
        return _anglePicker();
      case SteelShape.hollow:
        return _hollowPicker();
      case SteelShape.flat:
        return FieldPair(
          left: _num('flat-w', context.tr(pl: 'Szerokość b', en: 'Width b'),
              _flatW, (v) => _flatW = v),
          right: _num('flat-t', context.tr(pl: 'Grubość t', en: 'Thickness t'),
              _flatT, (v) => _flatT = v),
        );
      case SteelShape.roundBar:
        return _num('round-d', context.tr(pl: 'Średnica d', en: 'Diameter d'),
            _roundD, (v) => _roundD = v);
      case SteelShape.squareBar:
        return _num('square-a', context.tr(pl: 'Bok a', en: 'Side a'), _squareA,
            (v) => _squareA = v);
      case SteelShape.plate:
        return _num('plate-t', context.tr(pl: 'Grubość t', en: 'Thickness t'),
            _plateT, (v) => _plateT = v);
      default:
        return _sectionDropdown();
    }
  }

  Widget _sectionDropdown() {
    final list = sectionsOf(_shape);
    final current =
        sectionByName(_shape, _picked[_shape])?.name ?? list.first.name;
    return DropdownButtonFormField<String>(
      key: ValueKey('sw-section-${_shape.name}'),
      initialValue: current,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: _dropDecoration(
          context.tr(pl: 'Wymiar z tablicy', en: 'Size from the table')),
      items: [
        for (final s in list)
          DropdownMenuItem(
            value: s.name,
            child: Text(s.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        unawaited(Haptic.tap());
        setState(() => _picked[_shape] = v);
      },
    );
  }

  Widget _anglePicker() {
    final list = sectionsOf(_shape);
    final current = sectionByName(_shape, _picked[_shape]) ?? list.first;
    String sizeOf(SteelSection s) => '${fmtDim(s.h)}×${fmtDim(s.b)}';
    final sizes = <String>[];
    for (final s in list) {
      if (!sizes.contains(sizeOf(s))) sizes.add(sizeOf(s));
    }
    final curSize = sizeOf(current);
    final thicknesses = [
      for (final s in list)
        if (sizeOf(s) == curSize) s
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('sw-angle-size-${_shape.name}'),
          initialValue: curSize,
          isExpanded: true,
          menuMaxHeight: 420,
          decoration: _dropDecoration(
              context.tr(pl: 'Ramiona a × b [mm]', en: 'Legs a × b [mm]')),
          items: [
            for (final s in sizes)
              DropdownMenuItem(
                value: s,
                child: Text('L $s',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            unawaited(Haptic.tap());
            final same = [
              for (final s in list)
                if (sizeOf(s) == v) s
            ];
            // Najbliższa grubość do dotychczasowej.
            same.sort((x, y) =>
                (x.t - current.t).abs().compareTo((y.t - current.t).abs()));
            setState(() => _picked[_shape] = same.first.name);
          },
        ),
        const SizedBox(height: 10),
        Text(context.tr(pl: 'Grubość t', en: 'Thickness t'),
            style: const TextStyle(fontSize: 12.5, color: kTextSec)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in thicknesses)
              ChoiceChip(
                key: ValueKey('sw-angle-t-${fmtDim(s.t)}'),
                label: Text('${fmtDim(s.t)} mm'),
                selected: s.name == current.name,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  unawaited(Haptic.tap());
                  setState(() => _picked[_shape] = s.name);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _hollowPicker() {
    String sizeOf((double, double, double) s) =>
        '${s.$1 == s.$2 ? 'SHS' : 'RHS'} ${fmtDim(s.$1)}×${fmtDim(s.$2)}';
    final sizes = <String>[];
    for (final s in kHollowSizes) {
      if (!sizes.contains(sizeOf(s))) sizes.add(sizeOf(s));
    }
    final curSize = sizeOf(_hollowStd);
    final thicknesses = [
      for (final s in kHollowSizes)
        if (sizeOf(s) == curSize) s
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('sw-hollow-custom'),
          contentPadding: EdgeInsets.zero,
          value: _hollowCustom,
          title: Text(context.tr(pl: 'Własny wymiar', en: 'Custom size')),
          subtitle: Text(
            context.tr(
                pl: 'Np. 30×20×2 spoza tabeli — wzór EN 10219-2',
                en: 'E.g. 30×20×2 not in the table — EN 10219-2 formula'),
            style: const TextStyle(fontSize: 12, color: kTextMut),
          ),
          onChanged: (v) => setState(() => _hollowCustom = v),
        ),
        const SizedBox(height: 6),
        if (_hollowCustom) ...[
          FieldPair(
            left: _num('hollow-h', context.tr(pl: 'Bok H', en: 'Side H'),
                _hollowH, (v) => _hollowH = v),
            right: _num('hollow-b', context.tr(pl: 'Bok B', en: 'Side B'),
                _hollowB, (v) => _hollowB = v),
          ),
          const SizedBox(height: 10),
          _num('hollow-t', context.tr(pl: 'Ścianka t', en: 'Wall t'), _hollowT,
              (v) => _hollowT = v),
        ] else ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('sw-hollow-size'),
            initialValue: curSize,
            isExpanded: true,
            menuMaxHeight: 420,
            decoration: _dropDecoration(context.tr(
                pl: 'Wymiar EN 10219-2 [mm]', en: 'EN 10219-2 size [mm]')),
            items: [
              for (final s in sizes)
                DropdownMenuItem(
                  value: s,
                  child: Text(s,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              unawaited(Haptic.tap());
              final same = [
                for (final s in kHollowSizes)
                  if (sizeOf(s) == v) s
              ];
              same.sort((x, y) => (x.$3 - _hollowStd.$3)
                  .abs()
                  .compareTo((y.$3 - _hollowStd.$3).abs()));
              setState(() => _hollowStd = same.first);
            },
          ),
          const SizedBox(height: 10),
          Text(context.tr(pl: 'Ścianka t', en: 'Wall t'),
              style: const TextStyle(fontSize: 12.5, color: kTextSec)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in thicknesses)
                ChoiceChip(
                  key: ValueKey('sw-hollow-t-${fmtDim(s.$3)}'),
                  label: Text('${fmtDim(s.$3)} mm'),
                  selected: s == _hollowStd,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    unawaited(Haptic.tap());
                    setState(() => _hollowStd = s);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _lengthInputs() {
    final countField = _num('count', context.tr(pl: 'Sztuk', en: 'Pieces'),
        _count, (v) => _count = v,
        unit: context.tr(pl: 'szt.', en: 'pcs'), decimal: false, decimals: 0);
    if (_shape == SteelShape.plate) {
      return Column(
        children: [
          FieldPair(
            left: _num(
                'plate-w-$_draftGen',
                context.tr(pl: 'Szerokość arkusza', en: 'Sheet width'),
                _plateW,
                (v) => _plateW = v,
                decimals: 1),
            right: _num(
                'plate-l-$_draftGen',
                context.tr(pl: 'Długość arkusza', en: 'Sheet length'),
                _plateL,
                (v) => _plateL = v,
                decimals: 1),
          ),
          const SizedBox(height: 10),
          countField,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (w, l) in const [
                (1000.0, 2000.0),
                (1250.0, 2500.0),
                (1500.0, 3000.0),
                (2000.0, 6000.0)
              ])
                ActionChip(
                  key: ValueKey('sw-sheet-${w.round()}x${l.round()}'),
                  label: Text('${fmtDim(w)}×${fmtDim(l)}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => setState(() {
                    _plateW = w;
                    _plateL = l;
                    _draftGen++;
                  }),
                ),
            ],
          ),
        ],
      );
    }
    final len = _lengthMm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldPair(
          left: _num(
              'len-$_draftGen',
              context.tr(pl: 'Długość sztuki', en: 'Piece length'),
              _lengthMm,
              (v) => _lengthMm = v,
              decimals: 1,
              helper: len != null && len > 0
                  ? '= ${fmtNum(len / 1000, decimals: 3, english: _en)} m'
                  : null),
          right: countField,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [1.0, 3.0, 6.0, 12.0])
              ActionChip(
                key: ValueKey('sw-len-${(m * 1000).round()}'),
                label: Text('${fmtDim(m)} m'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => setState(() {
                  _lengthMm = m * 1000;
                  _draftGen++;
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _materialChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in SteelMaterial.values)
              ChoiceChip(
                key: ValueKey('sw-mat-${m.name}'),
                label: Text(m.label(_en)),
                selected: _material == m,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  unawaited(Haptic.tap());
                  setState(() => _material = m);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
              pl: 'Gęstość ${fmtNum(_material.density, decimals: 0)} kg/m³',
              en: 'Density ${fmtNum(_material.density, decimals: 0, english: true)} kg/m³'),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      ],
    );
  }

  String _problemText(SteelItemProblem p) => switch (p) {
        SteelItemProblem.noSection => context.tr(
            pl: 'Wybierz wymiar z tablicy.', en: 'Pick a size from the table.'),
        SteelItemProblem.badDimensions => _shape == SteelShape.plate
            ? context.tr(
                pl: 'Wpisz grubość i szerokość arkusza.',
                en: 'Enter the sheet thickness and width.')
            : context.tr(
                pl: 'Wpisz wymiary przekroju większe od zera.',
                en: 'Enter cross-section dimensions greater than zero.'),
        SteelItemProblem.wallTooThick => context.tr(
            pl: 'Ścianka za gruba do tych boków (naroże EN 10219-2 to 2–3 × t).',
            en: 'Wall too thick for these sides (EN 10219-2 corner is 2–3 × t).'),
        SteelItemProblem.noLength => _shape == SteelShape.plate
            ? context.tr(
                pl: 'Wpisz długość arkusza.', en: 'Enter the sheet length.')
            : context.tr(
                pl: 'Wpisz długość sztuki.', en: 'Enter the piece length.'),
        SteelItemProblem.noCount => context.tr(
            pl: 'Liczba sztuk: co najmniej 1.', en: 'Pieces: at least 1.'),
      };

  Widget _resultSection(SteelItem item) {
    final problem = item.problem;
    if (problem != null) {
      return QuoteSection(
        title: context.tr(pl: 'Wynik', en: 'Result'),
        children: [
          QuoteNotice(
            key: const ValueKey('sw-problem'),
            text: _problemText(problem),
            icon: Icons.edit_outlined,
          ),
        ],
      );
    }
    final en = _en;
    final plate = item.shape == SteelShape.plate;
    String kg(double v) => fmtKg(v, english: en);
    final paint = item.paintM2PerM;
    final totalPaint = item.totalPaintM2;
    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        Readout(
          key: const ValueKey('sw-mass'),
          label: context.tr(pl: 'Masa razem', en: 'Total mass'),
          value: kg(item.totalKg),
          unit: plate
              ? context.tr(
                  pl: 'kg · ${item.count} ark. ${fmtDim(item.t)}×${fmtDim(item.a)}×${fmtDim(item.lengthMm)} mm',
                  en: 'kg · ${item.count} sheets ${fmtDim(item.t)}×${fmtDim(item.a)}×${fmtDim(item.lengthMm)} mm')
              : 'kg · ${item.label(english: en)} · '
                  '${item.count} × ${fmtDim(item.lengthMm)} mm',
          hot: true,
        ),
        const SizedBox(height: 12),
        _tiles([
          FactTile(
            key: const ValueKey('sw-fact-unit'),
            icon: Icons.straighten,
            label: plate
                ? context.tr(pl: 'Masa 1 m²', en: 'Mass per m²')
                : context.tr(pl: 'Masa 1 m', en: 'Mass per metre'),
            value: plate
                ? '${fmtNum(item.kgPerM2, decimals: 2, english: en)} kg/m²'
                : '${fmtNum(item.kgPerM, decimals: 2, english: en)} kg/m',
          ),
          FactTile(
            key: const ValueKey('sw-fact-piece'),
            icon: Icons.fitness_center,
            label: plate
                ? context.tr(pl: 'Masa arkusza', en: 'Sheet mass')
                : context.tr(pl: 'Masa sztuki', en: 'Piece mass'),
            value: '${kg(item.pieceKg)} kg',
          ),
          FactTile(
            icon: plate ? Icons.crop_square : Icons.linear_scale,
            label: plate
                ? context.tr(pl: 'Powierzchnia arkuszy', en: 'Sheet area')
                : context.tr(pl: 'Długość łączna', en: 'Total length'),
            value: plate
                ? '${fmtNum(item.plateAreaM2, decimals: 2, english: en)} m²'
                : '${fmtNum(item.totalLengthM, decimals: 2, english: en)} m',
          ),
          FactTile(
            key: const ValueKey('sw-fact-paint'),
            icon: Icons.format_paint_outlined,
            label: context.tr(pl: 'Malowanie', en: 'Painting area'),
            value: paint == null
                ? '—'
                : '${fmtNum(paint, decimals: 3, english: en)} m²/m',
            sub: totalPaint == null
                ? context.tr(pl: 'brak w źródle', en: 'not in the source')
                : context.tr(
                    pl: 'razem ${fmtNum(totalPaint, decimals: 2)} m²',
                    en: 'total ${fmtNum(totalPaint, decimals: 2, english: true)} m²'),
          ),
        ]),
        const SizedBox(height: 10),
        ..._details(item),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('sw-add'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: () => _add(item),
          icon: const Icon(Icons.playlist_add),
          label: Text(
            context.tr(pl: 'Dodaj do listy', en: 'Add to list'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  /// Kafle 2 × 2 (na wąskim ekranie jeden pod drugim).
  Widget _tiles(List<Widget> tiles) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 300) {
        return Column(children: [
          for (final t in tiles) ...[t, const SizedBox(height: 8)],
        ]);
      }
      return Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]);
    });
  }

  List<Widget> _details(SteelItem item) {
    final en = _en;
    const style = TextStyle(fontSize: 12.5, color: kTextSec, height: 1.4);
    const muted = TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4);
    final s = item.tableSection;
    final lines = <Widget>[];
    if (s != null) {
      final dims = s.family == SectionFamily.angle
          ? 'a ${fmtDim(s.h)} · b ${fmtDim(s.b)} · t ${fmtDim(s.t)} · '
              'r1 ${fmtDim(s.r1)} · r2 ${fmtDim(s.r2!)} mm'
          : 'h ${fmtDim(s.h)} · b ${fmtDim(s.b)} · tw ${fmtDim(s.tw)} · '
              'tf ${fmtDim(s.tf)} · r ${fmtDim(s.r1)} mm';
      lines.add(Text(dims, key: const ValueKey('sw-dims'), style: style));
    } else if (item.shape == SteelShape.hollow) {
      final r = en10219Radii(item.t);
      lines.add(Text(
          '${item.label(english: en)} · ro ${fmtDim(r.ro)} · ri ${fmtDim(r.ri)} mm',
          key: const ValueKey('sw-dims'),
          style: style));
    }
    final source = switch (item.shape) {
      SteelShape.ipe ||
      SteelShape.hea ||
      SteelShape.heb ||
      SteelShape.hem =>
        context.tr(
            pl: 'Masa i wymiary: EN 10365 (tablice ArcelorMittal / eurocodeapplied.com), stal 7850 kg/m³. Malowanie: obwód z tablicy.',
            en: 'Mass and size: EN 10365 (ArcelorMittal / eurocodeapplied.com tables), steel 7850 kg/m³. Painting: perimeter from the table.'),
      SteelShape.upn => context.tr(
          pl: 'Masa i wymiary: EN 10365 / DIN 1026-1 (ArcelorMittal), stal 7850 kg/m³. Malowanie: AL z katalogu ArcelorMittal.',
          en: 'Mass and size: EN 10365 / DIN 1026-1 (ArcelorMittal), steel 7850 kg/m³. Painting: AL from the ArcelorMittal catalogue.'),
      SteelShape.upe => context.tr(
          pl: 'Masa i wymiary: EN 10365 (ArcelorMittal), stal 7850 kg/m³. Malowanie: z geometrii przekroju.',
          en: 'Mass and size: EN 10365 (ArcelorMittal), steel 7850 kg/m³. Painting: from the section geometry.'),
      SteelShape.angleEqual || SteelShape.angleUnequal => context.tr(
          pl: 'Masa: EN 10056-1 (SCI Blue Book, ArcelorMittal), stal 7850 kg/m³. Malowanie: z geometrii przekroju.',
          en: 'Mass: EN 10056-1 (SCI Blue Book, ArcelorMittal), steel 7850 kg/m³. Painting: from the section geometry.'),
      SteelShape.hollow => context.tr(
          pl: 'Zimnogięty EN 10219-2: masa i obwód wzorem normy (naroża zaokrąglone ro, ri).',
          en: 'Cold-formed EN 10219-2: mass and perimeter by the standard formula (rounded corners ro, ri).'),
      _ => context.tr(
          pl: 'Z wymiarów nominalnych (krawędzie ostre) × gęstość materiału.',
          en: 'From nominal dimensions (sharp edges) × material density.'),
    };
    lines
      ..add(const SizedBox(height: 4))
      ..add(Text(source, style: muted));
    if (item.shape.tabulated && item.material != SteelMaterial.carbon) {
      lines
        ..add(const SizedBox(height: 4))
        ..add(Text(
          context.tr(
              pl: 'Tablica jest dla stali 7850 kg/m³ — masę przeliczono × ${fmtNum(item.material.density, decimals: 0)}/7850 (ten sam przekrój).',
              en: 'The table is for steel 7850 kg/m³ — mass scaled × ${fmtNum(item.material.density, decimals: 0, english: true)}/7850 (same section).'),
          style: muted.copyWith(color: kWarn),
        ));
    }
    return lines;
  }

  // ═══ Zakładka: Lista ════════════════════════════════════════════════════

  Widget _listTab() {
    final en = _en;
    final s = summarizeOrder(_order, english: en);
    final items = _order.items;
    String kg(double v) => fmtKg(v, english: en);
    final waste = fmtNum(_order.wastePct, decimals: 1, english: en)
        .replaceFirst(RegExp(r'[,.]0$'), '');
    return ListView(
      key: const ValueKey('sw-list-list'),
      padding: _pagePadding,
      children: [
        if (items.isEmpty)
          QuoteNotice(
            key: const ValueKey('sw-empty'),
            icon: Icons.playlist_add,
            color: kTextSec,
            text: context.tr(
                pl: 'Lista jest pusta. Wybierz profil w zakładce „Profil" i stuknij „Dodaj do listy".',
                en: 'The list is empty. Pick a section on the “Section” tab and tap “Add to list”.'),
          )
        else ...[
          QuoteSection(
            title: context.tr(pl: 'Zamówienie', en: 'Order'),
            children: [
              Readout(
                key: const ValueKey('sw-order-mass'),
                label: context.tr(pl: 'Do zamówienia', en: 'To order'),
                value: kg(s.orderKg),
                unit: context.tr(
                    pl: 'kg · netto ${kg(s.netKg)} kg + zapas $waste %',
                    en: 'kg · net ${kg(s.netKg)} kg + $waste % allowance'),
                hot: true,
              ),
              const SizedBox(height: 12),
              _kv(context.tr(pl: 'Masa netto', en: 'Net mass'),
                  '${kg(s.netKg)} kg'),
              _kv(context.tr(pl: 'Zapas $waste %', en: 'Allowance $waste %'),
                  '+${kg(s.wasteKg)} kg'),
              if (s.totalLengthM > 0)
                _kv(
                    context.tr(
                        pl: 'Długość łączna (bez blach)',
                        en: 'Total length (without plates)'),
                    '${fmtNum(s.totalLengthM, decimals: 2, english: en)} m'),
              if (s.paintM2 > 0)
                _kv(
                    context.tr(pl: 'Malowanie', en: 'Painting area'),
                    '${fmtNum(s.paintM2, decimals: 1, english: en)} m²'
                    '${s.unpaintedItems > 0 ? ' *' : ''}'),
              if (s.unpaintedItems > 0 && s.paintM2 > 0)
                Text(
                  context.tr(
                      pl: '* bez ${s.unpaintedItems} poz. — źródło nie podaje powierzchni',
                      en: '* excluding ${s.unpaintedItems} item(s) — no area in the source'),
                  style: const TextStyle(fontSize: 11.5, color: kTextMut),
                ),
              const Divider(height: 20),
              if (s.netGrosze == null)
                Text(
                  context.tr(
                      pl: 'Wpisz cenę za kg niżej, żeby policzyć koszt.',
                      en: 'Enter the price per kg below to get the cost.'),
                  style: const TextStyle(fontSize: 12.5, color: kTextSec),
                )
              else ...[
                MoneyRow(
                  label: context.tr(pl: 'Koszt netto', en: 'Net cost'),
                  grosze: s.netGrosze!,
                ),
                MoneyRow(
                  label: context.tr(
                      pl: 'Zapas $waste %', en: 'Allowance $waste %'),
                  grosze: s.wasteGrosze!,
                ),
                MoneyRow(
                  key: const ValueKey('sw-order-cost'),
                  label: context.tr(
                      pl: 'Razem z zapasem', en: 'Total with allowance'),
                  grosze: s.orderGrosze!,
                  strong: true,
                ),
                if (s.unpricedItems > 0)
                  Text(
                    context.tr(
                        pl: 'Pozycje bez ceny: ${s.unpricedItems} — nie wchodzą do kosztu.',
                        en: 'Items without a price: ${s.unpricedItems} — not in the cost.'),
                    style: const TextStyle(fontSize: 11.5, color: kWarn),
                  ),
              ],
            ],
          ),
          QuoteSection(
            title: context.tr(
                pl: 'Pozycje (${items.length})', en: 'Items (${items.length})'),
            subtitle: context.tr(
                pl: 'Stuknij pozycję, żeby zmienić długość, sztuki lub cenę.',
                en: 'Tap an item to change its length, pieces or price.'),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
            children: [
              for (final (i, item) in items.indexed) _itemTile(i, item),
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Razem wg profili', en: 'Totals by section'),
            children: [
              for (final g in s.groups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, color: kText)),
                            Text(
                              g.shape == SteelShape.plate
                                  ? context.tr(
                                      pl:
                                          '${g.pieces} ark. · ${fmtNum(g.areaM2, decimals: 2)} m²',
                                      en:
                                          '${g.pieces} sheets · ${fmtNum(g.areaM2, decimals: 2, english: true)} m²')
                                  : context.tr(
                                      pl: '${fmtNum(g.lengthM, decimals: 2)} m · ${g.pieces} szt.',
                                      en: '${fmtNum(g.lengthM, decimals: 2, english: true)} m · ${g.pieces} pcs'),
                              style: const TextStyle(
                                  fontSize: 12.5, color: kTextSec),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${kg(g.kg)} kg',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kText,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                    ],
                  ),
                ),
            ],
          ),
        ],
        QuoteSection(
          title: context.tr(pl: 'Cena i zapas', en: 'Price and allowance'),
          children: [
            FieldPair(
              left: QuoteNumberField(
                key: ValueKey('sw-price-$_listGen'),
                label: context.tr(pl: 'Cena stali', en: 'Steel price'),
                value: _order.pricePerKg,
                unit: 'zł/kg',
                helper: context.tr(
                    pl: 'Dla pozycji bez własnej ceny',
                    en: 'For items without their own price'),
                validate: (v) => v != null && v < 0
                    ? context.tr(pl: 'Poza zakresem', en: 'Out of range')
                    : null,
                onChanged: (v) {
                  if (v == null) {
                    _setOrder(_order.copyWith(clearPrice: true));
                  } else if (v >= 0) {
                    _setOrder(_order.copyWith(pricePerKg: v));
                  }
                },
              ),
              right: QuoteNumberField(
                key: ValueKey('sw-waste-$_listGen'),
                label: context.tr(pl: 'Zapas na odpady', en: 'Waste allowance'),
                value: _order.wastePct,
                unit: '%',
                decimals: 1,
                validate: (v) => v != null && (v < 0 || v > 100)
                    ? context.tr(pl: 'Poza zakresem', en: 'Out of range')
                    : null,
                onChanged: (v) {
                  if (v != null && v >= 0 && v <= 100) {
                    _setOrder(_order.copyWith(wastePct: v));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [0.0, 5.0, 10.0, 15.0])
                  ActionChip(
                    key: ValueKey('sw-waste-preset-${p.round()}'),
                    label: Text('+${p.round()} %'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onPressed: () {
                      _listGen++;
                      _setOrder(_order.copyWith(wastePct: p));
                    },
                  ),
              ],
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          FilledButton.icon(
            key: const ValueKey('sw-share'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _share,
            icon: const Icon(Icons.ios_share),
            label: Text(
              context.tr(pl: 'Udostępnij listę', en: 'Share the list'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('sw-clear'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget)),
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(context.tr(pl: 'Wyczyść listę', en: 'Clear the list')),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          context.tr(
              pl: 'Masy nominalne. Rzeczywista masa wyrobu mieści się w tolerancji jego normy — do dźwigu i transportu licz z zapasem.',
              en: 'Nominal masses. The actual mass lies within the product standard tolerance — allow a margin for lifting and transport.'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13.5, color: kTextSec))),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kText,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }

  Widget _itemTile(int i, SteelItem item) {
    final en = _en;
    final plate = item.shape == SteelShape.plate;
    final own = item.unitPrice;
    final price = own == null
        ? ''
        : ' · ${fmtNum(own, decimals: 2, english: en)} '
            '${item.priceUnit == PriceUnit.perM ? 'zł/m' : 'zł/kg'}';
    final sub = plate
        ? context.tr(
            pl: '${item.count} ark. · ${fmtNum(item.kgPerM2, decimals: 1)} kg/m²$price',
            en: '${item.count} sheets · ${fmtNum(item.kgPerM2, decimals: 1, english: true)} kg/m²$price')
        : '${item.count} × ${fmtDim(item.lengthMm)} mm · '
            '${fmtNum(item.kgPerM, decimals: 2, english: en)} kg/m$price';
    return ListTile(
      key: ValueKey('sw-item-$i'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 6,
      title: Text(item.label(english: en),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
      onTap: () => _editItem(i),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${fmtKg(item.totalKg, english: en)} kg',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kText,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
          IconButton(
            key: ValueKey('sw-del-$i'),
            tooltip: context.tr(pl: 'Usuń pozycję', en: 'Remove item'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            icon: const Icon(Icons.delete_outline, color: kTextSec),
            onPressed: () {
              unawaited(Haptic.tap());
              final list = [..._order.items]..removeAt(i);
              _setOrder(_order.copyWith(items: list));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editItem(int i) async {
    final generation = _loadGeneration;
    final item = _order.items[i];
    final plate = item.shape == SteelShape.plate;
    double? len = item.lengthMm;
    double? n = item.count.toDouble();
    double? price = item.unitPrice;
    var unit = item.priceUnit;
    final result = await _showOrderDialog<SteelItem>( (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final draft = item.copyWith(
          lengthMm: len ?? 0,
          count: (n ?? 0).round(),
          unitPrice: price,
          clearPrice: price == null,
          priceUnit: unit,
        );
        return AlertDialog(
          title: Text(item.label(english: _en)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuoteNumberField(
                  key: const ValueKey('sw-edit-len'),
                  label: plate
                      ? context.tr(pl: 'Długość arkusza', en: 'Sheet length')
                      : context.tr(pl: 'Długość sztuki', en: 'Piece length'),
                  value: len,
                  unit: 'mm',
                  decimals: 1,
                  onChanged: (v) => setD(() => len = v),
                ),
                const SizedBox(height: 10),
                QuoteNumberField(
                  key: const ValueKey('sw-edit-count'),
                  label: context.tr(pl: 'Sztuk', en: 'Pieces'),
                  value: n,
                  unit: context.tr(pl: 'szt.', en: 'pcs'),
                  decimal: false,
                  decimals: 0,
                  onChanged: (v) => setD(() => n = v),
                ),
                const SizedBox(height: 10),
                QuoteNumberField(
                  key: const ValueKey('sw-edit-price'),
                  label: context.tr(
                      pl: 'Cena tej pozycji', en: 'Price of this item'),
                  value: price,
                  unit: unit == PriceUnit.perM ? 'zł/m' : 'zł/kg',
                  helper: context.tr(
                      pl: 'Puste = cena za kg z listy',
                      en: 'Empty = list price per kg'),
                  onChanged: (v) => setD(() => price = v),
                ),
                if (!plate) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final u in PriceUnit.values)
                        ChoiceChip(
                          key: ValueKey('sw-edit-unit-${u.name}'),
                          label: Text(u == PriceUnit.perM ? 'zł/m' : 'zł/kg'),
                          selected: unit == u,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) => setD(() => unit = u),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  draft.isValid
                      ? context.tr(
                          pl: 'Masa: ${fmtKg(draft.totalKg)} kg'
                              '${itemCostGrosze(draft, _order.pricePerKg) == null ? '' : ' · ${formatPln(itemCostGrosze(draft, _order.pricePerKg)!)}'}',
                          en: 'Mass: ${fmtKg(draft.totalKg, english: true)} kg'
                              '${itemCostGrosze(draft, _order.pricePerKg) == null ? '' : ' · ${formatPln(itemCostGrosze(draft, _order.pricePerKg)!)}'}')
                      : _problemText(draft.problem!),
                  style: TextStyle(
                      fontSize: 13,
                      color: draft.isValid ? kText : kWarn,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            FilledButton(
              key: const ValueKey('sw-edit-save'),
              onPressed:
                  draft.isValid ? () => Navigator.of(ctx).pop(draft) : null,
              child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
            ),
          ],
        );
      }),
    );
    if (result == null || !mounted || generation != _loadGeneration) return;
    final list = [..._order.items];
    if (i < list.length) list[i] = result;
    _setOrder(_order.copyWith(items: list));
  }
}
