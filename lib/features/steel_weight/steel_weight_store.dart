// Zapis listy materiałowej „Ciężar stali" w SharedPreferences (JSON) —
// bez zmian schematu bazy.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/steel_weight/steel_weight.dart';

class SteelOrderStore {
  static const String key = 'steel_weight_order_v1';

  const SteelOrderStore();

  Future<SteelOrder> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const SteelOrder();
    try {
      return SteelOrder.fromJson(jsonDecode(raw));
    } on FormatException {
      return const SteelOrder();
    }
  }

  Future<void> save(SteelOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(order.toJson()));
  }
}
