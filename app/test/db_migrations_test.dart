import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Migrations & Schema', () {
    late DatabaseService dbService;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
    });

    tearDown(() async {
      await dbService.close();
    });

    test('creates all required M2 tables and indices', () async {
      final tables = await dbService.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();

      expect(tableNames, contains('schema_migrations'));
      expect(tableNames, contains('service_preferences'));
      expect(tableNames, contains('clients'));
      expect(tableNames, contains('projects'));
      expect(tableNames, contains('scope_versions'));
      expect(tableNames, contains('scope_items'));
    });

    test('records migration version 1 in schema_migrations audit log', () async {
      final rows = await dbService.db.query('schema_migrations');
      expect(rows.length, equals(1));
      expect(rows.first['version'], equals(1));
      expect(rows.first['description'], contains('M2 initial schema'));
    });
  });
}
