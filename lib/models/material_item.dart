class MaterialItem {
  final String category; // PIPE, ELB90, etc.
  final String description;
  final int? quantity;
  final double? totalLengthMm;

  /// For a fitting WITHOUT a component-library entry — a project from the ISO
  /// scanner, or a library entry deleted after the segment was saved — the
  /// stored end kind (`axial` = elbow/tee family, `nonAxial` = flange, valve,
  /// reducer…). Lets the screen describe the row in the active language.
  /// Null for pipes and for fittings resolved from the library.
  final String? endKind;

  /// Pipe OD at that fitting (kind-based rows only).
  final double? diameterMm;

  /// Centre-to-end (take-out) stored on the segment for an axial fitting —
  /// the one number that identifies it when the type is unknown.
  final double? takeoutMm;

  /// True when segments point at a library entry that no longer exists.
  final bool libraryEntryMissing;

  MaterialItem({
    required this.category,
    required this.description,
    this.quantity,
    this.totalLengthMm,
    this.endKind,
    this.diameterMm,
    this.takeoutMm,
    this.libraryEntryMissing = false,
  });
}
