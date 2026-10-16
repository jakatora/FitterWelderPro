// Przelicznik grubości obliczeniowej a ↔ długości boku z spoiny pachwinowej.
//
// Czysta geometria, bez Fluttera. EN ISO 2553:2019: grubość obliczeniowa a
// to wysokość największego trójkąta równoramiennego wpisanego w przekrój
// spoiny (p. 3.16); z to długość boku spoiny (p. 3.17). Dla pachwiny
// równoramiennej w złączu pod kątem prostym:
//
//   a = z · cos 45° = z / √2 ≈ 0,707 · z        z = a · √2 ≈ 1,414 · a
//
// Ręcznie: a5 → z = 5 · 1,41421 = 7,071 mm;  z10 → a = 10 / 1,41421 = 7,071 mm.
//
// Rysunek z „a5” i rysunek z „z7” to NIE to samo — z7 daje a ≈ 4,95, czyli
// odrobinę mniej niż a5. Dla innego kąta między ściankami ta zależność nie
// obowiązuje; spoinę o nierównych bokach norma wymiaruje przez z1 i z2
// (bez a).

import 'dart:math' as math;

/// Grubość obliczeniowa a [mm] pachwiny równoramiennej o boku [legZ] [mm].
/// `null`, gdy wymiar nie jest dodatni i skończony.
double? throatFromLeg(double legZ) {
  if (!legZ.isFinite || legZ <= 0) return null;
  return legZ / math.sqrt2;
}

/// Długość boku z [mm] pachwiny równoramiennej o grubości obliczeniowej
/// [throatA] [mm]. `null`, gdy wymiar nie jest dodatni i skończony.
double? legFromThroat(double throatA) {
  if (!throatA.isFinite || throatA <= 0) return null;
  return throatA * math.sqrt2;
}

/// Wymiar w milimetrach do wyświetlenia: najwyżej jedno miejsce po
/// przecinku, bez zbędnego „,0”; przecinek po polsku, kropka po angielsku.
///
/// `5` → „5”, `7.0711` → „7,1” (PL) / „7.1” (EN), `4.9497` → „4,9”,
/// `3.96` → „4” (zaokrąglenie do 0,1 daje 4,0).
String formatWeldMm(double value, {required bool en}) {
  final rounded = (value * 10).roundToDouble() / 10;
  var s = rounded == rounded.truncateToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// Jak [formatWeldMm], ale z dwoma miejscami po przecinku — do przelicznika,
/// gdzie spawacz porównuje a z tabelą (np. 4,95 vs 5).
String formatWeldMmPrecise(double value, {required bool en}) {
  final s = value.toStringAsFixed(2);
  return en ? s : s.replaceAll('.', ',');
}
