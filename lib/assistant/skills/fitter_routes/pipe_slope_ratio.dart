import '../../../domain/fitter/pipe_slope.dart';
import '../../core/skill.dart';
import 'quantities.dart';

/// Remove ratio tokens before reading lengths so a denominator cannot become
/// a pipe dimension. Percent units are parsed from the original utterance.
(double?, Utterance) pipeSlopeRatio(Utterance u) {
  if (!u.raw.contains(':') && !u.hasAny(const ['do', 'in'])) return (null, u);
  final values = <double>[];
  final pattern = RegExp(r'(-?\d+(?:[.,]\d+)?)\s*:\s*(-?\d+(?:[.,]\d+)?)');
  final text = u.raw.replaceAllMapped(pattern, (m) {
    final a = double.parse(m[1]!.replaceAll(',', '.')),
        b = double.parse(m[2]!.replaceAll(',', '.'));
    final before = u.raw.substring(0, m.start).toLowerCase();
    values.add(slopePercentFromRatio(
            RegExp(r'minus\s*$').hasMatch(before) ? -a.abs() : a, b) ??
        double.nan);
    final after = u.withRaw(u.raw.substring(m.end)).items;
    if (after.isNotEmpty &&
        (lengthUnitScale(after.first.word) != null || after.first.isNumber)) {
      values.add(double.nan);
    }
    return ' ';
  });
  if (text.contains(':') && values.isNotEmpty) values.add(double.nan);
  final cleaned = u.withRaw(text), items = cleaned.items;
  final removed = <int>{};
  for (var i = 0; i + 2 < items.length; i++) {
    if (!items[i].isNumber || !const {'do', 'in'}.contains(items[i + 1].word)) {
      continue;
    }
    final start = i > 0 && items[i - 1].word == 'minus' ? i - 1 : i;
    final label = start > 0 ? items[start - 1].word : '';
    if (start != 0 &&
        !const {
          'spadek',
          'slope',
          'nachylenie',
          'ratio',
          'proporcja',
          'stosunek'
        }.contains(label)) {
      continue;
    }
    final denominator =
        i + 2 < items.length && items[i + 2].word == 'minus' ? i + 3 : i + 2;
    if (denominator >= items.length || !items[denominator].isNumber) {
      values.add(double.nan);
      continue;
    }
    values.add(slopePercentFromRatio(
            signedQuantity(cleaned, i), signedQuantity(cleaned, denominator)) ??
        double.nan);
    if (denominator + 1 < items.length &&
        (lengthUnitScale(items[denominator + 1].word) != null ||
            items[denominator + 1].isNumber ||
            const {'do', 'in'}.contains(items[denominator + 1].word))) {
      values.add(double.nan);
    }
    removed.addAll([for (var n = start; n <= denominator; n++) n]);
    i = denominator;
  }
  if (values.isEmpty) return (u.raw.contains(':') ? double.nan : null, u);
  final valid = values.every((v) =>
      v.isFinite && (v - values.first).abs() <= 1e-12 * values.first.abs());
  final rest = removed.isEmpty
      ? cleaned
      : cleaned.withRaw([
          for (var i = 0; i < items.length; i++)
            if (!removed.contains(i))
              items[i].isNumber ? items[i].value.toString() : items[i].word,
        ].join(' '));
  return (valid ? values.first : double.nan, rest);
}
