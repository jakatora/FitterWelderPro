// Maximum pipe support spacing per MSS SP-69 / ASME B31 reference tables.
// Spacing is the longest distance allowed between two supports for a straight
// run carrying water (full of liquid) or vapor (empty / gas / steam).
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
  SupportSpan(dn: 15,  nps: '1/2',   vaporMm: 2100,  waterMm: 2100),
  SupportSpan(dn: 20,  nps: '3/4',   vaporMm: 2400,  waterMm: 2400),
  SupportSpan(dn: 25,  nps: '1',     vaporMm: 2700,  waterMm: 2100),
  SupportSpan(dn: 32,  nps: '1 1/4', vaporMm: 3000,  waterMm: 2400),
  SupportSpan(dn: 40,  nps: '1 1/2', vaporMm: 3400,  waterMm: 2700),
  SupportSpan(dn: 50,  nps: '2',     vaporMm: 4000,  waterMm: 3000),
  SupportSpan(dn: 65,  nps: '2 1/2', vaporMm: 4300,  waterMm: 3400),
  SupportSpan(dn: 80,  nps: '3',     vaporMm: 4600,  waterMm: 3700),
  SupportSpan(dn: 100, nps: '4',     vaporMm: 5200,  waterMm: 4300),
  SupportSpan(dn: 150, nps: '6',     vaporMm: 5800,  waterMm: 5200),
  SupportSpan(dn: 200, nps: '8',     vaporMm: 6400,  waterMm: 5800),
  SupportSpan(dn: 250, nps: '10',    vaporMm: 6700,  waterMm: 6400),
  SupportSpan(dn: 300, nps: '12',    vaporMm: 7000,  waterMm: 7000),
  SupportSpan(dn: 350, nps: '14',    vaporMm: 7300,  waterMm: 7000),
  SupportSpan(dn: 400, nps: '16',    vaporMm: 7600,  waterMm: 7600),
  SupportSpan(dn: 450, nps: '18',    vaporMm: 8200,  waterMm: 7900),
  SupportSpan(dn: 500, nps: '20',    vaporMm: 8800,  waterMm: 8200),
  SupportSpan(dn: 600, nps: '24',    vaporMm: 10000, waterMm: 9100),
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
    'Pionowe odcinki: podpora na górze (utrzymanie ciężaru) plus '
    'prowadnice co 2× rozstaw poziomego rozstawu w dół.',
    'Vertical runs: a support at the top to carry the weight, then guides every '
    '2× the horizontal spacing going down.',
  ),
  PlacementRule(
    'Trójnik / odgałęzienie ≥ DN 80: osobna podpora na odgałęzieniu '
    'w pobliżu pnia, niezależna od głównego rurociągu.',
    'Branch ≥ DN 80 off a tee: a separate support on the branch near the header, '
    'independent of the main line.',
  ),
  PlacementRule(
    'Izolacja zwiększa ciężar — zmniejsz rozstaw o 10–15 % dla rur '
    'izolowanych grubością ≥ 50 mm.',
    'Insulation adds weight — reduce spacing by 10–15 % for lines with ≥ 50 mm '
    'insulation.',
  ),
  PlacementRule(
    'Rurociąg na stali nierdzewnej sanitarnej (food / pharma): unikać '
    'kontaktu z stalą węglową — używaj wkładek z PTFE lub stali nierdzewnej.',
    'Sanitary stainless lines (food / pharma): avoid carbon-steel contact — '
    'use PTFE or stainless inserts.',
  ),
];
