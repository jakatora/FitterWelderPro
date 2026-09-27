import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as ph;
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../database/heat_photo_dao.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/heat_photo.dart';
import '../services/heat_photo_capture.dart';
import '../services/heat_photo_storage.dart';
import '../widgets/heat_photo_source_buttons.dart';
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
    final p = await _projectDao.getById(widget.projectId);
    final lib = <String, LibraryComponent>{};
    if (p != null) {
      // Every size the project runs through, not just the one it started on:
      // fittings behind a reducer used to be impossible to pick.
      final sizes = <String, (double, double)>{
        '${p.diameterMm}|${p.wallThicknessMm}': (p.diameterMm, p.wallThicknessMm),
        for (final s in await SegmentDao().listForProject(p.id))
          '${s.diameterMm}|${s.wallThicknessMm}': (s.diameterMm, s.wallThicknessMm),
      };
      for (final (d, w) in sizes.values) {
        for (final c in await _libDao.listFor(
          materialGroup: p.materialGroup,
          currentDiameter: d,
          wallThickness: w,
        )) {
          lib[c.id] = c;
        }
      }
    }
    final rows = await _dao.listForProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = p;
      _library = lib.values.toList();
      _items = rows;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) => _recoverLostPhoto());
  }

  /// Android potrafi zabić aplikację, gdy aparat jest otwarty (mało pamięci).
  /// Zdjęcie wtedy nie wraca do `pickImage`, tylko czeka w `retrieveLostData`
  /// — bez tego monter zrobiłby zdjęcie etykiety i nic by się nie zapisało.
  Future<void> _recoverLostPhoto() async {
    String? lost;
    try {
      lost = await HeatPhotoPicker.instance.retrieveLost();
    } catch (e) {
      debugPrint('HeatPhotos retrieveLost: $e');
    }
    if (lost == null || !mounted) return;
    await _addFromPath(lost);
  }

  Future<void> _add() async {
    if (_project == null) return;
    // Aparat / Galeria na telefonie; na Windows / web od razu wybór pliku.
    final path = await showHeatPhotoSourceSheet(context);
    if (path == null || !mounted) return;
    await _addFromPath(path);
  }

  Future<void> _addFromPath(String path) async {
    final p = _project;
    if (p == null) return;

    LibraryComponent? selected;
    final noteCtrl = TextEditingController();
    final heatCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Dodaj HEAT number (opcjonalnie)', en: 'Add HEAT number (optional)')),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The screen is called "Heat numbers" but had no field for one:
            // the number could only go into the free-text note.
            TextField(
              key: const ValueKey('heat-photo-heat-no'),
              controller: heatCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Numer wytopu (heat)', en: 'Heat number'),
              ),
            ),
            const SizedBox(height: 12),
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

    // The picker hands back a path inside its volatile cache (camera shots
    // included); that copy is wiped on cache-clear, which would silently
    // destroy the heat/MTR traceability evidence. Copy the file into
    // <documents>/heat_photos (covered by the backup) and store THAT path.
    String persistentPath;
    try {
      persistentPath = await persistPickedHeatPhoto(path);
    } catch (e) {
      debugPrint('HeatPhotos copy failed: $e');
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
      'heat_no': heatCtrl.text.trim().isEmpty ? null : heatCtrl.text.trim(),
    });

    await Haptic.saved();
    await _load();
  }

  void _showFull(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              maxScale: 6,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
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
    // Best-effort removal of the on-disk copy — only one the app owns.
    // Rows from before photos were copied point at the user's own gallery
    // file; deleting that would destroy his photo (same rule as
    // ProjectDao.purgePhotoFiles).
    try {
      final root = ph.normalize((await heatPhotosDirectory()).path);
      final path = ph.normalize(item.imagePath);
      if (ph.isWithin(root, path)) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
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
                        final compId = it.libraryComponentId;
                        final comp = compId == null
                            ? null
                            : _library.where((c) => c.id == compId).firstOrNull;
                        return Card(
                          child: Padding(
                            // Safe-area padding belongs to the list end only
                            // (it used to add ~34 px under EVERY photo).
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (it.heatNo != null)
                                            Text('Heat: ${it.heatNo}',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                          // The picked component used to be saved and never shown.
                                          if (compId != null)
                                            Text(
                                              comp?.displayLabel() ??
                                                  context.tr(pl: 'komponent usunięty z biblioteki', en: 'component deleted from the library'),
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          if (it.note != null)
                                            Text(it.note!, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        ],
                                      ),
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
                                      // Tap: full screen with pinch-zoom, to
                                      // read the number off the label.
                                      ? GestureDetector(
                                          onTap: () => _showFull(file),
                                          child: Image.file(
                                            file,
                                            fit: BoxFit.cover,
                                            cacheWidth: 1080,
                                            gaplessPlayback: true,
                                          ),
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
