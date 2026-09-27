// Minimal sketch model for the notebook domain tests — what the notebook
// screen's private classes implement.

import 'dart:ui' show Offset;

import 'package:cut_list_app/domain/iso_notebook/sketch_cut.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/prefab/end_connection.dart';
import 'package:cut_list_app/services/prefab_engine.dart';

class Comp implements SketchComponent {
  Comp(
    this.pos,
    this.toolName, {
    this.dn,
    this.cteMm,
    this.physicalLengthMm,
    this.dnOut,
    this.endA,
    this.endB,
  });
  @override
  final Offset pos;
  @override
  final String toolName;
  @override
  final int? dn;
  @override
  final int? cteMm;
  @override
  final int? physicalLengthMm;
  @override
  final int? dnOut;
  @override
  final EndConnection? endA;
  @override
  final EndConnection? endB;
}

class Ded implements SketchDeduct {
  Ded(this.name, this.value);
  @override
  final String name;
  @override
  final String value;
}

class Dim implements SketchDimension {
  Dim(
    this.iso, {
    this.ref = DimRef.centreToCentre,
    this.deducts = const [],
    this.stopA,
    this.stopB,
  });
  @override
  final String iso;
  @override
  final DimRef ref;
  @override
  final List<SketchDeduct> deducts;
  @override
  final SideStop? stopA;
  @override
  final SideStop? stopB;
  @override
  bool get isReference {
    final t = iso.trim();
    return t.startsWith('(') && t.endsWith(')');
  }
}

class Pipe implements SketchPipe {
  Pipe(this.a, this.b, [this.dimension]);
  @override
  final Offset a;
  @override
  final Offset b;
  @override
  final SketchDimension? dimension;
}

const double kGrid = 32.0;
Offset gp(double x, double y) => Offset(x * kGrid, y * kGrid);
