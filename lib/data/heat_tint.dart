import 'package:flutter/material.dart';

// Weld discoloration ("heat tint") reference for the inside of austenitic
// stainless tube, modelled on AWS D18.1 / D18.2 sample discoloration levels.
//
// The colour an inside weld bead takes is driven by the oxygen left in the
// backing (purge) gas while the metal is hot. More O₂ → darker oxide. A
// food/pharma welder reads the bead, names the level and decides whether it
// passes — this screen is that decision, offline, on site.
//
// The ppm values are APPROXIMATE correlations: real acceptance is whatever
// the project specification / WPS calls out. The screen says so plainly.

class HeatTintLevel {
  final int level;          // 1 (best) … 10 (worst)
  final Color swatch;       // representative oxide colour
  final String namePl;
  final String nameEn;
  final String approxO2;    // approximate backing-gas O₂ band
  final HeatTintVerdict verdict;

  const HeatTintLevel({
    required this.level,
    required this.swatch,
    required this.namePl,
    required this.nameEn,
    required this.approxO2,
    required this.verdict,
  });
}

enum HeatTintVerdict { pharma, food, marginal, reject }

const List<HeatTintLevel> kHeatTintLevels = [
  HeatTintLevel(
    level: 1, swatch: Color(0xFFD9D9D9),
    namePl: 'Srebrny / bez przebarwień', nameEn: 'Silver / no tint',
    approxO2: '< 15 ppm', verdict: HeatTintVerdict.pharma),
  HeatTintLevel(
    level: 2, swatch: Color(0xFFE8D48A),
    namePl: 'Słomkowy', nameEn: 'Light straw',
    approxO2: '~ 25 ppm', verdict: HeatTintVerdict.pharma),
  HeatTintLevel(
    level: 3, swatch: Color(0xFFC9A03A),
    namePl: 'Ciemnozłoty', nameEn: 'Dark gold',
    approxO2: '~ 50 ppm', verdict: HeatTintVerdict.food),
  HeatTintLevel(
    level: 4, swatch: Color(0xFF9C6B2E),
    namePl: 'Brąz', nameEn: 'Bronze',
    approxO2: '~ 75 ppm', verdict: HeatTintVerdict.food),
  HeatTintLevel(
    level: 5, swatch: Color(0xFF8B4A5C),
    namePl: 'Czerwono-fioletowy', nameEn: 'Red-purple',
    approxO2: '~ 110 ppm', verdict: HeatTintVerdict.marginal),
  HeatTintLevel(
    level: 6, swatch: Color(0xFF6B4A8B),
    namePl: 'Fioletowy', nameEn: 'Purple',
    approxO2: '~ 175 ppm', verdict: HeatTintVerdict.marginal),
  HeatTintLevel(
    level: 7, swatch: Color(0xFF3A5A9C),
    namePl: 'Niebieski', nameEn: 'Blue',
    approxO2: '~ 250 ppm', verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 8, swatch: Color(0xFF4A5A6B),
    namePl: 'Szaroniebieski', nameEn: 'Grey-blue',
    approxO2: '~ 500 ppm', verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 9, swatch: Color(0xFF555555),
    namePl: 'Szary', nameEn: 'Grey',
    approxO2: '~ 1000 ppm', verdict: HeatTintVerdict.reject),
  HeatTintLevel(
    level: 10, swatch: Color(0xFF1A1A1A),
    namePl: 'Czarny / łuska tlenkowa', nameEn: 'Black / oxide scale',
    approxO2: 'brak osłony / no purge', verdict: HeatTintVerdict.reject),
];
