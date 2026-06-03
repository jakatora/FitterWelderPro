/// Joint type at each end of a physical component.
///
/// Drives the upcoming Phase 3 auto-weld pass: when two adjacent ends both
/// report `producesWeld == true`, the synthesizer inserts a `WeldPoint`
/// between them. Threaded / grooved / none ends are skipped.
library;

enum EndConnection {
  buttWeld,
  socketWeld,
  threaded,
  slipOn,
  lapJoint,
  weldNeck,
  groove,
  none,
}

extension EndConnectionX on EndConnection {
  String get code {
    switch (this) {
      case EndConnection.buttWeld:
        return 'BW';
      case EndConnection.socketWeld:
        return 'SW';
      case EndConnection.threaded:
        return 'TH';
      case EndConnection.slipOn:
        return 'SO';
      case EndConnection.lapJoint:
        return 'LJ';
      case EndConnection.weldNeck:
        return 'WN';
      case EndConnection.groove:
        return 'GR';
      case EndConnection.none:
        return 'NONE';
    }
  }

  String get labelPl {
    switch (this) {
      case EndConnection.buttWeld:
        return 'spaw doczolowy';
      case EndConnection.socketWeld:
        return 'spaw kielichowy';
      case EndConnection.threaded:
        return 'gwint';
      case EndConnection.slipOn:
        return 'wsuwany';
      case EndConnection.lapJoint:
        return 'Lap joint';
      case EndConnection.weldNeck:
        return 'weld neck';
      case EndConnection.groove:
        return 'rowek';
      case EndConnection.none:
        return 'brak';
    }
  }

  String get labelEn {
    switch (this) {
      case EndConnection.buttWeld:
        return 'butt weld';
      case EndConnection.socketWeld:
        return 'socket weld';
      case EndConnection.threaded:
        return 'threaded';
      case EndConnection.slipOn:
        return 'slip-on';
      case EndConnection.lapJoint:
        return 'lap joint';
      case EndConnection.weldNeck:
        return 'weld neck';
      case EndConnection.groove:
        return 'groove';
      case EndConnection.none:
        return 'none';
    }
  }

  bool get producesWeld {
    switch (this) {
      case EndConnection.buttWeld:
      case EndConnection.socketWeld:
      case EndConnection.weldNeck:
      case EndConnection.lapJoint:
      case EndConnection.slipOn:
        return true;
      case EndConnection.threaded:
      case EndConnection.groove:
      case EndConnection.none:
        return false;
    }
  }
}
