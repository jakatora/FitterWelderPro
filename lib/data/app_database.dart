import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'cut_list_app.db';
  static const _dbVersion = 5;

  Database? _db;

  Future<Database> get db async {
    final existing = _db;
    if (existing != null) return existing;

    final path = await _dbPath();
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgradeToV2(db);
        await _upgradeToV3(db);
        await _upgradeToV4(db);
        await _upgradeToV5(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _upgradeToV2(db);
        }
        if (oldVersion < 3) {
          await _upgradeToV3(db);
        }
        if (oldVersion < 4) {
          await _upgradeToV4(db);
        }
        if (oldVersion < 5) {
          await _upgradeToV5(db);
        }
      },
    );

    return _db!;
  }

  Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbName);
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
CREATE TABLE projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  client TEXT,
  location TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

    await db.execute('''
CREATE TABLE heat_numbers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  heat_number TEXT NOT NULL,
  material TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
);
''');

    await db.execute('CREATE INDEX idx_heat_numbers_project_id ON heat_numbers(project_id);');
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_kv (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS community_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  module TEXT NOT NULL,            -- 'welder_pipe'
  signature TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,            -- 'pending' | 'sent' | 'error'
  last_error TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_status ON community_outbox(status);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_signature ON community_outbox(signature);');
  }

  Future<void> _upgradeToV3(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS welder_pipe_params (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Klucz rury
  material TEXT NOT NULL,          -- np. 'CARBON_STEEL', 'SS316L'
  od_mm REAL NOT NULL,
  wt_mm REAL NOT NULL,

  -- Parametry spawania
  amps REAL NOT NULL,
  method TEXT NOT NULL,            -- 'WTC' | 'FREE_HAND'
  cup_size REAL NOT NULL,          -- porcelanka
  electrode_mm REAL NOT NULL,
  torch_gas TEXT NOT NULL,         -- np. 'ARGON'
  pipe_gas TEXT NOT NULL,          -- gaz do rury (np. 'ARGON')

  purge_enabled INTEGER NOT NULL,  -- 0/1 (dla czarnej stali wybór)
  purge_flow_lpm REAL,             -- opcjonalnie (jeśli purge_enabled=1)

  wire_enabled INTEGER NOT NULL,   -- 0/1
  wire_mm REAL,                    -- jeśli wire_enabled=1

  notes TEXT,

  outlet_holes_count INTEGER NOT NULL DEFAULT 1,
  weld_tempo TEXT NOT NULL DEFAULT 'NORMAL',

  signature TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_wp_signature ON welder_pipe_params(signature);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_wp_key ON welder_pipe_params(material, od_mm, wt_mm);');
  }

  
Future<void> _upgradeToV4(Database db) async {
  await _ensureColumn(db, 'welder_pipe_params', 'outlet_holes_count', 'INTEGER NOT NULL DEFAULT 1');
  await _ensureColumn(db, 'welder_pipe_params', 'weld_tempo', "TEXT NOT NULL DEFAULT 'NORMAL'");
}

Future<void> _ensureColumn(Database db, String table, String column, String sqlType) async {
  final info = await db.rawQuery('PRAGMA table_info($table);');
  final exists = info.any((row) => row['name'] == column);
  if (!exists) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $sqlType;');
  }
}


    Future<void> _upgradeToV5(Database db) async {
      await db.execute('''
CREATE TABLE IF NOT EXISTS tandem_amp_params (
  id TEXT PRIMARY KEY,
  position TEXT NOT NULL,        -- 'HORIZONTAL' | 'VERTICAL'
  t1_mm REAL NOT NULL,
  t2_mm REAL NOT NULL,
  inside_amps INTEGER NOT NULL,  -- wewnętrzny (bez drutu)
  outside_amps INTEGER NOT NULL, -- zewnętrzny (z drutem)
  tempo TEXT NOT NULL,           -- 'SLOW' | 'NORMAL' | 'FAST'
  variant TEXT NOT NULL,         -- 'NORMAL' | 'TI'
  approved INTEGER NOT NULL,     -- 1=Approved, 0=My params
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_tandem_key ON tandem_amp_params(position, tempo, variant, approved, t1_mm, t2_mm);');
      final c = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(1) FROM tandem_amp_params WHERE approved=1;')) ?? 0;
      if (c == 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_0','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':72,'outside_amps':140,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_1','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':72,'outside_amps':170,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_2','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':101,'outside_amps':200,'tempo':'FAST','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_3','position':'HORIZONTAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':100,'outside_amps':190,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_4','position':'HORIZONTAL','t1_mm':5.0,'t2_mm':5.0,'inside_amps':112,'outside_amps':220,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_5','position':'HORIZONTAL','t1_mm':6.0,'t2_mm':6.0,'inside_amps':118,'outside_amps':238,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_6','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':5.0,'inside_amps':90,'outside_amps':180,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_7','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':5.0,'inside_amps':94,'outside_amps':188,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_8','position':'HORIZONTAL','t1_mm':5.0,'t2_mm':6.0,'inside_amps':75,'outside_amps':140,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_9','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':4.0,'inside_amps':85,'outside_amps':165,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_10','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':4.0,'inside_amps':87,'outside_amps':190,'tempo':'NORMAL','variant':'TI','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_11','position':'HORIZONTAL','t1_mm':5.0,'t2_mm':6.0,'inside_amps':107,'outside_amps':210,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_12','position':'HORIZONTAL','t1_mm':6.0,'t2_mm':8.0,'inside_amps':140,'outside_amps':270,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_13','position':'HORIZONTAL','t1_mm':8.0,'t2_mm':8.0,'inside_amps':170,'outside_amps':250,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_14','position':'HORIZONTAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':80,'outside_amps':150,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_15','position':'HORIZONTAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':170,'outside_amps':180,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_16','position':'HORIZONTAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':170,'outside_amps':170,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_HORIZONTAL_17','position':'HORIZONTAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':180,'outside_amps':190,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_0','position':'VERTICAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':72,'outside_amps':140,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_1','position':'VERTICAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':72,'outside_amps':170,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_2','position':'VERTICAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':101,'outside_amps':200,'tempo':'FAST','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_3','position':'VERTICAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':100,'outside_amps':190,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_4','position':'VERTICAL','t1_mm':5.0,'t2_mm':5.0,'inside_amps':112,'outside_amps':220,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_5','position':'VERTICAL','t1_mm':6.0,'t2_mm':6.0,'inside_amps':118,'outside_amps':238,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_6','position':'VERTICAL','t1_mm':3.0,'t2_mm':5.0,'inside_amps':90,'outside_amps':180,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_7','position':'VERTICAL','t1_mm':3.0,'t2_mm':5.0,'inside_amps':94,'outside_amps':188,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_8','position':'VERTICAL','t1_mm':5.0,'t2_mm':6.0,'inside_amps':75,'outside_amps':140,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_9','position':'VERTICAL','t1_mm':3.0,'t2_mm':4.0,'inside_amps':85,'outside_amps':165,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_10','position':'VERTICAL','t1_mm':3.0,'t2_mm':4.0,'inside_amps':87,'outside_amps':190,'tempo':'NORMAL','variant':'TI','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_11','position':'VERTICAL','t1_mm':5.0,'t2_mm':6.0,'inside_amps':107,'outside_amps':210,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_12','position':'VERTICAL','t1_mm':6.0,'t2_mm':8.0,'inside_amps':140,'outside_amps':270,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_13','position':'VERTICAL','t1_mm':8.0,'t2_mm':8.0,'inside_amps':170,'outside_amps':250,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_14','position':'VERTICAL','t1_mm':3.0,'t2_mm':3.0,'inside_amps':80,'outside_amps':150,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_15','position':'VERTICAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':170,'outside_amps':180,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_16','position':'VERTICAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':170,'outside_amps':170,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
    await db.insert('tandem_amp_params', {'id':'seed_VERTICAL_17','position':'VERTICAL','t1_mm':4.0,'t2_mm':4.0,'inside_amps':180,'outside_amps':190,'tempo':'NORMAL','variant':'NORMAL','approved':1,'note':null,'created_at':now,'updated_at':now});
      }
    }
Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }
}
