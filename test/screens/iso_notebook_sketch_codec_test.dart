// The ISO notebook autosave stores the drawing as JSON
// (lib/screens/iso_notebook_sketch_codec.dart). These tests pin that EVERY
// field of EVERY element kind survives the trip into the model and back —
// a field the encoder or the decoder forgets would silently vanish from the
// fitter's drawing on the next reopen.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/screens/iso_notebook_screen.dart';

import '../support/iso_sketch_fixture.dart';

void main() {
  test('every element of a representative sketch survives JSON → model → JSON',
      () {
    final original = representativeIsoSketch();
    final back = jsonDecode(isoSketchRoundTripForTesting(jsonEncode(original)));
    expect(back, original);
    expect(isoSketchSkippedItemsForTesting(jsonEncode(original)), 0);
  });

  test('the round trip is stable — a second save writes the same document',
      () {
    final once = isoSketchRoundTripForTesting(jsonEncode(representativeIsoSketch()));
    expect(isoSketchRoundTripForTesting(once), once);
  });

  test('an element this build cannot read is skipped and counted, not fatal',
      () {
    final sketch = representativeIsoSketch();
    (sketch['items']! as List<Object?>).addAll(<Object?>[
      <String, Object?>{'kind': 'comp', 'tool': 'hologramValve', 'pos': <double>[0, 0]},
      <String, Object?>{'kind': 'spline', 'points': <Object?>[]},
      <String, Object?>{
        'kind': 'comp',
        'tool': 'elbow90',
        'pos': <double>[0, 0],
        'elbowSubtype': 'lr180',
      },
    ]);
    final json = jsonEncode(sketch);

    expect(isoSketchSkippedItemsForTesting(json), 3);
    final back = jsonDecode(isoSketchRoundTripForTesting(json)) as Map;
    expect(back['items'], representativeIsoSketch()['items']);
  });

  test('a sketch from a newer format is refused instead of half-read', () {
    final sketch = representativeIsoSketch()..['format'] = kIsoSketchFormatVersion + 1;
    expect(
      () => isoSketchRoundTripForTesting(jsonEncode(sketch)),
      throwsA(isA<IsoSketchFormatException>()
          .having((e) => e.tooNew, 'tooNew', isTrue)),
    );
  });

  test('something that is not a sketch at all is refused', () {
    expect(() => isoSketchRoundTripForTesting('[1, 2, 3]'),
        throwsA(isA<IsoSketchFormatException>()));
    expect(() => isoSketchRoundTripForTesting('{"items": []}'),
        throwsA(isA<IsoSketchFormatException>()));
  });

  test('an empty sheet round-trips to an empty sheet', () {
    final empty = <String, Object?>{
      'format': kIsoSketchFormatVersion,
      'name': '',
      'items': <Object?>[],
      'takeoutMemory': <String, Object?>{
        'values': <Object?>[],
        'lastDn': <String, Object?>{},
      },
    };
    expect(jsonDecode(isoSketchRoundTripForTesting(jsonEncode(empty))), empty);
  });
}
