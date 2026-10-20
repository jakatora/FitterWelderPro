import 'steel_sections.dart';
import 'steel_weight.dart';

const steelDraftFields = {
  'shape',
  'section',
  'a_mm',
  'b_mm',
  't_mm',
  'length_mm',
  'quantity',
  'material'
};

/// Strict draft input: validates mass geometry, never accepts prices or an order.
SteelItem? steelDraftFromFields(Map<String, Object?> fields) {
  if (fields.keys.any((k) => !steelDraftFields.contains(k))) return null;
  final shape =
      SteelShape.values.where((s) => s.name == fields['shape']).firstOrNull;
  final material = SteelMaterial.values
      .where((m) => m.name == fields['material'])
      .firstOrNull;
  if (shape == null || material == null) return null;
  for (final key in const ['a_mm', 'b_mm', 't_mm', 'length_mm', 'quantity']) {
    if (!fields.containsKey(key)) continue;
    final v = fields[key];
    if (v is! num || !v.isFinite || v < 0) return null;
  }
  final length = fields['length_mm'], qty = fields['quantity'];
  if (length is! num ||
      qty is! num ||
      qty <= 0 ||
      qty != qty.roundToDouble() ||
      qty > 2147483647) {
    return null;
  }
  final section = fields['section'];
  if (section != null && section is! String) return null;
  final item = SteelItem(
      shape: shape,
      material: material,
      section: section as String?,
      a: (fields['a_mm'] as num?)?.toDouble() ?? 0,
      b: (fields['b_mm'] as num?)?.toDouble() ?? 0,
      t: (fields['t_mm'] as num?)?.toDouble() ?? 0,
      lengthMm: length.toDouble(),
      count: qty.toInt());
  if (!item.isValid ||
      !item.kgPerM.isFinite ||
      item.kgPerM <= 0 ||
      !item.totalKg.isFinite ||
      item.totalKg <= 0) {
    return null;
  }
  final paint = item.totalPaintM2;
  if (paint != null && !paint.isFinite) return null;
  return item;
}
