import 'dart:convert';

/// ComponentLibrary model for storing component specifications
class ComponentLibraryItem {
  final int? id;
  final String material; // SS or CS
  final double od;
  final double t;
  final String componentType;
  final bool isAxial;
  final double offsetAxis; // distance to centerline for axial components

  ComponentLibraryItem({
    this.id,
    required this.material,
    required this.od,
    required this.t,
    required this.componentType,
    required this.isAxial,
    this.offsetAxis = 0,
  });

  /// Get display label: "Rodzaj – Ø x t (wymiar do osi)"
  String get displayLabel {
    final typeName = _getTypeName(componentType);
    if (isAxial) {
      return '$typeName – ${od.toStringAsFixed(1)} x $t (do osi: ${offsetAxis.toStringAsFixed(1)}mm)';
    }
    return '$typeName – ${od.toStringAsFixed(1)} x $t';
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'elbow90':
        return 'Elbow 90°';
      case 'elbow45':
        return 'Elbow 45°';
      case 'tee':
        return 'Trójnik';
      case 'reducer':
        return 'Redukcja';
      case 'flange':
        return 'Flansza';
      case 'valve':
        return 'Zawór';
      case 'other':
        return 'Inny';
      default:
        return type;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'material': material,
      'od': od,
      't': t,
      'component_type': componentType,
      'is_axial': isAxial ? 1 : 0,
      'offset_axis': offsetAxis,
    };
  }

  factory ComponentLibraryItem.fromMap(Map<String, dynamic> map) {
    return ComponentLibraryItem(
      id: map['id'],
      material: map['material'] ?? '',
      od: map['od']?.toDouble() ?? 0,
      t: map['t']?.toDouble() ?? 0,
      componentType: map['component_type'] ?? '',
      isAxial: (map['is_axial'] ?? 0) == 1,
      offsetAxis: map['offset_axis']?.toDouble() ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ComponentLibraryItem.fromJson(String source) =>
      ComponentLibraryItem.fromMap(jsonDecode(source));

  ComponentLibraryItem copyWith({
    int? id,
    String? material,
    double? od,
    double? t,
    String? componentType,
    bool? isAxial,
    double? offsetAxis,
  }) {
    return ComponentLibraryItem(
      id: id ?? this.id,
      material: material ?? this.material,
      od: od ?? this.od,
      t: t ?? this.t,
      componentType: componentType ?? this.componentType,
      isAxial: isAxial ?? this.isAxial,
      offsetAxis: offsetAxis ?? this.offsetAxis,
    );
  }
}
