/// Teksty modułu „Tolerancje spoola”: nazwy pozycji i zestawów, opis
/// podstawy tolerancji („wobec czego oceniono”), braki danych, werdykty
/// i protokół tekstowy do udostępnienia.
///
/// Czysty Dart.
library;

import 'spool_check.dart';

/// Zastrzeżenie — na ekranie i w tekście protokołu.
String spoolCheckDisclaimer({required bool en}) => en
    ? 'Aid for the dimensional check — the binding tolerances are those of '
        'the design / purchase specification and the standard edition '
        'agreed for the job. Check built-in values against your copy of the '
        'standard.'
    : 'Pomoc przy kontroli wymiarów — wiążące są tolerancje z projektu / '
        'specyfikacji zamówienia i wydanie normy uzgodnione dla zadania. '
        'Wartości wbudowane porównaj z egzemplarzem normy.';

extension SpoolItemKindText on SpoolItemKind {
  String label({required bool en}) => switch (this) {
        SpoolItemKind.faceToFace =>
          en ? 'Face-to-face (F–F)' : 'Czoło–czoło (F–F)',
        SpoolItemKind.centerToFace =>
          en ? 'Center-to-face (C–F)' : 'Środek–czoło (C–F)',
        SpoolItemKind.centerToCenter =>
          en ? 'Center-to-center (C–C)' : 'Środek–środek (C–C)',
        SpoolItemKind.branchPosition => en
            ? 'Branch / attachment location'
            : 'Położenie odgałęzienia / uchwytu',
        SpoolItemKind.boltRotation =>
          en ? 'Flange bolt-hole rotation' : 'Skręt otworów kołnierza',
        SpoolItemKind.faceTilt =>
          en ? 'Flange face tilt' : 'Nachylenie czoła kołnierza',
        SpoolItemKind.branchOffset =>
          en ? 'Branch lateral offset' : 'Przesunięcie boczne odgałęzienia',
        SpoolItemKind.straightness =>
          en ? 'Straightness / bow' : 'Prostoliniowość / łuk',
      };

  /// Co wpisać jako „zmierzono”.
  String measuredLabel({required bool en}) => switch (this) {
        SpoolItemKind.faceToFace ||
        SpoolItemKind.centerToFace ||
        SpoolItemKind.centerToCenter ||
        SpoolItemKind.branchPosition =>
          en ? 'Measured' : 'Zmierzono',
        SpoolItemKind.boltRotation => en
            ? 'Hole offset along the bolt circle'
            : 'Przesunięcie otworu po obwodzie',
        SpoolItemKind.faceTilt =>
          en ? 'Deviation across the diameter' : 'Odchyłka na średnicy',
        SpoolItemKind.branchOffset =>
          en ? 'Lateral offset' : 'Przesunięcie boczne',
        SpoolItemKind.straightness =>
          en ? 'Bow (max. from the line)' : 'Strzałka łuku (max od żyłki)',
      };

  /// Opis średnicy / długości odniesienia (pole „base”) albo `null`.
  String? baseLabel({required bool en}) => switch (this) {
        SpoolItemKind.boltRotation =>
          en ? 'Bolt circle diameter (PCD)' : 'Średnica podziałowa (PCD)',
        SpoolItemKind.faceTilt =>
          en ? 'Diameter measured across' : 'Średnica, na której zmierzono',
        SpoolItemKind.straightness => en ? 'Length checked' : 'Długość odcinka',
        _ => null,
      };
}

extension SpoolToleranceSetText on SpoolToleranceSet {
  String label({required bool en}) => switch (this) {
        SpoolToleranceSet.pfiEs3 => 'PFI ES-3',
        SpoolToleranceSet.en13480 => 'EN 13480-4',
        SpoolToleranceSet.project => en ? 'Design' : 'Z projektu',
      };
}

/// „Wobec czego oceniono” dla całego protokołu.
String spoolSetBasisText(SpoolCheck c, {required bool en}) {
  switch (c.toleranceSet) {
    case null:
      return en
          ? 'tolerance set unreadable — choose it again'
          : 'zestaw tolerancji nieczytelny — wybierz ponownie';
    case SpoolToleranceSet.pfiEs3:
      return en
          ? 'PFI ES-3 (copies of the March 2004 revision; ES-03 R24 not '
              'checked)'
          : 'PFI ES-3 (kopie wyd. III 2004; ES-03 R24 niesprawdzone)';
    case SpoolToleranceSet.en13480:
      final g = c.enGrade.trim();
      final grade = g.isEmpty
          ? (en ? 'grade not stated' : 'klasa nie podana')
          : (en ? 'grade $g' : 'klasa $g');
      return en
          ? 'EN 13480-4:2017 Annex B, $grade — values entered by the user'
          : 'EN 13480-4:2017 zał. B, $grade — wartości wpisane przez '
              'użytkownika';
    case SpoolToleranceSet.project:
      return en
          ? 'design tolerances — values entered by the user'
          : 'tolerancje z projektu — wartości wpisane przez użytkownika';
  }
}

/// Podstawa tolerancji pozycji: „PFI ES-3, do 10″ (DN ≤ 250)”.
String spoolBasisText(SpoolTolerance t, {required bool en}) {
  switch (t.basis) {
    case null:
      return '—';
    case SpoolToleranceBasis.es3Linear:
      final band = t.band!;
      return 'PFI ES-3, ${band.sizeLabel(en: en)}';
    case SpoolToleranceBasis.es3Rotation:
      return en ? 'PFI ES-3, flange rotation' : 'PFI ES-3, obrót kołnierza';
    case SpoolToleranceBasis.es3Alignment:
      return en
          ? 'PFI ES-3, 3/64″ per ft or 1/32″'
          : 'PFI ES-3, 3/64″ na stopę lub 1/32″';
    case SpoolToleranceBasis.drawing:
      return en ? 'drawing / design (item)' : 'rysunek / projekt (pozycja)';
    case SpoolToleranceBasis.en13480:
      return en
          ? 'EN 13480-4 Annex B (entered)'
          : 'EN 13480-4 zał. B (wpisane)';
    case SpoolToleranceBasis.project:
      return en ? 'design (entered)' : 'projekt (wpisane)';
  }
}

/// Brak danych — po co wracać.
String spoolGapText(SpoolGap g, {required bool en}) => switch (g) {
      SpoolGap.noDrawing =>
        en ? 'no drawing dimension' : 'brak wymiaru z rysunku',
      SpoolGap.noMeasured => en ? 'no measurement' : 'brak pomiaru',
      SpoolGap.noPcd =>
        en ? 'no bolt circle diameter' : 'brak średnicy podziałowej',
      SpoolGap.noDiameter => en
          ? 'no diameter measured across'
          : 'brak średnicy, na której zmierzono',
      SpoolGap.noDn => en ? 'no DN (ES-3 band)' : 'brak DN (pasmo ES-3)',
      SpoolGap.dnBeyondEs3 => en
          ? 'above DN 900 ES-3 value not confirmed — enter the design '
              'tolerance'
          : 'powyżej DN 900 wartości ES-3 nie potwierdzono — wpisz '
              'tolerancję z projektu',
      SpoolGap.notInEs3 => en
          ? 'ES-3 gives no value — enter the design tolerance'
          : 'ES-3 nie podaje wartości — wpisz tolerancję z projektu',
      SpoolGap.noTolerance => en ? 'no tolerance entered' : 'brak tolerancji',
      SpoolGap.toleranceInvalid => en
          ? 'tolerance out of range (0–${kSpoolMaxToleranceMm.round()} mm)'
          : 'tolerancja poza zakresem (0–${kSpoolMaxToleranceMm.round()} mm)',
      SpoolGap.toleranceAsymIncomplete => en
          ? 'enter both parts of the tolerance: + and −'
          : 'wpisz obie wartości tolerancji: + i −',
      SpoolGap.toleranceDamaged => en
          ? 'saved tolerance unreadable — enter it again'
          : 'zapisana tolerancja nieczytelna — wpisz ponownie',
      SpoolGap.setUnreadable =>
        en ? 'tolerance set unreadable' : 'zestaw tolerancji nieczytelny',
    };

String spoolVerdictText(SpoolVerdict v, {required bool en}) => switch (v) {
      SpoolVerdict.ok => en ? 'within tolerance' : 'w tolerancji',
      SpoolVerdict.out => en ? 'OUT OF TOLERANCE' : 'POZA TOLERANCJĄ',
      SpoolVerdict.none => en ? 'no verdict' : 'brak werdyktu',
    };

/// Główny komunikat protokołu.
String spoolOverallText(SpoolCheckResult r, {required bool en}) {
  final n = r.items.length;
  switch (r.overall) {
    case SpoolOverall.empty:
      return en
          ? 'No measurement items — add items from the isometric.'
          : 'Brak pozycji pomiaru — dodaj pozycje z izometrii.';
    case SpoolOverall.out:
      final o = r.count(SpoolVerdict.out);
      return en
          ? 'Spool OUT OF TOLERANCE — $o of $n item(s). Do not ship before '
              'correction or a decision.'
          : 'Spool POZA TOLERANCJĄ — pozycje poza: $o z $n. Nie wysyłać '
              'przed poprawką albo decyzją.';
    case SpoolOverall.incomplete:
      final none = r.count(SpoolVerdict.none);
      return en
          ? 'No verdict for $none of $n item(s) — complete the data.'
          : 'Bez werdyktu: $none z $n poz. — uzupełnij dane.';
    case SpoolOverall.ok:
      return en
          ? 'Spool within tolerance — $n/$n item(s) checked.'
          : 'Spool w tolerancji — $n/$n poz. sprawdzonych.';
  }
}

/// Krótki stan na liście historii.
String spoolOverallShort(SpoolOverall o, {required bool en}) => switch (o) {
      SpoolOverall.ok => en ? 'Within tolerance' : 'W tolerancji',
      SpoolOverall.out => en ? 'Out of tolerance' : 'Poza tolerancją',
      SpoolOverall.incomplete => en ? 'Incomplete' : 'Niekompletny',
      SpoolOverall.empty => en ? 'No items' : 'Brak pozycji',
    };

/// Tolerancja do wyświetlenia: „±3 mm (≈0,118″)” albo niesymetryczna
/// „+0 mm (0″) / −3 mm (≈0,118″)”; brak — „—”.
String spoolToleranceText(SpoolTolerance t, SpoolUnit u, {required bool en}) {
  if (t.isAsymmetric) {
    return '+${spoolFormatBoth(t.plusMm!, u, en: en)} / '
        '−${spoolFormatBoth(t.minusMm!, u, en: en)}';
  }
  final mm = t.mm;
  return mm == null ? '—' : '±${spoolFormatBoth(mm, u, en: en)}';
}

/// Wiersz pozycji: „rysunek 1250 mm, zmierzono 1253,5 mm → odchyłka
/// +3,5 mm; tolerancja ±3 mm (PFI ES-3, …) → POZA TOLERANCJĄ”.
String spoolItemLine(SpoolItemResult r, SpoolUnit u, {required bool en}) {
  final it = r.item;
  String len(double mm) => spoolFormatLength(mm, u, en: en);
  final parts = <String>[];
  if (it.kind.isLinear) {
    parts.add('${en ? 'drawing' : 'rysunek'} '
        '${it.drawingMm == null ? '—' : len(it.drawingMm!)}');
    parts.add('${en ? 'measured' : 'zmierzono'} '
        '${it.measuredMm == null ? '—' : len(it.measuredMm!)}');
  } else if (it.kind == SpoolItemKind.boltRotation && it.rotationByAngle) {
    parts.add('${en ? 'angle' : 'kąt'} '
        '${it.angleDeg == null ? '—' : '${spoolNum(it.angleDeg!, en: en, decimals: 3)}°'}');
    parts.add('PCD ${it.baseMm == null ? '—' : len(it.baseMm!)}');
  } else {
    if (it.baseMm != null) {
      parts.add('${it.kind.baseLabel(en: en)} ${len(it.baseMm!)}');
    }
  }
  final dev = r.signedDeviationMm ?? r.deviationMm;
  final devText = dev == null
      ? '—'
      : it.kind.isLinear
          ? '${spoolFormatSigned(dev, u, en: en)}'
              '${u == SpoolUnit.inch ? ' (${spoolFormatMm(dev.abs(), en: en)})' : ''}'
          : spoolFormatBoth(dev, u, en: en);
  final t = r.tolerance;
  final tolText = t.known
      ? '${spoolToleranceText(t, u, en: en)} — ${spoolBasisText(t, en: en)}'
      : '—';
  final verdict = spoolVerdictText(r.verdict, en: en);
  final gaps = r.gaps.isEmpty
      ? ''
      : ' (${r.gaps.map((g) => spoolGapText(g, en: en)).join('; ')})';
  final head = parts.isEmpty ? '' : '${parts.join(', ')} → ';
  return '$head${en ? 'deviation' : 'odchyłka'} $devText; '
      '${en ? 'tolerance' : 'tolerancja'} $tolText → $verdict$gaps';
}

/// Tytuł pozycji: „Czoło–czoło (F–F) — F1–F2”.
String spoolItemTitle(SpoolItem it, {required bool en}) {
  final l = it.label.trim();
  return l.isEmpty ? it.kind.label(en: en) : '${it.kind.label(en: en)} — $l';
}

/// Tytuł protokołu na liście: numer spoola, inaczej izometria.
String spoolCheckTitle(SpoolCheck c, {required bool en}) {
  final s = c.spoolNo.trim();
  if (s.isNotEmpty) return s;
  final iso = c.isoNo.trim();
  if (iso.isNotEmpty) return iso;
  return en ? '(no spool no.)' : '(bez numeru spoola)';
}

String spoolCheckSubject({required bool en}) => en
    ? 'Spool dimensional check — record'
    : 'Tolerancje spoola — protokół kontroli wymiarów';

String _orDash(String s) => s.trim().isEmpty ? '—' : s.trim();

/// Protokół tekstowy do udostępnienia (komunikator, e-mail).
String spoolCheckProtocolText(SpoolCheck c, {required bool en}) {
  final r = c.evaluate();
  final u = c.unit;
  final b = StringBuffer()
    ..writeln(en
        ? 'SPOOL DIMENSIONAL CHECK — RECORD'
        : 'TOLERANCJE SPOOLA — PROTOKÓŁ KONTROLI WYMIARÓW')
    ..writeln()
    ..writeln('${en ? 'Spool no.' : 'Nr spoola'}: ${_orDash(c.spoolNo)}')
    ..writeln('${en ? 'Isometric' : 'Izometria'}: ${_orDash(c.isoNo)}')
    ..writeln('${en ? 'Drawing / rev.' : 'Rysunek / rewizja'}: '
        '${_orDash(c.drawingNo)} / ${_orDash(c.revision)}')
    ..writeln('${en ? 'Date' : 'Data'}: ${_orDash(c.date)}')
    ..writeln('${en ? 'Measured by' : 'Mierzył'}: ${_orDash(c.inspector)}')
    ..writeln('DN: ${c.dn?.toString() ?? '—'}')
    ..writeln('${en ? 'Tolerances' : 'Tolerancje'}: '
        '${spoolSetBasisText(c, en: en)}')
    ..writeln(en
        ? 'Verdict computed in mm; |deviation| = tolerance → within.'
        : 'Werdykt liczony w mm; |odchyłka| = tolerancja → w tolerancji.')
    ..writeln()
    ..writeln('${en ? 'VERDICT' : 'WERDYKT'}: ${spoolOverallText(r, en: en)}')
    ..writeln()
    ..writeln(en ? 'ITEMS' : 'POZYCJE');
  if (r.items.isEmpty) {
    b.writeln(en ? '— none —' : '— brak —');
  } else {
    for (final (i, ir) in r.items.indexed) {
      b.writeln('${i + 1}. ${spoolItemTitle(ir.item, en: en)}: '
          '${spoolItemLine(ir, u, en: en)}');
      final note = ir.item.note.trim();
      if (note.isNotEmpty) b.writeln('   ${en ? 'Note' : 'Uwaga'}: $note');
    }
  }
  if (c.notes.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('${en ? 'Notes' : 'Uwagi'}: ${c.notes.trim()}');
  }
  b
    ..writeln()
    ..writeln(en ? 'SOURCES' : 'ŹRÓDŁA');
  for (final s in kSpoolCheckSources) {
    b.writeln('- ${s.label(en: en)}');
  }
  b
    ..writeln()
    ..writeln(spoolCheckDisclaimer(en: en))
    ..write('Fitter Welder Pro');
  return b.toString();
}
