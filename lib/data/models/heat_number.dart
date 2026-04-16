class HeatNumber {
  final int? id;
  final int projectId;
  final String heatNumber;
  final String? material;
  final String? note;
  final DateTime createdAt;

  const HeatNumber({
    this.id,
    required this.projectId,
    required this.heatNumber,
    this.material,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'heat_number': heatNumber,
      'material': material,
      'note': note,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  static HeatNumber fromMap(Map<String, Object?> map) {
    return HeatNumber(
      id: map['id'] as int?,
      projectId: map['project_id'] as int,
      heatNumber: (map['heat_number'] as String?) ?? '',
      material: map['material'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
