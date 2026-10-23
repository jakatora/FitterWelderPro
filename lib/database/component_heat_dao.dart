import 'package:uuid/uuid.dart';

import '../models/component_heat.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

/// Heat numbers (material traceability) of a CUT project, pinned to a
/// segment's stable id and a place on it (schema v23). v34: they belong to
/// the owner of their project.
class ComponentHeatDao {
  ComponentHeatDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _projects = OwnedProjects(captureOwner: captureOwner);
  final OwnedProjects _projects;

  static const _owned = OwnedProjects.childOfOwnedProject;

  /// Heat number is trimmed (the field capitalises as typed, the value is
  /// not rewritten); a blank one is refused — it would prove nothing.
  static String normalizeHeatNo(String raw) => raw.trim();

  /// Adds a heat number for [side] of segment [segmentId]; returns its id.
  Future<String> add({
    required String projectId,
    required String segmentId,
    required TraceSide side,
    required String heatNo,
    String? imagePath,
    String? note,
  }) async {
    final heat = normalizeHeatNo(heatNo);
    if (heat.isEmpty) throw ArgumentError.value(heatNo, 'heatNo', 'blank');
    final id = const Uuid().v4();
    final (owner, db) = await _projects.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _projects.requireProject(txn, projectId, owner);
      await txn.insert('component_heats', {
        'id': id,
        'project_id': projectId,
        'component_key': '${segmentId}_${side.code}',
        'heat_no': heat,
        'image_path': imagePath,
        'note': _blankToNull(note),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'segment_id': segmentId,
        'side': side.code,
      });
      owner.requireCurrent();
    });
    return id;
  }

  /// Corrects the number / note of entry [id]. Returns rows changed.
  Future<int> update(String id, {required String heatNo, String? note}) async {
    final heat = normalizeHeatNo(heatNo);
    if (heat.isEmpty) throw ArgumentError.value(heatNo, 'heatNo', 'blank');
    final (owner, db) = await _projects.ownerAndDb();
    final n = await db.update(
      'component_heats',
      {'heat_no': heat, 'note': _blankToNull(note)},
      where: 'id = ? AND $_owned',
      whereArgs: [id, owner.key],
    );
    owner.requireCurrent();
    return n;
  }

  /// Puts a legacy entry that lost its place (segment deleted) on [side] of
  /// [segmentId].
  Future<int> reassign(String id,
      {required String segmentId, required TraceSide side}) async {
    final (owner, db) = await _projects.ownerAndDb();
    final n = await db.update(
      'component_heats',
      {'segment_id': segmentId, 'side': side.code},
      where: 'id = ? AND $_owned',
      whereArgs: [id, owner.key],
    );
    owner.requireCurrent();
    return n;
  }

  Future<void> deleteById(String id) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.delete('component_heats',
        where: 'id = ? AND $_owned', whereArgs: [id, owner.key]);
    owner.requireCurrent();
  }

  /// Every heat entry of the project, oldest first.
  Future<List<ComponentHeat>> listForProject(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query(
      'component_heats',
      where: 'project_id = ? AND $_owned',
      whereArgs: [projectId, owner.key],
      orderBy: 'created_at ASC, id ASC',
    );
    owner.requireCurrent();
    return rows.map(ComponentHeat.fromMap).toList();
  }

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
