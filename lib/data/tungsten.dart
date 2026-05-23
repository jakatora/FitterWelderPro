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

/// DC- current bands per electrode diameter.
const List<TungstenSize> kTungstenSizes = [
  TungstenSize(diaMm: 1.0, diaImp: '0.040"', minA: 15,  maxA: 80),
  TungstenSize(diaMm: 1.6, diaImp: '1/16"',  minA: 70,  maxA: 150),
  TungstenSize(diaMm: 2.4, diaImp: '3/32"',  minA: 150, maxA: 250),
  TungstenSize(diaMm: 3.2, diaImp: '1/8"',   minA: 250, maxA: 400),
];

class TungstenType {
  final String code;     // e.g. WL20
  final String tipColor; // ground-tip colour code
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
];

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
