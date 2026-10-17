// Zapis ostatnich wejść: pełny obieg, uszkodzony JSON → domyślne + flaga,
// uszkodzone pole → domyślne tego pola + flaga, prędkość poniżej minimum
// procesu nie wraca z zapisu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_assessment.dart';
import 'package:cut_list_app/domain/fume/fume_capture.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';
import 'package:cut_list_app/domain/fume/fume_inputs.dart';

void main() {
  test('obieg zapis → odczyt bez strat', () {
    const i = FumeInputs(
      material: FumeMaterial.stainless,
      process: FumeProcess.tig,
      lev: FumeLevStatus.present,
      rpe: FumeRpe.th3,
      flow: 1200,
      flowUnit: FumeFlowUnit.ls,
      shape: FumeHoodShape.rectangular,
      width: 30,
      height: 20,
      lengthUnit: FumeLengthUnit.cm,
      flanged: true,
      velocity: 0.75,
      distance: 25,
    );
    final d = decodeFumeInputs(encodeFumeInputs(i));
    expect(d.corrupt, isFalse);
    final o = d.inputs;
    expect(o.material, i.material);
    expect(o.process, i.process);
    expect(o.lev, i.lev);
    expect(o.rpe, i.rpe);
    expect(o.flow, i.flow);
    expect(o.flowUnit, i.flowUnit);
    expect(o.shape, i.shape);
    expect(o.width, i.width);
    expect(o.height, i.height);
    expect(o.lengthUnit, i.lengthUnit);
    expect(o.flanged, isTrue);
    expect(o.velocity, 0.75);
    expect(o.distance, 25);
  });

  test('brak zapisu → domyślne, bez informacji o uszkodzeniu', () {
    final d = decodeFumeInputs(null);
    expect(d.corrupt, isFalse);
    expect(d.inputs.material, isNull);
    expect(d.inputs.velocity, 0.5);
  });

  test('uszkodzony JSON → domyślne + informacja', () {
    for (final raw in ['{nie json', '[]', '"tekst"', '42', '']) {
      final d = decodeFumeInputs(raw);
      expect(d.corrupt, isTrue, reason: raw);
      expect(d.inputs.material, isNull, reason: raw);
      expect(d.inputs.flow, isNull, reason: raw);
      expect(d.inputs.velocity, 0.5, reason: raw);
    }
  });

  test('uszkodzone pole → domyślne tego pola + informacja, reszta zostaje', () {
    final d = decodeFumeInputs(
        '{"material":"stal?","process":"mma","flow":"dużo","diameter":-3,'
        '"flanged":"tak","rpe":"p3"}');
    expect(d.corrupt, isTrue);
    expect(d.inputs.material, isNull);
    expect(d.inputs.process, FumeProcess.mma);
    expect(d.inputs.flow, isNull);
    expect(d.inputs.diameter, isNull);
    expect(d.inputs.flanged, isFalse);
    expect(d.inputs.rpe, FumeRpe.p3);
  });

  test('prędkość poniżej minimum procesu z zapisu → minimum + informacja', () {
    final low = decodeFumeInputs('{"process":"migMag","velocity":0.3}');
    expect(low.corrupt, isTrue);
    expect(low.inputs.velocity, 0.5);
    // Szlifowanie: minimum 2,5 — zapisane 1,0 nie wraca.
    final g = decodeFumeInputs('{"process":"grinding","velocity":1.0}');
    expect(g.corrupt, isTrue);
    expect(g.inputs.velocity, 2.5);
    // Wyższa niż minimum — przyjęta.
    final ok = decodeFumeInputs('{"process":"grinding","velocity":4}');
    expect(ok.corrupt, isFalse);
    expect(ok.inputs.velocity, 4);
  });

  test('zła jednostka → liczba z tą jednostką odrzucona (nie zgadujemy)', () {
    final d = decodeFumeInputs(
        '{"flowUnit":"galony","flow":500,"lengthUnit":"cale","diameter":6}');
    expect(d.corrupt, isTrue);
    expect(d.inputs.flow, isNull);
    expect(d.inputs.diameter, isNull);
    expect(d.inputs.flowUnit, FumeFlowUnit.m3h);
    expect(d.inputs.lengthUnit, FumeLengthUnit.mm);
  });

  test('wartości ponad limit pola → odrzucone', () {
    final d = decodeFumeInputs('{"flow":1e9,"distance":99999}');
    expect(d.corrupt, isTrue);
    expect(d.inputs.flow, isNull);
    expect(d.inputs.distance, isNull);
  });
}
