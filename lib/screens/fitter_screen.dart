import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../models/segment.dart';
import 'segment_builder_screen.dart';
import 'material_list_screen.dart';
import 'cut_list_summary_screen.dart';
import 'project_components_screen.dart';
import 'heat_photos_screen.dart';
import '../widgets/help_button.dart';

class FitterScreen extends StatefulWidget {
  final String projectId;
  const FitterScreen({super.key, required this.projectId});

  @override
  State<FitterScreen> createState() => _FitterScreenState();
}

class _FitterScreenState extends State<FitterScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  final _libDao = ComponentLibraryDao();

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

  Future<void> _addSegment() async {
    final p = _project;
    if (p == null) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentBuilderScreen(
          materialGroup: p.materialGroup,
          currentDiameter: p.currentDiameterMm,
          wallThickness: p.wallThicknessMm,
          gapMm: p.gapMm,
        ),
      ),
    );

    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = await _segmentDao.nextSeqNo(p.id);
    final segId = const Uuid().v4();

    final measured = _measuredColumns(result);
    final endLibraryId = measured['end_library_id'] as String?;
    final endValue = measured['end_value_mm'] as double;

    // Segment diameter is the current project diameter at time of creation.
    // If START is a reducer (out matches current), diameter remains current.
    final segDiameter = p.currentDiameterMm;

    await _segmentDao.insert({
      'id': segId,
      'project_id': p.id,
      'seq_no': seq,
      'diameter_mm': segDiameter,
      'wall_thickness_mm': p.wallThicknessMm,
      ...measured,
      'created_at': now,
      'updated_at': now,
    });

    // Auto-update current diameter when END is REDUCER (inlet matches current)
    // Outlet diameter can come either from the library record or from user input (endValue).
    if (endLibraryId != null) {
      final endComp = await _libDao.getById(endLibraryId);
      if (endComp != null && endComp.type == 'REDUCER') {
        final outFromLib = endComp.diameterOutMm;
        final out = (outFromLib != null && outFromLib > 0) ? outFromLib : endValue;
        if (out > 0) {
          // Only apply if reducer inlet equals current diameter (normal case)
          if ((endComp.diameterMm - p.currentDiameterMm).abs() < 0.0001) {
            await _projectDao.updateCurrentDiameter(p.id, out);
          }
        }
      }
    }

    await _load();
  }

  /// Columns that come back from SegmentBuilderScreen — everything the fitter
  /// actually measured, i.e. every column an edit is allowed to change.
  ///
  /// Shared by [_addSegment] and [_editSegment] so a corrected segment is
  /// written exactly the way a new one is; two hand-written copies of this
  /// mapping would be free to drift, and a column read differently on the
  /// edit path is a silently wrong cut length.
  Map<String, Object?> _measuredColumns(Map<String, dynamic> result) => {
        'start_kind': (result['startKind'] as String?) ?? 'logical',
        'start_library_id': result['startLibraryId'] as String?,
        'start_value_mm': (result['startValue'] as num).toDouble(),
        'end_kind': (result['endKind'] as String?) ?? 'logical',
        'end_library_id': result['endLibraryId'] as String?,
        'end_value_mm': (result['endValue'] as num).toDouble(),
        'iso_ref': (result['isoRef'] as String?) ?? 'FACE',
        'iso_expr': (result['isoExpr'] as String).trim(),
        'iso_mm': (result['isoMm'] as num).toDouble(),
        'cut_mm': (result['cutMm'] as num).toDouble(),
      };

  /// Reopens a saved segment for correction.
  ///
  /// Before this, a typo in a dimension (3450 for 3540) could only be undone
  /// by swiping the segment away — behind a "cannot be undone" dialog — and
  /// rebuilding the whole sequence from the palette. The update below keeps
  /// the row's id and seq_no, so the segment holds its place in the cut list
  /// and in the PDF; only what the fitter re-measured changes.
  Future<void> _editSegment(Segment s) async {
    final p = _project;
    if (p == null) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentBuilderScreen(
          materialGroup: p.materialGroup,
          // The segment's OWN diameter and wall, not the project's current
          // ones: the route may have passed through a reducer since this
          // segment was built, and the palette has to offer the fittings this
          // segment is actually made of.
          currentDiameter: s.diameterMm,
          wallThickness: s.wallThicknessMm,
          gapMm: p.gapMm,
          existing: s,
        ),
      ),
    );

    if (result == null) return;

    final changed = await _segmentDao.update({
      'id': s.id,
      // seq_no is passed for completeness; SegmentDao.update drops it, along
      // with id/project_id/created_at, so an edit can never renumber the
      // sheet the fitter is cutting from.
      'seq_no': s.seqNo,
      'diameter_mm': s.diameterMm,
      'wall_thickness_mm': s.wallThicknessMm,
      ..._measuredColumns(result),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Deliberately NOT re-running the REDUCER auto-diameter step from
    // _addSegment: the route diameter was already advanced when this segment
    // was first saved, so applying it a second time would shift the rest of
    // the route on every re-save of the same segment.

    if (!mounted) return;
    if (changed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Tego segmentu już nie ma — poprawki nie zostały zapisane.',
          en: 'This segment no longer exists — changes were not saved.',
        )),
      ));
    }
    await _load();
  }

  Future<String> _compLabel(String? libraryId) async {
    if (libraryId == null) return 'OPEN END/LOGICAL';
    final c = await _libDao.getById(libraryId);
    return c?.type ?? 'COMP';
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;

    return Scaffold(
      appBar: AppBar(
        // Po lewej: wstecz (standardowy przycisk AppBar). Po prawej: szybkie przyciski.
        actions: p == null
            ? null
            : [
                HelpButton(help: kHelpFitter),
                IconButton(
                  icon: const Icon(Icons.list_alt),
                  tooltip: context.tr(pl: 'Lista materiałowa', en: 'Material list'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MaterialListScreen(projectId: p.id)),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.inventory_2_outlined),
                  tooltip: context.tr(pl: 'Komponenty / Heat', en: 'Components / Heat'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectComponentsScreen(projectId: p.id)),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.photo_camera_outlined),
                  tooltip: context.tr(pl: 'Zdjęcia certyfikatów / heat', en: 'Heat / certificate photos'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => HeatPhotosScreen(projectId: p.id)),
                    );
                  },
                ),
              ],
        title: Text(p?.name?.isNotEmpty == true ? p!.name! : 'Projekt'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _project == null ? null : _addSegment,
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj segment', en: 'Add segment')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: ListTile(
                        title: Text('Ø${p.diameterMm.toStringAsFixed(1)} | t=${p.wallThicknessMm.toStringAsFixed(1)}'),
                        subtitle: Text(context.tr(pl: 'Aktualna średnica w trasie: Ø${p.currentDiameterMm.toStringAsFixed(1)}', en: 'Current route diameter: Ø${p.currentDiameterMm.toStringAsFixed(1)}')),
                      ),
                    ),
                    Expanded(
                      child: _segments.isEmpty
                          ? Center(child: Text(context.tr(pl: 'Brak segmentów. Dodaj pierwszy segment.', en: 'No segments yet. Add the first segment.')))
                          : ListView.separated(
                              itemCount: _segments.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (context, i) {
                                final s = _segments[i];
                                return Dismissible(
                                  key: ValueKey(s.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    color: const Color(0xFFE74C3C),
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
                                  ),
                                  confirmDismiss: (_) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text(context.tr(pl: 'Usuń segment', en: 'Delete segment')),
                                        // Deleting is no longer the only way
                                        // to fix a bad dimension, so say so
                                        // here — this dialog is exactly where
                                        // a fitter lands who only wanted to
                                        // correct a digit.
                                        content: Text(context.tr(
                                          pl: 'Usunąć Segment ${s.seqNo}? Tej operacji nie można cofnąć.\n\nAby tylko poprawić wymiar — anuluj i dotknij segmentu.',
                                          en: 'Delete Segment ${s.seqNo}? This cannot be undone.\n\nTo just fix a dimension — cancel and tap the segment.',
                                        )),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE74C3C), foregroundColor: Colors.white),
                                            onPressed: () => Navigator.pop(context, true),
                                            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
                                          ),
                                        ],
                                      ),
                                    ) ?? false;
                                  },
                                  onDismissed: (_) async {
                                    await _segmentDao.deleteById(s.id);
                                    await _load();
                                  },
                                  child: FutureBuilder<List<String>>(
                                    future: Future.wait([
                                      _compLabel(s.startLibraryId),
                                      _compLabel(s.endLibraryId),
                                    ]),
                                    builder: (_, snap) {
                                      final labels = snap.data;
                                      final startLbl = labels == null ? '...' : labels[0];
                                      final endLbl = labels == null ? '...' : labels[1];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: const Color(0xFFFF8E1E).withValues(alpha: 0.15),
                                          child: Text('${s.seqNo}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFF8E1E))),
                                        ),
                                        title: Text(
                                          '${context.tr(pl: 'Segment', en: 'Seg.')} ${s.seqNo}  •  Ø${s.diameterMm.toStringAsFixed(1)} × t${s.wallThicknessMm.toStringAsFixed(1)}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          '$startLbl → $endLbl\nISO: ${s.isoExpr} = ${s.isoMm.toStringAsFixed(1)} mm  |  CUT: ${s.cutMm.toStringAsFixed(1)} mm',
                                          style: const TextStyle(fontSize: 12, height: 1.4),
                                        ),
                                        isThreeLine: true,
                                        // The chevron had always been here but
                                        // led nowhere: the row was inert, so
                                        // the only way to fix a dimension was
                                        // to swipe the segment away and build
                                        // it again. A pencil says what the tap
                                        // now does.
                                        trailing: const Icon(Icons.edit_outlined, size: 18),
                                        onTap: () => _editSegment(s),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.checklist),
                          label: Text(context.tr(pl: 'Zakończ CUT LIST', en: 'Finish CUT LIST')),
                          onPressed: _segments.isEmpty
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CutListSummaryScreen(projectId: p.id),
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
