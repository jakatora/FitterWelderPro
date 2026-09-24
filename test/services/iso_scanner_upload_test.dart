// Skaner izometrii: prawdziwy typ obrazu, zmniejszanie przed wysyłką, HEIC,
// nagłówki tożsamości i zrozumiałe komunikaty odmowy serwera.
// Transport to atrapa (http.runWithClient + MockClient) — zero połączeń.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/premium_service.dart';

const _deviceId = '0123456789abcdef0123456789abcdef';
const _secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

img.Image _canvas(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(240, 240, 240));
  img.drawLine(image,
      x1: 0, y1: 0, x2: w - 1, y2: h - 1, color: img.ColorRgb8(0, 0, 0));
  return image;
}

Uint8List _heicHeader() => Uint8List.fromList([
      0, 0, 0, 24, // rozmiar boxa
      ...'ftypheic'.codeUnits,
      0, 0, 0, 0,
      ...'mif1heic'.codeUnits,
      ...List.filled(64, 0),
    ]);

(int, int) _size(Uint8List bytes) {
  final info = img.findDecoderForData(bytes)!.startDecode(bytes)!;
  return (info.width, info.height);
}

void main() {
  group('rozpoznanie formatu po bajtach', () {
    test('JPEG, PNG, GIF, WebP, HEIC, AVIF i śmieci', () {
      final small = _canvas(8, 8);
      expect(sniffScanImageFormat(img.encodeJpg(small)), ScanImageFormat.jpeg);
      expect(sniffScanImageFormat(img.encodePng(small)), ScanImageFormat.png);
      expect(sniffScanImageFormat(img.encodeGif(small)), ScanImageFormat.gif);
      expect(sniffScanImageFormat(img.encodeWebP(small)), ScanImageFormat.webp);
      expect(sniffScanImageFormat(_heicHeader()), ScanImageFormat.heif);
      final avif = _heicHeader()..setRange(8, 12, 'avif'.codeUnits);
      expect(sniffScanImageFormat(avif), ScanImageFormat.heif);
      expect(sniffScanImageFormat(utf8.encode('to nie jest obraz')),
          ScanImageFormat.unknown);
      expect(sniffScanImageFormat(const []), ScanImageFormat.unknown);
    });

    test('media_type tylko dla formatów, które serwer przyjmuje', () {
      expect(scanMediaType(ScanImageFormat.jpeg), 'image/jpeg');
      expect(scanMediaType(ScanImageFormat.png), 'image/png');
      expect(scanMediaType(ScanImageFormat.gif), 'image/gif');
      expect(scanMediaType(ScanImageFormat.webp), 'image/webp');
      expect(scanMediaType(ScanImageFormat.heif), isNull);
    });
  });

  group('przygotowanie zdjęcia', () {
    test('mały PNG idzie bez zmian jako image/png (nie image/jpeg)', () async {
      final png = img.encodePng(_canvas(800, 600));
      final out = await prepareScanImage(png);
      expect(out.mediaType, 'image/png');
      expect(out.bytes, same(png));
      expect(out.resized, isFalse);
    });

    test('WebP idzie jako image/webp', () async {
      final webp = img.encodeWebP(_canvas(640, 480));
      final out = await prepareScanImage(webp);
      expect(out.mediaType, 'image/webp');
      expect(out.bytes, same(webp));
    });

    test('duże zdjęcie JPEG: dłuższy bok zmniejszony do 2576 px', () async {
      final jpeg = img.encodeJpg(_canvas(3000, 2000), quality: 80);
      final out = await prepareScanImage(jpeg);
      expect(out.resized, isTrue);
      expect(out.mediaType, 'image/jpeg');
      expect(sniffScanImageFormat(out.bytes), ScanImageFormat.jpeg);
      final (w, h) = _size(out.bytes);
      expect(w, kScanMaxLongSidePx);
      expect(h, closeTo(2000 * kScanMaxLongSidePx / 3000, 1));
    });

    test('duży rysunek PNG w pionie zostaje PNG, wysokość 2576 px', () async {
      final png = img.encodePng(_canvas(1000, 3000));
      final out = await prepareScanImage(png);
      expect(out.resized, isTrue);
      expect(out.mediaType, 'image/png');
      final (w, h) = _size(out.bytes);
      expect(h, kScanMaxLongSidePx);
      expect(w, closeTo(1000 * kScanMaxLongSidePx / 3000, 1));
    });

    test('HEIC przekodowany dekoderem platformy na JPEG', () async {
      final out = await prepareScanImage(
        _heicHeader(),
        platformDecoder: (bytes, maxLongSide) async {
          expect(maxLongSide, kScanMaxLongSidePx);
          return (
            rgba: Uint8List.fromList(List.filled(12 * 8 * 4, 200)),
            width: 12,
            height: 8,
          );
        },
      );
      expect(out.mediaType, 'image/jpeg');
      expect(out.converted, isTrue);
      expect(sniffScanImageFormat(out.bytes), ScanImageFormat.jpeg);
      expect(_size(out.bytes), (12, 8));
    });

    test('HEIC, którego telefon nie umie zdekodować → prośba o JPEG', () async {
      await expectLater(
        prepareScanImage(
          _heicHeader(),
          platformDecoder: (_, __) async => throw Exception('brak kodeka'),
        ),
        throwsA(isA<IsoScannerAiException>().having(
            (e) => e.message, 'message', contains('JPEG'))),
      );
    });

    test('nieznany format → komunikat zamiast wysyłki', () async {
      await expectLater(
        prepareScanImage(Uint8List.fromList(utf8.encode('x' * 2048))),
        throwsA(isA<IsoScannerAiException>()),
      );
    });
  });

  group('wysyłka do serwera', () {
    late Directory dir;
    final requests = <http.Request>[];

    setUp(() async {
      requests.clear();
      dir = await Directory.systemTemp.createTemp('fwp-scan-');
      SharedPreferences.setMockInitialValues({
        'fitter_device_id': _deviceId,
        'fitter_install_secret': _secret,
      });
      PremiumService.instance.resetForTest();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<AiScanResult> scan(String path, http.Response response) =>
        http.runWithClient(
          () => scanIsoImage(path),
          () => MockClient((r) async {
            requests.add(r);
            return response;
          }),
        );

    Future<String> writePng(String name) async {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(img.encodePng(_canvas(400, 300)));
      return file.path;
    }

    test('PNG zapisany jako *.jpg idzie jako image/png, z nagłówkami', () async {
      final path = await writePng('rysunek.jpg');
      await scan(
        path,
        http.Response(jsonEncode({'result': {}, 'tookMs': 1}), 200),
      );
      final req = requests.single;
      expect(req.url.path, '/api/fitter/scan-iso');
      expect(req.headers[kDeviceIdHeader], _deviceId);
      expect(req.headers[kInstallSecretHeader], _secret);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['media_type'], 'image/png');
      expect(body['device_id'], _deviceId);
      expect(sniffScanImageFormat(base64Decode(body['image_base64'] as String)),
          ScanImageFormat.png);
    });

    test('401 INSTALL_SECRET_INVALID → zrozumiały komunikat, nie surowy kod',
        () async {
      final path = await writePng('a.png');
      await expectLater(
        scan(
          path,
          http.Response(
              jsonEncode({
                'error': {
                  'code': 'INSTALL_SECRET_INVALID',
                  'message': 'Nieprawidłowy sekret instalacji dla tego urządzenia.'
                }
              }),
              401,
              headers: {'content-type': 'application/json; charset=utf-8'}),
        ),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message',
                contains('nie rozpoznał tej instalacji'))
            .having((e) => e.message, 'message',
                isNot(contains('INSTALL_SECRET')))),
      );
    });

    test('415 UNSUPPORTED_IMAGE_TYPE → prośba o JPEG', () async {
      final path = await writePng('b.png');
      await expectLater(
        scan(
          path,
          http.Response(
              jsonEncode({
                'error': {'code': 'UNSUPPORTED_IMAGE_TYPE', 'message': 'x'}
              }),
              415),
        ),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.message, 'message', contains('JPEG'))),
      );
    });
  });
}
