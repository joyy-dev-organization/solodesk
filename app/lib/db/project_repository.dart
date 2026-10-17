import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/project.dart';

abstract class IProjectRepository {
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true});
  Future<Project?> getProjectById(String id);
  Future<void> createProject(Project project);
  Future<void> updateProject(Project project);
  Future<void> deleteProject(String id);
}

class ProjectRepository implements IProjectRepository {
  final Database db;

  ProjectRepository(this.db);

  @override
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true}) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (clientId != null) {
      whereClauses.add('client_id = ?');
      whereArgs.add(clientId);
    }
    if (!includeSynthetic) {
      whereClauses.add('is_synthetic = 0');
    }

    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');

    final rows = await db.query(
      'projects',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows.map(Project.fromDbMap).toList();
  }

  @override
  Future<Project?> getProjectById(String id) async {
    final rows = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Project.fromDbMap(rows.first);
  }

  @override
  Future<void> createProject(Project project) async {
    await db.insert('projects', project.toDbMap());
  }

  @override
  Future<void> updateProject(Project project) async {
    await db.update(
      'projects',
      project.toDbMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  @override
  Future<void> deleteProject(String id) async {
    await db.delete(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
