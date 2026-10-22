import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/domain/weld_journal/weld_compliance.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';

/// Every table and column the shipping schema is expected to have once a
/// database has been migrated to [AppDatabase.schemaVersion].
///
/// Hand-written on purpose: if someone adds a column to `createSchema` and
/// forgets the matching migration step, the point is that this list disagrees
/// with the migrated database and the test fails. That is exactly how the
/// missing `component_library.diameter_out_mm` step was found — it was in
/// createSchema and in ComponentLibraryDao's REDUCER lookup, but no
/// `oldVersion <` block ever added it to an existing table.
const Map<String, List<String>> _expectedSchema = <String, List<String>>{
  'component_library': <String>[
    'id',
    'material_group',
    'type',
    'diameter_mm',
    'wall_thickness_mm',
    'axis_mm',
    'length_mm',
    'measurement_mode',
    'diameter_out_mm',
    'created_at',
    'updated_at',
  ],
  'projects': <String>[
    'id',
    'name',
    'material_group',
    'diameter_mm',
    'wall_thickness_mm',
    'current_diameter_mm',
    'stock_length_mm',
    'saw_kerf_mm',
    'gap_mm',
    'created_at',
    'updated_at',
    // v22: identyfikacja sztuk.
    'line_no',
    'iso_no',
    'iso_rev',
    'client',
    'spec',
  ],
  'segments': <String>[
    'id',
    'project_id',
    'seq_no',
    'diameter_mm',
    'wall_thickness_mm',
    'start_kind',
    'start_library_id',
    'start_value_mm',
    'end_kind',
    'end_library_id',
    'end_value_mm',
    'iso_ref',
    'iso_expr',
    'iso_mm',
    'cut_mm',
    'created_at',
    'updated_at',
    // v22: oznaczenie sztuki i spool.
    'label',
    'spool_id',
  ],
  'heat_photos': <String>[
    'id',
    'project_id',
    'library_component_id',
    'image_path',
    'note',
    'created_at',
    // v23: numer wytopu z etykiety.
    'heat_no',
  ],
  'component_heats': <String>[
    'id',
    'project_id',
    'component_key',
    'heat_no',
    'image_path',
    'note',
    'created_at',
    // v23: przypięcie do stabilnego id segmentu.
    'segment_id',
    'side',
  ],
  // v23: odhaczone ucięte kawałki listy cięć.
  'cut_marks': <String>[
    'project_id',
    'segment_id',
    'part',
    'cut_mm',
    'marked_at',
  ],
  'weld_params': <String>[
    'id',
    'owner_scope',
    'method',
    'base_material',
    'welder_model',
    'diameter_mm',
    'wall_thickness_mm',
    'electrode_mm',
    'torch_gas_lpm',
    'nozzle_type',
    'nozzle_size',
    'purge_lpm',
    'amps',
    'outlet_holes',
    'tempo',
    'note',
    'created_at',
    'updated_at',
  ],
  'approved_weld_params': <String>[
    'id',
    'method',
    'base_material',
    'diameter_mm',
    'wall_thickness_mm',
    'electrode_mm',
    'torch_gas_lpm',
    'purge_lpm',
    'amps',
    'note',
    'created_at',
    'updated_at',
  ],
  'tandem_tig_params': <String>[
    'id',
    'material_group',
    'position',
    'joint_type',
    'land_mm',
    'gap_mm',
    'wall_thickness_mm',
    'wall_thickness2_mm',
    'outside_amps',
    'inside_amps',
    'approved',
    'note',
    'created_at',
    'updated_at',
  ],
  // The three registers below used to be created lazily by their screens
  // (`CREATE TABLE IF NOT EXISTS` on first open), so a phone whose owner had
  // never opened the screen had no such table — and a restored backup
  // silently dropped every row of it. They are part of the schema now.
  'weld_journal': <String>[
    'id',
    'weld_no',
    'project_name',
    'pipe_name',
    'material',
    'od',
    't',
    'method',
    'welder',
    'date',
    'notes',
    'status',
    'weld_type',
    'fitter',
    'heat_no1',
    'heat_no2',
    'coupon_ref',
    'exam',
    'wps_ref',
    // v20: identification, welders, filler, actual parameters, PWHT,
    // acceptance, soft delete and NDT per method.
    'project_id',
    'iso_drawing',
    'iso_rev',
    'spool',
    'test_package',
    'joint_type',
    'shop_field',
    'position',
    'root_welder',
    'cap_welder',
    'filler_class',
    'filler_batch',
    'preheat_c',
    'interpass_c',
    'heat_input',
    'coupon_id',
    'pwht_required',
    'pwht_chart',
    'hardness',
    'inspector',
    'inspected_at',
    'deleted_at',
    'ndt_vt_scope',
    'ndt_vt_result',
    'ndt_vt_report',
    'ndt_vt_date',
    'ndt_pt_scope',
    'ndt_pt_result',
    'ndt_pt_report',
    'ndt_pt_date',
    'ndt_mt_scope',
    'ndt_mt_result',
    'ndt_mt_report',
    'ndt_mt_date',
    'ndt_rt_scope',
    'ndt_rt_result',
    'ndt_rt_report',
    'ndt_rt_date',
    'ndt_ut_scope',
    'ndt_ut_result',
    'ndt_ut_report',
    'ndt_ut_date',
    // v25: WPS picked from the library.
    'wps_id',
    // v28: prowadzenie grani, przenoszenie metalu, wyrób (ISO 9606-1).
    'root_backing',
    'metal_transfer',
    'product_form',
  ],
  // v20: who changed what on a weld, when, from what to what.
  'weld_journal_history': <String>[
    'id',
    'weld_id',
    'at',
    'by_stamp',
    'action',
    'field',
    'old_value',
    'new_value',
  ],
  // v20: repairs R1, R2, … with the state before each of them.
  'weld_repairs': <String>[
    'id',
    'weld_id',
    'seq',
    'date',
    'reason',
    'prev_status',
    'prev_ndt',
    'by_stamp',
    'created_at',
    // v25: acceptance / PWHT / hardness before the repair.
    'prev_acceptance',
  ],
  // v20: PDF header and RT/UT target per project.
  'weld_journal_projects': <String>[
    'project_key',
    'project_name',
    'company',
    'client',
    'project_title',
    'document_no',
    'revision',
    'rt_target_pct',
  ],
  'weld_coupons': <String>[
    'id',
    'date',
    'welder',
    'machine',
    'size',
    'result',
    'notes',
    // v20
    'program_no',
    'program_params',
    'o2_ppm',
    'heat_tint',
    // v25: soft delete, who accepted and when.
    'deleted_at',
    'accepted_by',
    'accepted_at',
  ],
  // v25: change history of the coupon log.
  'weld_coupon_history': <String>[
    'id',
    'coupon_id',
    'at',
    'by_stamp',
    'action',
    'field',
    'old_value',
    'new_value',
  ],
  'hydrotest_records': <String>[
    'id',
    'system_name',
    'test_date',
    'gauge',
    'pressure_start_bar',
    'pressure_end_bar',
    'temperature_c',
    'hold_minutes',
    'result',
    'witness',
    'od_mm',
    'wall_mm',
    'line_length_mm',
    'design_bar',
    'factor',
    'test_pressure_bar',
    'volume_l',
    'notes',
    'created_at',
    // v19: pressure-test protocol fields.
    'company',
    'project',
    'test_package',
    'drawing_refs',
    'test_medium',
    'test_preset',
    'stress_ratio',
    'metal_temp_c',
    'gauge_range',
    'gauge_cal_due',
    'relief_set_bar',
    'protocol_no',
    'protocol_rev',
  ],
  // ISO notebook autosave: the sketch used to live only in RAM.
  'iso_drawings': <String>[
    'id',
    'name',
    'json',
    'created_at',
    'updated_at',
  ],
  // v24: odczyt skanera izometryku — dotąd żył tylko w pamięci ekranu.
  'iso_scans': <String>[
    'id',
    'name',
    'image_path',
    'envelope_json',
    'created_at',
  ],
  // v21: rejestr uprawnień spawacza (ISO 9606-1 / ASME IX WPQ). Dotąd jeden
  // numer i jedna data w SharedPreferences, błędnie nazwane „WPQR".
  'welder_certificates': <String>[
    'id',
    'welder_stamp',
    'standard',
    'standard_label',
    'cert_no',
    'examiner',
    'test_date',
    'expiry_date',
    'last_confirmed_date',
    'prolongation',
    'processes',
    'material_group',
    'thickness_min_mm',
    'thickness_max_mm',
    'diameter_min_mm',
    'diameter_max_mm',
    'positions',
    'filler',
    'joint_kinds',
    'notes',
    'photo_path',
    'created_at',
    'updated_at',
  ],
  // v21: biblioteka WPS. Dotąd WPS istniała tylko jako wolny tekst w dzienniku
  // i dwa niezapisywane pola w kalkulatorze heat input.
  'wps_library': <String>[
    'id',
    'wps_no',
    'revision',
    'standard',
    'pqr_ref',
    'processes',
    'material_group',
    'thickness_min_mm',
    'thickness_max_mm',
    'diameter_min_mm',
    'diameter_max_mm',
    'positions',
    'joint_kinds',
    'filler',
    'shielding_gas',
    'backing_gas',
    'preheat_min_c',
    'interpass_max_c',
    'heat_input_min_kj_mm',
    'heat_input_max_kj_mm',
    'heat_input_method',
    'pwht',
    'notes',
    'attachment_path',
    'created_at',
    'updated_at',
    // v25: status dokumentu (pWPS / zatwierdzona / wycofana).
    'doc_status',
  ],
  // v25: historia potwierdzeń ISO 9606-1 §9.2 / wpisów ciągłości WPQ.
  'welder_cert_confirmations': <String>[
    'id',
    'certificate_id',
    'date',
    'confirmed_by',
    'notes',
    'created_at',
  ],
  // v25: wersje treści WPS z datą obowiązywania.
  'wps_versions': <String>[
    'id',
    'wps_id',
    'version_no',
    'valid_from',
    'snapshot',
    'by_stamp',
    'created_at',
  ],
  // v25: rejestr trawienia / pasywacji.
  'passivation_records': <String>[
    'id',
    'date',
    'treatment',
    'line',
    'test_package',
    'area',
    'agent',
    'agent_batch',
    'dwell_min',
    'temp_c',
    'rinse_us_cm',
    'test_method',
    'test_result',
    'by_stamp',
    'notes',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
  // v27: rejestr przyrządów i kalibracji.
  'instruments': <String>[
    'id',
    'kind',
    'name',
    'serial_no',
    'location',
    'last_calibration',
    'interval_months',
    'due_override',
    'certificate_no',
    'calibrated_by',
    'notes',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
  // v26: wyceny spawalnicze — nagłówek + treść w JSON, kwoty w groszach.
  'weld_quotes': <String>[
    'id',
    'number',
    'title',
    'client',
    'status',
    'data_json',
    'net_grosze',
    'gross_grosze',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
};

// ── Legacy schemas ────────────────────────────────────────────────────────
//
// Reconstructed by reading the migration ladder backwards: whatever a
// `oldVersion < N` block adds is by definition absent from version N - 1.

/// v1: the three original tables, before the v2/v3 column additions.
Future<void> _buildV1(Database db) async {
  await db.execute('''
CREATE TABLE component_library (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  axis_mm REAL,
  length_mm REAL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  name TEXT,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  current_diameter_mm REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE segments (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  seq_no INTEGER NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  start_kind TEXT NOT NULL,
  start_library_id TEXT,
  start_value_mm REAL NOT NULL,
  end_kind TEXT NOT NULL,
  end_library_id TEXT,
  end_value_mm REAL NOT NULL,
  iso_expr TEXT NOT NULL,
  iso_mm REAL NOT NULL,
  cut_mm REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (project_id, seq_no)
);
''');
}

/// v4: v1 plus the v2 and v3 columns, plus the heat_photos table.
Future<void> _buildV4(Database db) async {
  await _buildV1(db);
  await db.execute("ALTER TABLE projects ADD COLUMN material_group TEXT NOT NULL DEFAULT 'SS';");
  await db.execute('ALTER TABLE projects ADD COLUMN stock_length_mm REAL NOT NULL DEFAULT 6000;');
  await db.execute('ALTER TABLE projects ADD COLUMN saw_kerf_mm REAL NOT NULL DEFAULT 1;');
  await db.execute("ALTER TABLE component_library ADD COLUMN material_group TEXT NOT NULL DEFAULT 'SS';");
  await db.execute('ALTER TABLE component_library ADD COLUMN measurement_mode TEXT;');
  await db.execute("ALTER TABLE segments ADD COLUMN iso_ref TEXT NOT NULL DEFAULT 'FACE';");
  await db.execute('''
CREATE TABLE heat_photos (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  library_component_id TEXT,
  image_path TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL
);
''');
}

/// v10: v4 plus component_heats, weld_params (already carrying its v7/v10
/// columns) and tandem_tig_params in its original v8 shape — no
/// wall_thickness2_mm (v11) and no gap_mm (v15). approved_weld_params does not
/// exist yet (v13) and projects has no gap_mm yet (v12).
Future<void> _buildV10(Database db) async {
  await _buildV4(db);
  await db.execute('''
CREATE TABLE component_heats (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  component_key TEXT NOT NULL,
  heat_no TEXT NOT NULL,
  image_path TEXT,
  note TEXT,
  created_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE weld_params (
  id TEXT PRIMARY KEY,
  method TEXT NOT NULL,
  base_material TEXT NOT NULL,
  welder_model TEXT,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  electrode_mm REAL NOT NULL,
  torch_gas_lpm REAL NOT NULL,
  nozzle_type TEXT,
  nozzle_size TEXT,
  purge_lpm REAL NOT NULL,
  amps REAL NOT NULL,
  outlet_holes INTEGER,
  tempo TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE tandem_tig_params (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL,
  position TEXT NOT NULL,
  joint_type TEXT NOT NULL,
  land_mm REAL,
  wall_thickness_mm REAL NOT NULL,
  outside_amps REAL NOT NULL,
  inside_amps REAL NOT NULL,
  approved INTEGER NOT NULL DEFAULT 0,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
}

/// v16: the state a device is in after the v16 self-heal block ran — every
/// table present and every *projects* column repaired.
///
/// component_library is deliberately left without diameter_out_mm: the v16
/// block only ever healed `projects`, so this is what an upgraded device
/// actually looks like, and the 16 -> 17 step has to close the gap.
Future<void> _buildV16(Database db) async {
  await _buildV10(db);
  await db.execute('ALTER TABLE tandem_tig_params ADD COLUMN wall_thickness2_mm REAL;');
  await db.execute('ALTER TABLE tandem_tig_params ADD COLUMN gap_mm REAL;');
  await db.execute('ALTER TABLE projects ADD COLUMN gap_mm REAL NOT NULL DEFAULT 0;');
  await db.execute('''
CREATE TABLE approved_weld_params (
  id TEXT PRIMARY KEY,
  method TEXT NOT NULL,
  base_material TEXT NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  electrode_mm REAL NOT NULL,
  torch_gas_lpm REAL NOT NULL,
  purge_lpm REAL NOT NULL,
  amps REAL NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
}

/// v17 as it exists on a real phone: v16, the diameter_out_mm repair, and
/// the three registers exactly as their SCREENS used to create them on first
/// open — including the OLDEST weld_journal shape (12 columns, before the
/// ASME BPE weld-map columns and wps_ref were bolted on with ALTER TABLE).
///
/// The DDL is copied from the historical screen code on purpose, not from
/// db.dart: the point is that the migration has to cope with whatever the
/// old code left behind.
Future<void> _buildV17WithScreenTables(Database db) async {
  await _buildV16(db);
  await db.execute('ALTER TABLE component_library ADD COLUMN diameter_out_mm REAL;');
  // weld_journal_screen.dart, first release (e5c54d0).
  await db.execute('''
      CREATE TABLE IF NOT EXISTS weld_journal (
        id TEXT PRIMARY KEY,
        weld_no TEXT,
        project_name TEXT,
        pipe_name TEXT,
        material TEXT,
        od TEXT,
        t TEXT,
        method TEXT,
        welder TEXT,
        date TEXT,
        notes TEXT,
        status TEXT
      )
    ''');
  // coupon_log_screen.dart CouponDao._ensure().
  await db.execute('''
      CREATE TABLE IF NOT EXISTS weld_coupons (
        id TEXT PRIMARY KEY,
        date TEXT, welder TEXT, machine TEXT,
        size TEXT, result TEXT, notes TEXT
      )
    ''');
  // hydrotest_dao.dart HydrotestDao.ensureTable().
  await db.execute('''
      CREATE TABLE IF NOT EXISTS hydrotest_records (
        id TEXT PRIMARY KEY,
        system_name TEXT,
        test_date TEXT,
        gauge TEXT,
        pressure_start_bar REAL,
        pressure_end_bar REAL,
        temperature_c REAL,
        hold_minutes REAL,
        result TEXT,
        witness TEXT,
        od_mm REAL,
        wall_mm REAL,
        line_length_mm REAL,
        design_bar REAL,
        factor REAL,
        test_pressure_bar REAL,
        volume_l REAL,
        notes TEXT,
        created_at INTEGER
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hydrotest_created ON hydrotest_records(created_at DESC)',
  );
}

/// v19 as shipped: v17 plus the v18 steps (weld-map columns on the journal,
/// ISO notebook table) and the v19 pressure-test protocol columns. This is
/// the last schema before the weld journal got its history, NDT and repairs.
Future<void> _buildV19(Database db) async {
  await _buildV17WithScreenTables(db);
  for (final c in [
    'weld_type',
    'fitter',
    'heat_no1',
    'heat_no2',
    'coupon_ref',
    'exam',
    'wps_ref',
  ]) {
    await db.execute('ALTER TABLE weld_journal ADD COLUMN $c TEXT;');
  }
  await db.execute('''
CREATE TABLE iso_drawings (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  for (final c in <String, String>{
    'company': 'TEXT',
    'project': 'TEXT',
    'test_package': 'TEXT',
    'drawing_refs': 'TEXT',
    'test_medium': 'TEXT',
    'test_preset': 'TEXT',
    'stress_ratio': 'REAL',
    'metal_temp_c': 'REAL',
    'gauge_range': 'TEXT',
    'gauge_cal_due': 'TEXT',
    'relief_set_bar': 'REAL',
    'protocol_no': 'TEXT',
    'protocol_rev': 'TEXT',
  }.entries) {
    await db.execute(
        'ALTER TABLE hydrotest_records ADD COLUMN ${c.key} ${c.value};');
  }
}

/// v21 as shipped: v19 plus the v20 journal/coupon columns. The v20/v21
/// tables (history, repairs, journal projects, certificates, WPS) are left
/// to the self-heal at the top of the migration, exactly like on a device
/// that never opened those screens. `projects` and `segments` are still in
/// their pre-v22 shape — no line, ISO, client, class, label or spool.
Future<void> _buildV21(Database db) async {
  await _buildV19(db);
  for (final c in <String, String>{
    'project_id': 'TEXT',
    'iso_drawing': 'TEXT',
    'iso_rev': 'TEXT',
    'spool': 'TEXT',
    'test_package': 'TEXT',
    'joint_type': 'TEXT',
    'shop_field': 'TEXT',
    'position': 'TEXT',
    'root_welder': 'TEXT',
    'cap_welder': 'TEXT',
    'filler_class': 'TEXT',
    'filler_batch': 'TEXT',
    'preheat_c': 'TEXT',
    'interpass_c': 'TEXT',
    'heat_input': 'TEXT',
    'coupon_id': 'TEXT',
    'pwht_required': 'INTEGER',
    'pwht_chart': 'TEXT',
    'hardness': 'TEXT',
    'inspector': 'TEXT',
    'inspected_at': 'TEXT',
    'deleted_at': 'INTEGER',
    for (final m in const ['vt', 'pt', 'mt', 'rt', 'ut'])
      for (final f in const ['scope', 'result', 'report', 'date'])
        'ndt_${m}_$f': 'TEXT',
  }.entries) {
    await db.execute(
        'ALTER TABLE weld_journal ADD COLUMN ${c.key} ${c.value};');
  }
  for (final c in <String, String>{
    'program_no': 'TEXT',
    'program_params': 'TEXT',
    'o2_ppm': 'REAL',
    'heat_tint': 'INTEGER',
  }.entries) {
    await db.execute('ALTER TABLE weld_coupons ADD COLUMN ${c.key} ${c.value};');
  }
}

/// v22 as shipped: v21 plus the piece identification columns.
Future<void> _buildV22(Database db) async {
  await _buildV21(db);
  for (final c in AppDatabase.kProjectIdentityColumns.entries) {
    await db.execute('ALTER TABLE projects ADD COLUMN ${c.key} ${c.value};');
  }
  for (final c in AppDatabase.kSegmentIdentityColumns.entries) {
    await db.execute('ALTER TABLE segments ADD COLUMN ${c.key} ${c.value};');
  }
}

/// v22 on a device that had opened the journal and the qualification
/// register: the v20/v21 tables in their pre-v25 shape. Starting point of
/// the G5 quality-documentation step (v25).
Future<void> _buildV22WithRegisters(Database db) async {
  await _buildV22(db);
  await db.execute('''
CREATE TABLE welder_certificates (
  id TEXT PRIMARY KEY,
  welder_stamp TEXT,
  standard TEXT NOT NULL DEFAULT 'ISO_9606_1',
  standard_label TEXT,
  cert_no TEXT,
  examiner TEXT,
  test_date TEXT,
  expiry_date TEXT,
  last_confirmed_date TEXT,
  prolongation TEXT,
  processes TEXT,
  material_group TEXT,
  thickness_min_mm REAL,
  thickness_max_mm REAL,
  diameter_min_mm REAL,
  diameter_max_mm REAL,
  positions TEXT,
  filler TEXT,
  joint_kinds TEXT,
  notes TEXT,
  photo_path TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE wps_library (
  id TEXT PRIMARY KEY,
  wps_no TEXT NOT NULL,
  revision TEXT,
  standard TEXT,
  pqr_ref TEXT,
  processes TEXT,
  material_group TEXT,
  thickness_min_mm REAL,
  thickness_max_mm REAL,
  diameter_min_mm REAL,
  diameter_max_mm REAL,
  positions TEXT,
  joint_kinds TEXT,
  filler TEXT,
  shielding_gas TEXT,
  backing_gas TEXT,
  preheat_min_c REAL,
  interpass_max_c REAL,
  heat_input_min_kj_mm REAL,
  heat_input_max_kj_mm REAL,
  heat_input_method TEXT,
  pwht TEXT,
  notes TEXT,
  attachment_path TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  await db.execute('''
CREATE TABLE weld_repairs (
  id TEXT PRIMARY KEY,
  weld_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  date TEXT,
  reason TEXT,
  prev_status TEXT,
  prev_ndt TEXT,
  by_stamp TEXT,
  created_at INTEGER NOT NULL
);
''');
}

/// v27 as shipped: the whole current schema except the v28 journal columns.
///
/// weld_journal goes in FIRST, in its v27 shape (every column of the
/// expected schema but the v28 ones); [AppDatabase.createSchema] then adds
/// every other table and index and — CREATE TABLE IF NOT EXISTS — leaves
/// that journal alone. So the only difference to a fresh install is exactly
/// what the v28 step has to add.
Future<void> _buildV27(Database db) async {
  const integer = {'pwht_required', 'deleted_at'};
  final columns = _expectedSchema['weld_journal']!
      .where((c) => c != 'id')
      .where((c) => !AppDatabase.kWeldJournalV28Columns.containsKey(c))
      .map((c) => '  $c ${integer.contains(c) ? 'INTEGER' : 'TEXT'}')
      .join(',\n');
  await db.execute('CREATE TABLE weld_journal (\n  id TEXT PRIMARY KEY,\n'
      '$columns\n);');
  await AppDatabase.createSchema(db);
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fwp_migration_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Creates a database at [version] with [buildLegacy]'s schema, closes it,
  /// then reopens it at the shipping version so sqflite calls
  /// [AppDatabase.migrate] exactly the way it does on a user's device.
  Future<Database> migrateFrom(
    int version,
    Future<void> Function(Database db) buildLegacy, {
    Future<void> Function(Database db)? seedData,
  }) async {
    final path = '${tmp.path}/legacy_v$version.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          await buildLegacy(db);
          if (seedData != null) await seedData(db);
        },
      ),
    );
    await legacy.close();

    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onUpgrade: AppDatabase.migrate,
      ),
    );
  }

  Future<Set<String>> tablesOf(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table';",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  Future<Set<String>> columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table);');
    return rows.map((r) => r['name'] as String).toSet();
  }

  Future<void> expectShippingSchema(Database db, {required int from}) async {
    final tables = await tablesOf(db);
    for (final entry in _expectedSchema.entries) {
      expect(
        tables,
        contains(entry.key),
        reason: 'table ${entry.key} is missing after migrating from v$from',
      );
      final columns = await columnsOf(db, entry.key);
      for (final column in entry.value) {
        expect(
          columns,
          contains(column),
          reason: '${entry.key}.$column is missing after migrating from v$from',
        );
      }
    }
  }

  // ── Schema completeness from each historical starting point ─────────────

  test('v28 parameters survive v29 upgrade as guest without assignment to an account', () async {
    final db = await migrateFrom(28, (db) async {
      await _buildV27(db);
      for (final c in AppDatabase.kWeldJournalV28Columns.entries) {
        await db.execute('ALTER TABLE weld_journal ADD COLUMN "${c.key}" ${c.value}');
      }
    }, seedData: (db) async {
      await db.insert('weld_params', {
        'id': 'legacy-ownerless', 'method': 'MAG', 'base_material': 'CS',
        'diameter_mm': 60.3, 'wall_thickness_mm': 2.0, 'electrode_mm': 1.6,
        'torch_gas_lpm': 8.0, 'purge_lpm': 4.0, 'amps': 100.0,
        'created_at': 1, 'updated_at': 2,
      });
    });
    addTearDown(db.close);
    final row = (await db.query('weld_params')).single;
    expect(row['id'], 'legacy-ownerless');
    expect(row['amps'], 100.0);
    expect(row['owner_scope'], 'guest');
    final column = (await db.rawQuery('PRAGMA table_info(weld_params)'))
        .singleWhere((c) => c['name'] == 'owner_scope');
    expect(column['notnull'], 1);
    expect(column['dflt_value'], "'guest'");
  });

  for (final start in <int, Future<void> Function(Database)>{
    1: _buildV1,
    4: _buildV4,
    10: _buildV10,
    16: _buildV16,
    17: _buildV17WithScreenTables,
    19: _buildV19,
    21: _buildV21,
    22: _buildV22,
    27: _buildV27,
  }.entries) {
    test('v${start.key} -> current: every table and column is present', () async {
      final db = await migrateFrom(start.key, start.value);
      addTearDown(db.close);

      await expectShippingSchema(db, from: start.key);
      expect(await db.getVersion(), AppDatabase.schemaVersion);
    });
  }

  test('a migrated database has the same shape as a freshly created one', () async {
    // Guards the drift that the version ladder cannot catch on its own: a
    // column added to createSchema without a matching migration step reaches
    // new installs but never reaches upgrades.
    final freshPath = '${tmp.path}/fresh.db';
    final fresh = await databaseFactoryFfi.openDatabase(
      freshPath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    addTearDown(fresh.close);

    for (final start in <int, Future<void> Function(Database)>{
      1: _buildV1,
      4: _buildV4,
      10: _buildV10,
      16: _buildV16,
      17: _buildV17WithScreenTables,
      19: _buildV19,
      21: _buildV21,
      22: _buildV22,
      27: _buildV27,
    }.entries) {
      final migrated = await migrateFrom(start.key, start.value);
      addTearDown(migrated.close);

      for (final table in _expectedSchema.keys) {
        expect(
          await columnsOf(migrated, table),
          await columnsOf(fresh, table),
          reason: 'v${start.key} -> current left $table a different shape '
              'than a fresh install gets',
        );
      }
    }
  });

  // ── The missing-table case ─────────────────────────────────────────────

  test('PRAGMA table_info on an unknown table returns rows, not an error', () async {
    // The premise behind the _ensureColumn bug below: SQLite answers an empty
    // result set instead of failing, so "no rows" cannot be read as "the
    // column is missing" — it may mean the table is missing.
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/pragma.db',
      options: OpenDatabaseOptions(version: 1),
    );
    addTearDown(db.close);

    expect(await db.rawQuery('PRAGMA table_info(no_such_table);'), isEmpty);
  });

  test('a database missing a table still migrates instead of bricking', () async {
    // A v2 install whose `segments` table never made it. The v3 step calls
    // _ensureColumn(db, 'segments', 'iso_ref', ...); before the fix, PRAGMA
    // returned nothing, the code concluded the column was missing, and
    // ALTER TABLE segments threw "no such table: segments" — which aborted
    // onUpgrade, which made openDatabase throw, which meant the app could not
    // start at all and no later version could ever repair it.
    Future<void> buildV2WithoutSegments(Database db) async {
      await db.execute('''
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  name TEXT,
  material_group TEXT NOT NULL DEFAULT 'SS',
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  current_diameter_mm REAL NOT NULL,
  stock_length_mm REAL NOT NULL DEFAULT 6000,
  saw_kerf_mm REAL NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
      await db.execute('''
CREATE TABLE component_library (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL DEFAULT 'SS',
  type TEXT NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  axis_mm REAL,
  length_mm REAL,
  measurement_mode TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    }

    final db = await migrateFrom(2, buildV2WithoutSegments);
    addTearDown(db.close);

    await expectShippingSchema(db, from: 2);
    expect(await columnsOf(db, 'segments'), contains('iso_ref'));
  });

  test('a database missing every table migrates from an empty file', () async {
    // The worst version of the same shape: the stored version number says 12,
    // the file holds nothing. Every _ensureColumn and every seed INSERT in the
    // ladder used to throw here.
    final db = await migrateFrom(12, (_) async {});
    addTearDown(db.close);

    await expectShippingSchema(db, from: 12);
  });

  // ── Data survival, not just column presence ────────────────────────────

  test('v1 rows survive the migration and get the new column defaults', () async {
    final db = await migrateFrom(
      1,
      _buildV1,
      seedData: (legacy) async {
        await legacy.insert('projects', <String, Object?>{
          'id': 'p1',
          'name': 'Rack 12',
          'diameter_mm': 60.3,
          'wall_thickness_mm': 2.0,
          'current_diameter_mm': 60.3,
          'created_at': 1000,
          'updated_at': 1000,
        });
        await legacy.insert('segments', <String, Object?>{
          'id': 's1',
          'project_id': 'p1',
          'seq_no': 1,
          'diameter_mm': 60.3,
          'wall_thickness_mm': 2.0,
          'start_kind': 'ELBOW',
          'start_library_id': null,
          'start_value_mm': 38.0,
          'end_kind': 'FACE',
          'end_library_id': null,
          'end_value_mm': 0.0,
          'iso_expr': '1200',
          'iso_mm': 1200.0,
          'cut_mm': 1162.0,
          'created_at': 1000,
          'updated_at': 1000,
        });
      },
    );
    addTearDown(db.close);

    final project = (await db.query('projects', where: 'id = ?', whereArgs: ['p1'])).single;
    expect(project['name'], 'Rack 12');
    // Lengths are millimetres throughout.
    expect((project['diameter_mm']! as num).toDouble(), 60.3);
    expect(project['material_group'], 'SS');
    // Read through num: the ALTER TABLE defaults are integer literals on REAL
    // columns, so whether they come back as int or double is SQLite's business,
    // not something this test should pin down.
    expect((project['stock_length_mm']! as num).toDouble(), 6000.0);
    expect((project['saw_kerf_mm']! as num).toDouble(), 1.0);
    expect((project['gap_mm']! as num).toDouble(), 0.0);

    final segment = (await db.query('segments', where: 'id = ?', whereArgs: ['s1'])).single;
    expect((segment['cut_mm']! as num).toDouble(), 1162.0);
    expect(segment['iso_ref'], 'FACE');
  });

  test('rows the old screens wrote survive the move into the schema', () async {
    // A welder with a year of journal entries, a coupon log and a pressure
    // test register upgrades. Their tables were created by the screens, the
    // journal one in its oldest 12-column shape. Nothing may be lost, and
    // the journal must gain the weld-map columns so the screen can save.
    final db = await migrateFrom(
      17,
      _buildV17WithScreenTables,
      seedData: (legacy) async {
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w-legacy',
          'weld_no': 'W-017',
          'project_name': 'Blok 4',
          'pipe_name': 'L-12',
          'material': '316L',
          'od': '60,3',
          't': '2',
          'method': 'TIG',
          'welder': 'JK-12',
          'date': '2026-03-02',
          'notes': 'przetop OK',
          'status': 'OK',
        });
        await legacy.insert('weld_coupons', <String, Object?>{
          'id': 'c-legacy',
          'date': '2026-03-02',
          'welder': 'JK-12',
          'machine': 'Orbitalna M-3',
          'size': '2"x1.65',
          'result': 'OK',
          'notes': 'boroskop poz. 2',
        });
        await legacy.insert('hydrotest_records', <String, Object?>{
          'id': 'h-legacy',
          'system_name': 'WFI-101',
          'test_date': '2026-03-05',
          'pressure_start_bar': 15.0,
          'pressure_end_bar': 14.9,
          'hold_minutes': 30.0,
          'result': 'PASS',
          'line_length_mm': 120000.0,
          'created_at': 1000,
        });
      },
    );
    addTearDown(db.close);

    final weld = (await db.query('weld_journal')).single;
    expect(weld['weld_no'], 'W-017');
    expect(weld['notes'], 'przetop OK');
    expect(weld['wps_ref'], isNull);
    // The screen writes every weld-map column; they have to be there now.
    await db.update(
      'weld_journal',
      <String, Object?>{'wps_ref': 'WPS-01', 'weld_type': 'ORBITAL'},
      where: 'id = ?',
      whereArgs: <Object?>['w-legacy'],
    );
    expect((await db.query('weld_journal')).single['wps_ref'], 'WPS-01');

    final coupon = (await db.query('weld_coupons')).single;
    expect(coupon['machine'], 'Orbitalna M-3');

    final hydro = (await db.query('hydrotest_records')).single;
    expect(hydro['system_name'], 'WFI-101');
    // Millimetres in, millimetres out.
    expect((hydro['line_length_mm']! as num).toDouble(), 120000.0);
    // v19 protocol fields arrive empty on an old test — never invented.
    expect(hydro['test_preset'], isNull);
    expect(hydro['relief_set_bar'], isNull);

    expect(await db.query('iso_drawings'), isEmpty);
  });

  test('v19 -> v20: every journal and coupon row survives, new fields empty',
      () async {
    // A welder with journal rows written by the v19 app (weld-map columns
    // filled, including DUPLICATE weld numbers, which older builds allowed)
    // and coupons upgrades to the journal with history, NDT and repairs.
    // Nothing may be lost or rewritten; the new columns arrive NULL —
    // never an invented NDT result, never a "deleted" flag.
    final db = await migrateFrom(
      19,
      _buildV19,
      seedData: (legacy) async {
        for (final (id, no, status) in [
          ('w1', 'W-010', 'OK'),
          ('w2', 'W-9', 'NOK'),
          ('w3', 'W-9', 'PENDING'),
        ]) {
          await legacy.insert('weld_journal', <String, Object?>{
            'id': id,
            'weld_no': no,
            'project_name': 'Blok 4',
            'pipe_name': 'L-12',
            'material': '316L',
            'od': '60,3',
            't': '2',
            'method': 'TIG',
            'welder': 'JK-12',
            'date': '2026-09-01',
            'notes': 'grań OK; lico do szlifowania',
            'status': status,
            'weld_type': 'ORBITAL',
            'fitter': 'MN-03',
            'heat_no1': 'H-1',
            'heat_no2': 'H-2',
            'coupon_ref': 'C-2026-09-01-A',
            'exam': 'VT OK',
            'wps_ref': 'WPS-141-01',
          });
        }
        await legacy.insert('weld_coupons', <String, Object?>{
          'id': 'c1',
          'date': '2026-09-01',
          'welder': 'JK-12',
          'machine': 'M-3',
          'size': '2"x1.65',
          'result': 'OK',
          'notes': 'boroskop poz. 2',
        });
      },
    );
    addTearDown(db.close);

    final welds = await db.query('weld_journal', orderBy: 'id');
    expect(welds.map((w) => w['id']), ['w1', 'w2', 'w3']);
    expect(welds.map((w) => w['weld_no']), ['W-010', 'W-9', 'W-9']);
    expect(welds.map((w) => w['status']), ['OK', 'NOK', 'PENDING']);
    for (final w in welds) {
      expect(w['notes'], 'grań OK; lico do szlifowania');
      expect(w['wps_ref'], 'WPS-141-01');
      expect(w['coupon_ref'], 'C-2026-09-01-A');
      expect(w['deleted_at'], isNull, reason: 'no row may arrive deleted');
      expect(w['project_id'], isNull);
      expect(w['ndt_rt_result'], isNull);
      expect(w['pwht_required'], isNull);
    }

    final coupon = (await db.query('weld_coupons')).single;
    expect(coupon['notes'], 'boroskop poz. 2');
    expect(coupon['o2_ppm'], isNull);
    expect(coupon['heat_tint'], isNull);

    expect(await db.query('weld_journal_history'), isEmpty);
    expect(await db.query('weld_repairs'), isEmpty);
    expect(await db.query('weld_journal_projects'), isEmpty);

    // The new columns are writable.
    await db.update(
      'weld_journal',
      <String, Object?>{'ndt_rt_result': 'OK', 'deleted_at': 5},
      where: 'id = ?',
      whereArgs: <Object?>['w1'],
    );
    final w1 = (await db.query('weld_journal', where: "id = 'w1'")).single;
    expect(w1['ndt_rt_result'], 'OK');
  });

  test('v19 -> v21: rejestry uprawnień i WPS dochodzą puste, dziennik zostaje',
      () async {
    final db = await migrateFrom(
      19,
      _buildV19,
      seedData: (legacy) async {
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w-19',
          'weld_no': 'W-101',
          'method': 'TIG',
          'welder': 'JK-014',
          'date': '2026-09-01',
          'wps_ref': 'WPS-141-01',
        });
      },
    );
    addTearDown(db.close);

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(21));
    final weld = (await db.query('weld_journal')).single;
    expect(weld['wps_ref'], 'WPS-141-01');
    expect(await db.query('welder_certificates'), isEmpty);
    expect(await db.query('wps_library'), isEmpty);

    // Tabele przyjmują pełny wiersz — to, co zapisuje DAO.
    await db.insert('welder_certificates', <String, Object?>{
      'id': 'c1',
      'standard': 'ISO_9606_1',
      'cert_no': 'PL-001',
      'expiry_date': '2028-06-09',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('wps_library', <String, Object?>{
      'id': 'wps1',
      'wps_no': 'WPS-141-01',
      'heat_input_max_kj_mm': 1.2,
      'created_at': 1,
      'updated_at': 1,
    });
    expect((await db.query('welder_certificates')).single['cert_no'], 'PL-001');
    expect(
      ((await db.query('wps_library')).single['heat_input_max_kj_mm']! as num)
          .toDouble(),
      1.2,
    );
  });

  test('v21 -> v22: projekty i segmenty zostają, identyfikacja dochodzi pusta',
      () async {
    // Monter z projektami i pociętymi segmentami aktualizuje aplikację. Nic
    // nie może zniknąć ani się zmienić; nowe kolumny przychodzą NULL — nigdy
    // wymyślony numer linii czy oznaczenie sztuki.
    final db = await migrateFrom(
      21,
      _buildV21,
      seedData: (legacy) async {
        await legacy.insert('projects', <String, Object?>{
          'id': 'p21',
          'name': 'Rack 12',
          'material_group': 'CS',
          'diameter_mm': 114.3,
          'wall_thickness_mm': 6.02,
          'current_diameter_mm': 88.9,
          'stock_length_mm': 12000.0,
          'saw_kerf_mm': 3.0,
          'gap_mm': 2.5,
          'created_at': 1000,
          'updated_at': 2000,
        });
        for (final (id, seq, cut) in [('s1', 1, 1162.0), ('s2', 2, 845.5)]) {
          await legacy.insert('segments', <String, Object?>{
            'id': id,
            'project_id': 'p21',
            'seq_no': seq,
            'diameter_mm': 114.3,
            'wall_thickness_mm': 6.02,
            'start_kind': 'axial',
            'start_library_id': null,
            'start_value_mm': 152.0,
            'end_kind': 'logical',
            'end_library_id': null,
            'end_value_mm': 0.0,
            'iso_ref': 'AXIS|OPEN',
            'iso_expr': '1000+200',
            'iso_mm': 1200.0,
            'cut_mm': cut,
            'created_at': 1000,
            'updated_at': 1000,
          });
        }
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w21',
          'weld_no': 'W-001',
          'iso_drawing': 'ISO-7',
          'spool': 'SP01',
        });
      },
    );
    addTearDown(db.close);

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(22));

    final project = (await db.query('projects')).single;
    expect(project['name'], 'Rack 12');
    expect(project['material_group'], 'CS');
    expect((project['current_diameter_mm']! as num).toDouble(), 88.9);
    expect((project['stock_length_mm']! as num).toDouble(), 12000.0);
    expect((project['gap_mm']! as num).toDouble(), 2.5);
    expect(project['updated_at'], 2000);
    for (final c in ['line_no', 'iso_no', 'iso_rev', 'client', 'spec']) {
      expect(project.containsKey(c), isTrue, reason: 'projects.$c missing');
      expect(project[c], isNull, reason: 'projects.$c must arrive empty');
    }

    final segments = await db.query('segments', orderBy: 'seq_no');
    expect(segments.map((s) => s['id']), ['s1', 's2']);
    expect(segments.map((s) => (s['cut_mm']! as num).toDouble()),
        [1162.0, 845.5]);
    for (final s in segments) {
      expect(s['iso_expr'], '1000+200');
      expect(s['iso_ref'], 'AXIS|OPEN');
      expect(s['label'], isNull);
      expect(s['spool_id'], isNull);
    }

    expect((await db.query('weld_journal')).single['spool'], 'SP01');

    // Nowe kolumny przyjmują to, co zapisuje DAO.
    await db.update(
      'projects',
      <String, Object?>{'line_no': 'L-100', 'iso_no': 'ISO-7', 'iso_rev': 'B'},
      where: "id = 'p21'",
    );
    await db.update(
      'segments',
      <String, Object?>{'label': 'SP02-03', 'spool_id': 'SP02'},
      where: "id = 's1'",
    );
    expect((await db.query('projects')).single['iso_rev'], 'B');
    expect(
        (await db.query('segments', where: "id = 's1'")).single['label'],
        'SP02-03');
  });

  test('v22 -> v24: odczyt skanu dostaje własną tabelę, reszta bez zmian',
      () async {
    final db = await migrateFrom(
      22,
      _buildV22,
      seedData: (legacy) async {
        await legacy.insert('projects', <String, Object?>{
          'id': 'p22',
          'name': 'Rack 22',
          'material_group': 'SS',
          'diameter_mm': 60.3,
          'wall_thickness_mm': 2.77,
          'current_diameter_mm': 60.3,
          'stock_length_mm': 6000.0,
          'saw_kerf_mm': 1.5,
          'gap_mm': 0.0,
          'created_at': 1000,
          'updated_at': 1000,
          'line_no': 'L-22',
        });
      },
    );
    addTearDown(db.close);

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(24));
    await expectShippingSchema(db, from: 22);
    expect((await db.query('projects')).single['line_no'], 'L-22');
    expect(await db.query('iso_scans'), isEmpty);

    await db.insert('iso_scans', <String, Object?>{
      'id': 'scan-1',
      'name': 'DN100-P-1001',
      'image_path': '/docs/heat_photos/a.jpg',
      'envelope_json': '{"result":{}}',
      'created_at': 5000,
    });
    expect((await db.query('iso_scans')).single['envelope_json'],
        '{"result":{}}');
  });

  test('v22 -> v23: numery wytopów przepięte z seq_no na id segmentu, nic nie '
      'ginie', () async {
    // Monter wpisał heat do kolana na końcu S001, do startu S001 i do
    // S003_END — a segment 3 został potem usunięty. Po aktualizacji dwa
    // pierwsze wpisy wskazują id swoich segmentów; trzeci zostaje (bez
    // miejsca), bo zgadywanie przypisałoby wytop innej kształtce.
    final db = await migrateFrom(
      22,
      _buildV22,
      seedData: (legacy) async {
        await legacy.insert('projects', <String, Object?>{
          'id': 'p22',
          'name': 'Rack 3',
          'diameter_mm': 114.3,
          'wall_thickness_mm': 3.05,
          'current_diameter_mm': 114.3,
          'created_at': 1,
          'updated_at': 1,
        });
        for (final (id, seq) in [('seg-a', 1), ('seg-b', 2)]) {
          await legacy.insert('segments', <String, Object?>{
            'id': id,
            'project_id': 'p22',
            'seq_no': seq,
            'diameter_mm': 114.3,
            'wall_thickness_mm': 3.05,
            'start_kind': 'axial',
            'start_value_mm': 152.4,
            'end_kind': 'axial',
            'end_value_mm': 152.4,
            'iso_ref': 'AXIS|AXIS',
            'iso_expr': '1000',
            'iso_mm': 1000.0,
            'cut_mm': 695.2,
            'created_at': 1,
            'updated_at': 1,
          });
        }
        for (final (id, key, heat) in [
          ('h1', 'S001_END', 'H-111'),
          ('h2', 'S001_START', 'H-000'),
          ('h3', 'S003_END', 'H-333'),
        ]) {
          await legacy.insert('component_heats', <String, Object?>{
            'id': id,
            'project_id': 'p22',
            'component_key': key,
            'heat_no': heat,
            'image_path': null,
            'note': 'n-$id',
            'created_at': 5,
          });
        }
        await legacy.insert('heat_photos', <String, Object?>{
          'id': 'ph1',
          'project_id': 'p22',
          'library_component_id': null,
          'image_path': '/x/heat_photos/a.jpg',
          'note': 'H-777 na etykiecie',
          'created_at': 6,
        });
      },
    );
    addTearDown(db.close);

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    final heats = {
      for (final r in await db.query('component_heats')) r['id']: r,
    };
    expect(heats.keys, unorderedEquals(['h1', 'h2', 'h3']),
        reason: 'żaden wpis nie może zniknąć');
    expect(heats['h1']!['segment_id'], 'seg-a');
    expect(heats['h1']!['side'], 'END');
    expect(heats['h2']!['segment_id'], 'seg-a');
    expect(heats['h2']!['side'], 'START');
    expect(heats['h3']!['segment_id'], isNull,
        reason: 'segmentu 3 nie ma — nie wolno go zgadywać');
    expect(heats['h3']!['heat_no'], 'H-333');
    expect(heats['h1']!['heat_no'], 'H-111');
    expect(heats['h1']!['note'], 'n-h1');

    final photo = (await db.query('heat_photos')).single;
    expect(photo['note'], 'H-777 na etykiecie');
    expect(photo['heat_no'], isNull, reason: 'numeru nie wymyślamy z notatki');

    expect(await db.query('cut_marks'), isEmpty);
    await db.insert('cut_marks', <String, Object?>{
      'project_id': 'p22',
      'segment_id': 'seg-a',
      'part': 1,
      'cut_mm': 695.2,
      'marked_at': 9,
    });
    expect(await db.query('cut_marks'), hasLength(1));

    // Drugi przebieg migracji niczego nie przestawia.
    await AppDatabase.migrate(db, 22, AppDatabase.schemaVersion);
    expect(
        (await db.query('component_heats', where: "id = 'h1'"))
            .single['segment_id'],
        'seg-a');
  });

  test(
      'v22 -> v25: potwierdzenie przechodzi do historii, WPS dostaje wersję 1, '
      'kupony / naprawy / spoiny zostają bez zmian', () async {
    final db = await migrateFrom(
      22,
      _buildV22WithRegisters,
      seedData: (legacy) async {
        await legacy.insert('welder_certificates', <String, Object?>{
          'id': 'cert-1',
          'standard': 'ISO_9606_1',
          'cert_no': 'PL-001',
          'test_date': '2025-01-10',
          'last_confirmed_date': '2025-07-05',
          'created_at': 1,
          'updated_at': 7,
        });
        await legacy.insert('welder_certificates', <String, Object?>{
          'id': 'cert-2',
          'standard': 'ASME_IX',
          'cert_no': 'WPQ-9',
          'created_at': 1,
          'updated_at': 1,
        });
        await legacy.insert('wps_library', <String, Object?>{
          'id': 'wps-1',
          'wps_no': 'WPS-141-01',
          'revision': 'B',
          'positions': 'PA, PC, PF',
          'heat_input_max_kj_mm': 1.2,
          'created_at': 1,
          'updated_at': 5,
        });
        await legacy.insert('weld_coupons', <String, Object?>{
          'id': 'c1',
          'date': '2026-09-01',
          'welder': 'JK-12',
          'result': 'NOK',
          'o2_ppm': 12.5,
        });
        await legacy.insert('weld_repairs', <String, Object?>{
          'id': 'r1',
          'weld_id': 'w1',
          'seq': 1,
          'date': '2026-09-02',
          'reason': 'porowatość',
          'prev_status': 'NOK',
          'prev_ndt': '{"RT":{"result":"NOK"}}',
          'created_at': 9,
        });
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w1',
          'weld_no': 'W-1',
          'wps_ref': 'WPS-141-01 rev. B',
          'status': 'PENDING',
        });
      },
    );
    addTearDown(db.close);
    expect(await db.getVersion(), AppDatabase.schemaVersion);

    // Certyfikaty bez zmian; ostatnie potwierdzenie = pierwszy wpis historii.
    final certs = await db.query('welder_certificates', orderBy: 'id');
    expect(certs.map((c) => c['last_confirmed_date']), ['2025-07-05', null]);
    final conf = await db.query('welder_cert_confirmations');
    expect(conf, hasLength(1));
    expect(conf.single['certificate_id'], 'cert-1');
    expect(conf.single['date'], '2025-07-05');

    // WPS: wiersz bez zmian, wersja 1 obowiązuje od zawsze.
    final wps = (await db.query('wps_library')).single;
    expect(wps['positions'], 'PA, PC, PF');
    expect(wps['doc_status'], isNull);
    final versions = await db.query('wps_versions');
    expect(versions, hasLength(1));
    expect(versions.single['wps_id'], 'wps-1');
    expect(versions.single['version_no'], 1);
    expect(versions.single['valid_from'], 0);
    expect(versions.single['snapshot'] as String, contains('PA, PC, PF'));

    // Kupon: wynik NOK zostaje, nowe pola puste — nikt go nie „usunął".
    final coupon = (await db.query('weld_coupons')).single;
    expect(coupon['result'], 'NOK');
    expect((coupon['o2_ppm']! as num).toDouble(), 12.5);
    expect(coupon['deleted_at'], isNull);
    expect(coupon['accepted_by'], isNull);

    final repair = (await db.query('weld_repairs')).single;
    expect(repair['prev_ndt'], '{"RT":{"result":"NOK"}}');
    expect(repair['prev_acceptance'], isNull);

    final weld = (await db.query('weld_journal')).single;
    expect(weld['wps_ref'], 'WPS-141-01 rev. B');
    expect(weld['wps_id'], isNull);

    expect(await db.query('weld_coupon_history'), isEmpty);
    expect(await db.query('passivation_records'), isEmpty);

    // Ponowne przejście kroku v25 nie dubluje wpisów.
    await AppDatabase.migrateV25(db);
    expect(await db.query('welder_cert_confirmations'), hasLength(1));
    expect(await db.query('wps_versions'), hasLength(1));
  });

  test(
      'v27 -> v28: każda spoina zostaje, grań / przenoszenie / wyrób '
      'dochodzą puste (NULL)', () async {
    final db = await migrateFrom(
      27,
      _buildV27,
      seedData: (legacy) async {
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w1',
          'weld_no': 'W-27',
          'project_name': 'Blok 4',
          'od': '60,3',
          't': '3,9',
          'method': 'MIG/MAG',
          'welder': 'JK-12',
          'date': '2026-10-01',
          'status': 'OK',
          'joint_type': 'BW',
          'wps_ref': 'WPS-135-01',
          'wps_id': 'wps-1',
          'ndt_rt_result': 'OK',
          'pwht_required': 0,
        });
        await legacy.insert('weld_journal', <String, Object?>{
          'id': 'w2',
          'weld_no': 'W-28',
          'deleted_at': 5,
        });
      },
    );
    addTearDown(db.close);
    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(28));

    final rows = await db.query('weld_journal', orderBy: 'id');
    expect(rows.map((r) => r['id']), ['w1', 'w2'], reason: 'nic nie ginie');
    final w1 = rows.first;
    expect(w1['weld_no'], 'W-27');
    expect(w1['wps_id'], 'wps-1');
    expect(w1['ndt_rt_result'], 'OK');
    expect(w1['pwht_required'], 0);
    expect(rows.last['deleted_at'], 5);
    for (final r in rows) {
      for (final c in AppDatabase.kWeldJournalV28Columns.keys) {
        expect(r.containsKey(c), isTrue, reason: '$c po migracji');
        expect(r[c], isNull, reason: 'stara spoina nie podaje $c');
      }
    }

    // „Nie podano” = brak danych: kontrola nie dostaje grani ani
    // przenoszenia; wyrób jak przed v28 — rura z OD.
    final entry = WeldEntry.fromRow(w1);
    expect(entry.rootBacking, isEmpty);
    expect(entry.metalTransfer, isEmpty);
    expect(entry.productForm, isEmpty);
    final p = weldParametersOf(entry);
    expect(p.root, isNull);
    expect(p.dipTransfer, isNull);
    expect(p.productForm?.code, 'T');

    // Ponowne przejście kroku nic nie psuje.
    await AppDatabase.migrate(db, 27, AppDatabase.schemaVersion);
    expect(await db.query('weld_journal'), hasLength(2));
  });

  test('świeża instalacja v28: dziennik ma kolumny grani, przenoszenia '
      'i wyrobu, zapis i odczyt przez WeldEntry', () async {
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/fresh_v28.db',
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    addTearDown(db.close);
    expect(await columnsOf(db, 'weld_journal'),
        containsAll(AppDatabase.kWeldJournalV28Columns.keys));

    const e = WeldEntry(
      id: 'w1',
      weldNo: 'W-1',
      projectName: 'P',
      pipeName: 'L',
      material: '',
      od: '',
      t: '10',
      method: 'MIG/MAG',
      welder: 'JK-12',
      date: '2026-10-17',
      notes: '',
      status: WeldStatus.pending,
      rootBacking: WeldRootBacking.nb,
      metalTransfer: WeldMetalTransfer.dip,
      productForm: WeldProductKind.plate,
    );
    await db.insert('weld_journal', e.toRow());
    final row = (await db.query('weld_journal')).single;
    expect(row['root_backing'], 'nb');
    expect(row['metal_transfer'], 'dip');
    expect(row['product_form'], 'P');
    expect(WeldEntry.fromRow(row).toRow(), e.toRow());
  });

  test('the approved seed data lands on every upgrade path', () async {
    // _seedApprovedData is the other statement in the ladder that touches a
    // table by name, so a missing tandem_tig_params or approved_weld_params
    // used to abort the migration here rather than in _ensureColumn.
    for (final start in <int, Future<void> Function(Database)>{
      1: _buildV1,
      10: _buildV10,
      16: _buildV16,
    }.entries) {
      final db = await migrateFrom(start.key, start.value);
      addTearDown(db.close);

      final tandem = await db.query(
        'tandem_tig_params',
        where: 'id = ?',
        whereArgs: ['APPROVED_TANDEM_H_BUTT_3_3'],
      );
      expect(
        (tandem.single['outside_amps']! as num).toDouble(),
        140.0,
        reason: 'seed missing after migrating from v${start.key}',
      );

      final amp = await db.query(
        'approved_weld_params',
        where: 'id = ?',
        whereArgs: ['APPROVED_PIPE_TIGWIRE_60_2'],
      );
      expect(
        (amp.single['amps']! as num).toDouble(),
        60.0,
        reason: 'seed missing after migrating from v${start.key}',
      );
    }
  });

  test('migrate is idempotent when it runs twice over the same file', () async {
    // Devices do re-run upgrades: an install that is rolled back and rolled
    // forward again replays the ladder. Every step has to survive that.
    final db = await migrateFrom(1, _buildV1);
    addTearDown(db.close);

    await AppDatabase.migrate(db, 1, AppDatabase.schemaVersion);
    await expectShippingSchema(db, from: 1);

    // Seeding twice must not duplicate the approved rows the welder reads off.
    final seeded = await db.query(
      'tandem_tig_params',
      where: 'id = ?',
      whereArgs: ['APPROVED_TANDEM_H_BUTT_3_3'],
    );
    expect(seeded, hasLength(1));
  });
}
