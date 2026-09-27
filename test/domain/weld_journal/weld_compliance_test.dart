// Dziennik spoin ↔ WPS i uprawnienia: przekład pól spoiny v20 na parametry
// kontroli zakresu, dopasowanie wpisu WPS do biblioteki, znaczki i teksty
// ostrzeżenia (bez bazy).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/weld_journal/weld_compliance.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';

const WpsRecord _wps = WpsRecord(
  id: 'wps-1',
  wpsNo: 'WPS-141-01',
  revision: 'B',
  processes: '141',
  materialGroup: '8.1',
  thicknessMinMm: 1.5,
  thicknessMaxMm: 6,
  diameterMinMm: 25,
  diameterMaxMm: 168.3,
  positions: 'PA, PC, PF',
  jointKinds: {WeldJointKind.bw},
  preheatMinC: 10,
  interpassMaxC: 150,
  heatInputMinKjMm: 0.3,
  heatInputMaxKjMm: 1.2,
  heatInputMethod: HeatInputStandard.en1011,
  createdAt: 0,
  updatedAt: 10,
);

WelderCertificate _cert({
  String id = 'c1',
  String? stamp = 'JK-12',
  DateTime? expiry,
  String positions = 'PA, PC, PF',
}) =>
    WelderCertificate(
      id: id,
      standard: QualificationStandard.iso9606_1,
      welderStamp: stamp,
      certNo: 'UDT/123/2026',
      testDate: DateTime(2026, 1, 10),
      expiryDate: expiry ?? DateTime(2028, 1, 10),
      // Potwierdzenie w terminie (egzamin 2026-01-10 + 6 mies. = 2026-07-10).
      lastConfirmedDate: DateTime(2026, 7, 1),
      processes: '141',
      materialGroup: '8.1',
      thicknessMinMm: 1,
      thicknessMaxMm: 8,
      diameterMinMm: 25,
      positions: positions,
      jointKinds: const {WeldJointKind.bw},
      createdAt: 0,
      updatedAt: 0,
    );

WeldEntry _weld({
  String wpsRef = 'WPS-141-01 rev. B',
  String t = '2.77',
  String od = '60.3',
  String material = '8.1',
  String position = 'PF',
  String jointType = WeldJointType.butt,
  String heatInput = '0,6 EN',
  String preheat = '20',
  String interpass = '120',
  String welder = 'JK-12',
  String rootWelder = '',
  String date = '2026-09-20',
}) =>
    WeldEntry(
      id: 'w1',
      weldNo: 'W-001',
      projectName: 'Blok 4',
      pipeName: 'L-12',
      material: material,
      od: od,
      t: t,
      method: 'TIG',
      welder: welder,
      rootWelder: rootWelder,
      date: date,
      notes: '',
      status: WeldStatus.pending,
      wpsRef: wpsRef,
      position: position,
      jointType: jointType,
      heatInput: heatInput,
      preheatC: preheat,
      interpassC: interpass,
    );

WeldCompliance _assess(
  WeldEntry e, {
  List<WpsRecord> library = const [_wps],
  List<WelderCertificate>? certificates,
}) =>
    assessWeldCompliance(
      entry: e,
      wpsLibrary: library,
      certificates: certificates ?? [_cert()],
      today: DateTime(2026, 9, 25),
    );

void main() {
  group('energia liniowa z konwencją w tekście', () {
    test('rozbicie i złożenie — w obie strony', () {
      final en = splitHeatInput('1,25 EN');
      expect(en.number, '1,25');
      expect(en.method, HeatInputStandard.en1011);
      final asme = splitHeatInput('0.8 ASME');
      expect(asme.number, '0.8');
      expect(asme.method, HeatInputStandard.asmeIx);
      expect(joinHeatInput('1,25', HeatInputStandard.en1011), '1,25 EN');
      expect(joinHeatInput('0.8', HeatInputStandard.asmeIx), '0.8 ASME');
    });

    test('stary wpis bez dopisku = konwencja nieznana, tekst bez zmian', () {
      final old = splitHeatInput('1.2');
      expect(old.number, '1.2');
      expect(old.method, isNull);
      expect(joinHeatInput(old.number, old.method), '1.2');
    });

    test('sama konwencja bez liczby nie jest zapisywana', () {
      expect(joinHeatInput('  ', HeatInputStandard.en1011), '');
    });
  });

  group('przekład pól spoiny v20 na WeldParameters', () {
    test('liczby z przecinkiem, pozycja, BW, temperatury, energia z konwencją',
        () {
      final p = weldParametersOf(_weld(t: '2,77', od: '60,3 mm'));
      expect(p.thicknessMm, 2.77);
      expect(p.outsideDiameterMm, 60.3);
      expect(p.materialGroup, '8.1');
      expect(p.process, 'TIG');
      expect(p.position, 'PF');
      expect(p.jointKind, WeldJointKind.bw);
      expect(p.heatInputKjMm, 0.6);
      expect(p.heatInputMethod, HeatInputStandard.en1011);
      expect(p.preheatC, 20);
      expect(p.interpassC, 120);
    });

    test('typ złącza: SW i FW → FW, odgałęzienie → nie zgadujemy', () {
      expect(jointKindOfWeld('FW'), WeldJointKind.fw);
      expect(jointKindOfWeld('SW'), WeldJointKind.fw);
      expect(jointKindOfWeld('BR'), isNull);
      expect(jointKindOfWeld(''), isNull);
    });

    test('materiał: grupa jest porównywana, gatunek nie', () {
      expect(materialGroupOfWeld('8.1'), '8.1');
      expect(materialGroupOfWeld('P8'), 'P8');
      expect(materialGroupOfWeld('1 + 8.1'), '1 + 8.1');
      expect(materialGroupOfWeld('316L'), isNull);
      expect(materialGroupOfWeld('P265GH'), isNull);
      expect(materialGroupOfWeld('1.4404'), isNull);
      expect(materialGroupOfWeld(''), isNull);
    });

    test('puste pola = brak danych, nie zero', () {
      final p = weldParametersOf(_weld(
          t: '', od: '', position: '', jointType: '', heatInput: '',
          preheat: '', interpass: ''));
      expect(p.thicknessMm, isNull);
      expect(p.outsideDiameterMm, isNull);
      expect(p.position, isNull);
      expect(p.jointKind, isNull);
      expect(p.heatInputKjMm, isNull);
      expect(p.preheatC, isNull);
      expect(p.interpassC, isNull);
    });
  });

  group('dopasowanie wpisu WPS do biblioteki', () {
    final older = WpsRecord(
        id: 'old', wpsNo: 'WPS-141-01', revision: 'A', createdAt: 0,
        updatedAt: 1);
    test('pełna nazwa z rewizją, sam numer (stary tekst), identyfikator', () {
      expect(resolveWpsRef('WPS-141-01 rev. B', [older, _wps])?.id, 'wps-1');
      expect(resolveWpsRef('wps-141-01 REV. a', [older, _wps])?.id, 'old');
      // Sam numer przy kilku rewizjach → niejednoznaczne (nie najnowsza —
      // rev. B mogła powstać po dacie spoiny).
      expect(resolveWpsRef(' WPS-141-01 ', [older, _wps]), isNull);
      expect(
          resolveWpsRefDetailed(' WPS-141-01 ', [older, _wps])
              .ambiguous
              .map((w) => w.revision),
          ['A', 'B']);
      // Jedna rewizja w bibliotece → sam numer wystarcza.
      expect(resolveWpsRef('WPS-141-01', [_wps])?.id, 'wps-1');
      expect(resolveWpsRef('cokolwiek', [older, _wps], wpsId: 'old')?.id,
          'old');
      expect(resolveWpsRef('WPS-999', [older, _wps]), isNull);
      expect(resolveWpsRef('', [older, _wps]), isNull);
    });

    test('po wyborze z listy dziennik zapisuje nazwę z rewizją', () {
      expect(wpsRefOf(_wps), 'WPS-141-01 rev. B');
    });
  });

  group('wynik kontroli spoiny', () {
    test('spoina zgodna z WPS i uprawnieniem — bez ostrzeżeń', () {
      final c = _assess(_weld());
      expect(c.wps?.id, 'wps-1');
      expect(c.hasWarnings, isFalse);
      expect(c.outsideWps, isFalse);
      expect(c.welderNotQualified, isFalse);
      expect(c.warningLines(en: false), isEmpty);
    });

    test('pozycja i energia poza WPS → znaczek „poza WPS" i punkty listy', () {
      final c = _assess(_weld(position: 'PE', heatInput: '1,5 EN'),
          certificates: [_cert(positions: 'wszystkie')]);
      expect(c.outsideWps, isTrue);
      expect(c.welderNotQualified, isFalse);
      expect(c.hasWarnings, isTrue);
      final lines = c.warningLines(en: false);
      expect(lines.where((l) => l.contains('Pozycja')), hasLength(1));
      expect(lines.where((l) => l.contains('Energia liniowa')), hasLength(1));
      expect(lines.first, startsWith('WPS WPS-141-01 rev. B — '));
    });

    test('energia w innej konwencji → „do wyjaśnienia", nie „poza WPS"', () {
      final c = _assess(_weld(heatInput: '0,6 ASME'));
      expect(c.outsideWps, isFalse);
      expect(c.wpsNeedsReview, isTrue);
      expect(c.hasWarnings, isTrue);
    });

    test('stara energia bez konwencji też jest do wyjaśnienia', () {
      final c = _assess(_weld(heatInput: '0.6'));
      expect(c.wpsNeedsReview, isTrue);
    });

    test('spawacz bez ważnego uprawnienia w dniu spawania', () {
      final c = _assess(_weld(date: '2028-03-01'));
      expect(c.welderNotQualified, isTrue);
      expect(c.hasWarnings, isTrue);
      final lines = c.warningLines(en: false);
      expect(lines.first, contains('Spawacz JK-12'));
      expect(lines.first, contains('2028-03-01'));
      expect(lines.any((l) => l.contains('certyfikat UDT/123/2026')), isTrue);
      expect(lines.any((l) => l.contains('Ważność uprawnienia')), isTrue);
    });

    test('pozycja spoza uprawnienia spawacza grani — każdy stempel osobno',
        () {
      final c = _assess(
        _weld(rootWelder: 'AB-7', position: 'PC'),
        library: const [],
        certificates: [
          _cert(),
          _cert(id: 'c2', stamp: 'AB-7', positions: 'PA'),
        ],
      );
      expect(c.welders.map((w) => w.stamp), ['JK-12', 'AB-7']);
      expect(c.welders[0].notQualified, isFalse);
      expect(c.welders[1].notQualified, isTrue);
      expect(c.welderNotQualified, isTrue);
    });

    test('brak WPS w bibliotece i brak certyfikatów → informacja, nie '
        'ostrzeżenie', () {
      final c = _assess(_weld(wpsRef: 'WPS-999'),
          library: const [], certificates: const []);
      expect(c.hasWarnings, isFalse);
      expect(c.wpsNotInLibrary, isTrue);
      final info = c.infoLines(en: false);
      expect(info.any((l) => l.contains('WPS-999') && l.contains('Bibliotece')),
          isTrue);
      expect(info.any((l) => l.contains('Brak certyfikatów spawacza JK-12')),
          isTrue);
      expect(c.cardInfoLines(en: false), info);
    });

    test('spoina bez WPS: na karcie nic nie krzyczy', () {
      final c = _assess(_weld(wpsRef: ''),
          library: const [], certificates: const []);
      expect(c.hasWarnings, isFalse);
      expect(c.infoLines(en: false).first, contains('Nie wybrano WPS'));
      expect(c.cardInfoLines(en: false), isEmpty);
    });

    test('tekst do historii wymienia każdą niezgodność', () {
      final c = _assess(_weld(position: 'PE', date: '2028-03-01'));
      final text = c.historyText(en: false);
      expect(text, startsWith('Zapisano mimo ostrzeżeń:'));
      expect(text, contains('• WPS WPS-141-01 rev. B — Pozycja'));
      expect(text, contains('• Spawacz JK-12'));
      final en = c.historyText(en: true);
      expect(en, startsWith('Saved despite warnings:'));
      expect(en, contains('Position'));
    });

    test('RangeIssue z listy WPS jest tą samą oceną co checkWeldAgainstWps',
        () {
      final e = _weld(t: '7');
      final direct = checkWeldAgainstWps(weldParametersOf(e), _wps);
      final c = _assess(e);
      expect(c.wpsIssues.map((i) => i.field), direct.map((i) => i.field));
      expect(c.wpsIssues.single.field, WeldCheckField.thickness);
    });
  });

  group('certyfikat bez stempla i historia potwierdzeń', () {
    test('certyfikat bez stempla NIE obejmuje spoiny kolegi z brygady', () {
      final c = assessWeldCompliance(
        entry: _weld(welder: 'XY-1'),
        wpsLibrary: const [],
        certificates: [_cert(stamp: null)],
        defaultStamp: 'JK-12',
        today: DateTime(2026, 9, 25),
      );
      expect(c.welderNotQualified, isFalse);
      expect(c.welders.single.coverage.noCertificates, isTrue);
      expect(c.infoLines(en: false).join(),
          contains('Brak certyfikatów spawacza XY-1'));
    });

    test('certyfikat bez stempla liczy się dla właściciela telefonu', () {
      for (final welder in ['JK-12', '']) {
        final c = assessWeldCompliance(
          entry: _weld(welder: welder),
          wpsLibrary: const [],
          certificates: [_cert(stamp: null)],
          defaultStamp: 'JK-12',
          today: DateTime(2026, 9, 25),
        );
        expect(c.welders.single.coverage.noCertificates, isFalse,
            reason: 'spawacz "$welder"');
        expect(c.welderNotQualified, isFalse);
      }
    });

    test('certificatesForStamp: stempel obcy, właściciel, bez stempla', () {
      final mine = _cert(id: 'a', stamp: null);
      final his = _cert(id: 'b', stamp: 'xy-1');
      expect(
          certificatesForStamp([mine, his], 'XY-1', ownerStamp: 'JK-12')
              .map((c) => c.id),
          ['b']);
      expect(
          certificatesForStamp([mine, his], 'jk-12', ownerStamp: 'JK-12')
              .map((c) => c.id),
          ['a']);
      expect(certificatesForStamp([mine, his], '', ownerStamp: null)
          .map((c) => c.id), ['a']);
    });

    test(
        'nowe potwierdzenie nie robi z dawnej spoiny „spawacza bez '
        'uprawnień"', () {
      // Egzamin 2025-01-10, potwierdzenia 2025-07-05 i 2026-01-05 w
      // historii; spoina 2025-10-01 z okresu pierwszego potwierdzenia.
      final cert = WelderCertificate(
        id: 'c1',
        standard: QualificationStandard.iso9606_1,
        welderStamp: 'JK-12',
        testDate: DateTime(2025, 1, 10),
        lastConfirmedDate: DateTime(2026, 1, 5),
        confirmations: [
          CertificateConfirmation(
              id: 'k1',
              certificateId: 'c1',
              date: DateTime(2025, 7, 5),
              createdAt: 0),
          CertificateConfirmation(
              id: 'k2',
              certificateId: 'c1',
              date: DateTime(2026, 1, 5),
              createdAt: 0),
        ],
        processes: '141',
        createdAt: 0,
        updatedAt: 0,
      );
      final c = assessWeldCompliance(
        entry: _weld(date: '2025-10-01'),
        wpsLibrary: const [],
        certificates: [cert],
        defaultStamp: 'JK-12',
        today: DateTime(2026, 3, 1),
      );
      expect(c.welderNotQualified, isFalse);
    });
  });

  group('WPS: rewizje, wersje treści i status dokumentu (v25)', () {
    final older = WpsRecord(
        id: 'old', wpsNo: 'WPS-141-01', revision: 'A', createdAt: 0,
        updatedAt: 1);

    test('sam numer przy dwóch rewizjach → „nie da się porównać”, nie alarm',
        () {
      final c = _assess(_weld(wpsRef: 'WPS-141-01', position: 'PE'),
          library: [older, _wps], certificates: const []);
      expect(c.wps, isNull);
      expect(c.ambiguousWps, hasLength(2));
      expect(c.outsideWps, isFalse);
      expect(c.wpsNeedsReview, isTrue);
      expect(c.wpsNotInLibrary, isFalse);
      expect(c.hasWarnings, isFalse);
      expect(c.infoLines(en: false).join(), contains('kilka rewizji (A, B)'));
    });

    test('spoina zapamiętała wps_id — rozstrzyga bez tekstu', () {
      final c = _assess(
          _weld(wpsRef: 'WPS-141-01').copyWith(wpsId: 'old'),
          library: [older, _wps],
          certificates: const []);
      expect(c.wps?.id, 'old');
    });

    test('edycja WPS po dniu spawania nie zmienia oceny dawnej spoiny', () {
      // Wersja 1 (od zawsze): pozycje PA, PC, PF, PE. Wersja 2 od
      // 2026-10-01: PA, PC, PF.
      final v1 = WpsVersion(
          id: 'v1',
          wpsId: 'wps-1',
          versionNo: 1,
          validFrom: 0,
          snapshot: WpsRecord.fromRow(
              {..._wps.toRow(), 'positions': 'PA, PC, PF, PE'}),
          createdAt: 0);
      final v2 = WpsVersion(
          id: 'v2',
          wpsId: 'wps-1',
          versionNo: 2,
          validFrom: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          snapshot: _wps,
          createdAt: 0);
      WeldCompliance run(String date) => assessWeldCompliance(
            entry: _weld(position: 'PE', date: date),
            wpsLibrary: const [_wps],
            certificates: [_cert(positions: 'wszystkie')],
            today: DateTime(2026, 10, 5),
            wpsVersions: {
              'wps-1': [v1, v2]
            },
          );
      final old = run('2026-09-20');
      expect(old.outsideWps, isFalse);
      expect(old.wpsOlderVersion, isTrue);
      final fresh = run('2026-10-02');
      expect(fresh.outsideWps, isTrue);
      expect(fresh.wpsOlderVersion, isFalse);
    });

    test('bieżąca treść różna od ostatniej wersji → najnowsza od updated_at',
        () {
      final v1 = WpsVersion(
          id: 'v1',
          wpsId: 'wps-1',
          versionNo: 1,
          validFrom: 0,
          snapshot:
              WpsRecord.fromRow({..._wps.toRow(), 'positions': 'wszystkie'}),
          createdAt: 0);
      final current = WpsRecord.fromRow({
        ..._wps.toRow(),
        'updated_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
      });
      expect(wpsAsOf(current, [v1], DateTime(2026, 8, 31)).positions,
          'wszystkie');
      expect(wpsAsOf(current, [v1], DateTime(2026, 9, 1)).positions,
          'PA, PC, PF');
      // Bez wersji — bieżąca treść.
      expect(wpsAsOf(current, const [], DateTime(2020)).positions,
          'PA, PC, PF');
    });

    test('WPS wycofana → poza WPS; pWPS → do wyjaśnienia z ostrzeżeniem', () {
      final withdrawn = WpsRecord.fromRow(
          {..._wps.toRow(), 'doc_status': WpsDocStatus.withdrawn.code});
      final c = _assess(_weld(), library: [withdrawn]);
      expect(c.outsideWps, isTrue);
      expect(c.warningLines(en: false).first, contains('wycofana'));
      final pwps = WpsRecord.fromRow(
          {..._wps.toRow(), 'doc_status': WpsDocStatus.preliminary.code});
      final p = _assess(_weld(), library: [pwps]);
      expect(p.outsideWps, isFalse);
      expect(p.wpsNeedsReview, isTrue);
      expect(p.hasWarnings, isTrue);
    });
  });
}
