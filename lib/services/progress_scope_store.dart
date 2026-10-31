/// Zakres pracy (spoiny / DI do wykonania, termin, soboty) zapamiętany per
/// projekt i pakiet w SharedPreferences. Nie dotyka bazy: dziennik spoin
/// zostaje jedynym źródłem tego, co zrobione.
library;

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../database/local_record_owner.dart';
import 'owned_prefs.dart';

import '../domain/progress/progress_forecast.dart';

class ProgressScopeStore {
  static Future<void>? _writes;
  static const String prefix = 'work_progress.scope_v1.';

  final Future<LocalRecordOwner> Function()? captureOwner;

  const ProgressScopeStore({this.captureOwner});

  static String keyFor(String project, String testPackage) =>
      '$prefix${ProgressScope.keyFor(project, testPackage)}';

  /// Nigdy nie rzuca: nieczytelne preferencje = pusty zakres.
  Future<ProgressScope> load(String project, String testPackage) async {
    try {
      final pending = _writes;
      if (pending != null) await pending;
      final prefs = await OwnedPrefs.instance(captureOwner);
      await prefs.reload();
      return ProgressScope.decode(
          prefs.getString(keyFor(project, testPackage)));
    } catch (e) {
      debugPrint('[work_progress] read scope failed: $e');
      return const ProgressScope();
    }
  }

  Future<void> save(String project, String testPackage, ProgressScope scope) {
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
    final encoded = scope.encode();
    final key = keyFor(project, testPackage);
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      final prefs = await prefsReady;
      if (prefs == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      await _saveNow(prefs, key, encoded);
    }();
    final settled =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return write;
  }

  Future<void> _saveNow(
      SharedPreferences prefs, String key, String encoded) async {
    if (!await prefs.setString(key, encoded)) {
      throw StateError('Could not save progress scope');
    }
    await prefs.reload();
    if (prefs.getString(key) != encoded) {
      throw StateError('Progress scope was not persisted');
    }
  }
}
