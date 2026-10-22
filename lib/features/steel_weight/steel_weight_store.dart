// Account-bound local steel lists. Legacy device data remains the guest list.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/local_record_owner.dart';
import '../../domain/steel_weight/steel_weight.dart';

class SteelOrderStore {
  static const String key = 'steel_weight_order_v1';
  const SteelOrderStore() : _owner = null;
  const SteelOrderStore.forOwner(LocalRecordOwner owner) : _owner = owner;
  final LocalRecordOwner? _owner;

  static String keyForScope(String scope) => scope == LocalRecordOwner.guest
      ? key
      : 'steel_weight_order_v2.${base64Url.encode(utf8.encode(scope))}';

  Future<SteelOrder> load() async {
    final owner = _owner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    final prefs = await SharedPreferences.getInstance();
    owner.requireCurrent();
    final raw = prefs.getString(keyForScope(owner.key));
    if (raw == null || raw.isEmpty) return const SteelOrder();
    try {
      return SteelOrder.fromJson(jsonDecode(raw));
    } on FormatException {
      return const SteelOrder();
    }
  }

  Future<void> save(SteelOrder order) async {
    final owner = _owner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    final encoded = jsonEncode(order.toJson());
    final prefs = await SharedPreferences.getInstance();
    owner.requireCurrent();
    if (!await prefs.setString(keyForScope(owner.key), encoded)) {
      throw StateError('Could not persist the steel list');
    }
    owner.requireCurrent();
  }
}
