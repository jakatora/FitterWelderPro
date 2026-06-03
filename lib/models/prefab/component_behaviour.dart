// Classification of how a pipeline component behaves geometrically in a prefab cut.
//
// This drives two distinct decisions in the prefab engine:
//   1. Whether the dimension-reference picker auto-prompts the user.
//      Any segment whose end-component has a physical body (i.e.
//      [ComponentBehaviourX.hasPhysicalBody]) on either end triggers the
//      picker, because the cut length depends on whether the dimension is
//      taken to centre, face, or end-of-fitting.
//   2. Whether a mid-segment component subtracts its physicalLength from the
//      raw centreline distance when computing the actual pipe cut length.
//      Only [hasPhysicalBody] components occupy real space along the run;
//      axial/zero-length markers do not shorten the cut.
//
// Keep this file standalone — no UI imports, no _Tool enum from
// iso_notebook_screen.dart. The _Tool to ComponentBehaviour mapping is
// defined in iso_notebook_screen.dart so this layer stays decoupled and
// reusable by PrefabEngine.

enum ComponentBehaviour {
  axialCenter,
  axialWithBranch,
  physicalLength,
  faceOnly,
  diameterChange,
  zeroLength,
}

extension ComponentBehaviourX on ComponentBehaviour {
  bool get isAxial =>
      this == ComponentBehaviour.axialCenter ||
      this == ComponentBehaviour.axialWithBranch;

  bool get hasPhysicalBody =>
      this == ComponentBehaviour.physicalLength ||
      this == ComponentBehaviour.faceOnly ||
      this == ComponentBehaviour.diameterChange;

  String get code {
    switch (this) {
      case ComponentBehaviour.axialCenter:
        return 'AXIAL';
      case ComponentBehaviour.axialWithBranch:
        return 'AXIAL_BRANCH';
      case ComponentBehaviour.physicalLength:
        return 'PHYSICAL';
      case ComponentBehaviour.faceOnly:
        return 'FACE';
      case ComponentBehaviour.diameterChange:
        return 'DIA_CHANGE';
      case ComponentBehaviour.zeroLength:
        return 'ZERO';
    }
  }
}
