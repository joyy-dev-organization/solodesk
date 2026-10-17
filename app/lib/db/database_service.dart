import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static const int currentSchemaVersion = 2;

  final Database _db;

  DatabaseService._(this._db);

  Database get db => _db;

  /// Open default desktop database in user application-support directory
  static Future<DatabaseService> openDefault() async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'solodesk'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'solodesk.db');
    return openPath(dbPath);
  }

  /// Open database at a specific file path (used for restart persistence tests)
  static Future<DatabaseService> openPath(String path, {int version = currentSchemaVersion}) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        singleInstance: path != inMemoryDatabasePath,
        version: version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
          if (path != inMemoryDatabasePath) {
            await db.execute('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA busy_timeout = 5000;');
          }
        },
        onDowngrade: onDatabaseDowngradeDelete,
        onCreate: (db, version) async {
          await _applyMigrations(db, 0, version);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _applyMigrations(db, oldVersion, newVersion);
        },
        onOpen: (db) async {
          await _ensureTriggers(db);
        },
      ),
    );
    return DatabaseService._(db);
  }

  /// Open an isolated in-memory database for unit testing
  static Future<DatabaseService> inMemory() async {
    return openPath(inMemoryDatabasePath);
  }

  Future<void> close() async {
    await _db.close();
  }

  static Future<void> _applyMigrations(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      if (v == 1) {
        await _applyV1(db);
      }
      if (v == 2) {
        await _applyV2(db);
      }
    }
  }

  static Future<void> _applyV1(DatabaseExecutor db) async {
    // 1. Schema migrations audit table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        applied_at TEXT NOT NULL,
        description TEXT NOT NULL
      );
    ''');

    // 2. Service Preferences
    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_preferences (
        id TEXT PRIMARY KEY NOT NULL,
        niches_json TEXT NOT NULL DEFAULT '["Design & branding","Writing & content"]',
        default_currency TEXT NOT NULL CHECK(length(default_currency) = 3),
        business_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    final prefNow = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert('''
      INSERT INTO service_preferences (id, niches_json, default_currency, business_name, created_at, updated_at)
      VALUES ('default', '["Design & branding","Writing & content"]', 'NGN', 'ladydiamond · Independent freelancer', ?, ?)
    ''', [prefNow, prefNow]);

    // 3. Clients
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        initials TEXT NOT NULL,
        company TEXT,
        email TEXT,
        notes TEXT,
        is_synthetic INTEGER NOT NULL DEFAULT 0 CHECK(is_synthetic IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_clients_synthetic ON clients(is_synthetic);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_clients_name ON clients(name);');

    // 4. Projects
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY NOT NULL,
        client_id TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        niche TEXT NOT NULL,
        currency TEXT NOT NULL CHECK(length(currency) = 3),
        budget_minor_units INTEGER NOT NULL DEFAULT 0 CHECK(budget_minor_units >= 0),
        status TEXT NOT NULL CHECK(status IN ('lead', 'drafting', 'active', 'completed', 'archived')),
        is_synthetic INTEGER NOT NULL DEFAULT 0 CHECK(is_synthetic IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_projects_client_id ON projects(client_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_projects_synthetic ON projects(is_synthetic);');

    // 5. Scope Versions (Immutable once approved)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scope_versions (
        id TEXT PRIMARY KEY NOT NULL,
        project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        version_number INTEGER NOT NULL CHECK(version_number >= 1),
        title TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('draft', 'approved')),
        approved_at TEXT,
        notes TEXT,
        is_synthetic INTEGER NOT NULL DEFAULT 0 CHECK(is_synthetic IN (0, 1)),
        created_at TEXT NOT NULL,
        UNIQUE(project_id, version_number)
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_scope_versions_project ON scope_versions(project_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_scope_versions_status ON scope_versions(status);');

    // 6. Scope Items
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scope_items (
        id TEXT PRIMARY KEY NOT NULL,
        scope_version_id TEXT NOT NULL REFERENCES scope_versions(id) ON DELETE CASCADE,
        category TEXT NOT NULL CHECK(category IN ('included', 'excluded', 'allowance')),
        description TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_synthetic INTEGER NOT NULL DEFAULT 0 CHECK(is_synthetic IN (0, 1))
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_scope_items_version ON scope_items(scope_version_id);');

    // 7. Immutability Triggers for Approved Scopes (Real records)
    await _ensureTriggers(db);

    // Record migration in audit log
    await db.rawInsert('''
      INSERT INTO schema_migrations (version, applied_at, description)
      VALUES (?, ?, ?)
    ''', [
      1,
      DateTime.now().toUtc().toIso8601String(),
      'M2 initial schema: preferences, clients, projects, scope_versions, scope_items, immutability triggers'
    ]);
  }

  static Future<void> _applyV2(DatabaseExecutor db) async {
    // 6. Invoices table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY NOT NULL,
        client_id TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
        project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
        invoice_number TEXT NOT NULL,
        amount_minor_units INTEGER NOT NULL CHECK(amount_minor_units >= 0),
        currency TEXT NOT NULL CHECK(length(currency) = 3),
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('draft', 'unpaid', 'paid', 'cancelled')),
        paid_at TEXT,
        notes TEXT,
        is_synthetic INTEGER NOT NULL DEFAULT 0 CHECK(is_synthetic IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_client_id ON invoices(client_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_project_id ON invoices(project_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_due_date ON invoices(due_date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_synthetic ON invoices(is_synthetic);');

    // Record migration in audit log
    await db.rawInsert('''
      INSERT INTO schema_migrations (version, applied_at, description)
      VALUES (?, ?, ?)
    ''', [
      2,
      DateTime.now().toUtc().toIso8601String(),
      'M5 schema: invoices table with client/project FKs, status, minor units, calendar dates'
    ]);
  }

  /// Ensures scope immutability triggers exist and are up to date on database open.
  /// Drops and recreates the triggers so existing databases seamlessly adopt fixes.
  static Future<void> _ensureTriggers(DatabaseExecutor db) async {
    // 1. scope_versions update trigger: prevent modifying approved real versions
    await db.execute('DROP TRIGGER IF EXISTS trg_scope_versions_prevent_update_when_approved;');
    await db.execute('''
      CREATE TRIGGER trg_scope_versions_prevent_update_when_approved
      BEFORE UPDATE ON scope_versions
      FOR EACH ROW
      WHEN OLD.status = 'approved' AND OLD.is_synthetic = 0
      BEGIN
        SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Approved scope versions cannot be modified.');
      END;
    ''');

    // 2. scope_versions delete trigger: prevent deleting approved real versions
    await db.execute('DROP TRIGGER IF EXISTS trg_scope_versions_prevent_delete_when_approved;');
    await db.execute('''
      CREATE TRIGGER trg_scope_versions_prevent_delete_when_approved
      BEFORE DELETE ON scope_versions
      FOR EACH ROW
      WHEN OLD.status = 'approved' AND OLD.is_synthetic = 0
      BEGIN
        SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Approved scope versions cannot be deleted.');
      END;
    ''');

    // 3. scope_items update trigger: prevent updating items belonging to approved real versions
    await db.execute('DROP TRIGGER IF EXISTS trg_scope_items_prevent_update_when_approved;');
    await db.execute('''
      CREATE TRIGGER trg_scope_items_prevent_update_when_approved
      BEFORE UPDATE ON scope_items
      FOR EACH ROW
      WHEN (SELECT status FROM scope_versions WHERE id = OLD.scope_version_id) = 'approved'
        AND (SELECT is_synthetic FROM scope_versions WHERE id = OLD.scope_version_id) = 0
      BEGIN
        SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Cannot modify items under an approved scope version.');
      END;
    ''');

    // 4. scope_items delete trigger: prevent deleting items belonging to approved real versions
    await db.execute('DROP TRIGGER IF EXISTS trg_scope_items_prevent_delete_when_approved;');
    await db.execute('''
      CREATE TRIGGER trg_scope_items_prevent_delete_when_approved
      BEFORE DELETE ON scope_items
      FOR EACH ROW
      WHEN (SELECT status FROM scope_versions WHERE id = OLD.scope_version_id) = 'approved'
        AND (SELECT is_synthetic FROM scope_versions WHERE id = OLD.scope_version_id) = 0
      BEGIN
        SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Cannot delete items under an approved scope version.');
      END;
    ''');

    // 5. scope_items insert trigger: prevent inserting items into approved real versions
    await db.execute('DROP TRIGGER IF EXISTS trg_scope_items_prevent_insert_when_approved;');
    await db.execute('''
      CREATE TRIGGER trg_scope_items_prevent_insert_when_approved
      BEFORE INSERT ON scope_items
      FOR EACH ROW
      WHEN (SELECT status FROM scope_versions WHERE id = NEW.scope_version_id) = 'approved'
        AND (SELECT is_synthetic FROM scope_versions WHERE id = NEW.scope_version_id) = 0
      BEGIN
        SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Cannot add items to an already approved scope version.');
      END;
    ''');
  }
}
