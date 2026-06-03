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

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/elbow_takeouts.dart';
import 'premium_service.dart';

const String kIsoAiBase = String.fromEnvironment(
  'ISO_AI_BASE',
  defaultValue: BackendConfig.baseUrl,
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

  bool get is45 {
    final t = '${hint ?? ''} $ask';
    return t.contains('45');
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
  IsoScannerAiException(this.message, {this.statusCode});
  @override
  String toString() => 'IsoScannerAiException($statusCode): $message';
}

Future<AiScanResult> scanIsoImage(
  String imagePath, {
  // Sonnet vision over a 4-8 MB iso photo on a 4G connection routinely runs
  // 30-60 s before the first byte. Old 90 s window was tight; lift to 150 s
  // to absorb a slow uplink without falsely cancelling a successful scan.
  Duration timeout = const Duration(seconds: 150),
}) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    throw IsoScannerAiException('Plik nie istnieje: $imagePath');
  }
  final bytes = await file.readAsBytes();
  final lower = imagePath.toLowerCase();
  final mediaType = (lower.endsWith('.png')) ? 'image/png' : 'image/jpeg';

  await PremiumService.instance.init();
  final deviceId = PremiumService.instance.deviceId;
  final uri = Uri.parse('$kIsoAiBase${BackendConfig.scanIso}');
  final resp = await http
      .post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image_base64': base64Encode(bytes),
          'media_type': mediaType,
          'device_id': deviceId,
        }),
      )
      .timeout(timeout);

  if (resp.statusCode != 200) {
    String message = 'Błąd serwera (${resp.statusCode})';
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map && err['message'] is String) {
        message = err['message'] as String;
      } else if (j['message'] is String) {
        message = j['message'] as String;
      }
    } catch (_) {}
    throw IsoScannerAiException(message, statusCode: resp.statusCode);
  }

  final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
  return AiScanResult.fromEnvelope(envelope);
}
