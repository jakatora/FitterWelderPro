// Zakładka „Spoiny": pozycje złączy i pozycje dodatkowe wyceny.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/quotes/quote_calculator.dart';
import '../../domain/quotes/quote_labels.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import 'quote_edit_page.dart' show QuoteChanged;
import 'quote_import_sheet.dart';
import 'quote_joint_page.dart';
import 'quote_widgets.dart';

class QuoteScopeTab extends StatelessWidget {
  final WeldQuote quote;
  final QuoteResult result;
  final QuoteChanged onChanged;

  /// Zmiana liczona od AKTUALNEJ wyceny — dla akcji, które wracają po
  /// czasie (okno pozycji, „Cofnij" w SnackBarze), a ten widżet trzyma
  /// wycenę z chwili zbudowania.
  final void Function(WeldQuote Function(WeldQuote current)) onUpdate;
  final VoidCallback onOpenDetails;

  const QuoteScopeTab({
    super.key,
    required this.quote,
    required this.result,
    required this.onChanged,
    required this.onUpdate,
    required this.onOpenDetails,
  });

  Future<void> _editJoint(BuildContext context, [QuoteJoint? j]) async {
    final saved = await Navigator.of(context).push<QuoteJoint>(
      MaterialPageRoute(builder: (_) => QuoteJointPage(quote: quote, joint: j)),
    );
    if (saved == null) return;
    onUpdate((cur) {
      final list = [...cur.joints];
      final i = list.indexWhere((x) => x.id == saved.id);
      if (i >= 0) {
        list[i] = saved;
      } else {
        list.add(saved);
      }
      return cur.copyWith(joints: list);
    });
  }

  /// Import ze skanu ISO / dziennika spoin / projektu CUT. Pozycje dochodzą
  /// do AKTUALNEJ wyceny (okno wraca po czasie), a „Cofnij" zdejmuje tylko
  /// je.
  Future<void> _import(BuildContext context) async {
    final added = await showQuoteImport(context, quote: quote);
    if (added == null || added.isEmpty) return;
    final ids = {for (final j in added) j.id};
    onUpdate((cur) => cur.copyWith(joints: [...cur.joints, ...added]));
    if (!context.mounted) return;
    final welds = added.fold(0, (a, j) => a + j.count);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Dodano pozycji: ${added.length} (spoin: $welds).',
            en: 'Added items: ${added.length} (welds: $welds).')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () => onUpdate((cur) => cur.copyWith(
              joints: cur.joints.where((x) => !ids.contains(x.id)).toList())),
        ),
      ));
  }

  void _duplicate(QuoteJoint j) {
    final list = [...quote.joints];
    final i = list.indexWhere((x) => x.id == j.id);
    list.insert(i + 1, j.copyWith(id: const Uuid().v4()));
    onChanged(quote.copyWith(joints: list));
  }

  void _removeJoint(BuildContext context, QuoteJoint j) {
    final index = quote.joints.indexWhere((x) => x.id == j.id);
    onUpdate((cur) =>
        cur.copyWith(joints: cur.joints.where((x) => x.id != j.id).toList()));
    Haptic.tap();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Usunięto pozycję.', en: 'Item removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          // Wraca tylko ta pozycja — inne zmiany zrobione po usunięciu
          // zostają.
          onPressed: () => onUpdate((cur) {
            if (cur.joints.any((x) => x.id == j.id)) return cur;
            final list = [...cur.joints];
            list.insert(index.clamp(0, list.length), j);
            return cur.copyWith(joints: list);
          }),
        ),
      ));
  }

  Future<void> _editExtra(BuildContext context, [QuoteExtra? e]) async {
    final saved = await showDialog<QuoteExtra>(
      context: context,
      builder: (_) => _ExtraDialog(extra: e),
    );
    if (saved == null) return;
    onUpdate((cur) {
      final list = [...cur.extras];
      final i = list.indexWhere((x) => x.id == saved.id);
      if (i >= 0) {
        list[i] = saved;
      } else {
        list.add(saved);
      }
      return cur.copyWith(extras: list);
    });
  }

  void _removeExtra(QuoteExtra e) => onUpdate((cur) =>
      cur.copyWith(extras: cur.extras.where((x) => x.id != e.id).toList()));

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        // Kontekst wyceny — jedno dotknięcie do zakładki Dane.
        InkWell(
          key: const ValueKey('quote-context'),
          onTap: onOpenDetails,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18, color: kTextMut),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      en ? quote.material.labelEn : quote.material.labelPl,
                      quote.scheme.label,
                      en ? quote.site.labelEn : quote.site.labelPl,
                      if (quote.purge)
                        context.tr(pl: 'formowanie', en: 'purge'),
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 12.5, color: kTextSec),
                  ),
                ),
                Text(context.tr(pl: 'Zmień', en: 'Change'),
                    style: const TextStyle(
                        color: kArc, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (result.invalidJointCount > 0)
          QuoteNotice(
            color: kFail,
            icon: Icons.error_outline,
            text: context.tr(
                pl: 'Pozycje z błędem (${result.invalidJointCount}) nie są liczone — popraw je.',
                en: 'Items with errors (${result.invalidJointCount}) are not counted — fix them.'),
          ),
        if (quote.joints.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              context.tr(
                pl: 'Dodaj spoiny, które masz wykonać: np. 24 spoiny DN100 '
                    'Sch 40 w pozycji 5G. Aplikacja policzy stopiwo, czas, '
                    'spoiwo, gaz i prąd, a z Twoich stawek — cenę.',
                en: 'Add the welds you have to make: e.g. 24 welds DN100 '
                    'Sch 40 in 5G. The app works out deposit, time, filler, '
                    'gas and power, and — from your rates — the price.',
              ),
              style: const TextStyle(color: kTextSec, height: 1.45),
            ),
          ),
        for (final (i, j) in quote.joints.indexed)
          _JointCard(
            key: ValueKey('joint-${j.id}'),
            index: i,
            joint: j,
            result: result.joints.length > i ? result.joints[i] : null,
            onEdit: () => _editJoint(context, j),
            onDuplicate: () => _duplicate(j),
            onDelete: () => _removeJoint(context, j),
          ),
        const SizedBox(height: 4),
        FilledButton.icon(
          key: const ValueKey('add-joint'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: kArc,
            foregroundColor: kOnArc,
          ),
          onPressed: () => _editJoint(context),
          icon: const Icon(Icons.add),
          label: Text(context.tr(pl: 'Dodaj spoiny', en: 'Add welds'),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('import-joints'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: () => _import(context),
          icon: const Icon(Icons.move_to_inbox_outlined),
          label: Text(context.tr(
              pl: 'Importuj spoiny (skan ISO, dziennik)',
              en: 'Import welds (ISO scan, journal)')),
        ),
        const SizedBox(height: 20),
        QuoteSection(
          title: context.tr(pl: 'Pozycje dodatkowe', en: 'Additional items'),
          subtitle: context.tr(
              pl: 'Dojazd, wynajem agregatu, materiał, PWHT u podwykonawcy, '
                  'rusztowanie…',
              en: 'Travel, generator hire, material, subcontracted PWHT, '
                  'scaffolding…'),
          children: [
            for (final e in quote.extras)
              ListTile(
                key: ValueKey('extra-${e.id}'),
                contentPadding: EdgeInsets.zero,
                onTap: () => _editExtra(context, e),
                title: Text(e.description.trim().isEmpty
                    ? context.tr(pl: '(bez opisu)', en: '(no description)')
                    : e.description),
                subtitle: Text(
                  '${formatQty(e.quantity)} ${e.unit} × ${formatPln(costGrosze(1, e.unitPrice))}'
                  '${e.withMarkup ? '' : context.tr(pl: '  ·  bez narzutu', en: '  ·  no markup')}',
                  style: const TextStyle(fontSize: 12, color: kTextMut),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatPln(costGrosze(e.quantity, e.unitPrice)),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => _removeExtra(e),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('add-extra'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinTapTarget)),
              onPressed: () => _editExtra(context),
              icon: const Icon(Icons.playlist_add),
              label: Text(context.tr(pl: 'Dodaj pozycję', en: 'Add item')),
            ),
          ],
        ),
      ],
    );
  }
}

class _JointCard extends StatelessWidget {
  final int index;
  final QuoteJoint joint;
  final JointResult? result;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _JointCard({
    super.key,
    required this.index,
    required this.joint,
    required this.result,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final r = result;
    final bad = r == null || !r.isValid;
    // Ink zamiast dekoracji Containera — fala dotknięcia ma być widoczna.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Ink(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: bad ? kFail.withValues(alpha: 0.6) : kBorder),
        ),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kArc.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${joint.count}×',
                      style: const TextStyle(
                          color: kArc,
                          fontWeight: FontWeight.w900,
                          fontSize: 15)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(jointKindShort(joint.kind, en: en),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(jointSizeLabel(joint, en: en),
                          style:
                              const TextStyle(fontSize: 12.5, color: kTextSec)),
                      if (joint.label.trim().isNotEmpty)
                        Text(joint.label.trim(),
                            style: const TextStyle(
                                fontSize: 12.5, color: kTextSec)),
                      const SizedBox(height: 4),
                      if (bad)
                        Text(
                          (r?.problems ?? joint.problems)
                              .map((p) => jointProblemText(p, en: en))
                              .join(' · '),
                          style: const TextStyle(fontSize: 12, color: kFail),
                        )
                      else
                        Text(
                          [
                            r.scheme.label,
                            joint.position.code,
                            '${formatQty(r.depositedKg, decimals: 2)} kg',
                            formatHours(r.weldHours + r.prepHours),
                          ].join('  ·  '),
                          style: const TextStyle(fontSize: 12, color: kTextMut),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.tr(pl: 'Więcej', en: 'More'),
                  onSelected: (v) => switch (v) {
                    'dup' => onDuplicate(),
                    'del' => onDelete(),
                    _ => onEdit(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit',
                        child: Text(context.tr(pl: 'Edytuj', en: 'Edit'))),
                    PopupMenuItem(
                        value: 'dup',
                        child:
                            Text(context.tr(pl: 'Duplikuj', en: 'Duplicate'))),
                    PopupMenuItem(
                        value: 'del',
                        child: Text(context.tr(pl: 'Usuń', en: 'Delete'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtraDialog extends StatefulWidget {
  final QuoteExtra? extra;
  const _ExtraDialog({this.extra});

  @override
  State<_ExtraDialog> createState() => _ExtraDialogState();
}

class _ExtraDialogState extends State<_ExtraDialog> {
  late final QuoteExtra _e = widget.extra ?? QuoteExtra(id: const Uuid().v4());
  late final _desc = TextEditingController(text: _e.description);
  late final _qty = TextEditingController(text: numText(_e.quantity));
  late final _unit = TextEditingController(text: _e.unit);
  late final _price = TextEditingController(
      text: _e.unitPrice == 0 ? '' : numText(_e.unitPrice));
  late bool _markup = _e.withMarkup;

  @override
  void dispose() {
    for (final c in [_desc, _qty, _unit, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _qtyV => parseDecimal(_qty.text);
  double? get _priceV => parseDecimal(_price.text);

  bool get _ok =>
      _desc.text.trim().isNotEmpty && (_qtyV ?? -1) >= 0 && _priceV != null;

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String l, {String? suffix}) => InputDecoration(
        labelText: l,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder());
    return AlertDialog(
      title: Text(widget.extra == null
          ? context.tr(pl: 'Pozycja dodatkowa', en: 'Additional item')
          : context.tr(pl: 'Edycja pozycji', en: 'Edit item')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('extra-desc'),
              controller: _desc,
              autofocus: widget.extra == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: dec(context.tr(pl: 'Opis', en: 'Description')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('extra-qty'),
                  controller: _qty,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  decoration: dec(context.tr(pl: 'Ilość', en: 'Qty')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _unit,
                  decoration: dec(context.tr(pl: 'Jedn.', en: 'Unit')),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('extra-price'),
              controller: _price,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              decoration: dec(
                  context.tr(pl: 'Cena jedn. netto', en: 'Unit price net'),
                  suffix: 'zł'),
              onChanged: (_) => setState(() {}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _markup,
              onChanged: (v) => setState(() => _markup = v),
              title: Text(context.tr(
                  pl: 'Doliczaj narzut i zysk',
                  en: 'Apply overhead and profit')),
              subtitle: Text(
                context.tr(
                    pl: 'Wyłącz dla kosztów przenoszonych 1:1 (np. opłaty, '
                        'które klient zwraca bez marży).',
                    en: 'Turn off for pass-through costs (e.g. fees the client '
                        'refunds without margin).'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('extra-save'),
          onPressed: _ok
              ? () => Navigator.pop(
                    context,
                    _e.copyWith(
                      description: _desc.text.trim(),
                      quantity: _qtyV,
                      unit: _unit.text.trim().isEmpty
                          ? 'szt.'
                          : _unit.text.trim(),
                      unitPrice: _priceV,
                      withMarkup: _markup,
                    ),
                  )
              : null,
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}
