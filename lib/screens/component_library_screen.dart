import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';
import '../models/library_component.dart';
import '../widgets/help_button.dart';

class ComponentLibraryScreen extends StatefulWidget {
  const ComponentLibraryScreen({super.key});

  @override
  State<ComponentLibraryScreen> createState() => _ComponentLibraryScreenState();
}

class _ComponentLibraryScreenState extends State<ComponentLibraryScreen> {
  final _dao = ComponentLibraryDao();
  List<LibraryComponent> _items = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _dao.listAll();
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _addDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddComponentDialog(),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Biblioteka komponentów', en: 'Component library')),
        actions: [
          HelpButton(help: kHelpComponentLibrary),
          IconButton(onPressed: _addDialog, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(context.tr(pl: 'Biblioteka pusta. Kliknij + aby dodać.', en: 'The library is empty. Click + to add an item.')))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final c = _items[i];
                    return ListTile(
                      title: Text(c.displayLabel()),
                      subtitle: Text('ID: ${c.id.substring(0, 8)}'),
                    );
                  },
                ),
    );
  }
}

class _AddComponentDialog extends StatefulWidget {
  const _AddComponentDialog();

  @override
  State<_AddComponentDialog> createState() => _AddComponentDialogState();
}

class _AddComponentDialogState extends State<_AddComponentDialog> {
  final _dao = ComponentLibraryDao();

  final _diameter = TextEditingController();
  final _wall = TextEditingController();
  final _axis = TextEditingController();
  final _len = TextEditingController();
  final _diamOut = TextEditingController();

  String _type = 'ELB90';
  String _materialGroup = 'SS';
  String _mode = 'FACE';
  String? _error;
  bool _saving = false;

  bool get _isAxial => _type == 'ELB90' || _type == 'ELB45' || _type == 'TEE';
  bool get _isReducer => _type == 'REDUCER';

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saving = true;
    });

    final d = double.tryParse(_diameter.text.replaceAll(',', '.'));
    final w = double.tryParse(_wall.text.replaceAll(',', '.'));
    if (d == null || d <= 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj średnicę', en: 'Enter diameter');
        _saving = false;
      });
      return;
    }
    if (w == null || w <= 0) {
      setState(() {
        _error = context.tr(pl: 'Podaj grubość ścianki', en: 'Enter wall thickness');
        _saving = false;
      });
      return;
    }

    double? axis;
    double? len;
    double? out;

    if (_isAxial) {
      axis = double.tryParse(_axis.text.replaceAll(',', '.'));
      if (axis == null || axis <= 0) {
        setState(() {
          _error = context.tr(pl: 'Podaj wymiar do osi', en: 'Enter axis dimension');
          _saving = false;
        });
        return;
      }
    } else {
      len = double.tryParse(_len.text.replaceAll(',', '.'));
      if (_type != 'OPEN_END') {
        if (len == null || len < 0) {
          setState(() {
            _error = context.tr(pl: 'Podaj długość', en: 'Enter length');
            _saving = false;
          });
          return;
        }
      }
      if (_isReducer) {
        out = double.tryParse(_diamOut.text.replaceAll(',', '.'));
        if (out == null || out <= 0) {
          setState(() {
            _error = context.tr(pl: 'Podaj średnicę wyjściową redukcji', en: 'Enter reducer outlet diameter');
            _saving = false;
          });
          return;
        }
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final c = LibraryComponent(
      id: const Uuid().v4(),
      materialGroup: _materialGroup,
      type: _type,
      diameterMm: d,
      wallThicknessMm: w,
      axisMm: axis,
      lengthMm: len,
      measurementMode: (_isAxial || _isReducer) ? null : _mode,
      diameterOutMm: out,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _dao.insert(c);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = context.tr(pl: 'Nie udało się zapisać (możliwy duplikat): $e', en: 'Could not save (possible duplicate): $e');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(pl: 'Dodaj komponent', en: 'Add component')),
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
              onChanged: (v) => setState(() => _materialGroup = v ?? 'SS'),
              decoration: InputDecoration(labelText: context.tr(pl: 'Materiał', en: 'Material')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [
                DropdownMenuItem(value: 'ELB90', child: Text(context.tr(pl: 'ELB90 (osiowy)', en: 'ELB90 (axial)'))),
                DropdownMenuItem(value: 'ELB45', child: Text(context.tr(pl: 'ELB45 (osiowy)', en: 'ELB45 (axial)'))),
                DropdownMenuItem(value: 'TEE', child: Text(context.tr(pl: 'TEE (osiowy)', en: 'TEE (axial)'))),
                DropdownMenuItem(value: 'REDUCER', child: Text(context.tr(pl: 'REDUCER (nieosiowy)', en: 'REDUCER (non-axial)'))),
                DropdownMenuItem(value: 'VALVE', child: Text(context.tr(pl: 'VALVE (nieosiowy)', en: 'VALVE (non-axial)'))),
                DropdownMenuItem(value: 'FLANGE', child: Text(context.tr(pl: 'FLANGE (nieosiowy)', en: 'FLANGE (non-axial)'))),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'ELB90'),
              decoration: InputDecoration(labelText: context.tr(pl: 'Typ', en: 'Type')),
            ),
            TextField(
              controller: _diameter,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.tr(pl: 'Średnica (mm)', en: 'Diameter (mm)')),
            ),
            TextField(
              controller: _wall,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.tr(pl: 'Grubość ścianki (mm)', en: 'Wall thickness (mm)')),
            ),
            const SizedBox(height: 8),
            if (_isAxial)
              TextField(
                controller: _axis,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr(pl: 'Wymiar do osi A (mm)', en: 'A dimension to axis (mm)')),
              )
            else
              TextField(
                controller: _len,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr(pl: 'Długość L (mm)', en: 'Length L (mm)')),
              ),
            if (!_isAxial && !_isReducer)
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: InputDecoration(labelText: context.tr(pl: 'Tryb długości (dla ISO)', en: 'Length mode (for ISO)')),
                items: const [
                  DropdownMenuItem(value: 'FACE', child: Text('FACE')),
                  DropdownMenuItem(value: 'AXIS', child: Text('AXIS')),
                  DropdownMenuItem(value: 'END', child: Text('END')),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'FACE'),
              ),
            if (_isReducer)
              TextField(
                controller: _diamOut,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr(pl: 'Średnica wyjściowa (mm)', en: 'Outlet diameter (mm)')),
              ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFEF5350))),
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? context.tr(pl: 'Zapisywanie...', en: 'Saving...') : context.tr(pl: 'Zapisz', en: 'Save'))),
      ],
    );
  }
}
