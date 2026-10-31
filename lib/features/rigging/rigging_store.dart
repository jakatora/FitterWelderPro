/// Ostatnie dane kalkulatora zawiesi w SharedPreferences (JSON).
///
/// To kalkulator — utrata zapisu niczego nie kasuje poza wygodą, więc bez
/// kopii uszkodzonej wartości (inaczej niż historia protokołów). Odczyt
/// nie rzuca: uszkodzony albo nieczytelny zapis → wartości
/// domyślne z flagą `damaged` (ekran pokazuje informację).
///
/// Etykieta i lista kontrolna nie są zapisywane (rigging_inputs.dart).
library;

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart' show debugPrint;
import '../../database/local_record_owner.dart';
import '../../services/owned_prefs.dart';

import '../../domain/rigging/rigging_inputs.dart';

class RiggingStoreLoad {
  /// `null` — nic nie zapisano (pierwsze otwarcie).
  final RiggingSavedInputs? inputs;
  final bool damaged;
  const RiggingStoreLoad(this.inputs, {this.damaged = false});
}

class RiggingStore {
  static Future<void>? _writes;
  static const String key = 'rigging_inputs_v1';

  const RiggingStore({this.captureOwner});

  final Future<LocalRecordOwner> Function()? captureOwner;

  Future<RiggingStoreLoad> load() async {
    try {
      final pending = _writes;
      if (pending != null) await pending;
      final prefs = await OwnedPrefs.instance(captureOwner)
          .timeout(const Duration(seconds: 2));
      await prefs.reload().timeout(const Duration(seconds: 2));
      final raw = prefs.get(key);
      if (raw == null) return const RiggingStoreLoad(null);
      if (raw is! String) {
        return const RiggingStoreLoad(RiggingSavedInputs(), damaged: true);
      }
      final d = decodeRiggingInputs(raw);
      return RiggingStoreLoad(d.inputs, damaged: !d.intact);
    } catch (e) {
      debugPrint('[rigging] read failed: $e');
      return const RiggingStoreLoad(RiggingSavedInputs(), damaged: true);
    }
  }

  Future<void> save(RiggingSavedInputs inputs) {
    Object? captureError;
    StackTrace? captureStack;
    final prefsReady =
        OwnedPrefs.instance(captureOwner).then<SharedPreferences?>(
      (prefs) => prefs,
      onError: (Object error, StackTrace stack) {
        captureError = error;
        captureStack = stack;
        return null;
      },
    );
    final encoded = encodeRiggingInputs(inputs);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      if (!await prefs.setString(key, encoded)) {
        throw StateError('Could not save rigging settings');
      }
      await prefs.reload();
      if (prefs.getString(key) != encoded) {
        throw StateError('Rigging settings were not persisted');
      }
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }
}
