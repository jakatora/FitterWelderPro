/// Captures HOW the on-drawing dimension between two endpoints was measured.
///
/// On isometric drawings the same nominal length can mean different physical
/// cut lengths depending on where the tape was hooked: pipe centreline,
/// fitting face, or the very end of the pipe. PrefabEngine.cutLengthMm
/// branches on this value to add or subtract take-out / lay-in offsets when
/// translating a drawn dimension into a raw pipe cut length.
///
/// Default for purely axial-to-axial segments is [DimRef.centreToCentre]
/// (per user directive 2026-05-31: no popup when both endpoints are axial
/// components such as elbows / tees / reducers — designers always
/// dimension centre-to-centre in that case).
enum DimRef {
  centreToCentre,
  centreToFace,
  faceToFace,
  faceToEnd,
  centreToEnd,
}

extension DimRefX on DimRef {
  String get code {
    switch (this) {
      case DimRef.centreToCentre:
        return 'CTC';
      case DimRef.centreToFace:
        return 'CTF';
      case DimRef.faceToFace:
        return 'FTF';
      case DimRef.faceToEnd:
        return 'FTE';
      case DimRef.centreToEnd:
        return 'CTE';
    }
  }

  String get labelPl {
    switch (this) {
      case DimRef.centreToCentre:
        return 'oś-oś';
      case DimRef.centreToFace:
        return 'oś-czoło';
      case DimRef.faceToFace:
        return 'czoło-czoło';
      case DimRef.faceToEnd:
        return 'czoło-koniec';
      case DimRef.centreToEnd:
        return 'oś-koniec';
    }
  }

  String get labelEn {
    switch (this) {
      case DimRef.centreToCentre:
        return 'centre-centre';
      case DimRef.centreToFace:
        return 'centre-face';
      case DimRef.faceToFace:
        return 'face-face';
      case DimRef.faceToEnd:
        return 'face-end';
      case DimRef.centreToEnd:
        return 'centre-end';
    }
  }
}

DimRef parseDimRefCode(String code) {
  final normalized = code.toUpperCase();
  for (final ref in DimRef.values) {
    if (ref.code == normalized) return ref;
  }
  throw ArgumentError.value(code, 'code', 'Unknown DimRef code');
}
