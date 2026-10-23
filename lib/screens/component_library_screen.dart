import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';
import '../models/library_component.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/empty_state.dart';
import '../widgets/help_button.dart';
import '../widgets/local_record_scope.dart';
import '../widgets/number_field.dart';
import '../widgets/reducer_spec_dialog.dart' show suggestedReducerLength;

/// `true` when [c] matches the search [query] (type, material or a size as
/// typed — `114,3` finds `114.3`).
bool libraryEntryMatches(LibraryComponent c, String query) {
  final q = query.trim().toLowerCase().replaceAll(',', '.');
  if (q.isEmpty) return true;
  final hay = '${c.type} ${c.materialGroup} ${c.displayLabel()}'.toLowerCase();
  return q.split(RegExp(r'\s+')).every(hay.contains);
}

/// "Rack 7 S03, Rack 7 S05, …" — where a library entry is used.
String describeLibraryUsages(List<LibraryUsage> usages, {int max = 6}) {
  final parts = [
    for (final u in usages.take(max))
      '${(u.projectName?.trim().isNotEmpty ?? false) ? u.projectName!.trim() : '—'} '
          'S${u.seqNo.toString().padLeft(2, '0')}',
  ];
  final more = usages.length - parts.length;
  return more > 0 ? '${parts.join(', ')} (+$more)' : parts.join(', ');
}

/// Biblioteka bieżącego konta; po zmianie konta lista startuje od nowa.
class ComponentLibraryScreen extends StatelessWidget {
  const ComponentLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      builder: (_, session) => _ComponentLibrary(
          dao: ComponentLibraryDao(captureOwner: session.captureOwner)));
}

class _ComponentLibrary extends StatefulWidget {
  const _ComponentLibrary({required this.dao});
  final ComponentLibraryDao dao;

  @override
  State<_ComponentLibrary> createState() => _ComponentLibraryScreenState();
}

class _ComponentLibraryScreenState extends State<_ComponentLibrary> {
  ComponentLibraryDao get _dao => widget.dao;
  final _search = TextEditingController();
  List<LibraryComponent> _items = [];
  bool _loading = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // First load only: a reload after an edit keeps the list (and its scroll
    // position) on screen instead of flashing a spinner.
    if (_items.isEmpty) setState(() => _loading = true);
    try {
      final list = await _dao.listAll();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ComponentLibrary load failed: $e');
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(
          pl: 'Nie udało się wczytać biblioteki.',
          en: 'Could not load the library.',
        ))),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openDialog({LibraryComponent? existing}) async {
    final result = await showDialog<_SaveResult>(
      context: context,
      builder: (_) => ComponentEditDialog(existing: existing),
    );
    if (result == null) return;
    await _load();
    if (!mounted || result.usages.isEmpty) return;
    // A corrected take-off does not rewrite cuts that are already saved: each
    // segment keeps what was cut from it until it is reopened. Say which ones.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(context.tr(
          pl: 'Zapisano. Wpis jest użyty w ${result.usages.length} segm.: '
              '${describeLibraryUsages(result.usages)}. Ich CUT nie zmienia się '
              'sam — otwórz każdy segment i zapisz, aby przeliczyć.',
          en: 'Saved. The entry is used in ${result.usages.length} segment(s): '
              '${describeLibraryUsages(result.usages)}. Their CUT does not change '
              'by itself — open each segment and save it to recompute.',
        )),
      ));
  }

  Future<void> _delete(LibraryComponent c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Usunąć wpis?', en: 'Delete entry?')),
        content: Text(c.displayLabel()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final blocked = await _dao.deleteIfUnused(c.id);
    if (!mounted) return;
    if (blocked.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr(
              pl: 'Wpis jest używany', en: 'The entry is in use')),
          content: Text(context.tr(
            pl: 'Użyty w ${blocked.length} segm.: '
                '${describeLibraryUsages(blocked)}.\n\nZ niego liczono ich CUT, '
                'więc nie można go usunąć. Możesz poprawić jego wymiary.',
            en: 'Used in ${blocked.length} segment(s): '
                '${describeLibraryUsages(blocked)}.\n\nTheir CUT was computed '
                'from it, so it cannot be deleted. You can correct its values.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final visible = [
      for (final c in _items)
        if (libraryEntryMatches(c, query)) c,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Biblioteka komponentów', en: 'Component library')),
        actions: [
          HelpButton(help: kHelpComponentLibrary),
          IconButton(
            tooltip: context.tr(pl: 'Dodaj komponent', en: 'Add component'),
            onPressed: () => _openDialog(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: context.tr(pl: 'Biblioteka pusta', en: 'Library is empty'),
                  subtitle: context.tr(
                    pl: 'Dodaj pierwszy komponent, by uniknąć ponownego wpisywania średnic i grubości.',
                    en: 'Add your first component so you stop re-typing diameters and wall thicknesses.',
                  ),
                  actionLabel: context.tr(pl: 'Dodaj komponent', en: 'Add component'),
                  onAction: () => _openDialog(),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        key: const ValueKey('library-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: context.tr(
                              pl: 'Szukaj: typ, materiał, średnica',
                              en: 'Search: type, material, diameter'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (context, i) {
                          final c = visible[i];
                          final label = c.displayLabel();
                          return ListTile(
                            key: ValueKey('library-${c.id}'),
                            title: Text(label),
                            subtitle: Text(
                              '${c.materialGroup} · ${context.tr(pl: 'dotknij, aby poprawić', en: 'tap to edit')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => _openDialog(existing: c),
                            onLongPress: () => copyToClipboard(context, label,
                                label: context.tr(pl: 'Komponent', en: 'Component')),
                            trailing: IconButton(
                              tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(c),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// What a save in [ComponentEditDialog] leaves behind: the segments that use
/// the saved entry (their stored CUT did not follow the change).
class _SaveResult {
  const _SaveResult(this.usages);
  final List<LibraryUsage> usages;
}

/// Add ([existing] null) or correct a library entry.
class ComponentEditDialog extends StatefulWidget {
  const ComponentEditDialog({super.key, this.existing});

  final LibraryComponent? existing;

  @override
  State<ComponentEditDialog> createState() => _ComponentEditDialogState();
}

class _ComponentEditDialogState extends State<ComponentEditDialog> {
  final _dao = ComponentLibraryDao();

  late final LibraryComponent? _e = widget.existing;
  late final _diameter = TextEditingController(text: _num(_e?.diameterMm));
  late final _wall = TextEditingController(text: _num(_e?.wallThicknessMm));
  late final _axis = TextEditingController(text: _num(_e?.axisMm));
  late final _len = TextEditingController(text: _num(_e?.lengthMm));
  late final _diamOut = TextEditingController(text: _num(_e?.diameterOutMm));

  late String _type = _e?.type ?? 'ELB90';
  late String _materialGroup = _e?.materialGroup ?? 'SS';
  String? _error;
  bool _saving = false;

  /// An entry with the same key found on save — offered for overwrite.
  LibraryComponent? _duplicate;

  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
  }

  bool get _isAxial => _type == 'ELB90' || _type == 'ELB45' || _type == 'TEE';
  bool get _isReducer => _type == 'REDUCER';

  @override
  void dispose() {
    for (final c in [_diameter, _wall, _axis, _len, _diamOut]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fail(String pl, String en) {
    setState(() {
      _error = context.tr(pl: pl, en: en);
      _saving = false;
    });
  }

  /// The entry as typed, or null (with [_error] set) when it is not valid.
  LibraryComponent? _read({required String id}) {
    final d = parseDecimal(_diameter.text);
    final w = parseDecimal(_wall.text);
    if (d == null || d <= 0) {
      _fail('Podaj średnicę', 'Enter diameter');
      return null;
    }
    if (w == null || w <= 0 || w >= d / 2) {
      _fail('Podaj grubość ścianki (mniejszą niż połowa średnicy)',
          'Enter a wall thickness (below half the diameter)');
      return null;
    }
    double? axis;
    double? len;
    double? out;
    var large = d;
    if (_isAxial) {
      axis = parseDecimal(_axis.text);
      if (axis == null || axis <= 0) {
        _fail('Podaj wymiar do osi', 'Enter axis dimension');
        return null;
      }
    } else {
      len = parseDecimal(_len.text);
      // L = 0 is exactly the reducer defect this screen exists to correct:
      // "to the far face" would subtract nothing.
      if (len == null || len <= 0) {
        _fail('Podaj długość L (większą od 0)', 'Enter length L (above 0)');
        return null;
      }
      if (_isReducer) {
        out = parseDecimal(_diamOut.text);
        if (out == null || out <= 0 || (out - d).abs() <= 0.05) {
          _fail('Podaj średnicę drugiego końca (inną niż pierwszego)',
              'Enter the other end diameter (different from the first)');
          return null;
        }
        // Stored large end → small end, whichever order was typed.
        if (out > d) {
          large = out;
          out = d;
        }
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return LibraryComponent(
      id: id,
      materialGroup: _materialGroup,
      type: _type,
      diameterMm: large,
      wallThicknessMm: w,
      axisMm: axis,
      lengthMm: len,
      measurementMode: (_isAxial || _isReducer) ? null : 'FACE',
      diameterOutMm: out,
      createdAt: _e?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _save({bool overwriteDuplicate = false}) async {
    setState(() {
      _error = null;
      _saving = true;
    });
    final dup = _duplicate;
    final target = overwriteDuplicate && dup != null ? dup.id : (_e?.id ?? const Uuid().v4());
    final c = _read(id: target);
    if (c == null) return;

    try {
      if (!overwriteDuplicate) {
        final same = await _dao.findSameKind(c);
        if (!mounted) return;
        if (same != null) {
          setState(() {
            _duplicate = same;
            _saving = false;
            _error = context.tr(
              pl: 'Taki wpis już jest: ${same.displayLabel()}.',
              en: 'Such an entry exists: ${same.displayLabel()}.',
            );
          });
          return;
        }
      }
      if (_e != null || overwriteDuplicate) {
        await _dao.update(c);
      } else {
        await _dao.insert(c);
      }
      final usages = await _dao.usages(c.id);
      if (mounted) Navigator.pop(context, _SaveResult(usages));
    } catch (e) {
      debugPrint('ComponentEditDialog save failed: $e');
      _fail('Nie udało się zapisać wpisu.', 'Could not save the entry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d1 = parseDecimal(_diameter.text);
    final d2 = parseDecimal(_diamOut.text);
    final hHint = _isReducer && d1 != null && d2 != null
        ? suggestedReducerLength(d1, d2)
        : null;
    final dup = _duplicate;
    return AlertDialog(
      title: Text(_e == null
          ? context.tr(pl: 'Dodaj komponent', en: 'Add component')
          : context.tr(pl: 'Popraw komponent', en: 'Edit component')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _materialGroup,
              items: const [
                DropdownMenuItem(value: 'SS', child: Text('SS')),
                DropdownMenuItem(value: 'CS', child: Text('CS')),
              ],
              onChanged: (v) => setState(() {
                _materialGroup = v ?? 'SS';
                _duplicate = null;
              }),
              decoration: InputDecoration(labelText: context.tr(pl: 'Materiał', en: 'Material')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [
                DropdownMenuItem(value: 'ELB90', child: Text(context.tr(pl: 'ELB90 (osiowy)', en: 'ELB90 (axial)'))),
                DropdownMenuItem(value: 'ELB45', child: Text(context.tr(pl: 'ELB45 (osiowy)', en: 'ELB45 (axial)'))),
                DropdownMenuItem(value: 'TEE', child: Text(context.tr(pl: 'TEE (osiowy)', en: 'TEE (axial)'))),
                DropdownMenuItem(value: 'REDUCER', child: Text(context.tr(pl: 'REDUCER (długość H)', en: 'REDUCER (length H)'))),
                DropdownMenuItem(value: 'VALVE', child: Text(context.tr(pl: 'VALVE (długość L)', en: 'VALVE (length L)'))),
                DropdownMenuItem(value: 'FLANGE', child: Text(context.tr(pl: 'FLANGE (długość L)', en: 'FLANGE (length L)'))),
                DropdownMenuItem(value: 'OTHER', child: Text(context.tr(pl: 'Inne (długość L)', en: 'Other (length L)'))),
              ],
              onChanged: (v) => setState(() {
                _type = v ?? 'ELB90';
                _duplicate = null;
              }),
              decoration: InputDecoration(labelText: context.tr(pl: 'Typ', en: 'Type')),
            ),
            TextField(
              key: const ValueKey('lib-diameter'),
              controller: _diameter,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              onChanged: (_) => setState(() => _duplicate = null),
              decoration: InputDecoration(
                labelText: _isReducer
                    ? context.tr(pl: 'Średnica jednego końca (mm)', en: 'Diameter of one end (mm)')
                    : context.tr(pl: 'Średnica (mm)', en: 'Diameter (mm)'),
              ),
            ),
            if (_isReducer)
              TextField(
                key: const ValueKey('lib-diameter-out'),
                controller: _diamOut,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                onChanged: (_) => setState(() => _duplicate = null),
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Średnica drugiego końca (mm)',
                      en: 'Diameter of the other end (mm)'),
                ),
              ),
            TextField(
              key: const ValueKey('lib-wall'),
              controller: _wall,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              onChanged: (_) => setState(() => _duplicate = null),
              decoration: InputDecoration(labelText: context.tr(pl: 'Grubość ścianki (mm)', en: 'Wall thickness (mm)')),
            ),
            const SizedBox(height: 8),
            if (_isAxial)
              TextField(
                key: const ValueKey('lib-axis'),
                controller: _axis,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(labelText: context.tr(pl: 'Wymiar do osi A (mm)', en: 'A dimension to axis (mm)')),
              )
            else
              TextField(
                key: const ValueKey('lib-length'),
                controller: _len,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                  labelText: _isReducer
                      ? context.tr(pl: 'Długość H czoło–czoło (mm)', en: 'Length H face to face (mm)')
                      : context.tr(pl: 'Długość L (mm)', en: 'Length L (mm)'),
                ),
              ),
            if (hHint != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(context.tr(
                      pl: 'Wstaw H = ${hHint.h.toStringAsFixed(0)} mm (ASME B16.9, DN${hHint.dn})',
                      en: 'Use H = ${hHint.h.toStringAsFixed(0)} mm (ASME B16.9, DN${hHint.dn})',
                    )),
                    onPressed: () => setState(
                        () => _len.text = hHint.h.toStringAsFixed(0)),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    key: const ValueKey('lib-error'),
                    style: const TextStyle(color: Color(0xFFEF5350))),
              ),
            // Only when ADDING: correcting entry A into a copy of entry B
            // would leave two of the same — there the fitter edits B instead.
            if (dup != null && _e == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('lib-overwrite'),
                  icon: const Icon(Icons.edit_note),
                  label: Text(context.tr(
                      pl: 'Popraw istniejący tymi wartościami',
                      en: 'Correct the existing one with these values')),
                  onPressed: _saving ? null : () => _save(overwriteDuplicate: true),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
        ElevatedButton(onPressed: _saving ? null : () => _save(), child: Text(_saving ? context.tr(pl: 'Zapisywanie...', en: 'Saving...') : context.tr(pl: 'Zapisz', en: 'Save'))),
      ],
    );
  }
}
