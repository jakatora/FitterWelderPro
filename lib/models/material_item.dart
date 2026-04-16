class MaterialItem {
  final String category; // PIPE, ELB90, etc.
  final String description;
  final int? quantity;
  final double? totalLengthMm;

  MaterialItem({
    required this.category,
    required this.description,
    this.quantity,
    this.totalLengthMm,
  });
}
