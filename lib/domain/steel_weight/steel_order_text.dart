/// Lista materiałowa jako zwykły tekst — do wysłania hurtowni / szefowi
/// (Share.share). Czysty Dart.
library;

import '../quotes/quote_calculator.dart' show formatPln;
import 'steel_sections.dart';
import 'steel_weight.dart';

String steelOrderText(SteelOrder order,
    {bool english = false, DateTime? date}) {
  String tr(String pl, String en) => english ? en : pl;
  String kg(double v) => fmtKg(v, english: english);
  String num(double v, int d) => fmtNum(v, decimals: d, english: english);
  String len(double m) => '${num(m, m == m.roundToDouble() ? 0 : 2)} m';
  String pcs(int n) => '$n ${tr('szt.', 'pcs')}';
  final pct = num(
      order.wastePct, order.wastePct == order.wastePct.roundToDouble() ? 0 : 1);

  final s = summarizeOrder(order, english: english);
  final b = StringBuffer()
    ..writeln(tr('Lista materiałowa — stal', 'Material list — steel'));
  if (date != null) {
    String two(int v) => v.toString().padLeft(2, '0');
    b.writeln('${date.year}-${two(date.month)}-${two(date.day)}');
  }
  b.writeln();

  final items = order.items.where((i) => i.isValid).toList();
  for (final (n, item) in items.indexed) {
    final name = item.label(english: english);
    if (item.shape == SteelShape.plate) {
      b.writeln('${n + 1}. $name — ${pcs(item.count)} = '
          '${num(item.plateAreaM2, 2)} m² · '
          '${num(item.kgPerM2, 1)} kg/m² · ${kg(item.totalKg)} kg');
    } else {
      b.writeln('${n + 1}. $name — ${item.count} × '
          '${fmtDim(item.lengthMm)} mm = ${len(item.totalLengthM)} · '
          '${num(item.kgPerM, 2)} kg/m · ${kg(item.totalKg)} kg');
    }
    final own = item.unitPrice;
    if (own != null) {
      final unit = item.priceUnit == PriceUnit.perM ? 'zł/m' : 'zł/kg';
      b.writeln('   ${tr('cena', 'price')}: ${num(own, 2)} $unit');
    }
  }
  if (items.isEmpty) b.writeln(tr('(lista pusta)', '(empty list)'));

  if (s.groups.isNotEmpty) {
    b
      ..writeln()
      ..writeln(tr('Razem wg profili:', 'Totals by section:'));
    for (final g in s.groups) {
      final amount = g.shape == SteelShape.plate
          ? '${pcs(g.pieces)} (${num(g.areaM2, 2)} m²)'
          : '${len(g.lengthM)} (${pcs(g.pieces)})';
      b.writeln('• ${g.label} — $amount — ${kg(g.kg)} kg');
    }
  }

  b
    ..writeln()
    ..writeln('${tr('Masa netto', 'Net mass')}: ${kg(s.netKg)} kg');
  if (s.wasteKg > 0) {
    b
      ..writeln('${tr('Zapas', 'Allowance')} $pct %: '
          '+${kg(s.wasteKg)} kg')
      ..writeln('${tr('Do zamówienia', 'To order')}: ${kg(s.orderKg)} kg');
  }
  if (s.paintM2 > 0) {
    b.writeln('${tr('Malowanie', 'Painting')}: ${num(s.paintM2, 1)} m²');
  }
  if (s.netGrosze != null) {
    final price = order.pricePerKg;
    final at = price == null ? '' : ' (${num(price, 2)} zł/kg)';
    b.writeln(
        '${tr('Koszt netto', 'Net cost')}$at: ${formatPln(s.netGrosze!)}');
    if (s.wasteKg > 0) {
      b.writeln('${tr('Z zapasem', 'With allowance')} $pct %: '
          '${formatPln(s.orderGrosze!)}');
    }
    if (s.unpricedItems > 0) {
      b.writeln(tr('(pozycje bez ceny: ${s.unpricedItems} — poza kosztem)',
          '(items without a price: ${s.unpricedItems} — not in the cost)'));
    }
  }
  b
    ..writeln()
    ..write(tr(
        'Masy nominalne: kształtowniki z tablic EN 10365 / EN 10056-1, '
            'profile zamknięte wzorem EN 10219-2, reszta z wymiarów '
            '(stal 7850 kg/m³). Rzeczywista masa mieści się w tolerancji '
            'normy wyrobu.',
        'Nominal masses: sections from EN 10365 / EN 10056-1 tables, '
            'hollow sections by the EN 10219-2 formula, the rest from '
            'dimensions (steel 7850 kg/m³). Actual mass lies within the '
            'product standard tolerance.'));
  return b.toString();
}

/// Compact spoken/chat summary, using exactly the native order calculations.
String steelOrderSummaryText(SteelOrder order, {bool english = false}) {
  String tr(String pl, String en) => english ? en : pl;
  final s = summarizeOrder(order, english: english);
  if (order.items.isEmpty) {
    return tr(
        'Zapisana lista stali jest pusta.', 'The saved steel list is empty.');
  }
  final pieces = order.items.fold<int>(0, (total, item) => total + item.count);
  final b = StringBuffer(tr('Zapisana lista stali', 'Saved steel list'))
    ..write(
        ': ${order.items.length} ${tr('poz.', 'rows')}, $pieces ${tr('szt.', 'pieces')}. ')
    ..write(
        '${tr('Masa netto', 'Net mass')}: ${fmtKg(s.netKg, english: english)} kg. ')
    ..write(
        '${tr('Zapas', 'Allowance')}: ${fmtNum(order.wastePct, decimals: 2, english: english)} %. ')
    ..write(
        '${tr('Do zamówienia', 'To order')}: ${fmtKg(s.orderKg, english: english)} kg.');
  if (s.netGrosze == null) {
    b.write(tr(' Brak cen — koszt nie jest określony.',
        ' No prices — cost is unspecified.'));
  } else {
    b.write(
        ' ${tr('Koszt netto wycenionych pozycji', 'Net cost of priced items')}: ${formatPln(s.netGrosze!)}. ');
    b.write(
        '${tr('Koszt z zapasem', 'Cost with allowance')}: ${formatPln(s.orderGrosze!)}.');
  }
  if (s.unpricedItems > 0) {
    b.write(
        ' ${tr('Pozycje bez ceny', 'Items without a price')}: ${s.unpricedItems} — ${tr('poza kosztem', 'excluded from cost')}.');
  }
  return b.toString();
}
