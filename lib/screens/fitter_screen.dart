import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';
import '../models/library_component.dart';
import '../models/project.dart';
import '../models/segment.dart';
import '../services/piece_marks.dart';
import 'segment_builder_screen.dart';
import 'material_list_screen.dart';
import 'cut_list_summary_screen.dart';
import 'project_components_screen.dart';
import 'heat_photos_screen.dart';
import 'new_project_screen.dart' show showProjectSettingsDialog, projectSettingsSavedMessage;
import '../widgets/local_record_scope.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

/// Pipe size the route stands at after the saved segments — what the NEXT
/// segment starts on.
class RoutePosition {
  const RoutePosition({required this.diameterMm, required this.wallThicknessMm});

  final double diameterMm;

  /// Null right behind a reducer: the database stores no outlet wall (a
  /// component-library reducer has one wall, its inlet's), so it cannot be
  /// derived and must be asked for.
  final double? wallThicknessMm;
}

/// Where the route stands after [segments], derived from what is saved
/// instead of a field that is overwritten on the way.
///
/// It used to be `projects.current_diameter_mm`, bumped when a segment ended
/// on a reducer and never touched again: deleting that segment left the
/// route on the reducer's outlet, and the wall was never changed at all, so
/// the pipe behind a DN100 → DN50 reducer was built as Ø60.3 with the Ø114.3
/// wall (and offered library fittings for that non-existent size).
///
/// Rules, on the segment with the highest seq_no:
///   * none saved → the project's own diameter and wall;
///   * its END is a library REDUCER with one end on that segment's diameter →
///     the reducer's OTHER end, wall unknown (null). Both ways round: inlet
///     on the pipe is a reduction (route goes down to the outlet), outlet on
///     the pipe is an expander (route goes up to the inlet) — see
///     [reducerOtherEndMm];
///   * its END is a library component that is gone from the library → the
///     stored `current_diameter_mm` is the only witness left: if it differs
///     from the segment, a reduction happened there (wall unknown);
///   * otherwise → that segment's own diameter and wall.
///
/// [lastEndComponent] is the library record of that last segment's END, or
/// null when it has none (or it was deleted).
/// Diameter on the far side of reducer [comp] when one of its ends sits on
/// a pipe of [pipeDiameterMm], or null when neither end does (a damaged or
/// mismatched row — then nothing may be inferred from it).
///
/// The library stores a reducer as `diameter_mm` → `diameter_out_mm`, but the
/// fitting has no direction of its own: welded on by its small end it is an
/// expander. The builder offers a reducer whenever EITHER end matches the
/// pipe (`ComponentLibraryDao.listFor`), so both readings must be handled.
double? reducerOtherEndMm(LibraryComponent comp, double pipeDiameterMm) {
  // Same tolerance the library offered the reducer with — a pipe the picker
  // matched must also be recognised here.
  const eps = kLibraryMatchToleranceMm + 1e-9;
  final out = comp.diameterOutMm;
  if (out == null || out <= 0) return null;
  if ((comp.diameterMm - pipeDiameterMm).abs() <= eps) return out;
  if ((out - pipeDiameterMm).abs() <= eps) return comp.diameterMm;
  return null;
}

RoutePosition routeAfterSegments({
  required Project project,
  required List<Segment> segments,
  required LibraryComponent? lastEndComponent,
}) {
  if (segments.isEmpty) {
    return RoutePosition(
      diameterMm: project.diameterMm,
      wallThicknessMm: project.wallThicknessMm,
    );
  }
  final last = segments.reduce((a, b) => a.seqNo >= b.seqNo ? a : b);
  const eps = 1e-4;

  if (last.endLibraryId != null) {
    final comp = lastEndComponent;
    if (comp == null) {
      if ((project.currentDiameterMm - last.diameterMm).abs() > eps) {
        return RoutePosition(
          diameterMm: project.currentDiameterMm,
          wallThicknessMm: null,
        );
      }
    } else if (comp.type == 'REDUCER') {
      final other = reducerOtherEndMm(comp, last.diameterMm);
      if (other != null) {
        return RoutePosition(diameterMm: other, wallThicknessMm: null);
      }
    }
  }
  return RoutePosition(
    diameterMm: last.diameterMm,
    wallThicknessMm: last.wallThicknessMm,
  );
}

/// Projekt należy do konta, które go otworzyło: po zmianie konta ekran nie
/// pokazuje już jego segmentów, tylko prosi o ponowne otwarcie.
class FitterScreen extends StatelessWidget {
  final String projectId;
  const FitterScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      restartOnAccountChange: false,
      builder: (_, session) =>
          _FitterBody(projectId: projectId, session: session));
}

class _FitterBody extends StatefulWidget {
  const _FitterBody({required this.projectId, required this.session});
  final String projectId;
  final LocalRecordSession session;

  @override
  State<_FitterBody> createState() => _FitterScreenState();
}

class _FitterScreenState extends State<_FitterBody> {
  late final _projectDao =
      ProjectDao(captureOwner: widget.session.captureOwner);
  late final _segmentDao =
      SegmentDao(captureOwner: widget.session.captureOwner);
  final _libDao = ComponentLibraryDao();

  Project? _project;
  List<Segment> _segments = [];
  RoutePosition? _route;
  bool _loading = true;

  /// Library entries the segments use (id → entry, null = deleted), read
  /// once per load — every row used to fire two queries on every rebuild,
  /// and its labels flickered "...".
  Map<String, LibraryComponent?> _library = const {};

  Future<void> _load() async {
    if (!mounted) return;
    // Only the very first load swaps the list for a spinner. A reload after
    // an add / edit / delete keeps the list — and the fitter's place in a
    // 40-segment list — on screen.
    final p = await _projectDao.getById(widget.projectId);
    final segs = await _segmentDao.listForProject(widget.projectId);
    final library = <String, LibraryComponent?>{};
    for (final s in segs) {
      for (final id in [s.startLibraryId, s.endLibraryId]) {
        if (id != null && !library.containsKey(id)) {
          library[id] = await _libDao.getById(id);
        }
      }
    }

    RoutePosition? route;
    if (p != null) {
      LibraryComponent? lastEnd;
      if (segs.isNotEmpty) {
        final last = segs.reduce((a, b) => a.seqNo >= b.seqNo ? a : b);
        final endId = last.endLibraryId;
        if (endId != null) lastEnd = library[endId];
      }
      route = routeAfterSegments(
          project: p, segments: segs, lastEndComponent: lastEnd);
      // The stored field is kept in step for everything that still reads it
      // (backups, exports) — but it is written FROM the segments now, never
      // the other way round.
      if ((route.diameterMm - p.currentDiameterMm).abs() > 1e-4) {
        await _projectDao.updateCurrentDiameter(p.id, route.diameterMm);
      }
    }

    if (!mounted) return;
    setState(() {
      _project = p;
      _segments = segs;
      _library = library;
      _route = route;
      _loading = false;
    });
  }

  /// Swipe-delete with Undo: the row goes at once, and for 6 s the snackbar
  /// can put it back — same id (its heat numbers and saw ticks reattach)
  /// and, if still free, the same number. The project list has had Undo for
  /// a while; a segment was "cannot be undone".
  Future<void> _deleteSegment(Segment s) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = context.tr(
        pl: 'Usunięto segment ${s.seqNo}.', en: 'Segment ${s.seqNo} deleted.');
    final undo = context.tr(pl: 'COFNIJ', en: 'UNDO');
    // Out of the list right away, so the Dismissible is not rebuilt.
    setState(() => _segments = [
          for (final x in _segments)
            if (x.id != s.id) x,
        ]);
    final snapshot = await _segmentDao.deleteWithSnapshot(s.id);
    await _projectDao.touch(s.projectId);
    await _load();
    if (!mounted || snapshot == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(label),
        action: SnackBarAction(
          label: undo,
          onPressed: () async {
            await _segmentDao.restore(snapshot);
            await _projectDao.touch(s.projectId);
            await _load();
          },
        ),
      ));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Wall of the pipe right behind a reducer — stored nowhere, so asked.
  ///
  /// No prefill on purpose: the only number to prefill with would be the
  /// wall before the reducer, which is exactly the wrong value this prompt
  /// exists to stop.
  Future<double?> _askWallBehindReducer(double diameterMm) {
    return showDialog<double>(
      context: context,
      builder: (_) => _WallBehindReducerDialog(diameterMm: diameterMm),
    );
  }

  Future<void> _addSegment() async {
    final p = _project;
    final route = _route;
    if (p == null || route == null) return;

    // The new segment starts where the saved ones end (routeAfterSegments):
    // behind a reducer that is its outlet, and a wall nobody has told us yet.
    var wall = route.wallThicknessMm;
    if (wall == null) {
      wall = await _askWallBehindReducer(route.diameterMm);
      if (wall == null || !mounted) return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentBuilderScreen(
          materialGroup: p.materialGroup,
          currentDiameter: route.diameterMm,
          wallThickness: wall!,
          gapMm: p.gapMm,
          // SP02-03 → SP02-04: the next mark of the spool being numbered.
          suggestedLabel: suggestNextSegmentLabel(_segments),
        ),
      ),
    );

    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = await _segmentDao.nextSeqNo(p.id);
    final segId = const Uuid().v4();

    await _segmentDao.insert({
      'id': segId,
      'project_id': p.id,
      'seq_no': seq,
      'diameter_mm': route.diameterMm,
      'wall_thickness_mm': wall,
      ..._measuredColumns(result),
      'created_at': now,
      'updated_at': now,
    });
    await _projectDao.touch(p.id);

    // No separate "reducer moves the route" step any more: _load derives the
    // route from the segments, so a reducer END moves it, and deleting that
    // segment moves it back.
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
        // v22 piece mark; spool_id is left alone (the builder does not edit
        // it — a scanned segment keeps the spool it came with).
        'label': result['label'] as String?,
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
    if (changed > 0) await _projectDao.touch(p.id);

    // No route bookkeeping here either: _load derives it from the segments,
    // so re-saving a segment can never shift the route twice.

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

  /// Name, stock, kerf and gap — reachable from here because the gap is
  /// what the fitter notices is wrong while building segments. A changed gap
  /// recomputes every saved CUT of the project.
  Future<void> _editSettings(Project p) async {
    final result =
        await showProjectSettingsDialog(context, p, dao: _projectDao);
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(projectSettingsSavedMessage(context, result)),
        duration: const Duration(seconds: 6),
      ));
  }

  String _routeLabel(BuildContext context, RoutePosition? route) {
    if (route == null) return '';
    final d = route.diameterMm.toStringAsFixed(1);
    final w = route.wallThicknessMm;
    if (w == null) {
      return context.tr(
        pl: 'Aktualnie w trasie: Ø$d — za redukcją; ściankę podasz przy '
            'następnym segmencie',
        en: 'Current route: Ø$d — behind a reducer; you will be asked for '
            'the wall with the next segment',
      );
    }
    return context.tr(
      pl: 'Aktualnie w trasie: Ø$d × t ${w.toStringAsFixed(2)}',
      en: 'Current route: Ø$d × t ${w.toStringAsFixed(2)}',
    );
  }

  /// What sits at one end of a segment, in words. A fitting from the ISO scan
  /// or sketch has no library id but a stored kind — it is an elbow or a body
  /// fitting, not an open end (the old label called every such end
  /// "OPEN END/LOGICAL").
  String _compLabel(String? libraryId, String kind) {
    if (libraryId != null) {
      return _library[libraryId]?.type ??
          context.tr(pl: 'usunięty z biblioteki', en: 'deleted from library');
    }
    switch (kind) {
      case 'axial':
        return context.tr(pl: 'Kształtka (skan)', en: 'Fitting (scan)');
      case 'nonAxial':
        return context.tr(pl: 'Element (skan)', en: 'Component (scan)');
      default:
        return context.tr(pl: 'Koniec otwarty', en: 'Open end');
    }
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
                  icon: const Icon(Icons.tune),
                  tooltip: context.tr(pl: 'Ustawienia projektu', en: 'Project settings'),
                  onPressed: () => _editSettings(p),
                ),
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
                  tooltip: context.tr(pl: 'Numery wytopów (heat)', en: 'Heat numbers'),
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
        title: Text(p?.name?.isNotEmpty == true
            ? p!.name!
            : context.tr(pl: 'Projekt', en: 'Project')),
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
                        title: Text('Ø${p.diameterMm.toStringAsFixed(1)} | t=${p.wallThicknessMm.toStringAsFixed(1)} | gap ${p.gapMm.toStringAsFixed(1)}'),
                        subtitle: Text(_routeLabel(context, _route)),
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
                                        // Deleting is not the way to fix a
                                        // bad dimension, so say so here —
                                        // this dialog is exactly where a
                                        // fitter lands who only wanted to
                                        // correct a digit.
                                        content: Text(context.tr(
                                          pl: 'Usunąć Segment ${s.seqNo}? Przez kilka sekund możesz to cofnąć.\n\nAby tylko poprawić wymiar — anuluj i dotknij segmentu.',
                                          en: 'Delete Segment ${s.seqNo}? You can undo it for a few seconds.\n\nTo just fix a dimension — cancel and tap the segment.',
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
                                  onDismissed: (_) => _deleteSegment(s),
                                  child: Builder(
                                    builder: (_) {
                                      final startLbl = _compLabel(s.startLibraryId, s.startKind);
                                      final endLbl = _compLabel(s.endLibraryId, s.endKind);
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: const Color(0xFFFF8E1E).withValues(alpha: 0.15),
                                          child: Text('${s.seqNo}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFF8E1E))),
                                        ),
                                        title: Text(
                                          '${context.tr(pl: 'Segment', en: 'Seg.')} ${s.seqNo}${s.label == null ? '' : ' · ${s.label}'}  •  Ø${s.diameterMm.toStringAsFixed(1)} × t${s.wallThicknessMm.toStringAsFixed(1)}',
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

/// Asks for the wall of the pipe behind a reducer. A widget of its own so
/// the text controller lives exactly as long as the dialog, exit animation
/// included.
class _WallBehindReducerDialog extends StatefulWidget {
  final double diameterMm;
  const _WallBehindReducerDialog({required this.diameterMm});

  @override
  State<_WallBehindReducerDialog> createState() =>
      _WallBehindReducerDialogState();
}

class _WallBehindReducerDialogState extends State<_WallBehindReducerDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseDecimal(_c.text);
    if (v == null || !v.isFinite || v <= 0) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameterMm.toStringAsFixed(1);
    return AlertDialog(
      title: Text(context.tr(
        pl: 'Ścianka rury za redukcją (Ø$d)',
        en: 'Wall of the pipe behind the reducer (Ø$d)',
      )),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText:
              context.tr(pl: 'Grubość ścianki (mm)', en: 'Wall thickness (mm)'),
          helperText: context.tr(
            pl: 'Po redukcji zmienia się rura — podaj jej ściankę.',
            en: 'The pipe changes at the reducer — enter its wall.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
