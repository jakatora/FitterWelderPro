/// Place on a segment a heat number belongs to (schema v23 `side`).
enum TraceSide {
  /// The fitting the segment starts on.
  start('START'),

  /// The segment's own pipe.
  pipe('PIPE'),

  /// The fitting the segment ends on.
  end('END');

  const TraceSide(this.code);

  /// Value stored in `component_heats.side`.
  final String code;

  static TraceSide? fromCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

class ComponentHeat {
  final String id;
  final String projectId;

  /// Legacy key (`S001_END`, built from seq_no) for rows written before
  /// v23; `<segment id>_<SIDE>` for rows written since. Not used to find
  /// the place any more — see [segmentId] / [side].
  final String componentKey;
  final String heatNo;
  final String? imagePath;
  final String? note;
  final int createdAt;

  /// v23: stable id of the segment this heat belongs to; null for a legacy
  /// row whose segment no longer existed when it was migrated.
  final String? segmentId;

  /// v23: where on [segmentId] — null together with it.
  final TraceSide? side;

  ComponentHeat({
    required this.id,
    required this.projectId,
    required this.componentKey,
    required this.heatNo,
    required this.imagePath,
    required this.note,
    required this.createdAt,
    this.segmentId,
    this.side,
  });

  static ComponentHeat fromMap(Map<String, Object?> m) => ComponentHeat(
        id: m['id'] as String,
        projectId: m['project_id'] as String,
        componentKey: m['component_key'] as String,
        heatNo: m['heat_no'] as String,
        imagePath: m['image_path'] as String?,
        note: m['note'] as String?,
        createdAt: (m['created_at'] as num).toInt(),
        segmentId: m['segment_id'] as String?,
        side: TraceSide.fromCode(m['side'] as String?),
      );
}
