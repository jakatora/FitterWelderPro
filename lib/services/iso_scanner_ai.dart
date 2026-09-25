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

// ── Tolerant JSON readers (schema v2) ────────────────────────────────────
//
// The model does not always keep to the declared types: a DN comes back as
// `100` or `"100"`, a weld number as `7` or `"W-07"`. Every v2 field is read
// through these, so a wrong type becomes "not read" (null) instead of a
// crash — and an unknown field is simply ignored.

String? _jStr(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is num || v is bool) return v.toString();
  return null;
}

double? _jNum(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

int? _jInt(dynamic v) {
  final d = _jNum(v);
  if (d == null || d != d.roundToDouble()) return null;
  return d.toInt();
}

bool? _jBool(dynamic v) => v is bool ? v : null;

List<String> _jStrList(dynamic v) {
  if (v is String) return [if (v.trim().isNotEmpty) v.trim()];
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (_jStr(e) != null) _jStr(e)!,
  ];
}

/// Direction of a pipe run as the model read it off the drawing: an axis
/// word (`E`, `W`, `N`, `S`, `UP`, `DOWN`, `+X`…) or a vector `{x, y, z}`.
/// Kept raw here; `scan_geometry.dart` turns it into a vector.
Object? _jDirection(dynamic v) {
  if (v is String) return v.trim().isEmpty ? null : v.trim();
  if (v is Map) {
    final m = <String, double>{};
    for (final k in ['x', 'y', 'z']) {
      final n = _jNum(v[k]);
      if (n != null) m[k] = n;
    }
    return m.isEmpty ? null : m;
  }
  return null;
}

/// `{"E": 500, "N": 300, "UP": 400}` — projections of a skewed run, mm.
Map<String, double> _jProjections(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, double>{};
  v.forEach((k, value) {
    final key = _jStr(k);
    final n = _jNum(value);
    if (key != null && n != null && n.isFinite) out[key] = n;
  });
  return out;
}

class AiSegment {
  final String id;
  final double? dimensionMm;
  final String? rawDimension;
  final String? fromId;
  final String? toId;
  final bool auxiliary;
  final AiConfidence confidence;

  // ── v2 ────────────────────────────────────────────────────────────────
  /// Nominal size of THIS run as printed next to it (DN), when the drawing
  /// gives one — a run past a reducer has a different size than the line.
  final int? dn;

  /// Size callout as printed (`4"`, `NPS 4`, `DN100`) when not a plain DN.
  final String? nps;

  /// Schedule printed for this run, when it differs from the title block.
  final String? schedule;

  /// Direction of the run on the isometric: `E`/`W`/`N`/`S`/`UP`/`DOWN`,
  /// `+X`…, or a vector map `{x, y, z}` for a skewed run.
  final Object? direction;

  /// Projections of a skewed (offset) run, mm, keyed by direction word —
  /// what an isometric prints on the hatched offset triangle.
  final Map<String, double> projections;

  /// Where the dimension line stops on the from / to side as drawn:
  /// `CL` (centreline / work point), `FACE` (the component's face, a
  /// flange's gasket face), `EOP` (end of pipe / weld line).
  final String? refFrom;
  final String? refTo;

  /// Spool this run belongs to (id or label from the drawing).
  final String? spoolId;

  /// Slope callout as printed (`1:100`, `1%`), for display.
  final String? slope;

  /// Set by the review screen when the fitter re-entered / confirmed the
  /// dimension himself. Never set from the model's JSON on purpose.
  final bool userConfirmed;

  AiSegment({
    required this.id,
    this.dimensionMm,
    this.rawDimension,
    this.fromId,
    this.toId,
    this.auxiliary = false,
    this.confidence = AiConfidence.unknown,
    this.dn,
    this.nps,
    this.schedule,
    this.direction,
    this.projections = const {},
    this.refFrom,
    this.refTo,
    this.spoolId,
    this.slope,
    this.userConfirmed = false,
  });

  factory AiSegment.fromJson(Map<String, dynamic> j) => AiSegment(
        id: _jStr(j['id']) ?? '',
        dimensionMm: _jNum(j['dimensionMm']),
        rawDimension: _jStr(j['rawDimension']),
        fromId: _jStr(j['fromId']),
        toId: _jStr(j['toId']),
        auxiliary: j['auxiliary'] as bool? ?? false,
        confidence: _confFromJson(j['confidence']),
        dn: _jInt(j['dn']),
        nps: _jStr(j['nps']),
        schedule: _jStr(j['schedule']),
        direction: _jDirection(j['direction']),
        projections: _jProjections(j['projections']),
        refFrom: _jStr(j['refFrom'])?.toUpperCase(),
        refTo: _jStr(j['refTo'])?.toUpperCase(),
        spoolId: _jStr(j['spoolId']),
        slope: _jStr(j['slope']),
      );

  static const Object _keep = Object();

  /// Copy with some fields replaced. Every field not named is kept, so a
  /// correction on the review screen never drops a v2 field on the way.
  AiSegment copyWith({
    String? id,
    Object? dimensionMm = _keep,
    Object? rawDimension = _keep,
    Object? fromId = _keep,
    Object? toId = _keep,
    bool? auxiliary,
    AiConfidence? confidence,
    Object? dn = _keep,
    Object? schedule = _keep,
    bool? userConfirmed,
  }) =>
      AiSegment(
        id: id ?? this.id,
        dimensionMm: identical(dimensionMm, _keep)
            ? this.dimensionMm
            : dimensionMm as double?,
        rawDimension: identical(rawDimension, _keep)
            ? this.rawDimension
            : rawDimension as String?,
        fromId: identical(fromId, _keep) ? this.fromId : fromId as String?,
        toId: identical(toId, _keep) ? this.toId : toId as String?,
        auxiliary: auxiliary ?? this.auxiliary,
        confidence: confidence ?? this.confidence,
        dn: identical(dn, _keep) ? this.dn : dn as int?,
        nps: identical(dn, _keep) ? nps : null,
        schedule:
            identical(schedule, _keep) ? this.schedule : schedule as String?,
        direction: direction,
        projections: projections,
        refFrom: refFrom,
        refTo: refTo,
        spoolId: spoolId,
        slope: slope,
        userConfirmed: userConfirmed ?? this.userConfirmed,
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

  // ── v2 ────────────────────────────────────────────────────────────────
  /// Sizes of a size-changing fitting as printed: a reducer `DN100×80`, a
  /// reducing tee (run × branch), an olet (header × outlet). Raw text or DN.
  final String? sizeLarge;
  final String? sizeSmall;

  /// End connection: `BW` (butt weld), `SW` (socket weld), `THD` (thread),
  /// `FL` (flanged).
  final String? endType;

  /// Flange type: `WN`, `SO`, `SW`, `LJ`, `BL`, `THD`.
  final String? flangeType;

  /// Pressure class as printed: `150`, `300`, `3000`, `6000`…
  final String? rating;

  /// Flange facing: `RF`, `FF`, `RTJ`.
  final String? facing;

  /// Components bolted / screwed straight onto this one with no pipe in
  /// between — a flanged valve between its two flanges.
  final List<String> connectedTo;

  /// Tee / olet: the segment ids of the straight-through run, and the
  /// segment id of the branch.
  final List<String> runIds;
  final String? branchId;

  /// Bill-of-materials position number (`item`) of this component.
  final String? bomItem;

  /// Bend angle of an elbow in degrees when printed (`60°`).
  final double? angleDeg;

  /// Spool this component belongs to.
  final String? spoolId;

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
    this.sizeLarge,
    this.sizeSmall,
    this.endType,
    this.flangeType,
    this.rating,
    this.facing,
    this.connectedTo = const [],
    this.runIds = const [],
    this.branchId,
    this.bomItem,
    this.angleDeg,
    this.spoolId,
  });

  /// Copy with a new type / valve type / confidence; everything else kept.
  AiComponent copyWith({
    String? id,
    String? type,
    Object? valveType = _keepC,
    AiConfidence? confidence,
  }) =>
      AiComponent(
        id: id ?? this.id,
        type: type ?? this.type,
        valveType: identical(valveType, _keepC)
            ? this.valveType
            : valveType as String?,
        supportType: supportType,
        label: label,
        weldNo: weldNo,
        weldType: weldType,
        weldNde: weldNde,
        weldPwht: weldPwht,
        weldPosition: weldPosition,
        throatA: throatA,
        isField: isField,
        instrumentTag: instrumentTag,
        confidence: confidence ?? this.confidence,
        sizeLarge: sizeLarge,
        sizeSmall: sizeSmall,
        endType: endType,
        flangeType: flangeType,
        rating: rating,
        facing: facing,
        connectedTo: connectedTo,
        runIds: runIds,
        branchId: branchId,
        bomItem: bomItem,
        angleDeg: angleDeg,
        spoolId: spoolId,
      );

  static const Object _keepC = Object();

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
        id: _jStr(j['id']) ?? '',
        type: _jStr(j['type']) ?? 'other',
        valveType: _jStr(j['valveType']),
        supportType: _jStr(j['supportType']),
        label: _jStr(j['label']),
        weldNo: _jStr(j['weldNo']),
        weldType: _jStr(j['weldType']),
        weldNde: _jStr(j['weldNde']),
        weldPwht: _jBool(j['weldPwht']),
        weldPosition: _jStr(j['weldPosition']),
        throatA: _jStr(j['throatA']),
        isField: _jBool(j['isField']),
        instrumentTag: _jStr(j['instrumentTag']),
        confidence: _confFromJson(j['confidence']),
        sizeLarge: _jStr(j['sizeLarge']),
        sizeSmall: _jStr(j['sizeSmall']),
        endType: _jStr(j['endType'])?.toUpperCase(),
        flangeType: _jStr(j['flangeType'])?.toUpperCase(),
        rating: _jStr(j['rating']),
        facing: _jStr(j['facing'])?.toUpperCase(),
        connectedTo: _jStrList(j['connectedTo']),
        runIds: _jStrList(j['runIds']),
        branchId: _jStr(j['branchId']),
        bomItem: _jStr(j['bomItem']),
        angleDeg: _jNum(j['angleDeg']),
        spoolId: _jStr(j['spoolId']),
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

  /// v2: unit of [quantity] as printed — `M`, `MM`, `FT`, `PCS`, `EA`, `SET`.
  final String? unit;

  AiBomItem({
    required this.item,
    required this.description,
    this.quantity,
    this.material,
    this.size,
    this.schedule,
    this.standard,
    this.unit,
  });

  factory AiBomItem.fromJson(Map<String, dynamic> j) => AiBomItem(
        item: _jStr(j['item']) ?? '',
        description: _jStr(j['description']) ?? '',
        quantity: _jNum(j['quantity']),
        material: _jStr(j['material']),
        size: _jStr(j['size']),
        schedule: _jStr(j['schedule']),
        standard: _jStr(j['standard']),
        unit: _jStr(j['unit'])?.toUpperCase(),
      );
}

/// v2: one weld as marked on the isometric — a shop weld (dot) or a field
/// weld (FW), with its number from the drawing.
class AiWeld {
  final String id;

  /// Weld number as printed (`7`, `W-07`, `FW3`).
  final String? number;

  /// `shop` or `field`; null when the drawing does not say.
  final String? location;

  /// `BW`, `SW`, `BR` (branch), `FW` (fillet).
  final String? jointType;

  /// Components / segments this weld joins (usually two ids).
  final List<String> betweenIds;

  final String? spoolId;
  final String? nde;
  final bool? pwht;
  final String? position;
  final AiConfidence confidence;

  AiWeld({
    required this.id,
    this.number,
    this.location,
    this.jointType,
    this.betweenIds = const [],
    this.spoolId,
    this.nde,
    this.pwht,
    this.position,
    this.confidence = AiConfidence.unknown,
  });

  bool get isField => location == 'field';

  factory AiWeld.fromJson(Map<String, dynamic> j) {
    final loc = _jStr(j['type'] ?? j['location'])?.toLowerCase();
    return AiWeld(
      id: _jStr(j['id']) ?? '',
      number: _jStr(j['number'] ?? j['weldNo']),
      location: switch (loc) {
        'shop' || 'sw' || 'warsztatowa' => 'shop',
        'field' || 'fw' || 'site' || 'montazowa' || 'montażowa' => 'field',
        _ => null,
      },
      jointType: _jStr(j['jointType'])?.toUpperCase(),
      betweenIds: _jStrList(j['betweenIds']),
      spoolId: _jStr(j['spoolId']),
      nde: _jStr(j['nde']),
      pwht: _jBool(j['pwht']),
      position: _jStr(j['position']),
      confidence: _confFromJson(j['confidence']),
    );
  }
}

/// v2: a spool (prefabricated piece) marked on the drawing.
class AiSpool {
  final String id;
  final String? label;
  AiSpool({required this.id, this.label});

  factory AiSpool.fromJson(Map<String, dynamic> j) =>
      AiSpool(id: _jStr(j['id']) ?? '', label: _jStr(j['label']));

  String get display => label ?? id;
}

/// v2: an overall (sum) dimension between two points of the drawing, used
/// to check that the chain of run dimensions closes.
class AiOverallDimension {
  final String fromId;
  final String toId;

  /// Axis word the dimension is measured along (`E`, `N`, `UP`, `X`…).
  final String? axis;
  final double? valueMm;
  final String? raw;
  final AiConfidence confidence;

  AiOverallDimension({
    required this.fromId,
    required this.toId,
    this.axis,
    this.valueMm,
    this.raw,
    this.confidence = AiConfidence.unknown,
  });

  factory AiOverallDimension.fromJson(Map<String, dynamic> j) =>
      AiOverallDimension(
        fromId: _jStr(j['fromId']) ?? '',
        toId: _jStr(j['toId']) ?? '',
        axis: _jStr(j['axis'])?.toUpperCase(),
        valueMm: _jNum(j['valueMm']),
        raw: _jStr(j['raw'] ?? j['rawDimension']),
        confidence: _confFromJson(j['confidence']),
      );
}

/// v2: an elevation mark (`EL +3.250`) at a component or point.
class AiElevation {
  final String atId;

  /// As printed.
  final String value;

  /// Normalised by the model to millimetres, when it did.
  final double? elevationMm;

  AiElevation({required this.atId, required this.value, this.elevationMm});
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

  // ── v2 ────────────────────────────────────────────────────────────────
  /// Version of the reading schema the model answered in. 1 when absent —
  /// a reading from before the v2 prompt, which still parses and plans.
  final int schemaVersion;

  /// Welds marked on the drawing (`welds[]` in the JSON). The legacy weld
  /// markers in [components] stay where they were — see [welds].
  final List<AiWeld> weldMarks;

  final List<AiSpool> spools;
  final List<AiOverallDimension> overallDimensions;

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
    this.schemaVersion = 1,
    this.weldMarks = const [],
    this.spools = const [],
    this.overallDimensions = const [],
  }) : titleBlock = titleBlock ?? AiTitleBlock();

  bool get isError =>
      error != null ||
      warnings.any((w) => w.toLowerCase().contains('not_an_isometric'));

  List<AiComponent> get welds =>
      components.where((c) => c.isWeld).toList(growable: false);

  /// Elevation marks with the model's millimetre value when it gave one.
  List<AiElevation> get elevationPoints => [
        for (final e in elevations)
          if ((e['atId'] ?? '').isNotEmpty)
            AiElevation(
              atId: e['atId']!,
              value: e['value'] ?? '',
              elevationMm: double.tryParse(e['elevationMm'] ?? ''),
            ),
      ];

  /// Copy with some lists replaced; everything else — v2 fields included —
  /// kept. The review screen corrects a scan only through this.
  AiScanResult copyWith({
    List<AiSegment>? segments,
    List<AiComponent>? components,
  }) =>
      AiScanResult(
        drawingStandard: drawingStandard,
        sizeNotation: sizeNotation,
        isHygienic: isHygienic,
        titleBlock: titleBlock,
        northArrow: northArrow,
        scale: scale,
        segments: segments ?? this.segments,
        components: components ?? this.components,
        elevations: elevations,
        billOfMaterials: billOfMaterials,
        needsUserInput: needsUserInput,
        uncertainty: uncertainty,
        warnings: warnings,
        error: error,
        tookMs: tookMs,
        model: model,
        schemaVersion: schemaVersion,
        weldMarks: weldMarks,
        spools: spools,
        overallDimensions: overallDimensions,
      );

  factory AiScanResult.fromEnvelope(Map<String, dynamic> envelope) {
    final result = (envelope['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final version = _jInt(result['schemaVersion'] ?? envelope['schemaVersion']);
    return AiScanResult(
      schemaVersion: (version == null || version < 1) ? 1 : version,
      weldMarks: ((result['welds'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiWeld.fromJson(e.cast<String, dynamic>()))
          .toList(),
      spools: ((result['spools'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiSpool.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.id.isNotEmpty)
          .toList(),
      overallDimensions: ((result['overallDimensions'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiOverallDimension.fromJson(e.cast<String, dynamic>()))
          .where((d) => d.fromId.isNotEmpty && d.toId.isNotEmpty)
          .toList(),
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
                if (_jNum(e['elevationMm']) != null)
                  'elevationMm': _jNum(e['elevationMm'])!.toString(),
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
