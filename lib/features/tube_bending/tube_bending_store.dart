/// Ostatnia rurka z ekranu „Gięcie rurek” w SharedPreferences (JSON).
///
/// Celowo bez bazy SQLite: moduł nie zmienia schematu. Klucz ma wersję
/// w nazwie — przy zmianie formatu nowy klucz.
///
/// Uszkodzony zapis (nieczytelny JSON, wartość innego typu, niespójne
/// listy) NIE ginie przy następnym zapisie: zanim [TubeBendingStore.save]
/// go nadpisze, surowa wartość trafia pod [TubeBendingStore.corruptKey] —
/// istniejąca kopia nie jest nadpisywana, a inna uszkodzona wartość blokuje
/// nowy zapis, by jej nie zgubić. Ta sama zasada co
/// `bolt_kit_store.dart`. Po nieudanym ODCZYCIE (wyjątek platformy) pierwszy
/// zapis kopiuje surową wartość także wtedy, gdy była nienaruszona.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, protected;
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/fitter/tube_bending.dart';

enum TubeBendingMode { single, offset, multi }

/// Stan pól ekranu w mm / ° (null = puste pole).
class TubeBendingSaved {
  final TubeBendingMode mode;
  final TubeUnit unit;
  final double? clrMm;
  final double? minStraightMm;
  final double? markerOffsetMm;
  final double? springbackDeg;

  final double? singleAngleDeg;
  final double? singleLegAMm;
  final double? singleLegBMm;

  final double? offsetHeightMm;
  final double? offsetSpreadMm;
  final double? offsetAngleDeg;
  final double? offsetLegAMm;
  final double? offsetLegBMm;

  /// Rurka z wieloma gięciami: odcinki (o jeden więcej niż kątów), kąty
  /// i obroty (tyle co kątów).
  final List<double?> segmentsMm;
  final List<double?> anglesDeg;
  final List<double?> rotationsDeg;

  const TubeBendingSaved({
    required this.mode,
    required this.unit,
    required this.segmentsMm,
    required this.anglesDeg,
    required this.rotationsDeg,
    this.clrMm,
    this.minStraightMm,
    this.markerOffsetMm,
    this.springbackDeg,
    this.singleAngleDeg,
    this.singleLegAMm,
    this.singleLegBMm,
    this.offsetHeightMm,
    this.offsetSpreadMm,
    this.offsetAngleDeg,
    this.offsetLegAMm,
    this.offsetLegBMm,
  });
}

const int _format = 1;

Object? _n(double? v) => v == null || !v.isFinite ? null : v;

String encodeTubeBending(TubeBendingSaved s) => jsonEncode({
      'v': _format,
      'mode': s.mode.name,
      'unit': s.unit.name,
      'clr': _n(s.clrMm),
      'minStraight': _n(s.minStraightMm),
      'markerOffset': _n(s.markerOffsetMm),
      'springback': _n(s.springbackDeg),
      'single': [
        _n(s.singleAngleDeg),
        _n(s.singleLegAMm),
        _n(s.singleLegBMm),
      ],
      'offset': [
        _n(s.offsetHeightMm),
        _n(s.offsetSpreadMm),
        _n(s.offsetAngleDeg),
        _n(s.offsetLegAMm),
        _n(s.offsetLegBMm),
      ],
      'segments': [for (final v in s.segmentsMm) _n(v)],
      'angles': [for (final v in s.anglesDeg) _n(v)],
      'rotations': [for (final v in s.rotationsDeg) _n(v)],
    });

class _Bad implements Exception {
  const _Bad();
}

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num && v.isFinite) return v.toDouble();
  throw const _Bad();
}

List<double?> _list(Object? v, {int? length}) {
  if (v is! List) throw const _Bad();
  if (length != null && v.length != length) throw const _Bad();
  return [for (final e in v) _num(e)];
}

T _enum<T extends Enum>(List<T> values, Object? name) {
  for (final e in values) {
    if (e.name == name) return e;
  }
  throw const _Bad();
}

/// Odczyt: stan albo `null` i `intact: false`, gdy zapis jest uszkodzony.
/// `null` na wejściu (brak zapisu) — `intact: true`, stan `null`.
({TubeBendingSaved? state, bool intact}) decodeTubeBending(String? raw) {
  if (raw == null) return (state: null, intact: true);
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['v'] != _format) throw const _Bad();
    final single = _list(m['single'], length: 3);
    final offset = _list(m['offset'], length: 5);
    final angles = _list(m['angles']);
    final segments = _list(m['segments'], length: angles.length + 1);
    final rotations = _list(m['rotations'], length: angles.length);
    if (angles.isEmpty || angles.length > kMaxTubeBends) throw const _Bad();
    return (
      state: TubeBendingSaved(
        mode: _enum(TubeBendingMode.values, m['mode']),
        unit: _enum(TubeUnit.values, m['unit']),
        clrMm: _num(m['clr']),
        minStraightMm: _num(m['minStraight']),
        markerOffsetMm: _num(m['markerOffset']),
        springbackDeg: _num(m['springback']),
        singleAngleDeg: single[0],
        singleLegAMm: single[1],
        singleLegBMm: single[2],
        offsetHeightMm: offset[0],
        offsetSpreadMm: offset[1],
        offsetAngleDeg: offset[2],
        offsetLegAMm: offset[3],
        offsetLegBMm: offset[4],
        segmentsMm: segments,
        anglesDeg: angles,
        rotationsDeg: rotations,
      ),
      intact: true,
    );
  } catch (_) {
    return (state: null, intact: false);
  }
}

class TubeBendingLoad {
  final TubeBendingSaved? state;

  /// Coś było zapisane, ale nie dało się tego odczytać.
  final bool damaged;

  /// Odczyt rzucił wyjątek — w pamięci może leżeć dobra rurka.
  final bool readFailed;

  const TubeBendingLoad(this.state,
      {this.damaged = false, this.readFailed = false});
}

class TubeBendingStore {
  static const String key = 'tube_bending_v1';
  static const String corruptKey = 'tube_bending_v1_corrupt';

  const TubeBendingStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  /// Surowa wartość spod [key] (punkt podmiany w teście).
  @protected
  Future<Object?> readRaw() async =>
      (await OwnedPrefs.instance(captureOwner)).get(key);

  /// Nigdy nie rzuca.
  Future<TubeBendingLoad> load() async {
    try {
      final raw = await readRaw();
      if (raw == null) return const TubeBendingLoad(null);
      if (raw is! String) return const TubeBendingLoad(null, damaged: true);
      final d = decodeTubeBending(raw);
      return TubeBendingLoad(d.state, damaged: !d.intact);
    } catch (e) {
      debugPrint('[tube_bending] read failed: $e');
      return const TubeBendingLoad(null, damaged: true, readFailed: true);
    }
  }

  /// Zapis; przed nadpisaniem uszkodzonej (albo nieodczytanej —
  /// [afterFailedRead]) wartości robi jej kopię pod [corruptKey]. Jeśli
  /// miejsce kopii zajmuje inna wartość, wstrzymuje zapis.
  Future<void> save(TubeBendingSaved state,
      {bool afterFailedRead = false}) async {
    final prefs = await OwnedPrefs.instance(captureOwner);
    final raw = prefs.get(key);
    if (raw != null) {
      final damaged = raw is! String || !decodeTubeBending(raw).intact;
      if (damaged || afterFailedRead) {
        final copy = raw is String ? raw : _describe(raw);
        final existing = prefs.get(corruptKey);
        if (existing != null && existing != copy) {
          throw StateError(
              'Different tube bending record is already backed up');
        }
        if (existing == null && !await prefs.setString(corruptKey, copy)) {
          throw StateError('Could not back up tube bending record');
        }
      }
    }
    if (!await prefs.setString(key, encodeTubeBending(state))) {
      throw StateError('Could not save tube bending record');
    }
  }

  static String _describe(Object raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }
}
