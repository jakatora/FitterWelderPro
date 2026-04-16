/// CUT length between two components for a given ISO dimension.
///
/// ISO is provided by the user (usually FACE→FACE on drawings, but can be
/// switched to AXIS or END).
///
/// The rule is always:
///   CUT = ISO - startOffset - endOffset
///
/// Offsets depend on the component and ISO reference.
double calculateCutOffsets({
  required double isoMm,
  required double startOffsetMm,
  required double endOffsetMm,
}) {
  return isoMm - startOffsetMm - endOffsetMm;
}