// Tests for the scan → project plan translation.
//
// Everything here is built by hand: no network, no backend, no image. The
// point of the layer under test is that it turns an AI reading into a plan
// WITHOUT inventing anything, so most of these tests assert on what stays
// null just as hard as on what gets computed.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

// ── Builders ──────────────────────────────────────────────────────────────

/// Title block of a readable DN100 Sch40 stainless drawing — enough for the
/// project header to come out complete, so header gaps do not drown the
/// segment assertions in tests that are not about the header.
AiTitleBlock _readableTitleBlock() => AiTitleBlock(
      lineNumber: 'DN100-P-1001-A1A',
      material: 'A312 TP316L',
      schedule: 'Sch 40',
      pipeClass: 'CL150',
    );

AiScanResult _scan({
  List<AiSegment> segments = const [],
  List<AiComponent> components = const [],
  AiTitleBlock? titleBlock,
  List<AiBomItem> bom = const [],
  String sizeNotation = 'DN',
  List<String> warnings = const [],
  String? error,
}) =>
    AiScanResult(
      segments: segments,
      components: components,
      titleBlock: titleBlock ?? _readableTitleBlock(),
      billOfMaterials: bom,
      sizeNotation: sizeNotation,
      warnings: warnings,
      error: error,
    );

AiComponent _comp(String id, String type, {String? label, String? valveType}) =>
    AiComponent(
      id: id,
      type: type,
      label: label,
      valveType: valveType,
      confidence: AiConfidence.high,
    );

AiSegment _seg(
  String id, {
  String? from,
  String? to,
  double? mm,
  String? raw,
  bool auxiliary = false,
  AiConfidence confidence = AiConfidence.high,
}) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: mm,
      rawDimension: raw,
      auxiliary: auxiliary,
      confidence: confidence,
    );

/// Whether two planned segments meet at a shared component — the property
/// route threading has to guarantee.
bool _meet(PlannedSegment a, PlannedSegment b) {
  final ends = <String>{
    if (a.start.componentId != null) a.start.componentId!,
    if (a.end.componentId != null) a.end.componentId!,
  };
  return ends.contains(b.start.componentId) || ends.contains(b.end.componentId);
}

List<ScanIssueCode> _codes(List<ScanIssue> issues) =>
    issues.map((i) => i.code).toList();

void main() {
  // ── Project header ─────────────────────────────────────────────────────

  group('project draft', () {
    test('DN + schedule from the title block give wall thickness', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.dn, 100);
      expect(plan.project.diameterMm, closeTo(114.3, 0.001));
      expect(plan.project.wallThicknessMm, closeTo(6.02, 0.001));
      expect(plan.project.schedule, '40');
      expect(plan.project.materialGroup, 'SS');
      expect(plan.project.name, 'DN100-P-1001-A1A');
      expect(plan.project.diameterSource, ScanValueSource.scan);
      expect(plan.project.wallThicknessSource, ScanValueSource.scan);
      expect(plan.project.isComplete, isTrue);
    });

    test('NPS bill of materials resolves the same way, carbon steel', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(),
        sizeNotation: 'NPS',
        bom: [
          AiBomItem(
            item: '1',
            description: 'PIPE, SMLS, BE',
            size: '4"',
            schedule: 'SCH 40',
            material: 'A106 GR.B',
          ),
        ],
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.dn, 100);
      expect(plan.project.diameterMm, closeTo(114.3, 0.001));
      expect(plan.project.wallThicknessMm, closeTo(6.02, 0.001));
      expect(plan.project.materialGroup, 'CS');
    });

    test('caller values win over the drawing and are marked as such', () {
      final plan = planFromScan(
        _scan(
          components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
          segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
        ),
        diameterMm: 60.3,
        wallThicknessMm: 5.54,
      );

      expect(plan.project.diameterMm, 60.3);
      expect(plan.project.wallThicknessMm, 5.54);
      expect(plan.project.dn, 50, reason: 'OD 60.3 is DN50');
      expect(plan.project.diameterSource, ScanValueSource.caller);
      expect(plan.project.wallThicknessSource, ScanValueSource.caller);
    });

    test('a schedule the app has no table for leaves the wall blank', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(
          lineNumber: 'DN100-P-1001',
          material: 'A312 TP316L',
          schedule: '40S',
        ),
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.wallThicknessMm, isNull);
      expect(plan.project.wallThicknessSource, ScanValueSource.none);
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingWallThickness));
    });

    test('an alloy grade is not forced into SS or CS', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(
          lineNumber: 'DN100-P-1001',
          material: 'A335 P22',
          schedule: '80',
        ),
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.materialGroup, isNull);
      expect(plan.project.materialText, 'A335 P22');
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingMaterialGroup));
    });
  });

  // ── Simple thread ──────────────────────────────────────────────────────

  group('elbow — pipe — flange', () {
    ScanPlan build() => planFromScan(_scan(
          components: [_comp('e1', 'elbow90'), _comp('f1', 'flange')],
          segments: [_seg('s1', from: 'e1', to: 'f1', mm: 1000)],
        ));

    test('classifies both ends with ComponentClassification', () {
      final seg = build().segments.single;

      expect(seg.sourceId, 's1');
      expect(seg.seqNo, 1);
      expect(seg.start.kind, ScanEndKind.axial);
      expect(seg.start.kind.code, 'axial');
      expect(seg.start.isPhysical, isFalse);
      expect(seg.end.kind, ScanEndKind.nonAxial);
      expect(seg.end.kind.code, 'nonAxial');
      expect(seg.end.isPhysical, isTrue);
      expect(seg.isoRefCode, 'AXIS|FACE_NEAR');
    });

    test('take-out for the elbow comes from the ASME table', () {
      final seg = build().segments.single;

      expect(seg.start.takeoutMm, 152, reason: '90° LR, DN100, ASME B16.9');
      expect(seg.start.takeoutNote, contains('B16.9'));
      expect(seg.start.offsetMm, 152);
      // The dimension stops at the flange face, so the flange adds nothing.
      expect(seg.end.takeoutMm, 0);
      expect(seg.end.offsetMm, 0);
    });

    test('a bodied end forces the fitter to confirm the reference, so no CUT',
        () {
      final plan = build();
      final seg = plan.segments.single;

      expect(seg.isoMm, 1000);
      expect(seg.dimRef, isNull);
      expect(seg.needsDimRefConfirmation, isTrue);
      expect(seg.proposedDimRef, DimRef.centreToFace);
      expect(seg.cutMm, isNull,
          reason: 'centre-to-face vs centre-to-end cannot be read off a photo');
      expect(
        _codes(plan.gaps),
        contains(ScanIssueCode.dimensionReferenceUnknown),
      );
      expect(plan.canSave, isFalse);
    });

    test('once the reference is confirmed, PrefabEngine gives the CUT', () {
      final resolved = build().segments.single.withDimRef(DimRef.centreToFace);

      expect(resolved.dimRef, DimRef.centreToFace);
      expect(resolved.cutMm, closeTo(848, 0.001), reason: '1000 − 152');
      expect(resolved.isComplete, isTrue);
    });

    // ASME B16.5 Class 150, NPS 4: weld-neck length through hub Y = 3.00 in.
    // = 76 mm; disc thickness C = 0.94 in. = 24 mm. Until 2026-09 the scanner
    // took C for every flange, so a run measured through a WN flange came out
    // 52 mm long.
    test('a weld-neck flange takes Y (76 mm), not the disc thickness C', () {
      final seg = build().segments.single;
      expect(seg.end.bodyLengthMm, 76, reason: 'B16.5 Cl.150 NPS 4, Y');

      final through = seg.withDimRef(DimRef.centreToEnd);
      expect(through.cutMm, closeTo(772, 0.001), reason: '1000 − 152 − 76');
    });

    test('"ISO" in a label is not read as a slip-on (word boundary)', () {
      final seg = planFromScan(_scan(
        components: [
          _comp('e1', 'elbow90'),
          _comp('f1', 'flange', label: 'ISO 4" 150# RF'),
        ],
        segments: [_seg('s1', from: 'e1', to: 'f1', mm: 1000)],
      )).segments.single;
      expect(seg.end.bodyLengthMm, 76);
    });

    test('slip-on / socket flanges get no invented body length', () {
      for (final label in ['SO 4" 150#', 'SLIP-ON', 'SW flange', 'LJ']) {
        final seg = planFromScan(_scan(
          components: [
            _comp('e1', 'elbow90'),
            _comp('f1', 'flange', label: label),
          ],
          segments: [_seg('s1', from: 'e1', to: 'f1', mm: 1000)],
        )).segments.single;
        expect(seg.end.bodyLengthMm, isNull, reason: label);
      }
    });

    test('a blind flange keeps the disc thickness C (24 mm)', () {
      final seg = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('b1', 'blindFlange')],
        segments: [_seg('s1', from: 'e1', to: 'b1', mm: 1000)],
      )).segments.single;
      expect(seg.end.bodyLengthMm, 24);
    });
  });

  group('elbow — pipe — elbow', () {
    test('two axial ends need no question and CUT is computed', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));
      final seg = plan.segments.single;

      expect(seg.dimRef, DimRef.centreToCentre);
      expect(seg.cutMm, closeTo(896, 0.001), reason: '1200 − 152 − 152');
      expect(seg.isComplete, isTrue);
      expect(plan.gaps, isEmpty);
      expect(plan.canSave, isTrue);
      // The LR default is stated out loud rather than hidden.
      expect(
        _codes(plan.warnings),
        contains(ScanIssueCode.takeoutAssumedLongRadius),
      );
    });

    test('a 45° elbow and an open end use their own numbers', () {
      final plan = planFromScan(_scan(
        components: [_comp('b1', 'elbow45')],
        segments: [_seg('s1', from: 'b1', mm: 900)],
      ));
      final seg = plan.segments.single;

      expect(seg.start.takeoutMm, 64, reason: '45° LR, DN100');
      expect(seg.end.kind, ScanEndKind.logical);
      expect(seg.end.takeoutMm, 0, reason: 'nothing is fitted on an open end');
      expect(seg.cutMm, closeTo(836, 0.001), reason: '900 − 64');
    });

    test('a short-radius marking is honoured instead of the LR default', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('e1', 'elbow90', label: '90° SR'),
          _comp('e2', 'elbow90', label: '90° SR'),
        ],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.segments.single.start.takeoutMm, 102, reason: 'SR DN100');
      expect(
        _codes(plan.warnings),
        isNot(contains(ScanIssueCode.takeoutAssumedLongRadius)),
      );
    });
  });

  // ── Route threading ────────────────────────────────────────────────────

  group('route order', () {
    test('a straight run is threaded from its open end', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('f1', 'flange'),
          _comp('e1', 'elbow90'),
          _comp('e2', 'elbow90'),
          _comp('f2', 'flange'),
        ],
        segments: [
          _seg('s1', from: 'f1', to: 'e1', mm: 500),
          _seg('s2', from: 'e1', to: 'e2', mm: 800),
          _seg('s3', from: 'e2', to: 'f2', mm: 300),
        ],
      ));

      expect(plan.segments.map((s) => s.sourceId).toList(),
          ['s1', 's2', 's3']);
      expect(plan.segments.map((s) => s.seqNo).toList(), [1, 2, 3]);
      expect(plan.runCount, 1);
      expect(_codes(plan.warnings),
          isNot(contains(ScanIssueCode.routeNotContinuous)));
    });

    test('segments delivered out of order still come back as one chain', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('f1', 'flange'),
          _comp('e1', 'elbow90'),
          _comp('e2', 'elbow90'),
          _comp('f2', 'flange'),
        ],
        segments: [
          _seg('s2', from: 'e1', to: 'e2', mm: 800),
          _seg('s3', from: 'e2', to: 'f2', mm: 300),
          _seg('s1', from: 'f1', to: 'e1', mm: 500),
        ],
      ));

      expect(plan.segments.length, 3);
      expect(plan.segments.map((s) => s.sourceId).toSet(),
          {'s1', 's2', 's3'});
      for (var i = 1; i < plan.segments.length; i++) {
        expect(_meet(plan.segments[i - 1], plan.segments[i]), isTrue,
            reason: 'consecutive planned segments must share a component');
      }
      expect(plan.runCount, 1);
    });

    test('a tee is a branch: flagged, never fatal', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('f1', 'flange'),
          _comp('t1', 'tee', label: 'T-01'),
          _comp('e1', 'elbow90'),
          _comp('f2', 'flange'),
        ],
        segments: [
          _seg('s1', from: 'f1', to: 't1', mm: 500),
          _seg('s2', from: 't1', to: 'e1', mm: 800),
          _seg('s3', from: 't1', to: 'f2', mm: 300),
        ],
      ));

      expect(plan.segments.length, 3, reason: 'no leg is dropped');
      expect(plan.segments.map((s) => s.sourceId).toSet(),
          {'s1', 's2', 's3'});
      expect(plan.runCount, 1);

      final branch =
          plan.warnings.where((w) => w.code == ScanIssueCode.branchInRoute);
      expect(branch, hasLength(1));
      expect(branch.single.componentId, 't1');
      expect(branch.single.blocking, isFalse);

      // The tee is axial on both of its in-line ends, so the middle segment
      // still gets a real cut.
      final s2 = plan.segments.firstWhere((s) => s.sourceId == 's2');
      expect(s2.start.kind, ScanEndKind.axial);
      // ASME B16.9-2018 Tab. 6.1-7: NPS 4 tee C = 4.12 in = 105 mm (the
      // catalog used to say 102).
      expect(s2.start.takeoutMm, 105, reason: 'tee CTE, DN100');
      expect(s2.cutMm, closeTo(543, 0.001), reason: '800 − 105 − 152');
      expect(plan.segments.where((s) => s.isBranch).length, 3);
    });

    test('two disconnected runs are reported, not merged silently', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('e1', 'elbow90'),
          _comp('e2', 'elbow90'),
          _comp('e3', 'elbow90'),
          _comp('e4', 'elbow90'),
        ],
        segments: [
          _seg('s1', from: 'e1', to: 'e2', mm: 1200),
          _seg('s2', from: 'e3', to: 'e4', mm: 900),
        ],
      ));

      expect(plan.runCount, 2);
      expect(plan.segments.length, 2);
      expect(_codes(plan.warnings),
          contains(ScanIssueCode.routeNotContinuous));
      expect(plan.segments[1].startsNewRun, isTrue);
      // A break in the route does not poison the arithmetic of either run.
      expect(plan.segments[0].cutMm, closeTo(896, 0.001));
      expect(plan.segments[1].cutMm, closeTo(596, 0.001));
    });
  });

  // ── Auxiliary lines ────────────────────────────────────────────────────

  test('auxiliary lines are skipped but counted', () {
    final plan = planFromScan(_scan(
      components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
      segments: [
        _seg('aux1', from: 'e1', to: 'e2', mm: 250, auxiliary: true),
        _seg('s1', from: 'e1', to: 'e2', mm: 1200),
        _seg('aux2', mm: 90, auxiliary: true),
      ],
    ));

    expect(plan.segments.map((s) => s.sourceId).toList(), ['s1']);
    expect(plan.auxiliarySegmentCount, 2);

    final skipped = plan.warnings
        .where((w) => w.code == ScanIssueCode.auxiliarySegmentsSkipped);
    expect(skipped, hasLength(1));
    expect(skipped.single.blocking, isFalse);
    expect(skipped.single.pl, contains('2'));
    expect(skipped.single.en, contains('2'));
  });

  test('a drawing of nothing but auxiliary lines blocks the save', () {
    final plan = planFromScan(_scan(
      segments: [_seg('aux1', mm: 250, auxiliary: true)],
    ));

    expect(plan.segments, isEmpty);
    expect(plan.auxiliarySegmentCount, 1);
    expect(_codes(plan.gaps), contains(ScanIssueCode.noUsableSegments));
    expect(plan.canSave, isFalse);
  });

  // ── Components the app cannot identify ─────────────────────────────────

  group('unknown components', () {
    test('an unknown type warns, goes logical, and blocks the CUT', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('x1', 'gizmo')],
        segments: [_seg('s1', from: 'e1', to: 'x1', mm: 1000)],
      ));
      final seg = plan.segments.single;

      final unknown = plan.warnings
          .where((w) => w.code == ScanIssueCode.unknownComponentType);
      expect(unknown, hasLength(1));
      expect(unknown.single.componentId, 'x1');
      expect(unknown.single.blocking, isFalse);
      expect(unknown.single.pl, contains('gizmo'));

      expect(seg.end.kind, ScanEndKind.logical);
      expect(seg.end.isResolved, isFalse);
      expect(seg.end.behaviour, isNull);
      expect(seg.end.takeoutMm, isNull,
          reason: 'an unidentified end must not contribute a silent zero');
      expect(seg.end.offsetMm, isNull);
      expect(seg.cutMm, isNull);
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingTakeout));
      expect(plan.canSave, isFalse);
    });

    test('a valve without a subtype still classifies but asks for its length',
        () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('v1', 'valve')],
        segments: [_seg('s1', from: 'e1', to: 'v1', mm: 1000)],
      ));
      final seg = plan.segments.single;

      expect(seg.end.kind, ScanEndKind.nonAxial);
      expect(seg.end.isResolved, isTrue);
      expect(seg.end.bodyLengthMm, isNull,
          reason: 'no face-to-face table applies until the type is known');
      expect(_codes(plan.warnings), contains(ScanIssueCode.valveTypeUnknown));
    });

    test('a gate valve on a Class 150 line picks up its face-to-face', () {
      final plan = planFromScan(_scan(
        components: [
          _comp('e1', 'elbow90'),
          _comp('v1', 'valve', valveType: 'gate'),
        ],
        segments: [_seg('s1', from: 'e1', to: 'v1', mm: 1000)],
      ));
      final seg = plan.segments.single;

      expect(seg.end.bodyLengthMm, 229, reason: 'DN100 gate, Class 150');
      expect(
          _codes(plan.warnings), isNot(contains(ScanIssueCode.valveTypeUnknown)));
    });

    test('a globe valve on a Class 150 line uses the globe column (292)', () {
      final seg = planFromScan(_scan(
        components: [
          _comp('e1', 'elbow90'),
          _comp('v1', 'valve', valveType: 'globe'),
        ],
        segments: [_seg('s1', from: 'e1', to: 'v1', mm: 1000)],
      )).segments.single;

      expect(seg.end.bodyLengthMm, 292,
          reason: 'ASME B16.10 Class 150 globe, NPS 4 = 11.50 in.');
    });

    test('a reducer flags the diameter change downstream', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('r1', 'reducer')],
        segments: [_seg('s1', from: 'e1', to: 'r1', mm: 1000)],
      ));

      expect(plan.segments.single.end.kind, ScanEndKind.nonAxial);
      expect(_codes(plan.warnings),
          contains(ScanIssueCode.reducerChangesDiameter));
    });

    test('a weld end is a logical point, not a body', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('w1', 'fieldWeld')],
        segments: [_seg('s1', from: 'e1', to: 'w1', mm: 1000)],
      ));
      final seg = plan.segments.single;

      expect(seg.end.kind, ScanEndKind.logical);
      expect(seg.end.isPhysical, isFalse);
      expect(seg.dimRef, DimRef.centreToCentre);
      expect(seg.cutMm, closeTo(848, 0.001), reason: '1000 − 152');
    });
  });

  // ── Dimensions ─────────────────────────────────────────────────────────

  group('dimensions', () {
    test('a segment with no dimension at all blocks the save', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2')],
      ));
      final seg = plan.segments.single;

      expect(seg.isoMm, isNull);
      expect(seg.isoExpr, isNull);
      expect(seg.cutMm, isNull, reason: 'no dimension, no invented length');

      final missing = plan.gaps
          .where((g) => g.code == ScanIssueCode.missingDimension)
          .toList();
      expect(missing, hasLength(1));
      expect(missing.single.segmentId, 's1');
      expect(missing.single.blocking, isTrue);
      expect(plan.canSave, isFalse);
    });

    test('an unreadable raw dimension is reported with the text it saw', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', raw: '1?0O')],
      ));

      expect(plan.segments.single.isoMm, isNull);
      expect(plan.segments.single.cutMm, isNull);
      final gap = plan.gaps
          .firstWhere((g) => g.code == ScanIssueCode.missingDimension);
      expect(gap.dimensionLabel, '1?0O');
      expect(gap.pl, contains('1?0O'));
    });

    test('an imperial raw dimension is converted, not guessed', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', raw: '4\' 6"')],
      ));
      final seg = plan.segments.single;

      expect(seg.isoExpr, '4\' 6"');
      expect(seg.isoMm, closeTo(1371.6, 0.001), reason: '54 in');
      expect(seg.cutMm, closeTo(1067.6, 0.001), reason: '1371.6 − 152 − 152');
      expect(_codes(plan.gaps),
          isNot(contains(ScanIssueCode.missingDimension)));
    });

    test('a dimension shorter than its fittings is refused, not cut', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 200)],
      ));

      expect(plan.segments.single.cutMm, isNull,
          reason: '200 − 152 − 152 is negative');
      expect(_codes(plan.gaps), contains(ScanIssueCode.cutImpossible));
    });

    test('a zero or negative dimension counts as missing', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 0)],
      ));

      expect(plan.segments.single.isoMm, isNull);
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingDimension));
    });
  });

  // ── Confidence ─────────────────────────────────────────────────────────

  group('confidence', () {
    test('a low-confidence reading is warned about by its printed value', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [
          _seg('s1',
              from: 'e1',
              to: 'e2',
              mm: 1200,
              raw: '1200',
              confidence: AiConfidence.low),
        ],
      ));

      final low =
          plan.warnings.where((w) => w.code == ScanIssueCode.lowConfidence);
      expect(low, hasLength(1));
      expect(low.single.segmentId, 's1');
      expect(low.single.dimensionLabel, '1200',
          reason: 'the screen highlights exactly this number');
      expect(low.single.blocking, isFalse);
      // A shaky reading is still worth planning — it just gets flagged.
      expect(plan.segments.single.cutMm, closeTo(896, 0.001));
      expect(plan.canSave, isTrue);
    });

    test('an absent confidence is treated as unsure, not as certain', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [
          AiSegment(id: 's1', fromId: 'e1', toId: 'e2', dimensionMm: 1200),
        ],
      ));

      expect(_codes(plan.warnings), contains(ScanIssueCode.lowConfidence));
    });

    test('a high-confidence reading raises nothing', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(_codes(plan.warnings),
          isNot(contains(ScanIssueCode.lowConfidence)));
    });
  });

  // ── Degenerate input ───────────────────────────────────────────────────

  group('degenerate scans', () {
    test('an empty scan yields an empty plan, not a crash', () {
      final plan = planFromScan(AiScanResult());

      expect(plan.segments, isEmpty);
      expect(plan.auxiliarySegmentCount, 0);
      expect(plan.runCount, 0);
      expect(plan.canSave, isFalse);
      expect(_codes(plan.gaps), contains(ScanIssueCode.noUsableSegments));
      expect(plan.project.diameterMm, isNull);
      expect(plan.project.wallThicknessMm, isNull);
      expect(plan.project.materialGroup, isNull);
    });

    test('a failed scan stops before planning anything', () {
      final plan = planFromScan(_scan(
        error: 'not_an_isometric',
        components: [_comp('e1', 'elbow90')],
        segments: [_seg('s1', from: 'e1', mm: 1000)],
      ));

      expect(_codes(plan.gaps), [ScanIssueCode.scanFailed]);
      expect(plan.segments, isEmpty);
      expect(plan.canSave, isFalse);
    });

    test('a not-an-isometric warning counts as a failed scan', () {
      final plan = planFromScan(_scan(
        warnings: ['not_an_isometric: this is a photo of a cat'],
        segments: [_seg('s1', mm: 1000)],
      ));

      expect(_codes(plan.gaps), contains(ScanIssueCode.scanFailed));
      expect(plan.segments, isEmpty);
    });

    test('a fromId pointing at nothing is a warning, and the CUT is refused',
        () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90')],
        segments: [_seg('s1', from: 'ghost', to: 'e1', mm: 1000)],
      ));
      final seg = plan.segments.single;

      final broken = plan.warnings
          .where((w) => w.code == ScanIssueCode.unresolvedComponentRef);
      expect(broken, hasLength(1));
      expect(broken.single.componentId, 'ghost');
      expect(broken.single.segmentId, 's1');
      expect(broken.single.blocking, isFalse);

      expect(seg.start.isResolved, isFalse);
      expect(seg.start.componentId, 'ghost');
      expect(seg.start.takeoutMm, isNull);
      expect(seg.cutMm, isNull);
      expect(seg.isoMm, 1000, reason: 'the dimension itself was still read');
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingTakeout));
    });

    test('segments still thread through a component that was never listed',
        () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [
          _seg('s1', from: 'e1', to: 'ghost', mm: 800),
          _seg('s2', from: 'ghost', to: 'e2', mm: 600),
        ],
      ));

      expect(plan.runCount, 1,
          reason: 'the drawing says they meet, even if we cannot name the joint');
      expect(plan.segments.map((s) => s.sourceId).toList(), ['s1', 's2']);
      expect(plan.segments.every((s) => s.cutMm == null), isTrue);
    });

    test('a component with no id and no components list does not crash', () {
      final plan = planFromScan(_scan(
        components: const [],
        segments: [_seg('', mm: 1000)],
      ));

      expect(plan.segments, hasLength(1));
      expect(plan.segments.single.sourceId, 'seg1');
      expect(plan.segments.single.start, same(ScanEndpoint.openEnd));
      expect(plan.segments.single.cutMm, closeTo(1000, 0.001),
          reason: 'open end to open end is the raw dimension');
    });
  });

  // ── The core promise ───────────────────────────────────────────────────

  group('nothing is invented', () {
    test('with no title block and no BOM every header field stays blank', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(),
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.dn, isNull);
      expect(plan.project.diameterMm, isNull);
      expect(plan.project.wallThicknessMm, isNull);
      expect(plan.project.schedule, isNull);
      expect(plan.project.materialGroup, isNull);
      expect(plan.project.diameterSource, ScanValueSource.none);
      expect(plan.project.wallThicknessSource, ScanValueSource.none);
      expect(plan.project.materialGroupSource, ScanValueSource.none);
      expect(plan.project.isComplete, isFalse);

      expect(
        _codes(plan.gaps),
        containsAll([
          ScanIssueCode.missingDiameter,
          ScanIssueCode.missingWallThickness,
          ScanIssueCode.missingMaterialGroup,
        ]),
      );
    });

    test('without a nominal size no take-out is guessed, so no CUT', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(),
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));
      final seg = plan.segments.single;

      expect(seg.start.takeoutMm, isNull);
      expect(seg.start.takeoutNote, isNull);
      expect(seg.cutMm, isNull);
      expect(seg.isComplete, isFalse);
      expect(_codes(plan.gaps), contains(ScanIssueCode.missingTakeout));
    });

    test('an ambiguous bare size on an unknown notation is not resolved', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(lineNumber: '100-P-1001', schedule: '40'),
        sizeNotation: 'unknown',
        components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
        segments: [_seg('s1', from: 'e1', to: 'e2', mm: 1200)],
      ));

      expect(plan.project.dn, isNull,
          reason: '"100" is DN100 on ISO and nonsense as NPS');
      expect(plan.project.diameterMm, isNull);
    });

    test('every planned CUT is a positive finite number or absent', () {
      final plans = <ScanPlan>[
        planFromScan(_scan(
          components: [_comp('e1', 'elbow90'), _comp('f1', 'flange')],
          segments: [_seg('s1', from: 'e1', to: 'f1', mm: 1000)],
        )),
        planFromScan(_scan(
          titleBlock: AiTitleBlock(),
          components: [_comp('x1', 'gizmo')],
          segments: [_seg('s1', from: 'x1')],
        )),
        planFromScan(_scan(
          components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
          segments: [_seg('s1', from: 'e1', to: 'e2', mm: 100)],
        )),
        planFromScan(_scan(
          components: [_comp('e1', 'elbow90'), _comp('e2', 'elbow90')],
          segments: [_seg('s1', from: 'e1', to: 'e2', raw: 'illegible')],
        )),
      ];

      for (final plan in plans) {
        for (final seg in plan.segments) {
          final cut = seg.cutMm;
          if (cut != null) {
            expect(cut.isFinite, isTrue);
            expect(cut, greaterThan(0));
            expect(seg.isoMm, isNotNull,
                reason: 'a CUT without a dimension would be fabricated');
            expect(seg.dimRef, isNotNull);
          }
        }
        // Anything that could not be planned has to be visible as a gap.
        final incomplete =
            plan.segments.where((s) => !s.isComplete).map((s) => s.sourceId);
        for (final id in incomplete) {
          expect(plan.gapsFor(id), isNotEmpty,
              reason: 'segment $id is incomplete and must say why');
        }
      }
    });

    test('gaps block and warnings do not', () {
      final plan = planFromScan(_scan(
        components: [_comp('e1', 'elbow90'), _comp('x1', 'gizmo')],
        segments: [
          _seg('s1',
              from: 'e1', to: 'x1', mm: 1000, confidence: AiConfidence.low),
        ],
      ));

      expect(plan.gaps.every((g) => g.blocking), isTrue);
      expect(plan.warnings.every((w) => !w.blocking), isTrue);
      expect(plan.has(ScanIssueCode.lowConfidence), isTrue);
      expect(plan.warningsFor('s1'), isNotEmpty);
      expect(plan.gapsFor('s1'), isNotEmpty);
    });

    test('every issue carries both languages', () {
      final plan = planFromScan(_scan(
        titleBlock: AiTitleBlock(),
        components: [_comp('x1', 'gizmo')],
        segments: [_seg('s1', from: 'x1')],
      ));

      for (final issue in [...plan.gaps, ...plan.warnings]) {
        expect(issue.pl, isNotEmpty);
        expect(issue.en, isNotEmpty);
        expect(issue.text(polish: true), issue.pl);
        expect(issue.text(polish: false), issue.en);
      }
    });
  });
}
