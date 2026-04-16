import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database.
///
/// NOTE: Keep schema and DAO/models in sync.
class AppDatabase {
  static Database? _db;

  // Bump this whenever you change schema.
  // v16: schema self-heal for users who installed earlier builds with version
  // already bumped but missing some columns (e.g. projects.gap_mm).
  static const int _dbVersion = 17;

  static Future<Database> get() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'cutlist.db');

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await _createSchema(db);
        await _seedApprovedData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // ---- Projects
        if (oldVersion < 2) {
          await _ensureColumn(db, 'projects', 'material_group', "TEXT NOT NULL DEFAULT 'SS'");
          await _ensureColumn(db, 'projects', 'stock_length_mm', 'REAL NOT NULL DEFAULT 6000');
          await _ensureColumn(db, 'projects', 'saw_kerf_mm', 'REAL NOT NULL DEFAULT 1');

          await _ensureColumn(db, 'component_library', 'material_group', "TEXT NOT NULL DEFAULT 'SS'");
          await _ensureColumn(db, 'component_library', 'measurement_mode', 'TEXT');
        }

        // ---- Segments
        if (oldVersion < 3) {
          await _ensureColumn(db, 'segments', 'iso_ref', "TEXT NOT NULL DEFAULT 'FACE'");
        }

        // ---- Photos / heats
        if (oldVersion < 4) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS heat_photos (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  library_component_id TEXT,
  image_path TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_heat_project ON heat_photos(project_id);');
        }
        if (oldVersion < 5) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS component_heats (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  component_key TEXT NOT NULL,
  heat_no TEXT NOT NULL,
  image_path TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_component_heats_project ON component_heats(project_id);');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_component_heats_key ON component_heats(project_id, component_key);');
        }

        // ---- Welder pipes: user weld params
        if (oldVersion < 6) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS weld_params (
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
          await db.execute('CREATE INDEX IF NOT EXISTS idx_weld_params_main ON weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
        }
        if (oldVersion < 7) {
          await _ensureColumn(db, 'weld_params', 'welder_model', 'TEXT');
        }
        // Add newer weld_params columns for very old DBs.
        if (oldVersion < 10) {
          await _ensureColumn(db, 'weld_params', 'nozzle_type', 'TEXT');
          await _ensureColumn(db, 'weld_params', 'nozzle_size', 'TEXT');
          await _ensureColumn(db, 'weld_params', 'outlet_holes', 'INTEGER');
          await _ensureColumn(db, 'weld_params', 'tempo', 'TEXT');
        }

        // ---- Welder tanks: tandem TIG approved params
        if (oldVersion < 8) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS tandem_tig_params (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL,
  position TEXT NOT NULL,            -- HORIZONTAL / VERTICAL
  joint_type TEXT NOT NULL,          -- BUTT / GAP / BEVEL
  land_mm REAL,                      -- only for BEVEL
  wall_thickness_mm REAL NOT NULL,
  wall_thickness2_mm REAL,
  outside_amps REAL NOT NULL,
  inside_amps REAL NOT NULL,
  approved INTEGER NOT NULL DEFAULT 0,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_tandem_tig_main ON tandem_tig_params(material_group, position, joint_type, land_mm, wall_thickness_mm);');
        }
        if (oldVersion < 11) {
          await _ensureColumn(db, 'tandem_tig_params', 'wall_thickness2_mm', 'REAL');
        }

        // ---- Welder tanks: optional gap for GAP and BEVEL (e.g. faza + szczelina)
        if (oldVersion < 15) {
          await _ensureColumn(db, 'tandem_tig_params', 'gap_mm', 'REAL');
        }

        // ---- Projects: optional welding gap
        if (oldVersion < 12) {
          await _ensureColumn(db, 'projects', 'gap_mm', 'REAL NOT NULL DEFAULT 0');
        }

        // ---- Approved AMP table (Welder pipes)
        if (oldVersion < 13) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS approved_weld_params (
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
          await db.execute('CREATE INDEX IF NOT EXISTS idx_approved_weld_params_main ON approved_weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
        }

        // ---- Seed / patch approved data
        if (oldVersion < 15) {
          await _seedApprovedData(db);
        }

        // ---- v16: schema self-heal (idempotent)
        if (oldVersion < 16) {
          // Ensure core tables exist (safe if already created).
          await db.execute('''
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT,
  material_group TEXT NOT NULL DEFAULT 'SS',
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  current_diameter_mm REAL NOT NULL,
  stock_length_mm REAL NOT NULL DEFAULT 6000,
  saw_kerf_mm REAL NOT NULL DEFAULT 1,
  gap_mm REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

          // Ensure critical columns exist even if version was previously bumped.
          await _ensureColumn(db, 'projects', 'material_group', "TEXT NOT NULL DEFAULT 'SS'");
          await _ensureColumn(db, 'projects', 'stock_length_mm', 'REAL NOT NULL DEFAULT 6000');
          await _ensureColumn(db, 'projects', 'saw_kerf_mm', 'REAL NOT NULL DEFAULT 1');
          await _ensureColumn(db, 'projects', 'gap_mm', 'REAL NOT NULL DEFAULT 0');
        }

        if (oldVersion < 17) {
          await _seedApprovedData(db);
        }
      },
    );

    await _seedApprovedData(_db!);
    return _db!;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS component_library (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL DEFAULT 'SS',
  type TEXT NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  axis_mm REAL,
  length_mm REAL,
  measurement_mode TEXT,
  diameter_out_mm REAL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (material_group, type, diameter_mm, wall_thickness_mm, diameter_out_mm)
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_library_d_w ON component_library(material_group, diameter_mm, wall_thickness_mm);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT,
  material_group TEXT NOT NULL DEFAULT 'SS',
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  current_diameter_mm REAL NOT NULL,
  stock_length_mm REAL NOT NULL DEFAULT 6000,
  saw_kerf_mm REAL NOT NULL DEFAULT 1,
  gap_mm REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS segments (
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
  iso_ref TEXT NOT NULL DEFAULT 'FACE',
  iso_expr TEXT NOT NULL,
  iso_mm REAL NOT NULL,
  cut_mm REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (project_id, seq_no),
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segments_project ON segments(project_id);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS heat_photos (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  library_component_id TEXT,
  image_path TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_heat_project ON heat_photos(project_id);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS component_heats (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  component_key TEXT NOT NULL,
  heat_no TEXT NOT NULL,
  image_path TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_component_heats_project ON component_heats(project_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_component_heats_key ON component_heats(project_id, component_key);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_params (
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_weld_params_main ON weld_params(base_material, diameter_mm, wall_thickness_mm, method);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS approved_weld_params (
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_approved_weld_params_main ON approved_weld_params(base_material, diameter_mm, wall_thickness_mm, method);');

    await db.execute('''
CREATE TABLE IF NOT EXISTS tandem_tig_params (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL,
  position TEXT NOT NULL,
  joint_type TEXT NOT NULL,
  land_mm REAL,
  gap_mm REAL,
  wall_thickness_mm REAL NOT NULL,
  wall_thickness2_mm REAL,
  outside_amps REAL NOT NULL,
  inside_amps REAL NOT NULL,
  approved INTEGER NOT NULL DEFAULT 0,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tandem_tig_main ON tandem_tig_params(material_group, position, joint_type, land_mm, wall_thickness_mm);');
  }

  static Future<void> _seedApprovedData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // ---- Tandem TIG (tanks)
    // Insert only if not exists (by id).
    Future<void> upsertTandem(Map<String, Object?> row) async {
      final id = row['id'] as String;
      final existing = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tandem_tig_params WHERE id = ?', [id])) ?? 0;
      if (existing > 0) return;
      await db.insert('tandem_tig_params', row);
    }

    // ---- Approved points provided by user (tanks / tandem TIG)
    // POZIOM | na styk: 3/3 => 140/72
    await upsertTandem({
      'id': 'APPROVED_TANDEM_H_BUTT_3_3',
      'material_group': 'SS',
      'position': 'HORIZONTAL',
      'joint_type': 'BUTT',
      'land_mm': null,
      'gap_mm': null,
      'wall_thickness_mm': 3.0,
      'wall_thickness2_mm': 3.0,
      'outside_amps': 140.0,
      'inside_amps': 72.0,
      'approved': 1,
      'note': 'Zatwierdzone: poziom na styk 3/3 → 140/72 A.',
      'created_at': now,
      'updated_at': now,
    });

    // POZIOM | na styk: 4/4 => 190/100
    await upsertTandem({
      'id': 'APPROVED_TANDEM_H_BUTT_4_4',
      'material_group': 'SS',
      'position': 'HORIZONTAL',
      'joint_type': 'BUTT',
      'land_mm': null,
      'gap_mm': null,
      'wall_thickness_mm': 4.0,
      'wall_thickness2_mm': 4.0,
      'outside_amps': 190.0,
      'inside_amps': 100.0,
      'approved': 1,
      'note': 'Zatwierdzone: poziom na styk 4/4 → 190/100 A.',
      'created_at': now,
      'updated_at': now,
    });

    // ---- Approved AMP for welder pipes
    // These presets are common starting points gathered from field experience and
    // welding forums. They provide approximate amperage values for various
    // diameter/thickness combinations and are used by the automatic AMP
    // calculator in the welder pipes screen. Each preset is upserted by id to
    // ensure idempotency.
    Future<void> upsertApproved(Map<String, Object?> row) async {
      final id = row['id'] as String;
      final existing = Sqflite.firstIntValue(
              await db.rawQuery(
                  'SELECT COUNT(*) FROM approved_weld_params WHERE id = ?',
                  [id])) ??
          0;
      if (existing > 0) return;
      await db.insert('approved_weld_params', row);
    }

    // Define a helper to create row map.
    Map<String, Object?> preset({
      required String id,
      required String method,
      required String material,
      required double d,
      required double t,
      required double amps,
      double electrode = 1.6,
      double torchGas = 8.0,
      double purge = 6.0,
      String? note,
    }) {
      return {
        'id': id,
        'method': method,
        'base_material': material,
        'diameter_mm': d,
        'wall_thickness_mm': t,
        'electrode_mm': electrode,
        'torch_gas_lpm': torchGas,
        'purge_lpm': purge,
        'amps': amps,
        'note': note ?? '',
        'created_at': now,
        'updated_at': now,
      };
    }

    final List<Map<String, Object?>> approvedList = [
      // Stainless steel (autogen) – thin wall
      preset(id: 'APP_SS_AUTO_10_1_0', method: 'TIG_AUTOGEN', material: 'SS', d: 10.0, t: 1.0, amps: 30.0),
      preset(id: 'APP_SS_AUTO_10_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 10.0, t: 1.5, amps: 35.0),
      preset(id: 'APP_SS_AUTO_12_1_0', method: 'TIG_AUTOGEN', material: 'SS', d: 12.0, t: 1.0, amps: 32.0),
      preset(id: 'APP_SS_AUTO_12_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 12.0, t: 1.5, amps: 35.0),
      preset(id: 'APP_SS_AUTO_14_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 14.0, t: 1.5, amps: 37.0),
      preset(id: 'APP_SS_AUTO_16_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 16.0, t: 1.5, amps: 38.0),
      preset(id: 'APP_SS_AUTO_18_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 18.0, t: 1.5, amps: 40.0),
      preset(id: 'APP_SS_AUTO_20_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 20.0, t: 1.5, amps: 43.0),
      preset(id: 'APP_SS_AUTO_25_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 25.0, t: 1.5, amps: 48.0),
      preset(id: 'APP_SS_AUTO_25_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 25.0, t: 2.0, amps: 60.0, electrode: 2.4),
      // Stainless mid sizes
      preset(id: 'APP_SS_AUTO_32_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 32.0, t: 1.5, amps: 55.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_32_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 32.0, t: 2.0, amps: 65.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_38_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 38.0, t: 1.5, amps: 60.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_38_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 38.0, t: 2.0, amps: 70.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_40_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 40.0, t: 1.5, amps: 60.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_40_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 40.0, t: 2.0, amps: 70.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_50_1_5', method: 'TIG_AUTOGEN', material: 'SS', d: 50.0, t: 1.5, amps: 65.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_50_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 50.0, t: 2.0, amps: 75.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_60_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 60.0, t: 2.0, amps: 80.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_60_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 60.0, t: 3.0, amps: 90.0, electrode: 2.4),
      // Stainless large sizes
      preset(id: 'APP_SS_AUTO_76_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 76.0, t: 2.0, amps: 85.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_76_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 76.0, t: 3.0, amps: 100.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_88_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 88.0, t: 2.0, amps: 90.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_88_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 88.0, t: 3.0, amps: 105.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_100_2_0', method: 'TIG_AUTOGEN', material: 'SS', d: 100.0, t: 2.0, amps: 100.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_100_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 100.0, t: 3.0, amps: 120.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_114_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 114.0, t: 3.0, amps: 130.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_114_4_0', method: 'TIG_AUTOGEN', material: 'SS', d: 114.0, t: 4.0, amps: 150.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_139_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 139.0, t: 3.0, amps: 140.0, electrode: 2.4),
      preset(id: 'APP_SS_AUTO_139_4_0', method: 'TIG_AUTOGEN', material: 'SS', d: 139.0, t: 4.0, amps: 160.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_168_3_0', method: 'TIG_AUTOGEN', material: 'SS', d: 168.0, t: 3.0, amps: 150.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_168_4_0', method: 'TIG_AUTOGEN', material: 'SS', d: 168.0, t: 4.0, amps: 165.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_168_5_0', method: 'TIG_AUTOGEN', material: 'SS', d: 168.0, t: 5.0, amps: 190.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_219_4_0', method: 'TIG_AUTOGEN', material: 'SS', d: 219.0, t: 4.0, amps: 180.0, electrode: 3.2),
      preset(id: 'APP_SS_AUTO_219_5_0', method: 'TIG_AUTOGEN', material: 'SS', d: 219.0, t: 5.0, amps: 200.0, electrode: 3.2),
      // Carbon steel (wire) – typical sets
      preset(id: 'APP_CS_WIRE_60_3_0', method: 'TIG_WIRE', material: 'CS', d: 60.0, t: 3.0, amps: 120.0, electrode: 2.4),
      preset(id: 'APP_CS_WIRE_76_3_0', method: 'TIG_WIRE', material: 'CS', d: 76.0, t: 3.0, amps: 130.0, electrode: 2.4),
      preset(id: 'APP_CS_WIRE_88_4_0', method: 'TIG_WIRE', material: 'CS', d: 88.0, t: 4.0, amps: 150.0, electrode: 3.2),
      preset(id: 'APP_CS_WIRE_114_4_0', method: 'TIG_WIRE', material: 'CS', d: 114.0, t: 4.0, amps: 160.0, electrode: 3.2),
      preset(id: 'APP_CS_WIRE_168_5_0', method: 'TIG_WIRE', material: 'CS', d: 168.0, t: 5.0, amps: 200.0, electrode: 3.2),
    ];

    // Expanded approved presets grouped by material so the app can filter by
    // welded material and avoid mixing amperage recommendations.
    final ssAutogen = <Map<String, double>>[
      {'d': 6, 't': 1.0, 'a': 20, 'e': 1.0}, {'d': 8, 't': 1.0, 'a': 24, 'e': 1.0},
      {'d': 12, 't': 1.65, 'a': 34, 'e': 1.6}, {'d': 22, 't': 1.5, 'a': 45, 'e': 1.6},
      {'d': 28, 't': 2.0, 'a': 63, 'e': 2.4}, {'d': 35, 't': 2.0, 'a': 68, 'e': 2.4},
      {'d': 45, 't': 2.0, 'a': 73, 'e': 2.4}, {'d': 50, 't': 3.0, 'a': 90, 'e': 2.4},
      {'d': 63, 't': 2.0, 'a': 82, 'e': 2.4}, {'d': 63, 't': 3.0, 'a': 92, 'e': 2.4},
      {'d': 70, 't': 2.0, 'a': 85, 'e': 2.4}, {'d': 70, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 80, 't': 3.0, 'a': 102, 'e': 2.4}, {'d': 159, 't': 3.0, 'a': 145, 'e': 3.2},
      {'d': 159, 't': 4.0, 'a': 165, 'e': 3.2}, {'d': 273, 't': 5.0, 'a': 210, 'e': 4.0},
      {'d': 273, 't': 6.0, 'a': 230, 'e': 4.0}, {'d': 323, 't': 6.0, 'a': 240, 'e': 4.0},
    ];
    for (final r in ssAutogen) {
      approvedList.add(preset(
        id: 'APP_SS_AUTO_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_AUTOGEN', material: 'SS', d: r['d']!, t: r['t']!,
        amps: r['a']!, electrode: r['e']!, torchGas: r['d']! <= 25 ? 7 : 8.0,
        purge: r['d']! <= 50 ? 10 : 15,
      ));
    }

    final ssWire = <Map<String, double>>[
      {'d': 20, 't': 2.0, 'a': 75, 'e': 2.4}, {'d': 25, 't': 2.0, 'a': 80, 'e': 2.4},
      {'d': 32, 't': 2.0, 'a': 85, 'e': 2.4}, {'d': 32, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 38, 't': 2.0, 'a': 90, 'e': 2.4}, {'d': 38, 't': 3.0, 'a': 102, 'e': 2.4},
      {'d': 40, 't': 2.0, 'a': 90, 'e': 2.4}, {'d': 40, 't': 3.0, 'a': 98, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 105, 'e': 2.4}, {'d': 60, 't': 3.0, 'a': 110, 'e': 2.4},
      {'d': 63, 't': 3.0, 'a': 112, 'e': 2.4}, {'d': 70, 't': 3.0, 'a': 114, 'e': 2.4},
      {'d': 76, 't': 3.0, 'a': 118, 'e': 2.4}, {'d': 80, 't': 3.0, 'a': 120, 'e': 2.4},
      {'d': 88, 't': 4.0, 'a': 130, 'e': 3.2}, {'d': 100, 't': 4.0, 'a': 135, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 145, 'e': 3.2}, {'d': 139, 't': 4.0, 'a': 155, 'e': 3.2},
      {'d': 159, 't': 5.0, 'a': 170, 'e': 3.2}, {'d': 168, 't': 5.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 3.0, 'a': 130, 'e': 2.4}, {'d': 273, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 323, 't': 3.0, 'a': 130, 'e': 2.4}, {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 273, 't': 4.0, 'a': 180, 'e': 3.2}, {'d': 323, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 5.0, 'a': 220, 'e': 3.2}, {'d': 273, 't': 5.0, 'a': 220, 'e': 3.2},
      {'d': 323, 't': 5.0, 'a': 220, 'e': 3.2}, {'d': 219, 't': 6.0, 'a': 310, 'e': 4.0},
      {'d': 273, 't': 6.0, 'a': 310, 'e': 4.0}, {'d': 323, 't': 6.0, 'a': 310, 'e': 4.0},
    ];
    for (final r in ssWire) {
      approvedList.add(preset(
        id: 'APP_SS_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE', material: 'SS', d: r['d']!, t: r['t']!, amps: r['a']!,
        electrode: r['e']!, torchGas: 9.0, purge: 18.0,
      ));
    }

    final csWire = <Map<String, double>>[
      {'d': 40, 't': 3.0, 'a': 110, 'e': 2.4}, {'d': 50, 't': 3.0, 'a': 115, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 125, 'e': 2.4}, {'d': 100, 't': 4.0, 'a': 155, 'e': 3.2},
      {'d': 139, 't': 5.0, 'a': 180, 'e': 3.2}, {'d': 159, 't': 5.0, 'a': 190, 'e': 3.2},
      {'d': 219, 't': 6.0, 'a': 220, 'e': 4.0}, {'d': 273, 't': 6.0, 'a': 240, 'e': 4.0},
      {'d': 323, 't': 8.0, 'a': 260, 'e': 4.0}, {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 273, 't': 4.0, 'a': 180, 'e': 3.2}, {'d': 323, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 3.0, 'a': 130, 'e': 2.4}, {'d': 273, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 323, 't': 3.0, 'a': 130, 'e': 2.4}, {'d': 168, 't': 6.0, 'a': 280, 'e': 4.0},
      {'d': 219, 't': 8.0, 'a': 330, 'e': 4.8}, {'d': 273, 't': 8.0, 'a': 330, 'e': 4.8},
      {'d': 323, 't': 8.0, 'a': 330, 'e': 4.8},
    ];
    for (final r in csWire) {
      approvedList.add(preset(
        id: 'APP_CS_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE', material: 'CS', d: r['d']!, t: r['t']!, amps: r['a']!,
        electrode: r['e']!, torchGas: 8.0, purge: 0.0,
      ));
    }

    final duplexAuto = <Map<String, double>>[
      {'d': 38, 't': 1.5, 'a': 55, 'e': 2.4}, {'d': 40, 't': 2.0, 'a': 65, 'e': 2.4},
      {'d': 50, 't': 2.0, 'a': 70, 'e': 2.4}, {'d': 60, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 100, 'e': 2.4}, {'d': 76, 't': 3.0, 'a': 105, 'e': 2.4},
      {'d': 88, 't': 3.0, 'a': 110, 'e': 2.4}, {'d': 100, 't': 4.0, 'a': 120, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 145, 'e': 3.2}, {'d': 139, 't': 4.0, 'a': 150, 'e': 3.2},
      {'d': 159, 't': 5.0, 'a': 160, 'e': 3.2}, {'d': 168, 't': 5.0, 'a': 170, 'e': 3.2},
    ];
    for (final r in duplexAuto) {
      approvedList.add(preset(
        id: 'APP_DUPLEX_AUTO_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_AUTOGEN', material: 'DUPLEX', d: r['d']!, t: r['t']!, amps: r['a']!,
        electrode: r['e']!, torchGas: 9.0, purge: 18.0,
      ));
    }

    final alWire = <Map<String, double>>[
      {'d': 20, 't': 2.0, 'a': 70, 'e': 2.4}, {'d': 25, 't': 2.0, 'a': 75, 'e': 2.4},
      {'d': 32, 't': 3.0, 'a': 90, 'e': 2.4}, {'d': 40, 't': 3.0, 'a': 100, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 110, 'e': 2.4}, {'d': 60, 't': 4.0, 'a': 130, 'e': 3.2},
      {'d': 76, 't': 4.0, 'a': 140, 'e': 3.2}, {'d': 88, 't': 5.0, 'a': 160, 'e': 3.2},
      {'d': 100, 't': 5.0, 'a': 170, 'e': 3.2}, {'d': 114, 't': 3.0, 'a': 150, 'e': 3.2},
      {'d': 168, 't': 3.0, 'a': 150, 'e': 3.2}, {'d': 219, 't': 3.0, 'a': 150, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 180, 'e': 3.2}, {'d': 168, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2}, {'d': 114, 't': 6.0, 'a': 260, 'e': 4.0},
      {'d': 168, 't': 6.0, 'a': 260, 'e': 4.0}, {'d': 219, 't': 6.0, 'a': 260, 'e': 4.0},
    ];
    for (final r in alWire) {
      approvedList.add(preset(
        id: 'APP_AL_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE', material: 'AL', d: r['d']!, t: r['t']!, amps: r['a']!,
        electrode: r['e']!, torchGas: 11.0, purge: 0.0,
      ));
    }

    for (final p in approvedList) {
      await upsertApproved(p);
    }

    // POZIOM | na styk: 3/5 => 180/90
    await upsertTandem({
      'id': 'APPROVED_TANDEM_H_BUTT_3_5',
      'material_group': 'SS',
      'position': 'HORIZONTAL',
      'joint_type': 'BUTT',
      'land_mm': null,
      'gap_mm': null,
      'wall_thickness_mm': 3.0,
      'wall_thickness2_mm': 5.0,
      'outside_amps': 180.0,
      'inside_amps': 90.0,
      'approved': 1,
      'note': 'Zatwierdzone: poziom na styk 3/5 → 180/90 A.',
      'created_at': now,
      'updated_at': now,
    });

    // FAZA + szczelina 3mm: 8.7/10 => 175/105
    await upsertTandem({
      'id': 'APPROVED_TANDEM_H_BEVEL_L3_G3_8_7_10',
      'material_group': 'SS',
      'position': 'HORIZONTAL',
      'joint_type': 'BEVEL',
      'land_mm': 3.0,
      'gap_mm': 3.0,
      'wall_thickness_mm': 8.7,
      'wall_thickness2_mm': 10.0,
      'outside_amps': 175.0,
      'inside_amps': 105.0,
      'approved': 1,
      'note': 'Zatwierdzone: faza + szczelina 3mm, 8.7/10 → 175/105 A.',
      'created_at': now,
      'updated_at': now,
    });

    // PION | na styk: 3/3 => 70/40 (punkt odniesienia)
    await upsertTandem({
      'id': 'APPROVED_TANDEM_V_BUTT_3_3',
      'material_group': 'SS',
      'position': 'VERTICAL',
      'joint_type': 'BUTT',
      'land_mm': null,
      'gap_mm': null,
      'wall_thickness_mm': 3.0,
      'wall_thickness2_mm': 3.0,
      'outside_amps': 70.0,
      'inside_amps': 40.0,
      'approved': 1,
      'note': 'Zatwierdzone: pion na styk 3/3 → 70/40 A.',
      'created_at': now,
      'updated_at': now,
    });

    // ---- Approved AMP (pipes) - placeholder seeds (safe to keep empty)
    Future<void> upsertApprovedAmp(Map<String, Object?> row) async {
      final id = row['id'] as String;
      final existing = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM approved_weld_params WHERE id = ?', [id])) ?? 0;
      if (existing > 0) return;
      await db.insert('approved_weld_params', row);
    }

    await upsertApprovedAmp({
      'id': 'APPROVED_PIPE_TIGWIRE_60_2',
      'method': 'TIG_WIRE',
      'base_material': 'SS',
      'diameter_mm': 60.3,
      'wall_thickness_mm': 2.0,
      'electrode_mm': 1.6,
      'torch_gas_lpm': 9.0,
      'purge_lpm': 2.0,
      'amps': 60.0,
      'note': 'Placeholder zatwierdzone AMP (do podmiany na dane z Firebase).',
      'created_at': now,
      'updated_at': now,
    });
  }

  static Future<void> _ensureColumn(Database db, String table, String column, String sqlType) async {
    final info = await db.rawQuery('PRAGMA table_info($table);');
    final exists = info.any((r) => r['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $sqlType;');
    }
  }
}
