class TandemTigParam {
  final String id;
  final String materialGroup; // SS / CS
  final String position; // HORIZONTAL / VERTICAL
  final String jointType; // BUTT / GAP / BEVEL
  final double? landMm; // only for BEVEL
  final double? gapMm; // for GAP and optionally for BEVEL (e.g. faza + szczelina)
  final double wallThicknessMm;
  final double? wallThickness2Mm; // jeśli 3/4 itp.
  final double outsideAmps; // outside welder (with filler)
  final double insideAmps; // inside welder (autogenous)
  final bool approved;
  final String? note;
  final int createdAt;
  final int updatedAt;

  const TandemTigParam({
    required this.id,
    required this.materialGroup,
    required this.position,
    required this.jointType,
    required this.landMm,
    required this.gapMm,
    required this.wallThicknessMm,
    required this.wallThickness2Mm,
    required this.outsideAmps,
    required this.insideAmps,
    required this.approved,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TandemTigParam.fromMap(Map<String, Object?> m) {
    return TandemTigParam(
      id: m['id'] as String,
      materialGroup: (m['material_group'] as String?) ?? 'SS',
      position: (m['position'] as String?) ?? 'HORIZONTAL',
      jointType: (m['joint_type'] as String?) ?? 'BUTT',
      landMm: (m['land_mm'] as num?)?.toDouble(),
      gapMm: (m['gap_mm'] as num?)?.toDouble(),
      wallThicknessMm: (m['wall_thickness_mm'] as num).toDouble(),
      wallThickness2Mm: (m['wall_thickness2_mm'] as num?)?.toDouble(),
      outsideAmps: (m['outside_amps'] as num).toDouble(),
      insideAmps: (m['inside_amps'] as num).toDouble(),
      approved: ((m['approved'] as int?) ?? 0) == 1,
      note: m['note'] as String?,
      createdAt: (m['created_at'] as int?) ?? 0,
      updatedAt: (m['updated_at'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'material_group': materialGroup,
      'position': position,
      'joint_type': jointType,
      'land_mm': landMm,
      'gap_mm': gapMm,
      'wall_thickness_mm': wallThicknessMm,
      'wall_thickness2_mm': wallThickness2Mm,
      'outside_amps': outsideAmps,
      'inside_amps': insideAmps,
      'approved': approved ? 1 : 0,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
