// Drobne pola formularzy rejestru uprawnień i biblioteki WPS.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/qualification/qualification_dates.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

/// Liczba wpisana w polu formularza („1,5" albo „1.5"); `null` dla pustego.
/// Tekst, który nie jest liczbą, też daje `null` — walidator [decimalValidator]
/// zgłasza go wcześniej.
double? parseDecimalField(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return (v != null && v.isFinite) ? v : null;
}

/// Liczba nieujemna albo puste pole.
String? Function(String?) decimalValidator(BuildContext context) => (raw) {
      final t = (raw ?? '').trim();
      if (t.isEmpty) return null;
      final v = parseDecimalField(t);
      if (v == null) {
        return context.tr(pl: 'Wpisz liczbę', en: 'Enter a number');
      }
      if (v < 0) {
        return context.tr(pl: 'Nie może być ujemna', en: 'Cannot be negative');
      }
      return null;
    };

/// `1.5` → „1,5" w PL, „1.5" w EN; `null` → pusty tekst.
String formatDecimalField(double? v) {
  if (v == null) return '';
  var s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  if (!AppLanguageController.isEnglish) s = s.replaceAll('.', ',');
  return s;
}

/// Pole liczbowe z jednostką.
class DecimalField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? unit;
  final String? helper;

  const DecimalField({
    super.key,
    required this.controller,
    required this.label,
    this.unit,
    this.helper,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        validator: decimalValidator(context),
      );
}

/// Pole tekstowe jednoliniowe.
class PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final int maxLines;
  final int? maxLength;

  const PlainField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        minLines: 1,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      );
}

/// Data z kalendarza, z możliwością wyczyszczenia.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) onChanged(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today)
                : IconButton(
                    tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
                    icon: const Icon(Icons.clear),
                    onPressed: () => onChanged(null),
                  ),
          ),
          child: Text(
            value == null
                ? context.tr(pl: 'Nie ustawiono', en: 'Not set')
                : formatIsoDate(value!),
            style: TextStyle(color: value == null ? kTextMut : null),
          ),
        ),
      );
}

/// Nagłówek sekcji formularza.
class FormSectionTitle extends StatelessWidget {
  final String text;
  const FormSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: kTextSec,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// Dwa pola obok siebie (min – max).
class FieldPair extends StatelessWidget {
  final Widget left;
  final Widget right;
  const FieldPair({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      );
}

/// „1,5–6 mm", „≥ 25 mm", „—".
String describeRange(double? min, double? max, String unit) {
  if (min == null && max == null) return '—';
  if (min != null && max != null) {
    return '${formatDecimalField(min)}–${formatDecimalField(max)} $unit';
  }
  if (min != null) return '≥ ${formatDecimalField(min)} $unit';
  return '≤ ${formatDecimalField(max)} $unit';
}

/// Min ≤ max, gdy oba podane; komunikat błędu albo `null`.
String? rangeProblem(BuildContext context, double? min, double? max,
    {required String pl, required String en}) {
  if (min != null && max != null && min > max) {
    return context.tr(
      pl: '$pl: minimum większe od maksimum.',
      en: '$en: minimum is greater than maximum.',
    );
  }
  return null;
}
