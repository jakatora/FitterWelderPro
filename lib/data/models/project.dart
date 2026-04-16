class Project {
  final int? id;
  final String name;
  final String? client;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    this.id,
    required this.name,
    this.client,
    this.location,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Project copyWith({
    int? id,
    String? name,
    String? client,
    String? location,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      client: client ?? this.client,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'client': client,
      'location': location,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  static Project fromMap(Map<String, Object?> map) {
    return Project(
      id: map['id'] as int?,
      name: (map['name'] as String?) ?? '',
      client: map['client'] as String?,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
