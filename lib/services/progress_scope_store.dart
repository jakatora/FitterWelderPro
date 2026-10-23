/// Zakres pracy (spoiny / DI do wykonania, termin, soboty) zapamiętany per
/// projekt i pakiet w SharedPreferences. Nie dotyka bazy: dziennik spoin
/// zostaje jedynym źródłem tego, co zrobione.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'owned_prefs.dart';

import '../domain/progress/progress_forecast.dart';

class ProgressScopeStore {
  static const String prefix = 'work_progress.scope_v1.';

  const ProgressScopeStore();

  static String keyFor(String project, String testPackage) =>
      '$prefix${ProgressScope.keyFor(project, testPackage)}';

  /// Nigdy nie rzuca: nieczytelne preferencje = pusty zakres.
  Future<ProgressScope> load(String project, String testPackage) async {
    try {
      final prefs = await OwnedPrefs.instance();
      return ProgressScope.decode(prefs.getString(keyFor(project, testPackage)));
    } catch (e) {
      debugPrint('[work_progress] read scope failed: $e');
      return const ProgressScope();
    }
  }

  Future<void> save(
      String project, String testPackage, ProgressScope scope) async {
    final prefs = await OwnedPrefs.instance();
    await prefs.setString(keyFor(project, testPackage), scope.encode());
  }
}
