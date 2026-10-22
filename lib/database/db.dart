import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

/// Local SQLite database.
///
/// NOTE: Keep schema and DAO/models in sync.
class AppDatabase {
  static Database? _db;
  static Future<Database>? _opening;
  static String? _databasePathForTesting;

  // Bump this whenever you change schema.
  // v16: schema self-heal for users who installed earlier builds with version
  // already bumped but missing some columns (e.g. projects.gap_mm).
  // v18: the weld journal, the test-coupon log and the pressure-test register
  //   move from lazy screen-side CREATE TABLE into this schema (a phone that
  //   had never opened those screens had no table, so a restored backup
  //   silently dropped their rows), plus `iso_drawings` for the ISO notebook
  //   autosave. The step also widens a weld_journal created by the oldest
  //   screen code to the full weld-map shape.
  // v19: hydrotest_records gains the pressure-test protocol fields (company,
  //   project, test package, P&ID/ISO, medium, code preset, stress ratio,
  //   metal temperature, gauge range and calibration due date, relief-valve
  //   set pressure, protocol no. and revision) — see
  //   lib/domain/pressure_test/hydrotest_protocol_meta.dart.
  // v20: the weld journal an inspector accepts — identification, root/cap
  //   stamps, filler, actual preheat/interpass/heat input, PWHT, acceptance,
  //   soft delete and NDT per method on weld_journal; change history
  //   (weld_journal_history), repairs (weld_repairs), per-project header and
  //   RT/UT target (weld_journal_projects); program, O₂ and heat tint on
  //   weld_coupons. See lib/domain/weld_journal/.
  // v21: rejestr uprawnień spawacza `welder_certificates` (ISO 9606-1 /
  //   ASME IX WPQ — wiele certyfikatów, zakres, ciągłość 6-miesięczna) i
  //   biblioteka WPS `wps_library`. Obie tabele nowe i puste; dotychczasowy
  //   numer i data „WPQR" z SharedPreferences przenosi do rejestru
  //   WelderQualificationService (jednorazowo, przy pierwszym odczycie).
  // v22: identyfikacja sztuk — `projects` dostaje nr linii, nr ISO, rewizję,
  //   klienta i klasę rurociągu (line_no, iso_no, iso_rev, client, spec),
  //   `segments` oznaczenie sztuki i spool (label, spool_id). Wszystko TEXT,
  //   NULL, bez domyślnych — stary projekt po prostu ich nie ma.
  // v23: identyfikowalność materiału w projektach CUT —
  //   `component_heats` dostaje `segment_id` + `side` (START / PIPE / END):
  //   numer wytopu przypięty do stabilnego id segmentu, nie do `seq_no`
  //   (usunięty ostatni segment oddawał swój numer następnemu i heat
  //   „przechodził” na inną kształtkę). Stare klucze `S003_END` są
  //   przepinane na id segmentu; wpis, którego segmentu już nie ma, zostaje
  //   z `segment_id` NULL (ekran pokazuje go jako „bez miejsca”).
  //   `heat_photos.heat_no` — numer wytopu na zdjęciu etykiety / atestu.
  //   `cut_marks` — odhaczone ucięte kawałki listy cięć (offline).
  // v24: odczyt skanera izometryku `iso_scans` — koperta odpowiedzi serwera
  //   (JSON) i kopia zdjęcia w <documents>/heat_photos (katalog objęty kopią
  //   zapasową). Płatny skan przeżywa zabicie aplikacji i „Odrzuć”; ponowne
  //   otwarcie nie zużywa limitu. Tabela nowa i pusta. (v23 i v24 powstały
  //   równolegle; krok v23 jest idempotentny i wykonuje się zawsze, więc
  //   baza z v24 bez v23 też go dostaje.)
  // v25 (G5 — dokumentacja jakości):
  //   • `welder_cert_confirmations` — historia potwierdzeń ISO 9606-1 §9.2
  //     (data, kto, uwagi). Dotychczasowe `last_confirmed_date` każdego
  //     certyfikatu staje się pierwszym wpisem historii;
  //   • `weld_coupon_history` + kolumny `deleted_at`, `accepted_by`,
  //     `accepted_at` w `weld_coupons` — historia zmian kuponów, miękkie
  //     usuwanie i „kto przyjął";
  //   • `weld_repairs.prev_acceptance` — odbiór, PWHT i twardość sprzed
  //     naprawy (JSON);
  //   • `weld_journal.wps_id` — WPS wybrana z biblioteki;
  //   • `wps_library.doc_status` i `wps_versions` — status dokumentu
  //     (pWPS / zatwierdzona / wycofana) i wersje treści WPS z datą
  //     obowiązywania; każda istniejąca WPS dostaje wersję 1 „od zawsze";
  //   • `passivation_records` — rejestr trawienia / pasywacji.
  //   Wszystkie nowe kolumny NULL, bez domyślnych — stary wiersz ich nie ma.
  // v26: wyceny spawalnicze `weld_quotes` — nagłówek (numer, przedmiot,
  //   klient, status, sumy netto/brutto w groszach do listy) i treść wyceny
  //   w `data_json` (złącza, schemat procesów, KOPIA stawek i cen z chwili
  //   utworzenia — patrz lib/domain/quotes/weld_quote.dart). Tabela nowa
  //   i pusta; nic istniejącego nie jest ruszane.
  // v27: rejestr przyrządów i kalibracji `instruments` (spawarki —
  //   walidacja, manometry, termometry, mierniki, analizatory O₂, klucze
  //   dynamometryczne) — lib/domain/instruments/instrument.dart. Daty
  //   `yyyy-MM-dd`, usuwanie miękkie. Tabela nowa i pusta.
  // v28: `weld_journal` dostaje dane do kontroli ograniczeń z próby
  //   ISO 9606-1 (linia `[ISO9606 v1]` w uwagach certyfikatu):
  //   `root_backing` (prowadzenie grani: nb / mb / bs / gb / ci / fb),
  //   `metal_transfer` (MIG/MAG: dip / other) i `product_form` (T rura /
  //   P blacha). TEXT, NULL, bez domyślnych — stara spoina „nie podaje”, więc
  //   kontrola mówi „nie da się porównać”, nie „poza zakresem”.
  // v29: saved welding parameters belong to an account or the offline guest.
  static const int _dbVersion = 29;

  /// The schema version [get] opens the database at.
  ///
  /// Exposed so `test/database/migration_test.dart` migrates to whatever the
  /// app actually ships instead of to a hard-coded 17 that silently stops
  /// matching the next time someone bumps [_dbVersion].
  static int get schemaVersion => _dbVersion;

  static Future<Database> get() {
    final ready = _db;
    if (ready != null && ready.isOpen) return Future.value(ready);
    // Every caller waits for the same complete preparation, not just open().
    final pending = _opening;
    if (pending != null) return pending;
    final opening = _open();
    _opening = opening;
    // _open() clears `_opening` in its finally — but when it fails
    // SYNCHRONOUSLY (e.g. `databaseFactory` not initialised: the getter
    // throws before any await), that finally has already run by the time the
    // line above stores the future. Without this the failed future stayed
    // cached forever: every later get() replayed the stale error, and in
    // widget tests awaited a future bound to a finished test's zone, which
    // never completes. test/database/startup_test.dart pins it.
    opening.then<void>((_) {}, onError: (Object _) {
      if (identical(_opening, opening)) _opening = null;
    });
    return opening;
  }

  static Future<Database> _open() async {
    Database? connection;
    try {
      final dbPath = await getDatabasesPath();
      final path = _databasePathForTesting ?? p.join(dbPath, 'cutlist.db');
      connection = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, _) async {
          await createSchema(db);
          await _seedApprovedData(db);
        },
        onUpgrade: migrate,
      );

      // A current-version database can still lack tables. Keep the existing
      // idempotent repair/seed step, but do not expose the connection until
      // it finishes. Indexes may reference missing legacy columns, so only
      // repair tables here, as before.
      await _createTables(connection);
      await _ensureColumn(connection, 'weld_params', 'owner_scope',
          "TEXT NOT NULL DEFAULT 'guest'");
      await _seedApprovedData(connection);
      _db = connection;
      return connection;
    } catch (_) {
      _db = null;
      if (connection != null && connection.isOpen) {
        try {
          await connection.close();
        } catch (_) {
          // Preserve the initialization error if cleanup also fails.
        }
      }
      rethrow;
    } finally {
      // A failed attempt must not poison the next retry.
      _opening = null;
    }
  }

  /// Applies every schema step needed to bring a database from [oldVersion]
  /// up to [newVersion].
  ///
  /// Public on purpose: this is the entry point `test/database/migration_test.dart`
  /// drives. Seventeen schema versions shipped without a single migration test,
  /// and v16 exists only because one of those migrations had already failed on
  /// users' devices — an untestable closure inside [get] is how that happened.
  static Future<void> migrate(
      Database db, int oldVersion, int newVersion) async {
    // Self-heal FIRST, for every upgrade path — not just the v16 one.
    //
    // The steps below reach for tables with ALTER TABLE (via [_ensureColumn])
    // and with INSERT (via [_seedApprovedData]). Both throw "no such table" on
    // a database that is missing one, which aborts onUpgrade, which makes
    // openDatabase throw, which bricks the app on launch with no way back.
    // The v16 block already did this for `projects` alone after users hit
    // exactly that; every statement in [_createTables] is CREATE TABLE IF
    // NOT EXISTS, so running the whole thing is idempotent and covers every
    // table rather than just `projects`.
    await _createTables(db);

    // Column drift the version ladder never covered.
    //
    // component_library.diameter_out_mm is in [createSchema] and is both
    // written and queried by ComponentLibraryDao (the REDUCER branch of its
    // lookup selects on it), but no `oldVersion <` block below ever adds it.
    // _createTables cannot help: CREATE TABLE IF NOT EXISTS sees the legacy
    // table and leaves it alone. So every database whose component_library
    // predates that column reaches v17 without it and throws "no such column"
    // on the first reducer lookup. Unconditional, because a 16 -> 17 upgrade
    // skips every block below.
    await _ensureColumn(db, 'component_library', 'diameter_out_mm', 'REAL');

    // ---- Projects
    if (oldVersion < 2) {
      await _ensureColumn(
          db, 'projects', 'material_group', "TEXT NOT NULL DEFAULT 'SS'");
      await _ensureColumn(
          db, 'projects', 'stock_length_mm', 'REAL NOT NULL DEFAULT 6000');
      await _ensureColumn(
          db, 'projects', 'saw_kerf_mm', 'REAL NOT NULL DEFAULT 1');

      await _ensureColumn(db, 'component_library', 'material_group',
          "TEXT NOT NULL DEFAULT 'SS'");
      await _ensureColumn(db, 'component_library', 'measurement_mode', 'TEXT');
    }

    // ---- Segments
    if (oldVersion < 3) {
      await _ensureColumn(
          db, 'segments', 'iso_ref', "TEXT NOT NULL DEFAULT 'FACE'");
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
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_heat_project ON heat_photos(project_id);');
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
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_component_heats_project ON component_heats(project_id);');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_component_heats_key ON component_heats(project_id, component_key);');
    }

    // ---- Welder pipes: user weld params
    if (oldVersion < 6) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS weld_params (
  id TEXT PRIMARY KEY,
  owner_scope TEXT NOT NULL DEFAULT 'guest',
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
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_weld_params_main ON weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
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
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tandem_tig_main ON tandem_tig_params(material_group, position, joint_type, land_mm, wall_thickness_mm);');
    }
    if (oldVersion < 11) {
      await _ensureColumn(
          db, 'tandem_tig_params', 'wall_thickness2_mm', 'REAL');
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
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_approved_weld_params_main ON approved_weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
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
      await _ensureColumn(
          db, 'projects', 'material_group', "TEXT NOT NULL DEFAULT 'SS'");
      await _ensureColumn(
          db, 'projects', 'stock_length_mm', 'REAL NOT NULL DEFAULT 6000');
      await _ensureColumn(
          db, 'projects', 'saw_kerf_mm', 'REAL NOT NULL DEFAULT 1');
      await _ensureColumn(db, 'projects', 'gap_mm', 'REAL NOT NULL DEFAULT 0');
    }

    if (oldVersion < 17) {
      await _seedApprovedData(db);
    }

    // ---- v18: registers that used to be created by their screens.
    //
    // _createTables (top of this method) already created weld_journal,
    // weld_coupons, hydrotest_records and iso_drawings where they were
    // missing. Where the SCREEN had created them first, CREATE TABLE IF NOT
    // EXISTS left the old table alone — and weld_journal_screen.dart shipped
    // with 12 columns and grew the ASME BPE weld-map ones (and later wps_ref)
    // through its own ALTER TABLE on screen open. A welder who had not opened
    // the journal since then still carries the 12-column table, so widen it
    // here. Rows are untouched; the new columns start NULL, which WeldEntry
    // already reads as its defaults.
    if (oldVersion < 18) {
      for (final column in _kWeldJournalLateColumns) {
        await _ensureColumn(db, 'weld_journal', column, 'TEXT');
      }
    }

    // ---- v19: pressure-test protocol fields. All nullable, no defaults: a
    // test filed before v19 simply has none of them, and the protocol prints
    // "—" for each.
    if (oldVersion < 19) {
      for (final column in _kHydrotestProtocolColumns.entries) {
        await _ensureColumn(db, 'hydrotest_records', column.key, column.value);
      }
    }

    // ---- v20: weld journal for the inspector. Columns only — the three new
    // tables came from _createTables at the top. All nullable, no defaults:
    // a weld logged before v20 has no NDT, no repair and is not deleted, and
    // must not be made to look otherwise.
    if (oldVersion < 20) {
      for (final column in _kWeldJournalV20Columns.entries) {
        await _ensureColumn(db, 'weld_journal', column.key, column.value);
      }
      for (final column in _kWeldCouponsV20Columns.entries) {
        await _ensureColumn(db, 'weld_coupons', column.key, column.value);
      }
    }

    // ---- v21: rejestr uprawnień spawacza i biblioteka WPS. Obie tabele są
    // nowe — _createTables na początku migracji już je utworzył; wołamy
    // jeszcze raz jawnie (idempotentnie), żeby krok wersji był samodzielny,
    // gdyby ktoś kiedyś przeniósł self-heal. Żaden istniejący wiersz nie jest
    // ruszany. Przeniesienie starego numeru „WPQR" z SharedPreferences robi
    // WelderQualificationService — migracja SQL nie ma dostępu do preferencji.
    if (oldVersion < 21) {
      await _createQualificationTables(db);
    }

    // ---- v22: identyfikacja sztuk (monter → QC → brygadzista). Same
    // kolumny, wszystkie NULL: projekt i segment sprzed v22 nie mają numeru
    // linii ani oznaczenia i nie wolno ich wymyślać.
    if (oldVersion < 22) {
      for (final column in kProjectIdentityColumns.entries) {
        await _ensureColumn(db, 'projects', column.key, column.value);
      }
      for (final column in kSegmentIdentityColumns.entries) {
        await _ensureColumn(db, 'segments', column.key, column.value);
      }
    }

    // ---- v23: identyfikowalność (heat) w projektach CUT. Kolumny NULL;
    // `cut_marks` przyszło z _createTables na początku. Istniejące wpisy
    // heat są przepinane z `seq_no` na id segmentu — żaden nie jest kasowany.
    //
    // Bez warunku `oldVersion < 23`: v24 (skaner) powstał równolegle, więc
    // baza testowa mogła dostać v24 bez kroku v23 — a indeks na
    // component_heats(segment_id) w _createIndexes wywróciłby wtedy start
    // aplikacji. Każda instrukcja jest idempotentna (_ensureColumn, relink
    // tylko wierszy bez segment_id), więc powtórka niczego nie zmienia.
    {
      for (final column in kComponentHeatV23Columns.entries) {
        await _ensureColumn(db, 'component_heats', column.key, column.value);
      }
      for (final column in kHeatPhotoV23Columns.entries) {
        await _ensureColumn(db, 'heat_photos', column.key, column.value);
      }
      await relinkLegacyHeatKeys(db);
    }

    // ---- v24: odczyty skanera izometryku. Tabela nowa — self-heal na
    // początku już ją utworzył; jawnie jeszcze raz (idempotentnie), żeby
    // krok wersji był samodzielny. Nic istniejącego nie jest ruszane.
    if (oldVersion < 24) {
      await _createIsoScanTable(db);
    }

    // ---- v25: dokumentacja jakości (G5). Tabele przyszły z _createTables na
    // początku migracji; tu kolumny w istniejących tabelach i przeniesienie
    // danych. Idempotentne — ponowne przejście nie dubluje wpisów.
    if (oldVersion < 25) {
      await migrateV25(db);
    }

    // ---- v26: wyceny spawalnicze. Tabela nowa — self-heal na początku już
    // ją utworzył; jawnie jeszcze raz (idempotentnie), żeby krok wersji był
    // samodzielny. Nic istniejącego nie jest ruszane.
    if (oldVersion < 26) {
      await _createQuoteTables(db);
    }

    // ---- v27: rejestr przyrządów i kalibracji. Tabela nowa — jak v26.
    if (oldVersion < 27) {
      await _createInstrumentTables(db);
    }

    // ---- v28: grań / przenoszenie metalu / wyrób w dzienniku spoin. Same
    // kolumny, wszystkie NULL: spoina sprzed v28 ich nie podaje i nie wolno
    // ich wymyślać (kontrola uprawnień mówi wtedy „nie da się porównać”).
    if (oldVersion < 28) {
      for (final c in kWeldJournalV28Columns.entries) {
        await _ensureColumn(db, 'weld_journal', c.key, c.value);
      }
    }

    if (oldVersion < 29) {
      await _ensureColumn(
          db, 'weld_params', 'owner_scope', "TEXT NOT NULL DEFAULT 'guest'");
    }

    // Last, now that every column the indexes reference exists.
    await _createIndexes(db);
  }

  /// Krok v25 (patrz komentarz przy [_dbVersion]). Publiczny dla testu.
  @visibleForTesting
  static Future<void> migrateV25(Database db) async {
    await _createQualityTables(db);
    for (final c in kWeldJournalV25Columns.entries) {
      await _ensureColumn(db, 'weld_journal', c.key, c.value);
    }
    for (final c in kWeldCouponsV25Columns.entries) {
      await _ensureColumn(db, 'weld_coupons', c.key, c.value);
    }
    for (final c in kWeldRepairsV25Columns.entries) {
      await _ensureColumn(db, 'weld_repairs', c.key, c.value);
    }
    for (final c in kWpsLibraryV25Columns.entries) {
      await _ensureColumn(db, 'wps_library', c.key, c.value);
    }

    // Ostatnie potwierdzenie → pierwszy wpis historii potwierdzeń. Nic nie
    // jest kasowane: kolumna last_confirmed_date zostaje (czyta ją starsza
    // kopia zapasowa i jest „ostatnim" wpisem łańcucha).
    await db.execute('''
INSERT INTO welder_cert_confirmations
  (id, certificate_id, date, confirmed_by, notes, created_at)
SELECT 'v25-' || c.id, c.id, c.last_confirmed_date, NULL,
       'Przeniesione z pola „Ostatnie potwierdzenie" (v25)',
       COALESCE(c.updated_at, 0)
FROM welder_certificates c
WHERE c.last_confirmed_date IS NOT NULL
  AND TRIM(c.last_confirmed_date) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM welder_cert_confirmations x
    WHERE x.certificate_id = c.id AND x.date = c.last_confirmed_date);
''');

    // Każda WPS dostaje wersję 1 z bieżącą treścią, obowiązującą „od zawsze"
    // (valid_from = 0): historii sprzed v25 nie znamy, więc stare spoiny są
    // oceniane dokładnie tak jak dotąd.
    final wps = await db.query('wps_library');
    for (final row in wps) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final has = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM wps_versions WHERE wps_id = ?', [id])) ??
          0;
      if (has > 0) continue;
      await db.insert('wps_versions', <String, Object?>{
        'id': 'v25-$id-1',
        'wps_id': id,
        'version_no': 1,
        'valid_from': 0,
        'snapshot': jsonEncode(row),
        'by_stamp': null,
        'created_at': (row['updated_at'] as num?)?.toInt() ?? 0,
      });
    }
  }

  @visibleForTesting
  static Future<void> configureForTesting(String databasePath) async {
    final existing = _db;
    _db = null;
    if (existing != null && existing.isOpen) await existing.close();
    _databasePathForTesting = databasePath;
  }

  @visibleForTesting
  static Future<void> clearTestingConfiguration() async {
    final existing = _db;
    _db = null;
    _databasePathForTesting = null;
    if (existing != null && existing.isOpen) await existing.close();
  }

  /// Creates every table and index the current schema defines.
  ///
  /// Every statement is CREATE ... IF NOT EXISTS, so it is idempotent and safe
  /// to run against a populated database. Split in two underneath, because the
  /// two halves are NOT equally safe on a legacy schema - see [_createTables]
  /// and [_createIndexes].
  static Future<void> createSchema(Database db) async {
    await _createTables(db);
    await _createIndexes(db);
  }

  /// Creates every table of the current schema that [db] is missing, and
  /// touches nothing that already exists.
  ///
  /// For callers outside the open/upgrade path that need "the tables this
  /// app owns" to be present — the backup restore calls it inside its own
  /// transaction before refilling, so a table known to this schema is never
  /// skipped just because the live file happens to lack it.
  static Future<void> ensureTables(DatabaseExecutor db) => _createTables(db);

  /// Columns weld_journal_screen.dart added to its own table with ALTER TABLE
  /// after the first release (ASME BPE weld map, then the WPS reference).
  static const List<String> _kWeldJournalLateColumns = <String>[
    'weld_type',
    'fitter',
    'heat_no1',
    'heat_no2',
    'coupon_ref',
    'exam',
    'wps_ref',
  ];

  /// Pressure-test protocol columns added in v19 (name → SQLite type). Must
  /// match `HydrotestProtocolMeta.columns`; a test checks that it does.
  static const Map<String, String> _kHydrotestProtocolColumns =
      <String, String>{
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
  };

  /// weld_journal columns added in v20 (name → SQLite type). Must match
  /// `WeldEntry.toRow()`; the backup round-trip test compares the two.
  static final Map<String, String> _kWeldJournalV20Columns =
      Map.unmodifiable(<String, String>{
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
    // NDT per method — see lib/domain/weld_journal/weld_ndt.dart.
    for (final m in const ['vt', 'pt', 'mt', 'rt', 'ut'])
      for (final f in const ['scope', 'result', 'report', 'date'])
        'ndt_${m}_$f': 'TEXT',
  });

  /// projects columns added in v22 (name → SQLite type): the line, the
  /// isometric and its revision, the client and the piping class the QC
  /// inspector and the foreman identify a job by.
  static const Map<String, String> kProjectIdentityColumns = <String, String>{
    'line_no': 'TEXT',
    'iso_no': 'TEXT',
    'iso_rev': 'TEXT',
    'client': 'TEXT',
    'spec': 'TEXT',
  };

  /// segments columns added in v22: the piece mark as the drawing numbers it
  /// (`SP02-03`) and the spool it belongs to.
  static const Map<String, String> kSegmentIdentityColumns = <String, String>{
    'label': 'TEXT',
    'spool_id': 'TEXT',
  };

  /// component_heats columns added in v23: the segment (stable id) and the
  /// place on it — `START`, `PIPE` or `END` — the heat number belongs to.
  static const Map<String, String> kComponentHeatV23Columns = <String, String>{
    'segment_id': 'TEXT',
    'side': 'TEXT',
  };

  /// heat_photos columns added in v23: the heat number read off the label.
  static const Map<String, String> kHeatPhotoV23Columns = <String, String>{
    'heat_no': 'TEXT',
  };

  /// Pins pre-v23 heat entries (`component_key` = `S003_END`, built from the
  /// segment's seq_no) to the segment's id and side.
  ///
  /// Only rows still without a `segment_id` are touched, so running it twice
  /// changes nothing. A key whose segment is gone (deleted since) — or that
  /// does not follow the old pattern — stays unlinked: nothing is guessed,
  /// nothing is deleted, the screen lists it as "no place".
  static Future<void> relinkLegacyHeatKeys(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
        'SELECT id, project_id, component_key FROM component_heats '
        'WHERE segment_id IS NULL');
    final pattern = RegExp(r'^S(\d+)_(START|END)$');
    for (final r in rows) {
      final m = pattern.firstMatch((r['component_key'] as String?) ?? '');
      if (m == null) continue;
      final seq = int.parse(m.group(1)!);
      final seg = await db.query(
        'segments',
        columns: ['id'],
        where: 'project_id = ? AND seq_no = ?',
        whereArgs: [r['project_id'], seq],
        limit: 1,
      );
      if (seg.isEmpty) continue;
      await db.update(
        'component_heats',
        {'segment_id': seg.first['id'], 'side': m.group(2)},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
  }

  /// weld_coupons columns added in v20 (name → SQLite type).
  static const Map<String, String> _kWeldCouponsV20Columns = <String, String>{
    'program_no': 'TEXT',
    'program_params': 'TEXT',
    'o2_ppm': 'REAL',
    'heat_tint': 'INTEGER',
  };

  /// `  name TYPE,\n  name TYPE` for a CREATE TABLE body.
  static String _columnsDdl(Map<String, String> columns) => columns.entries
      .map((c) => '  ${c.key} ${c.value}')
      .join(',\n');

  /// CREATE TABLE IF NOT EXISTS for every table, and nothing else.
  ///
  /// Safe to run against a database of ANY vintage, which is what makes it
  /// usable as the self-heal at the top of [migrate]: none of these
  /// statements names a column of a table it is not itself creating, so an
  /// old table simply survives untouched.
  static Future<void> _createTables(DatabaseExecutor db) async {
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
  updated_at INTEGER NOT NULL,
${_columnsDdl(kProjectIdentityColumns)}
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
${_columnsDdl(kSegmentIdentityColumns)},
  UNIQUE (project_id, seq_no),
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS heat_photos (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  library_component_id TEXT,
  image_path TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
${_columnsDdl(kHeatPhotoV23Columns)},
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS component_heats (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  component_key TEXT NOT NULL,
  heat_no TEXT NOT NULL,
  image_path TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
${_columnsDdl(kComponentHeatV23Columns)},
  FOREIGN KEY(project_id) REFERENCES projects(id)
);
''');
    // v23: pieces of the cut list ticked off at the saw. One row per piece
    // (segment + part of a split cut); `cut_mm` is the segment's CUT when it
    // was ticked, so a mark on a segment corrected since is not trusted.
    await db.execute('''
CREATE TABLE IF NOT EXISTS cut_marks (
  project_id TEXT NOT NULL,
  segment_id TEXT NOT NULL,
  part INTEGER NOT NULL,
  cut_mm REAL NOT NULL,
  marked_at INTEGER NOT NULL,
  PRIMARY KEY (segment_id, part)
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_params (
  id TEXT PRIMARY KEY,
  owner_scope TEXT NOT NULL DEFAULT 'guest',
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

    // ---- Registers (v18). Until v18 each of these was created lazily by
    // its own screen/DAO; the column lists are exactly what that code built
    // (see _kWeldJournalLateColumns for how weld_journal got its last seven),
    // so a table the old code created and one created here are the same.
    // Every column is nullable on purpose: these are field records, and a
    // half-filled row is still evidence worth keeping.
    //
    // Weld journal — weld_journal_screen.dart (WeldJournalDao / WeldEntry).
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
  status TEXT,
  weld_type TEXT,
  fitter TEXT,
  heat_no1 TEXT,
  heat_no2 TEXT,
  coupon_ref TEXT,
  exam TEXT,
  wps_ref TEXT,
${_columnsDdl(_kWeldJournalV20Columns)},
${_columnsDdl(kWeldJournalV25Columns)},
${_columnsDdl(kWeldJournalV28Columns)}
);
''');
    // v20: change history of the journal — one row per changed field (or per
    // create / delete / restore / repair), stamped with the welder identity.
    // Never updated or deleted by the app.
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_journal_history (
  id TEXT PRIMARY KEY,
  weld_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  by_stamp TEXT,
  action TEXT NOT NULL,
  field TEXT,
  old_value TEXT,
  new_value TEXT
);
''');
    // v20: repairs R1, R2, … with the weld's status and NDT state before
    // each repair (prev_ndt is the JSON of weld_ndt.dart encodeNdtSnapshot).
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_repairs (
  id TEXT PRIMARY KEY,
  weld_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  date TEXT,
  reason TEXT,
  prev_status TEXT,
  prev_ndt TEXT,
  by_stamp TEXT,
  created_at INTEGER NOT NULL,
${_columnsDdl(kWeldRepairsV25Columns)}
);
''');
    // v20: per-project journal settings — PDF header and the RT/UT target
    // from the project specification. Keyed by lower-case project name.
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_journal_projects (
  project_key TEXT PRIMARY KEY,
  project_name TEXT,
  company TEXT,
  client TEXT,
  project_title TEXT,
  document_no TEXT,
  revision TEXT,
  rt_target_pct REAL
);
''');
    // Daily test-coupon log — coupon_log_screen.dart (CouponDao).
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_coupons (
  id TEXT PRIMARY KEY,
  date TEXT,
  welder TEXT,
  machine TEXT,
  size TEXT,
  result TEXT,
  notes TEXT,
${_columnsDdl(_kWeldCouponsV20Columns)},
${_columnsDdl(kWeldCouponsV25Columns)}
);
''');
    // Pressure-test register — hydrotest_dao.dart. Units: bar, °C, minutes,
    // litres, MILLIMETRES (line_length_mm too; see the DAO's library doc).
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
  created_at INTEGER,
  company TEXT,
  project TEXT,
  test_package TEXT,
  drawing_refs TEXT,
  test_medium TEXT,
  test_preset TEXT,
  stress_ratio REAL,
  metal_temp_c REAL,
  gauge_range TEXT,
  gauge_cal_due TEXT,
  relief_set_bar REAL,
  protocol_no TEXT,
  protocol_rev TEXT
);
''');
    // ISO notebook sketches — iso_drawing_dao.dart. `json` is the whole
    // drawing in the versioned format of iso_notebook_sketch_codec.dart; the
    // name is duplicated into its own column so a list of sketches does not
    // have to parse every drawing.
    await db.execute('''
CREATE TABLE IF NOT EXISTS iso_drawings (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    await _createQualificationTables(db);
    await _createIsoScanTable(db);
    await _createQualityTables(db);
    await _createQuoteTables(db);
    await _createInstrumentTables(db);
  }

  /// v27: rejestr przyrządów i kalibracji — instrument_dao.dart.
  static Future<void> _createInstrumentTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS instruments (
  id TEXT PRIMARY KEY,
  kind TEXT,
  name TEXT,
  serial_no TEXT,
  location TEXT,
  last_calibration TEXT,
  interval_months INTEGER,
  due_override TEXT,
  certificate_no TEXT,
  calibrated_by TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
''');
  }

  /// v26: wyceny spawalnicze — weld_quote_dao.dart. Kwoty w GROSZACH
  /// (INTEGER), żeby lista ofert sumowała się co do grosza; treść wyceny
  /// (złącza, stawki, pozycje dodatkowe) jako JSON w `data_json`.
  static Future<void> _createQuoteTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_quotes (
  id TEXT PRIMARY KEY,
  number TEXT,
  title TEXT,
  client TEXT,
  status TEXT,
  data_json TEXT NOT NULL,
  net_grosze INTEGER,
  gross_grosze INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
''');
  }

  /// weld_journal columns added in v25: the WPS picked from the library.
  static const Map<String, String> kWeldJournalV25Columns = <String, String>{
    'wps_id': 'TEXT',
  };

  /// weld_journal columns added in v28: prowadzenie grani, przenoszenie
  /// metalu (MIG/MAG) i wyrób (rura / blacha) — dane do ograniczeń z próby
  /// ISO 9606-1 (patrz `WeldEntry.rootBacking` i dalej).
  static const Map<String, String> kWeldJournalV28Columns = <String, String>{
    'root_backing': 'TEXT',
    'metal_transfer': 'TEXT',
    'product_form': 'TEXT',
  };

  /// weld_coupons columns added in v25: soft delete and who accepted the
  /// coupon, when (`YYYY-MM-DD`).
  static const Map<String, String> kWeldCouponsV25Columns = <String, String>{
    'deleted_at': 'INTEGER',
    'accepted_by': 'TEXT',
    'accepted_at': 'TEXT',
  };

  /// weld_repairs columns added in v25: acceptance, PWHT chart and hardness
  /// the weld carried before the repair (JSON, see weld_repair.dart).
  static const Map<String, String> kWeldRepairsV25Columns = <String, String>{
    'prev_acceptance': 'TEXT',
  };

  /// wps_library columns added in v25: document status (pWPS / approved /
  /// withdrawn), see wps_record.dart.
  static const Map<String, String> kWpsLibraryV25Columns = <String, String>{
    'doc_status': 'TEXT',
  };

  /// v25: tabele dokumentacji jakości (G5) — historia potwierdzeń
  /// uprawnień, historia kuponów, wersje WPS i rejestr pasywacji.
  static Future<void> _createQualityTables(DatabaseExecutor db) async {
    // Potwierdzenia EN ISO 9606-1 §9.2 (i wpisy ciągłości WPQ). Łańcuch
    // tych dat liczy status certyfikatu na dowolny dzień.
    await db.execute('''
CREATE TABLE IF NOT EXISTS welder_cert_confirmations (
  id TEXT PRIMARY KEY,
  certificate_id TEXT NOT NULL,
  date TEXT NOT NULL,
  confirmed_by TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL
);
''');
    // Historia zmian logu kuponów — jak weld_journal_history.
    await db.execute('''
CREATE TABLE IF NOT EXISTS weld_coupon_history (
  id TEXT PRIMARY KEY,
  coupon_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  by_stamp TEXT,
  action TEXT NOT NULL,
  field TEXT,
  old_value TEXT,
  new_value TEXT
);
''');
    // Wersje treści WPS: snapshot wiersza wps_library (JSON) obowiązujący
    // od valid_from (epoch ms). Spoina jest oceniana wg wersji z dnia
    // spawania.
    await db.execute('''
CREATE TABLE IF NOT EXISTS wps_versions (
  id TEXT PRIMARY KEY,
  wps_id TEXT NOT NULL,
  version_no INTEGER NOT NULL,
  valid_from INTEGER NOT NULL,
  snapshot TEXT NOT NULL,
  by_stamp TEXT,
  created_at INTEGER NOT NULL
);
''');
    // Rejestr trawienia / pasywacji (data book). Temperatura °C, czas min,
    // konduktywność wody płuczącej µS/cm.
    await db.execute('''
CREATE TABLE IF NOT EXISTS passivation_records (
  id TEXT PRIMARY KEY,
  date TEXT,
  treatment TEXT,
  line TEXT,
  test_package TEXT,
  area TEXT,
  agent TEXT,
  agent_batch TEXT,
  dwell_min REAL,
  temp_c REAL,
  rinse_us_cm REAL,
  test_method TEXT,
  test_result TEXT,
  by_stamp TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
''');
  }

  /// v24: odczyty skanera izometryku — iso_scan_dao.dart. `envelope_json` to
  /// odpowiedź serwera dokładnie tak, jak przyszła (`{result, tookMs,
  /// model}`), `image_path` kopia zdjęcia w katalogu `heat_photos`
  /// (`kPhotoPathColumns` w data_backup.dart).
  static Future<void> _createIsoScanTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS iso_scans (
  id TEXT PRIMARY KEY,
  name TEXT,
  image_path TEXT,
  envelope_json TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''');
  }

  /// v21: rejestr uprawnień spawacza i biblioteka WPS.
  ///
  /// Daty jako TEXT `yyyy-MM-dd` (dzień kalendarzowy, bez strefy czasowej —
  /// „ważny do 2026-09-10" to cały 10 września w każdej strefie). Wymiary
  /// w MILIMETRACH, temperatury w °C, energia liniowa w kJ/mm w konwencji
  /// z `heat_input_method` ('EN' = EN 1011-1 z k, 'ASME' = QW-409.1 bez k).
  /// `photo_path` / `attachment_path` wskazują kopię w
  /// `<documents>/heat_photos` — katalogu objętym kopią zapasową
  /// (`kPhotoPathColumns` w data_backup.dart).
  static Future<void> _createQualificationTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS welder_certificates (
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
CREATE TABLE IF NOT EXISTS wps_library (
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
  updated_at INTEGER NOT NULL,
${_columnsDdl(kWpsLibraryV25Columns)}
);
''');
  }

  /// CREATE INDEX IF NOT EXISTS for every index.
  ///
  /// Kept apart from [_createTables] because indexes DO name columns, and on
  /// a legacy database those columns may not exist yet: idx_library_d_w
  /// indexes component_library(material_group, ...), and material_group is
  /// only added to that table by the v2 step. Running this before the
  /// column ladder throws "no such column: material_group" and takes the
  /// whole migration - and the app launch - down with it. [migrate]
  /// therefore calls it last, once every column is in place.
  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_weld_params_owner ON weld_params(owner_scope, updated_at DESC);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_library_d_w ON component_library(material_group, diameter_mm, wall_thickness_mm);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_segments_project ON segments(project_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_heat_project ON heat_photos(project_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_component_heats_project ON component_heats(project_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_component_heats_key ON component_heats(project_id, component_key);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_component_heats_segment ON component_heats(project_id, segment_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cut_marks_project ON cut_marks(project_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_weld_params_main ON weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_approved_weld_params_main ON approved_weld_params(base_material, diameter_mm, wall_thickness_mm, method);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tandem_tig_main ON tandem_tig_params(material_group, position, joint_type, land_mm, wall_thickness_mm);');
    // Same name and definition HydrotestDao used to create, so a device that
    // already has it keeps it.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hydrotest_created ON hydrotest_records(created_at DESC);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_iso_drawings_updated ON iso_drawings(updated_at);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_weld_history_weld ON weld_journal_history(weld_id, at);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_weld_repairs_weld ON weld_repairs(weld_id, seq);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_wps_library_no ON wps_library(wps_no, revision);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cert_confirmations_cert ON welder_cert_confirmations(certificate_id, date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_coupon_history_coupon ON weld_coupon_history(coupon_id, at);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_wps_versions_wps ON wps_versions(wps_id, valid_from);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_weld_quotes_updated ON weld_quotes(updated_at DESC);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_instruments_kind ON instruments(kind);');
  }

  static Future<void> _seedApprovedData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // ---- Tandem TIG (tanks)
    // Insert only if not exists (by id).
    Future<void> upsertTandem(Map<String, Object?> row) async {
      final id = row['id'] as String;
      final existing = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM tandem_tig_params WHERE id = ?', [id])) ??
          0;
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
      final existing = Sqflite.firstIntValue(await db.rawQuery(
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
      preset(
          id: 'APP_SS_AUTO_10_1_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 10.0,
          t: 1.0,
          amps: 30.0),
      preset(
          id: 'APP_SS_AUTO_10_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 10.0,
          t: 1.5,
          amps: 35.0),
      preset(
          id: 'APP_SS_AUTO_12_1_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 12.0,
          t: 1.0,
          amps: 32.0),
      preset(
          id: 'APP_SS_AUTO_12_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 12.0,
          t: 1.5,
          amps: 35.0),
      preset(
          id: 'APP_SS_AUTO_14_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 14.0,
          t: 1.5,
          amps: 37.0),
      preset(
          id: 'APP_SS_AUTO_16_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 16.0,
          t: 1.5,
          amps: 38.0),
      preset(
          id: 'APP_SS_AUTO_18_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 18.0,
          t: 1.5,
          amps: 40.0),
      preset(
          id: 'APP_SS_AUTO_20_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 20.0,
          t: 1.5,
          amps: 43.0),
      preset(
          id: 'APP_SS_AUTO_25_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 25.0,
          t: 1.5,
          amps: 48.0),
      preset(
          id: 'APP_SS_AUTO_25_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 25.0,
          t: 2.0,
          amps: 60.0,
          electrode: 2.4),
      // Stainless mid sizes
      preset(
          id: 'APP_SS_AUTO_32_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 32.0,
          t: 1.5,
          amps: 55.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_32_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 32.0,
          t: 2.0,
          amps: 65.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_38_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 38.0,
          t: 1.5,
          amps: 60.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_38_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 38.0,
          t: 2.0,
          amps: 70.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_40_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 40.0,
          t: 1.5,
          amps: 60.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_40_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 40.0,
          t: 2.0,
          amps: 70.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_50_1_5',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 50.0,
          t: 1.5,
          amps: 65.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_50_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 50.0,
          t: 2.0,
          amps: 75.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_60_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 60.0,
          t: 2.0,
          amps: 80.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_60_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 60.0,
          t: 3.0,
          amps: 90.0,
          electrode: 2.4),
      // Stainless large sizes
      preset(
          id: 'APP_SS_AUTO_76_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 76.0,
          t: 2.0,
          amps: 85.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_76_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 76.0,
          t: 3.0,
          amps: 100.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_88_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 88.0,
          t: 2.0,
          amps: 90.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_88_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 88.0,
          t: 3.0,
          amps: 105.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_100_2_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 100.0,
          t: 2.0,
          amps: 100.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_100_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 100.0,
          t: 3.0,
          amps: 120.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_114_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 114.0,
          t: 3.0,
          amps: 130.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_114_4_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 114.0,
          t: 4.0,
          amps: 150.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_139_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 139.0,
          t: 3.0,
          amps: 140.0,
          electrode: 2.4),
      preset(
          id: 'APP_SS_AUTO_139_4_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 139.0,
          t: 4.0,
          amps: 160.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_168_3_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 168.0,
          t: 3.0,
          amps: 150.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_168_4_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 168.0,
          t: 4.0,
          amps: 165.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_168_5_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 168.0,
          t: 5.0,
          amps: 190.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_219_4_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 219.0,
          t: 4.0,
          amps: 180.0,
          electrode: 3.2),
      preset(
          id: 'APP_SS_AUTO_219_5_0',
          method: 'TIG_AUTOGEN',
          material: 'SS',
          d: 219.0,
          t: 5.0,
          amps: 200.0,
          electrode: 3.2),
      // Carbon steel (wire) – typical sets
      preset(
          id: 'APP_CS_WIRE_60_3_0',
          method: 'TIG_WIRE',
          material: 'CS',
          d: 60.0,
          t: 3.0,
          amps: 120.0,
          electrode: 2.4),
      preset(
          id: 'APP_CS_WIRE_76_3_0',
          method: 'TIG_WIRE',
          material: 'CS',
          d: 76.0,
          t: 3.0,
          amps: 130.0,
          electrode: 2.4),
      preset(
          id: 'APP_CS_WIRE_88_4_0',
          method: 'TIG_WIRE',
          material: 'CS',
          d: 88.0,
          t: 4.0,
          amps: 150.0,
          electrode: 3.2),
      preset(
          id: 'APP_CS_WIRE_114_4_0',
          method: 'TIG_WIRE',
          material: 'CS',
          d: 114.0,
          t: 4.0,
          amps: 160.0,
          electrode: 3.2),
      preset(
          id: 'APP_CS_WIRE_168_5_0',
          method: 'TIG_WIRE',
          material: 'CS',
          d: 168.0,
          t: 5.0,
          amps: 200.0,
          electrode: 3.2),
    ];

    // Expanded approved presets grouped by material so the app can filter by
    // welded material and avoid mixing amperage recommendations.
    final ssAutogen = <Map<String, double>>[
      {'d': 6, 't': 1.0, 'a': 20, 'e': 1.0},
      {'d': 8, 't': 1.0, 'a': 24, 'e': 1.0},
      {'d': 12, 't': 1.65, 'a': 34, 'e': 1.6},
      {'d': 22, 't': 1.5, 'a': 45, 'e': 1.6},
      {'d': 28, 't': 2.0, 'a': 63, 'e': 2.4},
      {'d': 35, 't': 2.0, 'a': 68, 'e': 2.4},
      {'d': 45, 't': 2.0, 'a': 73, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 90, 'e': 2.4},
      {'d': 63, 't': 2.0, 'a': 82, 'e': 2.4},
      {'d': 63, 't': 3.0, 'a': 92, 'e': 2.4},
      {'d': 70, 't': 2.0, 'a': 85, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 80, 't': 3.0, 'a': 102, 'e': 2.4},
      {'d': 159, 't': 3.0, 'a': 145, 'e': 3.2},
      {'d': 159, 't': 4.0, 'a': 165, 'e': 3.2},
      {'d': 273, 't': 5.0, 'a': 210, 'e': 4.0},
      {'d': 273, 't': 6.0, 'a': 230, 'e': 4.0},
      {'d': 323, 't': 6.0, 'a': 240, 'e': 4.0},
    ];
    for (final r in ssAutogen) {
      approvedList.add(preset(
        id: 'APP_SS_AUTO_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_AUTOGEN',
        material: 'SS',
        d: r['d']!,
        t: r['t']!,
        amps: r['a']!,
        electrode: r['e']!,
        torchGas: r['d']! <= 25 ? 7 : 8.0,
        purge: r['d']! <= 50 ? 10 : 15,
      ));
    }

    final ssWire = <Map<String, double>>[
      {'d': 20, 't': 2.0, 'a': 75, 'e': 2.4},
      {'d': 25, 't': 2.0, 'a': 80, 'e': 2.4},
      {'d': 32, 't': 2.0, 'a': 85, 'e': 2.4},
      {'d': 32, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 38, 't': 2.0, 'a': 90, 'e': 2.4},
      {'d': 38, 't': 3.0, 'a': 102, 'e': 2.4},
      {'d': 40, 't': 2.0, 'a': 90, 'e': 2.4},
      {'d': 40, 't': 3.0, 'a': 98, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 105, 'e': 2.4},
      {'d': 60, 't': 3.0, 'a': 110, 'e': 2.4},
      {'d': 63, 't': 3.0, 'a': 112, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 114, 'e': 2.4},
      {'d': 76, 't': 3.0, 'a': 118, 'e': 2.4},
      {'d': 80, 't': 3.0, 'a': 120, 'e': 2.4},
      {'d': 88, 't': 4.0, 'a': 130, 'e': 3.2},
      {'d': 100, 't': 4.0, 'a': 135, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 145, 'e': 3.2},
      {'d': 139, 't': 4.0, 'a': 155, 'e': 3.2},
      {'d': 159, 't': 5.0, 'a': 170, 'e': 3.2},
      {'d': 168, 't': 5.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 273, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 323, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 273, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 323, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 5.0, 'a': 220, 'e': 3.2},
      {'d': 273, 't': 5.0, 'a': 220, 'e': 3.2},
      {'d': 323, 't': 5.0, 'a': 220, 'e': 3.2},
      {'d': 219, 't': 6.0, 'a': 310, 'e': 4.0},
      {'d': 273, 't': 6.0, 'a': 310, 'e': 4.0},
      {'d': 323, 't': 6.0, 'a': 310, 'e': 4.0},
    ];
    for (final r in ssWire) {
      approvedList.add(preset(
        id: 'APP_SS_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE',
        material: 'SS',
        d: r['d']!,
        t: r['t']!,
        amps: r['a']!,
        electrode: r['e']!,
        torchGas: 9.0,
        purge: 18.0,
      ));
    }

    final csWire = <Map<String, double>>[
      {'d': 40, 't': 3.0, 'a': 110, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 115, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 125, 'e': 2.4},
      {'d': 100, 't': 4.0, 'a': 155, 'e': 3.2},
      {'d': 139, 't': 5.0, 'a': 180, 'e': 3.2},
      {'d': 159, 't': 5.0, 'a': 190, 'e': 3.2},
      {'d': 219, 't': 6.0, 'a': 220, 'e': 4.0},
      {'d': 273, 't': 6.0, 'a': 240, 'e': 4.0},
      {'d': 323, 't': 8.0, 'a': 260, 'e': 4.0},
      {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 273, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 323, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 273, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 323, 't': 3.0, 'a': 130, 'e': 2.4},
      {'d': 168, 't': 6.0, 'a': 280, 'e': 4.0},
      {'d': 219, 't': 8.0, 'a': 330, 'e': 4.8},
      {'d': 273, 't': 8.0, 'a': 330, 'e': 4.8},
      {'d': 323, 't': 8.0, 'a': 330, 'e': 4.8},
    ];
    for (final r in csWire) {
      approvedList.add(preset(
        id: 'APP_CS_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE',
        material: 'CS',
        d: r['d']!,
        t: r['t']!,
        amps: r['a']!,
        electrode: r['e']!,
        torchGas: 8.0,
        purge: 0.0,
      ));
    }

    final duplexAuto = <Map<String, double>>[
      {'d': 38, 't': 1.5, 'a': 55, 'e': 2.4},
      {'d': 40, 't': 2.0, 'a': 65, 'e': 2.4},
      {'d': 50, 't': 2.0, 'a': 70, 'e': 2.4},
      {'d': 60, 't': 3.0, 'a': 95, 'e': 2.4},
      {'d': 70, 't': 3.0, 'a': 100, 'e': 2.4},
      {'d': 76, 't': 3.0, 'a': 105, 'e': 2.4},
      {'d': 88, 't': 3.0, 'a': 110, 'e': 2.4},
      {'d': 100, 't': 4.0, 'a': 120, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 145, 'e': 3.2},
      {'d': 139, 't': 4.0, 'a': 150, 'e': 3.2},
      {'d': 159, 't': 5.0, 'a': 160, 'e': 3.2},
      {'d': 168, 't': 5.0, 'a': 170, 'e': 3.2},
    ];
    for (final r in duplexAuto) {
      approvedList.add(preset(
        id: 'APP_DUPLEX_AUTO_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_AUTOGEN',
        material: 'DUPLEX',
        d: r['d']!,
        t: r['t']!,
        amps: r['a']!,
        electrode: r['e']!,
        torchGas: 9.0,
        purge: 18.0,
      ));
    }

    final alWire = <Map<String, double>>[
      {'d': 20, 't': 2.0, 'a': 70, 'e': 2.4},
      {'d': 25, 't': 2.0, 'a': 75, 'e': 2.4},
      {'d': 32, 't': 3.0, 'a': 90, 'e': 2.4},
      {'d': 40, 't': 3.0, 'a': 100, 'e': 2.4},
      {'d': 50, 't': 3.0, 'a': 110, 'e': 2.4},
      {'d': 60, 't': 4.0, 'a': 130, 'e': 3.2},
      {'d': 76, 't': 4.0, 'a': 140, 'e': 3.2},
      {'d': 88, 't': 5.0, 'a': 160, 'e': 3.2},
      {'d': 100, 't': 5.0, 'a': 170, 'e': 3.2},
      {'d': 114, 't': 3.0, 'a': 150, 'e': 3.2},
      {'d': 168, 't': 3.0, 'a': 150, 'e': 3.2},
      {'d': 219, 't': 3.0, 'a': 150, 'e': 3.2},
      {'d': 114, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 168, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 219, 't': 4.0, 'a': 180, 'e': 3.2},
      {'d': 114, 't': 6.0, 'a': 260, 'e': 4.0},
      {'d': 168, 't': 6.0, 'a': 260, 'e': 4.0},
      {'d': 219, 't': 6.0, 'a': 260, 'e': 4.0},
    ];
    for (final r in alWire) {
      approvedList.add(preset(
        id: 'APP_AL_WIRE_${r['d']!.toInt()}_${(r['t']! * 100).round()}',
        method: 'TIG_WIRE',
        material: 'AL',
        d: r['d']!,
        t: r['t']!,
        amps: r['a']!,
        electrode: r['e']!,
        torchGas: 11.0,
        purge: 0.0,
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
      final existing = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM approved_weld_params WHERE id = ?',
              [id])) ??
          0;
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
      'note': 'Seed AMP — wartości startowe do edycji w bibliotece parametrów.',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Adds [column] to [table] unless it is already there.
  ///
  /// Returns false when [table] does not exist. That case has to be handled
  /// explicitly: `PRAGMA table_info` on an unknown table returns an EMPTY
  /// result set rather than an error, so the old code read "no such column",
  /// issued `ALTER TABLE <missing> ADD COLUMN ...`, and threw "no such
  /// table" — aborting onUpgrade and leaving openDatabase, and therefore the
  /// whole app, unable to start. [migrate] now runs [createSchema] first so
  /// this should not trigger, but a column added here for a table that
  /// [createSchema] does not define must degrade to a no-op, never to a brick.
  static Future<bool> _ensureColumn(
      Database db, String table, String column, String sqlType) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
      [table],
    );
    if (tables.isEmpty) return false;

    final info = await db.rawQuery('PRAGMA table_info($table);');
    final exists = info.any((r) => r['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $sqlType;');
    }
    return true;
  }
}
