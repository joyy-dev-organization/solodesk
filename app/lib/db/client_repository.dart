import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/client.dart';

abstract class IClientRepository {
  Future<List<Client>> getClients({bool includeSynthetic = true});
  Future<Client?> getClientById(String id);
  Future<void> createClient(Client client);
  Future<void> updateClient(Client client);
  Future<void> deleteClient(String id);
}

class ClientRepository implements IClientRepository {
  final Database db;

  ClientRepository(this.db);

  @override
  Future<List<Client>> getClients({bool includeSynthetic = true}) async {
    final rows = await db.query(
      'clients',
      where: includeSynthetic ? null : 'is_synthetic = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(Client.fromDbMap).toList();
  }

  @override
  Future<Client?> getClientById(String id) async {
    final rows = await db.query(
      'clients',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Client.fromDbMap(rows.first);
  }

  @override
  Future<void> createClient(Client client) async {
    await db.insert('clients', client.toDbMap());
  }

  @override
  Future<void> updateClient(Client client) async {
    await db.update(
      'clients',
      client.toDbMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  @override
  Future<void> deleteClient(String id) async {
    await db.delete(
      'clients',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
