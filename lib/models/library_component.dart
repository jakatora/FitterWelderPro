class LibraryComponent {
  final String id;
  final String materialGroup; // SS / CS
  final String type; // ELB90, ELB45, TEE, REDUCER, VALVE, FLANGE
  final double diameterMm; // for reducer: inlet diameter
  final double wallThicknessMm;
  final double? axisMm; // axial
  final double? lengthMm; // non axial
  final String? measurementMode; // FACE / AXIS / END (for non-axial components)
  final double? diameterOutMm; // reducer
  final int createdAt;
  final int updatedAt;

  LibraryComponent({
    required this.id,
    required this.materialGroup,
    required this.type,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.axisMm,
    required this.lengthMm,
    required this.measurementMode,
    required this.diameterOutMm,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAxial => type == 'ELB90' || type == 'ELB45' || type == 'TEE';

  /// Value used in CUT formulas.
  /// Rules:
  /// - Axial: axis_mm
  /// - Non-axial: length_mm
  /// - Reducer: 0 (ISO is to the beginning/end of reducer per our standard)
  double get calcValueMm {
    if (type == 'REDUCER') return 0;
    if (isAxial) return axisMm ?? 0;
    return lengthMm ?? 0;
  }

  /// Whether this component can be used with a given ISO reference.
  /// - Axial components always work (their takeoff is from face to axis).
  /// - Reducer is treated as boundary (offset 0).
  /// - For other components we require measurementMode to match ISO reference.
  bool supportsIsoRef(String isoRef) {
    if (type == 'REDUCER') return true;
    if (isAxial) return true;
    if (measurementMode == null) return false;
    return measurementMode == isoRef;
  }

  String displayLabel() {
    final base = '$type Ø${diameterMm.toStringAsFixed(1)} x ${wallThicknessMm.toStringAsFixed(1)}';
    if (isAxial) {
      return '$base | A=${(axisMm ?? 0).toStringAsFixed(1)}';
    }
    if (type == 'REDUCER') {
      final out = diameterOutMm == null ? '?' : diameterOutMm!.toStringAsFixed(1);
      return '$base | L=${(lengthMm ?? 0).toStringAsFixed(1)} | OUT Ø$out';
    }
    final mode = measurementMode ?? 'FACE';
    return '$base | $mode= ${(lengthMm ?? 0).toStringAsFixed(1)}';
  }

  static LibraryComponent fromRow(Map<String, Object?> r) {
    return LibraryComponent(
      id: r['id'] as String,
      materialGroup: (r['material_group'] as String?) ?? 'SS',
      type: r['type'] as String,
      diameterMm: (r['diameter_mm'] as num).toDouble(),
      wallThicknessMm: (r['wall_thickness_mm'] as num).toDouble(),
      axisMm: (r['axis_mm'] as num?)?.toDouble(),
      lengthMm: (r['length_mm'] as num?)?.toDouble(),
      measurementMode: r['measurement_mode'] as String?,
      diameterOutMm: (r['diameter_out_mm'] as num?)?.toDouble(),
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
    );
  }
}
