/// NDT summary of the weld journal: how much has been examined volumetrically
/// (RT/UT), per project, per line and per welder; repair rate per welder;
/// and the ASME B31.3 §341.3.4 progressive-examination counter.
///
/// No required percentage is hard-coded: the extent of examination comes
/// from the project specification (B31.3 §341.4 gives 5 % random for Normal
/// Fluid Service, but a client spec, EN 13480-5 Table 8.4-1 or a category M
/// line say otherwise). A target is only compared when the user entered one
/// for the project in the journal settings.
///
/// §341.3.4 is shown as a counter, never acted upon: for each weld rejected
/// in a random/spot sample, two additional welds of the same welder must be
/// examined with the same method. The counter is "2 × rejects − additional
/// samples already marked"; which welds to take is the inspector's call, so
/// nothing is selected automatically.
///
/// The counter is kept PER METHOD (§341.3.4(a): the additional samples are
/// examined "by the same method" as the rejected one — an extra RT does not
/// answer a PT reject). A NOK with no scope recorded is NOT counted as a
/// random reject: an empty scope means "unknown", not "spot sample" — it is
/// reported separately ([WeldGroupStats.rejectsNoScope]) for the inspector
/// to classify.
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'weld_entry.dart';
import 'weld_ndt.dart';

class WeldGroupStats {
  /// Project, "project · line" or welder stamp.
  final String key;
  final int welds;
  final int rtExamined;
  final int utExamined;

  /// Welds with an RT or a UT result (a weld with both counts once).
  final int volumetricExamined;

  /// Welds with at least one repair, and the total number of repairs.
  final int repairedWelds;
  final int repairs;

  /// NOK results from random/spot examination (scope other than
  /// "required"), including rejects recorded before a repair.
  final int rejects;

  /// Examinations marked as additional (§341.3.4) samples.
  final int progressiveSelected;

  /// NOK results with no scope recorded — not counted for §341.3.4.
  final int rejectsNoScope;

  /// Random/spot rejects and additional samples per method.
  final Map<NdtMethod, int> rejectsByMethod;
  final Map<NdtMethod, int> progressiveByMethod;

  /// Target % of volumetric examination from the project settings, if any.
  final double? targetPct;

  const WeldGroupStats({
    required this.key,
    required this.welds,
    required this.rtExamined,
    required this.utExamined,
    required this.volumetricExamined,
    required this.repairedWelds,
    required this.repairs,
    required this.rejects,
    required this.progressiveSelected,
    this.rejectsNoScope = 0,
    this.rejectsByMethod = const {},
    this.progressiveByMethod = const {},
    this.targetPct,
  });

  double get volumetricPct => welds == 0 ? 0 : volumetricExamined * 100 / welds;
  double get repairRatePct => welds == 0 ? 0 : repairedWelds * 100 / welds;

  /// Two additional examinations per reject.
  int get progressiveRequired => rejects * 2;

  /// Additional examinations still to be done by [m].
  int toExamineBy(NdtMethod m) {
    final left =
        (rejectsByMethod[m] ?? 0) * 2 - (progressiveByMethod[m] ?? 0);
    return left < 0 ? 0 : left;
  }

  /// Additional examinations still to be done ("do dobadania"), summed per
  /// method — an extra sample of another method does not count.
  int get toExamine {
    if (rejectsByMethod.isEmpty && progressiveByMethod.isEmpty) {
      final left = progressiveRequired - progressiveSelected;
      return left < 0 ? 0 : left;
    }
    return NdtMethod.values.fold(0, (sum, m) => sum + toExamineBy(m));
  }

  bool get belowTarget =>
      targetPct != null && welds > 0 && volumetricPct + 1e-9 < targetPct!;
}

class WeldJournalStats {
  final WeldGroupStats total;
  final List<WeldGroupStats> byProject;
  final List<WeldGroupStats> byLine;
  final List<WeldGroupStats> byWelder;

  const WeldJournalStats({
    required this.total,
    required this.byProject,
    required this.byLine,
    required this.byWelder,
  });
}

class _Acc {
  final String key;
  final double? target;
  int welds = 0,
      rt = 0,
      ut = 0,
      vol = 0,
      repairedWelds = 0,
      repairs = 0,
      rejects = 0,
      progressive = 0,
      noScope = 0;
  final Map<NdtMethod, int> rejByM = {};
  final Map<NdtMethod, int> progByM = {};
  _Acc(this.key, [this.target]);

  void add(WeldEntry e) {
    welds++;
    final rtDone = e.ndtOf(NdtMethod.rt).hasResult;
    final utDone = e.ndtOf(NdtMethod.ut).hasResult;
    if (rtDone) rt++;
    if (utDone) ut++;
    if (rtDone || utDone) vol++;
    if (e.repairs.isNotEmpty) repairedWelds++;
    repairs += e.repairs.length;
    void count(NdtMethod m, WeldNdt n) {
      if (!n.isRejected) return;
      if (n.scope.isEmpty) {
        noScope++;
      } else if (n.scope != NdtScope.required) {
        rejects++;
        rejByM[m] = (rejByM[m] ?? 0) + 1;
      }
    }

    for (final x in e.ndt.entries) {
      count(x.key, x.value);
      if (x.value.scope == NdtScope.progressive) {
        progressive++;
        progByM[x.key] = (progByM[x.key] ?? 0) + 1;
      }
    }
    for (final r in e.repairs) {
      for (final x in r.prevNdt.entries) {
        count(x.key, x.value);
      }
    }
  }

  WeldGroupStats build() => WeldGroupStats(
        key: key,
        welds: welds,
        rtExamined: rt,
        utExamined: ut,
        volumetricExamined: vol,
        repairedWelds: repairedWelds,
        repairs: repairs,
        rejects: rejects,
        progressiveSelected: progressive,
        rejectsNoScope: noScope,
        rejectsByMethod: Map.unmodifiable(rejByM),
        progressiveByMethod: Map.unmodifiable(progByM),
        targetPct: target,
      );
}

// Rejects that trigger §341.3.4: NOK in a random, spot or progressive sample
// — now, or in the state saved by a repair. A NOK under 100 % ("required")
// examination is repaired, not sampled further; a NOK with no scope is
// unknown and counted apart (see the library doc).

/// Groups by a trimmed, case-insensitive key; keeps the first-seen casing
/// and the first-seen order.
class _Groups {
  final Map<String, _Acc> _byKey = {};
  final double? Function(String key)? target;
  _Groups([this.target]);

  void add(String label, WeldEntry e) {
    final shown = label.trim().isEmpty ? '—' : label.trim();
    final k = shown.toLowerCase();
    _byKey.putIfAbsent(k, () => _Acc(shown, target?.call(k))).add(e);
  }

  List<WeldGroupStats> build() => [for (final a in _byKey.values) a.build()];
}

/// Line of a weld for grouping: the line field, else the ISO number.
String weldLineKey(WeldEntry e) {
  final line = e.pipeName.trim();
  if (line.isNotEmpty) return line;
  return e.isoDrawing.trim();
}

/// Computes the summary over the live (not deleted) entries of [entries].
///
/// [volumetricTargets] maps a project key (trimmed, lower-case project
/// name) to the target % of RT/UT examination from the project settings.
WeldJournalStats computeWeldJournalStats(
  Iterable<WeldEntry> entries, {
  Map<String, double?> volumetricTargets = const {},
}) {
  final live = entries.where((e) => !e.isDeleted).toList();
  final total = _Acc('');
  final byProject = _Groups((k) => volumetricTargets[k]);
  final byLine = _Groups();
  final byWelder = _Groups();
  final lineTargets = <String, double?>{};

  for (final e in live) {
    total.add(e);
    final project = e.projectName.trim().isEmpty ? '—' : e.projectName.trim();
    byProject.add(project, e);
    final line = weldLineKey(e);
    final lineLabel = '$project · ${line.isEmpty ? '—' : line}';
    lineTargets[lineLabel.toLowerCase()] =
        volumetricTargets[e.projectName.trim().toLowerCase()];
    byLine.add(lineLabel, e);
    final stamps = e.stamps;
    if (stamps.isEmpty) {
      byWelder.add('—', e);
    } else {
      for (final s in stamps) {
        byWelder.add(s, e);
      }
    }
  }

  // Lines inherit their project's target.
  final lines = byLine.build().map((g) {
    final t = lineTargets[g.key.toLowerCase()];
    return t == null
        ? g
        : WeldGroupStats(
            key: g.key,
            welds: g.welds,
            rtExamined: g.rtExamined,
            utExamined: g.utExamined,
            volumetricExamined: g.volumetricExamined,
            repairedWelds: g.repairedWelds,
            repairs: g.repairs,
            rejects: g.rejects,
            progressiveSelected: g.progressiveSelected,
            rejectsNoScope: g.rejectsNoScope,
            rejectsByMethod: g.rejectsByMethod,
            progressiveByMethod: g.progressiveByMethod,
            targetPct: t,
          );
  }).toList();

  return WeldJournalStats(
    total: total.build(),
    byProject: byProject.build(),
    byLine: lines,
    byWelder: byWelder.build(),
  );
}
