/// Teksty modułu „Ferryt i PMI” wspólne dla ekranu i protokołu do
/// udostępnienia (czysty Dart — testowalne bez Fluttera).
library;

import 'ferrite.dart';
import 'ferrite_pmi_protocol.dart';
import 'ferrite_pmi_sources.dart';
import 'pmi.dart';

String _t(bool en, String pl, String e) => en ? e : pl;

// ═══════════════════════════════════════════════════════════════════════════
// FERRYT
// ═══════════════════════════════════════════════════════════════════════════

String ferriteRuleLabel(FerriteRule r, {required bool en}) => switch (r) {
      FerriteRule.everyReading =>
        _t(en, 'Każdy odczyt w zakresie', 'Every reading in range'),
      FerriteRule.average =>
        _t(en, 'Średnia z N odczytów', 'Average of N readings'),
    };

String ferriteVerdictLabel(FerriteVerdict v, {required bool en}) =>
    switch (v) {
      FerriteVerdict.pass => _t(en, 'W ZAKRESIE', 'IN RANGE'),
      FerriteVerdict.fail => _t(en, 'POZA ZAKRESEM', 'OUT OF RANGE'),
      FerriteVerdict.none => _t(en, 'BRAK WERDYKTU', 'NO VERDICT'),
    };

String ferriteNoVerdictText(FerriteNoVerdict r,
        {required bool en, FerriteUnit? readingUnit, FerriteUnit? reqUnit,
        int? minCount, int? count}) =>
    switch (r) {
      FerriteNoVerdict.noReadings =>
        _t(en, 'brak odczytów', 'no readings'),
      FerriteNoVerdict.invalidReading => _t(
          en,
          'odczyt nieczytelny, ujemny albo > 100 % — popraw albo usuń',
          'a reading is unreadable, negative or > 100 % — fix or remove it'),
      FerriteNoVerdict.invalidRequirement => _t(
          en,
          'wpisz wymagany zakres ze specyfikacji (min i/lub max, min ≤ max)',
          'enter the required range from the specification (min and/or max, '
              'min ≤ max)'),
      FerriteNoVerdict.unknownPreset => _t(
          en,
          'zapisany preset nie istnieje w tej wersji aplikacji — wybierz '
              'zakres ponownie',
          'the saved preset does not exist in this app version — pick the '
              'range again'),
      FerriteNoVerdict.unitMismatch => _t(
          en,
          'odczyty w ${readingUnit?.symbol ?? '?'}, wymaganie '
              'w ${reqUnit?.symbol ?? '?'} — FN to nie % ferrytu, nie '
              'przeliczamy',
          'readings in ${readingUnit?.symbol ?? '?'}, requirement in '
              '${reqUnit?.symbol ?? '?'} — FN is not % ferrite, no '
              'conversion'),
      FerriteNoVerdict.invalidCount => _t(
          en,
          'wpisz minimalną liczbę odczytów ze specyfikacji (liczba '
              'całkowita ≥ 1; przy średniej — N)',
          'enter the minimum number of readings from the specification '
              '(whole number ≥ 1; for the average — N)'),
      FerriteNoVerdict.tooFewReadings => _t(
          en,
          'za mało odczytów: ${count ?? '?'} — specyfikacja wymaga '
              '≥ ${minCount ?? '?'} odczytów',
          'too few readings: ${count ?? '?'} — the specification requires '
              '≥ ${minCount ?? '?'} readings'),
      FerriteNoVerdict.notForLocation => _t(
          en,
          'wybrany zakres nie dotyczy tego miejsca — wpisz zakres ze '
              'specyfikacji',
          'the selected range does not apply to this location — enter the '
              'range from the specification'),
    };

/// Jedna linia wyniku miejsca (ekran i protokół).
String ferriteSiteSummary(FerriteSiteResult r, FerriteRequirement? req,
    {required bool en, required FerriteUnit readingUnit}) {
  final verdict = ferriteVerdictLabel(r.verdict, en: en);
  final parts = <String>[verdict];
  if (r.verdict == FerriteVerdict.none && r.reason != null) {
    parts.add(ferriteNoVerdictText(r.reason!,
        en: en,
        readingUnit: readingUnit,
        reqUnit: req?.unit,
        minCount: r.minCount,
        count: r.validCount));
  }
  final mean = r.mean;
  if (mean != null && req != null && req.isValid) {
    parts.add(_t(en, 'średnia ${ferriteFormatAgainst(mean, req, en: en)}',
        'mean ${ferriteFormatAgainst(mean, req, en: en)}'));
  }
  if (r.outOfRangeCount > 0) {
    parts.add(_t(
        en,
        'poza zakresem: ${r.outOfRangeCount} z ${r.values.length} odczytów',
        'out of range: ${r.outOfRangeCount} of ${r.values.length} readings'));
  }
  return parts.join(' · ');
}

// ═══════════════════════════════════════════════════════════════════════════
// PMI
// ═══════════════════════════════════════════════════════════════════════════

String pmiVerdictLabel(PmiVerdict v, {required bool en}) => switch (v) {
      PmiVerdict.conforming => _t(en, 'ZGODNY', 'CONFORMING'),
      PmiVerdict.conformingNoCarbon => _t(en, 'ZGODNY (bez weryfikacji C)',
          'CONFORMING (carbon not verified)'),
      PmiVerdict.toVerify => _t(en, 'DO WERYFIKACJI', 'TO BE VERIFIED'),
      PmiVerdict.nonConforming => _t(en, 'NIEZGODNY', 'NON-CONFORMING'),
      PmiVerdict.none => _t(en, 'BRAK WERDYKTU', 'NO VERDICT'),
    };

String pmiNoVerdictText(PmiNoVerdict r, {required bool en}) => switch (r) {
      PmiNoVerdict.noGrade => _t(en, 'wybierz wymagany gatunek i normę',
          'pick the required grade and standard'),
      PmiNoVerdict.missingKey => _t(
          en,
          'brak odczytu pierwiastka kluczowego',
          'a key element has no reading'),
      PmiNoVerdict.invalidInput => _t(
          en,
          'odczyt albo niepewność nieczytelne, ujemne albo > 100 %',
          'a reading or uncertainty is unreadable, negative or > 100 %'),
      PmiNoVerdict.sumOver100 => _t(
          en,
          'suma odczytów > 100 % — sprawdź przecinki we wpisach',
          'readings add up to > 100 % — check the decimal separators'),
    };

String pmiElementStatusLabel(PmiElementStatus s, {required bool en}) =>
    switch (s) {
      PmiElementStatus.inRange => _t(en, 'w zakresie', 'in range'),
      PmiElementStatus.toVerify =>
        _t(en, 'do weryfikacji (granica w niepewności)',
            'to verify (limit within uncertainty)'),
      PmiElementStatus.outOfRange => _t(en, 'poza zakresem', 'out of range'),
      PmiElementStatus.carbonDependent =>
        _t(en, 'zależy od C — potrzebny OES', 'depends on C — OES needed'),
      PmiElementStatus.missing => _t(en, 'brak odczytu', 'no reading'),
      PmiElementStatus.invalid => _t(en, 'nieczytelny', 'unreadable'),
      PmiElementStatus.notSpecified =>
        _t(en, 'norma nie podaje zakresu', 'no range in the standard'),
    };

/// Status pierwiastka z kontekstem gatunku — także dla pierwiastka spoza
/// składu („Mo 2,1 % — nie występuje w 1.4301 / 304 …; możliwy 1.4401 /
/// 316”) i kontrolnego bez odczytu („brak odczytu Mo — nie wyklucza 316”).
String pmiElementStatusText(PmiElementCheck c,
    {required PmiGrade grade, required bool en}) {
  final sym = c.element.symbol;
  final t = ferriteExact(pmiResidualThreshold(c.element), en: en);
  final value = ferriteRawText(c.readingText, en: en);
  final p = c.possibleGrade;
  return switch (c.note) {
    PmiCheckNote.residualAbove => _t(
        en,
        '$sym $value % — nie występuje w ${grade.title} (próg resztkowy '
            '$t %)${p == null ? '' : '; możliwy $p'}',
        '$sym $value % — not part of ${grade.title} (residual threshold '
            '$t %)${p == null ? '' : '; possibly $p'}'),
    PmiCheckNote.residualNear => _t(
        en,
        'do weryfikacji — $sym $value % ± u sięga progu resztkowego $t % '
            '(nie występuje w ${grade.title})${p == null ? '' : '; możliwy $p'}',
        'to verify — $sym $value % ± u reaches the residual threshold $t % '
            '(not part of ${grade.title})${p == null ? '' : '; possibly $p'}'),
    PmiCheckNote.controlMissing => _t(
        en,
        'do weryfikacji — brak odczytu $sym — nie wyklucza '
            '${p ?? 'gatunku z $sym'}',
        'to verify — no $sym reading — ${p ?? 'a grade with $sym'} not '
            'ruled out'),
    null => c.status == PmiElementStatus.missing
        ? _t(en, 'brak odczytu — pierwiastek wymagany (bez niego brak '
                'werdyktu)',
            'no reading — required element (no verdict without it)')
        : pmiElementStatusLabel(c.status, en: en),
  };
}

/// „Cr 16,9 ± 0,2 (wym. 16,5–18,5): w zakresie”.
String pmiCheckLine(PmiElementCheck c,
    {required PmiGrade grade, required bool en}) {
  final value = c.readingText.isEmpty
      ? '—'
      : c.uncertaintyText.isNotEmpty
          ? '${ferriteRawText(c.readingText, en: en)} ± '
              '${ferriteRawText(c.uncertaintyText, en: en)}'
          : ferriteRawText(c.readingText, en: en);
  final range = c.range == null
      ? ''
      : ' (${_t(en, 'wym.', 'req.')} ${c.range!.text(en: en)})';
  final key = c.key ? '*' : '';
  return '${c.element.symbol}$key $value$range: '
      '${pmiElementStatusText(c, grade: grade, en: en)}';
}

/// Podpowiedź „najbliższy gatunek z tabeli” — wyłącznie informacja.
String? pmiNearestText(PmiItem item, {required bool en, int max = 3}) {
  final matches = pmiNearestGrades(item.readings, kPmiGrades);
  if (matches.isEmpty) return null;
  final fits = matches.where((m) => m.fits).toList();
  String name(PmiMatch m) => '${m.grade.title} (${m.spec.standard})';
  if (fits.isNotEmpty) {
    final names = <String>[];
    for (final m in fits) {
      final n = name(m);
      if (!names.contains(n)) names.add(n);
      if (names.length >= max) break;
    }
    final more = fits.length > names.length
        ? _t(en, ' i inne', ' and others')
        : '';
    return _t(
        en,
        'Wpisane pierwiastki mieszczą się w: ${names.join('; ')}$more. Tylko '
            'informacja — gatunki różniące się C (np. 316 / 316L) XRF nie '
            'rozróżni.',
        'Entered elements fit: ${names.join('; ')}$more. Information only — '
            'grades differing in C (e.g. 316 / 316L) cannot be told apart by '
            'XRF.');
  }
  final best = matches.first;
  return _t(
      en,
      'Najbliższy w tabeli: ${name(best)} — odchyłka łącznie '
          '${ferriteExact(best.score, en: en)} % masy. Tylko informacja.',
      'Nearest in the table: ${name(best)} — total deviation '
          '${ferriteExact(best.score, en: en)} wt%. Information only.');
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOKÓŁ DO UDOSTĘPNIENIA
// ═══════════════════════════════════════════════════════════════════════════

String ferritePmiSubject({required bool en}) =>
    _t(en, 'Ferryt i PMI — protokół', 'Ferrite and PMI — record');

/// Zastrzeżenie na ekranie i w protokole.
String ferritePmiDisclaimer({required bool en}) => _t(
    en,
    'Aplikacja jest narzędziem pomocniczym. Wiążą: specyfikacja projektu '
        '(zakres ferrytu, jednostka, liczba odczytów, gatunek), norma '
        'przywołana w kontrakcie i procedura kontroli. Presety ferrytu to '
        'wartości TYPOWE — decyduje specyfikacja. FN ≠ % ferrytu. XRF nie '
        'mierzy węgla.',
    'This app is an aid. The project specification (ferrite range, unit, '
        'number of readings, grade), the standard invoked by the contract and '
        'the inspection procedure govern. Ferrite presets are TYPICAL values '
        '— the specification decides. FN ≠ % ferrite. XRF does not measure '
        'carbon.');

String _stamp(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Pełny tekst protokołu. [now] — chwila wygenerowania (wstrzykiwana).
String ferritePmiProtocolText(FerritePmiProtocol p,
    {required bool en, required DateTime now}) {
  final b = StringBuffer();
  void line([String s = '']) => b.writeln(s);
  line(_t(en, 'FERRYT I PMI — PROTOKÓŁ', 'FERRITE AND PMI — RECORD'));
  line('${_t(en, 'Data', 'Date')}: ${p.date}');
  if (p.title.trim().isNotEmpty) {
    line('${_t(en, 'Obiekt / spoina', 'Item / weld')}: ${p.title.trim()}');
  }
  if (p.inspector.trim().isNotEmpty) {
    line('${_t(en, 'Wykonał', 'Inspector')}: ${p.inspector.trim()}');
  }
  if (p.instrument.trim().isNotEmpty) {
    line('${_t(en, 'Przyrząd', 'Instrument')}: ${p.instrument.trim()}');
  }

  if (p.hasFerrite) {
    line();
    line(_t(en, '— FERRYT —', '— FERRITE —'));
    final req = p.requirement;
    final preset = p.preset;
    if (p.presetId.isNotEmpty && preset == null) {
      line(_t(en, 'Wymaganie: nieznany preset „${p.presetId}”',
          'Requirement: unknown preset “${p.presetId}”'));
    } else if (preset != null) {
      line('${_t(en, 'Wymaganie', 'Requirement')}: '
          '${preset.requirement.text(en: en)} — ${preset.title(en: en)}');
      line('  ${_t(en, 'Źródło', 'Source')}: ${preset.source(en: en)}');
      line('  ${_t(en, 'TYPOWE — decyduje specyfikacja projektu',
          'TYPICAL — the project specification governs')}');
    } else {
      line('${_t(en, 'Wymaganie (specyfikacja projektu)', 'Requirement (project specification)')}: '
          '${req != null && req.isValid ? req.text(en: en) : _t(en, 'nie wpisano / nieprawidłowe', 'not entered / invalid')}');
    }
    line('${_t(en, 'Jednostka odczytów', 'Reading unit')}: '
        '${p.readingUnit.label(en: en)}');
    final n = ferriteEffectiveMinCount(p.minCount,
        rule: p.rule, preset: p.preset);
    final rule = p.rule == FerriteRule.average
        ? '${ferriteRuleLabel(p.rule, en: en)} (N = ${n ?? '—'})'
        : '${ferriteRuleLabel(p.rule, en: en)} '
            '(${_t(en, 'min. odczytów na miejsce', 'min. readings per location')}: '
            '${n ?? '—'})';
    line('${_t(en, 'Reguła', 'Rule')}: $rule');
    var i = 0;
    for (final r in p.evaluateFerrite()) {
      if (r.site.isBlank) continue;
      i++;
      final label = r.site.label.trim();
      final where = label.isEmpty
          ? r.site.location.label(en: en)
          : '${r.site.location.label(en: en)} — $label';
      final readings = r.site.readings.isEmpty
          ? '—'
          : [
              for (final (k, v) in r.values.indexed)
                v == null
                    ? '„${r.site.readings[k]}” (${_t(en, 'nieczytelny', 'unreadable')})'
                    : ferriteRawText(r.site.readings[k], en: en),
            ].join('; ');
      line('$i. $where: $readings ${p.readingUnit.symbol}');
      line('   → '
          '${ferriteSiteSummary(r, req, en: en, readingUnit: p.readingUnit)}');
    }
    line('${_t(en, 'Wynik ferrytu', 'Ferrite result')}: '
        '${ferriteVerdictLabel(p.ferriteVerdict, en: en)}');
  }

  if (p.hasPmi) {
    line();
    line(_t(en, '— PMI (XRF) —', '— PMI (XRF) —'));
    var i = 0;
    for (final item in p.filledPmi) {
      i++;
      final r = item.evaluate();
      final label = item.label.trim().isEmpty ? '' : ' ${item.label.trim()}';
      final g = r.grade;
      final s = r.spec;
      line('$i.$label');
      line('   ${_t(en, 'Wymagany gatunek', 'Required grade')}: '
          '${g == null || s == null ? _t(en, 'nie wybrano', 'not selected') : '${g.title} — ${s.designation}, ${s.standard}'}');
      for (final c in r.checks) {
        line('   ${pmiCheckLine(c, grade: g!, en: en)}');
      }
      line('   ${_t(en, 'Werdykt', 'Verdict')}: '
          '${pmiVerdictLabel(r.verdict, en: en)}'
          '${r.reason == null ? '' : ' — ${pmiNoVerdictText(r.reason!, en: en)}'}');
      if (g != null && g.note(en: en).isNotEmpty) {
        line('   ${g.note(en: en)}');
      }
      final near = pmiNearestText(item, en: en);
      if (near != null) line('   $near');
    }
    line(_t(en, '* — pierwiastek wymagany (kluczowy albo z dolną granicą w normie).',
        '* — required element (key or with a lower limit in the standard).'));
    line(pmiCarbonNote(en: en));
  }

  if (p.notes.trim().isNotEmpty) {
    line();
    line('${_t(en, 'Uwagi', 'Notes')}: ${p.notes.trim()}');
  }
  line();
  line(ferritePmiDisclaimer(en: en));
  line();
  line('Fitter Welder Pro · ${_t(en, 'wygenerowano', 'generated')} '
      '${_stamp(now)}');
  return b.toString().trimRight();
}
