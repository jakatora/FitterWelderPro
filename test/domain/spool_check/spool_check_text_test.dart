// Teksty „Tolerancji spoola”: protokół do udostępnienia (PL/EN), podstawa
// oceny, źródła z wydaniem i spójność wartości ES-3 z kodem.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/domain/spool_check/spool_check_text.dart';

SpoolCheck _filled() => const SpoolCheck(
      id: 'c1',
      spoolNo: '100-P-1203-S02',
      isoNo: 'ISO-1203',
      drawingNo: 'D-77',
      revision: 'C',
      date: '2026-10-18',
      inspector: 'Jan Kowalski',
      dn: 150,
      items: [
        SpoolItem(
            id: 'a',
            kind: SpoolItemKind.faceToFace,
            label: 'F1–F2',
            drawingMm: 1250,
            measuredMm: 1253.5),
        SpoolItem(
            id: 'b',
            kind: SpoolItemKind.boltRotation,
            label: 'F2',
            measuredMm: 1.2),
        SpoolItem(id: 'c', kind: SpoolItemKind.straightness, measuredMm: 2),
      ],
      notes: 'Do poprawki: skrócić F1.',
    );

void main() {
  test(
      'protokół tekstowy: nagłówek, werdykt, podstawa oceny, pozycje i '
      'źródła (PL)', () {
    final t = spoolCheckProtocolText(_filled(), en: false);
    expect(t, startsWith('TOLERANCJE SPOOLA — PROTOKÓŁ KONTROLI WYMIARÓW'));
    expect(t, contains('Nr spoola: 100-P-1203-S02'));
    expect(t, contains('Rysunek / rewizja: D-77 / C'));
    expect(t, contains('Mierzył: Jan Kowalski'));
    expect(t, contains('Tolerancje: PFI ES-3 (kopie wyd. III 2004'));
    expect(t, contains('WERDYKT: Spool POZA TOLERANCJĄ — pozycje poza: 1 z 3'));
    expect(
        t,
        contains('1. Czoło–czoło (F–F) — F1–F2: rysunek 1250 mm, zmierzono '
            '1253,5 mm → odchyłka +3,5 mm; tolerancja ±3 mm (≈0,118″) — '
            'PFI ES-3, do 10″ (DN ≤ 250) → POZA TOLERANCJĄ'));
    expect(t, contains('2. Skręt otworów kołnierza — F2:'));
    expect(
        t,
        contains('±1,5875 mm (1/16″) — PFI ES-3, obrót kołnierza → '
            'w tolerancji'));
    expect(t, contains('3. Prostoliniowość / łuk: odchyłka 2 mm'));
    expect(
        t,
        contains('brak werdyktu (ES-3 nie podaje wartości — wpisz '
            'tolerancję z projektu)'));
    expect(t, contains('Uwagi: Do poprawki: skrócić F1.'));
    expect(t, contains('ŹRÓDŁA'));
    expect(t, contains('EN 13480-4:2017'));
    expect(t, endsWith('Fitter Welder Pro'));
  });

  test('protokół tekstowy po angielsku — cale z mm w nawiasie', () {
    final t = spoolCheckProtocolText(_filled().copyWith(unit: SpoolUnit.inch),
        en: true);
    expect(t, startsWith('SPOOL DIMENSIONAL CHECK — RECORD'));
    expect(t, contains('VERDICT: Spool OUT OF TOLERANCE — 1 of 3 item(s).'));
    expect(
        t,
        contains('deviation +≈0.138″ (3.5 mm); tolerance ±≈0.118″ '
            '(3 mm) — PFI ES-3, up to 10″ (DN ≤ 250) → OUT OF TOLERANCE'));
    expect(t, contains('Verdict computed in mm'));
  });

  test('podstawa oceny: EN 13480-4 z klasą, projekt, nieczytelny zestaw', () {
    final c = _filled();
    expect(
        spoolSetBasisText(
            c.copyWith(toleranceSet: SpoolToleranceSet.en13480, enGrade: '2'),
            en: false),
        'EN 13480-4:2017 zał. B, klasa 2 — wartości wpisane przez '
        'użytkownika');
    expect(
        spoolSetBasisText(c.copyWith(toleranceSet: SpoolToleranceSet.en13480),
            en: true),
        contains('grade not stated'));
    expect(
        spoolSetBasisText(c.copyWith(toleranceSet: SpoolToleranceSet.project),
            en: false),
        'tolerancje z projektu — wartości wpisane przez użytkownika');
    expect(spoolSetBasisText(c.copyWith(toleranceSet: null), en: false),
        contains('nieczytelny'));
  });

  test(
      'każda wartość ES-3 w kodzie ma źródło z wydaniem (PL i EN); '
      'EN 13480-4 bez wbudowanych wartości', () {
    final pl = kSpoolCheckSources.map((s) => s.pl).join('\n');
    final en = kSpoolCheckSources.map((s) => s.en).join('\n');
    for (final b in kEs3LinearBands) {
      final f = '±${spoolInchFraction(b.inch)}″';
      final metricEn = '(${b.metricMm.toStringAsFixed(1)} mm)';
      final metricPl = metricEn.replaceAll('.', ',');
      expect(pl, contains(f));
      expect(en, contains(f));
      expect(pl, contains(metricPl), reason: metricPl);
      expect(en, contains(metricEn), reason: metricEn);
    }
    for (final text in [pl, en]) {
      expect(text, contains('3/64″'));
      expect(text, contains('1/32″'));
      expect(text, contains('1/16″'));
      expect(text, contains('2004'));
      expect(text, contains('ES-03 R24 (2024)'));
      expect(text, contains('EN 13480-4:2017'));
    }
    expect(spoolInchFraction(kEs3RotationInch), '1/16');
    expect(spoolInchFraction(kEs3AlignPerFootInch), '3/64');
    expect(spoolInchFraction(kEs3AlignMinInch), '1/32');
    // Ściąga „jak mierzyć” — praktyka, po polsku i angielsku.
    expect(kSpoolHowToMeasure, isNotEmpty);
    for (final s in kSpoolHowToMeasure) {
      expect(s.pl, isNotEmpty);
      expect(s.en, isNotEmpty);
    }
  });

  test('wiersz pozycji bez danych mówi, czego brakuje', () {
    const c = SpoolCheck(id: 'x', date: '2026-10-18', items: [
      SpoolItem(id: 'a', kind: SpoolItemKind.centerToFace),
    ]);
    final line =
        spoolItemLine(c.evaluate().items.single, SpoolUnit.mm, en: false);
    expect(line, contains('rysunek —, zmierzono —'));
    expect(line, contains('brak werdyktu'));
    expect(line, contains('brak wymiaru z rysunku'));
    expect(line, contains('brak pomiaru'));
    expect(line, contains('brak DN (pasmo ES-3)'));
  });
}
