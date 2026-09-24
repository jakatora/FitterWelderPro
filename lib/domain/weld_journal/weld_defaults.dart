/// Fast entry for gloved hands: remembered values and "next weld".
///
/// A welder logs ~30 joints a shift on the same job, line and procedure. The
/// editor used to open every new weld with a hard-coded 316L, TIG and empty
/// OD / wall — wrong for anyone welding carbon steel, and retyped 30 times
/// for everyone else. Now:
///   * a new weld starts from the values of the last saved one
///     ([WeldEntryDefaults], [newWeldFromDefaults]) — or EMPTY, never an
///     invented material;
///   * "next weld" copies what does not change between joints from a given
///     weld and increments its number ([nextWeldFrom]).
///
/// The last project keeps its own preferences key ([kLastWeldProjectPrefsKey],
/// shipped before this file) so its semantics — trimmed, cleared by saving an
/// empty project — are untouched.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'weld_entry.dart';

// ── Last project ─────────────────────────────────────────────────────────

/// SharedPreferences key holding the project last used in the journal.
///
/// One slip ("Blok 4" vs "Blok4") silently splits the filter, the
/// weld-number suggester and the export into two projects that no longer
/// reconcile at an audit. Remembering the last name costs one string.
const String kLastWeldProjectPrefsKey = 'weld_journal.last_project_v1';

/// Reads the remembered project name, or `''` when there is none. Never
/// throws: a preferences store that cannot be read is a convenience lost,
/// not a reason to keep a welder from logging a joint.
Future<String> loadLastWeldProject() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kLastWeldProjectPrefsKey)?.trim() ?? '';
  } catch (e) {
    debugPrint('[weld_journal] read last project failed: $e');
    return '';
  }
}

/// Remembers [name] as the project to pre-fill next time. An empty name
/// CLEARS the memory: a welder who deliberately saved a weld with no project
/// is telling us the old one no longer applies.
Future<void> saveLastWeldProject(String name) async {
  final trimmed = name.trim();
  try {
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(kLastWeldProjectPrefsKey);
    } else {
      await prefs.setString(kLastWeldProjectPrefsKey, trimmed);
    }
  } catch (e) {
    debugPrint('[weld_journal] persist last project failed: $e');
  }
}

// ── Last used values ─────────────────────────────────────────────────────

const String kWeldDefaultsPrefsKey = 'weld_journal.last_values_v1';

/// Values of the last saved weld that the next new weld starts from.
class WeldEntryDefaults {
  final String pipeName;
  final String isoDrawing;
  final String isoRev;
  final String spool;
  final String testPackage;
  final String wpsRef;
  final String material;
  final String od;
  final String t;
  final String method;
  final String weldType;
  final String jointType;
  final String shopField;
  final String position;
  final String fillerClass;
  final String fillerBatch;

  /// Id of the last saved weld — what "Następna spoina" copies from.
  final String lastWeldId;

  const WeldEntryDefaults({
    this.pipeName = '',
    this.isoDrawing = '',
    this.isoRev = '',
    this.spool = '',
    this.testPackage = '',
    this.wpsRef = '',
    this.material = '',
    this.od = '',
    this.t = '',
    this.method = '',
    this.weldType = '',
    this.jointType = '',
    this.shopField = '',
    this.position = '',
    this.fillerClass = '',
    this.fillerBatch = '',
    this.lastWeldId = '',
  });

  factory WeldEntryDefaults.fromEntry(WeldEntry e) => WeldEntryDefaults(
        pipeName: e.pipeName,
        isoDrawing: e.isoDrawing,
        isoRev: e.isoRev,
        spool: e.spool,
        testPackage: e.testPackage,
        wpsRef: e.wpsRef,
        material: e.material,
        od: e.od,
        t: e.t,
        method: e.method,
        weldType: e.weldType,
        jointType: e.jointType,
        shopField: e.shopField,
        position: e.position,
        fillerClass: e.fillerClass,
        fillerBatch: e.fillerBatch,
        lastWeldId: e.id,
      );

  Map<String, String> toJson() => {
        'pipeName': pipeName,
        'isoDrawing': isoDrawing,
        'isoRev': isoRev,
        'spool': spool,
        'testPackage': testPackage,
        'wpsRef': wpsRef,
        'material': material,
        'od': od,
        't': t,
        'method': method,
        'weldType': weldType,
        'jointType': jointType,
        'shopField': shopField,
        'position': position,
        'fillerClass': fillerClass,
        'fillerBatch': fillerBatch,
        'lastWeldId': lastWeldId,
      };

  static WeldEntryDefaults fromJson(Map<Object?, Object?> j) {
    String s(String k) => j[k] is String ? j[k] as String : '';
    return WeldEntryDefaults(
      pipeName: s('pipeName'),
      isoDrawing: s('isoDrawing'),
      isoRev: s('isoRev'),
      spool: s('spool'),
      testPackage: s('testPackage'),
      wpsRef: s('wpsRef'),
      material: s('material'),
      od: s('od'),
      t: s('t'),
      method: s('method'),
      weldType: s('weldType'),
      jointType: s('jointType'),
      shopField: s('shopField'),
      position: s('position'),
      fillerClass: s('fillerClass'),
      fillerBatch: s('fillerBatch'),
      lastWeldId: s('lastWeldId'),
    );
  }
}

/// Reads the remembered values; empty defaults when there are none or the
/// stored JSON is damaged. Never throws.
Future<WeldEntryDefaults> loadWeldDefaults() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kWeldDefaultsPrefsKey);
    if (raw == null || raw.isEmpty) return const WeldEntryDefaults();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const WeldEntryDefaults();
    return WeldEntryDefaults.fromJson(decoded);
  } catch (e) {
    debugPrint('[weld_journal] read defaults failed: $e');
    return const WeldEntryDefaults();
  }
}

Future<void> saveWeldDefaults(WeldEntryDefaults d) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kWeldDefaultsPrefsKey, jsonEncode(d.toJson()));
  } catch (e) {
    debugPrint('[weld_journal] persist defaults failed: $e');
  }
}

/// A new, unsaved weld pre-filled from [d]. Nothing is invented: a value
/// that was never used is empty (in particular the material is never
/// "316L" by default). The project comes from [loadLastWeldProject].
WeldEntry newWeldFromDefaults(
  WeldEntryDefaults d, {
  required String id,
  required String weldNo,
  required String date,
  required String stamp,
  String projectName = '',
  String? projectId,
}) =>
    WeldEntry(
      id: id,
      weldNo: weldNo,
      projectName: projectName,
      projectId: projectId,
      pipeName: d.pipeName,
      isoDrawing: d.isoDrawing,
      isoRev: d.isoRev,
      spool: d.spool,
      testPackage: d.testPackage,
      wpsRef: d.wpsRef,
      material: d.material,
      od: d.od,
      t: d.t,
      method: d.method,
      weldType: d.weldType.isEmpty ? 'MANUAL' : d.weldType,
      jointType: d.jointType,
      shopField: d.shopField,
      position: d.position,
      fillerClass: d.fillerClass,
      fillerBatch: d.fillerBatch,
      welder: stamp,
      fitter: stamp,
      date: date,
      notes: '',
      status: WeldStatus.pending,
    );

/// "Następna spoina": the joint after [prev].
///
/// Copies what stays the same from joint to joint — project, line, drawing,
/// spool, test package, WPS, material, OD / wall, process, weld type, joint
/// type, shop/field, position and filler. Starts fresh everything that
/// belongs to THIS joint: number ([weldNo]), date, welder stamp, heat
/// numbers, measured preheat / interpass / heat input, coupon, NDT, PWHT,
/// acceptance, notes, status and repairs.
WeldEntry nextWeldFrom(
  WeldEntry prev, {
  required String id,
  required String weldNo,
  required String date,
  required String stamp,
}) =>
    WeldEntry(
      id: id,
      weldNo: weldNo,
      projectName: prev.projectName,
      projectId: prev.projectId,
      pipeName: prev.pipeName,
      isoDrawing: prev.isoDrawing,
      isoRev: prev.isoRev,
      spool: prev.spool,
      testPackage: prev.testPackage,
      wpsRef: prev.wpsRef,
      material: prev.material,
      od: prev.od,
      t: prev.t,
      method: prev.method,
      weldType: prev.weldType,
      jointType: prev.jointType,
      shopField: prev.shopField,
      position: prev.position,
      fillerClass: prev.fillerClass,
      fillerBatch: prev.fillerBatch,
      welder: stamp,
      // The fitter usually stays with the spool; fall back to the owner.
      fitter: prev.fitter.trim().isNotEmpty ? prev.fitter : stamp,
      date: date,
      notes: '',
      status: WeldStatus.pending,
    );
