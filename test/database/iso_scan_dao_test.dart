// iso_scans (v24): płatny odczyt skanera przeżywa zabicie aplikacji, a stare
// odczyty są przycinane razem ze swoimi zdjęciami.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_scan_dao.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

void main() {
  useTestDatabase();

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete(IsoScanDao.table);
  });

  test('zapis → odczyt: ta sama koperta, z niej ten sam skan', () async {
    final envelope = <String, dynamic>{
      'result': {
        'segments': [
          {'id': 's1', 'dimensionMm': 1200, 'rawDimension': '1200'}
        ],
      },
      'tookMs': 1000,
      'model': 'm',
    };
    await IsoScanDao().insert(IsoScanRecord(
      id: 'a',
      name: 'L-1',
      imagePath: '/x/heat_photos/a.jpg',
      envelopeJson: jsonEncode(envelope),
      createdAt: 10,
    ));
    final r = (await IsoScanDao().latest())!;
    expect(r.name, 'L-1');
    expect(r.imagePath, '/x/heat_photos/a.jpg');
    final scan = AiScanResult.fromEnvelope(r.envelope!);
    expect(scan.segments.single.dimensionMm, 1200);
    expect(scan.envelope, envelope, reason: 'koperta idzie dalej przy zapisie');
  });

  test('uszkodzony wiersz nie wywraca ekranu — po prostu nie ma koperty',
      () async {
    await IsoScanDao().insert(const IsoScanRecord(
        id: 'bad', envelopeJson: 'nie-json', createdAt: 1));
    expect((await IsoScanDao().latest())!.envelope, isNull);
  });

  test('najnowsze pierwsze; ponad limit — najstarsze usuwane ze zdjęciem',
      () async {
    final dir = await Directory.systemTemp.createTemp('fwp_iso_scans_');
    addTearDown(() => dir.delete(recursive: true));
    final oldest = File('${dir.path}/oldest.jpg')..writeAsStringSync('x');
    await IsoScanDao().insert(IsoScanRecord(
      id: 'old',
      imagePath: oldest.path,
      envelopeJson: '{}',
      createdAt: 0,
    ));
    for (var i = 1; i <= IsoScanDao.keep; i++) {
      await IsoScanDao().insert(
          IsoScanRecord(id: 's$i', envelopeJson: '{}', createdAt: i));
    }
    final all = await IsoScanDao().listRecent(limit: 100);
    expect(all, hasLength(IsoScanDao.keep));
    expect(all.first.id, 's${IsoScanDao.keep}');
    expect(all.any((r) => r.id == 'old'), isFalse);
    expect(oldest.existsSync(), isFalse);
  });
}
