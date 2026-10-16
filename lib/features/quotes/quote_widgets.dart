// Drobne widżety modułu wycen: sekcja-karta, pole liczbowe z jednostką,
// wiersz kwoty, chip wyboru.

import 'package:flutter/material.dart';

import '../../domain/quotes/quote_calculator.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';

/// Liczba do pola: bez zbędnych zer, przecinek w PL.
String numText(double? v, {int decimals = 2}) {
  if (v == null || !v.isFinite) return '';
  final s = formatQty(v, decimals: decimals);
  return AppLanguageController.isEnglish ? s.replaceAll(',', '.') : s;
}

class QuoteSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const QuoteSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
  });

  @override
  Widget build(BuildContext context) {
    // Material, nie dekorowany Container: ListTile i przyciski w sekcji
    // malują atrament kliknięcia na najbliższym Material — pod kolorowym
    // Containerem byłby niewidoczny (i Flutter zgłasza asercję).
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: kTextSec,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style:
                  const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
        ],
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// Pole liczbowe trzymające własny kontroler. Wartość zmieniona z zewnątrz
/// (np. zmiana materiału podmienia ceny spoiw) trafia do pola, gdy monter
/// w nim nie pisze — pole nigdy nie pokazuje innej liczby niż ta, z której
/// liczy się cena. Puste pole to błąd (cena liczy się dalej z poprzedniej
/// wartości), chyba że [allowEmpty].
class QuoteNumberField extends StatefulWidget {
  final String label;
  final double? value;
  final String? unit;
  final String? helper;
  final ValueChanged<double?> onChanged;
  final bool decimal;
  final int decimals;
  final String? Function(double? v)? validate;

  /// Puste pole jest dozwolone (np. opcjonalna stawka rynkowa).
  final bool allowEmpty;

  const QuoteNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit,
    this.helper,
    this.decimal = true,
    this.decimals = 2,
    this.validate,
    this.allowEmpty = false,
  });

  @override
  State<QuoteNumberField> createState() => _QuoteNumberFieldState();
}

class _QuoteNumberFieldState extends State<QuoteNumberField> {
  late final TextEditingController _c = TextEditingController(
      text: numText(widget.value, decimals: widget.decimals));
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Po zejściu z pustego pola wraca liczba, z której naprawdę liczymy.
    _focus.addListener(() {
      if (!_focus.hasFocus && !widget.allowEmpty && _c.text.trim().isEmpty) {
        setState(
            () => _c.text = numText(widget.value, decimals: widget.decimals));
      }
    });
  }

  @override
  void didUpdateWidget(QuoteNumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_focus.hasFocus) {
      final shown = parseDecimal(_c.text);
      final v = widget.value;
      if (shown == null || v == null || (shown - v).abs() > 1e-9) {
        _c.text = numText(v, decimals: widget.decimals);
      }
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseDecimal(_c.text);
    final empty = _c.text.trim().isEmpty;
    final error = empty
        ? (widget.allowEmpty
            ? null
            : context.tr(pl: 'Wpisz wartość', en: 'Enter a value'))
        : parsed == null
            ? context.tr(pl: 'Wpisz liczbę', en: 'Enter a number')
            : widget.validate?.call(parsed);
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: numberKeyboard(decimal: widget.decimal),
      inputFormatters: numberInputFormatters(decimal: widget.decimal),
      onChanged: (t) {
        setState(() {});
        widget.onChanged(parseDecimal(t));
      },
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.unit,
        helperText: widget.helper,
        helperMaxLines: 3,
        errorText: error,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Dwa pola obok siebie (wąski telefon → jedno pod drugim).
class FieldPair extends StatelessWidget {
  final Widget left;
  final Widget right;
  const FieldPair({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 300) {
        return Column(children: [left, const SizedBox(height: 10), right]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      );
    });
  }
}

/// Wiersz „etykieta ........ 1 234,56 zł" (przytrzymanie kopiuje kwotę).
class MoneyRow extends StatelessWidget {
  final String label;
  final int grosze;
  final bool strong;
  final bool hot;
  final String? hint;

  const MoneyRow({
    super.key,
    required this.label,
    required this.grosze,
    this.strong = false,
    this.hot = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final value = formatPln(grosze);
    return CopyOnLongPress(
      value: value,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: strong ? 15 : 13.5,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                        color: strong ? kText : kTextSec,
                      )),
                  if (hint != null)
                    Text(hint!,
                        style:
                            const TextStyle(fontSize: 11.5, color: kTextMut)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: strong ? 16 : 14,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: hot ? kArc : kText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etykieta + wartość w siatce faktów („Roboczogodziny · 12,5 h").
class FactTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;

  const FactTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return CopyOnLongPress(
      value: value,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: kTextMut),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: kTextMut,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: kText,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            if (sub != null)
              Text(sub!,
                  style: const TextStyle(fontSize: 11.5, color: kTextSec)),
          ],
        ),
      ),
    );
  }
}

/// Komunikat ostrzegawczy w treści (nie SnackBar — nie wędruje za
/// użytkownikiem na inne ekrany).
class QuoteNotice extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const QuoteNotice({
    super.key,
    required this.text,
    this.color = kWarn,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 12.5, color: kText, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
