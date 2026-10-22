/// The two windows the ISO notebook opens for its CUT-project features:
///
///   * [showSketchGapDialog] — the sketch's root gap per weld;
///   * [showSketchProjectDialog] — confirm the project header before a CUT
///     project is created from the sketch, with the segments that will be
///     created and the pipes that will not (and why).
///
/// Kept out of `iso_notebook_screen.dart` (already ~9 000 lines); everything
/// here works on the domain types of `lib/domain/iso_notebook/`.
library;

import 'package:flutter/material.dart';

import '../data/pipe_schedules.dart';
import '../domain/iso_notebook/sketch_to_project.dart';
import '../domain/iso_notebook/sketch_settings.dart';
export '../domain/iso_notebook/sketch_settings.dart' show kSketchMaxGapMm;
import '../i18n/app_language.dart';
import '../widgets/number_field.dart';

String _fmt(double v) {
  final r = v.roundToDouble();
  return (v - r).abs() < 1e-9 ? r.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Asks for the sketch's root gap per weld. Returns the new value (mm), or
/// null when cancelled.
Future<double?> showSketchGapDialog(
  BuildContext context, {
  required double current,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _GapDialog(current: current),
  );
}

class _GapDialog extends StatefulWidget {
  final double current;
  const _GapDialog({required this.current});

  @override
  State<_GapDialog> createState() => _GapDialogState();
}

class _GapDialogState extends State<_GapDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _fmt(widget.current));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final text = _ctrl.text.trim();
    final v = text.isEmpty ? 0.0 : parseDecimal(text);
    if (v == null || !isValidSketchGapMm(v)) {
      setState(() => _error = context.tr(
            pl: 'Podaj liczbę od 0 do ${_fmt(kSketchMaxGapMm)} mm',
            en: 'Enter a number from 0 to ${_fmt(kSketchMaxGapMm)} mm',
          ));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.tr(pl: 'Szczelina spoiny', en: 'Weld root gap')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('sketch-gap-field'),
                controller: _ctrl,
                autofocus: true,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Szczelina na spoinę', en: 'Gap per weld'),
                  suffixText: 'mm',
                  errorText: _error,
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(
                  pl: 'Zapisywana w tym szkicu (domyślnie 0). CUT każdej rury '
                      'jest krótszy o szczelinę × liczbę spawanych końców — '
                      'ta sama reguła co w kreatorze segmentu. Koniec z '
                      'kształtką (kolano, trójnik, kołnierz, zawór, redukcja, '
                      'zaślepka) to spoina; wolny koniec rury — bez '
                      'szczeliny. Projekt utworzony ze szkicu dostaje tę '
                      'szczelinę.',
                  en: 'Stored with this sketch (0 by default). Each pipe\'s '
                      'CUT gets shorter by gap × number of welded ends — the '
                      'same rule as the segment builder. An end with a '
                      'fitting (elbow, tee, flange, valve, reducer, cap) is a '
                      'weld; a free pipe end has no gap. A project created '
                      'from the sketch gets this gap.',
                ),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        ElevatedButton(
          key: const ValueKey('sketch-gap-save'),
          onPressed: _save,
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Create project
// ─────────────────────────────────────────────────────────────────────────

/// Shows what [plan] will create and asks for the project header. Returns
/// the confirmed settings, or null when cancelled.
Future<SketchProjectSettings?> showSketchProjectDialog(
  BuildContext context, {
  required SketchProjectPlan plan,
  required String sketchName,
}) {
  return showDialog<SketchProjectSettings>(
    context: context,
    builder: (_) => _ProjectDialog(plan: plan, sketchName: sketchName),
  );
}

class _ProjectDialog extends StatefulWidget {
  final SketchProjectPlan plan;
  final String sketchName;
  const _ProjectDialog({required this.plan, required this.sketchName});

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  static const double _defaultStockMm = 6000;
  static const double _defaultKerfMm = 1;

  late final TextEditingController _name;
  final TextEditingController _od = TextEditingController();
  final TextEditingController _wall = TextEditingController();
  final TextEditingController _stock =
      TextEditingController(text: _fmt(_defaultStockMm));
  final TextEditingController _kerf =
      TextEditingController(text: _fmt(_defaultKerfMm));
  int? _dn;
  String _schedule = '40';
  String _material = 'SS';
  String? _error;

  PipeRow? _row(int? dn) {
    if (dn == null) return null;
    for (final r in kPipeWalls) {
      if (r.dn == dn) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final trimmed = widget.sketchName.trim();
    _name = TextEditingController(
        text: trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed);
    _setDn(widget.plan.suggestedDn);
  }

  /// DN picked: OD and wall follow the pipe table (the fitter confirms).
  void _setDn(int? dn) {
    final row = _row(dn);
    _dn = row?.dn;
    if (row == null) return;
    _od.text = _fmt2(row.od);
    _fillWall(row);
  }

  void _fillWall(PipeRow row) {
    final w = row.walls[_schedule];
    _wall.text = w == null ? '' : _fmt2(w);
  }

  static String _fmt2(double v) {
    var t = v.toStringAsFixed(2);
    t = t.replaceFirst(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    return t;
  }

  @override
  void dispose() {
    _name.dispose();
    _od.dispose();
    _wall.dispose();
    _stock.dispose();
    _kerf.dispose();
    super.dispose();
  }

  void _create() {
    String t(String pl, String en) => context.tr(pl: pl, en: en);
    final od = parseDecimal(_od.text);
    final wall = parseDecimal(_wall.text);
    final stock = parseDecimal(_stock.text);
    final kerf = parseDecimal(_kerf.text);
    String? err;
    if (od == null || od <= 0) {
      err = t('Podaj średnicę zewnętrzną (OD).', 'Enter the outside diameter (OD).');
    } else if (wall == null || wall <= 0 || wall * 2 >= od) {
      err = t('Podaj grubość ścianki (mniejszą niż połowa OD).',
          'Enter the wall thickness (less than half the OD).');
    } else if (stock == null || stock <= 0) {
      err = t('Podaj długość sztangi.', 'Enter the stock length.');
    } else if (kerf == null || kerf < 0 || kerf >= stock) {
      err = t('Podaj szerokość rzazu (0 lub więcej).',
          'Enter the saw kerf (0 or more).');
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final typed = _name.text.trim();
    Navigator.pop(
      context,
      SketchProjectSettings(
        name: typed.isEmpty ? t('Szkic ISO', 'ISO sketch') : typed,
        materialGroup: _material,
        dn: _dn,
        schedule: _dn == null ? null : _schedule,
        diameterMm: od!,
        wallThicknessMm: wall!,
        stockLengthMm: stock!,
        sawKerfMm: kerf!,
      ),
    );
  }

  Widget _numberField(TextEditingController c, String label, String key,
      {String suffix = 'mm'}) {
    return TextField(
      key: ValueKey(key),
      controller: c,
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pl = context.language == AppLanguage.pl;
    String t(String p, String e) => pl ? p : e;
    final plan = widget.plan;
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final header = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
      letterSpacing: 0.6,
    );

    return AlertDialog(
      title: Text(t('Utwórz projekt CUT ze szkicu',
          'Create a CUT project from the sketch')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('sketch-project-name'),
                controller: _name,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: t('Nazwa projektu / nr linii',
                      'Project name / line no.'),
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      key: const ValueKey('sketch-project-dn'),
                      initialValue: _dn,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'DN', isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('—')),
                        for (final r in kPipeWalls)
                          DropdownMenuItem<int?>(
                            value: r.dn,
                            child: Text('DN${r.dn} (${r.nps}")'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _setDn(v)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('sketch-project-schedule'),
                      initialValue: _schedule,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Schedule', isDense: true),
                      items: [
                        for (final s in kSchedules)
                          DropdownMenuItem<String>(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setState(() {
                        if (v == null) return;
                        _schedule = v;
                        final row = _row(_dn);
                        if (row != null) _fillWall(row);
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _numberField(
                          _od, t('Średnica OD', 'OD'), 'sketch-project-od')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _numberField(_wall, t('Ścianka', 'Wall'),
                          'sketch-project-wall')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _numberField(_stock, t('Sztanga', 'Stock length'),
                          'sketch-project-stock')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _numberField(_kerf, t('Rzaz piły', 'Saw kerf'),
                          'sketch-project-kerf')),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'SS', label: Text(t('Nierdzewna SS', 'Stainless SS'))),
                  ButtonSegment(
                      value: 'CS', label: Text(t('Węglowa CS', 'Carbon CS'))),
                ],
                selected: {_material},
                onSelectionChanged: (s) => setState(() => _material = s.first),
              ),
              const SizedBox(height: 10),
              Text(
                t('Szczelina spoiny: ${_fmt(plan.gapMm)} mm — ze szkicu, ta '
                    'sama co w CUT zeszytu (zmienisz ją w menu Szkice).',
                    'Weld gap: ${_fmt(plan.gapMm)} mm — from the sketch, the '
                    'same as in the notebook CUT (change it in the Sketches '
                    'menu).'),
                style: small,
              ),
              const SizedBox(height: 12),
              Text(
                t('SEGMENTY W KOLEJNOŚCI TRASY (${plan.segments.length})',
                    'SEGMENTS IN ROUTE ORDER (${plan.segments.length})'),
                style: header,
              ),
              const SizedBox(height: 4),
              if (plan.segments.isEmpty)
                Text(
                  t('Żadna rura nie ma kompletu danych — nie ma czego '
                      'utworzyć.',
                      'No pipe has complete data — there is nothing to '
                      'create.'),
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              for (final s in plan.segments) ...[
                Text(
                  'S${s.seqNo.toString().padLeft(2, '0')} ← ${s.label}'
                  '${s.dn != null ? ' · DN${s.dn}' : ''}'
                  ' · ISO ${s.isoExpr} · CUT ${s.cutMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(fontSize: 13),
                ),
                for (final n in s.notes)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text('• ${n.text(polish: pl)}', style: small),
                  ),
              ],
              if (plan.skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  t('DO UZUPEŁNIENIA — NIE TRAFIĄ DO PROJEKTU '
                      '(${plan.skipped.length})',
                      'TO COMPLETE — NOT IN THE PROJECT '
                      '(${plan.skipped.length})'),
                  style: header.copyWith(color: cs.error),
                ),
                const SizedBox(height: 4),
                for (final s in plan.skipped)
                  Text('${s.label} — ${s.reason.text(polish: pl)}',
                      style: TextStyle(fontSize: 12, color: cs.error)),
              ],
              if (plan.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final n in plan.notes)
                  Text('• ${n.text(polish: pl)}', style: small),
              ],
              const SizedBox(height: 12),
              Text(
                t('R… to numer rury na szkicu (jak w zestawieniu zeszytu). '
                    'Projekt numeruje segmenty S01, S02… w kolejności trasy — '
                    'powyżej masz, który segment to która rura.',
                    'R… is the pipe number on the sketch (as in the notebook '
                    'summary). The project numbers segments S01, S02… in '
                    'route order — the list above says which segment is '
                    'which pipe.'),
                style: small,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Anuluj', 'Cancel')),
        ),
        ElevatedButton(
          key: const ValueKey('sketch-project-create'),
          onPressed: plan.canCreate ? _create : null,
          child: Text(t('Utwórz projekt', 'Create project')),
        ),
      ],
    );
  }
}
