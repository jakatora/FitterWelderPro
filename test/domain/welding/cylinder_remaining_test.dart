// „Na ile starczy tej butli?” — gaz do rezerwy, minuty łuku, spoiny.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/shielding_gas.dart';

void main() {
  test('50 L przy 60 bar, rezerwa 10, palnik 10 L/min → 250 min', () {
    final r = cylinderRemaining(
        waterCapacityL: 50,
        currentPressureBar: 60,
        reserveBar: 10,
        torchLpm: 10)!;
    expect(r.gasL, 2500);
    expect(r.flowMinutes, 250);
    expect(r.welds, isNull);
  });

  test('spoiny: czas spoiny + pre-/post-flow', () {
    final r = cylinderRemaining(
        waterCapacityL: 50,
        currentPressureBar: 60,
        reserveBar: 10,
        torchLpm: 10,
        weldMinutes: 4.75,
        preFlowS: 5,
        postFlowS: 10)!;
    // 250 min / (4,75 + 0,25) = 50 spoin.
    expect(r.welds, closeTo(50, 1e-9));
  });

  test('ciśnienie nie wyższe niż rezerwa albo przepływ 0 → null', () {
    expect(
        cylinderRemaining(
            waterCapacityL: 50,
            currentPressureBar: 10,
            reserveBar: 10,
            torchLpm: 10),
        isNull);
    expect(
        cylinderRemaining(
            waterCapacityL: 50, currentPressureBar: 60, torchLpm: 0),
        isNull);
  });
}
