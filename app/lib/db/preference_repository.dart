import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/service_preference.dart';

abstract class IPreferenceRepository {
  Future<ServicePreference> getPreferences();
  Future<void> savePreferences(ServicePreference preferences);
}

class PreferenceRepository implements IPreferenceRepository {
  final Database db;

  PreferenceRepository(this.db);

  @override
  Future<ServicePreference> getPreferences() async {
    final rows = await db.query(
      'service_preferences',
      where: 'id = ?',
      whereArgs: ['default'],
    );
    if (rows.isEmpty) {
      final initial = ServicePreference.initial();
      await db.insert(
        'service_preferences',
        initial.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return initial;
    }
    return ServicePreference.fromDbMap(rows.first);
  }

  @override
  Future<void> savePreferences(ServicePreference preferences) async {
    await db.insert(
      'service_preferences',
      preferences.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
