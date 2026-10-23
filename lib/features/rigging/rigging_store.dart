/// Ostatnie dane kalkulatora zawiesi w SharedPreferences (JSON).
///
/// To kalkulator — utrata zapisu niczego nie kasuje poza wygodą, więc bez
/// kopii uszkodzonej wartości (inaczej niż historia protokołów). Odczyt
/// i zapis NIGDY nie rzucają: uszkodzony albo nieczytelny zapis → wartości
/// domyślne z flagą `damaged` (ekran pokazuje informację).
///
/// Etykieta i lista kontrolna nie są zapisywane (rigging_inputs.dart).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/owned_prefs.dart';

import '../../domain/rigging/rigging_inputs.dart';

class RiggingStoreLoad {
  /// `null` — nic nie zapisano (pierwsze otwarcie).
  final RiggingSavedInputs? inputs;
  final bool damaged;
  const RiggingStoreLoad(this.inputs, {this.damaged = false});
}

class RiggingStore {
  static const String key = 'rigging_inputs_v1';

  const RiggingStore();

  Future<RiggingStoreLoad> load() async {
    try {
      final prefs = await OwnedPrefs.instance()
          .timeout(const Duration(seconds: 2));
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

  Future<void> save(RiggingSavedInputs inputs) async {
    try {
      final prefs = await OwnedPrefs.instance();
      await prefs.setString(key, encodeRiggingInputs(inputs));
    } catch (e) {
      // Kalkulator działa dalej w tej sesji.
      debugPrint('[rigging] save failed: $e');
    }
  }
}
