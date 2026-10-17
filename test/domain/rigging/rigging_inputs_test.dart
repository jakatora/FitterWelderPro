// Zapis ostatnich danych kalkulatora zawiesi: JSON tam i z powrotem,
// uszkodzony zapis → wartości domyślne i flaga, bez wyjątku.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';
import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_colors.dart';
import 'package:cut_list_app/domain/rigging/rigging_inputs.dart';

const _sample = RiggingSavedInputs(
  fromPipe: true,
  unit: MassUnit.t,
  mass: '1,6',
  od: '168,3',
  wall: '7,11',
  length: '6',
  extra: '50',
  material: PipeMaterial.ss316,
  sling: SlingType.chain,
  mode: HitchMode.multiLeg,
  chokedLegs: true,
  angleKind: AngleKind.included,
  angle: '90',
  asymmetric: true,
  wll: '2',
  colour: SlingColour.green,
);

void main() {
  test('zapis i odczyt zwracają te same dane', () {
    final d = decodeRiggingInputs(encodeRiggingInputs(_sample));
    expect(d.intact, isTrue);
    expect(d.inputs.toJson(), _sample.toJson());
  });

  test('bez koloru (null) — poprawny zapis', () {
    const s = RiggingSavedInputs(mass: '100');
    final d = decodeRiggingInputs(encodeRiggingInputs(s));
    expect(d.intact, isTrue);
    expect(d.inputs.colour, isNull);
    expect(d.inputs.mass, '100');
  });

  test('nieczytelny JSON albo nie-obiekt → domyślne i uszkodzony', () {
    const defaults = RiggingSavedInputs();
    for (final raw in ['{', 'null', '[1,2]', '"x"', '', '42']) {
      final d = decodeRiggingInputs(raw);
      expect(d.intact, isFalse, reason: raw);
      expect(d.inputs.toJson(), defaults.toJson(), reason: raw);
    }
  });

  test('złe pole → wartość domyślna tego pola, reszta zostaje', () {
    final json = _sample.toJson()
      ..['sling'] = 'hemp'
      ..['chokedLegs'] = 'tak'
      ..['mass'] = 12
      ..['colour'] = 'pink'
      ..['wll'] = 'x' * 200;
    final d = decodeRiggingInputs(jsonEncode(json));
    expect(d.intact, isFalse);
    expect(d.inputs.sling, SlingType.webbing);
    expect(d.inputs.chokedLegs, isFalse);
    expect(d.inputs.mass, '');
    expect(d.inputs.colour, isNull);
    expect(d.inputs.wll, '');
    // Pola nienaruszone wracają.
    expect(d.inputs.mode, HitchMode.multiLeg);
    expect(d.inputs.angleKind, AngleKind.included);
    expect(d.inputs.unit, MassUnit.t);
  });

  test('brakujące pole → uszkodzony', () {
    final json = _sample.toJson()..remove('mode');
    final d = decodeRiggingInputs(jsonEncode(json));
    expect(d.intact, isFalse);
    expect(d.inputs.mode, HitchMode.twoLeg);
  });
}
