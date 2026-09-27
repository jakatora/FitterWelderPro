class HeatPhoto {
  final String id;
  final String projectId;
  final String? libraryComponentId;
  final String imagePath;
  final String? note;
  final int createdAt;

  /// v23: heat number read off the label in the photo; null when none was
  /// typed (photos from before v23 may carry it in [note] only).
  final String? heatNo;

  HeatPhoto({
    required this.id,
    required this.projectId,
    required this.libraryComponentId,
    required this.imagePath,
    required this.note,
    required this.createdAt,
    this.heatNo,
  });

  static HeatPhoto fromRow(Map<String, Object?> r) {
    return HeatPhoto(
      id: r['id'] as String,
      projectId: r['project_id'] as String,
      libraryComponentId: r['library_component_id'] as String?,
      imagePath: r['image_path'] as String,
      note: r['note'] as String?,
      createdAt: (r['created_at'] as num).toInt(),
      heatNo: r['heat_no'] as String?,
    );
  }
}
