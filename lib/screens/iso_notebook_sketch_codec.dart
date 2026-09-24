part of 'iso_notebook_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ISO NOTEBOOK — sketch <-> JSON.
//
// The notebook's drawing is a list of private model objects (`_Seg`, `_Comp`,
// `_Note`) that used to exist only in RAM. This file turns them into one JSON
// document for `iso_drawings.json` (see `lib/database/iso_drawing_dao.dart`)
// and back. It is a `part` of the screen library because the model classes
// are private to it; nothing here touches widgets, the database or the
// screen state.
//
// FORMAT (kIsoSketchFormatVersion = 1):
//   {
//     "format": 1,
//     "name": "6\"-CWS-1234",
//     "items": [
//       {"kind": "seg",  "tool": "pipe", "a": [x, y], "b": [x, y],
//        "slope": "", "insulated": false,
//        "calc": null | {"iso": "2000", "ref": "centreToCentre",
//                        "deducts": [{"name": "...", "value": "..."}]}},
//       {"kind": "comp", "tool": "elbow90", "pos": [x, y], "dir": 0,
//        "dir2": 1 | null, "label": "", "dn": 100 | null,
//        "elbowSubtype": "lr90" | null, "cteMm": 152 | null,
//        "physicalLengthMm": null, "dnOut": null,
//        "endA": "buttWeld" | null, "endB": null},
//       {"kind": "note", "pos": [x, y], "text": "EL +12.500"}
//     ],
//     "takeoutMemory": {
//       "values": [{"tool": "elbow90", "dn": 100, "mm": 152}],
//       "lastDn": {"elbow90": 100}
//     }
//   }
//
// Coordinates are canvas world units (grid step 32), exactly as stored in the
// model. Enums are written by `.name` — `_Tool.name` is already a de-facto
// stable identifier (ComponentClassification keys on it).
//
// EVOLVING THE FORMAT: a new field that an older build would drop on its
// next autosave MUST bump [kIsoSketchFormatVersion]. An older build refuses a
// newer format (it starts a fresh sketch and leaves the stored one alone),
// which is the only way to guarantee it never overwrites data it cannot
// represent. Items this build cannot read inside a known format are counted
// in [_IsoSketch.skippedItems]; the screen then works on a copy so the
// original row stays intact.
// ═══════════════════════════════════════════════════════════════════════════

/// Version of the JSON document written into `iso_drawings.json`.
const int kIsoSketchFormatVersion = 1;

/// The stored sketch cannot be opened by this build.
class IsoSketchFormatException implements Exception {
  final String message;

  /// True when the sketch was written by a NEWER app version.
  final bool tooNew;

  const IsoSketchFormatException(this.message, {this.tooNew = false});

  @override
  String toString() => 'IsoSketchFormatException: $message';
}

/// Everything the notebook needs to put a drawing back on screen.
class _IsoSketch {
  final String name;
  final List<_Item> items;

  /// `_IsoState._compDimCache`: (tool, DN) → take-out typed for this drawing.
  final Map<(_Tool, int), int> takeoutByDn;

  /// `_IsoState._lastDnByTool`.
  final Map<_Tool, int> lastDnByTool;

  /// Items present in the document that this build could not read.
  final int skippedItems;

  const _IsoSketch({
    required this.name,
    required this.items,
    this.takeoutByDn = const {},
    this.lastDnByTool = const {},
    this.skippedItems = 0,
  });
}

// ── encode ──────────────────────────────────────────────────────────────────

List<double> _encodeOffset(Offset o) => [
      o.dx.isFinite ? o.dx : 0.0,
      o.dy.isFinite ? o.dy : 0.0,
    ];

Map<String, Object?> _encodeCalc(_CutCalc c) => {
      'iso': c.iso,
      'ref': c.ref.name,
      'deducts': [
        for (final d in c.deducts) {'name': d.name, 'value': d.value},
      ],
    };

Map<String, Object?> _encodeItem(_Item it) {
  if (it is _Seg) {
    return {
      'kind': 'seg',
      'tool': it.t.name,
      'a': _encodeOffset(it.a),
      'b': _encodeOffset(it.b),
      'slope': it.slope,
      'insulated': it.insulated,
      'calc': it.calc == null ? null : _encodeCalc(it.calc!),
    };
  }
  if (it is _Comp) {
    return {
      'kind': 'comp',
      'tool': it.t.name,
      'pos': _encodeOffset(it.pos),
      'dir': it.dir,
      'dir2': it.dir2,
      'label': it.label,
      'dn': it.dn,
      'elbowSubtype': it.elbowSubtype?.name,
      'cteMm': it.cteMm,
      'physicalLengthMm': it.physicalLengthMm,
      'dnOut': it.dnOut,
      'endA': it.endA?.name,
      'endB': it.endB?.name,
    };
  }
  if (it is _Note) {
    return {
      'kind': 'note',
      'pos': _encodeOffset(it.pos),
      'text': it.text,
    };
  }
  // A new _Item subtype has to be taught to this codec; failing the save is
  // loud, while writing nothing for it would lose it on the next reopen.
  throw StateError('ISO sketch codec does not know ${it.runtimeType}');
}

Map<String, Object?> _encodeIsoSketch(_IsoSketch s) => {
      'format': kIsoSketchFormatVersion,
      'name': s.name,
      'items': [for (final it in s.items) _encodeItem(it)],
      'takeoutMemory': {
        'values': [
          for (final e in s.takeoutByDn.entries)
            {'tool': e.key.$1.name, 'dn': e.key.$2, 'mm': e.value},
        ],
        'lastDn': {
          for (final e in s.lastDnByTool.entries) e.key.name: e.value,
        },
      },
    };

// ── decode ──────────────────────────────────────────────────────────────────

/// Thrown inside the item decoder; the item is skipped and counted.
class _UnreadableItem implements Exception {
  const _UnreadableItem();
}

final Map<String, _Tool> _toolByName = _Tool.values.asNameMap();
final Map<String, DimRef> _dimRefByName = DimRef.values.asNameMap();
final Map<String, _ElbowSubtype> _elbowByName = _ElbowSubtype.values.asNameMap();
final Map<String, EndConnection> _endByName = EndConnection.values.asNameMap();

T _enumOrThrow<T>(Map<String, T> byName, Object? raw) {
  final v = raw is String ? byName[raw] : null;
  if (v == null) throw const _UnreadableItem();
  return v;
}

T? _optionalEnum<T>(Map<String, T> byName, Object? raw) =>
    raw == null ? null : _enumOrThrow(byName, raw);

Offset _decodeOffset(Object? raw) {
  if (raw is! List || raw.length != 2) throw const _UnreadableItem();
  final x = raw[0];
  final y = raw[1];
  if (x is! num || y is! num) throw const _UnreadableItem();
  final o = Offset(x.toDouble(), y.toDouble());
  if (!o.dx.isFinite || !o.dy.isFinite) throw const _UnreadableItem();
  return o;
}

int? _optionalInt(Object? raw) {
  if (raw == null) return null;
  if (raw is! num) throw const _UnreadableItem();
  return raw.toInt();
}

String _string(Object? raw) {
  if (raw == null) return '';
  if (raw is! String) throw const _UnreadableItem();
  return raw;
}

_CutCalc _decodeCalc(Object? raw) {
  if (raw is! Map) throw const _UnreadableItem();
  final deductsRaw = raw['deducts'] ?? const [];
  if (deductsRaw is! List) throw const _UnreadableItem();
  final deducts = <_Deduct>[
    for (final d in deductsRaw)
      if (d is Map)
        _Deduct(_string(d['name']), _string(d['value']))
      else
        throw const _UnreadableItem(),
  ];
  return _CutCalc(
    _string(raw['iso']),
    deducts: deducts,
    ref: raw['ref'] == null
        ? DimRef.centreToCentre
        : _enumOrThrow(_dimRefByName, raw['ref']),
  );
}

_Item _decodeItem(Object? raw) {
  if (raw is! Map) throw const _UnreadableItem();
  switch (raw['kind']) {
    case 'seg':
      final tool = _enumOrThrow(_toolByName, raw['tool']);
      if (!tool.isLine) throw const _UnreadableItem();
      final insulated = raw['insulated'] ?? false;
      if (insulated is! bool) throw const _UnreadableItem();
      return _Seg(
        _decodeOffset(raw['a']),
        _decodeOffset(raw['b']),
        tool,
        calc: raw['calc'] == null ? null : _decodeCalc(raw['calc']),
        slope: _string(raw['slope']),
        insulated: insulated,
      );
    case 'comp':
      final tool = _enumOrThrow(_toolByName, raw['tool']);
      if (!tool.isComp) throw const _UnreadableItem();
      return _Comp(
        _decodeOffset(raw['pos']),
        tool,
        dir: _optionalInt(raw['dir']) ?? 0,
        dir2: _optionalInt(raw['dir2']),
        label: _string(raw['label']),
        dn: _optionalInt(raw['dn']),
        elbowSubtype: _optionalEnum(_elbowByName, raw['elbowSubtype']),
        cteMm: _optionalInt(raw['cteMm']),
        physicalLengthMm: _optionalInt(raw['physicalLengthMm']),
        dnOut: _optionalInt(raw['dnOut']),
        endA: _optionalEnum(_endByName, raw['endA']),
        endB: _optionalEnum(_endByName, raw['endB']),
      );
    case 'note':
      return _Note(_decodeOffset(raw['pos']), _string(raw['text']));
    default:
      throw const _UnreadableItem();
  }
}

/// Reads a decoded JSON document back into a sketch.
///
/// Throws [IsoSketchFormatException] when the document is not a sketch at
/// all or comes from a newer format. Individual unreadable items do NOT
/// throw: they are skipped and counted, so one odd element never costs the
/// fitter the rest of the drawing.
_IsoSketch _decodeIsoSketch(Object? raw) {
  if (raw is! Map) {
    throw const IsoSketchFormatException('not a JSON object');
  }
  final format = raw['format'];
  if (format is! int) {
    throw const IsoSketchFormatException('missing format version');
  }
  if (format > kIsoSketchFormatVersion) {
    throw IsoSketchFormatException(
      'format $format is newer than $kIsoSketchFormatVersion',
      tooNew: true,
    );
  }
  final itemsRaw = raw['items'] ?? const [];
  if (itemsRaw is! List) {
    throw const IsoSketchFormatException('items is not a list');
  }

  final items = <_Item>[];
  var skipped = 0;
  for (final r in itemsRaw) {
    try {
      items.add(_decodeItem(r));
    } on _UnreadableItem {
      skipped++;
    }
  }

  // The take-out memory is a typing convenience, not drawing data: an entry
  // this build cannot read is dropped without counting against the sketch.
  final takeoutByDn = <(_Tool, int), int>{};
  final lastDn = <_Tool, int>{};
  final memory = raw['takeoutMemory'];
  if (memory is Map) {
    final values = memory['values'];
    if (values is List) {
      for (final v in values) {
        if (v is! Map) continue;
        final tool = v['tool'] is String ? _toolByName[v['tool']] : null;
        final dn = v['dn'];
        final mm = v['mm'];
        if (tool == null || dn is! num || mm is! num) continue;
        takeoutByDn[(tool, dn.toInt())] = mm.toInt();
      }
    }
    final last = memory['lastDn'];
    if (last is Map) {
      for (final e in last.entries) {
        final tool = e.key is String ? _toolByName[e.key] : null;
        final dn = e.value;
        if (tool == null || dn is! num) continue;
        lastDn[tool] = dn.toInt();
      }
    }
  }

  final name = raw['name'];
  return _IsoSketch(
    name: name is String ? name : '',
    items: items,
    takeoutByDn: takeoutByDn,
    lastDnByTool: lastDn,
    skippedItems: skipped,
  );
}

/// JSON text → model → JSON text. The round trip the autosave relies on,
/// exposed so a test can prove every field of every element survives it.
@visibleForTesting
String isoSketchRoundTripForTesting(String json) =>
    jsonEncode(_encodeIsoSketch(_decodeIsoSketch(jsonDecode(json))));

/// How many items of [json] this build cannot read.
@visibleForTesting
int isoSketchSkippedItemsForTesting(String json) =>
    _decodeIsoSketch(jsonDecode(json)).skippedItems;
