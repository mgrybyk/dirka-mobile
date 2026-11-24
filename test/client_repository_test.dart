import 'package:dirka_mobile/clients/client_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'round trips stable IDs and keeps the allocation counter on deletion',
    () async {
      const writer = SecureClientRepository();
      expect((await writer.load()).clients, isEmpty);

      const source = 'N_T_ROUTE_ID=test-route';
      await writer.save(
        const StoredClients(
          nextId: 8,
          clients: [
            StoredClient(id: 3, source: source),
            StoredClient(id: 7, source: source),
          ],
        ),
      );

      const reader = SecureClientRepository();
      final snapshot = await reader.load();
      expect(snapshot.nextId, 8);
      expect(snapshot.clients.map((entry) => (entry.id, entry.source)), [
        (3, source),
        (7, source),
      ]);
      await reader.save(StoredClients(nextId: snapshot.nextId));
      final afterDeletion = await writer.load();
      expect(afterDeletion.nextId, 8);
      expect(afterDeletion.clients, isEmpty);
    },
  );
}
