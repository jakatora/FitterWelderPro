// Strażnik czytelności w słońcu: kontrast tokenów tekstu wg WCAG 2.x.
//
// Monter czyta etykiety i jednostki na rusztowaniu, w pełnym słońcu. Próg AA
// dla zwykłego tekstu to 4,5:1. Stary kTextMut (#5A6478) miał 3,25:1 na tle
// i 2,98:1 na karcie, a biały tekst na bursztynowym FAB-ie 2,30:1.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/theme/app_theme.dart';

/// Składowa sRGB (0..1) → liniowa, wg WCAG 2.x.
double _linear(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Luminancja względna wg WCAG 2.x.
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// Współczynnik kontrastu (1..21).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const double kAaNormalText = 4.5;

void main() {
  group('funkcja kontrastu', () {
    test('zgadza się z luminancją Fluttera i znanymi wartościami', () {
      for (final c in [kBg, kCard, kText, kTextSec, kTextMut, kArc]) {
        expect(relativeLuminance(c), closeTo(c.computeLuminance(), 1e-3));
      }
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(kArc, kArc), closeTo(1, 1e-9));
      // Wartości z raportu audytu — pinują, że liczymy tak samo jak on.
      expect(contrastRatio(const Color(0xFF5A6478), kBg), closeTo(3.25, 0.01));
      expect(contrastRatio(const Color(0xFF5A6478), kCard), closeTo(2.98, 0.01));
      expect(contrastRatio(Colors.white, kArc), closeTo(2.30, 0.01));
    });
  });

  group('tokeny tekstu na tle i karcie', () {
    final surfaces = {'kBg': kBg, 'kCard': kCard};
    final texts = {'kText': kText, 'kTextSec': kTextSec, 'kTextMut': kTextMut};

    for (final t in texts.entries) {
      for (final s in surfaces.entries) {
        test('${t.key} na ${s.key} ≥ 4,5:1', () {
          final ratio = contrastRatio(t.value, s.value);
          expect(ratio, greaterThanOrEqualTo(kAaNormalText),
              reason: '${t.key} na ${s.key}: ${ratio.toStringAsFixed(2)}:1');
        });
      }
    }

    test('kTextMut ma dokładnie te współczynniki, które opisuje komentarz', () {
      expect(contrastRatio(kTextMut, kBg), closeTo(6.03, 0.01));
      expect(contrastRatio(kTextMut, kCard), closeTo(5.54, 0.01));
    });

    test('hierarchia zostaje: kTextMut ciemniejszy od kTextSec', () {
      expect(contrastRatio(kTextMut, kBg), lessThan(contrastRatio(kTextSec, kBg)));
    });
  });

  group('tekst na bursztynie (kArc)', () {
    final theme = buildAppTheme();

    test('FAB: ciemny tekst ≥ 4,5:1', () {
      final fab = theme.floatingActionButtonTheme;
      expect(contrastRatio(fab.foregroundColor!, fab.backgroundColor!),
          greaterThanOrEqualTo(kAaNormalText));
    });

    test('zaznaczony segment SegmentedButton ≥ 4,5:1', () {
      final style = theme.segmentedButtonTheme.style!;
      const selected = {WidgetState.selected};
      final fg = style.foregroundColor!.resolve(selected)!;
      final bg = style.backgroundColor!.resolve(selected)!;
      expect(bg, kArc);
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(kAaNormalText));
    });

    test('niezaznaczony segment ≥ 4,5:1', () {
      final style = theme.segmentedButtonTheme.style!;
      const none = <WidgetState>{};
      expect(
        contrastRatio(style.foregroundColor!.resolve(none)!,
            style.backgroundColor!.resolve(none)!),
        greaterThanOrEqualTo(kAaNormalText),
      );
    });

    test('przycisk główny (ElevatedButton) ≥ 4,5:1', () {
      final style = theme.elevatedButtonTheme.style!;
      final fg = style.foregroundColor!.resolve(<WidgetState>{})!;
      final bg = style.backgroundColor!.resolve(<WidgetState>{})!;
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(kAaNormalText));
    });
  });

  test('cel dotyku z motywu ma co najmniej 48 dp', () {
    expect(kMinTapTarget, greaterThanOrEqualTo(48));
  });

  // Ekrany z tego zakresu korzystają z tokenu, a nie z własnej kopii starej
  // wartości — inaczej zmiana tokenu by ich nie dotknęła.
  test('ekrany startowe i menu nie trzymają kopii starego #5A6478', () {
    const files = [
      'lib/screens/home_screen.dart',
      'lib/screens/onboarding_name_screen.dart',
      'lib/screens/consent_screen.dart',
      'lib/screens/fitter_menu_screen.dart',
      'lib/screens/welder_menu_screen.dart',
      'lib/screens/profile_screen.dart',
      'lib/widgets/tool_tiles.dart',
    ];
    for (final path in files) {
      final src = File(path).readAsStringSync().toUpperCase();
      expect(src.contains('0XFF5A6478'), isFalse, reason: path);
    }
  });
}
