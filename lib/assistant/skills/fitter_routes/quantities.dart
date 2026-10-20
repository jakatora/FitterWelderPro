import '../../core/utterance.dart';
import '../../../utils/decimal_parse.dart';

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

/// Percent signs and spoken percent share one parser; conflicting values ask.
double? percentValue(Utterance u) {
  final values = <double>{};
  for (var i = 1; i < u.items.length; i++) {
    if ((u.items[i].word.startsWith('procent') ||
            u.items[i].word.startsWith('percent')) &&
        u.items[i - 1].isNumber) {
      values.add(signedQuantity(u, i - 1));
    }
  }
  for (final m in RegExp(r'(-?\d+(?:[.,]\d+)?)\s*%').allMatches(u.raw)) {
    final value = parseDecimal(m[1]!) ?? double.nan;
    final spokenMinus = RegExp(r'minus\s*$', caseSensitive: false)
        .hasMatch(u.raw.substring(0, m.start));
    values.add(spokenMinus ? -value.abs() : value);
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}

/// Explicit angle labels / degree units only, never an arbitrary nearby number.
double? angleValue(Utterance u) {
  final values = <double>{};
  for (var i = 0; i < u.items.length; i++) {
    if (!u.items[i].isNumber) continue;
    final before = i > 0 ? u.items[i - 1].word : '';
    final label = before == 'minus' && i > 1 ? u.items[i - 2].word : before;
    final after = i + 1 < u.items.length ? u.items[i + 1].word : '';
    if (const ['kat', 'angle', 'elbow', 'kolano'].contains(label) ||
        after.startsWith('stopn') ||
        after.startsWith('degree') ||
        after == 'deg') {
      values.add(
          lengthUnitScale(after) != null ? double.nan : signedQuantity(u, i));
    }
  }
  for (final m in RegExp(r'(-?\d+(?:[.,]\d+)?)\s*°').allMatches(u.raw)) {
    final v = parseDecimal(m[1]!) ?? double.nan;
    final minus = RegExp(r'minus\s*$', caseSensitive: false)
        .hasMatch(u.raw.substring(0, m.start));
    values.add(minus ? -v.abs() : v);
  }
  return values.length > 1 ? double.nan : values.singleOrNull;
}
