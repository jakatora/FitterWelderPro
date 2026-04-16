import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';

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
  String _materialGroup = 'SS';
  String? _error;
  bool _saving = false;

  Future<void> _create() async {
    setState(() {
      _error = null;
      _saving = true;
    });

    bool didPop = false;

    final d = double.tryParse(_diameter.text.replaceAll(',', '.'));
    final w = double.tryParse(_wall.text.replaceAll(',', '.'));
    final stock = double.tryParse(_stock.text.replaceAll(',', '.'));
    final kerf = double.tryParse(_kerf.text.replaceAll(',', '.'));
    final gap = double.tryParse(_gap.text.replaceAll(',', '.'));

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
    );

    try {
      await _dao.insert(p);
      if (!mounted) return;
      didPop = true;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr(pl: 'Błąd zapisu projektu: $e', en: 'Project save error: $e');
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error!)),
      );
      return;
    } finally {
      // If we didn't pop (e.g. validation or exception), re-enable the button.
      if (mounted && !didPop) setState(() => _saving = false);
    }
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
              TextField(
                controller: _diameter,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr(pl: 'Średnica rury (mm)', en: 'Pipe diameter (mm)')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wall,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr(pl: 'Grubość ścianki (mm)', en: 'Wall thickness (mm)')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stock,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Długość sztangi (mm)', en: 'Stock length (mm)'),
                  helperText: context.tr(pl: 'Domyślnie 6000', en: 'Default 6000'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kerf,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Kerf (mm na cięcie)', en: 'Kerf (mm per cut)'),
                  helperText: context.tr(pl: 'Np. 1.0', en: 'For example 1.0'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gap,
                keyboardType: TextInputType.number,
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
