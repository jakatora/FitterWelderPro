import '../utils/decimal_parse.dart';
// Maximum pipe support spacing for standard-weight (and heavier) steel pipe:
//  • ANSI/MSS SP-58-2018 Table 4 (formerly MSS SP-69 Table 3), metric column,
//    "water service" and "vapor service";
//  • ASME B31.1 Table 121.5 — same numbers where it lists the size
//    (NPS 1, 2, 3, 4, 6, 8, 12, 16, 20, 24). B31.1 bases the table on
//    INSULATED pipe filled with water (or the equivalent weight of steel pipe
//    for steam / gas / air), a sag of 2.5 mm and ≤ 400 °C; it does not apply
//    to concentrated loads (valves, flanges) between supports.
// Pinned value by value in test/data/support_spacing_norm_test.dart.
//
// Real spacing on a project is set by the stress engineer for that line —
// these are the standard reference numbers a fitter checks against on site.
// All values in millimetres.

class SupportSpan {
  final int dn;
  final String nps;
  /// Max spacing for VAPOR / gas / steam service (empty pipe).
  final int vaporMm;
  /// Max spacing for WATER (liquid-filled) service.
  final int waterMm;
  const SupportSpan({
    required this.dn,
    required this.nps,
    required this.vaporMm,
    required this.waterMm,
  });
}

const List<SupportSpan> kSupportSpans = [
  // MSS SP-58 Tab. 4 — water ft / vapor ft → metric column.
  SupportSpan(dn: 15,  nps: '1/2',   vaporMm: 2400,  waterMm: 2100), //  7 /  8 ft
  SupportSpan(dn: 20,  nps: '3/4',   vaporMm: 2700,  waterMm: 2100), //  7 /  9 ft
  SupportSpan(dn: 25,  nps: '1',     vaporMm: 2700,  waterMm: 2100), //  7 /  9 ft
  SupportSpan(dn: 32,  nps: '1 1/4', vaporMm: 2700,  waterMm: 2100), //  7 /  9 ft
  SupportSpan(dn: 40,  nps: '1 1/2', vaporMm: 3700,  waterMm: 2700), //  9 / 12 ft
  SupportSpan(dn: 50,  nps: '2',     vaporMm: 4000,  waterMm: 3000), // 10 / 13 ft
  SupportSpan(dn: 65,  nps: '2 1/2', vaporMm: 4300,  waterMm: 3400), // 11 / 14 ft
  SupportSpan(dn: 80,  nps: '3',     vaporMm: 4600,  waterMm: 3700), // 12 / 15 ft
  SupportSpan(dn: 90,  nps: '3 1/2', vaporMm: 4900,  waterMm: 4000), // 13 / 16 ft
  SupportSpan(dn: 100, nps: '4',     vaporMm: 5200,  waterMm: 4300), // 14 / 17 ft
  SupportSpan(dn: 125, nps: '5',     vaporMm: 5800,  waterMm: 4900), // 16 / 19 ft
  SupportSpan(dn: 150, nps: '6',     vaporMm: 6400,  waterMm: 5200), // 17 / 21 ft
  SupportSpan(dn: 200, nps: '8',     vaporMm: 7300,  waterMm: 5800), // 19 / 24 ft
  SupportSpan(dn: 250, nps: '10',    vaporMm: 7900,  waterMm: 6700), // 22 / 26 ft
  SupportSpan(dn: 300, nps: '12',    vaporMm: 9100,  waterMm: 7000), // 23 / 30 ft
  SupportSpan(dn: 350, nps: '14',    vaporMm: 9800,  waterMm: 7600), // 25 / 32 ft
  SupportSpan(dn: 400, nps: '16',    vaporMm: 10700, waterMm: 8200), // 27 / 35 ft
  SupportSpan(dn: 450, nps: '18',    vaporMm: 11300, waterMm: 8500), // 28 / 37 ft
  SupportSpan(dn: 500, nps: '20',    vaporMm: 11900, waterMm: 9100), // 30 / 39 ft
  SupportSpan(dn: 600, nps: '24',    vaporMm: 12800, waterMm: 9800), // 32 / 42 ft
];

SupportSpan? supportSpanForDn(int dn) {
  for (final s in kSupportSpans) {
    if (s.dn == dn) return s;
  }
  return null;
}

/// Closest tabulated entry by DN (never returns null inside the table).
SupportSpan closestSpanByDn(int dn) {
  SupportSpan best = kSupportSpans.first;
  int bestDiff = (best.dn - dn).abs();
  for (final s in kSupportSpans) {
    final d = (s.dn - dn).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = s;
    }
  }
  return best;
}

// ── Spacing calculator ───────────────────────────────────────────────────────

/// Max support spacing in whole millimetres for the closest tabulated DN.
///
/// No reduction for insulation: B31.1 Table 121.5 is already based on
/// insulated pipe. [ownMarginPct] is the user's OWN, non-normative safety
/// margin (e.g. 10 → spacing × 0.90); 0 by default, clamped to 0…50 %.
int maxSupportSpacingMm(
  int dn, {
  required bool liquidFilled,
  double ownMarginPct = 0,
}) {
  final span = closestSpanByDn(dn);
  final base = liquidFilled ? span.waterMm : span.vaporMm;
  final pct = ownMarginPct.isFinite ? ownMarginPct.clamp(0.0, 50.0) : 0.0;
  if (pct == 0) return base;
  return (base * (1 - pct / 100)).round();
}

/// Number of supports on a straight run: ⌈run ÷ spacing⌉ + 1 (the first one).
/// Integer arithmetic only, so a run that is an exact multiple of the spacing
/// never gains a phantom support from floating-point noise.
/// Returns null for a non-positive run or spacing.
int? supportsOnRun(int runMm, int spacingMm) {
  if (runMm <= 0 || spacingMm <= 0) return null;
  return (runMm + spacingMm - 1) ~/ spacingMm + 1;
}

/// Parses a run length typed in metres (comma or dot) into whole millimetres.
/// Returns null when the text is not a number.
int? runLengthMm(String text) {
  final v = parseDecimal(text);
  if (v == null || !v.isFinite) return null;
  return (v * 1000).round();
}

/// Millimetres shown as metres without hiding significant digits:
/// 3000 → "3.0", 2640 → "2.64", 3784 → "3.784".
String formatMmAsMetres(int mm) {
  final m = mm / 1000;
  if (mm % 100 == 0) return m.toStringAsFixed(1);
  if (mm % 10 == 0) return m.toStringAsFixed(2);
  return m.toStringAsFixed(3);
}

// ── Support types ────────────────────────────────────────────────────────────
//
// The mechanical role each type plays on a piping system. Pure reference;
// the engineer's drawing always decides what gets installed where.

enum SupportRole { anchor, guide, rest, hanger, spring, uBolt }

class SupportTypeInfo {
  final SupportRole role;
  final String namePl;
  final String nameEn;
  final String descPl;
  final String descEn;
  final String wherePl;
  final String whereEn;
  const SupportTypeInfo({
    required this.role,
    required this.namePl,
    required this.nameEn,
    required this.descPl,
    required this.descEn,
    required this.wherePl,
    required this.whereEn,
  });
}

const List<SupportTypeInfo> kSupportTypes = [
  SupportTypeInfo(
    role: SupportRole.anchor,
    namePl: 'Punkt stały (anchor)',
    nameEn: 'Anchor',
    descPl: 'Blokuje rurę we wszystkich 6 stopniach swobody — żadnego ruchu.',
    descEn: 'Locks the pipe in all 6 degrees of freedom — no movement.',
    wherePl: 'Końce odcinków kompensacyjnych, między dwoma kompensatorami, '
        'przy wejściu/wyjściu z aparatu.',
    whereEn: 'Ends of expansion legs, between two expansion joints, at vessel '
        'in/out nozzles.',
  ),
  SupportTypeInfo(
    role: SupportRole.guide,
    namePl: 'Prowadnica (guide)',
    nameEn: 'Guide',
    descPl: 'Pozwala na osiowy ruch (kompensacja), blokuje boczne i obrotowe.',
    descEn: 'Allows axial movement (expansion), blocks lateral / rotational.',
    wherePl: 'Wzdłuż odcinków prostych pomiędzy punktami stałymi, '
        'przed i za kompensatorem.',
    whereEn: 'Along straight runs between anchors, before and after expansion '
        'joints.',
  ),
  SupportTypeInfo(
    role: SupportRole.rest,
    namePl: 'Oparcie / shoe',
    nameEn: 'Resting support / shoe',
    descPl: 'Przenosi ciężar w dół; rura może się przesuwać po podporze.',
    descEn: 'Carries weight down; pipe slides freely on the support.',
    wherePl: 'Estakady, mosty rurowe, ślizgi nad belką nośną.',
    whereEn: 'Pipe racks, pipe bridges, slides over a support beam.',
  ),
  SupportTypeInfo(
    role: SupportRole.hanger,
    namePl: 'Zawieszenie (hanger)',
    nameEn: 'Rigid hanger',
    descPl: 'Sztywne zawieszenie pod stropem / belką, ciężar w górę.',
    descEn: 'Rigid rod or strap below a ceiling / beam, weight goes up.',
    wherePl: 'Tam, gdzie nie ma posadowienia od dołu — sufity, belki nośne.',
    whereEn: 'Where there is nothing to rest on — ceilings, overhead beams.',
  ),
  SupportTypeInfo(
    role: SupportRole.spring,
    namePl: 'Zawieszenie sprężynowe',
    nameEn: 'Spring hanger',
    descPl: 'Utrzymuje stałe obciążenie podczas ruchu termicznego rury.',
    descEn: 'Holds a constant load while the pipe moves with temperature.',
    wherePl: 'Linie o znacznym rozszerzeniu termicznym, w pobliżu maszyn.',
    whereEn: 'Lines with significant thermal expansion, near rotating machinery.',
  ),
  SupportTypeInfo(
    role: SupportRole.uBolt,
    namePl: 'U-bolt / strzemiączko',
    nameEn: 'U-bolt / clamp',
    descPl: 'Lekkie mocowanie rury do belki — głównie utrzymanie pozycji.',
    descEn: 'Light fastening of pipe to a beam — mostly position-holding.',
    wherePl: 'Małe średnice na konstrukcji, linie pomocnicze, instrumenty.',
    whereEn: 'Small bores on steelwork, utility lines, instrument tubing.',
  ),
];

// ── Placement rules ──────────────────────────────────────────────────────────
//
// A fitter's checklist of "must-haves" that a stress engineer rarely puts on
// the iso explicitly but expects to find on site.

class PlacementRule {
  final String pl;
  final String en;
  const PlacementRule(this.pl, this.en);
}

const List<PlacementRule> kPlacementRules = [
  PlacementRule(
    'Podpora w odległości ≤ 1 m od każdego kolana / trójnika '
    'po stronie krótszego ramienia.',
    'A support within ≤ 1 m of every elbow / tee on the short-arm side.',
  ),
  PlacementRule(
    'Podpora bezpośrednio za ciężkim zaworem (zasuwa, kulowy DN ≥ 100) '
    'i przed nim, jeśli pozwala trasa.',
    'A support immediately downstream of every heavy valve (gate, ball ≥ DN 100) '
    'and upstream where the route allows.',
  ),
  PlacementRule(
    'Punkt stały między dwoma kompensatorami i przed wejściem do aparatu '
    '(pompa, wymiennik) aby chronić króciec.',
    'An anchor between any two expansion joints and ahead of a piece of equipment '
    '(pump, exchanger) to protect the nozzle.',
  ),
  PlacementRule(
    'Pionowe odcinki: podpora nośna na górze (utrzymanie ciężaru), prowadnice '
    'wg rysunku podpór — tabela rozstawu MSS / B31.1 dotyczy tylko odcinków '
    'poziomych.',
    'Vertical runs: a load-carrying support at the top, guides per the support '
    'drawing — the MSS / B31.1 spacing table covers horizontal runs only.',
  ),
  PlacementRule(
    'Trójnik / odgałęzienie ≥ DN 80: osobna podpora na odgałęzieniu '
    'w pobliżu pnia, niezależna od głównego rurociągu.',
    'Branch ≥ DN 80 off a tee: a separate support on the branch near the header, '
    'independent of the main line.',
  ),
  PlacementRule(
    'Tabela ASME B31.1 121.5 zakłada już rurę izolowaną wypełnioną wodą — '
    'zwykła izolacja nie wymaga obniżki rozstawu. Obciążenia skupione między '
    'podporami (zawory, kołnierze, armatura) wymagają podpory bliżej — tabela '
    'ich nie obejmuje.',
    'ASME B31.1 Table 121.5 already assumes insulated pipe filled with water — '
    'normal insulation needs no spacing reduction. Concentrated loads between '
    'supports (valves, flanges, specialties) need a closer support — the table '
    'does not cover them.',
  ),
  PlacementRule(
    'Tabela dotyczy rury stalowej o ściance standard i grubszej. Rury '
    'cienkościenne (5S/10S, sanitarne), miedź i tworzywa mają znacznie '
    'mniejszy rozstaw — wg ich norm / producenta.',
    'The table is for standard-wall (and heavier) steel pipe. Thin-wall pipe '
    '(5S/10S, sanitary tube), copper and plastics need much closer spacing — '
    'per their own standard / manufacturer.',
  ),
  PlacementRule(
    'Rurociąg na stali nierdzewnej sanitarnej (food / pharma): unikać '
    'kontaktu z stalą węglową — używaj wkładek z PTFE lub stali nierdzewnej.',
    'Sanitary stainless lines (food / pharma): avoid carbon-steel contact — '
    'use PTFE or stainless inserts.',
  ),
];
