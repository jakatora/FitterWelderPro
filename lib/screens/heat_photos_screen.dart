import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../database/heat_photo_dao.dart';
import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import '../models/heat_photo.dart';
import '../widgets/help_button.dart';
import '../models/library_component.dart';
import '../models/project.dart';

class HeatPhotosScreen extends StatefulWidget {
  final String projectId;
  const HeatPhotosScreen({super.key, required this.projectId});

  @override
  State<HeatPhotosScreen> createState() => _HeatPhotosScreenState();
}

class _HeatPhotosScreenState extends State<HeatPhotosScreen> {
  final _projectDao = ProjectDao();
  final _libDao = ComponentLibraryDao();
  final _dao = HeatPhotoDao();

  Project? _project;
  List<HeatPhoto> _items = [];
  List<LibraryComponent> _library = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _projectDao.getById(widget.projectId);
    List<LibraryComponent> lib = [];
    if (p != null) {
      lib = await _libDao.listFor(
        materialGroup: p.materialGroup,
        currentDiameter: p.diameterMm,
        wallThickness: p.wallThicknessMm,
      );
    }
    final rows = await _dao.listForProject(widget.projectId);
    setState(() {
      _project = p;
      _library = lib;
      _items = rows;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _add() async {
    final p = _project;
    if (p == null) return;

    LibraryComponent? selected;
    final noteCtrl = TextEditingController();

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Dodaj HEAT number (opcjonalnie)', en: 'Add HEAT number (optional)')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<LibraryComponent>(
              initialValue: selected,
              decoration: InputDecoration(labelText: context.tr(pl: 'Komponent (opcjonalnie)', en: 'Component (optional)')),
              items: _library
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.displayLabel(), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => selected = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(labelText: context.tr(pl: 'Notatka (opcjonalnie)', en: 'Note (optional)')),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr(pl: 'Zapisz', en: 'Save'))),
        ],
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _dao.insert({
      'id': const Uuid().v4(),
      'project_id': p.id,
      'library_component_id': selected?.id,
      'image_path': path,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'created_at': now,
    });

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Heat numbers', en: 'Heat numbers')),
        actions: [HelpButton(help: kHelpHeatPhotos)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.add_a_photo),
        label: Text(context.tr(pl: 'Dodaj zdjęcie', en: 'Add photo')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : _items.isEmpty
                  ? Center(child: Text(context.tr(pl: 'Brak zdjęć. Dodaj pierwsze.', en: 'No photos yet. Add the first one.')))
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (ctx, i) {
                        final it = _items[i];
                        final file = File(it.imagePath);
                        return Card(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (it.note != null) Text(it.note!, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (it.note != null) const SizedBox(height: 8),
                                SizedBox(
                                  height: 220,
                                  width: double.infinity,
                                  child: file.existsSync()
                                      ? Image.file(file, fit: BoxFit.cover)
                                      : Center(child: Text(context.tr(pl: 'Plik nie istnieje', en: 'File does not exist'))),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
