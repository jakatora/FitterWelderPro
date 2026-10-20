import '../../core/utterance.dart';

double signedQuantity(Utterance u, int i) {
  final v = u.items[i].value!;
  return i > 0 && u.items[i - 1].word == 'minus' ? -v.abs() : v;
}

double? lengthUnitScale(String word) {
  if (word == 'mm' ||
      word.startsWith('milimetr') ||
      word.startsWith('millimet')) {
    return 1;
  }
  if (word == 'cm' ||
      word.startsWith('centymetr') ||
      word.startsWith('centimet')) {
    return 10;
  }
  if (word == 'm' || word.startsWith('metr') || word.startsWith('meter')) {
    return 1000;
  }
  return null;
}

double? lengthNear(Utterance u, List<String> labels) {
  final values = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (u.items[i].isNumber ||
        !labels.any((l) => u.items[i].word.startsWith(l))) {
      continue;
    }
    for (var j = i + 1; j < u.items.length && j <= i + 3; j++) {
      final n = u.items[j];
      if (!n.isNumber) {
        if (!const {
          'na',
          'is',
          'wynosi',
          'wysokosci',
          'of',
          'o',
          'to',
          'minus',
          'the',
          'rury',
          'pipe',
          'horizontal'
        }.contains(n.word)) {
          break;
        }
        continue;
      }
      final scale =
          j + 1 < u.items.length ? lengthUnitScale(u.items[j + 1].word) : null;
      if (scale != null) {
        values.add(signedQuantity(u, j) * scale);
      }
      break;
    }
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}
