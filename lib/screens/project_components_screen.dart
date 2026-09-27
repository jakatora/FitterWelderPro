import 'dart:io';

import 'package:flutter/material.dart';

import '../database/component_heat_dao.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/component_heat.dart';
import '../models/project.dart';
import '../services/heat_photo_storage.dart';
import '../services/heat_traceability.dart';
import '../widgets/component_icon.dart';
import '../widgets/heat_photo_source_buttons.dart';
import '../widgets/help_button.dart';

/// Heat numbers (material traceability) of a CUT project, per place: the
/// fitting a segment starts on (when it is not the previous one's end), its
/// pipe, the fitting it ends on. Every number is shown, can be corrected and
/// deleted; entries whose place no longer exists are listed apart.
class ProjectComponentsScreen extends StatefulWidget {
  final String projectId;
  const ProjectComponentsScreen({super.key, required this.projectId});

  @override
  State<ProjectComponentsScreen> createState() => _ProjectComponentsScreenState();
}

class _ProjectComponentsScreenState extends State<ProjectComponentsScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  final _heatDao = ComponentHeatDao();

  Project? _project;
  HeatTrace? _trace;
  bool _loading = true;

  Future<void> _load() async {
    // Only the first load shows a spinner; a reload after an edit keeps the
    // list (and where the fitter scrolled to) on screen.
    final p = await _projectDao.getById(widget.projectId);
    final segs = await _segmentDao.listForProject(widget.projectId);
    final trace = await loadHeatTrace(widget.projectId, segs, heats: _heatDao);
    if (!mounted) return;
    setState(() {
      _project = p;
      _trace = trace;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _english => context.language == AppLanguage.en;

  Future<void> _addHeat(TracePoint point) async {
    final p = _project;
    if (p == null) return;
    final result = await showDialog<_HeatDialogResult>(
      context: context,
      builder: (_) => const _HeatEntryDialog(),
    );
    if (result == null || !mounted) return;

    // The picker's path points into its own cache (or the gallery): cleared
    // with the cache and never part of a backup. Store a copy the app owns
    // in <documents>/heat_photos instead — copied only now, after "Zapisz",
    // so a cancelled dialog leaves no stray file behind.
    final pickedPath = result.imagePath;
    String? storedPath = pickedPath;
    var photoKeptAsLink = false;
    if (pickedPath != null) {
      try {
        storedPath = await persistPickedHeatPhoto(pickedPath);
      } catch (e) {
        // The heat number is the record; do not throw it away over a photo.
        debugPrint('ProjectComponents photo copy failed: $e');
        photoKeptAsLink = true;
      }
    }

    await _heatDao.add(
      projectId: p.id,
      segmentId: point.segment.id,
      side: point.side,
      heatNo: result.heatNo,
      imagePath: storedPath,
      note: result.note,
    );
    await _load();
    if (!mounted) return;
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

  Future<void> _editHeat(ComponentHeat heat) async {
    final result = await showDialog<_HeatDialogResult>(
      context: context,
      builder: (_) => _HeatEntryDialog(existing: heat),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      await _heatDao.deleteById(heat.id);
    } else {
      await _heatDao.update(heat.id, heatNo: result.heatNo, note: result.note);
    }
    await _load();
  }

  Widget _leading(TracePoint point, HeatTrace trace) {
    if (point.side == TraceSide.pipe) {
      return const Icon(Icons.straighten);
    }
    final id = point.libraryId;
    final type = id == null ? null : trace.typeOf(id);
    if (type != null) return ComponentIcon(type: type);
    return const Icon(Icons.document_scanner_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final trace = _trace;
    final english = _english;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Numery wytopów (heat)', en: 'Heat numbers')),
        actions: [HelpButton(help: kHelpProjectComponents)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null || trace == null
              ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : trace.points.isEmpty && trace.index.isEmpty
                  ? Center(child: Text(context.tr(pl: 'Brak segmentów – dodaj segmenty.', en: 'No segments yet - add segments.')))
                  : ListView(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                      children: [
                        for (final point in trace.points)
                          _PlaceTile(
                            key: ValueKey('trace-${point.key}'),
                            leading: _leading(point, trace),
                            title: '${point.segmentsLabel} • '
                                '${tracePlaceLabel(point, english: english, typeOf: trace.typeOf)}',
                            heats: trace.index.forPoint(point),
                            onAdd: () => _addHeat(point),
                            onEdit: _editHeat,
                          ),
                        ...() {
                          final orphans = trace.index.unplaced(trace.points);
                          if (orphans.isEmpty) return const <Widget>[];
                          return [
                            const Divider(height: 24),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                context.tr(
                                  pl: 'Bez miejsca — segment usunięty lub zmieniony. '
                                      'Wpisy zostają; popraw albo usuń.',
                                  en: 'No place — segment deleted or changed. '
                                      'The entries are kept; correct or delete them.',
                                ),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final h in orphans)
                                  _HeatChip(heat: h, onTap: () => _editHeat(h)),
                              ],
                            ),
                          ];
                        }(),
                      ],
                    ),
    );
  }
}

/// One place: what it is, its heat numbers (each tappable to correct or
/// delete) and a 48 dp "add" button.
class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    super.key,
    required this.leading,
    required this.title,
    required this.heats,
    required this.onAdd,
    required this.onEdit,
  });

  final Widget leading;
  final String title;
  final List<ComponentHeat> heats;
  final VoidCallback onAdd;
  final void Function(ComponentHeat) onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 12), child: leading),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (heats.isEmpty)
                    Text(
                      context.tr(pl: 'brak numeru wytopu', en: 'no heat number'),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF9BA3C7)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final h in heats)
                          _HeatChip(heat: h, onTap: () => onEdit(h)),
                      ],
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr(pl: 'Dodaj heat', en: 'Add heat'),
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatChip extends StatelessWidget {
  const _HeatChip({required this.heat, required this.onTap});

  final ComponentHeat heat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      key: ValueKey('heat-${heat.id}'),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      avatar: Icon(
        heat.imagePath == null ? Icons.local_fire_department_outlined : Icons.photo_outlined,
        size: 18,
      ),
      label: Text(
        heat.note == null ? heat.heatNo : '${heat.heatNo} · ${heat.note}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      tooltip: context.tr(pl: 'Popraw lub usuń', en: 'Edit or delete'),
      onPressed: onTap,
    );
  }
}

class _HeatDialogResult {
  const _HeatDialogResult({
    required this.heatNo,
    required this.note,
    this.imagePath,
    this.delete = false,
  });

  final String heatNo;
  final String? note;
  final String? imagePath;
  final bool delete;
}

/// Add ([existing] null: number, note, optional photo) or correct / delete
/// one heat entry. Pops a [_HeatDialogResult] or null (cancel).
class _HeatEntryDialog extends StatefulWidget {
  const _HeatEntryDialog({this.existing});

  final ComponentHeat? existing;

  @override
  State<_HeatEntryDialog> createState() => _HeatEntryDialogState();
}

class _HeatEntryDialogState extends State<_HeatEntryDialog> {
  late final _heat = TextEditingController(text: widget.existing?.heatNo ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  String? _imgPath;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _heat.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final heat = ComponentHeatDao.normalizeHeatNo(_heat.text);
    if (heat.isEmpty) {
      // It used to close as if saved and write nothing, the photo lost too.
      setState(() => _error = context.tr(
          pl: 'Wpisz numer wytopu (heat).', en: 'Enter the heat number.'));
      return;
    }
    Navigator.pop(
      context,
      _HeatDialogResult(heatNo: heat, note: _note.text, imagePath: _imgPath),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Usunąć numer wytopu?', en: 'Delete heat number?')),
        content: Text(widget.existing!.heatNo),
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
    Navigator.pop(
      context,
      _HeatDialogResult(heatNo: widget.existing!.heatNo, note: null, delete: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingPhoto = widget.existing?.imagePath;
    return AlertDialog(
      title: Text(_editing
          ? context.tr(pl: 'Numer wytopu', en: 'Heat number')
          : context.tr(pl: 'Dodaj HEAT (opcjonalnie zdjęcie)', en: 'Add HEAT (optional photo)')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('heat-number-field'),
              controller: _heat,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Heat number', en: 'Heat number'),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: context.tr(pl: 'Notatka (opcjonalnie)', en: 'Note (optional)')),
            ),
            if (_editing && existingPhoto != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                width: double.infinity,
                child: File(existingPhoto).existsSync()
                    ? InteractiveViewer(
                        child: Image.file(File(existingPhoto),
                            fit: BoxFit.contain, cacheWidth: 1080))
                    : Center(child: Text(context.tr(pl: 'Plik nie istnieje', en: 'File does not exist'))),
              ),
            ],
            if (!_editing) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_imgPath == null
                    ? context.tr(pl: 'Zdjęcie etykiety / atestu (opcjonalnie)', en: 'Label / certificate photo (optional)')
                    : context.tr(pl: 'Zmień zdjęcie', en: 'Change photo')),
              ),
              const SizedBox(height: 8),
              // Aparat / Galeria na telefonie, wybór pliku na desktopie.
              HeatPhotoSourceButtons(
                onPicked: (path) => setState(() => _imgPath = path),
              ),
              if (_imgPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      pl: 'Wybrane: ${File(_imgPath!).path.split(Platform.pathSeparator).last}',
                      en: 'Selected: ${File(_imgPath!).path.split(Platform.pathSeparator).last}',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            onPressed: _delete,
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        ElevatedButton(onPressed: _save, child: Text(context.tr(pl: 'Zapisz', en: 'Save'))),
      ],
    );
  }
}
