import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';

WpsRecord _wps() => const WpsRecord(
      id: 'local-id',
      wpsNo: 'WPS-141-01',
      revision: 'B',
      standard: WpsStandard.iso15614_1,
      pqrRef: 'WPQR-2025/17',
      processes: '141',
      materialGroup: '8.1',
      thicknessMinMm: 1.5,
      thicknessMaxMm: 6,
      diameterMinMm: 25,
      positions: 'PA, PC, PF',
      jointKinds: {WeldJointKind.bw},
      filler: 'ER316LSi Ø2,4',
      shieldingGas: 'I1 (Ar 99,996 %)',
      backingGas: 'N2 + 10 % H2',
      interpassMaxC: 150,
      heatInputMinKjMm: 0.3,
      heatInputMaxKjMm: 1.2,
      heatInputMethod: HeatInputStandard.en1011,
      pwht: 'brak',
      notes: 'Formowanie do < 50 ppm O2',
      attachmentPath: '/data/user/0/app/heat_photos/wps.pdf',
      createdAt: 1000,
      updatedAt: 2000,
    );

void main() {
  group('wiersz bazy', () {
    test('toRow / fromRow — nic nie ginie', () {
      final back = WpsRecord.fromRow(_wps().toRow());
      expect(back.toRow(), _wps().toRow());
    });
  });

  group('JSON — wymiana w brygadzie', () {
    test('eksport → import zachowuje technologię, bez id i ścieżki pliku', () {
      final json = encodeWpsJson(_wps(), exportedAt: DateTime.utc(2026, 9, 24));
      expect(json, isNot(contains('local-id')));
      expect(json, isNot(contains('heat_photos')));
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['format'], kWpsJsonFormat);
      expect(decoded['version'], kWpsJsonVersion);

      final imported = decodeWpsJson(json);
      expect(imported.id, '');
      expect(imported.attachmentPath, isNull);
      final expected = _wps().toRow()
        ..remove('id')
        ..remove('attachment_path')
        ..remove('created_at')
        ..remove('updated_at');
      final actual = imported.toRow()
        ..remove('id')
        ..remove('attachment_path')
        ..remove('created_at')
        ..remove('updated_at');
      expect(actual, expected);
    });

    test('liczba zapisana jako tekst z przecinkiem jest przyjmowana', () {
      final json = jsonEncode({
        'format': kWpsJsonFormat,
        'version': 1,
        'wps': {'wps_no': 'W-1', 'heat_input_max_kj_mm': '1,5'},
      });
      expect(decodeWpsJson(json).heatInputMaxKjMm, 1.5);
    });

    for (final (name, text) in <(String, String)>[
      ('nie-JSON', 'to nie json'),
      ('cudzy format', jsonEncode({'format': 'x', 'version': 1, 'wps': {}})),
      (
        'nowsza wersja',
        jsonEncode({
          'format': kWpsJsonFormat,
          'version': kWpsJsonVersion + 1,
          'wps': {'wps_no': 'W-1'},
        })
      ),
      (
        'brak numeru WPS',
        jsonEncode({'format': kWpsJsonFormat, 'version': 1, 'wps': {}})
      ),
      (
        'min > max',
        jsonEncode({
          'format': kWpsJsonFormat,
          'version': 1,
          'wps': {'wps_no': 'W-1', 'thickness_min_mm': 8, 'thickness_max_mm': 2},
        })
      ),
      (
        'liczba ujemna',
        jsonEncode({
          'format': kWpsJsonFormat,
          'version': 1,
          'wps': {'wps_no': 'W-1', 'preheat_min_c': -20},
        })
      ),
      (
        'tekst zamiast liczby',
        jsonEncode({
          'format': kWpsJsonFormat,
          'version': 1,
          'wps': {'wps_no': 'W-1', 'interpass_max_c': 'dużo'},
        })
      ),
    ]) {
      test('odrzuca: $name', () {
        expect(() => decodeWpsJson(text), throwsA(isA<WpsFormatException>()));
      });
    }

    test('komunikat błędu jest w obu językach', () {
      try {
        decodeWpsJson('{');
        fail('powinien rzucić');
      } on WpsFormatException catch (e) {
        expect(e.messagePl, contains('JSON'));
        expect(e.messageEn, contains('JSON'));
      }
    });
  });

  test('nazwa pliku eksportu bez znaków kłopotliwych', () {
    expect(wpsExportFileName(_wps()), 'WPS-141-01_rev-B.json');
    expect(
      wpsExportFileName(const WpsRecord(
          id: '', wpsNo: 'WPS 12/2026', createdAt: 0, updatedAt: 0)),
      'WPS-12-2026.json',
    );
  });

  test('displayName z rewizją', () {
    expect(_wps().displayName, 'WPS-141-01 rev. B');
  });
}
