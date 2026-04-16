import 'dart:convert';

/// PipeRun model representing a calculated pipe run between two items
class PipeRun {
  final int? id;
  final int segmentId;
  final int? fromItemId; // null for open end at start
  final int? toItemId; // null for open end at end
  final double od;
  final double t;
  final double iso;
  final double cut;
  final int createdAt;

  PipeRun({
    this.id,
    required this.segmentId,
    this.fromItemId,
    this.toItemId,
    required this.od,
    required this.t,
    required this.iso,
    required this.cut,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Check if this is an open end at start (no from item)
  bool get isOpenStart => fromItemId == null;

  /// Check if this is an open end at end (no to item)
  bool get isOpenEnd => toItemId == null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'segment_id': segmentId,
      'from_item_id': fromItemId,
      'to_item_id': toItemId,
      'od': od,
      't': t,
      'iso': iso,
      'cut': cut,
      'created_at': createdAt,
    };
  }

  factory PipeRun.fromMap(Map<String, dynamic> map) {
    return PipeRun(
      id: map['id'],
      segmentId: map['segment_id'],
      fromItemId: map['from_item_id'],
      toItemId: map['to_item_id'],
      od: map['od']?.toDouble() ?? 0,
      t: map['t']?.toDouble() ?? 0,
      iso: map['iso']?.toDouble() ?? 0,
      cut: map['cut']?.toDouble() ?? 0,
      createdAt: map['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory PipeRun.fromJson(String source) => PipeRun.fromMap(jsonDecode(source));

  PipeRun copyWith({
    int? id,
    int? segmentId,
    int? fromItemId,
    int? toItemId,
    double? od,
    double? t,
    double? iso,
    double? cut,
    int? createdAt,
  }) {
    return PipeRun(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      fromItemId: fromItemId ?? this.fromItemId,
      toItemId: toItemId ?? this.toItemId,
      od: od ?? this.od,
      t: t ?? this.t,
      iso: iso ?? this.iso,
      cut: cut ?? this.cut,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
