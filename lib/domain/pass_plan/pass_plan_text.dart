// Plan ściegów i elektrod — opisy, komunikaty i tekst do udostępnienia.
// Jedno źródło dla ekranu i tekstu. Czysty Dart (język wybiera wywołujący).
library;

import '../quotes/quote_labels.dart';
import '../quotes/quote_process.dart';
import '../quotes/weld_geometry.dart';
import '../welding/electrode_exposure.dart';
import 'pass_plan.dart';
import 'pass_plan_sources.dart';

// ─── Liczby ──────────────────────────────────────────────────────────────

/// Liczba z [decimals] miejscami: przecinek po polsku, kropka po angielsku.
String ppFixed(double v, int decimals, {required bool en}) {
  var s = v.toStringAsFixed(decimals);
  if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  return en ? s : s.replaceAll('.', ',');
}

/// Liczba bez zbędnych zer (do 2 miejsc): 7,11 · 60 · 2,5.
String ppNum(double v, {required bool en}) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// Polska odmiana: 1 ścieg, 2 ściegi, 5 ściegów, 12 ściegów, 22 ściegi.
String plPlural(int n, String one, String few, String many) {
  if (n == 1) return one;
  final d = n % 10, dd = n % 100;
  if (d >= 2 && d <= 4 && (dd < 12 || dd > 14)) return few;
  return many;
}

String passesText(int n, {required bool en}) => en
    ? '$n ${n == 1 ? 'pass' : 'passes'}'
    : '$n ${plPlural(n, 'ścieg', 'ściegi', 'ściegów')}';

String piecesText(int n, {required bool en}) => en ? '$n pcs' : '$n szt.';

String rodsText(int n, {required bool en}) => en
    ? '$n ${n == 1 ? 'rod' : 'rods'}'
    : '$n ${plPlural(n, 'pręt', 'pręty', 'prętów')}';

String jointsText(int n, {required bool en}) => en
    ? '$n ${n == 1 ? 'joint' : 'joints'}'
    : '$n ${plPlural(n, 'złącze', 'złącza', 'złączy')}';

String portionsText(int n, {required bool en}) => en
    ? '$n ${n == 1 ? 'batch' : 'batches'}'
    : '$n ${plPlural(n, 'porcja', 'porcje', 'porcji')}';

/// Czas W GÓRĘ do pełnej minuty: „44 min”, „5 h 47 min”.
String minutesText(double minutes) =>
    formatSpan(Duration(minutes: ceilTol(minutes)));

/// Godziny bez zbędnych zer: „8 h”, „5,5 h”.
String hoursText(double h, {required bool en}) => '${ppNum(h, en: en)} h';

/// Masa W GÓRĘ: do 1 g poniżej kilograma, potem do 0,01 kg.
String massText(double g, {required bool en}) => g < 1000
    ? '${ceilTol(g)} g'
    : '${ppFixed(ceilHundredth(g / 1000), 2, en: en)} kg';

// ─── Nazwy ───────────────────────────────────────────────────────────────

String layerName(PassLayer l, {required bool en}) => switch (l) {
      PassLayer.root => en ? 'Root' : 'Grań',
      PassLayer.hot => en ? 'Hot pass' : 'Ścieg gorący',
      PassLayer.fill => en ? 'Fill' : 'Wypełnienie',
      PassLayer.cap => en ? 'Cap' : 'Lico',
    };

/// Krótka nazwa na chip: „TIG”, „Ø2,5”, „MAG”.
String consumableShort(PassConsumable c, {required bool en}) => c.isElectrode
    ? 'Ø${formatDiameter(c.electrodeMm!, en: en)}'
    : c.process.code;

/// „Ø3,2 × 350 mm”.
String electrodeSizeText(ElectrodeCardRow r, {required bool en}) =>
    'Ø${formatDiameter(r.diameterMm, en: en)} × ${r.lengthMm} mm';

/// Spoiwo warstwy: „elektroda Ø2,5 × 350 mm”, „TIG, pręt Ø2,4”, „MAG,
/// drut”.
String layerConsumableText(PassLayerPlan l, PassPlanInput i,
    {required bool en}) {
  final row = l.electrode;
  if (row != null) {
    return en
        ? 'electrode ${electrodeSizeText(row, en: en)}'
        : 'elektroda ${electrodeSizeText(row, en: en)}';
  }
  if (l.consumable == PassConsumable.tig) {
    final d = formatDiameter(i.tigRodMm, en: en);
    return en ? 'TIG, rod Ø$d' : 'TIG, pręt Ø$d';
  }
  return en ? 'MAG, wire' : 'MAG, drut';
}

/// Ilość spoiwa warstwy jednego złącza: „4 szt.”, „2 pręty”, „0,05 kg”.
String layerQuantityText(PassLayerPlan l, {required bool en}) {
  if (l.electrode != null) return piecesText(l.unitsCeil, en: en);
  if (l.consumable == PassConsumable.tig) return rodsText(l.unitsCeil, en: en);
  return '${ppFixed(ceilHundredth(l.fillerG / 1000), 2, en: en)} kg';
}

/// Pozycja listy spoiw: „Elektroda Ø3,2 × 350 mm”, „Pręt TIG Ø2,4 ×
/// 1000 mm”, „Drut MAG”.
String supplyName(PassSupply s, {required bool en}) {
  final row = s.electrode;
  if (row != null) {
    return en
        ? 'Electrode ${electrodeSizeText(row, en: en)}'
        : 'Elektroda ${electrodeSizeText(row, en: en)}';
  }
  if (s.consumable == PassConsumable.tig) {
    final d = formatDiameter(s.tigRodMm!, en: en);
    final l = kTigRodLengthMm.round();
    return en ? 'TIG rod Ø$d × $l mm' : 'Pręt TIG Ø$d × $l mm';
  }
  return en ? 'MAG wire' : 'Drut MAG';
}

/// Ilość na całość: „39 szt. (z zapasem 42)”, „11 prętów (z zapasem 12) ·
/// 0,39 kg”, „1,32 kg (z zapasem 1,45 kg)”.
String supplyJobText(PassSupply s, {required bool en}) {
  final r = s.reservePct > 0;
  if (s.isElectrode) {
    final base = piecesText(s.unitsJob, en: en);
    if (!r) return base;
    return en
        ? '$base (with reserve ${s.unitsJobWithReserve})'
        : '$base (z zapasem ${s.unitsJobWithReserve})';
  }
  final kg = '${ppFixed(s.fillerKgJob, 2, en: en)} kg';
  final kgR = '${ppFixed(s.fillerKgJobWithReserve, 2, en: en)} kg';
  if (s.consumable == PassConsumable.tig) {
    final base = rodsText(s.unitsJob, en: en);
    if (!r) return '$base · $kg';
    return en
        ? '$base (with reserve ${s.unitsJobWithReserve}) · $kgR'
        : '$base (z zapasem ${s.unitsJobWithReserve}) · $kgR';
  }
  if (!r) return kg;
  return en ? '$kg (with reserve $kgR)' : '$kg (z zapasem $kgR)';
}

String _grooveText(PassPlanInput i, {required bool en}) {
  final b = ppNum(i.gapMm, en: en);
  if (i.groove == GrooveType.square) {
    return en ? 'I groove, gap $b' : 'rowek I, szczelina $b';
  }
  final a = ppNum(i.angleDeg, en: en);
  final c = ppNum(i.rootFaceMm, en: en);
  return en
      ? '${i.groove.code} groove $a°, gap $b, root face $c'
      : 'rowek ${i.groove.code} $a°, szczelina $b, próg $c';
}

/// „Doczołowa rury Ø168,3 × 7,11, rowek V 60°, szczelina 2,5, próg 1,5”.
String jointDescription(PassPlanInput i, {required bool en}) {
  String n(double v) => ppNum(v, en: en);
  final kind = jointKindShort(i.kind, en: en);
  return switch (i.kind) {
    JointKind.pipeButt =>
      '$kind Ø${n(i.odMm)} × ${n(i.wallMm)}, ${_grooveText(i, en: en)}',
    JointKind.plateButt =>
      '$kind t = ${n(i.wallMm)}, ${n(i.lengthM)} m, ${_grooveText(i, en: en)}',
    JointKind.pipeFillet => '$kind Ø${n(i.odMm)}, a = ${n(i.throatMm)}',
    JointKind.plateFillet => '$kind a = ${n(i.throatMm)}, ${n(i.lengthM)} m',
    JointKind.branch => kind,
  };
}

/// Nazwa klasy elektrody albo „nie zasadowa”.
String electrodeClassText(ElectrodeClass? c, {required bool en}) => c == null
    ? (en
        ? 'not low-hydrogen (rutile, cellulosic) — no limit'
        : 'nie zasadowa (rutylowa, celulozowa) — bez limitu')
    : c.code;

String electrodeSourceText(ElectrodeSource s, {required bool en}) =>
    switch (s) {
      ElectrodeSource.oven => en ? 'holding oven / quiver' : 'piecyk / termos',
      ElectrodeSource.hermeticPack =>
        en ? 'fresh vacuum pack' : 'świeże opakowanie próżniowe',
    };

String workOrderText(WorkOrder o, {required bool en}) => switch (o) {
      WorkOrder.jointByJoint => en ? 'joint by joint' : 'złącze po złączu',
      WorkOrder.rootsFirst =>
        en ? 'all roots first' : 'najpierw wszystkie granie',
    };

String processName(QuoteProcess p) => p.label;

// ─── Ekspozycja ──────────────────────────────────────────────────────────

/// „Ø2,5 × 14 szt. · Ø3,2 × 23 szt.”
String takeNowText(ExposurePlan e, {required bool en}) => e.takes
    .map((t) => 'Ø${formatDiameter(t.electrode.diameterMm, en: en)} × '
        '${piecesText(t.takeNow, en: en)}')
    .join(' · ');

/// Reguła „przy limicie X h i tempie Y elektrod/h bierz najwyżej Z naraz”.
String exposureRuleText(ExposurePlan e, {required bool en}) {
  if (!e.hasLimit) {
    return en
        ? 'Not low-hydrogen electrodes: no exposure limit — take all of them '
            '(keep them dry as the data sheet says).'
        : 'Elektrody nie zasadowe: bez limitu czasu na powietrzu — weź '
            'całość (chroń przed wilgocią wg karty producenta).';
  }
  final limit = formatSpan(Duration(minutes: e.limitMinutes!));
  final window = formatSpan(Duration(minutes: e.windowMinutes));
  final lead = '${e.leadMinutes} min';
  final rates = e.takes
      .map((t) => '${ppFixed(t.ratePerH, 1, en: en)} '
          '${en ? 'pcs/h' : 'szt./h'} '
          'Ø${formatDiameter(t.electrode.diameterMm, en: en)}')
      .join(' + ');
  final most = e.takes
      .map((t) => '${t.maxAtOnce} '
          '${en ? 'pcs' : 'szt.'} '
          'Ø${formatDiameter(t.electrode.diameterMm, en: en)}')
      .join(' + ');
  return en
      ? 'Limit $limit − $lead margin = $window. At $rates '
          '(${workOrderText(e.order, en: en)}) take at most $most at once '
          '(rounded down).'
      : 'Limit $limit − $lead zapasu = $window. Przy tempie $rates '
          '(${workOrderText(e.order, en: en)}) bierz najwyżej $most naraz '
          '(w dół).';
}

/// „2 porcje na zmianę 8 h” / „2 porcje na całą robotę (5 h 47 min)”.
String exposurePortionsText(ExposurePlan e, {required bool en}) {
  final p = e.portions;
  if (p == null) {
    return en
        ? 'The window is shorter than using up one electrode — take them out '
            'one at a time and put the rest back in the oven.'
        : 'Okno krótsze niż zużycie jednej elektrody — wyjmuj po jednej, '
            'resztę z powrotem do piecyka.';
  }
  if (e.wholeJobInShift) {
    final t = minutesText(e.hoursInShift * 60);
    return en
        ? '${portionsText(p, en: en)} for the whole job ($t of work)'
        : '${portionsText(p, en: en)} na całą robotę ($t pracy)';
  }
  final s = hoursText(e.shiftH, en: en);
  return en
      ? '${portionsText(p, en: en)} per $s shift'
      : '${portionsText(p, en: en)} na zmianę $s';
}

// ─── Komunikaty ──────────────────────────────────────────────────────────

String passPlanProblemText(PassPlanProblem p, {required bool en}) {
  switch (p.kind) {
    case PassPlanProblemKind.joint:
      return jointProblemText(p.joint!, en: en);
    case PassPlanProblemKind.count:
      return en
          ? 'Number of joints: a whole number from 1 to 100 000.'
          : 'Liczba złączy: liczba całkowita od 1 do 100 000.';
    case PassPlanProblemKind.kind:
      return en
          ? 'This joint type is not covered by the plan.'
          : 'Ten rodzaj złącza nie jest obsługiwany w planie.';
    case PassPlanProblemKind.grooveXOnPipe:
      return en
          ? 'X groove only for plates — a pipe is welded from one side.'
          : 'Rowek X tylko dla blach — rurę spawa się z jednej strony.';
    case PassPlanProblemKind.gapMissing:
      return en
          ? 'Enter the gap (0 mm or more).'
          : 'Podaj szczelinę (0 mm lub więcej).';
    case PassPlanProblemKind.rootFaceMissing:
      return en
          ? 'Enter the root face (0 mm or more).'
          : 'Podaj próg (0 mm lub więcej).';
    case PassPlanProblemKind.angleMissing:
      return en ? 'Enter the groove angle.' : 'Podaj kąt rowka.';
    case PassPlanProblemKind.stub:
      return en
          ? 'Stub from ${ppNum(kMinStubMm, en: en)} to '
              '${ppNum(kMaxStubMm, en: en)} mm.'
          : 'Ogarek od ${ppNum(kMinStubMm, en: en)} do '
              '${ppNum(kMaxStubMm, en: en)} mm.';
    case PassPlanProblemKind.reserve:
      return en ? 'Reserve from 0 to 100 %.' : 'Zapas od 0 do 100 %.';
    case PassPlanProblemKind.tigRod:
      return en
          ? 'Choose the TIG rod diameter.'
          : 'Wybierz średnicę pręta TIG.';
    case PassPlanProblemKind.beadArea:
      final c = consumableShort(p.consumable!, en: en);
      return en
          ? 'Bead area $c: more than 0, up to '
              '${ppNum(kMaxBeadAreaMm2, en: en)} mm².'
          : 'Przekrój ściegu $c: więcej niż 0, do '
              '${ppNum(kMaxBeadAreaMm2, en: en)} mm².';
    case PassPlanProblemKind.arcOn:
      final name = p.process!.code;
      return en
          ? 'Arc-on factor $name: from ${ppNum(kMinArcOnPct, en: en)} to '
              '${ppNum(kMaxArcOnPct, en: en)} %.'
          : 'Współczynnik jarzenia łuku $name: od '
              '${ppNum(kMinArcOnPct, en: en)} do '
              '${ppNum(kMaxArcOnPct, en: en)} %.';
    case PassPlanProblemKind.shift:
      return en
          ? 'Shift: more than 0, up to ${ppNum(kMaxShiftH, en: en)} h.'
          : 'Zmiana: więcej niż 0, do ${ppNum(kMaxShiftH, en: en)} h.';
    case PassPlanProblemKind.limit:
      return en
          ? 'Own limit from 1 min to 7 days (empty — from the table).'
          : 'Limit własny od 1 min do 7 dni (puste — z tabeli).';
  }
}

String passPlanDisclaimer({required bool en}) => en
    ? 'ESTIMATE for planning a shift — not a quote and not a WPS. Bead areas '
        'are assumed: check on the first joint (how many mm of bead one '
        'electrode gives) and correct them. The exposure limit from the WPS '
        'or the electrode data sheet takes precedence; after the limit the '
        'electrodes go to re-drying or scrap.'
    : 'SZACUNEK do zaplanowania zmiany — nie wycena i nie WPS. Przekroje '
        'ściegów są przyjęte: sprawdź na pierwszym złączu (ile mm ściegu '
        'daje jedna elektroda) i popraw. Pierwszeństwo ma limit czasu na '
        'powietrzu z WPS albo karty elektrody; po przekroczeniu limitu '
        'elektrody idą do ponownego suszenia albo na złom.';

// ─── Udostępnianie ───────────────────────────────────────────────────────

String passPlanTitle({required bool en}) =>
    en ? 'Pass and electrode plan' : 'Plan ściegów i elektrod';

/// Tekst planu do udostępnienia.
String passPlanShareText(PassPlanResult r, {required bool en}) {
  final i = r.input;
  final b = StringBuffer()
    ..writeln(passPlanTitle(en: en))
    ..writeln(en
        ? 'Joint: ${jointDescription(i, en: en)} — ${jointsText(r.jointCount, en: en)}'
        : 'Złącze: ${jointDescription(i, en: en)} — ${jointsText(r.jointCount, en: en)}')
    ..writeln()
    ..writeln(en ? 'Per joint:' : 'Na jedno złącze:');
  for (final l in r.layers) {
    b.writeln('• ${layerName(l.layer, en: en)} — '
        '${layerConsumableText(l, i, en: en)}: '
        '${passesText(l.passes, en: en)}, '
        '${massText(l.depositG, en: en)} ${en ? 'weld metal' : 'stopiwa'}, '
        '${layerQuantityText(l, en: en)}, '
        '${en ? 'arc' : 'łuk'} ${minutesText(l.arcMin)}, '
        '${en ? 'time' : 'czas'} ${minutesText(l.workMin)}');
  }
  b.writeln(en
      ? 'Total: ${passesText(r.passesPerJoint, en: en)}, '
          '${massText(r.depositGPerJoint, en: en)} weld metal, arc '
          '${minutesText(r.arcMinPerJoint)}, joint time '
          '${minutesText(r.workMinPerJoint)}'
      : 'Razem: ${passesText(r.passesPerJoint, en: en)}, '
          '${massText(r.depositGPerJoint, en: en)} stopiwa, łuk '
          '${minutesText(r.arcMinPerJoint)}, czas złącza '
          '${minutesText(r.workMinPerJoint)}');
  b
    ..writeln()
    ..writeln(en
        ? 'Whole job (${jointsText(r.jointCount, en: en)}, reserve '
            '${ppNum(i.reservePct, en: en)} %):'
        : 'Na całość (${jointsText(r.jointCount, en: en)}, zapas '
            '${ppNum(i.reservePct, en: en)} %):');
  for (final s in r.supplies) {
    b.writeln('• ${supplyName(s, en: en)}: ${supplyJobText(s, en: en)}');
  }
  b.writeln(en
      ? 'Arc time ${minutesText(r.arcMinJob)}, working time '
          '${minutesText(r.workMinJob)}'
      : 'Czas łuku ${minutesText(r.arcMinJob)}, czas pracy '
          '${minutesText(r.workMinJob)}');
  final e = r.exposure;
  if (e != null) {
    b
      ..writeln()
      ..writeln(en
          ? 'Take from the oven: ${takeNowText(e, en: en)}'
          : 'Weź z suszarki: ${takeNowText(e, en: en)}')
      ..writeln(en
          ? 'Electrodes: ${electrodeClassText(e.electrodeClass, en: en)}'
              '${e.hasLimit ? ', ${electrodeSourceText(e.source, en: en)}' : ''}'
          : 'Elektrody: ${electrodeClassText(e.electrodeClass, en: en)}'
              '${e.hasLimit ? ', ${electrodeSourceText(e.source, en: en)}' : ''}')
      ..writeln(exposureRuleText(e, en: en));
    if (e.hasLimit) b.writeln(exposurePortionsText(e, en: en));
  }
  b
    ..writeln()
    ..writeln(passPlanDisclaimer(en: en))
    ..writeln()
    ..writeln(en ? 'Sources:' : 'Źródła:');
  for (final s in kPassPlanSources) {
    b.writeln('• ${s.text(en: en)}');
  }
  return b.toString().trimRight();
}
