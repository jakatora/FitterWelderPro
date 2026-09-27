import 'package:flutter/material.dart';

// TIG tungsten electrode reference for DC electrode-negative welding of
// stainless steel (the food & pharma case). Current bands are for DC- with
// lanthanated/thoriated tungsten and an inert gas shield — the figures a
// welder uses to pick the right electrode and not overheat or contaminate it.

class TungstenSize {
  final double diaMm;
  final String diaImp;   // imperial callout
  final int minA;        // DC- current band
  final int maxA;
  const TungstenSize({
    required this.diaMm,
    required this.diaImp,
    required this.minA,
    required this.maxA,
  });
}

/// DC- current bands per electrode diameter. Single source for every screen
/// that picks an electrode (Tungsten screen, Pipes → AMP) — use
/// [sizeForCurrent], never private thresholds.
const List<TungstenSize> kTungstenSizes = [
  TungstenSize(diaMm: 1.0, diaImp: '0.040"', minA: 15,  maxA: 80),
  TungstenSize(diaMm: 1.6, diaImp: '1/16"',  minA: 70,  maxA: 150),
  TungstenSize(diaMm: 2.4, diaImp: '3/32"',  minA: 150, maxA: 250),
  TungstenSize(diaMm: 3.2, diaImp: '1/8"',   minA: 250, maxA: 400),
];

// Tip colours follow ISO 6848: WL20 blue, WL15 gold, WC20 grey, WT20 red,
// WP green, WZ8 white.
class TungstenType {
  final String code;     // e.g. WL20
  /// Designation per ISO 6848:2015 (WLa20, WCe20, WTh20, WZr8, WP).
  final String isoCode;
  final String tipColor; // ground-tip colour code, "PL / EN"
  final Color colorDot;
  final String namePl;
  final String nameEn;
  final String notePl;
  final String noteEn;
  final bool bestForSs;  // recommended for stainless DC TIG
  const TungstenType({
    required this.code,
    required this.isoCode,
    required this.tipColor,
    required this.colorDot,
    required this.namePl,
    required this.nameEn,
    required this.notePl,
    required this.noteEn,
    this.bestForSs = false,
  });
}

const List<TungstenType> kTungstenTypes = [
  TungstenType(
    code: 'WL20', isoCode: 'WLa20', tipColor: 'niebieski / blue',
    colorDot: Color(0xFF4A9EFF),
    namePl: '2% lantanowana', nameEn: '2% lanthanated',
    notePl: 'Najlepszy wybór do stali nierdzewnej DC. Stabilny łuk, długa żywotność, nieradioaktywna.',
    noteEn: 'Best pick for stainless DC. Stable arc, long life, non-radioactive.',
    bestForSs: true),
  TungstenType(
    code: 'WL15', isoCode: 'WLa15', tipColor: 'złoty / gold',
    colorDot: Color(0xFFE8C14B),
    namePl: '1.5% lantanowana', nameEn: '1.5% lanthanated',
    notePl: 'Uniwersalna, dobra do DC i AC. Solidna alternatywa dla WL20.',
    noteEn: 'All-round, good on DC and AC. Solid alternative to WL20.',
    bestForSs: true),
  TungstenType(
    code: 'WC20', isoCode: 'WCe20', tipColor: 'szary / grey',
    colorDot: Color(0xFF9BA3C7),
    namePl: '2% ceriowana', nameEn: '2% ceriated',
    notePl: 'Łatwe zajarzenie przy niskich prądach — cienkościenna rura, orbital.',
    noteEn: 'Easy low-current starts — thin-wall tube, orbital.',
    bestForSs: true),
  TungstenType(
    code: 'WT20', isoCode: 'WTh20', tipColor: 'czerwony / red',
    colorDot: Color(0xFFE74C3C),
    namePl: '2% torowana', nameEn: '2% thoriated',
    notePl: 'Klasyka, ale lekko radioaktywna — pył ze szlifowania szkodliwy. Wypierana przez WL20.',
    noteEn: 'Classic but mildly radioactive — grinding dust is a hazard. Being replaced by WL20.',
    bestForSs: false),
  TungstenType(
    code: 'WP', isoCode: 'WP', tipColor: 'zielony / green',
    colorDot: Color(0xFF2ECC71),
    namePl: 'Czysty wolfram', nameEn: 'Pure tungsten',
    notePl: 'Do AC (aluminium) — nie stosować do stali nierdzewnej DC.',
    noteEn: 'For AC (aluminium) — not for stainless DC.',
    bestForSs: false),
  TungstenType(
    code: 'WZ8', isoCode: 'WZr8', tipColor: 'biały / white',
    colorDot: Color(0xFFF2F2F2),
    namePl: '0.8% cyrkonowa', nameEn: '0.8% zirconiated',
    notePl: 'Do AC (aluminium, magnez) — trzyma kulistą końcówkę, odporna na zanieczyszczenie. Nie do DC.',
    noteEn: 'For AC (aluminium, magnesium) — holds a balled tip, resists contamination. Not for DC.',
    bestForSs: false),
];

/// Tip colour of [type] in the current language ("zielony / green" → PL or EN
/// half), so screens quoting a colour never drift from this table.
String tungstenTipColor(TungstenType type, {required bool english}) {
  final i = type.tipColor.indexOf(' / ');
  if (i < 0) return type.tipColor;
  return english
      ? type.tipColor.substring(i + 3)
      : type.tipColor.substring(0, i);
}

/// Electrode type by ISO 6848 code (e.g. 'WZ8'), or null if not listed.
TungstenType? tungstenTypeByCode(String code) {
  for (final t in kTungstenTypes) {
    if (t.code == code) return t;
  }
  return null;
}

/// Returns the electrode whose band covers [amps]. Where two bands overlap
/// (70–80 A: 1.0 and 1.6 mm) the LARGER electrode wins — the smaller one is
/// at the top of its band there and overheats (pipes: 1.6 mm, not 1.0 mm,
/// at 75 A). Below every band → the smallest, above → the largest.
TungstenSize? sizeForCurrent(double amps) {
  if (!amps.isFinite) return null;
  TungstenSize? pick;
  for (final s in kTungstenSizes) {
    if (amps >= s.minA && amps <= s.maxA) pick = s;
  }
  if (pick != null) return pick;
  if (amps > kTungstenSizes.last.maxA) return kTungstenSizes.last;
  if (amps < kTungstenSizes.first.minA) return kTungstenSizes.first;
  return null;
}

/// Cup / torch argon flow / tip-angle reference per electrode diameter.
/// Single source for the Tungsten screen AND Pipes (AMP, Starting points):
/// the torch gas for a given electrode is always this range.
/// Cup numbers are #-sizing (each # = 1/16" ID); argon flow in L/min for DC−
/// stainless TIG; tip angle sharp → blunt.
class TungstenExtras {
  final String cup;
  final int argonMinLpm;
  final int argonMaxLpm;
  final String tipAngle;
  const TungstenExtras({
    required this.cup,
    required this.argonMinLpm,
    required this.argonMaxLpm,
    required this.tipAngle,
  });

  /// e.g. '8–10 l/min'.
  String get argonFlow => '$argonMinLpm–$argonMaxLpm l/min';
}

// `const Map<double, _>` is illegal (double has no primitive equality), so
// the key is the printed mm value — use [tungstenExtrasFor].
const Map<String, TungstenExtras> kTungstenExtrasByDia = {
  '1.0': TungstenExtras(cup: '#4–#5 (6–8 mm)', argonMinLpm: 6, argonMaxLpm: 8, tipAngle: '15–25°'),
  '1.6': TungstenExtras(cup: '#5–#6 (8–10 mm)', argonMinLpm: 8, argonMaxLpm: 10, tipAngle: '20–30°'),
  '2.4': TungstenExtras(cup: '#6–#7 (10–11 mm)', argonMinLpm: 10, argonMaxLpm: 12, tipAngle: '30–45°'),
  '3.2': TungstenExtras(cup: '#7–#8 (11–13 mm)', argonMinLpm: 12, argonMaxLpm: 15, tipAngle: '45–60°'),
};

TungstenExtras? tungstenExtrasFor(double diaMm) =>
    kTungstenExtrasByDia[diaMm.toStringAsFixed(1)];
