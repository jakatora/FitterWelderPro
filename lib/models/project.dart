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
  });

  static Project fromRow(Map<String, Object?> r) {
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
    );
  }
}
