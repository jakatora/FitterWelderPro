/// Shared input limit for the ISO editor; not a welding recommendation.
const double kSketchMaxGapMm = 10;
bool isValidSketchGapMm(num value) =>
    value.isFinite && value >= 0 && value <= kSketchMaxGapMm;
