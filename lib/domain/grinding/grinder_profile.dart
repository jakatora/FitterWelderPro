/// „Moje szlifierki” — zapisane dane z tabliczek (np. „Ø125 · 11 000”),
/// żeby nie przepisywać ich przy każdej tarczy. Model i JSON.
///
/// Odczyt jest ostrożny: wpis bez poprawnych obrotów albo średnicy jest
/// pomijany, nieznany gwint — zerowany, a wynik mówi, że coś stracono
/// ([GrindersDecoded.lossy]) — magazyn robi wtedy kopię surowego zapisu.
///
/// Czysty Dart.
library;

import 'dart:convert';

import 'grinding_check.dart';

/// Klucz SharedPreferences (wersja w nazwie — zmiana formatu = nowy klucz).
const String kGrindersPrefsKey = 'grinding_grinders_v1';

/// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
const String kGrindersCorruptPrefsKey = 'grinding_grinders_v1_corrupt';

/// Najwięcej zapisanych szlifierek (więcej to już nie „moje”).
const int kMaxGrinders = 20;

/// Najdłuższa nazwa szlifierki.
const int kMaxGrinderNameLength = 40;

class GrinderProfile {
  final String id;
  final String name;
  final int maxRpm;
  final double diameterMm;
  final SpindleThread? thread;

  const GrinderProfile({
    required this.id,
    required this.name,
    required this.maxRpm,
    required this.diameterMm,
    this.thread,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'rpm': maxRpm,
        'd': diameterMm,
        if (thread != null) 'thread': thread!.name,
      };

  /// Domyślna nazwa: „Ø125 · 11 000”.
  static String defaultName(double diameterMm, int rpm, {required bool en}) =>
      'Ø${fmtNum(diameterMm, en: en)} · ${fmtRpm(rpm, en: en)}';

  @override
  bool operator ==(Object other) =>
      other is GrinderProfile &&
      other.id == id &&
      other.name == name &&
      other.maxRpm == maxRpm &&
      other.diameterMm == diameterMm &&
      other.thread == thread;

  @override
  int get hashCode => Object.hash(id, name, maxRpm, diameterMm, thread);
}

String encodeGrinders(List<GrinderProfile> grinders) =>
    jsonEncode([for (final g in grinders) g.toJson()]);

/// Wynik odczytu: to, co dało się odczytać, i czy coś stracono / zmieniono.
class GrindersDecoded {
  final List<GrinderProfile> grinders;
  final bool lossy;
  const GrindersDecoded(this.grinders, {this.lossy = false});
}

/// Nigdy nie rzuca. Nieczytelny JSON → pusta lista + `lossy`.
GrindersDecoded decodeGrinders(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return const GrindersDecoded([], lossy: true);
  }
  if (json is! List) return const GrindersDecoded([], lossy: true);
  var lossy = false;
  final out = <GrinderProfile>[];
  final ids = <String>{};
  for (final e in json) {
    if (e is! Map) {
      lossy = true;
      continue;
    }
    final id = e['id'];
    final name = e['name'];
    final rpm = e['rpm'];
    final d = e['d'];
    final rpmInt = rpm is int
        ? rpm
        : (rpm is double && rpm == rpm.roundToDouble() ? rpm.toInt() : null);
    final dNum = d is num && d.isFinite ? d.toDouble() : null;
    if (id is! String ||
        id.isEmpty ||
        ids.contains(id) ||
        name is! String ||
        rpmInt == null ||
        rpmInt < kMinRpm ||
        rpmInt > kMaxRpm ||
        dNum == null ||
        dNum < kMinDiameterMm ||
        dNum > kMaxDiameterMm) {
      lossy = true;
      continue;
    }
    SpindleThread? thread;
    final t = e['thread'];
    if (t != null) {
      thread = SpindleThread.values.where((v) => v.name == t).firstOrNull;
      if (thread == null) lossy = true;
    }
    ids.add(id);
    out.add(GrinderProfile(
      id: id,
      name: name.trim().isEmpty
          ? GrinderProfile.defaultName(dNum, rpmInt, en: false)
          : name,
      maxRpm: rpmInt,
      diameterMm: dNum,
      thread: thread,
    ));
  }
  return GrindersDecoded(List.unmodifiable(out), lossy: lossy);
}
