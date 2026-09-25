/// How a job is identified on paper: the line, the isometric and its
/// revision, the client and the piping class. The fitter reads them off the
/// drawing, the QC inspector checks them against the weld map, the foreman
/// finds the job by them. Every field is optional — a project made before
/// schema v22, or on a scrap of paper, simply has none.
class ProjectIdentity {
  /// Line number, e.g. `DN100-CWS-1234`.
  final String? lineNo;

  /// Isometric / drawing number.
  final String? isoNo;

  /// Revision of [isoNo].
  final String? isoRev;

  final String? client;

  /// Piping class (spec), e.g. `A1B`.
  final String? spec;

  const ProjectIdentity({
    this.lineNo,
    this.isoNo,
    this.isoRev,
    this.client,
    this.spec,
  });

  static const ProjectIdentity empty = ProjectIdentity();

  /// Trims every field and turns blanks into null — what a form hands over.
  factory ProjectIdentity.clean({
    String? lineNo,
    String? isoNo,
    String? isoRev,
    String? client,
    String? spec,
  }) =>
      ProjectIdentity(
        lineNo: _clean(lineNo),
        isoNo: _clean(isoNo),
        isoRev: _clean(isoRev),
        client: _clean(client),
        spec: _clean(spec),
      );

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory ProjectIdentity.fromRow(Map<String, Object?> r) =>
      ProjectIdentity.clean(
        lineNo: r['line_no'] as String?,
        isoNo: r['iso_no'] as String?,
        isoRev: r['iso_rev'] as String?,
        client: r['client'] as String?,
        spec: r['spec'] as String?,
      );

  /// The `projects` columns (schema v22).
  Map<String, Object?> toRow() => {
        'line_no': lineNo,
        'iso_no': isoNo,
        'iso_rev': isoRev,
        'client': client,
        'spec': spec,
      };

  bool get isEmpty =>
      lineNo == null &&
      isoNo == null &&
      isoRev == null &&
      client == null &&
      spec == null;

  bool get isNotEmpty => !isEmpty;

  /// `ISO-7 rew. B` — the drawing with its revision; null without a drawing.
  String? isoWithRev({required bool english}) {
    final iso = isoNo;
    if (iso == null) return null;
    final rev = isoRev;
    if (rev == null) return iso;
    return '$iso ${english ? 'rev.' : 'rew.'} $rev';
  }

  /// One line for a header: `Linia: L-100 · ISO: ISO-7 rew. B · Klient: X ·
  /// Klasa: A1`. Only what is filled in; empty string when nothing is.
  String summary({required bool english}) {
    final parts = <String>[
      if (lineNo != null) '${english ? 'Line' : 'Linia'}: $lineNo',
      if (isoNo != null) 'ISO: ${isoWithRev(english: english)}',
      if (isoNo == null && isoRev != null)
        '${english ? 'Rev.' : 'Rew.'}: $isoRev',
      if (client != null) '${english ? 'Client' : 'Klient'}: $client',
      if (spec != null) '${english ? 'Class' : 'Klasa'}: $spec',
    ];
    return parts.join(' · ');
  }

  /// Line and drawing only — the short form under a project name in a list.
  String shortSummary({required bool english}) {
    final parts = <String>[
      if (lineNo != null) lineNo!,
      if (isoNo != null) isoWithRev(english: english)!,
    ];
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectIdentity &&
      other.lineNo == lineNo &&
      other.isoNo == isoNo &&
      other.isoRev == isoRev &&
      other.client == client &&
      other.spec == spec;

  @override
  int get hashCode => Object.hash(lineNo, isoNo, isoRev, client, spec);

  @override
  String toString() => 'ProjectIdentity(line: $lineNo, iso: $isoNo, '
      'rev: $isoRev, client: $client, spec: $spec)';
}

class Project {
  final String id;
  final String? name;

  /// Material group affects component library filtering.
  /// - SS: stainless steel
  /// - CS: carbon steel
  final String materialGroup;

  final double diameterMm;
  final double wallThicknessMm;

  /// Current diameter in the route (auto-updated after reducer).
  final double currentDiameterMm;

  /// Stock length for optimization (mm). Default 6000.
  final double stockLengthMm;

  /// Saw kerf in mm, applied per cut during bar nesting.
  final double sawKerfMm;

  /// Optional welding gap per weld (mm). Applied to segment calculations.
  final double gapMm;

  final int createdAt;
  final int updatedAt;

  // ── v22: identification (all optional) ─────────────────────────────────
  final String? lineNo;
  final String? isoNo;
  final String? isoRev;
  final String? client;
  final String? spec;

  Project({
    required this.id,
    required this.name,
    required this.materialGroup,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.currentDiameterMm,
    required this.stockLengthMm,
    required this.sawKerfMm,
    required this.gapMm,
    required this.createdAt,
    required this.updatedAt,
    this.lineNo,
    this.isoNo,
    this.isoRev,
    this.client,
    this.spec,
  });

  /// Line / ISO / revision / client / class of this project.
  ProjectIdentity get identity => ProjectIdentity.clean(
        lineNo: lineNo,
        isoNo: isoNo,
        isoRev: isoRev,
        client: client,
        spec: spec,
      );

  static Project fromRow(Map<String, Object?> r) {
    final identity = ProjectIdentity.fromRow(r);
    return Project(
      id: r['id'] as String,
      name: r['name'] as String?,
      materialGroup: (r['material_group'] as String?) ?? 'SS',
      diameterMm: (r['diameter_mm'] as num).toDouble(),
      wallThicknessMm: (r['wall_thickness_mm'] as num).toDouble(),
      currentDiameterMm: (r['current_diameter_mm'] as num).toDouble(),
      stockLengthMm: ((r['stock_length_mm'] as num?) ?? 6000).toDouble(),
      sawKerfMm: ((r['saw_kerf_mm'] as num?) ?? 1).toDouble(),
      gapMm: ((r['gap_mm'] as num?) ?? 0).toDouble(),
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
      lineNo: identity.lineNo,
      isoNo: identity.isoNo,
      isoRev: identity.isoRev,
      client: identity.client,
      spec: identity.spec,
    );
  }
}

/// Whether [p] matches the project-list search [query]: every word of the
/// query has to occur (case-insensitively) in the name, line, ISO number,
/// client or class. An empty query matches everything.
bool projectMatchesQuery(Project p, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final haystack = [
    p.name,
    p.lineNo,
    p.isoNo,
    p.isoRev,
    p.client,
    p.spec,
  ].whereType<String>().join(' ').toLowerCase();
  return words.every(haystack.contains);
}
