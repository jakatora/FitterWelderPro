import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/nps_dn_od_r.dart';
import '../i18n/app_language.dart';
import '../services/takeout_catalog.dart';
import 'number_field.dart';

/// What the fitter told the builder about a reducer the library did not have.
class ReducerSpec {
  const ReducerSpec({
    required this.otherDiameterMm,
    required this.lengthMm,
    required this.expander,
  });

  /// OD of the pipe on the reducer's other end.
  final double otherDiameterMm;

  /// End-to-end length H (face to face) — what "ISO to the far face"
  /// subtracts from the cut.
  final double lengthMm;

  /// True when the line gets WIDER in the direction the route is built.
  final bool expander;

  /// Large end, small end — the order the component library stores a
  /// reducer in (`diameter_mm` → `diameter_out_mm`), whichever way round it
  /// is welded in. The route reads the direction from which end sits on the
  /// segment's pipe (`reducerOtherEndMm`).
  (double large, double small) libraryEnds(double currentDiameterMm) =>
      (
        math.max(currentDiameterMm, otherDiameterMm),
        math.min(currentDiameterMm, otherDiameterMm),
      );
}

/// ASME B16.9 reducer length H for the pair of ODs, looked up by the LARGER
/// end (the table lists one H per large end), with that end's DN; null when
/// the large OD is not a B16.9 size or the table has no H for it.
///
/// Only a suggestion: the dialog shows it on a chip, it is never written
/// into the field unless the fitter taps it — a swaged or EN 10253 reducer
/// can be longer, and a wrong H is a wrong cut.
({int dn, double h})? suggestedReducerLength(double d1, double d2) {
  if (!d1.isFinite || !d2.isFinite) return null;
  final row = b169RowForOd(math.max(d1, d2));
  if (row == null) return null;
  final h = TakeoutCatalog.reducer[row.dn];
  if (h == null) return null;
  return (dn: row.dn, h: h.toDouble());
}

/// Error for a reducer spec, or null when it is usable. Pure, so the rules
/// are tested without a dialog.
///
/// [atStart]: the reducer is the START of the segment (the pipe on its other
/// end came BEFORE), otherwise its END (the pipe on the other end comes next).
/// A narrowing reducer at the END leads to a smaller pipe; at the START it
/// came from a larger one — and the other way round for an expander.
String? validateReducerSpec({
  required double currentDiameterMm,
  required bool atStart,
  required bool? expander,
  required double? otherDiameterMm,
  required double? lengthMm,
  required bool english,
}) {
  String t(String pl, String en) => english ? en : pl;
  if (expander == null) {
    return t('Wybierz kierunek: zwężka czy ekspander.',
        'Choose the direction: reducer or expander.');
  }
  final other = otherDiameterMm;
  if (other == null || !other.isFinite || other <= 0) {
    return t('Podaj średnicę drugiego końca (mm).',
        'Enter the diameter of the other end (mm).');
  }
  if ((other - currentDiameterMm).abs() <= 0.05) {
    return t('Oba końce mają tę samą średnicę — to nie jest redukcja.',
        'Both ends have the same diameter — that is not a reducer.');
  }
  final nextIsSmaller = atStart ? other > currentDiameterMm : other < currentDiameterMm;
  // Narrowing: the route continues on the smaller pipe.
  if (!expander && !nextIsSmaller) {
    return atStart
        ? t('Zwężka na początku: rura przed nią musi być WIĘKSZA niż Ø${currentDiameterMm.toStringAsFixed(1)}.',
            'Reducer at the start: the pipe before it must be LARGER than Ø${currentDiameterMm.toStringAsFixed(1)}.')
        : t('Zwężka: rura za nią musi być MNIEJSZA niż Ø${currentDiameterMm.toStringAsFixed(1)}.',
            'Reducer: the pipe after it must be SMALLER than Ø${currentDiameterMm.toStringAsFixed(1)}.');
  }
  if (expander && nextIsSmaller) {
    return atStart
        ? t('Ekspander na początku: rura przed nim musi być MNIEJSZA niż Ø${currentDiameterMm.toStringAsFixed(1)}.',
            'Expander at the start: the pipe before it must be SMALLER than Ø${currentDiameterMm.toStringAsFixed(1)}.')
        : t('Ekspander: rura za nim musi być WIĘKSZA niż Ø${currentDiameterMm.toStringAsFixed(1)}.',
            'Expander: the pipe after it must be LARGER than Ø${currentDiameterMm.toStringAsFixed(1)}.');
  }
  final h = lengthMm;
  if (h == null || !h.isFinite || h <= 0) {
    return t('Podaj długość redukcji H (czoło–czoło, mm). '
            'Bez niej „ISO do końca redukcji” da rurę za długą o całą redukcję.',
        'Enter the reducer length H (face to face, mm). Without it '
            '"ISO to the end of the reducer" leaves the pipe a whole reducer too long.');
  }
  if (h > 2000) {
    return t('H > 2000 mm — sprawdź wartość.', 'H > 2000 mm — check the value.');
  }
  return null;
}

/// Asks for a reducer the library does not have yet: direction, the other
/// end's diameter and the length H. Pops a [ReducerSpec] or null (cancel).
///
/// [lengthOnly]: the reducer is already known (a library entry saved with
/// H = 0 by an older version) — only H is asked for; pops a spec whose
/// diameter/direction are those passed in.
Future<ReducerSpec?> showReducerSpecDialog(
  BuildContext context, {
  required double currentDiameterMm,
  required bool atStart,
  double? knownOtherDiameterMm,
  bool lengthOnly = false,
}) {
  return showDialog<ReducerSpec>(
    context: context,
    builder: (_) => ReducerSpecDialog(
      currentDiameterMm: currentDiameterMm,
      atStart: atStart,
      knownOtherDiameterMm: knownOtherDiameterMm,
      lengthOnly: lengthOnly,
    ),
  );
}

class ReducerSpecDialog extends StatefulWidget {
  const ReducerSpecDialog({
    super.key,
    required this.currentDiameterMm,
    required this.atStart,
    this.knownOtherDiameterMm,
    this.lengthOnly = false,
  });

  final double currentDiameterMm;
  final bool atStart;
  final double? knownOtherDiameterMm;
  final bool lengthOnly;

  @override
  State<ReducerSpecDialog> createState() => _ReducerSpecDialogState();
}

class _ReducerSpecDialogState extends State<ReducerSpecDialog> {
  late final _other = TextEditingController(
      text: widget.knownOtherDiameterMm == null
          ? ''
          : _fmt(widget.knownOtherDiameterMm!));
  final _length = TextEditingController();
  bool? _expander;
  String? _error;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void initState() {
    super.initState();
    final known = widget.knownOtherDiameterMm;
    if (widget.lengthOnly && known != null) {
      final nextIsSmaller = widget.atStart
          ? known > widget.currentDiameterMm
          : known < widget.currentDiameterMm;
      _expander = !nextIsSmaller;
    }
  }

  @override
  void dispose() {
    _other.dispose();
    _length.dispose();
    super.dispose();
  }

  bool get _english => context.language == AppLanguage.en;

  void _submit() {
    final other = parseDecimal(_other.text);
    final h = parseDecimal(_length.text);
    final error = validateReducerSpec(
      currentDiameterMm: widget.currentDiameterMm,
      atStart: widget.atStart,
      expander: _expander,
      otherDiameterMm: other,
      lengthMm: h,
      english: _english,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      ReducerSpec(otherDiameterMm: other!, lengthMm: h!, expander: _expander!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.currentDiameterMm.toStringAsFixed(1);
    final other = parseDecimal(_other.text);
    final hint = other == null
        ? null
        : suggestedReducerLength(widget.currentDiameterMm, other);
    final otherLabel = widget.atStart
        ? context.tr(
            pl: 'Średnica rury PRZED redukcją (mm)',
            en: 'Diameter of the pipe BEFORE the reducer (mm)')
        : context.tr(
            pl: 'Średnica rury ZA redukcją (mm)',
            en: 'Diameter of the pipe AFTER the reducer (mm)');

    return AlertDialog(
      title: Text(widget.lengthOnly
          ? context.tr(
              pl: 'Redukcja bez długości H', en: 'Reducer without length H')
          : context.tr(pl: 'Nowa redukcja na Ø$d', en: 'New reducer on Ø$d')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.lengthOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(context.tr(
                  pl: 'Ten wpis w bibliotece ma H = 0. Podaj długość — '
                      'poprawi się wpis w bibliotece.',
                  en: 'This library entry has H = 0. Enter the length — '
                      'the library entry is corrected.',
                )),
              )
            else ...[
              Text(
                context.tr(pl: 'Kierunek trasy', en: 'Route direction'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                key: const ValueKey('reducer-direction'),
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.tr(pl: 'Zwężka', en: 'Reducer')),
                    icon: const Icon(Icons.compress),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.tr(pl: 'Ekspander', en: 'Expander')),
                    icon: const Icon(Icons.expand),
                  ),
                ],
                selected: {if (_expander != null) _expander!},
                onSelectionChanged: (s) => setState(() {
                  _expander = s.isEmpty ? null : s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 4),
              Text(
                widget.atStart
                    ? context.tr(
                        pl: 'Zwężka: rura przed nią jest większa. Ekspander: mniejsza.',
                        en: 'Reducer: the pipe before it is larger. Expander: smaller.')
                    : context.tr(
                        pl: 'Zwężka: dalej rura mniejsza. Ekspander: dalej rura większa.',
                        en: 'Reducer: the pipe continues smaller. Expander: larger.'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('reducer-other-diameter'),
                controller: _other,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                autofocus: true,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(labelText: otherLabel),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('reducer-length'),
              controller: _length,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              autofocus: widget.lengthOnly,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Długość H czoło–czoło (mm)',
                    en: 'Length H face to face (mm)'),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  key: const ValueKey('reducer-length-suggestion'),
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(context.tr(
                    pl: 'Wstaw H = ${hint.h.toStringAsFixed(0)} mm '
                        '(ASME B16.9, DN${hint.dn})',
                    en: 'Use H = ${hint.h.toStringAsFixed(0)} mm '
                        '(ASME B16.9, DN${hint.dn})',
                  )),
                  onPressed: () => setState(() {
                    _length.text = hint.h.toStringAsFixed(0);
                    _error = null;
                  }),
                ),
              ),
              Text(
                context.tr(
                  pl: 'Podpowiedź z tabeli — sprawdź na kształtce lub atestach.',
                  en: 'Table value — check it against the fitting or its datasheet.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('reducer-error'),
                style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
