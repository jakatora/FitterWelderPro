/// Per-project settings of the weld journal: what goes into the PDF header
/// (company, client, project title, document number, revision) and the
/// target extent of volumetric examination (RT/UT %) the project
/// specification asks for.
///
/// Keyed by the trimmed, lower-case project name — the journal's grouping
/// key since the first release (few rows will ever carry a `project_id`).
/// The target is empty by default: the required percentage comes from the
/// project specification, never from the app.
///
/// Pure Dart: no Flutter, no I/O.
library;

class WeldJournalProjectSettings {
  /// [keyFor] of [projectName].
  final String projectKey;
  final String projectName;
  final String company;
  final String client;

  /// Full project title for the header (the journal's project name is often
  /// a short code).
  final String projectTitle;
  final String documentNo;
  final String revision;

  /// Target % of welds examined by RT or UT, from the project specification;
  /// null = not set.
  final double? volumetricTargetPct;

  const WeldJournalProjectSettings({
    required this.projectKey,
    required this.projectName,
    this.company = '',
    this.client = '',
    this.projectTitle = '',
    this.documentNo = '',
    this.revision = '',
    this.volumetricTargetPct,
  });

  factory WeldJournalProjectSettings.empty(String projectName) =>
      WeldJournalProjectSettings(
        projectKey: keyFor(projectName),
        projectName: projectName.trim(),
      );

  static String keyFor(String projectName) => projectName.trim().toLowerCase();

  bool get isEmpty =>
      company.trim().isEmpty &&
      client.trim().isEmpty &&
      projectTitle.trim().isEmpty &&
      documentNo.trim().isEmpty &&
      revision.trim().isEmpty &&
      volumetricTargetPct == null;

  Map<String, Object?> toRow() => {
        'project_key': projectKey,
        'project_name': projectName,
        'company': company,
        'client': client,
        'project_title': projectTitle,
        'document_no': documentNo,
        'revision': revision,
        'rt_target_pct': volumetricTargetPct,
      };

  static WeldJournalProjectSettings fromRow(Map<String, Object?> r) {
    String s(String k) => (r[k] as String?) ?? '';
    return WeldJournalProjectSettings(
      projectKey: s('project_key'),
      projectName: s('project_name'),
      company: s('company'),
      client: s('client'),
      projectTitle: s('project_title'),
      documentNo: s('document_no'),
      revision: s('revision'),
      volumetricTargetPct: (r['rt_target_pct'] as num?)?.toDouble(),
    );
  }

  static const Object _keep = Object();

  WeldJournalProjectSettings copyWith({
    String? company,
    String? client,
    String? projectTitle,
    String? documentNo,
    String? revision,
    Object? volumetricTargetPct = _keep,
  }) =>
      WeldJournalProjectSettings(
        projectKey: projectKey,
        projectName: projectName,
        company: company ?? this.company,
        client: client ?? this.client,
        projectTitle: projectTitle ?? this.projectTitle,
        documentNo: documentNo ?? this.documentNo,
        revision: revision ?? this.revision,
        volumetricTargetPct: identical(volumetricTargetPct, _keep)
            ? this.volumetricTargetPct
            : (volumetricTargetPct as num?)?.toDouble(),
      );
}

/// Parses a target percentage typed by the user ("10", "5,5", "100 %").
/// Returns null for empty input and for anything outside 0–100 — an
/// impossible target must not be stored as if it were a requirement.
double? parseTargetPct(String raw) {
  final s = raw.replaceAll('%', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v < 0 || v > 100) return null;
  return v;
}
