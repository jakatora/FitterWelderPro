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

    final startKind = (result['startKind'] as String?) ?? 'logical';
    final endKind = (result['endKind'] as String?) ?? 'logical';

    final startLibraryId = result['startLibraryId'] as String?;
    final endLibraryId = result['endLibraryId'] as String?;

    final startValue = (result['startValue'] as num).toDouble();
    final endValue = (result['endValue'] as num).toDouble();
    final isoExpr = (result['isoExpr'] as String).trim();
    final isoRef = (result['isoRef'] as String?) ?? 'FACE';
    final isoMm = (result['isoMm'] as num).toDouble();
    final cutMm = (result['cutMm'] as num).toDouble();

    // Segment diameter is the current project diameter at time of creation.
    // If START is a reducer (out matches current), diameter remains current.
    final segDiameter = p.currentDiameterMm;

    await _segmentDao.insert({
      'id': segId,
      'project_id': p.id,
      'seq_no': seq,
      'diameter_mm': segDiameter,
      'wall_thickness_mm': p.wallThicknessMm,
      'start_kind': startKind,
      'start_library_id': startLibraryId,
      'start_value_mm': startValue,
      'end_kind': endKind,
      'end_library_id': endLibraryId,
      'end_value_mm': endValue,
      'iso_ref': isoRef,
      'iso_expr': isoExpr,
      'iso_mm': isoMm,
      'cut_mm': cutMm,
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
                                        content: Text(context.tr(
                                          pl: 'Usunąć Segment ${s.seqNo}? Tej operacji nie można cofnąć.',
                                          en: 'Delete Segment ${s.seqNo}? This cannot be undone.',
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
                                          backgroundColor: const Color(0xFFF5A623).withOpacity(0.15),
                                          child: Text('${s.seqNo}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF5A623))),
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
                                        trailing: const Icon(Icons.chevron_right, size: 18),
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
