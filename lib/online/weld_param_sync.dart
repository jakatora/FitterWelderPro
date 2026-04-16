import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/weld_param.dart';

class WeldParamSync {
  static double _r(double v, double step) => (v / step).round() * step;

  /// Canonical (100% match) representation used to build a stable hash.
  static Map<String, Object?> canonical(WeldParam p) {
    return {
      'method': p.method,
      'baseMaterial': p.baseMaterial,
      'diameterMm': _r(p.diameterMm, 0.1),
      'wallThicknessMm': _r(p.wallThicknessMm, 0.1),
      'electrodeMm': _r(p.electrodeMm, 0.1),
      'torchGasLpm': _r(p.torchGasLpm, 0.1),
      'nozzleType': (p.nozzleType ?? '').trim(),
      'nozzleSize': (p.nozzleSize ?? '').trim(),
      'purgeLpm': _r(p.purgeLpm, 0.1),
      'amps': _r(p.amps, 1.0),
    };
  }

  static String hashOf(WeldParam p) {
    final jsonStr = jsonEncode(canonical(p));
    return sha256.convert(utf8.encode(jsonStr)).toString();
  }

  static Future<void> upsert(WeldParam p) async {
  }

  static Future<void> deleteById(String id, WeldParam p) async {
  }
}
