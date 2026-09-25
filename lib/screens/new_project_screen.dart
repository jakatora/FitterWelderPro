import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import 'fitter_screen.dart';
import '../widgets/number_field.dart';
import '../widgets/project_identity_fields.dart';

class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _dao = ProjectDao();
  final _name = TextEditingController();
  final _diameter = TextEditingController();
  final _wall = TextEditingController();
  final _stock = TextEditingController(text: '6000');
  final _kerf = TextEditingController(text: '1');
  final _gap = TextEditingController(text: '0');
  // Line / ISO + revision / client / class (schema v22), all optional.
  final _identity = ProjectIdentityControllers();
  String _materialGroup = 'SS';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _diameter.dispose();
    _wall.dispose();
    _stock.dispose();
    _kerf.dispose();
    _gap.dispose();
    _identity.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _error = null;
      _saving = true;
    });

    bool didPop = false;

    final d = parseDecimal(_diameter.text);
    final w = parseDecimal(_wall.text);
    final stock = parseDecimal(_stock.text);
    final kerf = parseDecimal(_kerf.text);
    final gap = parseDecimal(_gap.text);

    if (d == null || d <= 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj poprawną średnicę', en: 'Enter a valid diameter');
        _saving = false;
      });
      return;
    }
    if (w == null || w <= 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj poprawną grubość ścianki', en: 'Enter a valid wall thickness');
        _saving = false;
      });
      return;
    }

    if (stock == null || stock <= 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj poprawną długość sztangi', en: 'Enter a valid stock length');
        _saving = false;
      });
      return;
    }

    if (kerf == null || kerf < 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj poprawny kerf', en: 'Enter a valid kerf');
        _saving = false;
      });
      return;
    }

    if (gap == null || gap < 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj poprawny gap', en: 'Enter a valid gap');
        _saving = false;
      });
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final identity = _identity.value;
    final p = Project(
      id: const Uuid().v4(),
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      materialGroup: _materialGroup,
      diameterMm: d,
      wallThicknessMm: w,
      currentDiameterMm: d,
      stockLengthMm: stock,
      sawKerfMm: kerf,
      gapMm: gap,
      createdAt: now,
      updatedAt: now,
      lineNo: identity.lineNo,
      isoNo: identity.isoNo,
      isoRev: identity.isoRev,
      client: identity.client,
      spec: identity.spec,
    );

    try {
      await _dao.insert(p);
      if (!mounted) return;
      didPop = true;
      // Straight into the new project: the next thing a fitter does with a
      // fresh project is add its first segment, and dropping him back on the
      // list only made him find and open it again. The form is REPLACED, so
      // "back" from the project lands on the list; `result: true` still
      // tells the list a project was created, so it reloads underneath.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => FitterScreen(projectId: p.id)),
        result: true,
      );
    } catch (e) {
      // Don't expose the raw exception to a user filling in a project form —
      // map to a category they can act on; keep $e in the debug log for
      // support. Most common causes: duplicate name (DB UNIQUE) and disk-full.
      debugPrint('NewProjectScreen.save error: $e');
      final raw = e.toString().toLowerCase();
      String msg;
      if (raw.contains('unique') || raw.contains('duplicate')) {
        msg = context.tr(
          pl: 'Projekt o tej nazwie już istnieje. Wybierz inną nazwę.',
          en: 'A project with this name already exists. Pick a different name.',
        );
      } else if (raw.contains('disk') || raw.contains('no space')) {
        msg = context.tr(
          pl: 'Brak miejsca w pamięci telefonu.',
          en: 'No storage space left on the device.',
        );
      } else {
        msg = context.tr(
          pl: 'Nie udało się zapisać projektu. Spróbuj jeszcze raz.',
          en: 'Could not save the project. Please try again.',
        );
      }
      if (!mounted) return;
      setState(() {
        _error = msg;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    } finally {
      // If we didn't pop (e.g. validation or exception), re-enable the button.
      if (mounted && !didPop) setState(() => _saving = false);
    }
  }

  void _showKerfGapInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Kerf i gap — wzory', en: 'Kerf and gap — formulas')),
        content: SingleChildScrollView(
          child: Text(
            context.tr(
              pl: 'Kerf — szerokość rzazu (strata materiału na jedno cięcie '
                  'piły / plazmy), w mm.\n'
                  'Gap — luz montażowy między czołami rur pod spoinę '
                  '(np. root gap TIG), w mm.\n\n'
                  'Cięcie listy z jednej sztangi długości L:\n'
                  '  użyteczne = L − n·kerf\n'
                  '     gdzie n = liczba cięć w sztandze\n\n'
                  'Długość rury w segmencie (między dwoma elementami):\n'
                  '  L_rury = L_C-C − takeout_1 − takeout_2 − 2·gap\n'
                  '     gdzie takeout = wymiar kolanka/redukcji do osi\n\n'
                  'Typowe wartości:\n'
                  '  kerf piły taśmowej: 1,0–1,6 mm\n'
                  '  kerf plazmy CNC: 2,0–3,5 mm\n'
                  '  gap TIG (root): 1,5–3,0 mm',
              en: 'Kerf — saw / plasma cut width (material lost per cut), '
                  'in mm.\n'
                  'Gap — fit-up gap between pipe faces for the weld '
                  '(e.g. TIG root gap), in mm.\n\n'
                  'Cut list from one stock bar of length L:\n'
                  '  usable = L − n·kerf\n'
                  '     where n = number of cuts in the bar\n\n'
                  'Pipe length within a segment (between two fittings):\n'
                  '  L_pipe = L_C-C − takeout_1 − takeout_2 − 2·gap\n'
                  '     where takeout = elbow/reducer centre-to-face\n\n'
                  'Typical values:\n'
                  '  band-saw kerf: 1.0–1.6 mm\n'
                  '  CNC plasma kerf: 2.0–3.5 mm\n'
                  '  TIG root gap: 1.5–3.0 mm',
            ),
            style: const TextStyle(height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr(pl: 'OK', en: 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(pl: 'Nowy projekt', en: 'New project'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr(pl: 'Nazwa (opcjonalnie)', en: 'Name (optional)')),
              ),
              const SizedBox(height: 12),
              // Identification from the drawing — what QC and the foreman
              // find the job by; printed on the cut list and the BOM.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr(
                    pl: 'Identyfikacja z rysunku (opcjonalnie)',
                    en: 'Drawing identification (optional)',
                  ),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              ProjectIdentityFields(
                controllers: _identity,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _materialGroup,
                decoration: InputDecoration(labelText: context.tr(pl: 'Materiał', en: 'Material')),
                items: const [
                  DropdownMenuItem(value: 'SS', child: Text('SS')),
                  DropdownMenuItem(value: 'CS', child: Text('CS')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _materialGroup = v ?? 'SS'),
              ),
              const SizedBox(height: 12),
              // Every field below is parsed with parseDecimal(text) — i.e.
              // the code expects a decimal separator — but they used to ask
              // for the plain TextInputType.number keypad, which on iOS has
              // neither '.' nor ','. Ø76.2 could only be typed as 762 and the
              // project (and every cut in it) was then built on a bogus
              // diameter. The shared keyboard/filter from number_field.dart
              // keeps both separators and blocks anything else, so the parser
              // cannot be handed a value it will reject.
              TextField(
                controller: _diameter,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(labelText: context.tr(pl: 'Średnica rury (mm)', en: 'Pipe diameter (mm)')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wall,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(labelText: context.tr(pl: 'Grubość ścianki (mm)', en: 'Wall thickness (mm)')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stock,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Długość sztangi (mm)', en: 'Stock length (mm)'),
                  helperText: context.tr(pl: 'Domyślnie 6000', en: 'Default 6000'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kerf,
                // Its own helper text says "Np. 1,0" — the field must be able
                // to produce that.
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Kerf (mm na cięcie)', en: 'Kerf (mm per cut)'),
                  helperText: context.tr(pl: 'Np. 1,0', en: 'For example 1.0'),
                  // Kerf/gap drive the BOM math but workers rarely see the
                  // formula spelled out — a one-tap dialog beats memorising it.
                  suffixIcon: IconButton(
                    tooltip: context.tr(pl: 'Co to jest kerf i gap?', en: 'What are kerf and gap?'),
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => _showKerfGapInfo(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gap,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Gap (mm na spoinę)', en: 'Gap (mm per weld)'),
                  helperText: context.tr(pl: 'Domyślnie 0', en: 'Default 0'),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Color(0xFFEF5350))),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                // Glove-friendly: 56dp height ensures the primary CTA clears the
                // 48dp minimum hit target even with a thick work glove on.
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _create,
                  child: Text(_saving ? context.tr(pl: 'Zapisywanie...', en: 'Saving...') : context.tr(pl: 'Utwórz projekt', en: 'Create project')),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Ustawienia istniejącego projektu ─────────────────────────────────────

String _fmtNumber(double v) {
  var t = v.toStringAsFixed(3);
  t = t.replaceFirst(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t;
}

/// Opens the settings of an existing [project] — name, line / ISO +
/// revision / client / class, stock length, kerf and gap — and saves them
/// through [ProjectDao.updateSettings].
///
/// Returns what the save did, or null when the fitter backed out. A gap that
/// leaves some segment with nothing to cut is refused inside the dialog and
/// nothing is changed.
Future<ProjectSettingsUpdate?> showProjectSettingsDialog(
  BuildContext context,
  Project project, {
  ProjectDao? dao,
}) {
  return showDialog<ProjectSettingsUpdate>(
    context: context,
    builder: (_) => _ProjectSettingsDialog(
      project: project,
      dao: dao ?? ProjectDao(),
    ),
  );
}

/// One line for a SnackBar after [showProjectSettingsDialog] saved.
String projectSettingsSavedMessage(
  BuildContext context,
  ProjectSettingsUpdate result,
) {
  if (result.recomputed == 0) {
    return context.tr(
      pl: 'Zapisano ustawienia projektu.',
      en: 'Project settings saved.',
    );
  }
  final base = context.tr(
    pl: 'Zapisano. Gap zmieniony — przeliczono CUT ${result.recomputed} '
        'segmentów.',
    en: 'Saved. Gap changed — CUT recomputed for ${result.recomputed} '
        'segments.',
  );
  if (result.changedBeyondGap.isEmpty) return base;
  final list = result.changedBeyondGap.join(', ');
  return '$base ${context.tr(
    pl: 'Sprawdź segmenty: $list — ich CUT zmienił się o więcej niż różnica '
        'gapu (były zapisane starą regułą).',
    en: 'Check segments: $list — their CUT moved by more than the gap '
        'difference (they were saved under an old rule).',
  )}';
}

class _ProjectSettingsDialog extends StatefulWidget {
  final Project project;
  final ProjectDao dao;
  const _ProjectSettingsDialog({required this.project, required this.dao});

  @override
  State<_ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<_ProjectSettingsDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.project.name ?? '');
  late final TextEditingController _stock =
      TextEditingController(text: _fmtNumber(widget.project.stockLengthMm));
  late final TextEditingController _kerf =
      TextEditingController(text: _fmtNumber(widget.project.sawKerfMm));
  late final TextEditingController _gap =
      TextEditingController(text: _fmtNumber(widget.project.gapMm));
  late final ProjectIdentityControllers _identity =
      ProjectIdentityControllers(widget.project.identity);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _stock.dispose();
    _kerf.dispose();
    _gap.dispose();
    _identity.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) =>
      parseDecimal(c.text);

  bool get _gapChanges {
    final g = _parse(_gap);
    return g != null && (g - widget.project.gapMm).abs() > 1e-9;
  }

  Future<void> _save() async {
    final stock = _parse(_stock);
    final kerf = _parse(_kerf);
    final gap = _parse(_gap);
    String? error;
    if (stock == null || !stock.isFinite || stock <= 0) {
      error = context.tr(
          pl: 'Podaj poprawną długość sztangi', en: 'Enter a valid stock length');
    } else if (kerf == null || !kerf.isFinite || kerf < 0) {
      error = context.tr(pl: 'Podaj poprawny kerf', en: 'Enter a valid kerf');
    } else if (gap == null || !gap.isFinite || gap < 0) {
      error = context.tr(pl: 'Podaj poprawny gap', en: 'Enter a valid gap');
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    final typedName = _name.text.trim();
    try {
      final result = await widget.dao.updateSettings(
        widget.project.id,
        name: typedName.isEmpty ? null : typedName,
        stockLengthMm: stock!,
        sawKerfMm: kerf!,
        gapMm: gap!,
        identity: _identity.value,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on GapMakesCutImpossible catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr(
          pl: 'Przy gapie ${_fmtNumber(e.gapMm)} mm segment ${e.seqNo} nie ma '
              'już czego ciąć (CUT ≤ 0). Nic nie zostało zmienione.',
          en: 'With a ${_fmtNumber(e.gapMm)} mm gap segment ${e.seqNo} has '
              'nothing left to cut (CUT ≤ 0). Nothing was changed.',
        );
      });
    } catch (e) {
      debugPrint('ProjectSettingsDialog.save error: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr(
          pl: 'Nie udało się zapisać ustawień. Nic nie zostało zmienione.',
          en: 'Could not save the settings. Nothing was changed.',
        );
      });
    }
  }

  Widget _mmField(TextEditingController c, String label, {String? helper}) {
    return TextField(
      controller: c,
      enabled: !_saving,
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, helperText: helper),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(pl: 'Ustawienia projektu', en: 'Project settings')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText:
                    context.tr(pl: 'Nazwa (opcjonalnie)', en: 'Name (optional)'),
              ),
            ),
            const SizedBox(height: 8),
            ProjectIdentityFields(
              controllers: _identity,
              enabled: !_saving,
              dense: true,
            ),
            const SizedBox(height: 8),
            _mmField(_stock,
                context.tr(pl: 'Długość sztangi (mm)', en: 'Stock length (mm)')),
            const SizedBox(height: 8),
            _mmField(_kerf,
                context.tr(pl: 'Kerf (mm na cięcie)', en: 'Kerf (mm per cut)')),
            const SizedBox(height: 8),
            _mmField(
              _gap,
              context.tr(pl: 'Gap (mm na spoinę)', en: 'Gap (mm per weld)'),
            ),
            if (_gapChanges) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Zmiana gapu przeliczy CUT wszystkich segmentów tego '
                      'projektu (gap × liczba spoin każdego segmentu).',
                  en: 'Changing the gap recomputes the CUT of every segment '
                      'in this project (gap × welds of each segment).',
                ),
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFC44D)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF5350))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
        ),
      ],
    );
  }
}
