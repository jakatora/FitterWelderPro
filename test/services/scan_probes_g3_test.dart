// Sondy planisty skanera z przeglądu G3 (scan_probe_test w raporcie) jako
// testy: kołnierz bez typu, jawny SO, kolano bez LR, pewność medium, tekst
// wymiaru ≠ liczba (także „1 250” ze spacją tysięcy).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_outputs.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

Map<String, dynamic> _envelopeOf(String file) {
  final j = jsonDecode(File('test/golden_iso/$file').readAsStringSync())
      as Map<String, dynamic>;
  return (j['envelope'] as Map).cast<String, dynamic>();
}

List<Map> _list(Map<String, dynamic> env, String key) =>
    ((env['result'] as Map)[key] as List).cast<Map>();

({ScanPlan plan, ScanReviewGate gate}) _run(Map<String, dynamic> env,
    {double gap = 0}) {
  final plan = planFromScan(AiScanResult.fromEnvelope(env), gapMm: gap);
  final gate = evaluateReview(
    plan: plan,
    segments: plan.segments,
    materialGroup: plan.project.materialGroup,
    headerComplete: true,
  );
  return (plan: plan, gate: gate);
}

PlannedSegment _seg(ScanPlan p, String id) =>
    p.segments.singleWhere((s) => s.sourceId == id);

void main() {
  group('złoty 15 — kołnierze zespołu zaworu', () {
    test('bez flangeType i z etykietą „FLG RF 150#”: nie cichy WN', () {
      final env = _envelopeOf('15-zawor-zespol-kolnierzy.json');
      for (final c in _list(env, 'components')) {
        if (c['id'] == 'F1' || c['id'] == 'F2') {
          c.remove('flangeType');
          c['label'] = 'FLG RF 150#';
        }
      }
      final r = _run(env);
      // Przed poprawką: s1 = 772, s2 = 472, bez potwierdzenia i ostrzeżenia.
      expect(_seg(r.plan, 's1').cutMm, isNull);
      expect(_seg(r.plan, 's1').needsDimRefConfirmation, isTrue);
      expect(r.plan.has(ScanIssueCode.flangeAssumedWeldNeck), isTrue);
      expect(
          r.gate.openGaps
              .where((g) => g.code == ScanIssueCode.dimensionReferenceUnknown)
              .map((g) => g.segmentId),
          contains('s1'));
      // Po potwierdzeniu propozycji (WN do przylgi) Y się odejmuje.
      final s1 = _seg(r.plan, 's1');
      expect(s1.withStops(s1.proposedStops).cutMm, 772);
    });

    test('z WN w flangeType: jak dawniej, bez ostrzeżenia', () {
      final r = _run(_envelopeOf('15-zawor-zespol-kolnierzy.json'));
      expect(r.plan.has(ScanIssueCode.flangeAssumedWeldNeck), isFalse);
    });

    test('jawny SO: blokada (wsunięcia nie ma w katalogu)', () {
      final env = _envelopeOf('15-zawor-zespol-kolnierzy.json');
      for (final c in _list(env, 'components')) {
        if (c['id'] == 'F1' || c['id'] == 'F2') {
          c['flangeType'] = 'SO';
          c['label'] = 'SO RF 150#';
        }
      }
      final r = _run(env);
      expect(_seg(r.plan, 's1').cutMm, isNull);
      expect(r.gate.blocked.map((s) => s.sourceId), contains('s1'));
      expect(r.plan.has(ScanIssueCode.flangeAssumedWeldNeck), isFalse);
    });
  });

  group('złoty 01 — kolano–kolano, szczelina 2', () {
    test('kolana bez „LR” w etykiecie: LR 152 z ostrzeżeniem', () {
      final env = _envelopeOf('01-kolano-kolano-90lr.json');
      for (final c in _list(env, 'components')) {
        if (c['type'] == 'elbow90') c.remove('label');
      }
      final r = _run(env, gap: 2);
      expect(_seg(r.plan, 's2').cutMm, 892);
      expect(r.plan.has(ScanIssueCode.takeoutAssumedLongRadius), isTrue);
    });

    test('s2 „medium”: 892 zapisywalne, ale oznaczone do rzutu oka', () {
      final env = _envelopeOf('01-kolano-kolano-90lr.json');
      for (final s in _list(env, 'segments')) {
        if (s['id'] == 's2') s['confidence'] = 'medium';
      }
      final r = _run(env, gap: 2);
      expect(_seg(r.plan, 's2').cutMm, 892);
      expect(r.gate.savable.map((s) => s.sourceId), contains('s2'));
      expect(
          r.plan.warningsFor('s2').map((w) => w.code),
          contains(ScanIssueCode.mediumConfidence));
    });

    for (final raw in ['1250', '1 250', '1 250']) {
      test('tekst „$raw” ≠ liczba 1200: blokada do potwierdzenia', () {
        final env = _envelopeOf('01-kolano-kolano-90lr.json');
        for (final s in _list(env, 'segments')) {
          if (s['id'] == 's2') s['rawDimension'] = raw;
        }
        final r = _run(env, gap: 2);
        // Przed poprawką: CUT 892 z 1200, bez żadnej blokady.
        expect(r.gate.blocked.map((s) => s.sourceId), contains('s2'));
        final gap = r.gate
            .gapsFor('s2')
            .singleWhere((g) => g.code == ScanIssueCode.dimensionTextMismatch);
        expect(gap.pl, allOf(contains('1250'), contains('1200')));
      });
    }

    test('„1 200” (ta sama liczba ze spacją) nie blokuje', () {
      final env = _envelopeOf('01-kolano-kolano-90lr.json');
      for (final s in _list(env, 'segments')) {
        if (s['id'] == 's2') s['rawDimension'] = '1 200';
      }
      final r = _run(env, gap: 2);
      expect(r.gate.blocked, isEmpty);
    });
  });
}
