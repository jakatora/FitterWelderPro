// A representative ISO notebook sketch in the stored JSON format
// (lib/screens/iso_notebook_sketch_codec.dart), shared by the codec
// round-trip test and the autosave widget test.
//
// Expected CUT of its only pipe, worked by hand so the widget test does not
// just echo the engine: ISO 2000 centre-to-centre, elbow 90° at end A whose
// take-out the fitter booked BY HAND ("Kolano 90° LR (CTE)" 152 — the manual
// row replaces the automatic one), elbow 45° SR at end B with CTE 64 taken
// automatically, plus a 3 mm gasket row:
//   2000 − 64 − 152 − 3 = 1781 mm.

import 'package:cut_list_app/screens/iso_notebook_screen.dart';

const double kRepresentativeIsoSketchCutMm = 1781;

/// Grid row 4 of the notebook's triangular grid (step 32, row height 32·√3/2).
const double isoRow4 = 110.85125168440814;

/// A representative sketch, written in the stored format with every optional
/// field populated somewhere: a dimensioned pipe with a CUT calculator
/// (manual deduct + non-default DimRef), a sloped insulated drain line, two
/// specced elbows, a tee, a gate valve with end connections, a reducer, shop
/// and field welds carrying their numbers, a note with Polish text and a
/// North arrow — plus the per-drawing take-out memory.
Map<String, Object?> representativeIsoSketch() => <String, Object?>{
      'format': kIsoSketchFormatVersion,
      'name': '6"-CWS-1234 — linia zażółcona',
      'items': <Object?>[
        <String, Object?>{
          'kind': 'seg',
          'tool': 'pipe',
          'a': <double>[64.0, isoRow4],
          'b': <double>[192.0, isoRow4],
          'slope': '',
          'insulated': false,
          'calc': <String, Object?>{
            'iso': '2000',
            'ref': 'centreToCentre',
            'deducts': <Object?>[
              <String, Object?>{'name': 'Uszczelka', 'value': '3'},
              <String, Object?>{'name': 'Kolano 90° LR (CTE)', 'value': '152'},
            ],
          },
        },
        <String, Object?>{
          'kind': 'seg',
          'tool': 'dashed',
          'a': <double>[192.0, isoRow4],
          'b': <double>[208.0, 138.56406460551017],
          'slope': 'FALL 1:100',
          'insulated': true,
          'calc': <String, Object?>{
            'iso': '(450)',
            'ref': 'faceToEnd',
            'deducts': <Object?>[],
          },
        },
        <String, Object?>{
          'kind': 'seg',
          'tool': 'thin',
          'a': <double>[0.0, 0.0],
          'b': <double>[32.0, 0.0],
          'slope': '',
          'insulated': false,
          'calc': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'elbow90',
          'pos': <double>[64.0, isoRow4],
          'dir': 0,
          'dir2': 4,
          'label': 'DN100 · 4" 90° LR',
          'dn': 100,
          'elbowSubtype': 'lr90',
          'cteMm': 152,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'elbow45',
          'pos': <double>[192.0, isoRow4],
          'dir': 3,
          'dir2': 5,
          'label': '',
          'dn': 100,
          'elbowSubtype': 'sr45',
          'cteMm': 64,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'tee',
          'pos': <double>[128.0, 221.7025033688163],
          'dir': 2,
          'dir2': 5,
          'label': 'T-1',
          'dn': 100,
          'elbowSubtype': null,
          'cteMm': 105,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'gateValve',
          'pos': <double>[256.0, isoRow4],
          'dir': 0,
          'dir2': null,
          'label': 'DN100',
          'dn': 100,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': 229,
          'dnOut': null,
          'endA': 'weldNeck',
          'endB': 'buttWeld',
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'reducer',
          'pos': <double>[320.0, isoRow4],
          'dir': 0,
          'dir2': null,
          'label': 'DN100×80',
          'dn': 100,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': 102,
          'dnOut': 80,
          'endA': 'buttWeld',
          'endB': 'socketWeld',
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'weld',
          'pos': <double>[81.6, isoRow4],
          'dir': 0,
          'dir2': null,
          'label': '1',
          'dn': null,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'fieldWeld',
          'pos': <double>[174.4, isoRow4],
          'dir': 3,
          'dir2': null,
          'label': '2',
          'dn': null,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'comp',
          'tool': 'northArrow',
          'pos': <double>[416.0, 27.712812921102035],
          'dir': 2,
          'dir2': null,
          'label': '',
          'dn': null,
          'elbowSubtype': null,
          'cteMm': null,
          'physicalLengthMm': null,
          'dnOut': null,
          'endA': null,
          'endB': null,
        },
        <String, Object?>{
          'kind': 'note',
          'pos': <double>[96.0, 55.42562584220407],
          'text': 'EL +12.500 · spoina W-2 do boroskopu',
        },
      ],
      'takeoutMemory': <String, Object?>{
        'values': <Object?>[
          <String, Object?>{'tool': 'elbow90', 'dn': 100, 'mm': 152},
          <String, Object?>{'tool': 'gateValve', 'dn': 100, 'mm': 229},
        ],
        'lastDn': <String, Object?>{'elbow90': 100, 'gateValve': 100},
      },
    };
