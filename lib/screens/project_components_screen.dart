import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/component_heat_dao.dart';
import '../database/component_library_dao.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/library_component.dart';
import '../models/project.dart';
import '../models/segment.dart';
import '../services/heat_photo_storage.dart';
import '../widgets/component_icon.dart';
import '../widgets/heat_photo_source_buttons.dart';
import '../widgets/help_button.dart';

class ProjectComponentsScreen extends StatefulWidget {
  final String projectId;
  const ProjectComponentsScreen({super.key, required this.projectId});

  @override
  State<ProjectComponentsScreen> createState() => _ProjectComponentsScreenState();
}

class _ProjectComponentsScreenState extends State<ProjectComponentsScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  final _libDao = ComponentLibraryDao();
  final _heatDao = ComponentHeatDao();

  Project? _project;
  List<Segment> _segments = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _projectDao.getById(widget.projectId);
    final segs = await _segmentDao.listForProject(widget.projectId);
    setState(() {
      _project = p;
      _segments = segs;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<_ComponentInstance> _buildComponentInstances() {
    final out = <_ComponentInstance>[];
    if (_segments.isEmpty) return out;

    // Start component from the first segment
    final first = _segments.first;
    out.add(
      _ComponentInstance(
        componentKey: 'S${first.seqNo.toString().padLeft(3, '0')}_START',
        libraryId: first.startLibraryId,
        kind: first.startKind,
        diameterMm: first.diameterMm,
        wallThicknessMm: first.wallThicknessMm,
      ),
    );

    // End component for each segment
    for (final s in _segments) {
      out.add(
        _ComponentInstance(
          componentKey: 'S${s.seqNo.toString().padLeft(3, '0')}_END',
          libraryId: s.endLibraryId,
          kind: s.endKind,
          diameterMm: s.diameterMm,
          wallThicknessMm: s.wallThicknessMm,
        ),
      );
    }

    return out;
  }

  Future<LibraryComponent?> _getLib(String? id) async {
    if (id == null) return null;
    return _libDao.getById(id);
  }

  Future<void> _addHeat(_ComponentInstance inst) async {
    final p = _project;
    if (p == null) return;

    final heatCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? imgPath;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
      title: Text(context.tr(pl: 'Dodaj HEAT (opcjonalnie zdjęcie)', en: 'Add HEAT (optional photo)')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: heatCtrl,
              decoration: InputDecoration(labelText: context.tr(pl: 'Heat number', en: 'Heat number')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(labelText: context.tr(pl: 'Notatka (opcjonalnie)', en: 'Note (optional)')),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(imgPath == null
                  ? context.tr(pl: 'Zdjęcie etykiety / atestu (opcjonalnie)', en: 'Label / certificate photo (optional)')
                  : context.tr(pl: 'Zmień zdjęcie', en: 'Change photo')),
            ),
            const SizedBox(height: 8),
            // Aparat / Galeria na telefonie, wybór pliku na desktopie.
            // Zdjęcie z aparatu jest już zmniejszone (heat_photo_capture.dart).
            HeatPhotoSourceButtons(
              onPicked: (path) => setStateDialog(() => imgPath = path),
            ),
            if (imgPath != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr(pl: 'Wybrane: ${File(imgPath!).path.split(Platform.pathSeparator).last}', en: 'Selected: ${File(imgPath!).path.split(Platform.pathSeparator).last}'), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr(pl: 'Zapisz', en: 'Save'))),
        ],
      ),
      ),
    );

    if (ok != true) return;
    final heatNo = heatCtrl.text.trim();
    if (heatNo.isEmpty) return;

    // The picker's path points into its own cache (or the gallery): cleared
    // with the cache and never part of a backup. Store a copy the app owns
    // in <documents>/heat_photos instead — copied only now, after "Zapisz",
    // so a cancelled dialog leaves no stray file behind.
    final pickedPath = imgPath;
    String? storedPath = pickedPath;
    var photoKeptAsLink = false;
    if (pickedPath != null) {
      try {
        storedPath = await persistPickedHeatPhoto(pickedPath);
      } catch (e) {
        // The heat number is the record; do not throw it away over a photo.
        // Keep the original path (the backup still picks that file up while
        // it exists) and say so.
        debugPrint('ProjectComponents photo copy failed: $e');
        photoKeptAsLink = true;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _heatDao.insert({
      'id': const Uuid().v4(),
      'project_id': p.id,
      'component_key': inst.componentKey,
      'heat_no': heatNo,
      'image_path': storedPath,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'created_at': now,
    });

    if (!mounted) return;
    setState(() {});
    if (photoKeptAsLink) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Zapisano heat, ale zdjęcia nie udało się skopiować do aplikacji '
              '— zapamiętano tylko odnośnik do oryginału.',
          en: 'Heat saved, but the photo could not be copied into the app '
              '— only a link to the original was kept.',
        )),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final comps = _buildComponentInstances();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Komponenty / Heat', en: 'Components / Heat')),
        actions: [HelpButton(help: kHelpProjectComponents)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
          ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : comps.isEmpty
            ? Center(child: Text(context.tr(pl: 'Brak komponentów – dodaj segmenty.', en: 'No components yet - add segments.')))
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                      itemCount: comps.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (ctx, i) {
                        final inst = comps[i];
                        return FutureBuilder<LibraryComponent?>(
                          future: _getLib(inst.libraryId),
                          builder: (_, snap) {
                            final lib = snap.data;
                            final type = lib?.type ?? (inst.libraryId == null ? 'OPEN END' : 'COMP');
                            return FutureBuilder<int>(
                              future: _heatDao.countForComponent(projectId: p.id, componentKey: inst.componentKey),
                              builder: (_, csnap) {
                                final count = csnap.data ?? 0;
                                return ListTile(
                                  leading: lib == null ? const Icon(Icons.open_in_new) : ComponentIcon(type: type),
                                  title: Text('${inst.componentKey} • $type'),
                                  subtitle: Text(context.tr(pl: 'Ø${inst.diameterMm.toStringAsFixed(1)} | t=${inst.wallThicknessMm.toStringAsFixed(1)} | Heat: $count', en: 'Ø${inst.diameterMm.toStringAsFixed(1)} | t=${inst.wallThicknessMm.toStringAsFixed(1)} | Heat: $count')),
                                  trailing: IconButton(
                                    tooltip: context.tr(pl: 'Dodaj heat', en: 'Add heat'),
                                    icon: const Icon(Icons.add),
                                    onPressed: () => _addHeat(inst),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
    );
  }
}

class _ComponentInstance {
  final String componentKey;
  final String? libraryId;
  final String kind;
  final double diameterMm;
  final double wallThicknessMm;

  _ComponentInstance({
    required this.componentKey,
    required this.libraryId,
    required this.kind,
    required this.diameterMm,
    required this.wallThicknessMm,
  });
}
