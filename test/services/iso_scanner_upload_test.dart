// Skaner izometrii: prawdziwy typ obrazu, zmniejszanie przed wysyłką, HEIC,
// nagłówki tożsamości i zrozumiałe komunikaty odmowy serwera.
// Transport to atrapa (http.runWithClient + MockClient) — zero połączeń.

import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/scan_consent.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/premium_service.dart';

class _DelayedScanIdentity extends InMemorySharedPreferencesStore {
  _DelayedScanIdentity() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.fitter_device_id' && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

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
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.message, 'message', contains('JPEG'))),
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
      ScanConsent.resetForTest();
      await ScanConsent.accept();
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

    test('brak zgody blokuje upload; ponowna zgoda pozwala wysłać', () async {
      final path = await writePng('drawing.png');
      final response =
          http.Response(jsonEncode({'result': {}, 'tookMs': 1}), 200);
      await ScanConsent.clear();
      await expectLater(
          scan(path, response),
          throwsA(isA<IsoScannerAiException>()
              .having((error) => error.reachedModel, 'reachedModel', isFalse)));
      expect(requests, isEmpty);
      await ScanConsent.accept();
      await scan(path, response);
      expect(requests, hasLength(1));
    });

    test('cofnięcie zgody podczas przygotowania nagłówków blokuje HTTP',
        () async {
      final path = await writePng('drawing.png');
      SharedPreferences.setMockInitialValues({});
      final disk = _DelayedScanIdentity();
      SharedPreferencesStorePlatform.instance = disk;
      PremiumService.instance.resetForTest();
      final scanning = scan(
          path, http.Response(jsonEncode({'result': {}, 'tookMs': 1}), 200));
      final rejected = expectLater(
          scanning,
          throwsA(isA<IsoScannerAiException>()
              .having((error) => error.reachedModel, 'reachedModel', isFalse)));
      await disk.entered.future;
      await ScanConsent.clear();
      disk.release.complete();
      await rejected;
      expect(requests, isEmpty);
    });

    test('wycofanie zgody podczas konwersji blokuje zdjęcie przed HTTP',
        () async {
      final file = File('${dir.path}${Platform.pathSeparator}drawing.heic');
      await file.writeAsBytes(_heicHeader());
      final entered = Completer<void>(), release = Completer<void>();
      final scanning = http.runWithClient(
        () => scanIsoImage(file.path, platformDecoder: (_, __) async {
          entered.complete();
          await release.future;
          return (
            rgba: Uint8List.fromList(List.filled(12 * 8 * 4, 200)),
            width: 12,
            height: 8
          );
        }),
        () => MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'result': {}, 'tookMs': 1}), 200);
        }),
      );
      final rejected = expectLater(
          scanning,
          throwsA(isA<IsoScannerAiException>()
              .having((error) => error.code, 'code', 'SCAN_CONSENT_REQUIRED')
              .having((error) => error.reachedModel, 'reachedModel', isFalse)));
      await entered.future;
      await ScanConsent.clear();
      release.complete();
      await rejected;
      expect(requests, isEmpty);
    });

    test('PNG zapisany jako *.jpg idzie jako image/png, z nagłówkami',
        () async {
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
                  'message':
                      'Nieprawidłowy sekret instalacji dla tego urządzenia.'
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

    test('skaner idzie na dedykowany backend (ten sam co reszta apki)',
        () async {
      final path = await writePng('host.png');
      await scan(
        path,
        http.Response(jsonEncode({'result': {}, 'tookMs': 1}), 200),
      );
      expect(requests.single.url.host, Uri.parse(BackendConfig.baseUrl).host);
      expect(BackendConfig.scannerBaseUrl, BackendConfig.baseUrl);
    });

    http.Response jsonError(int status, String code, String message,
            {Map<String, String> headers = const {}}) =>
        http.Response(
          jsonEncode({
            'error': {'code': code, 'message': message}
          }),
          status,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            ...headers,
          },
        );

    test('429 dzienny limit → komunikat z godziną odnowienia', () async {
      final path = await writePng('limit.png');
      // Serwer liczy dobę UTC; Retry-After to sekundy do jej końca.
      final now = DateTime(2026, 9, 25, 14, 0);
      await expectLater(
        http.runWithClient(
          () => scanIsoImage(path, clock: () => now),
          () => MockClient((_) async => jsonError(
                429,
                'RATE_LIMITED',
                'Dzienny limit skanów na tym urządzeniu został wyczerpany.',
                headers: {'retry-after': '43200'}, // 12 h
              )),
        ),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', 'RATE_LIMITED')
            .having((e) => e.isDailyLimit, 'isDailyLimit', isTrue)
            .having(
                (e) => e.retryAfter, 'retryAfter', const Duration(hours: 12))
            .having((e) => e.message, 'message', contains('Dzienny limit'))
            .having((e) => e.message, 'message', contains('02:00'))),
      );
    });

    test('429 limit na minutę → „spróbuj za minutę", bez godziny', () async {
      final path = await writePng('minute.png');
      await expectLater(
        scan(
          path,
          jsonError(429, 'RATE_LIMITED', 'Za dużo skanów — spróbuj za minutę.',
              headers: {'retry-after': '40'}),
        ),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.isDailyLimit, 'isDailyLimit', isFalse)
            .having((e) => e.message, 'message', contains('minut'))),
      );
    });

    test('429 bez JSON i bez Retry-After (stary limiter) → zrozumiały tekst',
        () async {
      final path = await writePng('bare429.png');
      await expectLater(
        scan(path, http.Response('Too many requests', 429)),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.isDailyLimit, 'isDailyLimit', isFalse)
            .having((e) => e.message, 'message', isNot(contains('429')))),
      );
    });

    test('503 AI_BUDGET_EXCEEDED → wyczerpany budżet miesięczny', () async {
      final path = await writePng('budget.png');
      await expectLater(
        scan(
          path,
          jsonError(503, 'AI_BUDGET_EXCEEDED', 'Funkcje AI są chwilowo…',
              headers: {'retry-after': '86400'}),
        ),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.code, 'code', 'AI_BUDGET_EXCEEDED')
            .having((e) => e.reachedModel, 'reachedModel', isFalse)
            .having((e) => e.message, 'message', contains('budżet'))
            .having((e) => e.message, 'message', contains('ręcznie'))),
      );
    });

    test(
        '402 PREMIUM_REQUIRED → bez odsyłania do zakupu, gdy płatności wyłączone',
        () async {
      final path = await writePng('premium.png');
      await expectLater(
        scan(path, jsonError(402, 'PREMIUM_REQUIRED', 'x')),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.reachedModel, 'reachedModel', isFalse)
            .having((e) => e.message, 'message', contains('Premium'))
            .having((e) => e.message, 'message', contains('ręcznie'))),
      );
    });

    test('404 (stara wersja backendu, brak trasy) → zrozumiały komunikat',
        () async {
      final path = await writePng('old404.png');
      await expectLater(
        scan(path, jsonError(404, 'NOT_FOUND', 'Nie znaleziono zasobu')),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.reachedModel, 'reachedModel', isFalse)
            .having((e) => e.message, 'message', contains('jeszcze'))
            .having((e) => e.message, 'message',
                isNot(contains('Nie znaleziono zasobu')))),
      );
    });

    test('500 (stara wersja backendu) → zrozumiały komunikat, nie „Błąd 500"',
        () async {
      final path = await writePng('old500.png');
      await expectLater(
        scan(path, jsonError(500, 'SERVER_ERROR', 'Wewnętrzny błąd serwera')),
        throwsA(isA<IsoScannerAiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('ręcznie'))
            .having((e) => e.message, 'message', isNot(contains('(500)')))),
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
