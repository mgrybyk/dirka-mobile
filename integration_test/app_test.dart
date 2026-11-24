import 'dart:io';
import 'dart:math';

import 'package:dirka_mobile/app_info/android_app_info.dart';
import 'package:dirka_mobile/clients/client_repository.dart';
import 'package:dirka_mobile/main.dart';
import 'package:dirka_mobile/tunnel/android_tunnel_runtime.dart';
import 'package:dirka_mobile/tunnel/native_engine_info.dart';
import 'package:dirka_mobile/tunnel/tunnel_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads package and pinned engine metadata on Android', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const info = AndroidAppInfo();
      final version = await info.loadAppVersion();
      expect(version.version, isNotEmpty);
      expect(int.tryParse(version.buildNumber), greaterThan(0));
      final engine = await info.loadEngineInfo();
      expect(engine.engineVersion, isNotEmpty);
      expect(engine.protocolVersion, greaterThan(0));
      expect(engine.upstreamRevision, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(engine.upstreamLicense, contains('MIT License'));
      final notices = await NativeEngineInfo.loadDependencyLicenses();
      expect(
        notices.expand((notice) => notice.packages),
        contains(startsWith('ring ')),
      );
    });
  });

  testWidgets('launches Dirka on Android', (tester) async {
    await tester.pumpWidget(const DirkaApp());
    expect(find.text('Dirka'), findsOneWidget);
  });

  testWidgets('round trips saved clients through secure Android storage', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: false,
          storageNamespace: 'dirka_integration',
        ),
      );
      const repository = SecureClientRepository(storage: storage);
      addTearDown(storage.deleteAll);
      final source = 'N_T_ROUTE_ID=device-test';
      await repository.save(
        StoredClients(
          nextId: 4,
          clients: [
            StoredClient(id: 1, source: source),
            StoredClient(id: 3, source: source),
          ],
        ),
      );
      final restored = await repository.load();
      expect(restored.nextId, 4);
      expect(restored.clients.map((entry) => entry.id), [1, 3]);
      expect(restored.clients.map((entry) => entry.source), [source, source]);
    });
  });

  testWidgets('the Android service reports an occupied port', (tester) async {
    await tester.runAsync(() async {
      const runtime = AndroidTunnelRuntime(requestNotifications: false);
      const id = 900001;
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socket.close);
      addTearDown(() async {
        await runtime.stop(id);
        await runtime.clearStopped(id);
      });
      await runtime.start(id, _localConfig(socket.port));
      final failed = await runtime.states
          .firstWhere((states) => states[id]?.status == TunnelStatus.stopped)
          .timeout(const Duration(seconds: 10));
      expect(failed[id]?.error, contains('127.0.0.1:${socket.port}'));
      expect(failed[id]?.active, isFalse);
    });
  });

  testWidgets(
    'tunnel ownership survives Dart reattachment and releases its port',
    (tester) async {
      await tester.runAsync(() async {
        const runtime = AndroidTunnelRuntime(requestNotifications: false);
        const id = 900002;
        final listener = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = listener.port;
        await listener.close();
        addTearDown(() => runtime.stop(id));

        await runtime.start(id, _localConfig(port));
        expect(
          (await runtime.states.first.timeout(
            const Duration(seconds: 5),
          ))[id]?.active,
          isTrue,
        );
        final deadline = Stopwatch()..start();
        while (true) {
          try {
            final socket = await Socket.connect(
              InternetAddress.loopbackIPv4,
              port,
            );
            socket.destroy();
            break;
          } on SocketException {
            if (deadline.elapsed > const Duration(seconds: 5)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        final reattached = await runtime.states.first.timeout(
          const Duration(seconds: 5),
        );
        expect(reattached[id]?.active, isTrue);

        const conflictId = 900003;
        addTearDown(() async {
          await runtime.stop(conflictId);
          await runtime.clearStopped(conflictId);
        });
        await runtime.start(conflictId, _localConfig(port));
        final conflict = await runtime.states
            .firstWhere(
              (states) => states[conflictId]?.status == TunnelStatus.stopped,
            )
            .timeout(const Duration(seconds: 5));
        expect(conflict[conflictId]?.error, contains('127.0.0.1:$port'));
        expect(conflict[id]?.active, isTrue);

        await runtime.stop(id);
        await runtime.stop(id);
        await runtime.states
            .firstWhere((states) => !states.containsKey(id))
            .timeout(const Duration(seconds: 10));
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        await rebound.close();
      });
    },
  );
}

TunnelConfig _localConfig(int port) {
  final random = Random.secure();
  return TunnelConfig(
    relayHost: '127.0.0.1',
    relayPort: 1,
    route: 'dirka-device-test',
    key: List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join(),
    bindHost: '127.0.0.1',
    ports: [port],
    tls: false,
  );
}
