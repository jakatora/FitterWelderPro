import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/weld_journal/weld_defaults.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../../support/weld_fixtures.dart';

/// Szybkie wpisy w rękawicach: "Następna spoina" kopiuje to, co się nie
/// zmienia między złączami, a nowy wpis bierze ostatnio użyte wartości
/// zamiast "316L / TIG / puste OD i t" wpisanych na sztywno.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final prev = weld(
    'w1',
    weldNo: 'SP-001-W005',
    project: 'Blok 4',
    line: 'L-12',
    iso: 'ISO-0042',
    status: 'OK',
    material: '304L',
    ndt: {NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.ok, 'RT-1')},
  ).copyWith(
    projectId: 'p1',
    isoRev: 'B',
    wpsRef: 'WPS-141-01',
    method: 'MMA',
    od: '88.9',
    t: '3.2',
    fillerClass: 'E316L-17',
    fillerBatch: 'B-778',
    heatNo1: 'H-1',
    heatNo2: 'H-2',
    notes: 'lico do szlifowania',
    inspector: 'QC',
    preheatC: '100',
    couponRef: 'K-7',
  );

  test('następna spoina kopiuje projekt, linię, WPS, materiał, OD/t, proces, '
      'spoiwo i zwiększa numer', () {
    final next = nextWeldFrom(prev,
        id: 'w2', weldNo: 'SP-001-W006', date: '2026-09-24', stamp: 'JK-12');
    expect(next.id, 'w2');
    expect(next.weldNo, 'SP-001-W006');
    expect(next.projectName, 'Blok 4');
    expect(next.projectId, 'p1');
    expect(next.pipeName, 'L-12');
    expect(next.isoDrawing, 'ISO-0042');
    expect(next.isoRev, 'B');
    expect(next.wpsRef, 'WPS-141-01');
    expect(next.material, '304L');
    expect(next.od, '88.9');
    expect(next.t, '3.2');
    expect(next.method, 'MMA');
    expect(next.fillerClass, 'E316L-17');
    expect(next.fillerBatch, 'B-778');
  });

  test('v28: następna spoina i zapamiętane wartości niosą grań, '
      'przenoszenie i wyrób', () async {
    final mag = prev.copyWith(
      method: 'MIG/MAG',
      rootBacking: WeldRootBacking.mb,
      metalTransfer: WeldMetalTransfer.other,
      productForm: WeldProductKind.pipe,
    );
    final next = nextWeldFrom(mag,
        id: 'w2', weldNo: 'SP-001-W006', date: '2026-09-24', stamp: 'JK-12');
    expect(next.rootBacking, 'mb');
    expect(next.metalTransfer, 'other');
    expect(next.productForm, 'T');

    await saveWeldDefaults(WeldEntryDefaults.fromEntry(mag));
    final e = newWeldFromDefaults(await loadWeldDefaults(),
        id: 'n1', weldNo: 'W-001', date: '2026-09-24', stamp: 'JK-12');
    expect(e.rootBacking, 'mb');
    expect(e.metalTransfer, 'other');
    expect(e.productForm, 'T');

    // Zapis sprzed v28 (bez tych kluczy) — puste, nie wyjątek.
    final old = WeldEntryDefaults.fromJson(const {'material': '316L'});
    expect(old.rootBacking, isEmpty);
    expect(old.productForm, isEmpty);
  });

  test('następna spoina NIE kopiuje wyniku, NDT, wytopów ani odbioru', () {
    final next = nextWeldFrom(prev,
        id: 'w2', weldNo: 'SP-001-W006', date: '2026-09-24', stamp: 'JK-12');
    expect(next.status, 'PENDING');
    expect(next.ndt, isEmpty);
    expect(next.heatNo1, isEmpty);
    expect(next.heatNo2, isEmpty);
    expect(next.notes, isEmpty);
    expect(next.inspector, isEmpty);
    expect(next.preheatC, isEmpty);
    expect(next.couponRef, isEmpty);
    expect(next.repairs, isEmpty);
    expect(next.deletedAt, isNull);
    expect(next.date, '2026-09-24');
    expect(next.welder, 'JK-12');
  });

  test('nowy wpis bez zapamiętanych wartości ma pusty materiał (nie 316L)',
      () async {
    final d = await loadWeldDefaults();
    final e = newWeldFromDefaults(d,
        id: 'n1', weldNo: 'W-001', date: '2026-09-24', stamp: '');
    expect(e.material, isEmpty);
    expect(e.method, isEmpty);
    expect(e.od, isEmpty);
    expect(e.t, isEmpty);
  });

  test('zapamiętane wartości wracają w nowym wpisie', () async {
    await saveWeldDefaults(WeldEntryDefaults.fromEntry(prev));
    final d = await loadWeldDefaults();
    final e = newWeldFromDefaults(d,
        id: 'n1', weldNo: 'W-001', date: '2026-09-24', stamp: 'JK-12');
    expect(e.material, '304L');
    expect(e.method, 'MMA');
    expect(e.od, '88.9');
    expect(e.t, '3.2');
    expect(e.wpsRef, 'WPS-141-01');
    expect(e.fillerClass, 'E316L-17');
    expect(e.pipeName, 'L-12');
    expect(d.lastWeldId, 'w1');
    // Projekt ma własny klucz (loadLastWeldProject) — tu go nie dublujemy.
    expect(e.projectName, isEmpty);
  });

  test('uszkodzony zapis w preferencjach daje puste wartości, nie wyjątek',
      () async {
    SharedPreferences.setMockInitialValues({kWeldDefaultsPrefsKey: '{zepsute'});
    final d = await loadWeldDefaults();
    expect(d.material, isEmpty);
  });

  test('WeldEntry bez NDT i napraw ma puste mapy', () {
    final e = WeldEntry.fromRow(const {'id': 'x'});
    expect(e.ndt, isEmpty);
    expect(e.repairs, isEmpty);
    expect(e.pwhtRequired, isNull);
  });
}
