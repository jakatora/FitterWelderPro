class Segment {
  final String id;
  final String projectId;
  final int seqNo;
  final double diameterMm;
  final double wallThicknessMm;
  final String startKind;
  final String? startLibraryId;
  final double startValueMm;
  final String endKind;
  final String? endLibraryId;
  final double endValueMm;
  final String isoRef; // FACE / AXIS / END
  final String isoExpr;
  final double isoMm;
  final double cutMm;
  final int createdAt;
  final int updatedAt;

  /// v22: piece mark as the drawing numbers it (`SP02-03`); null when the
  /// fitter gave none. Blank is stored as null.
  final String? label;

  /// v22: spool this piece belongs to, as printed (`SP02`).
  final String? spoolId;

  Segment({
    required this.id,
    required this.projectId,
    required this.seqNo,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.startKind,
    required this.startLibraryId,
    required this.startValueMm,
    required this.endKind,
    required this.endLibraryId,
    required this.endValueMm,
    required this.isoRef,
    required this.isoExpr,
    required this.isoMm,
    required this.cutMm,
    required this.createdAt,
    required this.updatedAt,
    String? label,
    String? spoolId,
  })  : label = _clean(label),
        spoolId = _clean(spoolId);

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static Segment fromRow(Map<String, Object?> r) {
    return Segment(
      id: r['id'] as String,
      projectId: r['project_id'] as String,
      seqNo: (r['seq_no'] as num).toInt(),
      diameterMm: (r['diameter_mm'] as num).toDouble(),
      wallThicknessMm: (r['wall_thickness_mm'] as num).toDouble(),
      startKind: r['start_kind'] as String,
      startLibraryId: r['start_library_id'] as String?,
      startValueMm: (r['start_value_mm'] as num).toDouble(),
      endKind: r['end_kind'] as String,
      endLibraryId: r['end_library_id'] as String?,
      endValueMm: (r['end_value_mm'] as num).toDouble(),
      isoRef: (r['iso_ref'] as String?) ?? 'FACE',
      isoExpr: r['iso_expr'] as String,
      isoMm: (r['iso_mm'] as num).toDouble(),
      cutMm: (r['cut_mm'] as num).toDouble(),
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
      label: r['label'] as String?,
      spoolId: r['spool_id'] as String?,
    );
  }
}
