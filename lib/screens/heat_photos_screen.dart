import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../database/heat_photo_dao.dart';
import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import '../models/heat_photo.dart';
import '../widgets/help_button.dart';
import '../models/library_component.dart';
import '../models/project.dart';
import '../utils/haptic.dart';

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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Dodaj HEAT number (opcjonalnie)', en: 'Add HEAT number (optional)')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_library.isEmpty)
              // Empty library would render a tappable-but-empty dropdown —
              // confusing on shop floor. Show a clear hint instead.
              InputDecorator(
                decoration: InputDecoration(labelText: context.tr(pl: 'Komponent (opcjonalnie)', en: 'Component (optional)')),
                child: Text(
                  context.tr(pl: 'Brak pasujących komponentów w bibliotece', en: 'No matching components in library'),
                  style: const TextStyle(color: Color(0xFF9BA3C7)),
                ),
              )
            else
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr(pl: 'Zapisz', en: 'Save'))),
        ],
      ),
    );

    // 'Anuluj' (or dismiss by tapping outside) returns null/false — abort
    // without writing a record.
    if (confirmed != true) return;

    // The picker hands back a path inside its volatile cache; that copy is
    // wiped on cache-clear, which would silently destroy the heat/MTR
    // traceability evidence. Copy the file into an app-owned persistent
    // directory and store THAT path instead.
    String persistentPath;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final heatDir = Directory('${docsDir.path}/heat_photos');
      if (!await heatDir.exists()) {
        await heatDir.create(recursive: true);
      }
      final ext = picked.files.single.extension;
      final fileName =
          '${const Uuid().v4()}${ext != null && ext.isNotEmpty ? '.$ext' : '.jpg'}';
      final destPath = '${heatDir.path}${Platform.pathSeparator}$fileName';
      await File(path).copy(destPath);
      persistentPath = destPath;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się zapisać zdjęcia', en: 'Failed to save photo')),
        ),
      );
      await Haptic.error();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _dao.insert({
      'id': const Uuid().v4(),
      'project_id': p.id,
      'library_component_id': selected?.id,
      'image_path': persistentPath,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'created_at': now,
    });

    await Haptic.saved();
    await _load();
  }

  Future<void> _delete(HeatPhoto item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Usunąć zdjęcie?', en: 'Delete photo?')),
        content: Text(context.tr(
          pl: 'Tej operacji nie można cofnąć — dowód traceability zostanie usunięty.',
          en: 'This cannot be undone — the traceability evidence will be removed.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr(pl: 'Usuń', en: 'Delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await _dao.deleteById(item.id);
    // Best-effort removal of the on-disk copy we own.
    try {
      final f = File(item.imagePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    await Haptic.saved();
    if (!mounted) return;
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
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 56, color: Color(0xFF9BA3C7)),
                            const SizedBox(height: 16),
                            Text(
                              context.tr(pl: 'Brak zdjęć heat/MTR. Dodaj pierwsze.', en: 'No heat/MTR photos yet. Add the first one.'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add_a_photo),
                              label: Text(context.tr(pl: 'Dodaj zdjęcie', en: 'Add photo')),
                            ),
                          ],
                        ),
                      ),
                    )
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
                                Row(
                                  children: [
                                    Expanded(
                                      child: it.note != null
                                          ? Text(it.note!, style: const TextStyle(fontWeight: FontWeight.w600))
                                          : const SizedBox.shrink(),
                                    ),
                                    IconButton(
                                      tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(it),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 220,
                                  width: double.infinity,
                                  child: file.existsSync()
                                      // `cacheWidth` decodes the bitmap at
                                      // ~display resolution instead of the
                                      // raw camera 4000-px width, dropping
                                      // ~40× memory + decode cost per
                                      // scroll. `gaplessPlayback` keeps the
                                      // previous frame while the new one
                                      // decodes (no white flash).
                                      ? Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                          cacheWidth: 1080,
                                          gaplessPlayback: true,
                                        )
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
