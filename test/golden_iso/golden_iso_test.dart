// Złoty zestaw referencyjny skanera ISO — wersja offline.
//
// Każdy plik `*.json` w tym katalogu to RĘCZNIE zapisany odczyt AI (koperta
// `{result, tookMs, model}` dokładnie taka, jaką zwraca POST
// /api/fitter/scan-iso) dla typowej izometrii, razem z tym, co monter robi na
// ekranie przeglądu, i z oczekiwanym wynikiem policzonym ręcznie (pole
// `calc`: ISO − take-outy ASME B16.9 / B16.5 / B16.10 − szczelina × spoiny).
// To NIE są prawdziwe zdjęcia: sprawdzają deterministyczną część skanera
// (planista → zapis projektu → CUT z bazy), nie rozpoznawanie obrazu.
// Walidacja na prawdziwych rysunkach wymaga zdjęć izometrii od właściciela.
//
// Format (`format: "fwp-golden-iso"`, `formatVersion: 2`) — rozszerzalny:
// nieznane pola są ignorowane, nowa wersja formatu = nowy numer.
// v2 (2026-09-25, schemat odczytu v2): koperta może mieć pola v2 (dn,
// direction, projections, connectedTo, runIds, welds[], spools[]…); monter
// może podać DN odcinka i take-out; oczekiwania mogą sprawdzać DN / OD /
// etykietę odcinka.
//   id, title, drawing          opis przypadku i rysunku
//   gapMm                       szczelina na spoinę projektu (jak w przeglądzie)
//   envelope                    odczyt AI: {result: AiScanResult, tookMs, model}
//   knownLimitations[]          czego ten przypadek świadomie nie sprawdza
//   steps[]                     kolejne kroki montera na ekranie przeglądu:
//     fitter.diameterMm / wallThicknessMm / materialGroup
//                               wartości wpisane w nagłówku przeglądu
//     fitter.segmentDn {segId: DN}   średnica odcinka wybrana przez montera
//     fitter.takeouts {"komponent@segId": mm}
//                               take-out / długość korpusu wpisana ręcznie
//     fitter.dimensions {segId: "tekst"}
//                               wymiar przepisany/potwierdzony z rysunku
//                               (jak _setDimension: pewność → high)
//     fitter.references {segId: "proposal" | CTC | CTF | FTF | FTE | CTE | ETE}
//                               odpowiedź na „jak zmierzono wymiar"
//     expect.canSave            czy przycisk zapisu byłby aktywny
//     expect.gaps[]             DOKŁADNY zbiór otwartych blokad (kody)
//     expect.warnings[]         ostrzeżenia, które MUSZĄ się pojawić
//     expect.segments[]         {id, cutMm|null, proposed?, calc,
//                                dn?, diameterMm?, label?}
// Ostatni krok z `canSave: true` jest zapisywany do bazy tak jak robi to
// scan_review_screen (ProjectDao + SegmentDao z segmentRowFor), a CUT jest
// czytany z powrotem z tabeli `segments` i przeliczany z zapisanego wiersza.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

import '../support/test_database.dart';

const _kFormat = 'fwp-golden-iso';
const _kFormatVersion = 2;

/// Kopia odczytu z wymiarami przepisanymi przez montera — jak robi to ekran
/// przeglądu (`_setDimension`): wymiar i tekst z rysunku, pewność „high".
AiScanResult _withDimensions(AiScanResult scan, Map<String, String> dims) {
  if (dims.isEmpty) return scan;
  return scan.copyWith(
    segments: [
      for (final s in scan.segments)
        dims.containsKey(s.id)
            ? s.copyWith(
                dimensionMm: _mm(dims[s.id]!),
                rawDimension: dims[s.id],
                confidence: AiConfidence.high,
                userConfirmed: true,
              )
            : s,
    ],
  );
}

double _mm(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null) throw FormatException('wymiar montera: $text');
  return v;
}

ScanStops _answer(PlannedSegment seg, String code) {
  if (code == 'proposal') return seg.proposedStops;
  if (code == 'ETE') return const ScanStops(SideStop.end, SideStop.end);
  return stopsForDimRef(seg, parseDimRefCode(code));
}

String _refCode(ScanStops stops) => stops.dimRef?.code ?? 'ETE';

class _Step {
  final ScanPlan plan;
  final List<PlannedSegment> segments;
  final List<ScanIssue> openGaps;
  final bool canSave;
  final double? diameterMm;
  final double? wallThicknessMm;
  final String? materialGroup;
  _Step(this.plan, this.segments, this.openGaps, this.canSave,
      this.diameterMm, this.wallThicknessMm, this.materialGroup);
}

/// Jeden krok montera na ekranie przeglądu — ta sama logika co
/// `ScanReviewScreen._recompute` / `_computeOpenGaps` / `_canSave`.
_Step _runStep(AiScanResult scan, Map<String, dynamic> fitter, double gapMm) {
  final dia = (fitter['diameterMm'] as num?)?.toDouble();
  final wall = (fitter['wallThicknessMm'] as num?)?.toDouble();
  final dims = ((fitter['dimensions'] as Map?) ?? const {})
      .map((k, v) => MapEntry(k as String, v as String));
  final refs = ((fitter['references'] as Map?) ?? const {})
      .map((k, v) => MapEntry(k as String, v as String));
  final input = ScanFitterInput(
    segmentDn: ((fitter['segmentDn'] as Map?) ?? const {})
        .map((k, v) => MapEntry(k as String, (v as num).toInt())),
    segmentWallMm: ((fitter['segmentWallMm'] as Map?) ?? const {})
        .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
    takeoutMm: ((fitter['takeouts'] as Map?) ?? const {})
        .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
  );

  final corrected = _withDimensions(scan, dims);
  final plan = planFromScan(
    corrected,
    diameterMm: dia,
    wallThicknessMm: wall,
    gapMm: gapMm,
    fitter: input,
  );

  final segments = plan.segments.map((s) {
    if (!s.needsDimRefConfirmation) return s;
    final code = refs[s.sourceId];
    return code == null ? s : s.withStops(_answer(s, code));
  }).toList();

  final material =
      (fitter['materialGroup'] as String?) ?? plan.project.materialGroup;
  final open = <ScanIssue>[];
  for (final gap in plan.gaps) {
    switch (gap.code) {
      case ScanIssueCode.missingMaterialGroup:
        if (material == null) open.add(gap);
      case ScanIssueCode.dimensionReferenceUnknown:
        final seg = segments.where((s) => s.sourceId == gap.segmentId);
        if (seg.isEmpty || seg.single.cutMm == null) open.add(gap);
      default:
        open.add(gap);
    }
  }
  final diameter = dia ?? plan.project.diameterMm;
  final wallMm = wall ?? plan.project.wallThicknessMm;
  final canSave = open.isEmpty &&
      segments.isNotEmpty &&
      diameter != null &&
      wallMm != null &&
      material != null &&
      segments.every((s) => s.isComplete);
  return _Step(plan, segments, open, canSave, diameter, wallMm, material);
}

/// Zapis jak `ScanReviewScreen._save`, potem odczyt z bazy.
Future<List<Map<String, Object?>>> _saveAndReadBack(
    String caseId, _Step step, double gapMm) async {
  final projectId = 'golden-$caseId';
  final now = DateTime(2026, 9, 25).millisecondsSinceEpoch;
  await ProjectDao().insert(Project(
    id: projectId,
    name: 'Złoty zestaw $caseId',
    materialGroup: step.materialGroup!,
    diameterMm: step.diameterMm!,
    wallThicknessMm: step.wallThicknessMm!,
    currentDiameterMm: step.diameterMm!,
    stockLengthMm: 6000,
    sawKerfMm: 1.5,
    gapMm: gapMm,
    createdAt: now,
    updatedAt: now,
  ));
  final dao = SegmentDao();
  var n = 0;
  for (final seg in step.segments) {
    final row = segmentRowFor(
      seg,
      id: '$projectId-${++n}',
      projectId: projectId,
      diameterMm: step.diameterMm!,
      wallThicknessMm: step.wallThicknessMm!,
      nowMs: now,
    );
    expect(row, isNotNull, reason: '$caseId: ${seg.sourceId} bez wiersza');
    await dao.insert(row!);
  }
  final saved = await dao.listForProject(projectId);
  return [
    for (final s in saved)
      {
        'seq': s.seqNo,
        'cut': s.cutMm,
        'od': s.diameterMm,
        'recomputed': PrefabEngine.storedSegmentCutMm(
          isoMm: s.isoMm,
          isoRef: s.isoRef,
          startKind: s.startKind,
          startValueMm: s.startValueMm,
          endKind: s.endKind,
          endValueMm: s.endValueMm,
          gapMm: gapMm,
        ),
      }
  ];
}

List<File> _goldenFiles() {
  final dir = Directory('test/golden_iso');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  useTestDatabase();

  final files = _goldenFiles();

  test('zestaw ma co najmniej 8 przypadków w obsługiwanym formacie', () {
    expect(files.length, greaterThanOrEqualTo(8));
    final ids = <String>{};
    for (final f in files) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(j['format'], _kFormat, reason: f.path);
      expect(j['formatVersion'], _kFormatVersion, reason: f.path);
      expect(ids.add(j['id'] as String), isTrue, reason: 'powtórzone id');
      expect((j['steps'] as List), isNotEmpty, reason: f.path);
    }
  });

  for (final file in files) {
    final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final id = j['id'] as String;
    final title = j['title'] as String;

    test('$id — $title', () async {
      final scan = AiScanResult.fromEnvelope(
          (j['envelope'] as Map).cast<String, dynamic>());
      final gapMm = (j['gapMm'] as num?)?.toDouble() ?? 0;
      final steps = (j['steps'] as List).cast<Map<String, dynamic>>();

      _Step? last;
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final where = '$id krok ${i + 1}';
        final fitter =
            (step['fitter'] as Map?)?.cast<String, dynamic>() ?? const {};
        final expected = (step['expect'] as Map).cast<String, dynamic>();
        final got = _runStep(scan, fitter, gapMm);
        last = got;

        // Blokady: dokładnie te, nie więcej i nie mniej.
        final gapCodes = got.openGaps.map((g) => g.code.name).toSet();
        expect(gapCodes,
            ((expected['gaps'] as List?) ?? const []).cast<String>().toSet(),
            reason: '$where: otwarte blokady\n'
                '${got.openGaps.map((g) => '  ${g.code.name}: ${g.pl}').join('\n')}');
        for (final w in ((expected['warnings'] as List?) ?? const [])) {
          expect(got.plan.has(ScanIssueCode.values.byName(w as String)), isTrue,
              reason: '$where: brak ostrzeżenia $w');
        }
        expect(got.canSave, expected['canSave'], reason: '$where: canSave');

        final expSegs =
            ((expected['segments'] as List?) ?? const []).cast<Map>();
        if (expSegs.isNotEmpty) {
          expect(got.segments.map((s) => s.sourceId).toList(),
              expSegs.map((e) => e['id']).toList(),
              reason: '$where: kolejność odcinków na trasie');
        }
        for (final e in expSegs) {
          final seg = got.segments.singleWhere((s) => s.sourceId == e['id']);
          final calc = e['calc'] ?? '';
          final cut = (e['cutMm'] as num?)?.toDouble();
          if (cut == null) {
            expect(seg.cutMm, isNull, reason: '$where ${e['id']}: $calc');
          } else {
            expect(seg.cutMm, isNotNull, reason: '$where ${e['id']}: $calc');
            expect(seg.cutMm!, closeTo(cut, 0.001),
                reason: '$where ${e['id']}: $calc');
          }
          if (e.containsKey('dn')) {
            expect(seg.dn, e['dn'], reason: '$where ${e['id']}: DN odcinka');
          }
          if (e['diameterMm'] != null) {
            expect(seg.diameterMm,
                closeTo((e['diameterMm'] as num).toDouble(), 0.001),
                reason: '$where ${e['id']}: OD odcinka');
          }
          if (e['label'] != null) {
            expect(seg.label, e['label'], reason: '$where ${e['id']}: etykieta');
          }
          if (e['proposed'] != null) {
            expect(_refCode(seg.proposedStops), e['proposed'],
                reason: '$where ${e['id']}: proponowane odniesienie');
          }
        }
      }

      // Zapis jak na ekranie przeglądu i CUT z bazy.
      final finalStep = steps.last;
      final finalExpect = (finalStep['expect'] as Map).cast<String, dynamic>();
      if (finalExpect['canSave'] == true) {
        final rows = await _saveAndReadBack(id, last!, gapMm);
        final expSegs = (finalExpect['segments'] as List).cast<Map>();
        expect(rows, hasLength(expSegs.length), reason: '$id: wiersze w bazie');
        for (var k = 0; k < rows.length; k++) {
          final cut = (expSegs[k]['cutMm'] as num).toDouble();
          expect(rows[k]['seq'], k + 1);
          final od = expSegs[k]['diameterMm'];
          if (od != null) {
            expect(rows[k]['od'] as double,
                closeTo((od as num).toDouble(), 0.001),
                reason: '$id: OD odcinka w bazie');
          }
          expect(rows[k]['cut'] as double, closeTo(cut, 0.001),
              reason: '$id: CUT z bazy, ${expSegs[k]['calc']}');
          // Jedno źródło CUT: przeliczenie zapisanego wiersza daje to samo.
          expect(rows[k]['recomputed'] as double, closeTo(cut, 0.001),
              reason: '$id: przeliczenie wiersza ${expSegs[k]['id']}');
        }
      }
    });
  }
}
