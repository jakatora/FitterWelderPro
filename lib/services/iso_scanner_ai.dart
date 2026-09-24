// HTTP client + data models for the fitter-welder-backend AI scanner.
//
// v2 schema mirrors the expanded backend prompt:
//   - drawing standard (ASME / ISO) + size notation (NPS / DN / OD)
//   - hygienic / BPE flag
//   - full title block (line number, class, design P/T, material, etc.)
//   - bill of materials
//   - welds carry NDE, PWHT, position (PA/PB/PC…), throat thickness
//   - pipe supports with type
//   - per-element confidence

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../config/backend_config.dart';
import '../config/feature_flags.dart';
import '../data/elbow_takeouts.dart';
import '../i18n/app_language.dart';
import 'premium_service.dart';

// Skaner celuje w BackendConfig.scannerBaseUrl — od 2026-09-25 ten sam
// dedykowany backend co reszta apki (wymaga wdrożonej wersji z 2026-09-24,
// patrz komentarz w BackendConfig). Stara wersja odpowiada 500, brak trasy
// 404 — oba przypadki dostają zrozumiały komunikat ([friendlyScanError]).
// Nadpisanie przez --dart-define=ISO_AI_BASE=... dziala jak dotad.
const String kIsoAiBase = String.fromEnvironment(
  'ISO_AI_BASE',
  defaultValue: BackendConfig.scannerBaseUrl,
);

// ─────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────

enum AiConfidence { high, medium, low, unknown }

AiConfidence _confFromJson(dynamic v) {
  switch (v) {
    case 'high':
      return AiConfidence.high;
    case 'medium':
      return AiConfidence.medium;
    case 'low':
      return AiConfidence.low;
    default:
      return AiConfidence.unknown;
  }
}

class AiTitleBlock {
  final String? drawingNumber;
  final String? sheet;
  final String? revision;
  final String? lineNumber;
  final String? pipeClass;
  final String? designPressure;
  final String? designTemperature;
  final String? fluidService;
  final String? material;
  final String? schedule;
  final String? insulationType;
  final String? insulationThickness;
  final String? paintCode;
  final String? fromEquipment;
  final String? toEquipment;
  final String? hydrotestPressure;
  final String? pwht;
  final String units;

  AiTitleBlock({
    this.drawingNumber,
    this.sheet,
    this.revision,
    this.lineNumber,
    this.pipeClass,
    this.designPressure,
    this.designTemperature,
    this.fluidService,
    this.material,
    this.schedule,
    this.insulationType,
    this.insulationThickness,
    this.paintCode,
    this.fromEquipment,
    this.toEquipment,
    this.hydrotestPressure,
    this.pwht,
    this.units = 'mm',
  });

  bool get hasAnything =>
      drawingNumber != null ||
      lineNumber != null ||
      pipeClass != null ||
      material != null ||
      designPressure != null;

  factory AiTitleBlock.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AiTitleBlock();
    return AiTitleBlock(
      drawingNumber: j['drawingNumber'] as String?,
      sheet: j['sheet'] as String?,
      revision: j['revision'] as String?,
      lineNumber: j['lineNumber'] as String?,
      pipeClass: j['pipeClass'] as String?,
      designPressure: j['designPressure'] as String?,
      designTemperature: j['designTemperature'] as String?,
      fluidService: j['fluidService'] as String?,
      material: j['material'] as String?,
      schedule: j['schedule'] as String?,
      insulationType: j['insulationType'] as String?,
      insulationThickness: j['insulationThickness'] as String?,
      paintCode: j['paintCode'] as String?,
      fromEquipment: j['fromEquipment'] as String?,
      toEquipment: j['toEquipment'] as String?,
      hydrotestPressure: j['hydrotestPressure'] as String?,
      pwht: j['pwht'] as String?,
      units: (j['units'] as String?) ?? 'mm',
    );
  }
}

class AiSegment {
  final String id;
  final double? dimensionMm;
  final String? rawDimension;
  final String? fromId;
  final String? toId;
  final bool auxiliary;
  final AiConfidence confidence;

  AiSegment({
    required this.id,
    this.dimensionMm,
    this.rawDimension,
    this.fromId,
    this.toId,
    this.auxiliary = false,
    this.confidence = AiConfidence.unknown,
  });

  factory AiSegment.fromJson(Map<String, dynamic> j) => AiSegment(
        id: j['id'] as String? ?? '',
        dimensionMm: (j['dimensionMm'] as num?)?.toDouble(),
        rawDimension: j['rawDimension'] as String?,
        fromId: j['fromId'] as String?,
        toId: j['toId'] as String?,
        auxiliary: j['auxiliary'] as bool? ?? false,
        confidence: _confFromJson(j['confidence']),
      );
}

class AiComponent {
  final String id;
  final String type;
  final String? valveType;
  final String? supportType;
  final String? label;
  final String? weldNo;
  final String? weldType;
  final String? weldNde;
  final bool? weldPwht;
  final String? weldPosition;
  final String? throatA;
  final bool? isField;
  final String? instrumentTag;
  final AiConfidence confidence;

  AiComponent({
    required this.id,
    required this.type,
    this.valveType,
    this.supportType,
    this.label,
    this.weldNo,
    this.weldType,
    this.weldNde,
    this.weldPwht,
    this.weldPosition,
    this.throatA,
    this.isField,
    this.instrumentTag,
    this.confidence = AiConfidence.unknown,
  });

  bool get isWeld => type == 'weld' || type == 'fieldWeld' || isField == true;
  bool get isTakeOutBearing =>
      type == 'elbow90' ||
      type == 'elbow45' ||
      type == 'tee' ||
      type == 'reducer' ||
      type == 'flange' ||
      type == 'blindFlange' ||
      type == 'valve';

  factory AiComponent.fromJson(Map<String, dynamic> j) => AiComponent(
        id: j['id'] as String? ?? '',
        type: j['type'] as String? ?? 'other',
        valveType: j['valveType'] as String?,
        supportType: j['supportType'] as String?,
        label: j['label'] as String?,
        weldNo: j['weldNo']?.toString(),
        weldType: j['weldType'] as String?,
        weldNde: j['weldNde'] as String?,
        weldPwht: j['weldPwht'] as bool?,
        weldPosition: j['weldPosition'] as String?,
        throatA: j['throatA'] as String?,
        isField: j['isField'] as bool?,
        instrumentTag: j['instrumentTag'] as String?,
        confidence: _confFromJson(j['confidence']),
      );
}

class AiBomItem {
  final String item;
  final double? quantity;
  final String description;
  final String? material;
  final String? size;
  final String? schedule;
  final String? standard;

  AiBomItem({
    required this.item,
    required this.description,
    this.quantity,
    this.material,
    this.size,
    this.schedule,
    this.standard,
  });

  factory AiBomItem.fromJson(Map<String, dynamic> j) => AiBomItem(
        item: j['item']?.toString() ?? '',
        description: j['description'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toDouble(),
        material: j['material'] as String?,
        size: j['size'] as String?,
        schedule: j['schedule'] as String?,
        standard: j['standard'] as String?,
      );
}

/// A standalone "45" in a question / hint: not part of a longer number, so
/// `DN450` or a component id like `E-145` never reads as a 45° elbow, while
/// `45°`, `45 deg` and `elbow45` still do.
final RegExp _fortyFiveRe = RegExp(r'(?<!\d)45(?!\d)');

class AiNeedsInput {
  final String ask;
  final String? componentId;
  final String? hint;
  final String type; // takeout | schedule | material | weldPosition | other

  AiNeedsInput({
    required this.ask,
    this.componentId,
    this.hint,
    this.type = 'other',
  });

  factory AiNeedsInput.fromJson(Map<String, dynamic> j) => AiNeedsInput(
        ask: j['ask'] as String? ?? '',
        componentId: j['componentId'] as String?,
        hint: j['hint'] as String?,
        type: j['type'] as String? ?? 'other',
      );

  /// Tries to pull a DN size out of the hint / question — used to look up
  /// a default take-out value from our own ASME B16.9 table.
  /// Returns null if no DN can be inferred.
  int? guessDn() {
    final text = '${hint ?? ''} $ask'.toLowerCase();
    final m = RegExp(r'\bdn\s*(\d{2,4})\b').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    // NPS in inches like 2", 4"
    final inch = RegExp(r'(\d+(?:[./]\d+)?)\s*"').firstMatch(text);
    if (inch != null) {
      final v = double.tryParse(inch.group(1)!.replaceAll('/', '.'));
      if (v != null) {
        // Crude inch→DN map for common sizes (parallel arrays — can't use
        // a const Map<double,…> because double overrides ==).
        const inches = <double>[
          0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 6.0, 8.0, 10.0, 12.0,
        ];
        const dns = <int>[
          15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300,
        ];
        for (var i = 0; i < inches.length; i++) {
          if ((inches[i] - v).abs() < 0.05) return dns[i];
        }
      }
    }
    return null;
  }

  bool get isLongRadius {
    final t = '${hint ?? ''} $ask'.toLowerCase();
    return t.contains(' lr') || t.contains('long radius');
  }

  bool get isShortRadius {
    final t = '${hint ?? ''} $ask'.toLowerCase();
    return t.contains(' sr') || t.contains('short radius');
  }

  /// Whether the question is about a 45° elbow.
  ///
  /// A plain substring check used to fire on `DN450` or `E-145` and suggest
  /// the much smaller 45° take-out for a 90° elbow — the fitter would then
  /// deduct too little and cut the pipe too long.
  bool get is45 {
    final t = '${hint ?? ''} $ask';
    return _fortyFiveRe.hasMatch(t);
  }

  /// Best-effort suggested take-out in millimetres for this missing input,
  /// using our offline ASME B16.9 table. Returns null when we can't infer
  /// either the DN or the elbow style.
  int? suggestedTakeoutMm() {
    final dn = guessDn();
    if (dn == null) return null;
    final t = closestByDn(dn);
    if (is45) return t.lr45;
    if (isShortRadius) return t.sr90;
    // Default to long-radius 90°, the common process-piping choice.
    return t.lr90;
  }
}

class AiScanResult {
  final String drawingStandard; // ASME | ISO | unknown
  final String sizeNotation;    // NPS | DN | OD | unknown
  final bool isHygienic;
  final AiTitleBlock titleBlock;
  final String? northArrow;
  final String? scale;
  final List<AiSegment> segments;
  final List<AiComponent> components;
  final List<Map<String, String>> elevations;
  final List<AiBomItem> billOfMaterials;
  final List<AiNeedsInput> needsUserInput;
  final List<String> uncertainty;
  final List<String> warnings;
  final String? error;
  final int? tookMs;
  final String? model;

  AiScanResult({
    this.drawingStandard = 'unknown',
    this.sizeNotation = 'unknown',
    this.isHygienic = false,
    AiTitleBlock? titleBlock,
    this.northArrow,
    this.scale,
    this.segments = const [],
    this.components = const [],
    this.elevations = const [],
    this.billOfMaterials = const [],
    this.needsUserInput = const [],
    this.uncertainty = const [],
    this.warnings = const [],
    this.error,
    this.tookMs,
    this.model,
  }) : titleBlock = titleBlock ?? AiTitleBlock();

  bool get isError =>
      error != null ||
      warnings.any((w) => w.toLowerCase().contains('not_an_isometric'));

  List<AiComponent> get welds =>
      components.where((c) => c.isWeld).toList(growable: false);

  factory AiScanResult.fromEnvelope(Map<String, dynamic> envelope) {
    final result = (envelope['result'] as Map?)?.cast<String, dynamic>() ?? {};
    return AiScanResult(
      drawingStandard: result['drawingStandard'] as String? ?? 'unknown',
      sizeNotation: result['sizeNotation'] as String? ?? 'unknown',
      isHygienic: result['isHygienic'] as bool? ?? false,
      titleBlock:
          AiTitleBlock.fromJson((result['titleBlock'] as Map?)?.cast<String, dynamic>()),
      northArrow: result['northArrow'] as String?,
      scale: result['scale'] as String?,
      segments: ((result['segments'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiSegment.fromJson(e.cast<String, dynamic>()))
          .toList(),
      components: ((result['components'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiComponent.fromJson(e.cast<String, dynamic>()))
          .toList(),
      elevations: ((result['elevations'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => {
                'atId': (e['atId'] ?? '').toString(),
                'value': (e['value'] ?? '').toString(),
              })
          .toList(),
      billOfMaterials: ((result['billOfMaterials'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiBomItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
      needsUserInput: ((result['needsUserInput'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiNeedsInput.fromJson(e.cast<String, dynamic>()))
          .toList(),
      uncertainty: ((result['uncertainty'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      warnings: ((result['warnings'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      error: result['error'] as String?,
      tookMs: (envelope['tookMs'] as num?)?.toInt(),
      model: envelope['model'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// HTTP call
// ─────────────────────────────────────────────────────────────────────────

class IsoScannerAiException implements Exception {
  final String message;
  final int? statusCode;

  /// Kod maszynowy z odpowiedzi serwera (`error.code`), np. `RATE_LIMITED`,
  /// `AI_BUDGET_EXCEEDED`, `PREMIUM_REQUIRED`. Null, gdy serwer go nie podał.
  final String? code;

  /// Z nagłówka `Retry-After` — za ile serwer przyjmie kolejny skan.
  final Duration? retryAfter;

  IsoScannerAiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfter,
  });

  /// Dzienny limit (urządzenia albo sieci), nie minutowy: serwer liczy dobę
  /// UTC, więc `Retry-After` jest wtedy liczony w godzinach, a minutowy
  /// limiter odpowiada najwyżej 60 s.
  bool get isDailyLimit =>
      statusCode == 429 &&
      retryAfter != null &&
      retryAfter! > const Duration(minutes: 5);

  /// Czy żądanie mogło dojść do modelu (i kosztować). Odmowy, które serwer
  /// wydaje PRZED wywołaniem Claude — limity, budżet, Premium, zły format,
  /// brak trasy, brak konfiguracji AI — nie zjadają klientowego limitu.
  bool get reachedModel {
    final s = statusCode ?? 0;
    if (s < 500) return false;
    const beforeModel = {
      'AI_BUDGET_EXCEEDED',
      'SERVICE_UNAVAILABLE',
      'AI_CONFIG',
    };
    return !beforeModel.contains(code);
  }

  @override
  String toString() => 'IsoScannerAiException($statusCode $code): $message';
}

String _tr(String pl, String en) => AppLanguageController.isEnglish ? en : pl;

// ─────────────────────────────────────────────────────────────────────────
// Przygotowanie zdjęcia
// ─────────────────────────────────────────────────────────────────────────
//
// Wcześniej wszystko poza *.png szło jako `image/jpeg` — także WebP i HEIC —
// a 12-megapikselowe zdjęcie leciało w całości (4–8 MB, po base64 o 1/3 więcej)
// przez 4G na budowie. Teraz:
//   • typ rozpoznajemy po bajtach (jak serwer), nie po rozszerzeniu;
//   • JPEG / PNG / WebP / GIF idą z prawdziwym `media_type`;
//   • zdjęcie dłuższe niż [kScanMaxLongSidePx] zmniejszamy przed wysyłką —
//     model i tak nie czyta więcej szczegółów z większego obrazu, a upload
//     i limit serwera (10 MB base64) na tym zyskują;
//   • HEIC/HEIF/AVIF (serwer odpowiada na nie 415) zamieniamy na JPEG
//     dekoderem platformy (Android 9+, iOS), a gdy się nie da — prosimy o
//     zdjęcie w JPEG.
// Zmniejszanie robi pakiet `image` (czysty Dart, był już w projekcie jako
// zależność `pdf`) w osobnym izolacie, żeby nie zamrozić ekranu.

/// Dłuższy bok zdjęcia wysyłanego do skanera, w pikselach.
const int kScanMaxLongSidePx = 2576;

/// PNG po zmniejszeniu większy niż to idzie jako JPEG (rysunek kreskowy jako
/// PNG zwykle mieści się z zapasem; zdjęcie zapisane jako PNG — nie).
const int _kMaxPngBytes = 5 * 1024 * 1024;

enum ScanImageFormat { jpeg, png, gif, webp, heif, unknown }

/// Format obrazu rozpoznany po magicznych bajtach — tak samo jak robi to
/// serwer (`backend/src/services/imageType.js`).
ScanImageFormat sniffScanImageFormat(List<int> b) {
  bool ascii(int from, String s) {
    if (b.length < from + s.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[from + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return ScanImageFormat.jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      ascii(1, 'PNG') &&
      b[4] == 0x0D &&
      b[5] == 0x0A) {
    return ScanImageFormat.png;
  }
  if (ascii(0, 'GIF87a') || ascii(0, 'GIF89a')) return ScanImageFormat.gif;
  if (ascii(0, 'RIFF') && ascii(8, 'WEBP')) return ScanImageFormat.webp;
  if (ascii(4, 'ftyp') && b.length >= 12) {
    const heifBrands = {
      'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'hevm', 'hevs', //
      'mif1', 'msf1', 'avif', 'avis',
    };
    final brand = String.fromCharCodes(b.sublist(8, 12));
    if (heifBrands.contains(brand)) return ScanImageFormat.heif;
  }
  return ScanImageFormat.unknown;
}

/// `media_type` dla formatu, który serwer przyjmuje; `null` dla pozostałych.
String? scanMediaType(ScanImageFormat format) => switch (format) {
      ScanImageFormat.jpeg => 'image/jpeg',
      ScanImageFormat.png => 'image/png',
      ScanImageFormat.gif => 'image/gif',
      ScanImageFormat.webp => 'image/webp',
      ScanImageFormat.heif || ScanImageFormat.unknown => null,
    };

/// Zdjęcie gotowe do wysłania.
class PreparedScanImage {
  final Uint8List bytes;
  final String mediaType;

  /// Zmniejszone do [kScanMaxLongSidePx].
  final bool resized;

  /// Przekodowane do innego formatu (np. HEIC → JPEG).
  final bool converted;

  const PreparedScanImage(
    this.bytes,
    this.mediaType, {
    this.resized = false,
    this.converted = false,
  });
}

/// Surowe piksele RGBA po dekodowaniu przez platformę.
typedef RgbaImage = ({Uint8List rgba, int width, int height});

/// Dekoder platformy dla formatów, których pakiet `image` nie zna (HEIC).
/// Wstrzykiwany w testach.
typedef PlatformImageDecoder = Future<RgbaImage> Function(
    Uint8List bytes, int maxLongSide);

/// Rozpoznaje format, w razie potrzeby zmniejsza i przekodowuje zdjęcie.
/// Rzuca [IsoScannerAiException] z komunikatem dla montera, gdy formatu nie
/// da się wysłać.
Future<PreparedScanImage> prepareScanImage(
  Uint8List bytes, {
  PlatformImageDecoder? platformDecoder,
}) async {
  final format = sniffScanImageFormat(bytes);
  switch (format) {
    case ScanImageFormat.unknown:
      throw IsoScannerAiException(_tr(
        'Nieobsługiwany format zdjęcia. Wybierz zdjęcie JPG, PNG albo WEBP.',
        'Unsupported photo format. Pick a JPG, PNG or WEBP photo.',
      ));
    case ScanImageFormat.heif:
      try {
        final raw =
            await (platformDecoder ?? _decodeWithPlatform)(bytes, kScanMaxLongSidePx);
        final jpeg = await compute(_encodeRgbaAsJpeg, raw);
        return PreparedScanImage(jpeg, 'image/jpeg', converted: true);
      } catch (e) {
        debugPrint('prepareScanImage: HEIC/HEIF nie do przekonwertowania: $e');
        throw IsoScannerAiException(_tr(
          'Tego zdjęcia (HEIC/HEIF) nie da się przekonwertować na tym '
              'telefonie. Zrób zdjęcie w JPEG — w iPhonie: Ustawienia → '
              'Aparat → Formaty → „Najbardziej zgodne" — albo wybierz zrzut '
              'ekranu rysunku.',
          'This photo (HEIC/HEIF) cannot be converted on this phone. Take the '
              'photo as JPEG — on iPhone: Settings → Camera → Formats → "Most '
              'Compatible" — or pick a screenshot of the drawing.',
        ));
      }
    case ScanImageFormat.jpeg:
    case ScanImageFormat.png:
    case ScanImageFormat.gif:
    case ScanImageFormat.webp:
      final original = PreparedScanImage(bytes, scanMediaType(format)!);
      final longSide = _longSideOf(bytes);
      if (longSide == null || longSide <= kScanMaxLongSidePx) return original;
      try {
        return await compute(_downscale, (bytes, format));
      } catch (e) {
        // Nie udało się zmniejszyć — wysyłamy oryginał; za duży obraz serwer
        // odrzuci 413 z czytelnym komunikatem.
        debugPrint('prepareScanImage: zmniejszanie nie wyszło: $e');
        return original;
      }
  }
}

/// Dłuższy bok z nagłówka obrazu (bez dekodowania pikseli); `null`, gdy
/// nagłówka nie da się odczytać.
int? _longSideOf(Uint8List bytes) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    return math.max(info.width, info.height);
  } catch (_) {
    return null;
  }
}

/// W izolacie: dekoduje pierwszą klatkę, obraca wg EXIF, zmniejsza dłuższy
/// bok do [kScanMaxLongSidePx] i koduje — PNG/GIF jako PNG (ostre linie
/// rysunku), chyba że wyjdzie za duży; resztę jako JPEG.
PreparedScanImage _downscale((Uint8List, ScanImageFormat) job) {
  final (bytes, format) = job;
  final decoded = img.decodeImage(bytes, frame: 0);
  if (decoded == null) throw StateError('nie udało się zdekodować obrazu');
  final oriented = img.bakeOrientation(decoded);
  final landscape = oriented.width >= oriented.height;
  final resized = img.copyResize(
    oriented,
    width: landscape ? kScanMaxLongSidePx : null,
    height: landscape ? null : kScanMaxLongSidePx,
    interpolation: img.Interpolation.average,
  );
  if (format == ScanImageFormat.png || format == ScanImageFormat.gif) {
    final png = img.encodePng(resized);
    if (png.length <= _kMaxPngBytes) {
      return PreparedScanImage(png, 'image/png',
          resized: true, converted: format != ScanImageFormat.png);
    }
  }
  return PreparedScanImage(
    img.encodeJpg(resized, quality: 88),
    'image/jpeg',
    resized: true,
    converted: format != ScanImageFormat.jpeg,
  );
}

/// W izolacie: surowe RGBA z dekodera platformy → JPEG.
Uint8List _encodeRgbaAsJpeg(RgbaImage raw) {
  final image = img.Image.fromBytes(
    width: raw.width,
    height: raw.height,
    bytes: raw.rgba.buffer,
    bytesOffset: raw.rgba.offsetInBytes,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 88);
}

/// Dekoder platformy (Skia + systemowe kodeki; HEIF na Androidzie 9+ i iOS),
/// od razu ze zmniejszeniem do [maxLongSide].
Future<RgbaImage> _decodeWithPlatform(Uint8List bytes, int maxLongSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (w, h) {
      final longSide = math.max(w, h);
      if (longSide <= maxLongSide) return ui.TargetImageSize();
      final scale = maxLongSide / longSide;
      return ui.TargetImageSize(
        width: math.max(1, (w * scale).round()),
        height: math.max(1, (h * scale).round()),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('brak pikseli');
      return (
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Komunikat dla montera na odmowę serwera skanera — co się stało i co zrobić.
///
/// Null, gdy odpowiedź nie wymaga tłumaczenia (np. 400 z czytelnym tekstem
/// serwera, który ekran pokaże sam). Czysta funkcja: [now] podaje zegar, żeby
/// godzinę odnowienia limitu dało się sprawdzić w teście.
@visibleForTesting
String? friendlyScanError(
  int status,
  String? code, {
  Duration? retryAfter,
  DateTime Function() now = DateTime.now,
}) {
  if (code != null && code.startsWith('INSTALL_SECRET_')) {
    return _tr(
      'Serwer skanera nie rozpoznał tej instalacji aplikacji. Uruchom '
          'aplikację ponownie; jeśli to nie pomoże, napisz do nas z ekranu '
          'profilu (Kontakt).',
      'The scanner server did not recognise this app installation. Restart '
          'the app; if that does not help, write to us from your profile '
          '(Contact).',
    );
  }
  if (status == 415 || code == 'UNSUPPORTED_IMAGE_TYPE') {
    return _tr(
      'Serwer nie przyjmuje tego formatu zdjęcia. Zrób zdjęcie w JPEG albo '
          'wybierz zrzut ekranu rysunku.',
      'The server does not accept this photo format. Take the photo as JPEG '
          'or pick a screenshot of the drawing.',
    );
  }
  if (status == 402 || code == 'PREMIUM_REQUIRED') {
    // Właściciel może włączyć AI_SCAN_REQUIRES_PREMIUM na serwerze. Dopóki
    // Premium nie da się kupić w aplikacji, nie odsyłamy do zakupu.
    return kPaidFeaturesEnabled
        ? _tr(
            'Skaner rysunków jest dostępny w planie Premium. Wymiary możesz '
                'też wpisać ręcznie.',
            'The drawing scanner is available with Premium. You can also '
                'type the dimensions in by hand.',
          )
        : _tr(
            'Skaner rysunków jest chwilowo dostępny tylko w planie Premium, '
                'którego nie da się jeszcze kupić w aplikacji. Wymiary wpisz '
                'ręcznie — lista cięć działa bez skanera.',
            'The drawing scanner is for Premium only for now, and Premium '
                'cannot be bought in the app yet. Type the dimensions in by '
                'hand — the cut list works without the scanner.',
          );
  }
  if (status == 429) {
    final wait = retryAfter;
    if (wait != null && wait > const Duration(minutes: 5)) {
      final at = _hhmm(now().add(wait));
      return _tr(
        'Dzienny limit skanów został wykorzystany. Odnowi się ok. $at — do '
            'tego czasu wpisz wymiary ręcznie.',
        'The daily scan limit is used up. It renews at about $at — until '
            'then type the dimensions in by hand.',
      );
    }
    return _tr(
      'Za dużo skanów naraz — odczekaj minutę i spróbuj ponownie.',
      'Too many scans at once — wait a minute and try again.',
    );
  }
  if (code == 'AI_BUDGET_EXCEEDED') {
    return _tr(
      'Skaner jest wyłączony do końca miesiąca — wyczerpał się miesięczny '
          'budżet AI. Wymiary wpisz ręcznie; lista cięć działa bez skanera.',
      'The scanner is off until the end of the month — the monthly AI '
          'budget is used up. Type the dimensions in by hand; the cut list '
          'works without the scanner.',
    );
  }
  if (code == 'AI_BUSY') {
    return _tr(
      'Skaner jest chwilowo przeciążony — spróbuj za minutę.',
      'The scanner is busy right now — try again in a minute.',
    );
  }
  if (status == 404 ||
      status == 500 ||
      code == 'AI_CONFIG' ||
      code == 'SERVICE_UNAVAILABLE') {
    // 404: serwer nie ma jeszcze trasy skanera; 500: stara wersja backendu
    // (sprzed 2026-09-24); AI_CONFIG / SERVICE_UNAVAILABLE: serwer bez
    // skonfigurowanego AI. Monter nic tu nie naprawi ponowieniem.
    return _tr(
      'Skaner nie jest jeszcze dostępny na naszym serwerze. Spróbuj później '
          '— wymiary możesz wpisać ręcznie, reszta aplikacji działa bez niego.',
      'The scanner is not available on our server yet. Try again later — '
          'you can type the dimensions in by hand; the rest of the app works '
          'without it.',
    );
  }
  return null;
}

Duration? _retryAfter(Map<String, String> headers) {
  final raw = headers['retry-after']?.trim();
  if (raw == null || raw.isEmpty) return null;
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds < 0) return null;
  return Duration(seconds: seconds);
}

Future<AiScanResult> scanIsoImage(
  String imagePath, {
  // Sonnet vision over a 4-8 MB iso photo on a 4G connection routinely runs
  // 30-60 s before the first byte. Old 90 s window was tight; lift to 150 s
  // to absorb a slow uplink without falsely cancelling a successful scan.
  Duration timeout = const Duration(seconds: 150),
  PlatformImageDecoder? platformDecoder,
  DateTime Function() clock = DateTime.now,
}) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    throw IsoScannerAiException('Plik nie istnieje: $imagePath');
  }
  final bytes = await file.readAsBytes();
  final prepared =
      await prepareScanImage(bytes, platformDecoder: platformDecoder);

  // X-Device-Id + X-Install-Secret: nowy backend (TOFU) wiąże sekret z
  // device_id; backend PrzetargAI nieznane nagłówki ignoruje.
  final identity = await PremiumService.instance.authHeaders();
  final deviceId = PremiumService.instance.deviceId;
  final uri = Uri.parse('$kIsoAiBase${BackendConfig.scanIso}');
  final resp = await http
      .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...identity,
        },
        body: jsonEncode({
          'image_base64': base64Encode(prepared.bytes),
          'media_type': prepared.mediaType,
          'device_id': deviceId,
        }),
      )
      .timeout(timeout);

  if (resp.statusCode != 200) {
    String message = 'Błąd serwera (${resp.statusCode})';
    String? code;
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map && err['message'] is String) {
        message = err['message'] as String;
      } else if (j['message'] is String) {
        message = j['message'] as String;
      }
      if (err is Map && err['code'] is String) code = err['code'] as String;
    } catch (_) {}
    final retryAfter = _retryAfter(resp.headers);
    final friendly = friendlyScanError(
      resp.statusCode,
      code,
      retryAfter: retryAfter,
      now: clock,
    );
    if (friendly != null) {
      // Surowa odpowiedź tylko do logu.
      debugPrint('scanIsoImage ${resp.statusCode} $code: $message');
      message = friendly;
    }
    throw IsoScannerAiException(
      message,
      statusCode: resp.statusCode,
      code: code,
      retryAfter: retryAfter,
    );
  }

  final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
  return AiScanResult.fromEnvelope(envelope);
}
