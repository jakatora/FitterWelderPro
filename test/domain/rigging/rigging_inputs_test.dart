// Zapis ostatnich ustawień kalkulatora zawiesi: tylko ustawienia (bez
// liczb, WLL i koloru), JSON tam i z powrotem, stary zapis z WLL
// ignorowany, uszkodzony zapis → wartości domyślne i flaga, bez wyjątku.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';
import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_inputs.dart';

const _sample = RiggingSavedInputs(
  fromPipe: true,
  unit: MassUnit.t,
  material: PipeMaterial.ss316,
  sling: SlingType.chain,
  mode: HitchMode.multiLeg,
  chokedLegs: true,
  angleKind: AngleKind.included,
);

void main() {
  test('zapis i odczyt zwracają te same ustawienia', () {
    final d = decodeRiggingInputs(encodeRiggingInputs(_sample));
    expect(d.intact, isTrue);
    expect(d.inputs.toJson(), _sample.toJson());
  });

  test('zapis nie zawiera liczb, WLL ani koloru', () {
    final keys = _sample.toJson().keys.toSet();
    for (final k in [
      'mass',
      'wll',
      'colour',
      'angle',
      'od',
      'wall',
      'length',
      'extra',
      'asymmetric',
      'wllBasis',
      'label',
    ]) {
      expect(keys, isNot(contains(k)), reason: k);
    }
  });

  test('stary zapis z WLL 5 t i masą — liczby ignorowane, ustawienia wracają',
      () {
    final old = jsonEncode({
      'v': 1,
      'fromPipe': false,
      'unit': 'kg',
      'mass': '4000',
      'od': '',
      'wall': '',
      'length': '',
      'extra': '',
      'material': 'cs',
      'sling': 'webbing',
      'mode': 'straight',
      'chokedLegs': false,
      'angleKind': 'fromVertical',
      'angle': '30',
      'asymmetric': false,
      'wll': '5000',
      'colour': 'red',
    });
    final d = decodeRiggingInputs(old);
    expect(d.intact, isTrue);
    expect(d.inputs.mode, HitchMode.straight);
    expect(d.inputs.toJson().containsKey('wll'), isFalse);
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
      ..['unit'] = 7;
    final d = decodeRiggingInputs(jsonEncode(json));
    expect(d.intact, isFalse);
    expect(d.inputs.sling, SlingType.webbing);
    expect(d.inputs.chokedLegs, isFalse);
    expect(d.inputs.unit, MassUnit.kg);
    // Pola nienaruszone wracają.
    expect(d.inputs.mode, HitchMode.multiLeg);
    expect(d.inputs.angleKind, AngleKind.included);
    expect(d.inputs.material, PipeMaterial.ss316);
  });

  test('brakujące pole → uszkodzony', () {
    final json = _sample.toJson()..remove('mode');
    final d = decodeRiggingInputs(jsonEncode(json));
    expect(d.intact, isFalse);
    expect(d.inputs.mode, HitchMode.twoLeg);
  });
}
