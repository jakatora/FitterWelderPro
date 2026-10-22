// Account-bound local steel lists. Legacy device data remains the guest list.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../domain/steel_weight/steel_weight.dart';

class SteelOrderConflict implements Exception {
  const SteelOrderConflict();
}

class _Baseline {
  String? encoded;
}

class SteelOrderStore {
  static const String key = 'steel_weight_order_v1';
  const SteelOrderStore()
      : _owner = null,
        _baseline = null;
  SteelOrderStore.forOwner(LocalRecordOwner owner)
      : _owner = owner,
        _baseline = _Baseline();
  final LocalRecordOwner? _owner;
  final _Baseline? _baseline;
  static final _tails = <String, Future<void>>{};

  static String keyForScope(String scope) => scope == LocalRecordOwner.guest
      ? key
      : 'steel_weight_order_v2.${base64Url.encode(utf8.encode(scope))}';

  Future<T> _serial<T>(String scope, Future<T> Function() operation) {
    final previous = _tails[scope];
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[scope] = tail;
    unawaited(tail.then((_) {
      if (identical(_tails[scope], tail)) _tails.remove(scope);
    }));
    return result;
  }

  void _validateOrder(SteelOrder order) {
    if (order.items.any((item) =>
            !item.isValid || !item.totalKg.isFinite || item.totalKg <= 0) ||
        order.pricePerKg != null &&
            (!order.pricePerKg!.isFinite || order.pricePerKg! < 0) ||
        !order.wastePct.isFinite ||
        order.wastePct < 0) {
      throw const FormatException('Invalid steel order');
    }
    // Keep the existing domain calculation; refuse operands outside exact
    // integer-grosz range before double rounding could saturate an estimate.
    const maxExactGrosze = 9007199254740991.0;
    var pricedGrosze = 0;
    for (final item in order.items) {
      final own = item.unitPrice;
      if (own != null && (!own.isFinite || own < 0)) {
        throw const FormatException('Invalid item price');
      }
      final price = own ?? order.pricePerKg;
      if (price == null) continue;
      final quantity = own != null && item.priceUnit == PriceUnit.perM
          ? item.totalLengthM
          : item.totalKg;
      final raw = quantity * price * 100;
      if (!raw.isFinite || raw < 0 || raw > maxExactGrosze) {
        throw const FormatException(
            'Steel item cost exceeds the supported range');
      }
      pricedGrosze += itemCostGrosze(item, order.pricePerKg)!;
      if (pricedGrosze > maxExactGrosze) {
        throw const FormatException(
            'Steel order cost exceeds the supported range');
      }
    }
    final allowance = pricedGrosze * order.wastePct / 100;
    if (!allowance.isFinite ||
        allowance < 0 ||
        allowance > maxExactGrosze - pricedGrosze) {
      throw const FormatException(
          'Steel allowance exceeds the supported range');
    }
    final totals = summarizeOrder(order);
    if (!totals.netKg.isFinite ||
        !totals.orderKg.isFinite ||
        !totals.totalLengthM.isFinite ||
        !totals.paintM2.isFinite) {
      throw const FormatException(
          'Steel order geometry exceeds the supported range');
    }
    final ids =
        order.items.map((item) => item.recordId).whereType<String>().toList();
    if (ids.any((id) => id.isEmpty || id.length > 128) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid steel record identity');
    }
  }

  Future<SteelOrder> _read(LocalRecordOwner owner) async {
    owner.requireCurrent();
    final prefs = await SharedPreferences.getInstance();
    await prefs
        .reload(); // Do not treat a failed write's optimistic cache as disk truth.
    owner.requireCurrent();
    final raw = prefs.getString(keyForScope(owner.key));
    if (raw == null || raw.isEmpty) return const SteelOrder();
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['v'] != 1 || decoded['items'] is! List) {
      throw const FormatException('Invalid steel list');
    }
    final rows = decoded['items'] as List;
    for (final row in rows) {
      if (row is! Map) throw const FormatException('Invalid steel item');
      final quantity = row['n'];
      if (quantity is! num ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity != quantity.roundToDouble() ||
          quantity.toInt() != quantity) {
        throw const FormatException('Invalid steel record quantity');
      }
      final material = row['mat'];
      if (material != null &&
          !SteelMaterial.values.any((value) => value.name == material)) {
        throw const FormatException('Invalid steel material');
      }
      final ownPrice = row['price'], priceUnit = row['pu'];
      if (ownPrice != null &&
          (ownPrice is! num || !ownPrice.isFinite || ownPrice < 0)) {
        throw const FormatException('Invalid steel item price');
      }
      if (priceUnit != null &&
          !PriceUnit.values.any((unit) => unit.name == priceUnit)) {
        throw const FormatException('Invalid steel price unit');
      }
      final id = row['recordId'];
      if (id != null && (id is! String || id.isEmpty || id.length > 128)) {
        throw const FormatException('Invalid steel record identity');
      }
    }
    for (final key in const ['priceKg', 'waste']) {
      final value = decoded[key];
      if (value != null && (value is! num || !value.isFinite || value < 0)) {
        throw const FormatException('Invalid steel list price or allowance');
      }
    }
    final order = SteelOrder.fromJson(decoded);
    if (order.items.length != rows.length ||
        order.pricePerKg != null &&
            (!order.pricePerKg!.isFinite || order.pricePerKg! < 0) ||
        !order.wastePct.isFinite ||
        order.wastePct < 0) {
      throw const FormatException('Invalid steel list data');
    }
    final ids =
        order.items.map((item) => item.recordId).whereType<String>().toList();
    if (ids.toSet().length != ids.length) {
      throw const FormatException('Duplicate steel record identity');
    }
    _validateOrder(order);
    return order;
  }

  Future<SteelOrder> load() async {
    final owner = _owner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    return _serial(owner.key, () async {
      final order = await _read(owner);
      _baseline?.encoded = jsonEncode(order.toJson());
      return order;
    });
  }

  /// Read persisted state without rebasing a page's optimistic write guard.
  Future<SteelOrder> readLatest() async {
    final owner = _owner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    return _serial(owner.key, () => _read(owner));
  }

  Future<void> save(SteelOrder order) async {
    final owner = _owner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    return _serial(owner.key, () async {
      _validateOrder(order);
      final encoded = jsonEncode(order.toJson());
      final current = jsonEncode((await _read(owner)).toJson());
      final expected = _baseline?.encoded;
      if (expected != null && current != expected && current != encoded) {
        throw const SteelOrderConflict();
      }
      if (current != encoded) {
        final prefs = await SharedPreferences.getInstance();
        owner.requireCurrent();
        if (!await prefs.setString(keyForScope(owner.key), encoded)) {
          throw StateError('Could not persist the steel list');
        }
        owner.requireCurrent();
        if (jsonEncode((await _read(owner)).toJson()) != encoded) {
          throw StateError('Steel list persistence could not be verified');
        }
      }
      _baseline?.encoded = encoded;
    });
  }
}
