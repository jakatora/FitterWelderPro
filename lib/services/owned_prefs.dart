/// SharedPreferences widziane oczami jednego właściciela danych.
///
/// Zapisy zawodowe trzymane w SharedPreferences (protokoły prac pożarowo
/// niebezpiecznych, kontrole kołnierzy i spooli, partie elektrod, stawki
/// akordu i wycen, …) należą do konta, tak jak rejestry w bazie (schema34).
/// Każdy klucz idzie pod `<klucz>.owner.<konto>`; gość offline zostaje przy
/// starym kluczu, więc dane sprzed kont są jego — ten sam układ co
/// [InterpassStore.ownerKey] i tożsamość spawacza.
///
/// Właściciel jest uchwycony przy [OwnedPrefs.instance]. Zapis po zmianie
/// sesji (wylogowanie, inne konto) rzuca [AccountException] zamiast trafić do
/// rejestru innej osoby; odczyt zwraca dane uchwyconego właściciela.
///
/// Klasa implementuje [SharedPreferences], więc magazyny i ich pomocnicze
/// funkcje (`_backup(SharedPreferences prefs, …)`) zostają bez zmian — zmienia
/// się tylko miejsce, skąd biorą `prefs`.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_record_owner.dart';

class OwnedPrefs implements SharedPreferences {
  OwnedPrefs._(this._prefs, this.owner);

  final SharedPreferences _prefs;
  final LocalRecordOwner owner;

  /// Prefs bieżącego właściciela. [captureOwner] — np. sesja ekranu
  /// ([LocalRecordSession.captureOwner]); domyślnie bieżące konto.
  static Future<SharedPreferences> instance(
      [Future<LocalRecordOwner> Function()? captureOwner]) async {
    final owner = await (captureOwner ?? LocalRecordOwner.capture)();
    final prefs = await SharedPreferences.getInstance();
    owner.requireCurrent();
    return OwnedPrefs._(prefs, owner);
  }

  static String _suffix(LocalRecordOwner owner) =>
      '.owner.${Uri.encodeComponent(owner.key)}';

  /// Klucz [base] dla [owner] (gość — [base] bez zmian).
  static String keyFor(String base, LocalRecordOwner owner) =>
      owner.key == LocalRecordOwner.guest ? base : '$base${_suffix(owner)}';

  String _k(String key) => keyFor(key, owner);

  Future<bool> _write(Future<bool> Function() op) {
    owner.requireCurrent();
    return op();
  }

  @override
  Object? get(String key) => _prefs.get(_k(key));

  @override
  bool? getBool(String key) => _prefs.getBool(_k(key));

  @override
  int? getInt(String key) => _prefs.getInt(_k(key));

  @override
  double? getDouble(String key) => _prefs.getDouble(_k(key));

  @override
  String? getString(String key) => _prefs.getString(_k(key));

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(_k(key));

  @override
  bool containsKey(String key) => _prefs.containsKey(_k(key));

  /// Klucze TEGO właściciela, pod nazwami bazowymi. Gość widzi klucze bez
  /// przyrostka `.owner.` (także wszystkie ustawienia urządzenia — jak
  /// przed kontami), konto tylko swoje.
  @override
  Set<String> getKeys() {
    final all = _prefs.getKeys();
    if (owner.key == LocalRecordOwner.guest) {
      return {
        for (final k in all)
          if (!k.contains('.owner.')) k
      };
    }
    final suffix = _suffix(owner);
    return {
      for (final k in all)
        if (k.endsWith(suffix)) k.substring(0, k.length - suffix.length)
    };
  }

  @override
  Future<bool> setBool(String key, bool value) =>
      _write(() => _prefs.setBool(_k(key), value));

  @override
  Future<bool> setInt(String key, int value) =>
      _write(() => _prefs.setInt(_k(key), value));

  @override
  Future<bool> setDouble(String key, double value) =>
      _write(() => _prefs.setDouble(_k(key), value));

  @override
  Future<bool> setString(String key, String value) =>
      _write(() => _prefs.setString(_k(key), value));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(() => _prefs.setStringList(_k(key), value));

  @override
  Future<bool> remove(String key) => _write(() => _prefs.remove(_k(key)));

  /// Nie ma „wyczyść wszystko” dla jednego konta — to skasowałoby też
  /// ustawienia urządzenia i dane innych kont.
  @override
  Future<bool> clear() =>
      throw UnsupportedError('OwnedPrefs.clear: remove keys one by one');

  @override
  @Deprecated('No-op in shared_preferences; kept for the interface.')
  Future<bool> commit() async => true;

  @override
  Future<void> reload() => _prefs.reload();
}
