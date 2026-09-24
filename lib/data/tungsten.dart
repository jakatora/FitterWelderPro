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
  final String tipColor; // ground-tip colour code, "PL / EN"
  final Color colorDot;
  final String namePl;
  final String nameEn;
  final String notePl;
  final String noteEn;
  final bool bestForSs;  // recommended for stainless DC TIG
  const TungstenType({
    required this.code,
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
    code: 'WL20', tipColor: 'niebieski / blue',
    colorDot: Color(0xFF4A9EFF),
    namePl: '2% lantanowana', nameEn: '2% lanthanated',
    notePl: 'Najlepszy wybór do stali nierdzewnej DC. Stabilny łuk, długa żywotność, nieradioaktywna.',
    noteEn: 'Best pick for stainless DC. Stable arc, long life, non-radioactive.',
    bestForSs: true),
  TungstenType(
    code: 'WL15', tipColor: 'złoty / gold',
    colorDot: Color(0xFFE8C14B),
    namePl: '1.5% lantanowana', nameEn: '1.5% lanthanated',
    notePl: 'Uniwersalna, dobra do DC i AC. Solidna alternatywa dla WL20.',
    noteEn: 'All-round, good on DC and AC. Solid alternative to WL20.',
    bestForSs: true),
  TungstenType(
    code: 'WC20', tipColor: 'szary / grey',
    colorDot: Color(0xFF9BA3C7),
    namePl: '2% ceriowana', nameEn: '2% ceriated',
    notePl: 'Łatwe zajarzenie przy niskich prądach — cienkościenna rura, orbital.',
    noteEn: 'Easy low-current starts — thin-wall tube, orbital.',
    bestForSs: true),
  TungstenType(
    code: 'WT20', tipColor: 'czerwony / red',
    colorDot: Color(0xFFE74C3C),
    namePl: '2% torowana', nameEn: '2% thoriated',
    notePl: 'Klasyka, ale lekko radioaktywna — pył ze szlifowania szkodliwy. Wypierana przez WL20.',
    noteEn: 'Classic but mildly radioactive — grinding dust is a hazard. Being replaced by WL20.',
    bestForSs: false),
  TungstenType(
    code: 'WP', tipColor: 'zielony / green',
    colorDot: Color(0xFF2ECC71),
    namePl: 'Czysty wolfram', nameEn: 'Pure tungsten',
    notePl: 'Do AC (aluminium) — nie stosować do stali nierdzewnej DC.',
    noteEn: 'For AC (aluminium) — not for stainless DC.',
    bestForSs: false),
  TungstenType(
    code: 'WZ8', tipColor: 'biały / white',
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

/// Returns the smallest electrode whose band covers [amps], or the largest
/// size if the current is above every band.
TungstenSize? sizeForCurrent(double amps) {
  for (final s in kTungstenSizes) {
    if (amps >= s.minA && amps <= s.maxA) return s;
  }
  if (amps > kTungstenSizes.last.maxA) return kTungstenSizes.last;
  if (amps < kTungstenSizes.first.minA) return kTungstenSizes.first;
  return null;
}
