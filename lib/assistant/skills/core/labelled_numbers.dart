import '../../core/utterance.dart';

const _fillers = {
  'to',
  'is',
  'jest',
  'wynosi',
  'rowna',
  'rowne',
  'equals',
  'of',
  'o',
  'na',
  'ma',
  'minus',
  'the',
};

/// Liczba tuż po etykiecie („a 4”, „długość wynosi 100 mm”), najwyżej
/// [window] słów dalej, z pominięciem słów-wypełniaczy. Gdy [unit] podano,
/// za liczbą musi stać pasująca jednostka. Dwie różne wartości → NaN
/// (dopytać), brak → null.
double? numberAfterLabel(Utterance u, bool Function(String word) isLabel,
    {bool Function(String word)? unit,
    int window = 3,
    Set<String> skip = const {}}) {
  final found = <double>{};
  final items = u.items;
  for (var i = 0; i < items.length; i++) {
    if (items[i].isNumber || !isLabel(items[i].word)) continue;
    for (var j = i + 1; j < items.length && j <= i + window; j++) {
      if (!items[j].isNumber) {
        if (_fillers.contains(items[j].word) || skip.contains(items[j].word)) {
          continue;
        }
        break;
      }
      if (unit != null &&
          (j + 1 >= items.length ||
              items[j + 1].isNumber ||
              !unit(items[j + 1].word))) {
        break;
      }
      final v = items[j].value!;
      found.add(j > 0 && items[j - 1].word == 'minus' ? -v.abs() : v);
      break;
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}

/// Liczba stojąca tuż przed jednostką („12 kN”, „3 spoiny”). Dwie różne
/// wartości → NaN, brak → null.
double? numberBeforeUnit(Utterance u, bool Function(String word) isUnit) {
  final found = <double>{};
  final items = u.items;
  for (var i = 0; i + 1 < items.length; i++) {
    if (items[i].isNumber && !items[i + 1].isNumber && isUnit(items[i + 1].word)) {
      final v = items[i].value!;
      found.add(i > 0 && items[i - 1].word == 'minus' ? -v.abs() : v);
    }
  }
  return found.length > 1 ? double.nan : found.singleOrNull;
}
