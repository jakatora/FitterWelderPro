// Bridge between iso_notebook_screen's private _Tool enum and the engine's
// ComponentBehaviour. Stays string-keyed (matches _Tool.name) so this file
// does NOT import the private _Tool type and the engine remains decoupled
// from the UI layer.

import '../models/prefab/component_behaviour.dart';

class ComponentClassification {
  const ComponentClassification._();

  static ComponentBehaviour behaviourOfToolName(String toolName) {
    switch (toolName) {
      case 'elbow90':
      case 'elbow45':
      case 'tee':
      case 'olet':
        return ComponentBehaviour.axialCenter;

      case 'reducer':
      case 'gateValve':
      case 'ballValve':
      case 'checkValve':
      case 'globeValve':
      case 'butterflyValve':
        return ComponentBehaviour.physicalLength;

      case 'flange':
      case 'blindFlange':
      case 'cap':
        return ComponentBehaviour.faceOnly;

      case 'weld':
      case 'fieldWeld':
      case 'support':
      case 'instrument':
      case 'spoolBreak':
      case 'northArrow':
      case 'flowArrow':
      case 'text':
        return ComponentBehaviour.zeroLength;

      default:
        throw ArgumentError.value(
          toolName,
          'toolName',
          'Not a classifiable component (line tools and unknown names are rejected)',
        );
    }
  }

  static bool isPhysical(String toolName) =>
      behaviourOfToolName(toolName).hasPhysicalBody;

  static bool isAxial(String toolName) =>
      behaviourOfToolName(toolName).isAxial;
}
