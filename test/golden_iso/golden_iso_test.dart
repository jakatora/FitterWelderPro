// Złoty zestaw referencyjny skanera ISO — wersja offline.
//
// Każdy plik `*.json` w tym katalogu to RĘCZNIE zapisany odczyt AI (koperta
// `{result, tookMs, model}` dokładnie taka, jaką zwraca POST
// /api/fitter/scan-iso) dla typowej izometrii, razem z tym, co monter robi na
// ekranie przeglądu, i z oczekiwanym wynikiem policzonym ręcznie (pole
// `calc`: ISO − take-outy ASME B16.9 / B16.11 / B16.5 / B16.10 − szczelina ×
// spoiny). To NIE są prawdziwe zdjęcia: sprawdzają deterministyczną część
// skanera (planista → zapis projektu → CUT z bazy, mapa spoin, BOM, spoole,
// dziennik spoin), nie rozpoznawanie obrazu. Walidacja na prawdziwych
// rysunkach wymaga zdjęć izometrii od właściciela.
//
// Format (`format: "fwp-golden-iso"`, `formatVersion: 2`) — rozszerzalny:
// nieznane pola są ignorowane, nowa wersja formatu = nowy numer.
// v2 (2026-09-25, schemat odczytu v2): koperta może mieć pola v2 (dn,
// direction, projections, connectedTo, runIds, welds[], spools[]…); monter
// może podać DN odcinka i take-out; blokada dotyczy tylko swojego cięcia
// (zapis częściowy); oczekiwania sprawdzają też DN / OD / etykietę odcinka,
// mapę spoin, porównanie BOM, spoole i wpisy dziennika spoin.
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
//     expect.canSave            czy przycisk „Zapisz projekt" byłby aktywny
//                               (projekt bez blokad projektu + ≥1 gotowe cięcie)
//     expect.gaps[]             DOKŁADNY zbiór otwartych blokad (kody)
//     expect.warnings[]         ostrzeżenia, które MUSZĄ się pojawić
//     expect.segments[]         {id, cutMm|null, proposed?, calc, dn?,
//                                diameterMm?, label?, blocked?}
//                               blocked: cięcie czeka (nie zapisze się)
//     expect.welds              {count?, field?, numbers?[], assigned?}
//     expect.bom[]              {label (fragment etykiety PL), status}
//     expect.spools[]           {label, segments[] (id)}
//     expect.journal            {create, skippedOnReimport}
// Ostatni krok z `canSave: true` jest zapisywany do bazy tak jak robi to
// scan_review_screen (ProjectDao + SegmentDao z segmentRowFor, tylko cięcia
// gotowe), a CUT jest czytany z powrotem z tabeli `segments` i przeliczany
// z zapisanego wiersza; `journal` — wpisy przez WeldJournalDao, drugi import
// tego samego rysunku nie tworzy duplikatów.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/scan_outputs.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

import '../support/test_database.dart';

const _kFormat = 'fwp-golden-iso';
const _kFormatVersion = 2;

/// Kopia odczytu z wymiarami przepisanymi przez montera — jak robi to ekran
/// przeglądu (`_setDimension`): wymiar i tekst z rysunku, pewność „high",
/// odczyt oznaczony jako jego.
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
  final AiScanResult scan;
  final ScanPlan plan;
  final List<PlannedSegment> segments;
  final ScanReviewGate gate;
  final double? diameterMm;
  final double? wallThicknessMm;
  final String? materialGroup;
  _Step(this.scan, this.plan, this.segments, this.gate, this.diameterMm,
      this.wallThicknessMm, this.materialGroup);
}

/// Jeden krok montera na ekranie przeglądu — ta sama logika co
/// `ScanReviewScreen._recompute` (planFromScan + odpowiedzi + evaluateReview).
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
  final diameter = dia ?? plan.project.diameterMm;
  final wallMm = wall ?? plan.project.wallThicknessMm;
  final gate = evaluateReview(
    plan: plan,
    segments: segments,
    materialGroup: material,
    headerComplete: diameter != null && wallMm != null && material != null,
  );
  return _Step(corrected, plan, segments, gate, diameter, wallMm, material);
}

/// Zapis jak `ScanReviewScreen._save` (tylko cięcia gotowe, numeracja 1..n),
/// potem odczyt z bazy.
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
  final savable = step.gate.savable;
  for (var i = 0; i < savable.length; i++) {
    final seg = savable[i].renumbered(i + 1, savable[i].label);
    final row = segmentRowFor(
      seg,
      id: '$projectId-${i + 1}',
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

void _checkOutputs(String where, _Step got, Map<String, dynamic> expected) {
  final welds = buildWeldMap(got.scan, got.segments);
  final w = (expected['welds'] as Map?)?.cast<String, dynamic>();
  if (w != null) {
    if (w['count'] != null) {
      expect(welds, hasLength(w['count']), reason: '$where: liczba spoin');
    }
    if (w['field'] != null) {
      expect(welds.where((x) => x.isField).length, w['field'],
          reason: '$where: spoiny montażowe');
    }
    if (w['numbers'] != null) {
      expect(welds.map((x) => x.number).toList(),
          (w['numbers'] as List).cast<String>(),
          reason: '$where: numery spoin');
    }
    if (w['assigned'] != null) {
      expect(welds.every((x) => x.numberAssigned == w['assigned']), isTrue,
          reason: '$where: numery nadane przez aplikację');
    }
  }
  final bom = (expected['bom'] as List?)?.cast<Map>();
  if (bom != null) {
    final lines = compareBom(got.scan, got.segments);
    for (final e in bom) {
      final label = e['label'] as String;
      final match = lines.where((l) => l.labelPl.contains(label)).toList();
      expect(match, isNotEmpty,
          reason: '$where: brak pozycji BOM "$label" w '
              '${lines.map((l) => l.labelPl).toList()}');
      expect(match.first.status.name, e['status'],
          reason: '$where: BOM "$label": ${match.first.notePl}');
    }
  }
  final spools = (expected['spools'] as List?)?.cast<Map>();
  if (spools != null) {
    final got2 = buildSpools(got.scan, got.segments, welds);
    expect(got2.map((s) => s.label).toList(),
        spools.map((s) => s['label']).toList(),
        reason: '$where: spoole');
    for (var i = 0; i < spools.length; i++) {
      expect(got2[i].segments.map((s) => s.sourceId).toList(),
          (spools[i]['segments'] as List).cast<String>(),
          reason: '$where: odcinki spoola ${spools[i]['label']}');
    }
  }
}

void main() {
  useTestDatabase();

  final files = _goldenFiles();

  test('zestaw ma co najmniej 11 przypadków w obsługiwanym formacie', () {
    expect(files.length, greaterThanOrEqualTo(11));
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
        final gapCodes = got.gate.openGaps.map((g) => g.code.name).toSet();
        expect(gapCodes,
            ((expected['gaps'] as List?) ?? const []).cast<String>().toSet(),
            reason: '$where: otwarte blokady\n'
                '${got.gate.openGaps.map((g) => '  ${g.code.name} [${g.segmentId}]: ${g.pl}').join('\n')}');
        for (final w in ((expected['warnings'] as List?) ?? const [])) {
          expect(got.plan.has(ScanIssueCode.values.byName(w as String)), isTrue,
              reason: '$where: brak ostrzeżenia $w');
        }
        expect(got.gate.canSaveProject, expected['canSave'],
            reason: '$where: canSave');

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
          if (e['blocked'] != null) {
            expect(got.gate.blocked.contains(seg), e['blocked'],
                reason: '$where ${e['id']}: cięcie zablokowane?');
          }
          if (e['proposed'] != null) {
            expect(_refCode(seg.proposedStops), e['proposed'],
                reason: '$where ${e['id']}: proponowane odniesienie');
          }
        }
        _checkOutputs(where, got, expected);
      }

      // Zapis jak na ekranie przeglądu i CUT z bazy.
      final finalStep = steps.last;
      final finalExpect = (finalStep['expect'] as Map).cast<String, dynamic>();
      if (finalExpect['canSave'] == true) {
        final rows = await _saveAndReadBack(id, last!, gapMm);
        final expSegs = (finalExpect['segments'] as List)
            .cast<Map>()
            .where((e) => e['cutMm'] != null && e['blocked'] != true)
            .toList();
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

        final journal = (finalExpect['journal'] as Map?)?.cast<String, dynamic>();
        if (journal != null) {
          final welds = buildWeldMap(last.scan, last.segments);
          final dao = WeldJournalDao();
          var n = 0;
          WeldJournalImport run(List<WeldEntry> existing) => weldJournalEntries(
                welds: welds,
                scan: last!.scan,
                projectId: 'golden-$id',
                projectName: 'Złoty zestaw $id',
                savedSegmentIds:
                    last.gate.savable.map((s) => s.sourceId).toSet(),
                existing: existing,
                newId: () => 'golden-$id-w${++n}',
              );
          final first = run(await dao.listAll());
          expect(first.toInsert, hasLength(journal['create']),
              reason: '$id: wpisy dziennika');
          for (final e in first.toInsert) {
            expect(e.status, WeldStatus.pending);
            expect(e.projectId, 'golden-$id');
            await dao.insert(e);
          }
          final again = run(await dao.listAll());
          expect(again.toInsert, isEmpty,
              reason: '$id: ponowny import nie dubluje wpisów');
          expect(again.skipped, hasLength(journal['skippedOnReimport']),
              reason: '$id: pominięte przy ponownym imporcie');
        }
      }
    });
  }
}
