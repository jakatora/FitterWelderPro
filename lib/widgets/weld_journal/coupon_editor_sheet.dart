/// Create or edit one test coupon of the coupon log: date, welder, machine,
/// size, weld program and its parameters, the O₂ reading of the purge, the
/// heat tint level on the AWS D18.2 scale and the result.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/heat_tint.dart';
import '../../database/coupon_dao.dart';
import '../../domain/weld_journal/coupon_entry.dart';
import '../../domain/weld_journal/weld_dates.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import 'wj_ui.dart';

/// Opens the editor; returns the saved coupon or null.
Future<CouponEntry?> showCouponEditor(
  BuildContext context, {
  required CouponEntry initial,
  required bool isNew,
  CouponDao? dao,
}) =>
    showModalBottomSheet<CouponEntry>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CouponEditor(
          initial: initial, isNew: isNew, dao: dao ?? CouponDao()),
    );

Color _verdictColor(HeatTintVerdict v) => switch (v) {
      HeatTintVerdict.pharma => kPass,
      HeatTintVerdict.food => kPass,
      HeatTintVerdict.marginal => kWarn,
      HeatTintVerdict.reject => kFail,
    };

class _CouponEditor extends StatefulWidget {
  final CouponEntry initial;
  final bool isNew;
  final CouponDao dao;
  const _CouponEditor(
      {required this.initial, required this.isNew, required this.dao});

  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  late final CouponEntry _c = widget.initial;
  late final _date = TextEditingController(text: _c.date);
  late final _welder = TextEditingController(text: _c.welder);
  late final _machine = TextEditingController(text: _c.machine);
  late final _size = TextEditingController(text: _c.size);
  late final _program = TextEditingController(text: _c.programNo);
  late final _params = TextEditingController(text: _c.programParams);
  late final _o2 = TextEditingController(text: formatO2Ppm(_c.o2Ppm));
  late final _notes = TextEditingController(text: _c.notes);
  late String _result = _c.result.isEmpty ? 'OK' : _c.result;
  late int? _tint = _c.heatTint;
  bool _saving = false;
  bool _closing = false;
  String? _dateError;
  String? _o2Error;
  late final CouponEntry _snapshot0;

  @override
  void initState() {
    super.initState();
    _snapshot0 = _build(_c.o2Ppm);
  }

  @override
  void dispose() {
    for (final c in [
      _date, _welder, _machine, _size, _program, _params, _o2, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  CouponEntry _build(double? o2) => _c.copyWith(
        date: _date.text.trim(),
        welder: _welder.text.trim(),
        machine: _machine.text.trim(),
        size: _size.text.trim(),
        programNo: _program.text.trim(),
        programParams: _params.text.trim(),
        o2Ppm: o2,
        heatTint: _tint,
        result: _result,
        notes: _notes.text.trim(),
      );

  bool get _dirty {
    final now = _build(parseO2Ppm(_o2.text));
    final a = now.toRow();
    final b = _snapshot0.toRow();
    return a.keys.any((k) => a[k] != b[k]) ||
        (_o2.text.trim().isNotEmpty && parseO2Ppm(_o2.text) == null);
  }

  Future<void> _close() async {
    if (_saving || _closing) return;
    final nav = Navigator.of(context);
    if (!_dirty) {
      nav.pop();
      return;
    }
    _closing = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(pl: 'Porzucić zmiany?', en: 'Discard changes?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr(pl: 'Wróć do edycji', en: 'Keep editing'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr(pl: 'Porzuć', en: 'Discard'))),
        ],
      ),
    );
    _closing = false;
    if (discard == true && mounted) nav.pop();
  }

  Future<void> _save() async {
    final date = normalizeWeldDate(_date.text);
    final rawO2 = _o2.text.trim();
    final o2 = parseO2Ppm(rawO2);
    setState(() {
      _dateError = date == null
          ? context.tr(
              pl: 'Data RRRR-MM-DD lub DD.MM.RRRR',
              en: 'Date YYYY-MM-DD or DD.MM.YYYY')
          : null;
      _o2Error = rawO2.isNotEmpty && o2 == null
          ? context.tr(pl: 'Liczba ppm ≥ 0', en: 'A ppm value ≥ 0')
          : null;
    });
    if (date == null || _o2Error != null) return;
    _date.text = date;
    final c = _build(o2).copyWith(date: date);
    setState(() => _saving = true);
    try {
      if (widget.isNew) {
        await widget.dao.insert(c);
      } else {
        await widget.dao.update(c);
      }
      if (!mounted) return;
      Navigator.pop(context, c);
    } catch (e) {
      debugPrint('CouponLog save error: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie zapisano kuponu. Spróbuj ponownie.',
            en: 'Coupon not saved. Try again.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o2 = parseO2Ppm(_o2.text);
    final suggested = o2 == null ? null : heatTintLevelForO2Ppm(o2);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _close();
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      widget.isNew
                          ? context.tr(
                              pl: 'Nowy kupon próbny', en: 'New test coupon')
                          : context.tr(pl: 'Edytuj kupon', en: 'Edit coupon'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kText),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: kTextSec),
                    tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                    onPressed: _saving ? null : _close,
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WjRow([
                        TextField(
                          controller: _date,
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(
                            labelText: context.tr(pl: 'Data', en: 'Date'),
                            errorText: _dateError,
                          ),
                        ),
                        TextField(
                          controller: _welder,
                          decoration: InputDecoration(
                              labelText:
                                  context.tr(pl: 'Spawacz', en: 'Welder')),
                        ),
                      ]),
                      WjRow([
                        TextField(
                          controller: _machine,
                          decoration: InputDecoration(
                              labelText: context.tr(
                                  pl: 'Maszyna / głowica',
                                  en: 'Machine / head')),
                        ),
                        TextField(
                          controller: _size,
                          decoration: InputDecoration(
                              labelText: context.tr(
                                  pl: 'Wymiar (OD×t)', en: 'Size (OD×t)'),
                              hintText: '2"×1.65'),
                        ),
                      ]),
                      WjRow([
                        TextField(
                          controller: _program,
                          decoration: InputDecoration(
                              labelText: context.tr(
                                  pl: 'Nr programu', en: 'Program no.')),
                        ),
                        TextField(
                          controller: _o2,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]')),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: context.tr(
                                pl: 'Odczyt O₂ (ppm)',
                                en: 'O₂ reading (ppm)'),
                            errorText: _o2Error,
                          ),
                        ),
                      ]),
                      TextField(
                        controller: _params,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: context.tr(
                              pl: 'Parametry programu',
                              en: 'Program parameters'),
                          hintText: context.tr(
                              pl: 'np. 85/45 A, 2.1 obr/min, gaz 8 l/min',
                              en: 'e.g. 85/45 A, 2.1 rpm, gas 8 l/min'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        context.tr(
                            pl: 'Przebarwienie (próbka AWS D18.2)',
                            en: 'Heat tint (AWS D18.2 sample)'),
                        style: const TextStyle(fontSize: 12, color: kTextSec),
                      ),
                      if (suggested != null)
                        Text(
                          context.tr(
                            pl: 'O₂ ${formatO2Ppm(o2)} ppm ≈ poziom '
                                '${suggested.level} (orientacyjnie — oceniaj '
                                'wg koloru)',
                            en: 'O₂ ${formatO2Ppm(o2)} ppm ≈ level '
                                '${suggested.level} (indicative — judge by '
                                'colour)',
                          ),
                          style:
                              const TextStyle(fontSize: 12, color: kTextMut),
                        ),
                      const SizedBox(height: 6),
                      _tintPicker(context),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final r in [('OK', kPass), ('NOK', kFail)])
                          WjChoiceChip(
                            label: r.$1,
                            color: r.$2,
                            selected: _result == r.$1,
                            onTap: () => setState(() => _result = r.$1),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notes,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: context.tr(pl: 'Uwagi', en: 'Notes'),
                          hintText: context.tr(
                              pl: 'np. boroskop poz. 2, przetop OK',
                              en: 'e.g. borescope lvl 2, full penetration OK'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 8 + MediaQuery.viewPaddingOf(context).bottom),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: kBorder)),
                ),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: kArc,
                    foregroundColor: kOnArc,
                  ),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving
                      ? context.tr(pl: 'Zapisywanie...', en: 'Saving...')
                      : context.tr(pl: 'Zapisz', en: 'Save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ten swatches, 48 dp each, plus "none".
  Widget _tintPicker(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    final picked = kHeatTintLevels.where((l) => l.level == _tint).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _tintChip(
              key: const ValueKey('heat-tint-none'),
              selected: _tint == null,
              color: kBg,
              label: '—',
              onTap: () => setState(() => _tint = null),
            ),
            for (final l in kHeatTintLevels)
              _tintChip(
                key: ValueKey('heat-tint-${l.level}'),
                selected: _tint == l.level,
                color: l.swatch,
                label: '${l.level}',
                onTap: () => setState(() => _tint = l.level),
              ),
          ],
        ),
        if (picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${picked.level} — ${en ? picked.nameEn : picked.namePl} '
              '(${picked.approxO2} O₂)',
              style: TextStyle(
                  fontSize: 12, color: _verdictColor(picked.verdict)),
            ),
          ),
      ],
    );
  }

  Widget _tintChip({
    required Key key,
    required bool selected,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) =>
      Semantics(
        key: key,
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: kMinTapTarget,
            height: kMinTapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? kArc : kBorder, width: selected ? 3 : 1),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color.computeLuminance() > 0.35
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
        ),
      );
}
