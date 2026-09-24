import 'dart:math' as math;

import 'package:flutter/material.dart';

// Weld discoloration ("heat tint") reference for the inside of austenitic
// stainless tube, modelled on AWS D18.1 / D18.2 sample discoloration levels.
//
// The colour an inside weld bead takes is driven by the oxygen left in the
// backing (purge) gas while the metal is hot. More O₂ → darker oxide. A
// food/pharma welder reads the bead, names the level and decides whether it
// passes — this screen is that decision, offline, on site.
//
// O₂ per level = the backing-gas oxygen used to make the AWS D18.2 sample
// of that number: "The Sample Numbers refer to the amount of oxygen (ppm) in
// the purging gas: No.1 10, No.2 25, No.3 50, No.4 100, No.5 200, No.6 500,
// No.7 1000, No.8 5000, No.9 12500, No.10 25000" (AWS D18.2, quoted in the
// 3-A SSI talk "Hygienic Welding: How Do You Know When It's Right?").
//
// The ppm values are only a CORRELATION: colour also depends on moisture,
// surface contamination, hydrogen and finish, so AWS advises judging by the
// sample number, not ppm. Real acceptance is whatever the project
// specification / WPS calls out. The screen says so plainly.

class HeatTintLevel {
  final int level;          // 1 (best) … 10 (worst)
  final Color swatch;       // representative oxide colour
  final String namePl;
  final String nameEn;
  final String approxO2;    // backing-gas O₂ of the AWS D18.2 sample (text)
  final double o2Ppm;       // same value as a number, for lookups
  final HeatTintVerdict verdict;

  const HeatTintLevel({
    required this.level,
    required this.swatch,
    required this.namePl,
    required this.nameEn,
    required this.approxO2,
    required this.o2Ppm,
    required this.verdict,
  });
}

enum HeatTintVerdict { pharma, food, marginal, reject }

const List<HeatTintLevel> kHeatTintLevels = [
  HeatTintLevel(
    level: 1, swatch: Color(0xFFD9D9D9),
    namePl: 'Srebrny / bez przebarwień', nameEn: 'Silver / no tint',
    approxO2: '~ 10 ppm', o2Ppm: 10, verdict: HeatTintVerdict.pharma),
  HeatTintLevel(
    level: 2, swatch: Color(0xFFE8D48A),
    namePl: 'Słomkowy', nameEn: 'Light straw',
    approxO2: '~ 25 ppm', o2Ppm: 25, verdict: HeatTintVerdict.pharma),
  HeatTintLevel(
    level: 3, swatch: Color(0xFFC9A03A),
    namePl: 'Ciemnozłoty', nameEn: 'Dark gold',
    approxO2: '~ 50 ppm', o2Ppm: 50, verdict: HeatTintVerdict.food),
  HeatTintLevel(
    level: 4, swatch: Color(0xFF9C6B2E),
    namePl: 'Brąz', nameEn: 'Bronze',
    approxO2: '~ 100 ppm', o2Ppm: 100, verdict: HeatTintVerdict.food),
  HeatTintLevel(
    level: 5, swatch: Color(0xFF8B4A5C),
    namePl: 'Czerwono-fioletowy', nameEn: 'Red-purple',
    approxO2: '~ 200 ppm', o2Ppm: 200, verdict: HeatTintVerdict.marginal),
  HeatTintLevel(
    level: 6, swatch: Color(0xFF6B4A8B),
    namePl: 'Fioletowy', nameEn: 'Purple',
    approxO2: '~ 500 ppm', o2Ppm: 500, verdict: HeatTintVerdict.marginal),
  HeatTintLevel(
    level: 7, swatch: Color(0xFF3A5A9C),
    namePl: 'Niebieski', nameEn: 'Blue',
    approxO2: '~ 1000 ppm', o2Ppm: 1000, verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 8, swatch: Color(0xFF4A5A6B),
    namePl: 'Szaroniebieski', nameEn: 'Grey-blue',
    approxO2: '~ 5000 ppm', o2Ppm: 5000, verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 9, swatch: Color(0xFF555555),
    namePl: 'Szary', nameEn: 'Grey',
    approxO2: '~ 12 500 ppm', o2Ppm: 12500, verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 10, swatch: Color(0xFF1A1A1A),
    namePl: 'Czarny / łuska tlenkowa', nameEn: 'Black / oxide scale',
    approxO2: '~ 25 000 ppm', o2Ppm: 25000, verdict: HeatTintVerdict.reject),
];

/// The AWS D18.2 sample whose O₂ is nearest to [ppm] on a log scale (the
/// samples are spaced roughly geometrically). Below sample 1 → 1, above
/// sample 10 → 10. Indicative only — the chart is judged by colour.
HeatTintLevel heatTintLevelForO2Ppm(double ppm) {
  if (!(ppm > 0)) return kHeatTintLevels.first;
  final x = math.log(ppm);
  var best = kHeatTintLevels.first;
  var bestDist = double.infinity;
  for (final l in kHeatTintLevels) {
    final d = (math.log(l.o2Ppm) - x).abs();
    if (d < bestDist) {
      best = l;
      bestDist = d;
    }
  }
  return best;
}
