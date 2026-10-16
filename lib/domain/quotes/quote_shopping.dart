/// Lista zakupów do wyceny: ile opakowań spoiwa i ile butli gazu kupić
/// na zlecenie — wyliczone zużycie + zapas, zaokrąglone W GÓRĘ do pełnych
/// opakowań (pół paczki elektrod się nie kupi).
///
/// Czysty Dart.
library;

import 'quote_calculator.dart';
import 'quote_process.dart';
import 'weld_quote.dart';

enum ShoppingKind { filler, argon, mix, purge, flux }

class ShoppingItem {
  final ShoppingKind kind;

  /// Proces (tylko dla spoiwa).
  final QuoteProcess? process;

  /// Wyliczone zużycie (kg albo m³).
  final double needed;

  /// Zużycie z zapasem.
  final double withReserve;

  /// Wielkość opakowania (kg albo m³ w butli).
  final double packSize;

  /// Liczba opakowań / butli do kupienia.
  final int packs;

  const ShoppingItem({
    required this.kind,
    this.process,
    required this.needed,
    required this.withReserve,
    required this.packSize,
    required this.packs,
  });

  bool get inKg => kind == ShoppingKind.filler || kind == ShoppingKind.flux;
}

/// Worek topnika SAW, kg.
const double kFluxBagKg = 25;

int _packsFor(double amount, double pack) =>
    amount <= 0 || pack <= 0 ? 0 : (amount / pack - 1e-9).ceil();

List<ShoppingItem> shoppingList(QuoteResult r, QuoteRates rates) {
  final k = 1 + (rates.stockReservePct.clamp(0, 500)) / 100;
  final cyl = rates.cylinderM3 > 0 ? rates.cylinderM3 : 10.0;
  final out = <ShoppingItem>[];
  for (final p in QuoteProcess.values) {
    final u = r.byProcess[p];
    if (u == null || u.fillerKg <= 0) continue;
    final pack = rates.packKgOf(p);
    final need = u.fillerKg * k;
    out.add(ShoppingItem(
      kind: ShoppingKind.filler,
      process: p,
      needed: u.fillerKg,
      withReserve: need,
      packSize: pack,
      packs: _packsFor(need, pack),
    ));
  }
  void gas(ShoppingKind kind, double m3) {
    if (m3 <= 0) return;
    out.add(ShoppingItem(
      kind: kind,
      needed: m3,
      withReserve: m3 * k,
      packSize: cyl,
      packs: _packsFor(m3 * k, cyl),
    ));
  }

  gas(ShoppingKind.argon, r.shieldGasM3(QuoteGasKind.argon));
  gas(ShoppingKind.mix, r.shieldGasM3(QuoteGasKind.mix));
  gas(ShoppingKind.purge, r.purgeM3);
  if (r.fluxKg > 0) {
    out.add(ShoppingItem(
      kind: ShoppingKind.flux,
      needed: r.fluxKg,
      withReserve: r.fluxKg * k,
      packSize: kFluxBagKg,
      packs: _packsFor(r.fluxKg * k, kFluxBagKg),
    ));
  }
  return out;
}

String shoppingItemLabel(ShoppingItem i, {required bool en}) =>
    switch (i.kind) {
      ShoppingKind.filler =>
        en ? 'Filler ${i.process!.label}' : 'Spoiwo ${i.process!.label}',
      ShoppingKind.argon => en ? 'Argon (shielding)' : 'Argon (osłona)',
      ShoppingKind.mix => en ? 'Gas mix M21 / CO₂' : 'Mieszanka M21 / CO₂',
      ShoppingKind.purge => en ? 'Purge gas' : 'Gaz formujący',
      ShoppingKind.flux => en ? 'SAW flux' : 'Topnik SAW',
    };

/// „2 × 5 kg (z zapasem 7,2 kg)" / „1 butla × 10 m³".
String shoppingItemQty(ShoppingItem i, {required bool en}) {
  final unit = i.inKg ? 'kg' : 'm³';
  final pack = i.kind == ShoppingKind.filler || i.kind == ShoppingKind.flux
      ? '${formatQty(i.packSize)} $unit'
      : (en
          ? 'cyl. ${formatQty(i.packSize)} m³'
          : 'butla ${formatQty(i.packSize)} m³');
  return '${i.packs} × $pack';
}

/// Tekst do wysłania hurtowni / szefowi.
String buildShoppingText({
  required WeldQuote quote,
  required List<ShoppingItem> items,
  required bool en,
}) {
  final b = StringBuffer();
  final head = [
    en ? 'Shopping list' : 'Lista zakupów',
    if (quote.number.trim().isNotEmpty) quote.number.trim(),
    if (quote.title.trim().isNotEmpty) quote.title.trim(),
  ].join(' — ');
  b.writeln(head);
  b.writeln(en
      ? 'Material: ${quote.material.labelEn}'
      : 'Materiał: ${quote.material.labelPl}');
  for (final i in items) {
    final unit = i.inKg ? 'kg' : 'm³';
    b.writeln('• ${shoppingItemLabel(i, en: en)}: ${shoppingItemQty(i, en: en)}'
        ' (${en ? 'need' : 'potrzeba'} ${formatQty(i.needed)} $unit'
        ' + ${formatQty(quote.rates.stockReservePct)}%)');
  }
  return b.toString().trimRight();
}
