// Kontrola zakresu spoiny: WPS i uprawnienia spawacza — testy tabelaryczne.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';

const WpsRecord _wps = WpsRecord(
  id: 'w1',
  wpsNo: 'WPS-141-01',
  processes: '141',
  materialGroup: '8.1, 1 + 8.1',
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
  updatedAt: 0,
);

/// Spoina w pełni zgodna z [_wps].
const WeldParameters _ok = WeldParameters(
  thicknessMm: 2.77,
  outsideDiameterMm: 60.3,
  materialGroup: '8.1',
  process: '141',
  position: 'PF',
  jointKind: WeldJointKind.bw,
  heatInputKjMm: 0.6,
  heatInputMethod: HeatInputStandard.en1011,
  preheatC: 20,
  interpassC: 120,
);

WeldParameters _with({
  double? t,
  double? d,
  String? group,
  String? process,
  String? position,
  WeldJointKind? kind,
  double? hi,
  HeatInputStandard? hiMethod,
  bool clearHi = false,
  double? volts,
  double? amps,
  double? travel,
  double? preheat,
  double? interpass,
}) =>
    WeldParameters(
      thicknessMm: t ?? _ok.thicknessMm,
      outsideDiameterMm: d ?? _ok.outsideDiameterMm,
      materialGroup: group ?? _ok.materialGroup,
      process: process ?? _ok.process,
      position: position ?? _ok.position,
      jointKind: kind ?? _ok.jointKind,
      heatInputKjMm: clearHi ? null : (hi ?? _ok.heatInputKjMm),
      heatInputMethod: clearHi ? null : (hiMethod ?? _ok.heatInputMethod),
      volts: volts,
      amps: amps,
      travelMmPerMin: travel,
      preheatC: preheat ?? _ok.preheatC,
      interpassC: interpass ?? _ok.interpassC,
    );

void main() {
  group('checkWeldAgainstWps', () {
    test('spoina zgodna — brak niezgodności', () {
      expect(checkWeldAgainstWps(_ok, _wps), isEmpty);
    });

    test('pusta spoina — nic do sprawdzenia, nic nie zgłaszamy', () {
      expect(checkWeldAgainstWps(const WeldParameters(), _wps), isEmpty);
    });

    for (final (name, weld, field, severity) in <(
      String,
      WeldParameters,
      WeldCheckField,
      RangeIssueSeverity
    )>[
      ('proces 142 zamiast 141', _with(process: '142'), WeldCheckField.process,
          RangeIssueSeverity.outOfRange),
      ('MMA zamiast TIG', _with(process: 'MMA'), WeldCheckField.process,
          RangeIssueSeverity.outOfRange),
      ('grupa 1 (stal C)', _with(group: '1'), WeldCheckField.materialGroup,
          RangeIssueSeverity.outOfRange),
      ('za cienka', _with(t: 1.2), WeldCheckField.thickness,
          RangeIssueSeverity.outOfRange),
      ('za gruba', _with(t: 7.11), WeldCheckField.thickness,
          RangeIssueSeverity.outOfRange),
      ('za mała średnica', _with(d: 21.3), WeldCheckField.diameter,
          RangeIssueSeverity.outOfRange),
      ('za duża średnica', _with(d: 219.1), WeldCheckField.diameter,
          RangeIssueSeverity.outOfRange),
      ('pozycja PE', _with(position: 'PE'), WeldCheckField.position,
          RangeIssueSeverity.outOfRange),
      ('spoina pachwinowa', _with(kind: WeldJointKind.fw),
          WeldCheckField.jointKind, RangeIssueSeverity.outOfRange),
      ('energia za wysoka', _with(hi: 1.5), WeldCheckField.heatInput,
          RangeIssueSeverity.outOfRange),
      ('energia za niska', _with(hi: 0.2), WeldCheckField.heatInput,
          RangeIssueSeverity.outOfRange),
      (
        'energia w innej konwencji — nie da się porównać',
        _with(hi: 0.8, hiMethod: HeatInputStandard.asmeIx),
        WeldCheckField.heatInput,
        RangeIssueSeverity.cannotCompare
      ),
      ('podgrzewanie za niskie', _with(preheat: 5), WeldCheckField.preheat,
          RangeIssueSeverity.outOfRange),
      ('międzyściegowa za wysoka', _with(interpass: 175),
          WeldCheckField.interpass, RangeIssueSeverity.outOfRange),
    ]) {
      test('niezgodność: $name', () {
        final issues = checkWeldAgainstWps(weld, _wps);
        expect(issues, hasLength(1), reason: issues.toString());
        expect(issues.single.field, field);
        expect(issues.single.severity, severity);
        expect(issues.single.messagePl, isNotEmpty);
        expect(issues.single.messageEn, isNotEmpty);
      });
    }

    for (final (name, weld) in <(String, WeldParameters)>[
      ('granice zakresu grubości włącznie', _with(t: 1.5)),
      ('górna granica grubości włącznie', _with(t: 6)),
      ('granica średnicy włącznie', _with(d: 168.3)),
      ('TIG z dziennika (bez numeru) pasuje do 141', _with(process: 'TIG')),
      ('grupa zapisana inaczej', _with(group: ' grupa 8.1 ')),
      ('złącze różnoimienne w odwrotnej kolejności', _with(group: '8.1+1')),
      ('pozycja małymi literami', _with(position: 'pf')),
      ('energia na granicy', _with(hi: 1.2)),
      ('podgrzewanie na minimum', _with(preheat: 10)),
      ('międzyściegowa na maksimum', _with(interpass: 150)),
    ]) {
      test('w zakresie: $name', () {
        expect(checkWeldAgainstWps(weld, _wps), isEmpty);
      });
    }

    test('surowe U/I/v liczone w konwencji WPS (EN, k = 0,6 dla TIG)', () {
      // 12 V × 100 A × 60 / 90 mm/min = 0,80 kJ/mm łuku → EN: × 0,6 = 0,48.
      final inRange = _with(clearHi: true, volts: 12, amps: 100, travel: 90);
      expect(checkWeldAgainstWps(inRange, _wps), isEmpty);
      // Ten sam łuk przy WPS w konwencji ASME z maksimum 0,6 → 0,80 za dużo.
      const asmeWps = WpsRecord(
        id: 'a',
        wpsNo: 'A-1',
        processes: '141',
        heatInputMaxKjMm: 0.6,
        heatInputMethod: HeatInputStandard.asmeIx,
        createdAt: 0,
        updatedAt: 0,
      );
      final issues = checkWeldAgainstWps(inRange, asmeWps);
      expect(issues.single.field, WeldCheckField.heatInput);
      expect(issues.single.actual, '0.8 kJ/mm');
    });

    test('WPS bez ograniczeń — nic nie sprawdza', () {
      const open =
          WpsRecord(id: 'o', wpsNo: 'OPEN', createdAt: 0, updatedAt: 0);
      expect(
        checkWeldAgainstWps(_with(t: 99, process: 'MMA', group: '5'), open),
        isEmpty,
      );
    });

    test('P-No zapisane różnie to ta sama grupa', () {
      const asme = WpsRecord(
          id: 'p',
          wpsNo: 'P',
          materialGroup: 'P-No. 8',
          createdAt: 0,
          updatedAt: 0);
      expect(checkWeldAgainstWps(const WeldParameters(materialGroup: 'P8'), asme),
          isEmpty);
      expect(
          checkWeldAgainstWps(const WeldParameters(materialGroup: 'P1'), asme),
          hasLength(1));
    });

    test('pozycje „wszystkie" obejmują każdą', () {
      const all = WpsRecord(
          id: 'x', wpsNo: 'X', positions: 'wszystkie', createdAt: 0, updatedAt: 0);
      expect(checkWeldAgainstWps(const WeldParameters(position: 'PE'), all),
          isEmpty);
    });
  });

  group('checkWelderCoverage — uprawnienie w dniu spawania', () {
    final weldDate = DateTime(2026, 9, 24);

    WelderCertificate cert({
      String id = 'c',
      QualificationStandard standard = QualificationStandard.iso9606_1,
      DateTime? test,
      DateTime? expiry,
      DateTime? confirmed,
      String processes = '141',
      String group = '8.1',
      double? tMin = 1.5,
      double? tMax = 10,
      double? dMin = 25,
      String positions = 'PA, PC, PF',
      Set<WeldJointKind> kinds = const {WeldJointKind.bw},
    }) =>
        WelderCertificate(
          id: id,
          standard: standard,
          testDate: test ?? DateTime(2026, 6, 1),
          expiryDate: expiry,
          lastConfirmedDate: confirmed,
          processes: processes,
          materialGroup: group,
          thicknessMinMm: tMin,
          thicknessMaxMm: tMax,
          diameterMinMm: dMin,
          positions: positions,
          jointKinds: kinds,
          createdAt: 0,
          updatedAt: 0,
        );

    test('brak certyfikatów — nieobjęty', () {
      final r = checkWelderCoverage(
          weld: _ok, weldDate: weldDate, certificates: const []);
      expect(r.noCertificates, isTrue);
      expect(r.covered, isFalse);
    });

    test('ważny certyfikat w zakresie — objęty', () {
      final r = checkWelderCoverage(
          weld: _ok, weldDate: weldDate, certificates: [cert()]);
      expect(r.covered, isTrue);
      expect(r.coveringCertificate!.certificate.id, 'c');
      expect(r.coveringCertificate!.evaluation.state,
          QualificationState.valid);
    });

    for (final (name, c, field) in <(String, WelderCertificate, WeldCheckField)>[
      ('wygasł przed spoiną', cert(expiry: DateTime(2026, 9, 1)),
          WeldCheckField.validity),
      ('brak potwierdzenia 6 mies. (ISO §9.2)',
          cert(test: DateTime(2026, 1, 10)), WeldCheckField.continuity),
      ('egzamin po dacie spoiny', cert(test: DateTime(2026, 10, 1)),
          WeldCheckField.validity),
      ('inny proces', cert(processes: '111'), WeldCheckField.process),
      ('inna grupa materiałowa', cert(group: '1'),
          WeldCheckField.materialGroup),
      ('grubość poza zakresem', cert(tMin: 3), WeldCheckField.thickness),
      ('średnica poza zakresem', cert(dMin: 100), WeldCheckField.diameter),
      ('pozycja poza zakresem', cert(positions: 'PA'),
          WeldCheckField.position),
      ('tylko FW', cert(kinds: const {WeldJointKind.fw}),
          WeldCheckField.jointKind),
    ]) {
      test('nieobjęty: $name', () {
        final r = checkWelderCoverage(
            weld: _ok, weldDate: weldDate, certificates: [c]);
        expect(r.covered, isFalse);
        expect(r.closestCertificate!.issues.map((i) => i.field),
            contains(field));
      });
    }

    test('drugi certyfikat ratuje sytuację', () {
      final r = checkWelderCoverage(
        weld: _ok,
        weldDate: weldDate,
        certificates: [cert(id: 'old', processes: '111'), cert(id: 'tig')],
      );
      expect(r.covered, isTrue);
      expect(r.coveringCertificate!.certificate.id, 'tig');
    });

    test('ISO 9606-1: 135 obejmuje 138 (§5.2), ASME — nie z tej reguły', () {
      const mag = WeldParameters(process: '138');
      expect(
        checkWelderCoverage(
                weld: mag,
                weldDate: weldDate,
                certificates: [cert(processes: '135')])
            .covered,
        isTrue,
      );
      expect(
        checkWelderCoverage(weld: mag, weldDate: weldDate, certificates: [
          cert(standard: QualificationStandard.asmeIx, processes: '135'),
        ]).covered,
        isFalse,
      );
    });

    test('ASME: ciągłość z dziennika do dnia spoiny', () {
      final asme = cert(
          standard: QualificationStandard.asmeIx,
          test: DateTime(2025, 12, 1));
      // Bez spoin: termin 2026-06-01 → w dniu spoiny wygasło.
      expect(
        checkWelderCoverage(
                weld: _ok, weldDate: weldDate, certificates: [asme])
            .covered,
        isFalse,
      );
      // Spoina TIG 2026-05-20 utrzymała WPQ do 2026-11-20.
      expect(
        checkWelderCoverage(
          weld: _ok,
          weldDate: weldDate,
          certificates: [asme],
          journal: [
            JournalWeld(DateTime(2026, 5, 20), {WeldProcessFamily.gtaw}),
          ],
        ).covered,
        isTrue,
      );
      // Spoina MMA niczego nie utrzymuje w WPQ na TIG.
      expect(
        checkWelderCoverage(
          weld: _ok,
          weldDate: weldDate,
          certificates: [asme],
          journal: [
            JournalWeld(DateTime(2026, 5, 20), {WeldProcessFamily.smaw}),
          ],
        ).covered,
        isFalse,
      );
    });

    test('status „wymaga potwierdzenia" nadal pozwala spawać', () {
      final due = cert(test: DateTime(2026, 4, 10)); // termin 2026-10-10
      final r = checkWelderCoverage(
          weld: _ok, weldDate: weldDate, certificates: [due]);
      expect(r.covered, isTrue);
      expect(r.coveringCertificate!.evaluation.state,
          QualificationState.confirmationDue);
    });
  });

  test('parseNumber czyta liczby z tekstu dziennika', () {
    expect(WeldParameters.parseNumber('60,3'), 60.3);
    expect(WeldParameters.parseNumber('2.0 mm'), 2.0);
    expect(WeldParameters.parseNumber('ok. 3'), 3);
    expect(WeldParameters.parseNumber(''), isNull);
    expect(WeldParameters.parseNumber(null), isNull);
    expect(WeldParameters.parseNumber('brak'), isNull);
  });
}
