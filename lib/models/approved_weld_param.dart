class ApprovedWeldParam {
  final String id;
  final String method; // TIG_WIRE / TIG_AUTOGEN
  final String baseMaterial; // SS / CS
  final double diameterMm;
  final double wallThicknessMm;
  final double electrodeMm;
  final double torchGasLpm;
  final double purgeLpm;
  final double amps;
  final String? note;
  final int createdAt;
  final int updatedAt;

  const ApprovedWeldParam({
    required this.id,
    required this.method,
    required this.baseMaterial,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.electrodeMm,
    required this.torchGasLpm,
    required this.purgeLpm,
    required this.amps,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  static ApprovedWeldParam fromRow(Map<String, Object?> r) {
    return ApprovedWeldParam(
      id: r['id'] as String,
      method: r['method'] as String,
      baseMaterial: r['base_material'] as String,
      diameterMm: (r['diameter_mm'] as num).toDouble(),
      wallThicknessMm: (r['wall_thickness_mm'] as num).toDouble(),
      electrodeMm: (r['electrode_mm'] as num).toDouble(),
      torchGasLpm: (r['torch_gas_lpm'] as num).toDouble(),
      purgeLpm: (r['purge_lpm'] as num).toDouble(),
      amps: (r['amps'] as num).toDouble(),
      note: r['note'] as String?,
      createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
