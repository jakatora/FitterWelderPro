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
      'format': 1,
      'name': '',
      'items': <Object?>[],
      'takeoutMemory': <String, Object?>{
        'values': <Object?>[],
        'lastDn': <String, Object?>{},
      },
    };
    expect(jsonDecode(isoSketchRoundTripForTesting(jsonEncode(empty))), empty);
  });

  group('per-end stops (format 3)', () {
    Map<String, Object?> withStops(String a, String b) {
      final sketch = representativeIsoSketch()..['format'] = 3;
      final items = sketch['items']! as List<Object?>;
      final seg = items.firstWhere((it) =>
          it is Map && it['kind'] == 'seg' && it['calc'] != null) as Map;
      (seg['calc'] as Map)
        ..['stopA'] = a
        ..['stopB'] = b;
      return sketch;
    }

    test('stops survive the round trip and make the document format 3', () {
      final sketch = withStops('centre', 'end');
      final back =
          jsonDecode(isoSketchRoundTripForTesting(jsonEncode(sketch))) as Map;
      expect(back, sketch);
      expect(back['format'], 3);
      expect(kIsoSketchFormatVersion, 3);
    });

    test('through the body at both ends — a pair no DimRef names', () {
      final sketch = withStops('end', 'end');
      expect(jsonDecode(isoSketchRoundTripForTesting(jsonEncode(sketch))),
          sketch);
    });

    test('half a pair is unreadable, not half-applied', () {
      final sketch = withStops('centre', 'end');
      final items = sketch['items']! as List<Object?>;
      final seg = items.firstWhere((it) =>
          it is Map && it['kind'] == 'seg' && it['calc'] != null) as Map;
      (seg['calc'] as Map).remove('stopB');
      expect(isoSketchSkippedItemsForTesting(jsonEncode(sketch)), 1);
    });

    test('a sketch without stops stays readable by older builds', () {
      final back = jsonDecode(
              isoSketchRoundTripForTesting(jsonEncode(representativeIsoSketch())))
          as Map;
      expect(back['format'], 1);
    });
  });

  group('weld gap (format 2)', () {
    test('a sketch with a gap keeps it and is written as format 2', () {
      final sketch = representativeIsoSketch()
        ..['format'] = 2
        ..['gapMm'] = 3.5;
      final back =
          jsonDecode(isoSketchRoundTripForTesting(jsonEncode(sketch))) as Map;
      expect(back, sketch);
      expect(back['format'], 2);
      expect(back['gapMm'], 3.5);
    });

    test('no gap → format 1 without the field, readable by older builds', () {
      final back = jsonDecode(
              isoSketchRoundTripForTesting(jsonEncode(representativeIsoSketch())))
          as Map;
      expect(back['format'], 1);
      expect(back.containsKey('gapMm'), isFalse);
      expect(kIsoSketchFormatVersion, greaterThanOrEqualTo(2),
          reason: 'this build must still READ format 2');
    });

    test('a nonsense gap is read as 0 — never a longer pipe', () {
      for (final bad in <Object?>[-3, 'x', null, 0]) {
        final sketch = representativeIsoSketch()
          ..['format'] = 2
          ..['gapMm'] = bad;
        final back =
            jsonDecode(isoSketchRoundTripForTesting(jsonEncode(sketch))) as Map;
        expect(back.containsKey('gapMm'), isFalse, reason: '$bad');
        expect(back['format'], 1, reason: '$bad');
      }
    });
  });
}
