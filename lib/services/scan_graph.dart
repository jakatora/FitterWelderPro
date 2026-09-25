/// The route of a scanned isometric as a graph: components are nodes, pipe
/// runs are edges, and bolted joints with no pipe in between (a flanged
/// valve between its two flanges) are extra edges of their own.
///
/// Until this existed the planner threaded segments into ONE chain and
/// could only warn about anything that was not a chain: a tee, an olet, a
/// valve between flanges (two "disconnected" runs). Here:
///
///   * a tee's three runs get roles — the straight-through run and the
///     branch — from the drawing (`runIds` / `branchId`) or from the run
///     directions (the two opposite runs are the run),
///   * an olet sitting on a header splits the header only for dimensioning:
///     the two header segments are merged back into the ONE pipe that is
///     actually cut, and only the branch ends at the olet,
///   * the walking order follows the run before the branch, and assembly
///     links keep a valve between flanges in one continuous route.
///
/// Pure Dart, no Flutter.
library;

import 'iso_scanner_ai.dart';
import 'scan_geometry.dart';

/// Role of one pipe run at a tee or an olet.
enum PortRole { run, branch }

String normaliseScanType(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const Set<String> _oletTypes = {
  'olet', 'weldolet', 'sockolet', 'thredolet', 'threadolet', 'elbolet',
  'latrolet', 'nipolet', 'sweepolet', 'insert',
};

bool isOletComponent(AiComponent? c) =>
    c != null && _oletTypes.contains(normaliseScanType(c.type));

bool isTeeComponent(AiComponent? c) {
  if (c == null) return false;
  final t = normaliseScanType(c.type);
  return t == 'tee' || t == 'reducingtee' || t == 'redtee' || t == 'cross';
}

/// The run as a vector: its projections when printed, else its direction
/// (unit length). Null when the drawing gave neither.
Vec3? segmentVector(AiSegment s) =>
    projectionVector(s.projections) ?? directionVector(s.direction);

/// Unit vector of [s] pointing AWAY from [node], or null.
Vec3? outwardAt(AiSegment s, String node) {
  final v = segmentVector(s)?.unit;
  if (v == null) return null;
  if (s.fromId == node) return v;
  if (s.toId == node) return -v;
  return null;
}

/// Roles of the runs meeting at a tee / olet [c], or null when the drawing
/// does not say and the directions do not tell.
Map<String, PortRole>? portRoles(AiComponent c, List<AiSegment> incident) {
  final ids = [for (final s in incident) s.id];
  if (ids.isEmpty) return null;

  // 1. What the drawing says.
  if (c.runIds.isNotEmpty || c.branchId != null) {
    final roles = <String, PortRole>{};
    for (final id in ids) {
      if (c.runIds.contains(id)) {
        roles[id] = PortRole.run;
      } else if (id == c.branchId) {
        roles[id] = PortRole.branch;
      }
    }
    final unassigned = ids.where((id) => !roles.containsKey(id)).toList();
    final runs = roles.values.where((r) => r == PortRole.run).length;
    final branches = roles.values.where((r) => r == PortRole.branch).length;
    if (unassigned.length == 1) {
      if (runs == 2 && branches == 0) {
        roles[unassigned.single] = PortRole.branch;
      } else if (branches == 1 && runs <= 1) {
        roles[unassigned.single] = PortRole.run;
      }
    } else if (unassigned.length == 2 && branches == 1 && runs == 0) {
      for (final id in unassigned) {
        roles[id] = PortRole.run;
      }
    }
    final okRuns = roles.values.where((r) => r == PortRole.run).length <= 2;
    final okBranch =
        roles.values.where((r) => r == PortRole.branch).length <= 1;
    if (roles.length == ids.length && okRuns && okBranch) return roles;
  }

  // 2. The directions: the two runs pointing opposite ways are the run.
  final out = <String, Vec3>{};
  for (final s in incident) {
    final v = outwardAt(s, c.id);
    if (v == null) return null;
    out[s.id] = v;
  }
  final pairs = <(String, String)>[];
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      if (out[ids[i]]!.dot(out[ids[j]]!) < -0.995) pairs.add((ids[i], ids[j]));
    }
  }
  if (pairs.length != 1) return null;
  final (a, b) = pairs.single;
  return {
    for (final id in ids)
      id: (id == a || id == b) ? PortRole.run : PortRole.branch,
  };
}

/// Result of [mergeOletHeaders].
class OletMergeResult {
  /// The segments to plan: header halves on an olet replaced by one merged
  /// segment each (id `a+b`), everything else as it was.
  final List<AiSegment> segments;

  /// Merged segment id → the two original segment ids, in walking order.
  final Map<String, List<String>> parts;

  /// Olets whose header could not be told from their branch: olet id → the
  /// segment ids meeting there.
  final Map<String, List<String>> ambiguous;

  const OletMergeResult(this.segments, this.parts, this.ambiguous);
}

/// Joins the two header segments of every olet back into one pipe.
///
/// An isometric dimensions a header to the olet's centreline, so the model
/// returns the header as two segments meeting at the olet. But nothing is
/// cut there: the header is one pipe, the olet is welded onto it. The two
/// dimensions add up to that pipe's length (`a+b`, which the segment
/// builder's parser reads back), its ends are the header's real ends.
OletMergeResult mergeOletHeaders(
  List<AiSegment> segments,
  Map<String, AiComponent> components,
) {
  var list = List<AiSegment>.of(segments);
  final parts = <String, List<String>>{};
  final ambiguous = <String, List<String>>{};

  for (final c in components.values) {
    if (!isOletComponent(c)) continue;
    final incident =
        list.where((s) => s.fromId == c.id || s.toId == c.id).toList();
    if (incident.length < 2) continue;

    List<AiSegment>? header;
    final roles = portRoles(c, incident);
    if (roles != null) {
      final runs = incident.where((s) => roles[s.id] == PortRole.run).toList();
      if (runs.length == 2) header = runs;
    } else if (incident.length == 2 && c.branchId == null) {
      // Two runs and no branch among them: only a straight pair is a header.
      final a = outwardAt(incident[0], c.id);
      final b = outwardAt(incident[1], c.id);
      if (a != null && b != null && a.dot(b) < -0.995) header = incident;
    }
    if (header == null) {
      ambiguous[c.id] = [for (final s in incident) s.id];
      continue;
    }

    final a = header[0];
    final b = header[1];
    final aFar = a.fromId == c.id ? a.toId : a.fromId;
    final bFar = b.fromId == c.id ? b.toId : b.fromId;
    // Direction of the merged pipe from aFar towards bFar: a's own direction
    // when a points at the olet, reversed otherwise.
    Object? direction;
    final av = segmentVector(a)?.unit;
    if (av != null && a.projections.isEmpty) {
      final v = a.toId == c.id ? av : -av;
      direction = {'x': v.x, 'y': v.y, 'z': v.z};
    }
    double? mm;
    if (a.dimensionMm != null && b.dimensionMm != null) {
      mm = a.dimensionMm! + b.dimensionMm!;
    }
    String text(AiSegment s) =>
        s.rawDimension ?? s.dimensionMm?.toString() ?? '?';
    final merged = AiSegment(
      id: '${a.id}+${b.id}',
      dimensionMm: mm,
      rawDimension: '${text(a)}+${text(b)}',
      fromId: aFar,
      toId: bFar,
      confidence: _worse(a.confidence, b.confidence),
      dn: a.dn ?? b.dn,
      nps: a.nps ?? b.nps,
      schedule: a.schedule ?? b.schedule,
      direction: direction,
      refFrom: a.fromId == c.id ? a.refTo : a.refFrom,
      refTo: b.fromId == c.id ? b.refTo : b.refFrom,
      spoolId: a.spoolId ?? b.spoolId,
      userConfirmed: a.userConfirmed && b.userConfirmed,
    );
    parts[merged.id] = [a.id, b.id];
    final at = list.indexOf(a);
    list = [
      for (var i = 0; i < list.length; i++)
        if (i == at)
          merged
        else if (!identical(list[i], a) && !identical(list[i], b))
          list[i],
    ];
  }
  return OletMergeResult(list, parts, ambiguous);
}

AiConfidence _worse(AiConfidence a, AiConfidence b) {
  int rank(AiConfidence c) => switch (c) {
        AiConfidence.high => 3,
        AiConfidence.medium => 2,
        AiConfidence.low => 1,
        AiConfidence.unknown => 0,
      };
  return rank(a) <= rank(b) ? a : b;
}

/// Walking order of a route graph.
class RouteOrder {
  /// Indices into the segment list, in walking order.
  final List<int> order;

  /// Connected run (0-based) each segment index belongs to.
  final Map<int, int> runOf;

  final int runCount;

  /// Component ids touched by more than two pipe segments.
  final List<String> branchNodes;

  /// node id → segment indices that end there.
  final Map<String, List<int>> incident;

  const RouteOrder(
      this.order, this.runOf, this.runCount, this.branchNodes, this.incident);
}

/// Threads the graph into a walking order: depth-first from a free end, at a
/// tee the straight-through run before the branch, across a bolted joint
/// ([assembly]: node → nodes bolted to it) as if a pipe were there.
///
/// Ids that do not resolve to a component still take part — the drawing
/// says the two runs meet there even if we cannot say what sits between.
RouteOrder orderRouteGraph(
  List<AiSegment> segments, {
  Map<String, Set<String>> assembly = const {},
  Map<String, Map<String, PortRole>> roles = const {},
}) {
  final incident = <String, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    for (final id in [segments[i].fromId, segments[i].toId]) {
      if (id == null || id.isEmpty) continue;
      (incident[id] ??= <int>[]).add(i);
    }
  }

  final branchNodes = incident.entries
      .where((e) => e.value.length > 2)
      .map((e) => e.key)
      .toList()
    ..sort();

  // Every node bolted to [id], [id] included (transitively).
  Set<String> group(String id) {
    final out = <String>{id};
    final todo = [id];
    while (todo.isNotEmpty) {
      final n = todo.removeLast();
      for (final m in assembly[n] ?? const <String>{}) {
        if (out.add(m)) todo.add(m);
      }
    }
    return out;
  }

  int degree(String id) {
    var d = 0;
    for (final n in group(id)) {
      d += incident[n]?.length ?? 0;
    }
    return d;
  }

  bool isFreeEnd(String? id) => id == null || id.isEmpty || degree(id) <= 1;
  bool hasFreeEnd(int i) =>
      isFreeEnd(segments[i].fromId) || isFreeEnd(segments[i].toId);

  final visited = List<bool>.filled(segments.length, false);
  final order = <int>[];
  final runOf = <int, int>{};
  var runs = 0;

  void visit(int index, String? entry, int run) {
    if (visited[index]) return;
    visited[index] = true;
    order.add(index);
    runOf[index] = run;
    for (final id in [segments[index].fromId, segments[index].toId]) {
      if (id == null || id.isEmpty || id == entry) continue;
      final nodes = group(id).toList();
      final next = <(int, int, String)>[]; // (priority, index, node)
      for (final n in nodes) {
        for (final j in incident[n] ?? const <int>[]) {
          if (visited[j]) continue;
          final role = roles[n]?[segments[j].id];
          final priority = n == id
              ? (role == PortRole.branch ? 2 : 0)
              : 1; // across a bolted joint after the straight run
          next.add((priority, j, n));
        }
      }
      next.sort((a, b) =>
          a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      for (final (_, j, n) in next) {
        if (!visited[j]) visit(j, n, run);
      }
    }
  }

  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < segments.length; i++) {
      if (visited[i]) continue;
      if (pass == 0 && !hasFreeEnd(i)) continue;
      visit(i, null, runs);
      runs++;
    }
  }

  return RouteOrder(order, runOf, runs, branchNodes, incident);
}

/// Symmetric bolted-joint map from every component's `connectedTo`.
Map<String, Set<String>> assemblyLinks(Iterable<AiComponent> components) {
  final out = <String, Set<String>>{};
  for (final c in components) {
    if (c.id.isEmpty) continue;
    for (final other in c.connectedTo) {
      if (other.isEmpty || other == c.id) continue;
      (out[c.id] ??= <String>{}).add(other);
      (out[other] ??= <String>{}).add(c.id);
    }
  }
  return out;
}
