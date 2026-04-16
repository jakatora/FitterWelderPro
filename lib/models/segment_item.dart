import 'dart:convert';

/// Kind of segment item
enum ItemKind {
  component,
  pipe,
  openEnd;

  factory ItemKind.fromString(String s) {
    return values.firstWhere((e) => e.name == s);
  }
}

/// Component type enum
enum ComponentType {
  pipe,
  elbow90,
  elbow45,
  tee,
  reducer,
  flange,
  valve,
  other;

  factory ComponentType.fromString(String s) {
    return values.firstWhere((e) => e.name == s);
  }

  String get displayName {
    switch (this) {
      case pipe:
        return 'Rura';
      case elbow90:
        return 'Elbow 90°';
      case elbow45:
        return 'Elbow 45°';
      case tee:
        return 'Trójnik';
      case reducer:
        return 'Redukcja';
      case flange:
        return 'Flansza';
      case valve:
        return 'Zawór';
      case other:
        return 'Inny';
    }
  }

  bool get isAxial {
    switch (this) {
      case pipe:
      case reducer:
      case flange:
      case valve:
      case other:
        return false;
      case elbow90:
      case elbow45:
      case tee:
        return true;
    }
  }
}

/// SegmentItem model representing a component or pipe in a segment
class SegmentItem {
  final int? id;
  final int segmentId;
  final int seqIndex; // position in sequence
  final ItemKind kind;
  final ComponentType? componentType; // null for pipe
  final double od;
  final double t;
  final double? reducerOdOut; // for reducer: new OD after reduction
  final bool isAxial;
  final double offsetAxis; // only for axial components, 0 for non-axial

  SegmentItem({
    this.id,
    required this.segmentId,
    required this.seqIndex,
    required this.kind,
    this.componentType,
    required this.od,
    required this.t,
    this.reducerOdOut,
    required this.isAxial,
    this.offsetAxis = 0,
  });

  /// Create a pipe item
  factory SegmentItem.pipe({
    required int segmentId,
    required int seqIndex,
    required double od,
    required double t,
  }) {
    return SegmentItem(
      segmentId: segmentId,
      seqIndex: seqIndex,
      kind: ItemKind.pipe,
      od: od,
      t: t,
      isAxial: false,
    );
  }

  /// Create an open end marker
  factory SegmentItem.openEnd({
    required int segmentId,
    required int seqIndex,
    required double od,
    required double t,
  }) {
    return SegmentItem(
      segmentId: segmentId,
      seqIndex: seqIndex,
      kind: ItemKind.openEnd,
      od: od,
      t: t,
      isAxial: false,
      offsetAxis: 0,
    );
  }

  /// Create a reducer component
  factory SegmentItem.reducer({
    required int segmentId,
    required int seqIndex,
    required double odIn,
    required double t,
    required double odOut,
  }) {
    return SegmentItem(
      segmentId: segmentId,
      seqIndex: seqIndex,
      kind: ItemKind.component,
      componentType: ComponentType.reducer,
      od: odIn,
      t: t,
      reducerOdOut: odOut,
      isAxial: false,
      offsetAxis: 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'segment_id': segmentId,
      'seq_index': seqIndex,
      'kind': kind.name,
      'component_type': componentType?.name,
      'od': od,
      't': t,
      'reducer_od_out': reducerOdOut,
      'is_axial': isAxial ? 1 : 0,
      'offset_axis': offsetAxis,
    };
  }

  factory SegmentItem.fromMap(Map<String, dynamic> map) {
    return SegmentItem(
      id: map['id'],
      segmentId: map['segment_id'],
      seqIndex: map['seq_index'] ?? 0,
      kind: ItemKind.fromString(map['kind']),
      componentType: map['component_type'] != null
          ? ComponentType.fromString(map['component_type'])
          : null,
      od: map['od']?.toDouble() ?? 0,
      t: map['t']?.toDouble() ?? 0,
      reducerOdOut: map['reducer_od_out']?.toDouble(),
      isAxial: (map['is_axial'] ?? 0) == 1,
      offsetAxis: map['offset_axis']?.toDouble() ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory SegmentItem.fromJson(String source) =>
      SegmentItem.fromMap(jsonDecode(source));

  SegmentItem copyWith({
    int? id,
    int? segmentId,
    int? seqIndex,
    ItemKind? kind,
    ComponentType? componentType,
    double? od,
    double? t,
    double? reducerOdOut,
    bool? isAxial,
    double? offsetAxis,
  }) {
    return SegmentItem(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      seqIndex: seqIndex ?? this.seqIndex,
      kind: kind ?? this.kind,
      componentType: componentType ?? this.componentType,
      od: od ?? this.od,
      t: t ?? this.t,
      reducerOdOut: reducerOdOut ?? this.reducerOdOut,
      isAxial: isAxial ?? this.isAxial,
      offsetAxis: offsetAxis ?? this.offsetAxis,
    );
  }
}
