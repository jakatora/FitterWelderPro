import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/fitter/tube_bending.dart';
import 'package:cut_list_app/domain/fitter/tube_bending_command.dart';

Map<String, Object?> commandFields(String mode) => {
      'mode': mode,
      'unit': 'mm',
      'clr_mm': 38.0,
      'min_straight_mm': 0.0,
      'marker_offset_mm': 0.0,
      'springback_deg': 0.0,
      if (mode != 'multi') ...{
        'angle_deg': 90.0,
        'leg_a_mm': 200.0,
        'leg_b_mm': 150.0
      },
      if (mode == 'offset') ...{
        'height_mm': 100.0,
        'spread_mm': 50.0,
        'angle_deg': 45.0
      },
      if (mode == 'multi') ...{
        'segments_mm': [150.0, 200.0, 250.0],
        'angles_deg': [90.0, 45.0],
        'rotations_deg': [0.0, 180.0]
      },
    };

void main() {
  test('complete single command uses actual domain cut and mark', () {
    final c = TubeBendingCommand.fromFields(commandFields('single'));
    expect(c.run.cutLengthMm(c.unit), 334);
    expect(c.run.bends.single.markMm, closeTo(162, 1e-9));
    expect(c.run.input.springbackDeg, 0);
    expect(c.offset, isNull);
  });
  test('offset preserves actual travel, roll and opposite bend', () {
    final c = TubeBendingCommand.fromFields(commandFields('offset'));
    expect(c.offset!.travelMm, closeTo(158.113883, 1e-6));
    expect(c.offset!.rollFromVerticalDeg, closeTo(26.565051, 1e-6));
    expect(c.run.bends.last.rotationDeg, 180);
  });
  test('multi command copies lists and freezes wire values', () {
    final f = commandFields('multi');
    final c = TubeBendingCommand.fromFields(f);
    (f['segments_mm'] as List)[0] = 999.0;
    expect(c.run.input.segmentsMm.first, 150);
    expect(() => (c.fields['segments_mm'] as List)[0] = 500.0,
        throwsUnsupportedError);
    expect(() => c.fields['clr_mm'] = 90, throwsUnsupportedError);
    expect(c.run.cutLengthMm(TubeUnit.mm), 582.5);
    expect(c.run.bends.last.rotationDeg, 180);
  });
  test('inch output has the same geometry and actual native rounding', () {
    final c = TubeBendingCommand.fromFields(
        {...commandFields('single'), 'unit': 'inch'});
    expect(c.run.developedMm, closeTo(333.6903, 1e-4));
    expect(c.run.cutLengthMm(c.unit), greaterThanOrEqualTo(c.run.developedMm));
    expect(c.run.cutLengthMm(c.unit) - c.run.developedMm,
        lessThan(kMmPerInch / 32));
  });
  for (final (mode, patch) in <(String, Map<String, Object?>)>[
    ('single', {'clr_mm': '38'}),
    ('single', {'clr_mm': double.infinity}),
    ('single', {'clr_mm': 0}),
    ('single', {'unit': 'cm'}),
    ('single', {'angle_deg': 180}),
    ('single', {'leg_a_mm': 1}),
    ('single', {'height_mm': 100}),
    ('single', {'unknown': 1}),
    ('single', {'min_straight_mm': -1}),
    ('single', {'marker_offset_mm': 1001}),
    ('single', {'springback_deg': 31}),
    ('offset', {'angle_deg': 91}),
    ('offset', {'spread_mm': -1}),
    ('offset', {'height_mm': 0}),
    (
      'multi',
      {
        'segments_mm': [150, 200]
      }
    ),
    ('multi', {'angles_deg': []}),
    (
      'multi',
      {
        'rotations_deg': [180, 0]
      }
    ),
    (
      'multi',
      {
        'rotations_deg': [0]
      }
    ),
    (
      'multi',
      {
        'angles_deg': [90, '45']
      }
    ),
    (
      'multi',
      {
        'segments_mm': [150, double.nan, 250]
      }
    ),
    (
      'multi',
      {
        'rotations_deg': [0, double.infinity]
      }
    ),
  ]) {
    test('strict atomic contract rejects $mode $patch', () {
      expect(
          () =>
              TubeBendingCommand.fromFields({...commandFields(mode), ...patch}),
          throwsFormatException);
    });
  }
  for (final mode in ['single', 'offset', 'multi']) {
    for (final key in commandFields(mode).keys) {
      test('complete $mode contract requires $key', () {
        final f = commandFields(mode)..remove(key);
        expect(() => TubeBendingCommand.fromFields(f), throwsFormatException);
      });
    }
  }
  test(
      'nonblocking native warnings remain visible without fabricating grip checks',
      () {
    final c = TubeBendingCommand.fromFields({
      ...commandFields('single'),
      'min_straight_mm': 200,
      'marker_offset_mm': 1000
    });
    expect(c.run.feasible, isTrue);
    expect(
        c.run.warnings
            .where((w) => w.kind == TubeBendWarningKind.endStraightTooShort),
        hasLength(2));
    expect(
        c.run.warnings
            .where((w) => w.kind == TubeBendWarningKind.markOutsideTube),
        hasLength(1));
  });
}
