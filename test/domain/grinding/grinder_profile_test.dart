// „Moje szlifierki” — JSON: zapis i odczyt bez strat, uszkodzony zapis
// nigdy nie rzuca i mówi, że coś stracono (lossy), błędne wpisy pomijane,
// nieznany gwint zerowany.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/domain/grinding/grinding_check.dart';

const _a = GrinderProfile(
    id: 'a',
    name: 'Bosch 125',
    maxRpm: 11000,
    diameterMm: 125,
    thread: SpindleThread.m14);
const _b = GrinderProfile(id: 'b', name: 'Duża', maxRpm: 6600, diameterMm: 230);

void main() {
  test('zapis i odczyt bez strat', () {
    final d = decodeGrinders(encodeGrinders([_a, _b]));
    expect(d.lossy, isFalse);
    expect(d.grinders, [_a, _b]);
  });

  test('nieczytelny JSON albo nie-lista → pusta lista i lossy', () {
    for (final raw in ['{"id":', 'null', '{"a":1}', '42', '']) {
      final d = decodeGrinders(raw);
      expect(d.grinders, isEmpty, reason: raw);
      expect(d.lossy, isTrue, reason: raw);
    }
  });

  test('błędne wpisy pominięte, reszta zostaje, lossy', () {
    final raw = jsonEncode([
      _a.toJson(),
      {'id': 'x', 'name': 'bez obrotów', 'd': 125},
      {'id': 'y', 'name': 'zła średnica', 'rpm': 11000, 'd': 1250},
      {'id': 'z', 'name': 'ułamek obrotów', 'rpm': 11000.5, 'd': 125},
      {'id': 'a', 'name': 'duplikat', 'rpm': 9000, 'd': 125},
      'tekst',
      _b.toJson(),
    ]);
    final d = decodeGrinders(raw);
    expect(d.lossy, isTrue);
    expect(d.grinders.map((g) => g.id), ['a', 'b']);
    expect(d.grinders.first.name, 'Bosch 125');
  });

  test('nieznany gwint → bez gwintu, lossy', () {
    final raw = jsonEncode([
      {'id': 'a', 'name': 'X', 'rpm': 11000, 'd': 125, 'thread': 'M18'},
    ]);
    final d = decodeGrinders(raw);
    expect(d.lossy, isTrue);
    expect(d.grinders.single.thread, isNull);
    expect(d.grinders.single.maxRpm, 11000);
  });

  test('obroty zapisane jako 11000.0 i pusta nazwa → poprawny wpis', () {
    final raw = jsonEncode([
      {'id': 'a', 'name': '  ', 'rpm': 11000.0, 'd': 125},
    ]);
    final d = decodeGrinders(raw);
    expect(d.lossy, isFalse);
    expect(d.grinders.single.maxRpm, 11000);
    expect(d.grinders.single.name, 'Ø125 · 11${kNbsp}000');
  });

  test('nazwa domyślna PL i EN', () {
    expect(GrinderProfile.defaultName(125, 11000, en: false),
        'Ø125 · 11${kNbsp}000');
    expect(GrinderProfile.defaultName(115, 11500, en: true), 'Ø115 · 11,500');
  });
}
