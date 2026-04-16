import 'dart:convert';

import 'package:crypto/crypto.dart';

class WelderPipeSignature {
  static String signature(Map<String, dynamic> payload) {
    final normalized = _normalize(payload);
    final jsonStr = jsonEncode(normalized);
    return sha256.convert(utf8.encode(jsonStr)).toString();
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> p) {
    final keys = p.keys.toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k.trim()] = _normalizeValue(p[k]);
    }
    return out;
  }

  static dynamic _normalizeValue(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return _round(v.toDouble(), 4);
    if (v is String) return v.trim().toUpperCase();
    if (v is List) return v.map(_normalizeValue).toList();
    if (v is Map<String, dynamic>) return _normalize(v);
    return v.toString().trim().toUpperCase();
  }

  static double _round(double x, int places) {
    final p = _pow10(places);
    return (x * p).roundToDouble() / p;
  }

  static double _pow10(int n) {
    double v = 1;
    for (int i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}
