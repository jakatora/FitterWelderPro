class WeldParam {
  final String id;
  final String method; // 'MAG' | 'TIG_WIRE' | 'TIG_AUTOGEN'
  final String baseMaterial; // 'SS' | 'CS'
  final String? welderModel;
  final double diameterMm;
  final double wallThicknessMm;
  final double electrodeMm; // 1.0 / 1.6 / 2.4 / 3.2 / 4.0
  final double torchGasLpm;
  final String? nozzleType;
  final String? nozzleSize;
  final double purgeLpm;
  final double amps;
  final int? outletHoles;
  final String? tempo; // SLOW | NORMAL | FAST
  final String? note;
  final int createdAt;
  final int updatedAt;

  const WeldParam({
    required this.id,
    required this.method,
    required this.baseMaterial,
    required this.welderModel,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.electrodeMm,
    required this.torchGasLpm,
    required this.nozzleType,
    required this.nozzleSize,
    required this.purgeLpm,
    required this.amps,
    required this.outletHoles,
    required this.tempo,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  static WeldParam fromRow(Map<String, Object?> r) {
    return WeldParam(
      id: (r['id'] as String),
      method: (r['method'] as String),
      baseMaterial: (r['base_material'] as String),
      welderModel: r['welder_model'] as String?,
      diameterMm: (r['diameter_mm'] as num).toDouble(),
      wallThicknessMm: (r['wall_thickness_mm'] as num).toDouble(),
      electrodeMm: (r['electrode_mm'] as num).toDouble(),
      torchGasLpm: (r['torch_gas_lpm'] as num).toDouble(),
      nozzleType: r['nozzle_type'] as String?,
      nozzleSize: r['nozzle_size'] as String?,
      purgeLpm: (r['purge_lpm'] as num).toDouble(),
      amps: (r['amps'] as num).toDouble(),
      outletHoles: r['outlet_holes'] as int?,
      tempo: r['tempo'] as String?,
      note: r['note'] as String?,
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
    );
  }
}
