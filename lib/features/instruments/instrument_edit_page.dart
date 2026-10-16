// Formularz przyrządu w rejestrze kalibracji.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/instruments/instrument.dart';
import '../../domain/qualification/qualification_dates.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../qualification/form_bits.dart';
import '../quotes/quote_widgets.dart';

class InstrumentEditPage extends StatefulWidget {
  final Instrument? instrument;
  const InstrumentEditPage({super.key, this.instrument});

  @override
  State<InstrumentEditPage> createState() => _InstrumentEditPageState();
}

class _InstrumentEditPageState extends State<InstrumentEditPage> {
  late Instrument _i = widget.instrument ??
      Instrument(
        id: const Uuid().v4(),
        kind: InstrumentKind.pressureGauge,
        intervalMonths: InstrumentKind.pressureGauge.defaultIntervalMonths,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
  late final _name = TextEditingController(text: _i.name);
  late final _serial = TextEditingController(text: _i.serialNo);
  late final _location = TextEditingController(text: _i.location);
  late final _interval = TextEditingController(text: '${_i.intervalMonths}');
  late final _cert = TextEditingController(text: _i.certificateNo);
  late final _by = TextEditingController(text: _i.calibratedBy);
  late final _notes = TextEditingController(text: _i.notes);

  @override
  void dispose() {
    for (final c in [
      _name,
      _serial,
      _location,
      _interval,
      _cert,
      _by,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final interval = int.tryParse(_interval.text.trim());
    if (interval == null || interval < 1 || interval > 240) {
      Haptic.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Interwał od 1 do 240 miesięcy.',
              en: 'Interval from 1 to 240 months.'))));
      return;
    }
    Haptic.saved();
    Navigator.of(context).pop(_i.copyWith(
      name: _name.text.trim(),
      serialNo: _serial.text.trim(),
      location: _location.text.trim(),
      intervalMonths: interval,
      certificateNo: _cert.text.trim(),
      calibratedBy: _by.text.trim(),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final due = _i
        .copyWith(intervalMonths: int.tryParse(_interval.text.trim()))
        .dueDate;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.instrument == null
            ? context.tr(pl: 'Nowy przyrząd', en: 'New instrument')
            : context.tr(pl: 'Przyrząd', en: 'Instrument')),
        actions: [
          TextButton(
            key: const ValueKey('instrument-save'),
            onPressed: _save,
            child: Text(context.tr(pl: 'Zapisz', en: 'Save'),
                style:
                    const TextStyle(color: kArc, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteSection(
            title: context.tr(pl: 'Rodzaj', en: 'Kind'),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in InstrumentKind.values)
                    ChoiceChip(
                      key: ValueKey('instrument-kind-${k.code}'),
                      label: Text(en ? k.labelEn : k.labelPl),
                      selected: _i.kind == k,
                      onSelected: (_) => setState(() {
                        // Interwał idzie za rodzajem, dopóki go nie zmieniono.
                        final keep = int.tryParse(_interval.text.trim()) !=
                            _i.kind.defaultIntervalMonths;
                        _i = _i.copyWith(kind: k);
                        if (!keep) {
                          _interval.text = '${k.defaultIntervalMonths}';
                        }
                      }),
                    ),
                ],
              ),
              if ((en ? _i.kind.hintEn : _i.kind.hintPl).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(en ? _i.kind.hintEn : _i.kind.hintPl,
                    style: const TextStyle(fontSize: 12, color: kTextMut)),
              ],
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Identyfikacja', en: 'Identification'),
            children: [
              PlainField(
                  controller: _name,
                  label: context.tr(pl: 'Nazwa / model', en: 'Name / model')),
              const SizedBox(height: 10),
              PlainField(
                  controller: _serial,
                  label: context.tr(pl: 'Nr seryjny', en: 'Serial no.')),
              const SizedBox(height: 10),
              PlainField(
                  controller: _location,
                  label: context.tr(
                      pl: 'Gdzie / u kogo', en: 'Where / with whom')),
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Kalibracja', en: 'Calibration'),
            children: [
              DateField(
                label: context.tr(
                    pl: 'Ostatnia kalibracja / walidacja',
                    en: 'Last calibration / validation'),
                value: parseFlexibleDate(_i.lastCalibration),
                onChanged: (d) => setState(() => _i = _i.copyWith(
                    lastCalibration: d == null ? '' : formatIsoDate(d))),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('instrument-interval'),
                controller: _interval,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Interwał', en: 'Interval'),
                  suffixText: context.tr(pl: 'mies.', en: 'months'),
                  helperText: context.tr(
                      pl: 'Wg procedury firmy / producenta.',
                      en: 'Per company procedure / manufacturer.'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DateField(
                label: context.tr(
                    pl: 'Termin ze świadectwa (opcjonalnie)',
                    en: 'Due date from the certificate (optional)'),
                value: parseFlexibleDate(_i.dueOverride),
                helper: context.tr(
                    pl: 'Ma pierwszeństwo przed „ostatnia + interwał”.',
                    en: 'Takes precedence over "last + interval".'),
                onChanged: (d) => setState(() => _i = _i.copyWith(
                    dueOverride: d == null ? '' : formatIsoDate(d))),
              ),
              const SizedBox(height: 8),
              Text(
                due == null
                    ? context.tr(
                        pl: 'Termin: brak (podaj datę kalibracji).',
                        en: 'Due: none (enter the calibration date).')
                    : context.tr(
                        pl: 'Następna kalibracja: ${formatIsoDate(due)}',
                        en: 'Next calibration: ${formatIsoDate(due)}'),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, color: kText),
              ),
              const SizedBox(height: 10),
              PlainField(
                  controller: _cert,
                  label:
                      context.tr(pl: 'Nr świadectwa', en: 'Certificate no.')),
              const SizedBox(height: 10),
              PlainField(
                  controller: _by,
                  label: context.tr(
                      pl: 'Kalibrował (laboratorium)',
                      en: 'Calibrated by (laboratory)')),
              const SizedBox(height: 10),
              PlainField(
                  controller: _notes,
                  maxLines: 4,
                  label: context.tr(pl: 'Uwagi', en: 'Notes')),
            ],
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(context.tr(pl: 'Zapisz', en: 'Save'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
