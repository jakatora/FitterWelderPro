// Odczyt symbolu spoiny „po ludzku” — zdanie dla spawacza i notatki, co
// znaczy każdy element rysunku. Czysty Dart; język przez parametr [en].
//
// Przykład (PL): „Spoina pachwinowa a5 po stronie strzałki, przerywana
// 3 × 50 (100), dookoła, montażowa.”
//
// Zapis wymiarów wg EN ISO 2553:2019:
//   • PRZED symbolem wymiar przekroju: a (grubość obliczeniowa) albo z
//     (długość boku) przy pachwinie — litera + liczba, np. a5, z7; przy
//     spoinie czołowej sama liczba = głębokość wtopienia (np. „8” przed V);
//     brak liczby przy czołowej = pełny przetop;
//   • ZA symbolem długość spoiny albo n × l (e) przy przerywanej: n odcinków
//     po l, e = odstęp (prześwit) między sąsiednimi odcinkami; bez n układ
//     l (e) biegnie przez całe złącze; nic za symbolem = spoina ciągła na
//     całej długości złącza;
//   • przestawna (po obu stronach): znak Z między n × l i (e) — wg EN ISO
//     2553:2013 (zasada przestawienia zachowana w wydaniu 2019);
//   • w rozwidleniu (ogonie): numer procesu wg EN ISO 4063 i inne odwołania,
//     rozdzielone ukośnikiem.

import '../qualification/weld_process.dart';
import 'fillet_throat.dart';
import 'weld_symbol.dart';

/// Teksty wymiarów rysowane przy symbolu.
class WeldSymbolNotation {
  const WeldSymbolNotation({
    required this.size,
    required this.right,
    required this.rightLead,
    required this.rightGap,
    required this.tail,
  });

  /// Przed symbolem, np. „a5”, „z7”, „8”; pusty, gdy brak wymiaru.
  final String size;

  /// Za symbolem w całości, np. „300” albo „3 × 50 (100)”; pusty, gdy brak.
  final String right;

  /// Przerywana: część przed odstępem — „3 × 50” albo „50” (bez n).
  final String rightLead;

  /// Przerywana: odstęp w nawiasie — „(100)”.
  final String rightGap;

  /// W rozwidleniu (ogonie), np. „111/WPS-01”; pusty = bez rozwidlenia.
  final String tail;
}

/// Wynik odczytu: zdanie, objaśnienia elementów i ostrzeżenia o niepełnym
/// albo sprzecznym zapisie.
class WeldSymbolReading {
  const WeldSymbolReading({
    required this.sentence,
    required this.notes,
    required this.warnings,
  });

  final String sentence;
  final List<String> notes;
  final List<String> warnings;
}

String _mm(double v, bool en) => formatWeldMm(v, en: en);

/// „odcinek / odcinki / odcinków” — odmiana po liczbie.
String segmentsPl(int n) {
  if (n == 1) return 'odcinek';
  final last = n % 10, lastTwo = n % 100;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return 'odcinki';
  }
  return 'odcinków';
}

/// Pełna nazwa rodzaju spoiny (początek zdania).
String weldKindName(WeldKind kind, {required bool en}) => switch (kind) {
      WeldKind.fillet => en ? 'Fillet weld' : 'Spoina pachwinowa',
      WeldKind.squareButt => en ? 'Square butt weld' : 'Spoina na I',
      WeldKind.singleV => en ? 'Single-V butt weld' : 'Spoina na V',
      WeldKind.singleBevel => en ? 'Single-bevel butt weld' : 'Spoina na ½V',
      WeldKind.singleVRootFace =>
        en ? 'Single-V butt weld with broad root face' : 'Spoina na Y',
      WeldKind.singleBevelRootFace =>
        en ? 'Single-bevel butt weld with broad root face' : 'Spoina na ½Y',
      WeldKind.singleU => en ? 'Single-U butt weld' : 'Spoina na U',
      WeldKind.singleJ => en ? 'Single-J butt weld' : 'Spoina na ½U (J)',
      WeldKind.backingRun =>
        en ? 'Back run / backing weld' : 'Ścieg od strony grani (podpawanie)',
      WeldKind.plug => en ? 'Plug or slot weld' : 'Spoina otworowa',
      WeldKind.spot => en ? 'Spot weld' : 'Spoina punktowa',
      WeldKind.seam => en ? 'Seam weld' : 'Spoina liniowa',
      WeldKind.surfacing => en ? 'Surfacing' : 'Napawanie',
      WeldKind.edge => en ? 'Edge weld' : 'Spoina brzeżna',
    };

/// Krótka etykieta do przycisku wyboru w kreatorze.
String weldKindChip(WeldKind kind, {required bool en}) => switch (kind) {
      WeldKind.fillet => en ? 'Fillet' : 'Pachwinowa',
      WeldKind.squareButt => 'I',
      WeldKind.singleV => 'V',
      WeldKind.singleBevel => '½V',
      WeldKind.singleVRootFace => 'Y',
      WeldKind.singleBevelRootFace => '½Y',
      WeldKind.singleU => 'U',
      WeldKind.singleJ => en ? 'J' : '½U (J)',
      _ => weldKindName(kind, en: en),
    };

/// Strona złącza słowami (część zdania).
String weldSideText(WeldSide side, {required bool en}) => switch (side) {
      WeldSide.arrow => en ? 'on the arrow side' : 'po stronie strzałki',
      WeldSide.other => en ? 'on the other side' : 'po stronie przeciwnej',
      WeldSide.both => en ? 'on both sides' : 'po obu stronach',
    };

/// Co widać na rysunku dla danej strony — etykieta wyboru w kreatorze
/// (czytnik: użytkownik wskazuje, GDZIE stoi symbol, aplikacja mówi, co to
/// znaczy).
String sideAsDrawn(SymbolSystem system, WeldSide side, {required bool en}) =>
    switch ((system, side)) {
      (SymbolSystem.a, WeldSide.arrow) =>
        en ? 'On the solid line' : 'Na linii ciągłej',
      (SymbolSystem.a, WeldSide.other) =>
        en ? 'On the dashed line' : 'Na linii przerywanej',
      (SymbolSystem.a, WeldSide.both) => en
          ? 'Both sides of the line, no dashed line'
          : 'Po obu stronach linii, bez przerywanej',
      (SymbolSystem.b, WeldSide.arrow) => en ? 'Below the line' : 'Pod linią',
      (SymbolSystem.b, WeldSide.other) => en ? 'Above the line' : 'Nad linią',
      (SymbolSystem.b, WeldSide.both) =>
        en ? 'Above and below the line' : 'Nad i pod linią',
    };

String _contourText(WeldContour c, bool en) => switch (c) {
      WeldContour.flat => en ? 'flat (flush) face' : 'lico płaskie',
      WeldContour.convex => en ? 'convex face' : 'lico wypukłe',
      WeldContour.concave => en ? 'concave face' : 'lico wklęsłe',
      WeldContour.none => '',
    };

String _backingText(BackingStrip b, bool en) => switch (b) {
      BackingStrip.permanent =>
        en ? 'on a permanent backing strip (M)' : 'na podkładce stałej (M)',
      BackingStrip.removable =>
        en ? 'on a removable backing strip (MR)' : 'na podkładce usuwanej (MR)',
      BackingStrip.none => '',
    };

/// Teksty wymiarów i rozwidlenia dla rysunku.
WeldSymbolNotation notationFor(WeldSymbolSpec s, {required bool en}) {
  final size =
      s.size != null && s.size! > 0 ? '${s.sizePrefix}${_mm(s.size!, en)}' : '';
  var right = '', lead = '', gap = '';
  if (s.intermittent) {
    if (s.intermittentComplete) {
      final l = _mm(s.elementLength!, en);
      lead = s.count == null ? l : '${s.count} × $l';
      gap = '(${_mm(s.gap!, en)})';
      right = '$lead $gap';
    }
  } else if (s.length != null && s.length! > 0) {
    right = _mm(s.length!, en);
  }
  final tail = [
    s.process.trim(),
    s.reference.trim(),
  ].where((t) => t.isNotEmpty).join('/');
  return WeldSymbolNotation(
      size: size, right: right, rightLead: lead, rightGap: gap, tail: tail);
}

/// Nazwa procesu z numeru EN ISO 4063 (np. „141” → TIG / GTAW), jeśli znany.
String? _processName(String process, bool en) {
  final n = int.tryParse(process.trim());
  if (n == null) return null;
  final family = familyOfIso4063(n);
  if (family == null) return null;
  return en ? family.asmeCode : family.euName;
}

/// Odczyt symbolu: zdanie, objaśnienia i ostrzeżenia.
WeldSymbolReading describeWeldSymbol(WeldSymbolSpec s, {required bool en}) {
  final n = notationFor(s, en: en);
  final notes = <String>[];
  final warnings = <String>[];
  final isFillet = s.kind == WeldKind.fillet;
  final hasSize = s.size != null && s.size! > 0;
  final stagger = s.staggered && s.staggerApplies;

  // ── Zdanie ────────────────────────────────────────────────────────────────
  final head = StringBuffer(weldKindName(s.kind, en: en));
  if (isFillet && hasSize) head.write(' ${n.size}');
  head.write(' ${weldSideText(s.side, en: en)}');

  final parts = <String>[head.toString()];
  if (s.kind.isGrooveButt) {
    parts.add(hasSize
        ? (en
            ? 'penetration depth ${_mm(s.size!, en)} mm'
            : 'głębokość wtopienia ${_mm(s.size!, en)} mm')
        : (en ? 'full penetration' : 'pełny przetop'));
  }
  if (s.intermittent) {
    if (s.intermittentComplete) {
      parts.add(en
          ? '${stagger ? 'staggered intermittent' : 'intermittent'} ${n.right}'
          : 'przerywana${stagger ? ' przestawna' : ''} ${n.right}');
    } else {
      parts.add(en ? 'intermittent' : 'przerywana');
    }
  } else if (n.right.isNotEmpty) {
    parts.add(en ? 'length ${n.right} mm' : 'długość ${n.right} mm');
  }
  if (s.contour != WeldContour.none) parts.add(_contourText(s.contour, en));
  if (s.backing != BackingStrip.none && s.backingApplies) {
    parts.add(_backingText(s.backing, en));
  }
  if (s.allAround) parts.add(en ? 'all around' : 'dookoła');
  if (s.fieldWeld) parts.add(en ? 'field weld' : 'montażowa');
  final process = s.process.trim();
  if (process.isNotEmpty) {
    final name = _processName(process, en);
    parts.add(en
        ? 'process $process${name == null ? '' : ' ($name)'}'
        : 'proces $process${name == null ? '' : ' ($name)'}');
  }
  final reference = s.reference.trim();
  if (reference.isNotEmpty) {
    parts.add(en ? 'see $reference' : 'wg $reference');
  }
  final sentence = '${parts.join(', ')}.';

  // ── Objaśnienia ─────────────────────────────────────────────────────────
  notes.add(_sideNote(s, en));

  if (s.oneMemberPrepared) {
    notes.add(en
        ? 'Only one edge is prepared: the arrow (with a break) points to the '
            'member that gets the bevel.'
        : 'Ukosowany jest tylko jeden brzeg: strzałka (łamana) wskazuje '
            'element, który trzeba ukosować.');
  }

  if (isFillet && hasSize) {
    final v = s.size!;
    if (s.filletSize == FilletSize.throat) {
      final z = legFromThroat(v)!;
      notes.add(en
          ? '${n.size} = design throat thickness ${_mm(v, en)} mm (height of '
              'the largest isosceles triangle inscribed in the weld). '
              'Equal-leg fillet: leg length z ≈ ${_mm(z, en)} mm.'
          : '${n.size} = grubość obliczeniowa ${_mm(v, en)} mm (wysokość '
              'największego trójkąta równoramiennego wpisanego w spoinę). '
              'Pachwina równoramienna: długość boku z ≈ ${_mm(z, en)} mm.');
    } else {
      final a = throatFromLeg(v)!;
      notes.add(en
          ? '${n.size} = leg length ${_mm(v, en)} mm. Equal-leg fillet: '
              'throat a ≈ ${_mm(a, en)} mm.'
          : '${n.size} = długość boku spoiny ${_mm(v, en)} mm. Pachwina '
              'równoramienna: grubość obliczeniowa a ≈ ${_mm(a, en)} mm.');
    }
  }
  if (s.kind.isGrooveButt) {
    notes.add(hasSize
        ? (en
            ? '${n.size} before the symbol = penetration depth '
                '${_mm(s.size!, en)} mm — the weld does not have to go '
                'through the full thickness. Older drawings (ISO 2553:1992) '
                'write it as s${n.size}.'
            : '${n.size} przed symbolem = głębokość wtopienia '
                '${_mm(s.size!, en)} mm — spoina nie musi przechodzić przez '
                'całą grubość. Na starszych rysunkach (ISO 2553:1992) zapis '
                's${n.size}.')
        : (en
            ? 'No number before a butt-weld symbol = full penetration.'
            : 'Brak liczby przed symbolem spoiny czołowej = pełny przetop.'));
  }
  if (s.side == WeldSide.both) {
    final twin = switch (s.kind) {
      WeldKind.singleV => 'X',
      WeldKind.singleBevel => 'K',
      _ => null,
    };
    if (twin != null) {
      notes.add(en
          ? 'The same symbol on both sides of the line = double-sided weld '
              '(often called an $twin weld).'
          : 'Ten sam symbol po obu stronach linii = spoina dwustronna '
              '(spoina na $twin).');
    }
  }
  if (s.intermittent && s.intermittentComplete) {
    final l = _mm(s.elementLength!, en);
    final e = _mm(s.gap!, en);
    final count = s.count;
    if (count != null) {
      notes.add(en
          ? '${n.right}: $count weld ${count == 1 ? 'segment' : 'segments'}, '
              '$l mm long each, $e mm gap between neighbouring segments.'
          : '${n.right}: $count ${segmentsPl(count)} spoiny po $l mm, '
              'odstęp między sąsiednimi odcinkami $e mm.');
    } else {
      notes.add(en
          ? '${n.right}: segments $l mm long with $e mm gaps, repeated along '
              'the whole joint (no n given).'
          : '${n.right}: odcinki po $l mm z odstępami $e mm na całej długości '
              'złącza (bez podanego n).');
    }
    if (stagger) {
      notes.add(en
          ? 'Z between the length and the gap = staggered: the centres of '
              'the segments on one side face the centres of the gaps on the '
              'other side.'
          : 'Znak Z między długością a odstępem = przestawna: środki odcinków '
              'po jednej stronie leżą naprzeciw środków przerw po drugiej.');
    } else if (s.side == WeldSide.both && isFillet) {
      notes.add(en
          ? 'No Z: the segments on both sides sit opposite each other '
              '(chain intermittent).'
          : 'Bez znaku Z: odcinki po obu stronach leżą naprzeciw siebie '
              '(spoina przerywana łańcuchowa).');
    }
  } else if (!s.intermittent && n.right.isEmpty) {
    notes.add(en
        ? 'No length after the symbol — the weld runs continuously along the '
            'whole joint.'
        : 'Brak długości za symbolem — spoina ciągła na całej długości '
            'złącza.');
  }
  if (s.contour != WeldContour.none) {
    notes.add(switch (s.contour) {
      WeldContour.flat => en
          ? 'Straight line over the symbol: flat (flush) face. If it must be '
              'ground or machined, the drawing says so separately.'
          : 'Kreska nad symbolem: lico płaskie. Jeśli trzeba je szlifować '
              'lub obrabiać, rysunek podaje to osobno.',
      WeldContour.convex => en
          ? 'Arc bulging outwards: convex face.'
          : 'Łuk wygięty na zewnątrz: lico wypukłe.',
      _ => en
          ? 'Arc dipping towards the symbol: concave face.'
          : 'Łuk wygięty do symbolu: lico wklęsłe.',
    });
  }
  if (s.backing != BackingStrip.none && s.backingApplies) {
    notes.add(s.backing == BackingStrip.permanent
        ? (en
            ? 'M in a box (on the root side of the line): permanent backing '
                'strip — it stays in the joint.'
            : 'M w prostokącie (po stronie grani): podkładka stała — '
                'zostaje w złączu.')
        : (en
            ? 'MR in a box (on the root side of the line): removable backing '
                'strip — taken off after welding.'
            : 'MR w prostokącie (po stronie grani): podkładka usuwana — '
                'zdejmowana po spawaniu.'));
  }
  if (s.allAround) {
    notes.add(en
        ? 'Circle at the arrow/reference-line junction: weld all around '
            '(e.g. a pipe or a section welded round its whole perimeter).'
        : 'Kółko na załamaniu strzałki: spoina dookoła (np. rura albo '
            'profil spawany po całym obwodzie).');
  }
  if (s.fieldWeld) {
    notes.add(en
        ? 'Flag: field (site) weld — made at the erection site, not in the '
            'shop.'
        : 'Chorągiewka: spoina montażowa — wykonywana na budowie / przy '
            'montażu, nie w warsztacie.');
  }
  if (n.tail.isNotEmpty) {
    notes.add(en
        ? 'Tail: ${n.tail} — welding process number to EN ISO 4063 and other '
            'references (e.g. WPS), separated by slashes.'
        : 'Rozwidlenie (ogon): ${n.tail} — numer procesu wg EN ISO 4063 '
            'i inne odwołania (np. WPS), rozdzielone ukośnikiem.');
  }

  // ── Ostrzeżenia ─────────────────────────────────────────────────────────
  if (s.intermittent && !s.intermittentComplete) {
    warnings.add(en
        ? 'Intermittent weld: enter l and e (and n, if it is on the drawing).'
        : 'Spoina przerywana: podaj l i e (oraz n, jeśli jest na '
            'rysunku).');
  }
  if (s.staggered && !s.staggerApplies) {
    warnings.add(en
        ? 'Staggered applies only to an intermittent fillet weld on both '
            'sides.'
        : 'Przestawienie dotyczy tylko przerywanej spoiny pachwinowej po '
            'obu stronach.');
  }
  if (s.backing != BackingStrip.none && !s.backingApplies) {
    warnings.add(en
        ? 'A backing strip applies to a butt weld welded from one side.'
        : 'Podkładka dotyczy spoiny czołowej spawanej z jednej strony.');
  }
  if (s.allAround && s.intermittent) {
    warnings.add(en
        ? 'EN ISO 2553 does not use the all-around circle for a '
            'non-continuous weld — check the drawing with the designer.'
        : 'EN ISO 2553 nie przewiduje kółka „dookoła” przy spoinie '
            'nieciągłej — wyjaśnij rysunek z projektantem.');
  }

  return WeldSymbolReading(
    sentence: sentence,
    notes: List.unmodifiable(notes),
    warnings: List.unmodifiable(warnings),
  );
}

String _sideNote(WeldSymbolSpec s, bool en) {
  switch (s.system) {
    case SymbolSystem.a:
      return switch (s.side) {
        WeldSide.arrow => en
            ? 'System A: symbol on the solid line = arrow side (the side of '
                'the joint the arrow touches). The dashed line only marks '
                'which line is which.'
            : 'System A: symbol na linii ciągłej = strona strzałki (ta strona '
                'złącza, którą dotyka strzałka). Linia przerywana tylko '
                'pokazuje, która linia jest która.',
        WeldSide.other => en
            ? 'System A: symbol on the dashed line = other side — the side '
                'of the joint opposite the arrow.'
            : 'System A: symbol na linii przerywanej = strona przeciwna — '
                'druga strona złącza niż ta, którą dotyka strzałka.',
        WeldSide.both => en
            ? 'System A: the same symbol and dimensions on both sides of the '
                'solid line, no dashed line = symmetric weld on both sides.'
            : 'System A: ten sam symbol i wymiary po obu stronach linii '
                'ciągłej, bez linii przerywanej = spoina symetryczna po obu '
                'stronach.',
      };
    case SymbolSystem.b:
      return switch (s.side) {
        WeldSide.arrow => en
            ? 'System B (as AWS): symbol below the line = arrow side.'
            : 'System B (jak AWS): symbol pod linią = strona strzałki.',
        WeldSide.other => en
            ? 'System B (as AWS): symbol above the line = other side.'
            : 'System B (jak AWS): symbol nad linią = strona przeciwna.',
        WeldSide.both => en
            ? 'System B (as AWS): symbols above and below the line = weld on '
                'both sides.'
            : 'System B (jak AWS): symbole nad i pod linią = spoina po obu '
                'stronach.',
      };
  }
}
