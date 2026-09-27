/// One joint in the weld journal (weld map / weld log).
///
/// The field set follows what ISO 3834-2 §14–15 (identification and
/// traceability), ASME B31.3 §341/§344 (examination records) and
/// EN 13480-5 (weld identification, NDT, PWHT) expect a weld log to answer:
/// which joint (drawing, revision, line, spool, number), what kind of joint
/// and where it was made, who welded the root and the cap, with what
/// procedure and filler, at what preheat / interpass / heat input, how it was
/// examined, whether it was repaired or heat treated, and who accepted it.
///
/// Immutable: the history log compares the entry before and after an edit
/// ([diffWeldEntries] in `weld_history.dart`), and a mutable model is how a
/// "before" silently becomes the "after".
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'weld_ndt.dart';
import 'weld_repair.dart';

/// Joint type codes (ISO 2553 / B31.3 wording): butt weld, socket weld,
/// branch connection, fillet weld.
abstract final class WeldJointType {
  static const String butt = 'BW';
  static const String socket = 'SW';
  static const String branch = 'BR';
  static const String fillet = 'FW';
  static const List<String> values = [butt, socket, branch, fillet];
}

/// Shop (prefabrication) vs field (site) weld.
abstract final class WeldLocation {
  static const String shop = 'SHOP';
  static const String field = 'FIELD';
  static const List<String> values = [shop, field];
}

/// Welding positions, ASME IX (1G–6G) and ISO 6947 (PA–PH, H-L045, J-L045).
const List<String> kWeldPositions = [
  '1G', '2G', '5G', '6G',
  '1F', '2F', '4F', '5F',
  'PA', 'PB', 'PC', 'PD', 'PE', 'PF', 'PG', 'PH',
  'H-L045', 'J-L045',
];

/// Statuses the journal writes. Older databases may hold other strings;
/// they are shown and exported as they are, never rewritten.
abstract final class WeldStatus {
  static const String ok = 'OK';
  static const String nok = 'NOK';
  static const String pending = 'PENDING';
  static const List<String> values = [ok, nok, pending];
}

class WeldEntry {
  final String id;
  final String weldNo;

  /// Project as typed or picked. Stays the grouping key of the journal —
  /// every existing row has it, few will ever get [projectId].
  final String projectName;

  /// `projects.id` when the project was picked from the app's project list;
  /// null for a name typed by hand. Added in schema v20 next to
  /// [projectName], which is never removed.
  final String? projectId;

  /// Line designation ("Rura / linia" in the editor since the first release).
  final String pipeName;

  /// Isometric / drawing number and its revision.
  final String isoDrawing;
  final String isoRev;

  final String spool;

  /// Test package (pressure-test pack) the joint belongs to.
  final String testPackage;

  /// [WeldJointType] code or empty.
  final String jointType;

  /// [WeldLocation] code or empty.
  final String shopField;

  /// One of [kWeldPositions] or empty.
  final String position;

  final String material;
  final String od;
  final String t;

  /// Welding process: TIG / MIG/MAG / MMA / Tandem, or empty.
  final String method;

  /// Welder stamp responsible for the joint.
  final String welder;

  /// Stamps of the root and the cap welder when they differ from [welder].
  final String rootWelder;
  final String capWelder;

  /// `YYYY-MM-DD`.
  final String date;
  final String notes;

  /// [WeldStatus] value (legacy databases may hold others).
  final String status;

  /// ORBITAL / AUTO / MANUAL.
  final String weldType;
  final String fitter;
  final String heatNo1;
  final String heatNo2;

  /// Filler metal classification (e.g. ER316LSi, E7018-1) and batch / lot.
  final String fillerClass;
  final String fillerBatch;

  /// Actual values, as typed: °C, °C and kJ/mm.
  final String preheatC;
  final String interpassC;
  final String heatInput;

  /// Test coupon reference as text. Free text in every row written before
  /// v20; [couponId] links a coupon from the coupon log.
  final String couponRef;
  final String? couponId;

  /// Free-text examination remark (the pre-v20 "Wynik badania" field).
  final String exam;
  final String wpsRef;

  /// `wps_library.id` of the WPS picked from the library (v25); null for a
  /// number typed by hand — then [wpsRef] is matched to the library by text.
  final String? wpsId;

  /// PWHT required: null = not stated, true / false.
  final bool? pwhtRequired;
  final String pwhtChart;
  final String hardness;

  /// Inspector acceptance: who and when (`YYYY-MM-DD`).
  final String inspector;
  final String inspectedAt;

  /// Per-method NDT state; methods without data are absent.
  final Map<NdtMethod, WeldNdt> ndt;

  /// Epoch ms of the soft delete, or null for a live entry. Deleting a weld
  /// never removes the row: the journal is evidence, and a deleted joint has
  /// to stay visible in its history and restorable.
  final int? deletedAt;

  /// Repairs R1, R2, … in order. Loaded from `weld_repairs` by the DAO; NOT
  /// a column of `weld_journal`, so it is not part of [toRow].
  final List<WeldRepair> repairs;

  const WeldEntry({
    required this.id,
    required this.weldNo,
    required this.projectName,
    required this.pipeName,
    required this.material,
    required this.od,
    required this.t,
    required this.method,
    required this.welder,
    required this.date,
    required this.notes,
    required this.status,
    this.weldType = 'MANUAL',
    this.fitter = '',
    this.heatNo1 = '',
    this.heatNo2 = '',
    this.couponRef = '',
    this.exam = '',
    this.wpsRef = '',
    this.wpsId,
    this.projectId,
    this.isoDrawing = '',
    this.isoRev = '',
    this.spool = '',
    this.testPackage = '',
    this.jointType = '',
    this.shopField = '',
    this.position = '',
    this.rootWelder = '',
    this.capWelder = '',
    this.fillerClass = '',
    this.fillerBatch = '',
    this.preheatC = '',
    this.interpassC = '',
    this.heatInput = '',
    this.couponId,
    this.pwhtRequired,
    this.pwhtChart = '',
    this.hardness = '',
    this.inspector = '',
    this.inspectedAt = '',
    this.ndt = const {},
    this.deletedAt,
    this.repairs = const [],
  });

  bool get isDeleted => deletedAt != null;

  WeldNdt ndtOf(NdtMethod m) => ndt[m] ?? const WeldNdt();

  /// Distinct stamps that welded this joint (welder, root, cap), trimmed and
  /// de-duplicated case-insensitively, first-seen casing kept.
  List<String> get stamps {
    final seen = <String>{};
    final out = <String>[];
    for (final s in [welder, rootWelder, capWelder]) {
      final t = s.trim();
      if (t.isEmpty || !seen.add(t.toUpperCase())) continue;
      out.add(t);
    }
    return out;
  }

  /// Any NDT method has a recorded result.
  bool get isExamined => ndt.values.any((n) => n.hasResult);

  /// RT or UT has a recorded result.
  bool get isVolumetricExamined => ndt.entries
      .any((e) => e.key.isVolumetric && e.value.hasResult);

  Map<String, Object?> toRow() => {
        'id': id,
        'weld_no': weldNo,
        'project_name': projectName,
        'pipe_name': pipeName,
        'material': material,
        'od': od,
        't': t,
        'method': method,
        'welder': welder,
        'date': date,
        'notes': notes,
        'status': status,
        'weld_type': weldType,
        'fitter': fitter,
        'heat_no1': heatNo1,
        'heat_no2': heatNo2,
        'coupon_ref': couponRef,
        'exam': exam,
        'wps_ref': wpsRef,
        // ---- v20
        'project_id': projectId,
        'iso_drawing': isoDrawing,
        'iso_rev': isoRev,
        'spool': spool,
        'test_package': testPackage,
        'joint_type': jointType,
        'shop_field': shopField,
        'position': position,
        'root_welder': rootWelder,
        'cap_welder': capWelder,
        'filler_class': fillerClass,
        'filler_batch': fillerBatch,
        'preheat_c': preheatC,
        'interpass_c': interpassC,
        'heat_input': heatInput,
        'coupon_id': couponId,
        'pwht_required': pwhtRequired == null ? null : (pwhtRequired! ? 1 : 0),
        'pwht_chart': pwhtChart,
        'hardness': hardness,
        'inspector': inspector,
        'inspected_at': inspectedAt,
        'deleted_at': deletedAt,
        ...ndtToRow(ndt),
        // ---- v25
        'wps_id': wpsId,
      };

  static String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');

  static WeldEntry fromRow(Map<String, Object?> r) {
    final pwht = r['pwht_required'];
    return WeldEntry(
      id: r['id'] as String,
      weldNo: _s(r['weld_no']),
      projectName: _s(r['project_name']),
      pipeName: _s(r['pipe_name']),
      material: _s(r['material']),
      od: _s(r['od']),
      t: _s(r['t']),
      // Legacy rows were written with a TIG default; keep reading them so.
      method: (r['method'] as String?) ?? 'TIG',
      welder: _s(r['welder']),
      date: _s(r['date']),
      notes: _s(r['notes']),
      status: (r['status'] as String?) ?? WeldStatus.pending,
      weldType: (r['weld_type'] as String?) ?? 'MANUAL',
      fitter: _s(r['fitter']),
      heatNo1: _s(r['heat_no1']),
      heatNo2: _s(r['heat_no2']),
      couponRef: _s(r['coupon_ref']),
      exam: _s(r['exam']),
      wpsRef: _s(r['wps_ref']),
      wpsId: r['wps_id'] as String?,
      projectId: r['project_id'] as String?,
      isoDrawing: _s(r['iso_drawing']),
      isoRev: _s(r['iso_rev']),
      spool: _s(r['spool']),
      testPackage: _s(r['test_package']),
      jointType: _s(r['joint_type']),
      shopField: _s(r['shop_field']),
      position: _s(r['position']),
      rootWelder: _s(r['root_welder']),
      capWelder: _s(r['cap_welder']),
      fillerClass: _s(r['filler_class']),
      fillerBatch: _s(r['filler_batch']),
      preheatC: _s(r['preheat_c']),
      interpassC: _s(r['interpass_c']),
      heatInput: _s(r['heat_input']),
      couponId: r['coupon_id'] as String?,
      pwhtRequired: pwht is num ? pwht != 0 : null,
      pwhtChart: _s(r['pwht_chart']),
      hardness: _s(r['hardness']),
      inspector: _s(r['inspector']),
      inspectedAt: _s(r['inspected_at']),
      deletedAt: (r['deleted_at'] as num?)?.toInt(),
      ndt: ndtFromRow(r),
    );
  }

  /// Every field an inspector can see, as the strings the history log
  /// compares and stores. Keys are the column names, in column order.
  ///
  /// Left out on purpose: `id`; `project_id`, `coupon_id` and `wps_id`
  /// (internal links —
  /// the visible project / coupon text is logged instead); `deleted_at`
  /// (deleting and restoring are their own history actions).
  Map<String, String> auditFields() {
    final row = toRow();
    return {
      for (final key in weldAuditFieldKeys) key: _s(row[key]),
    };
  }

  static const Object _keep = Object();

  WeldEntry copyWith({
    String? id,
    String? weldNo,
    String? projectName,
    Object? projectId = _keep,
    String? pipeName,
    String? isoDrawing,
    String? isoRev,
    String? spool,
    String? testPackage,
    String? jointType,
    String? shopField,
    String? position,
    String? material,
    String? od,
    String? t,
    String? method,
    String? welder,
    String? rootWelder,
    String? capWelder,
    String? date,
    String? notes,
    String? status,
    String? weldType,
    String? fitter,
    String? heatNo1,
    String? heatNo2,
    String? fillerClass,
    String? fillerBatch,
    String? preheatC,
    String? interpassC,
    String? heatInput,
    String? couponRef,
    Object? couponId = _keep,
    String? exam,
    String? wpsRef,
    Object? wpsId = _keep,
    Object? pwhtRequired = _keep,
    String? pwhtChart,
    String? hardness,
    String? inspector,
    String? inspectedAt,
    Map<NdtMethod, WeldNdt>? ndt,
    Object? deletedAt = _keep,
    List<WeldRepair>? repairs,
  }) =>
      WeldEntry(
        id: id ?? this.id,
        weldNo: weldNo ?? this.weldNo,
        projectName: projectName ?? this.projectName,
        projectId: identical(projectId, _keep)
            ? this.projectId
            : projectId as String?,
        pipeName: pipeName ?? this.pipeName,
        isoDrawing: isoDrawing ?? this.isoDrawing,
        isoRev: isoRev ?? this.isoRev,
        spool: spool ?? this.spool,
        testPackage: testPackage ?? this.testPackage,
        jointType: jointType ?? this.jointType,
        shopField: shopField ?? this.shopField,
        position: position ?? this.position,
        material: material ?? this.material,
        od: od ?? this.od,
        t: t ?? this.t,
        method: method ?? this.method,
        welder: welder ?? this.welder,
        rootWelder: rootWelder ?? this.rootWelder,
        capWelder: capWelder ?? this.capWelder,
        date: date ?? this.date,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        weldType: weldType ?? this.weldType,
        fitter: fitter ?? this.fitter,
        heatNo1: heatNo1 ?? this.heatNo1,
        heatNo2: heatNo2 ?? this.heatNo2,
        fillerClass: fillerClass ?? this.fillerClass,
        fillerBatch: fillerBatch ?? this.fillerBatch,
        preheatC: preheatC ?? this.preheatC,
        interpassC: interpassC ?? this.interpassC,
        heatInput: heatInput ?? this.heatInput,
        couponRef: couponRef ?? this.couponRef,
        couponId:
            identical(couponId, _keep) ? this.couponId : couponId as String?,
        exam: exam ?? this.exam,
        wpsRef: wpsRef ?? this.wpsRef,
        wpsId: identical(wpsId, _keep) ? this.wpsId : wpsId as String?,
        pwhtRequired: identical(pwhtRequired, _keep)
            ? this.pwhtRequired
            : pwhtRequired as bool?,
        pwhtChart: pwhtChart ?? this.pwhtChart,
        hardness: hardness ?? this.hardness,
        inspector: inspector ?? this.inspector,
        inspectedAt: inspectedAt ?? this.inspectedAt,
        ndt: ndt ?? this.ndt,
        deletedAt:
            identical(deletedAt, _keep) ? this.deletedAt : deletedAt as int?,
        repairs: repairs ?? this.repairs,
      );
}

/// Keys of [WeldEntry.auditFields], i.e. every field the history log tracks,
/// in the order they are shown.
final List<String> weldAuditFieldKeys = List.unmodifiable([
  'weld_no',
  'project_name',
  'pipe_name',
  'iso_drawing',
  'iso_rev',
  'spool',
  'test_package',
  'joint_type',
  'shop_field',
  'position',
  'material',
  'od',
  't',
  'heat_no1',
  'heat_no2',
  'method',
  'weld_type',
  'wps_ref',
  'filler_class',
  'filler_batch',
  'welder',
  'root_welder',
  'cap_welder',
  'fitter',
  'date',
  'preheat_c',
  'interpass_c',
  'heat_input',
  'coupon_ref',
  'status',
  'exam',
  ...kWeldNdtColumns,
  'pwht_required',
  'pwht_chart',
  'hardness',
  'inspector',
  'inspected_at',
  'notes',
]);
