import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/fitter/pipe_route.dart';

Map<String, Object?> fields() => {
      'h1_mm': 2000.0,
      'h2_mm': 500.0,
      'x_mm': 1000.0,
      'y_mm': 800.0,
      'r_mm': 152.0,
      'gap_mm': 3.0,
      'end_welds': false,
      'dn': 100
    };
void main() {
  test('reference route separates straight stock, gaps and arcs', () {
    final a = PipeRouteInput.fromFields(fields());
    expect(a.result.seg1, 845);
    expect(a.result.seg2, 1190);
    expect(a.result.seg3, 645);
    expect(a.result.total, 2680);
  });
  for (final patch in <Map<String, Object?>>[
    {'h1_mm': 500},
    {'h1_mm': double.infinity},
    {'h1_mm': '2000'},
    {'h1_mm': double.maxFinite, 'h2_mm': -double.maxFinite},
    {'x_mm': 0},
    {'y_mm': -1},
    {'r_mm': -1},
    {'gap_mm': -1},
    {'end_welds': 'false'},
    {'dn': 50},
    {'dn': 100.0},
    {'extra': 1},
    {'r_mm': 999, 'dn': null},
    {'x_mm': double.maxFinite, 'y_mm': double.maxFinite},
  ]) {
    test('strict complete route rejects $patch', () {
      expect(() => PipeRouteInput.fromFields({...fields(), ...patch}),
          throwsFormatException);
    });
  }
  for (final key in fields().keys.where((k) => k != 'dn')) {
    test('requires $key', () {
      expect(() => PipeRouteInput.fromFields(fields()..remove(key)),
          throwsFormatException);
    });
  }
  test('wire freezes original data and permits explicit C-C', () {
    final f = fields()
      ..['r_mm'] = 0.0
      ..['dn'] = null;
    final a = PipeRouteInput.fromFields(f);
    f['r_mm'] = 999;
    expect(a.fields['r_mm'], 0);
    expect(() => a.fields['x_mm'] = 1, throwsUnsupportedError);
  });
}
