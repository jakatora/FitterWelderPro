class ComponentHeat {
  final String id;
  final String projectId;
  final String componentKey; // e.g. S001_START, S001_END
  final String heatNo;
  final String? imagePath;
  final String? note;
  final int createdAt;

  ComponentHeat({
    required this.id,
    required this.projectId,
    required this.componentKey,
    required this.heatNo,
    required this.imagePath,
    required this.note,
    required this.createdAt,
  });

  static ComponentHeat fromMap(Map<String, Object?> m) => ComponentHeat(
        id: m['id'] as String,
        projectId: m['project_id'] as String,
        componentKey: m['component_key'] as String,
        heatNo: m['heat_no'] as String,
        imagePath: m['image_path'] as String?,
        note: m['note'] as String?,
        createdAt: (m['created_at'] as num).toInt(),
      );
}
