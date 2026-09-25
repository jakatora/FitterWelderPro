/// Writes a CUT project planned from an ISO-notebook sketch
/// (`domain/iso_notebook/sketch_to_project.dart`) into the database.
///
/// The two DAOs do not share a transaction, so atomicity is enforced here the
/// way the scan review does it: the first failure deletes what was already
/// written and rethrows. A project with half its segments is worse than no
/// project — the fitter would cut from it.
library;

import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../domain/iso_notebook/sketch_to_project.dart';
import '../models/project.dart';

/// The write failed and was rolled back ([cleanedUp]) — or the cleanup failed
/// too, and a project named [projectName] may be left to delete by hand.
class SketchProjectWriteFailed implements Exception {
  final Object cause;
  final bool cleanedUp;
  final String projectName;
  const SketchProjectWriteFailed(this.cause,
      {required this.cleanedUp, required this.projectName});

  @override
  String toString() =>
      'SketchProjectWriteFailed($cause, cleanedUp: $cleanedUp)';
}

/// Creates the project and its segments; returns the new project's id.
///
/// Throws [StateError] for a plan with nothing to create and
/// [SketchProjectWriteFailed] when the database refused.
Future<String> createProjectFromSketch(
  SketchProjectPlan plan,
  SketchProjectSettings settings, {
  ProjectDao? projectDao,
  SegmentDao? segmentDao,
  int? nowMs,
}) async {
  if (!plan.canCreate) {
    throw StateError('the sketch plan has no segments to create');
  }
  final projects = projectDao ?? ProjectDao();
  final segments = segmentDao ?? SegmentDao();
  const uuid = Uuid();
  final projectId = uuid.v4();
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  var projectWritten = false;
  try {
    await projects.insert(Project(
      id: projectId,
      name: settings.name,
      materialGroup: settings.materialGroup,
      diameterMm: settings.diameterMm,
      wallThicknessMm: settings.wallThicknessMm,
      currentDiameterMm: settings.diameterMm,
      stockLengthMm: settings.stockLengthMm,
      sawKerfMm: settings.sawKerfMm,
      // The gap every CUT of the plan was computed with — the segment
      // builder and the gap recompute read it back from here.
      gapMm: plan.gapMm,
      createdAt: now,
      updatedAt: now,
    ));
    projectWritten = true;
    for (final seg in plan.segments) {
      final size = sketchSegmentSize(seg, settings);
      await segments.insert(sketchSegmentRow(
        seg,
        id: uuid.v4(),
        projectId: projectId,
        diameterMm: size.diameterMm,
        wallThicknessMm: size.wallThicknessMm,
        nowMs: now,
      ));
    }
  } catch (e) {
    var cleaned = !projectWritten;
    if (projectWritten) {
      try {
        await projects.deleteProjectCascade(projectId);
        cleaned = true;
      } catch (_) {
        cleaned = false;
      }
    }
    throw SketchProjectWriteFailed(e,
        cleanedUp: cleaned, projectName: settings.name);
  }
  return projectId;
}
