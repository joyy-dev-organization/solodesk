import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/scope_version.dart';
import '../models/scope_item.dart';

abstract class IScopeRepository {
  Future<List<ScopeVersion>> getVersionsForProject(String projectId);
  Future<ScopeVersionWithItems?> getVersionWithItems(String versionId);
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId);
  Future<ScopeVersionWithItems> createDraft({
    required String projectId,
    required String title,
    String? notes,
    List<ScopeItem> items = const [],
    bool isSynthetic = false,
  });
  Future<void> updateDraft({
    required ScopeVersion version,
    required List<ScopeItem> items,
  });
  Future<ScopeVersionWithItems> approveVersion(String versionId);
  Future<ScopeVersionWithItems> createRevisionFromApproved(
    String approvedVersionId, {
    required String newTitle,
    String? notes,
  });
  Future<void> deleteDraft(String versionId);
}

class ScopeRepository implements IScopeRepository {
  final Database db;
  final Uuid uuid;

  ScopeRepository(this.db, {this.uuid = const Uuid()});

  @override
  Future<List<ScopeVersion>> getVersionsForProject(String projectId) async {
    final rows = await db.query(
      'scope_versions',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'version_number DESC',
    );
    return rows.map(ScopeVersion.fromDbMap).toList();
  }

  @override
  Future<ScopeVersionWithItems?> getVersionWithItems(String versionId) async {
    final vRows = await db.query(
      'scope_versions',
      where: 'id = ?',
      whereArgs: [versionId],
    );
    if (vRows.isEmpty) return null;
    final version = ScopeVersion.fromDbMap(vRows.first);

    final iRows = await db.query(
      'scope_items',
      where: 'scope_version_id = ?',
      whereArgs: [versionId],
      orderBy: 'sort_order ASC',
    );
    final items = iRows.map(ScopeItem.fromDbMap).toList();
    return ScopeVersionWithItems(version: version, items: items);
  }

  @override
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId) async {
    final vRows = await db.query(
      'scope_versions',
      where: 'project_id = ? AND status = ?',
      whereArgs: [projectId, 'approved'],
      orderBy: 'version_number DESC',
      limit: 1,
    );
    if (vRows.isEmpty) return null;
    final version = ScopeVersion.fromDbMap(vRows.first);

    final iRows = await db.query(
      'scope_items',
      where: 'scope_version_id = ?',
      whereArgs: [version.id],
      orderBy: 'sort_order ASC',
    );
    final items = iRows.map(ScopeItem.fromDbMap).toList();
    return ScopeVersionWithItems(version: version, items: items);
  }

  @override
  Future<ScopeVersionWithItems> createDraft({
    required String projectId,
    required String title,
    String? notes,
    List<ScopeItem> items = const [],
    bool isSynthetic = false,
  }) async {
    return await db.transaction((txn) async {
      final maxVerRows = await txn.rawQuery(
        'SELECT MAX(version_number) as max_v FROM scope_versions WHERE project_id = ?',
        [projectId],
      );
      final maxV = maxVerRows.first['max_v'] as int?;
      final nextVersion = (maxV ?? 0) + 1;

      final versionId = uuid.v4();
      final now = DateTime.now().toUtc();
      final version = ScopeVersion(
        id: versionId,
        projectId: projectId,
        versionNumber: nextVersion,
        title: title,
        status: 'draft',
        approvedAt: null,
        notes: notes,
        isSynthetic: isSynthetic,
        createdAt: now,
      );
      await txn.insert('scope_versions', version.toDbMap());

      final savedItems = <ScopeItem>[];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final newItem = ScopeItem(
          id: item.id.isNotEmpty ? item.id : uuid.v4(),
          scopeVersionId: versionId,
          category: item.category,
          description: item.description,
          sortOrder: i,
          isSynthetic: isSynthetic,
        );
        await txn.insert('scope_items', newItem.toDbMap());
        savedItems.add(newItem);
      }

      return ScopeVersionWithItems(version: version, items: savedItems);
    });
  }

  @override
  Future<void> updateDraft({
    required ScopeVersion version,
    required List<ScopeItem> items,
  }) async {
    await db.transaction((txn) async {
      final rows = await txn.query('scope_versions', where: 'id = ?', whereArgs: [version.id]);
      if (rows.isEmpty) throw StateError('ScopeVersion ${version.id} not found');
      final current = ScopeVersion.fromDbMap(rows.first);
      if (current.isApproved) {
        throw StateError('Cannot modify an approved scope version');
      }

      await txn.update(
        'scope_versions',
        version.toDbMap(),
        where: 'id = ?',
        whereArgs: [version.id],
      );

      // Re-save items
      await txn.delete('scope_items', where: 'scope_version_id = ?', whereArgs: [version.id]);
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final toSave = ScopeItem(
          id: item.id.isNotEmpty ? item.id : uuid.v4(),
          scopeVersionId: version.id,
          category: item.category,
          description: item.description,
          sortOrder: i,
          isSynthetic: version.isSynthetic,
        );
        await txn.insert('scope_items', toSave.toDbMap());
      }
    });
  }

  @override
  Future<ScopeVersionWithItems> approveVersion(String versionId) async {
    return await db.transaction((txn) async {
      final rows = await txn.query('scope_versions', where: 'id = ?', whereArgs: [versionId]);
      if (rows.isEmpty) throw StateError('ScopeVersion $versionId not found');
      final current = ScopeVersion.fromDbMap(rows.first);
      if (current.isApproved) {
        throw StateError('ScopeVersion $versionId is already approved');
      }

      final itemRows = await txn.query('scope_items', where: 'scope_version_id = ?', whereArgs: [versionId]);
      if (itemRows.isEmpty) {
        throw StateError('Cannot approve a scope version without deliverables');
      }

      final now = DateTime.now().toUtc();
      await txn.update(
        'scope_versions',
        {
          'status': 'approved',
          'approved_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [versionId],
      );

      final approvedVersion = current.copyWith(
        status: 'approved',
        approvedAt: now,
      );
      final items = itemRows.map(ScopeItem.fromDbMap).toList();
      return ScopeVersionWithItems(version: approvedVersion, items: items);
    });
  }

  @override
  Future<ScopeVersionWithItems> createRevisionFromApproved(
    String approvedVersionId, {
    required String newTitle,
    String? notes,
  }) async {
    return await db.transaction((txn) async {
      final rows = await txn.query('scope_versions', where: 'id = ?', whereArgs: [approvedVersionId]);
      if (rows.isEmpty) throw StateError('Source approved version not found');
      final approved = ScopeVersion.fromDbMap(rows.first);
      if (!approved.isApproved) {
        throw StateError('Can only branch revisions from an approved scope version');
      }

      final maxVerRows = await txn.rawQuery(
        'SELECT MAX(version_number) as max_v FROM scope_versions WHERE project_id = ?',
        [approved.projectId],
      );
      final maxV = maxVerRows.first['max_v'] as int?;
      final nextVersion = (maxV ?? approved.versionNumber) + 1;

      final newVersionId = uuid.v4();
      final now = DateTime.now().toUtc();
      final newDraft = ScopeVersion(
        id: newVersionId,
        projectId: approved.projectId,
        versionNumber: nextVersion,
        title: newTitle,
        status: 'draft',
        approvedAt: null,
        notes: notes,
        isSynthetic: approved.isSynthetic,
        createdAt: now,
      );
      await txn.insert('scope_versions', newDraft.toDbMap());

      final itemsToClone = await txn.query(
        'scope_items',
        where: 'scope_version_id = ?',
        whereArgs: [approvedVersionId],
        orderBy: 'sort_order ASC',
      );
      final clonedItems = <ScopeItem>[];
      for (final row in itemsToClone) {
        final orig = ScopeItem.fromDbMap(row);
        final cloned = ScopeItem(
          id: uuid.v4(),
          scopeVersionId: newVersionId,
          category: orig.category,
          description: orig.description,
          sortOrder: orig.sortOrder,
          isSynthetic: orig.isSynthetic,
        );
        await txn.insert('scope_items', cloned.toDbMap());
        clonedItems.add(cloned);
      }

      return ScopeVersionWithItems(version: newDraft, items: clonedItems);
    });
  }

  @override
  Future<void> deleteDraft(String versionId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('scope_versions', where: 'id = ?', whereArgs: [versionId]);
      if (rows.isEmpty) return;
      final current = ScopeVersion.fromDbMap(rows.first);
      if (current.isApproved) {
        throw StateError('IMMUTABILITY_VIOLATION: Cannot delete an approved scope version');
      }
      await txn.delete('scope_versions', where: 'id = ?', whereArgs: [versionId]);
    });
  }
}
