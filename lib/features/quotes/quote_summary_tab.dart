// Zakładka „Wynik": cena, rozkład kosztów, zużycie materiałów i mediów,
// wskaźniki (zł/spoinę, zł/DI, zł/m) oraz wysyłka oferty.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/quotes/quote_calculator.dart';
import '../../domain/quotes/quote_labels.dart';
import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/quote_shopping.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../services/quote_export.dart';
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import 'quote_edit_page.dart' show QuoteChanged;
import 'quote_widgets.dart';

class QuoteSummaryTab extends StatelessWidget {
  final WeldQuote quote;
  final QuoteResult result;
  final QuoteSettings settings;
  final QuoteChanged onChanged;

  /// Zapis przed wysłaniem — oferta w PDF ma być tym, co jest w bazie.
  final Future<void> Function() beforeExport;

  const QuoteSummaryTab({
    super.key,
    required this.quote,
    required this.result,
    required this.settings,
    required this.onChanged,
    required this.beforeExport,
  });

  Future<void> _pdf(BuildContext context, {required bool internal}) async {
    final en = context.language == AppLanguage.en;
    await beforeExport();
    try {
      await QuoteExport.sharePdf(
          quote: quote, settings: settings, internal: internal, en: en);
      if (!internal && quote.status == QuoteStatus.draft) {
        onChanged(quote.copyWith(status: QuoteStatus.sent));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się przygotować PDF.',
              en: 'Could not prepare the PDF.'))));
    }
  }

  Future<void> _editPack(BuildContext context, QuoteProcess p) async {
    final c = TextEditingController(text: numText(quote.rates.packKgOf(p)));
    final v = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.tr(
            pl: 'Opakowanie — ${p.label}', en: 'Pack size — ${p.label}')),
        content: TextField(
          key: const ValueKey('pack-size'),
          controller: c,
          autofocus: true,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: const InputDecoration(
              suffixText: 'kg', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          FilledButton(
            onPressed: () {
              final x = parseDecimal(c.text);
              if (x != null && x > 0) Navigator.pop(d, x);
            },
            child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
          ),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    onChanged(quote.copyWith(
        rates: quote.rates.copyWith(packKg: {...quote.rates.packKg, p: v})));
  }

  Widget _shoppingSection(
      BuildContext context, List<ShoppingItem> items, bool en) {
    return QuoteSection(
      title: context.tr(pl: 'Lista zakupów', en: 'Shopping list'),
      subtitle: context.tr(
          pl: 'Pełne opakowania z zapasem. Dotknij spoiwa, żeby zmienić opakowanie.',
          en: 'Full packs with a reserve. Tap a filler to change the pack size.'),
      children: [
        for (final i in items)
          ListTile(
            key: ValueKey('shop-${i.kind.name}-${i.process?.code ?? ''}'),
            contentPadding: EdgeInsets.zero,
            onTap:
                i.process == null ? null : () => _editPack(context, i.process!),
            leading: Icon(
              i.kind == ShoppingKind.filler
                  ? Icons.inventory_2_outlined
                  : (i.kind == ShoppingKind.flux
                      ? Icons.grain
                      : Icons.propane_tank_outlined),
              color: kTextSec,
            ),
            title: Text(shoppingItemLabel(i, en: en)),
            subtitle: Text(
              '${context.tr(pl: 'potrzeba', en: 'needed')} '
              '${formatQty(i.needed)} ${i.inKg ? 'kg' : 'm³'}'
              ' · ${context.tr(pl: 'z zapasem', en: 'with reserve')} '
              '${formatQty(i.withReserve)} ${i.inKg ? 'kg' : 'm³'}',
              style: const TextStyle(fontSize: 12, color: kTextMut),
            ),
            trailing: Text(
              shoppingItemQty(i, en: en),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: kText, fontSize: 14),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(context.tr(pl: 'Zapas:', en: 'Reserve:'),
                style: const TextStyle(color: kTextSec)),
            for (final pct in const [0.0, 10.0, 20.0, 30.0])
              ChoiceChip(
                key: ValueKey('reserve-${pct.round()}'),
                label: Text('${pct.round()}%'),
                selected: quote.rates.stockReservePct == pct,
                onSelected: (_) => onChanged(quote.copyWith(
                    rates: quote.rates.copyWith(stockReservePct: pct))),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('share-shopping'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: () async {
            final text = buildShoppingText(quote: quote, items: items, en: en);
            if (kIsWeb) {
              await Clipboard.setData(ClipboardData(text: text));
              Haptic.copied();
              return;
            }
            try {
              await Share.share(text, subject: quote.number);
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: text));
            }
          },
          icon: const Icon(Icons.shopping_cart_outlined),
          label: Text(context.tr(
              pl: 'Wyślij listę zakupów', en: 'Send the shopping list')),
        ),
      ],
    );
  }

  Future<void> _text(BuildContext context) async {
    final en = context.language == AppLanguage.en;
    await beforeExport();
    final text = buildQuoteShareText(
        quote: quote, result: result, settings: settings, en: en);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      Haptic.copied();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Skopiowano tekst wyceny.', en: 'Quote text copied.'))));
      return;
    }
    try {
      await QuoteExport.shareText(quote: quote, settings: settings, en: en);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final r = result;
    final shopping = shoppingList(r, quote.rates);
    final parts = <(String, int, Color)>[
      (context.tr(pl: 'Robocizna', en: 'Labour'), r.labourGrosze, kArc),
      (
        context.tr(pl: 'Materiały i media', en: 'Materials and utilities'),
        r.materialsGrosze,
        const Color(0xFF4A9EFF)
      ),
      (
        context.tr(pl: 'NDT', en: 'NDT'),
        r.costOf(QuoteCostKind.ndt),
        const Color(0xFFAB47BC)
      ),
      (
        context.tr(pl: 'Dodatkowe', en: 'Additional'),
        r.costOf(QuoteCostKind.extras) + r.passThroughGrosze,
        const Color(0xFF78909C)
      ),
      (
        context.tr(pl: 'Koszty ogólne', en: 'Overhead'),
        r.overheadGrosze,
        const Color(0xFFE8C14B)
      ),
      (context.tr(pl: 'Zysk', en: 'Profit'), r.marginGrosze, kPass),
    ];
    final cyl = quote.rates.cylinderM3 > 0 ? quote.rates.cylinderM3 : 10.0;
    String cylinders(double m3) => m3 <= 0
        ? ''
        : ' · ${(m3 / cyl - 1e-9).ceil()} ${context.tr(pl: 'butl.', en: 'cyl.')}';

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        if (r.invalidJointCount > 0)
          QuoteNotice(
            color: kFail,
            icon: Icons.error_outline,
            text: context.tr(
                pl: '${r.invalidJointCount} poz. z błędem nie jest liczonych — popraw je w zakładce Spoiny.',
                en: '${r.invalidJointCount} item(s) with errors are not counted — fix them on the Welds tab.'),
          ),
        if (quote.joints.isEmpty && quote.extras.isEmpty)
          QuoteNotice(
            text: context.tr(
                pl: 'Wycena jest pusta — dodaj spoiny w zakładce Spoiny.',
                en: 'The quote is empty — add welds on the Welds tab.'),
          ),
        QuoteSection(
          title: context.tr(pl: 'Cena', en: 'Price'),
          children: [
            Readout(
              label: quote.rates.vat.rate > 0
                  ? context.tr(pl: 'Razem brutto', en: 'Total gross')
                  : context.tr(pl: 'Razem', en: 'Total'),
              value: formatPln(r.grossGrosze, withUnit: false),
              unit: 'zł · VAT ${quote.rates.vat.label}',
              hot: true,
            ),
            const SizedBox(height: 12),
            MoneyRow(
                label: context.tr(pl: 'Netto', en: 'Net'),
                grosze: r.netGrosze,
                strong: true),
            if (quote.rates.vat.rate > 0)
              MoneyRow(
                  label: 'VAT ${quote.rates.vat.label}', grosze: r.vatGrosze),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Z czego się składa', en: 'Breakdown'),
          children: [
            // Pasek proporcji netto.
            if (r.netGrosze > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      for (final p in parts)
                        if (p.$2 > 0)
                          Expanded(
                            flex: (p.$2 * 1000 ~/ r.netGrosze).clamp(1, 1000),
                            child: Container(color: p.$3),
                          ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (final p in parts)
              if (p.$2 != 0)
                Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: p.$3,
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MoneyRow(
                        label:
                            '${p.$1}  ${r.netGrosze > 0 ? '${(p.$2 * 100 / r.netGrosze).round()}%' : ''}',
                        grosze: p.$2,
                      ),
                    ),
                  ],
                ),
            const Divider(height: 20),
            for (final k in QuoteCostKind.values)
              if (r.costOf(k) != 0)
                MoneyRow(
                  label: costKindLabel(k, en: en),
                  grosze: r.costOf(k),
                  hint: switch (k) {
                    QuoteCostKind.weldLabour =>
                      '${formatQty(r.weldHours, decimals: 1)} h × ${formatQty(quote.rates.welderRate)} zł/h',
                    QuoteCostKind.prepLabour =>
                      '${formatQty(r.prepHours, decimals: 1)} h × ${formatQty(quote.rates.fitterRate)} zł/h',
                    QuoteCostKind.filler => r.byProcess.entries
                        .map((e) =>
                            '${e.key.code} ${formatQty(e.value.fillerKg, decimals: 2)} kg')
                        .join(' · '),
                    QuoteCostKind.ndt => r.ndtJoints.entries
                        .map((e) => '${e.key.code} ${e.value}')
                        .join(' · '),
                    QuoteCostKind.energy =>
                      '${formatQty(r.energyKWh, decimals: 1)} kWh',
                    _ => null,
                  },
                ),
            if (r.passThroughGrosze != 0)
              MoneyRow(
                  label: context.tr(
                      pl: 'Pozycje bez narzutu', en: 'Pass-through items'),
                  grosze: r.passThroughGrosze),
            MoneyRow(
                label:
                    '${context.tr(pl: 'Koszty ogólne', en: 'Overhead')} ${formatQty(quote.rates.overheadPct)}%',
                grosze: r.overheadGrosze),
            MoneyRow(
                label:
                    '${context.tr(pl: 'Zysk', en: 'Profit')} ${formatQty(quote.rates.marginPct)}%',
                grosze: r.marginGrosze),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Czas i zużycie', en: 'Time and consumption'),
          children: [
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.55,
              children: [
                FactTile(
                  icon: Icons.schedule,
                  label: context.tr(pl: 'Roboczogodziny', en: 'Man-hours'),
                  value: '${formatQty(r.labourHours, decimals: 1)} h',
                  sub: context.tr(
                      pl: 'spaw. ${formatQty(r.weldHours, decimals: 1)} · przyg. ${formatQty(r.prepHours, decimals: 1)}',
                      en: 'weld ${formatQty(r.weldHours, decimals: 1)} · prep ${formatQty(r.prepHours, decimals: 1)}'),
                ),
                FactTile(
                  icon: Icons.calendar_today_outlined,
                  label: context.tr(pl: 'Dni robocze', en: 'Working days'),
                  value: formatQty(r.workingDays, decimals: 1),
                  sub: context.tr(
                      pl: '${quote.crew} os. × 8 h',
                      en: 'crew ${quote.crew} × 8 h'),
                ),
                FactTile(
                  icon: Icons.scale_outlined,
                  label: context.tr(pl: 'Stopiwo', en: 'Weld metal'),
                  value: '${formatQty(r.depositedKg, decimals: 2)} kg',
                  sub: context.tr(
                      pl: 'spoiwo ${formatQty(r.fillerKg, decimals: 2)} kg',
                      en: 'filler ${formatQty(r.fillerKg, decimals: 2)} kg'),
                ),
                FactTile(
                  icon: Icons.bolt_outlined,
                  label: context.tr(pl: 'Czas łuku', en: 'Arc time'),
                  value: formatHours(r.arcHours),
                  sub: '${formatQty(r.energyKWh, decimals: 1)} kWh',
                ),
                if (r.shieldGasM3(QuoteGasKind.argon) > 0)
                  FactTile(
                    icon: Icons.propane_tank_outlined,
                    label: context.tr(pl: 'Argon', en: 'Argon'),
                    value:
                        '${formatQty(r.shieldGasM3(QuoteGasKind.argon), decimals: 2)} m³',
                    sub: cylinders(r.shieldGasM3(QuoteGasKind.argon))
                        .replaceFirst(' · ', ''),
                  ),
                if (r.shieldGasM3(QuoteGasKind.mix) > 0)
                  FactTile(
                    icon: Icons.propane_tank_outlined,
                    label: context.tr(pl: 'Mieszanka', en: 'Gas mix'),
                    value:
                        '${formatQty(r.shieldGasM3(QuoteGasKind.mix), decimals: 2)} m³',
                    sub: cylinders(r.shieldGasM3(QuoteGasKind.mix))
                        .replaceFirst(' · ', ''),
                  ),
                if (r.purgeL > 0)
                  FactTile(
                    icon: Icons.air,
                    label: context.tr(pl: 'Gaz formujący', en: 'Purge gas'),
                    value: '${formatQty(r.purgeM3, decimals: 2)} m³',
                    sub: cylinders(r.purgeM3).replaceFirst(' · ', ''),
                  ),
                if (r.fluxKg > 0)
                  FactTile(
                    icon: Icons.grain,
                    label: context.tr(pl: 'Topnik', en: 'Flux'),
                    value: '${formatQty(r.fluxKg, decimals: 1)} kg',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            for (final e in r.byProcess.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${e.key.label}: ${context.tr(pl: 'spoiwo', en: 'filler')} ${formatQty(e.value.fillerKg, decimals: 2)} kg · '
                  '${context.tr(pl: 'łuk', en: 'arc')} ${formatHours(e.value.arcHours)}'
                  '${e.value.shieldGasL > 0 ? ' · ${context.tr(pl: 'gaz', en: 'gas')} ${formatQty(e.value.shieldGasL / 1000, decimals: 2)} m³' : ''}',
                  style: const TextStyle(fontSize: 12, color: kTextSec),
                ),
              ),
          ],
        ),
        if (shopping.isNotEmpty) _shoppingSection(context, shopping, en),
        QuoteSection(
          title: context.tr(pl: 'Wskaźniki', en: 'Indicators'),
          subtitle: context.tr(
              pl: 'Netto. Porównaj ze stawkami, które znasz z rynku.',
              en: 'Net. Compare with the rates you know from the market.'),
          children: [
            if (r.weldCount > 0)
              MoneyRow(
                  label: context.tr(
                      pl: 'Na spoinę (${r.weldCount} szt.)',
                      en: 'Per weld (${r.weldCount})'),
                  grosze: r.netPerWeldGrosze),
            if (r.diameterInches > 0)
              MoneyRow(
                label: context.tr(
                    pl: 'Na cal-średnicę (${r.diApprox ? '≈ ' : ''}${formatQty(r.diameterInches, decimals: 1)} DI)',
                    en: 'Per dia-inch (${r.diApprox ? '≈ ' : ''}${formatQty(r.diameterInches, decimals: 1)} DI)'),
                grosze: r.netPerDiGrosze,
                hint: r.diApprox
                    ? context.tr(
                        pl: 'część średnic spoza tabeli NPS — DI ≈ OD / 25,4',
                        en: 'some diameters outside the NPS table — DI ≈ OD / 25.4')
                    : null,
              ),
            if (r.weldLengthM > 0)
              MoneyRow(
                  label: context.tr(
                      pl: 'Na metr spoiny (${formatQty(r.weldLengthM, decimals: 1)} m)',
                      en: 'Per metre of weld (${formatQty(r.weldLengthM, decimals: 1)} m)'),
                  grosze: r.netPerMetreGrosze),
            if (r.marketNetGrosze > 0) ...[
              const Divider(height: 18),
              MoneyRow(
                label: context.tr(
                    pl: 'Wg stawki rynkowej ${formatQty(quote.rates.marketDiRate)} zł/DI',
                    en: 'At market rate ${formatQty(quote.rates.marketDiRate)} zł/DI'),
                grosze: r.marketNetGrosze,
              ),
              Text(
                _marketVerdict(context, r),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: r.netGrosze > r.marketNetGrosze ? kWarn : kPass,
                ),
              ),
            ],
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Wyślij', en: 'Send'),
          children: [
            FilledButton.icon(
              key: const ValueKey('pdf-client'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: () => unawaited(_pdf(context, internal: false)),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                  context.tr(
                      pl: 'Oferta PDF dla klienta', en: 'Client quote PDF'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('pdf-internal'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinTapTarget)),
              onPressed: () => unawaited(_pdf(context, internal: true)),
              icon: const Icon(Icons.request_quote_outlined),
              label: Text(context.tr(
                  pl: 'Kosztorys wewnętrzny PDF',
                  en: 'Internal cost estimate PDF')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('share-text'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinTapTarget)),
              onPressed: () => unawaited(_text(context)),
              icon: const Icon(Icons.sms_outlined),
              label: Text(context.tr(
                  pl: 'Wyślij tekstem (SMS, WhatsApp)',
                  en: 'Send as text (SMS, WhatsApp)')),
            ),
            if (settings.company.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                context.tr(
                    pl: 'Uzupełnij dane firmy w „Moje stawki i firma" (lista wycen → ikona ustawień) — trafią do nagłówka oferty.',
                    en: 'Fill in your company in "My rates and company" (quote list → settings icon) — they go into the quote header.'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
            ],
          ],
        ),
        Text(
          context.tr(
              pl: 'Wycena szacunkowa: stopiwo z geometrii rowka, czasy z typowych '
                  'wydajności procesów i reguł kosztorysowych. Po kilku zleceniach '
                  'porównaj z rzeczywistością i popraw „Założenia procesów".',
              en: 'Estimate: weld metal from the groove geometry, times from typical '
                  'process rates and estimating rules. After a few jobs compare with '
                  'reality and adjust the "Process assumptions".'),
          style: const TextStyle(fontSize: 11.5, color: kTextMut, height: 1.4),
        ),
      ],
    );
  }

  String _marketVerdict(BuildContext context, QuoteResult r) {
    final diff = r.netGrosze - r.marketNetGrosze;
    final pct =
        r.marketNetGrosze == 0 ? 0 : (diff * 100 / r.marketNetGrosze).round();
    if (diff > 0) {
      return context.tr(
          pl: 'Twoja wycena jest o ${formatPln(diff)} ($pct%) wyższa niż rynek.',
          en: 'Your quote is ${formatPln(diff)} ($pct%) above the market.');
    }
    return context.tr(
        pl: 'Twoja wycena jest o ${formatPln(-diff)} (${-pct}%) niższa niż rynek — '
            'sprawdź, czy nie zostawiasz pieniędzy na stole.',
        en: 'Your quote is ${formatPln(-diff)} (${-pct}%) below the market — '
            'check you are not leaving money on the table.');
  }
}
