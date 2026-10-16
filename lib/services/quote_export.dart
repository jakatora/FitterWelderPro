/// Eksport wyceny: PDF oferty (dla klienta albo wewnętrzny kosztorys) i
/// krótki tekst do wysłania SMS-em / komunikatorem.
///
/// • Wersja DLA KLIENTA pokazuje zakres (pozycje i ilości), cenę netto,
///   VAT i brutto, termin realizacji i warunki — bez narzutu, zysku,
///   stawek godzinowych i założeń produkcyjnych.
/// • Wersja WEWNĘTRZNA to pełny kosztorys: każdy składnik kosztu, narzut,
///   zysk, godziny, kilogramy, butle, cale-średnice i założenia procesów.
///
/// Górna połowa czysta (budowa dokumentu z podanych czcionek — test renderuje
/// prawdziwe strony), dolna — platforma (zapis do pliku, udostępnienie).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/quotes/quote_calculator.dart';
import '../domain/quotes/quote_labels.dart';
import '../domain/quotes/quote_process.dart';
import '../domain/quotes/weld_quote.dart';
import 'quote_settings.dart';

final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');

String _date(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Nazwa pliku: „Oferta_WYC-2026-007.pdf" / „Kosztorys_WYC-2026-007.pdf".
String quoteFileName(WeldQuote q, {required bool internal, required bool en}) {
  final kind = internal
      ? (en ? 'Cost_estimate' : 'Kosztorys')
      : (en ? 'Quotation' : 'Oferta');
  final no = q.number.trim().isEmpty
      ? _date(DateTime.fromMillisecondsSinceEpoch(q.createdAt))
      : q.number.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  return '${kind}_$no.pdf';
}

/// Tekst do wysłania (SMS, WhatsApp, e-mail).
String buildQuoteShareText({
  required WeldQuote quote,
  required QuoteResult result,
  required QuoteSettings settings,
  required bool en,
}) {
  final b = StringBuffer();
  final no = quote.number.trim();
  b.writeln(en
      ? 'Quotation${no.isEmpty ? '' : ' $no'}'
      : 'Wycena${no.isEmpty ? '' : ' $no'}');
  if (quote.title.trim().isNotEmpty) b.writeln(quote.title.trim());
  if (quote.client.trim().isNotEmpty) {
    b.writeln('${en ? 'For' : 'Dla'}: ${quote.client.trim()}');
  }
  b.writeln();
  for (final j in result.joints.where((j) => j.isValid)) {
    b.writeln('• ${j.joint.count} × ${jointTitle(j.joint, en: en)}');
  }
  for (final e in quote.extras) {
    if (e.description.trim().isEmpty) continue;
    b.writeln('• ${e.description.trim()} — ${formatQty(e.quantity)} ${e.unit}');
  }
  b.writeln();
  b.writeln('${en ? 'Net' : 'Netto'}: ${formatPln(result.netGrosze)}');
  if (quote.rates.vat.rate > 0) {
    b.writeln('VAT ${quote.rates.vat.label}: ${formatPln(result.vatGrosze)}');
    b.writeln('${en ? 'Gross' : 'Brutto'}: ${formatPln(result.grossGrosze)}');
  } else {
    b.writeln('VAT: ${quote.rates.vat.label}');
  }
  if (result.workingDays > 0) {
    b.writeln(en
        ? 'Lead time: ~${formatQty(result.workingDays, decimals: 1)} working days'
        : 'Czas realizacji: ~${formatQty(result.workingDays, decimals: 1)} dni roboczych');
  }
  b.writeln(en
      ? 'Valid for ${quote.validityDays} days.'
      : 'Oferta ważna ${quote.validityDays} dni.');
  final c = settings.company;
  final sign = [c.person, c.name, c.phone].where((s) => s.trim().isNotEmpty);
  if (sign.isNotEmpty) {
    b.writeln();
    b.writeln(sign.join(', '));
  }
  return b.toString().trimRight();
}

class QuoteExport {
  const QuoteExport._();

  static Future<void> sharePdf({
    required WeldQuote quote,
    required QuoteSettings settings,
    required bool internal,
    required bool en,
  }) async {
    final now = DateTime.now();
    final doc = buildPdfDocument(
      quote: quote,
      result: computeQuote(quote),
      settings: settings,
      internal: internal,
      en: en,
      font:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      boldFont:
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      generatedAt: now,
    );
    final bytes = await doc.save();
    final name = quoteFileName(quote, internal: internal, en: en);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: name.replaceAll('.pdf', '').replaceAll('_', ' '),
    );
  }

  static Future<void> shareText({
    required WeldQuote quote,
    required QuoteSettings settings,
    required bool en,
  }) =>
      Share.share(
        buildQuoteShareText(
            quote: quote,
            result: computeQuote(quote),
            settings: settings,
            en: en),
        subject: quote.number,
      );

  static pw.Document buildPdfDocument({
    required WeldQuote quote,
    required QuoteResult result,
    required QuoteSettings settings,
    required bool internal,
    required bool en,
    required pw.Font font,
    pw.Font? boldFont,
    required DateTime generatedAt,
  }) {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
          base: font, bold: bold, italic: font, boldItalic: bold),
    );
    String t(String pl, String eng) => en ? eng : pl;
    final c = settings.company;
    final created = DateTime.fromMillisecondsSinceEpoch(quote.createdAt > 0
        ? quote.createdAt
        : generatedAt.millisecondsSinceEpoch);
    final validUntil = created.add(Duration(days: quote.validityDays));
    final valid = result.joints.where((j) => j.isValid).toList();

    pw.TextStyle st(double size, {bool b = false, PdfColor? color}) =>
        pw.TextStyle(
            fontSize: size,
            fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? _kInk);

    pw.Widget cell(String s,
            {bool b = false, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(s, style: st(8, b: b), textAlign: align),
        );

    pw.Widget moneyRow(String label, int grosze,
            {bool strong = false, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(
                child: pw.Text(label,
                    style: st(strong ? 10 : 8.5, b: strong, color: color))),
            pw.Text(formatPln(grosze),
                style: st(strong ? 10.5 : 8.5, b: strong, color: color)),
          ]),
        );

    final header = pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (c.name.trim().isNotEmpty)
                  pw.Text(c.name.trim(), style: st(12, b: true)),
                for (final line in [
                  c.address,
                  if (c.taxId.trim().isNotEmpty)
                    '${t('NIP', 'VAT ID')}: ${c.taxId.trim()}',
                  [c.phone, c.email]
                      .where((s) => s.trim().isNotEmpty)
                      .join('  ·  '),
                ])
                  if (line.trim().isNotEmpty)
                    pw.Text(line.trim(), style: st(8, color: _kInkMuted)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                  internal
                      ? t('KOSZTORYS WEWNĘTRZNY', 'INTERNAL COST ESTIMATE')
                      : t('OFERTA', 'QUOTATION'),
                  style: st(14, b: true)),
              if (quote.number.trim().isNotEmpty)
                pw.Text(quote.number.trim(), style: st(10, b: true)),
              pw.Text('${t('Data', 'Date')}: ${_date(created)}',
                  style: st(8, color: _kInkMuted)),
              if (!internal)
                pw.Text('${t('Ważna do', 'Valid until')}: ${_date(validUntil)}',
                    style: st(8, color: _kInkMuted)),
            ],
          ),
        ],
      ),
    );

    final scope = pw.Table(
      border: pw.TableBorder.all(color: _kRule, width: 0.5),
      columnWidths: internal
          ? const {
              0: pw.FixedColumnWidth(20),
              1: pw.FlexColumnWidth(5),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.1),
              4: pw.FixedColumnWidth(30),
              5: pw.FlexColumnWidth(1.1),
              6: pw.FlexColumnWidth(1.2),
            }
          : const {
              0: pw.FixedColumnWidth(20),
              1: pw.FlexColumnWidth(6),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FixedColumnWidth(36),
            },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _kHeadFill),
          children: [
            cell(t('Lp.', 'No.'), b: true),
            cell(t('Zakres', 'Scope'), b: true),
            cell(t('Proces', 'Process'), b: true),
            cell(t('Pozycja', 'Position'), b: true),
            cell(t('Ilość', 'Qty'), b: true, align: pw.TextAlign.right),
            if (internal) ...[
              cell(t('Stopiwo kg', 'Deposit kg'),
                  b: true, align: pw.TextAlign.right),
              cell(t('Roboczogodz.', 'Man-hours'),
                  b: true, align: pw.TextAlign.right),
            ],
          ],
        ),
        for (final (i, r) in valid.indexed)
          pw.TableRow(children: [
            cell('${i + 1}'),
            cell(jointTitle(r.joint, en: en)),
            cell(r.scheme.label),
            cell(r.joint.position.code),
            cell('${r.joint.count}', align: pw.TextAlign.right),
            if (internal) ...[
              cell(formatQty(r.depositedKg, decimals: 2),
                  align: pw.TextAlign.right),
              cell(formatQty(r.weldHours + r.prepHours, decimals: 1),
                  align: pw.TextAlign.right),
            ],
          ]),
        for (final (i, e) in quote.extras
            .where((e) => e.description.trim().isNotEmpty)
            .indexed)
          pw.TableRow(children: [
            cell('${valid.length + i + 1}'),
            cell(e.description.trim()),
            cell(''),
            cell(''),
            cell('${formatQty(e.quantity)} ${e.unit}',
                align: pw.TextAlign.right),
            if (internal) ...[cell(''), cell('')],
          ]),
      ],
    );

    final priceBox = pw.Container(
      width: 250,
      padding: const pw.EdgeInsets.all(8),
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: _kRule, width: 0.7)),
      child: pw.Column(children: [
        if (internal) ...[
          for (final k in QuoteCostKind.values)
            if (result.costOf(k) != 0)
              moneyRow(costKindLabel(k, en: en), result.costOf(k)),
          pw.Divider(color: _kRule, height: 6),
          moneyRow(
              t('Koszty bezpośrednie', 'Direct costs'), result.directGrosze),
          moneyRow(
              '${t('Koszty ogólne', 'Overhead')} ${formatQty(quote.rates.overheadPct)}%',
              result.overheadGrosze),
          moneyRow(
              '${t('Zysk', 'Profit')} ${formatQty(quote.rates.marginPct)}%',
              result.marginGrosze),
          if (result.passThroughGrosze != 0)
            moneyRow(t('Pozycje bez narzutu', 'Pass-through items'),
                result.passThroughGrosze),
          pw.Divider(color: _kRule, height: 6),
        ],
        moneyRow(t('Razem netto', 'Total net'), result.netGrosze, strong: true),
        if (quote.rates.vat.rate > 0) ...[
          moneyRow('VAT ${quote.rates.vat.label}', result.vatGrosze),
          moneyRow(t('Razem brutto', 'Total gross'), result.grossGrosze,
              strong: true, color: _kInk),
        ] else
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text('VAT', style: st(8.5))),
              pw.Text(quote.rates.vat.label, style: st(8.5)),
            ]),
          ),
      ]),
    );

    final facts = <(String, String)>[
      if (result.workingDays > 0)
        (
          t('Szacowany czas realizacji', 'Estimated lead time'),
          t('${formatQty(result.workingDays, decimals: 1)} dni roboczych (${quote.crew} os.)',
              '${formatQty(result.workingDays, decimals: 1)} working days (crew of ${quote.crew})')
        ),
      if (!internal && result.weldCount > 0)
        (t('Liczba spoin', 'Number of welds'), '${result.weldCount}'),
      if (internal) ...[
        (
          t('Roboczogodziny', 'Man-hours'),
          '${formatQty(result.labourHours, decimals: 1)} h  (${t('spawanie', 'welding')} ${formatQty(result.weldHours, decimals: 1)} h, ${t('przygotowanie', 'prep')} ${formatQty(result.prepHours, decimals: 1)} h)'
        ),
        (
          t('Czas łuku', 'Arc time'),
          '${formatQty(result.arcHours, decimals: 2)} h'
        ),
        (
          t('Stopiwo / spoiwo', 'Deposit / filler'),
          '${formatQty(result.depositedKg, decimals: 2)} kg / ${formatQty(result.fillerKg, decimals: 2)} kg'
        ),
        for (final e in result.byProcess.entries)
          (
            '  ${e.key.label}',
            '${t('spoiwo', 'filler')} ${formatQty(e.value.fillerKg, decimals: 2)} kg · ${t('łuk', 'arc')} ${formatQty(e.value.arcHours, decimals: 2)} h'
                '${e.value.shieldGasL > 0 ? ' · ${t('gaz', 'gas')} ${formatQty(e.value.shieldGasL / 1000, decimals: 2)} m³' : ''}'
          ),
        if (result.purgeL > 0)
          (
            t('Gaz formujący', 'Purge gas'),
            '${formatQty(result.purgeM3, decimals: 2)} m³'
          ),
        (
          t('Energia', 'Energy'),
          '${formatQty(result.energyKWh, decimals: 1)} kWh'
        ),
        if (result.diameterInches > 0) ...[
          (
            t('Cale-średnice', 'Diameter-inches'),
            '${result.diApprox ? '≈ ' : ''}${formatQty(result.diameterInches, decimals: 1)} DI'
          ),
          (
            t('Netto na cal-średnicę', 'Net per dia-inch'),
            formatPln(result.netPerDiGrosze)
          ),
        ],
        if (result.weldCount > 0)
          (
            t('Netto na spoinę', 'Net per weld'),
            formatPln(result.netPerWeldGrosze)
          ),
        if (result.marketNetGrosze > 0)
          (
            t('Wg stawki rynkowej DI', 'At market DI rate'),
            '${formatPln(result.marketNetGrosze)} (${formatQty(quote.rates.marketDiRate)} zł/DI)'
          ),
      ],
    ];

    final assumptions = internal
        ? pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 10),
              pw.Text(t('Założenia', 'Assumptions'), style: st(9, b: true)),
              pw.SizedBox(height: 3),
              pw.Text(
                '${t('Materiał', 'Material')}: ${en ? quote.material.labelEn : quote.material.labelPl}'
                ' · ${t('warunki', 'conditions')}: ${en ? quote.site.labelEn : quote.site.labelPl} (×${formatQty(quote.site.factor)})'
                ' · ${t('formowanie grani', 'root purge')}: ${quote.purge ? t('tak', 'yes') : t('nie', 'no')}'
                ' · ${t('stawki', 'rates')}: ${t('spawacz', 'welder')} ${formatQty(quote.rates.welderRate)} zł/h, ${t('monter', 'fitter')} ${formatQty(quote.rates.fitterRate)} zł/h',
                style: st(7.5, color: _kInkMuted),
              ),
              for (final p in {
                for (final r in valid) ...r.scheme.processes,
              })
                pw.Text(
                  '${p.label}: ${formatQty(quote.rates.profileOf(p).depositionKgH)} kg/h, '
                  '${t('uzysk', 'efficiency')} ${formatQty(quote.rates.profileOf(p).efficiency * 100, decimals: 0)}%, '
                  '${t('jarzenie łuku', 'arc duty')} ${formatQty(quote.rates.profileOf(p).dutyCycle * 100, decimals: 0)}%, '
                  '${t('spoiwo', 'filler')} ${formatQty(quote.rates.fillerPriceOf(p))} zł/kg',
                  style: st(7.5, color: _kInkMuted),
                ),
            ],
          )
        : pw.SizedBox();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      maxPages: 100,
      header: (ctx) => ctx.pageNumber == 1
          ? header
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                  '${quote.number}  ·  ${t('Strona', 'Page')} ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: st(7.5, color: _kInkMuted))),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              internal
                  ? t('Dokument wewnętrzny — nie przekazywać klientowi.',
                      'Internal document — do not send to the client.')
                  : t('Wycena przygotowana w Fitter Welder Pro.',
                      'Prepared with Fitter Welder Pro.'),
              style: st(7, color: _kInkMuted),
            ),
            pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
                style: st(7, color: _kInkMuted)),
          ],
        ),
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (quote.client.trim().isNotEmpty) ...[
                    pw.Text(t('Zamawiający', 'Client'),
                        style: st(7.5, color: _kInkMuted)),
                    pw.Text(quote.client.trim(), style: st(10, b: true)),
                    pw.SizedBox(height: 6),
                  ],
                  if (quote.title.trim().isNotEmpty) ...[
                    pw.Text(t('Przedmiot', 'Subject'),
                        style: st(7.5, color: _kInkMuted)),
                    pw.Text(quote.title.trim(), style: st(10, b: true)),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                    '${t('Materiał', 'Material')}: ${en ? quote.material.labelEn : quote.material.labelPl}',
                    style: st(8)),
                pw.Text('${t('Metoda', 'Method')}: ${quote.scheme.label}',
                    style: st(8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        if (valid.isEmpty && quote.extras.isEmpty)
          pw.Text(t('Brak pozycji.', 'No items.'),
              style: st(9, color: _kInkMuted))
        else
          scope,
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final f in facts)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                              width: 120,
                              child: pw.Text(f.$1,
                                  style: st(8, color: _kInkMuted))),
                          pw.Expanded(child: pw.Text(f.$2, style: st(8))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            priceBox,
          ],
        ),
        assumptions,
        if (!internal && settings.terms.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(t('Warunki', 'Terms'), style: st(9, b: true)),
          pw.SizedBox(height: 3),
          pw.Text(settings.terms.trim(), style: st(8)),
        ],
        if (quote.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(t('Uwagi', 'Notes'), style: st(9, b: true)),
          pw.SizedBox(height: 3),
          pw.Text(quote.notes.trim(), style: st(8)),
        ],
        pw.SizedBox(height: 10),
        pw.Text(
          internal
              ? t(
                  'Kosztorys szacunkowy: czasy i zużycie z geometrii rowka i typowych '
                      'wydajności procesów. Skalibruj założenia pomiarem własnej brygady.',
                  'Estimate: times and consumption from the groove geometry and typical '
                      'process rates. Calibrate the assumptions against your own crew.')
              : t(
                  'Cena dotyczy zakresu wymienionego powyżej. Prace dodatkowe, przestoje '
                      'niezależne od wykonawcy i zmiany zakresu rozliczane osobno.',
                  'The price covers the scope listed above. Additional work, downtime not '
                      'caused by the contractor and scope changes are charged separately.'),
          style: st(7.5, color: _kInkMuted),
        ),
        pw.SizedBox(height: 22),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.all(6),
              height: 46,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _kRule, width: 0.5)),
              child: pw.Text(
                  '${t('Wystawił', 'Issued by')}${c.person.trim().isEmpty ? '' : ': ${c.person.trim()}'}',
                  style: st(7.5, b: true)),
            ),
          ),
          if (!internal)
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(left: 6),
                padding: const pw.EdgeInsets.all(6),
                height: 46,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _kRule, width: 0.5)),
                child: pw.Text(
                    t('Akceptacja zamawiającego', 'Client acceptance'),
                    style: st(7.5, b: true)),
              ),
            ),
        ]),
      ],
    ));
    return doc;
  }
}

/// Procesy użyte w wycenie (do ekranu „Założenia").
Set<QuoteProcess> processesUsed(WeldQuote q) => {
      ...q.scheme.processes,
      for (final j in q.joints) ...?j.scheme?.processes,
    };
