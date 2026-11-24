import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class StoredClient {
  const StoredClient({required this.id, required this.source});

  final int id;
  final String source;
}

final class StoredClients {
  const StoredClients({this.nextId = 1, this.clients = const []});

  final int nextId;
  final List<StoredClient> clients;
}

abstract interface class ClientRepository {
  Future<StoredClients> load();
  Future<void> save(StoredClients clients);
}

final class SecureClientRepository implements ClientRepository {
  const SecureClientRepository({
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false, storageNamespace: 'dirka'),
    ),
  });

  static const _key = 'saved_clients_v1';
  final FlutterSecureStorage storage;

  @override
  Future<StoredClients> load() async {
    final text = await storage.read(key: _key);
    if (text == null) return const StoredClients();
    final stored = jsonDecode(text) as Map<String, Object?>;
    final nextId = stored['nextId'] as int;
    final ids = <int>{};
    final clients = [
      for (final row in stored['clients'] as List<Object?>)
        StoredClient(
          id: (row as Map<String, Object?>)['id'] as int,
          source: row['source'] as String,
        ),
    ];
    if (nextId < 1 ||
        clients.any((c) => c.id < 1 || c.id >= nextId || !ids.add(c.id))) {
      throw const FormatException('Invalid saved client identifiers.');
    }
    return StoredClients(nextId: nextId, clients: List.unmodifiable(clients));
  }

  @override
  Future<void> save(StoredClients clients) => storage.write(
    key: _key,
    value: jsonEncode({
      'nextId': clients.nextId,
      'clients': [
        for (final client in clients.clients)
          {'id': client.id, 'source': client.source},
      ],
    }),
  );
}
