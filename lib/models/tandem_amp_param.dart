class TandemAmpParam {
  final String id;
  final String position; // 'HORIZONTAL' | 'VERTICAL'
  final double t1Mm;
  final double t2Mm;
  final int insideAmps;  // wewnętrzny (bez drutu)
  final int outsideAmps; // zewnętrzny (z drutem)
  final String tempo;    // 'SLOW' | 'NORMAL' | 'FAST'
  final bool approved;   // true=Approved, false=My params
  final String? note;
  final int createdAt;
  final int updatedAt;

  const TandemAmpParam({
    required this.id,
    required this.position,
    required this.t1Mm,
    required this.t2Mm,
    required this.insideAmps,
    required this.outsideAmps,
    required this.tempo,
    required this.approved,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  double get avgT => (t1Mm + t2Mm) / 2.0;

  static TandemAmpParam fromRow(Map<String, Object?> r) {
    return TandemAmpParam(
      id: r['id'] as String,
      position: r['position'] as String,
      t1Mm: (r['t1_mm'] as num).toDouble(),
      t2Mm: (r['t2_mm'] as num).toDouble(),
      insideAmps: (r['inside_amps'] as num).toInt(),
      outsideAmps: (r['outside_amps'] as num).toInt(),
      tempo: r['tempo'] as String,
      approved: ((r['approved'] as num).toInt()) == 1,
      note: r['note'] as String?,
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'position': position,
        't1_mm': t1Mm,
        't2_mm': t2Mm,
        'inside_amps': insideAmps,
        'outside_amps': outsideAmps,
        'tempo': tempo,
        'approved': approved ? 1 : 0,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
