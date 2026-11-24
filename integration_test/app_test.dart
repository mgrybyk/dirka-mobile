import 'dart:io';
import 'dart:math';

import 'package:dirka_mobile/main.dart';
import 'package:dirka_mobile/tunnel/native_tunnel_engine.dart';
import 'package:dirka_mobile/tunnel/tunnel_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches Dirka on Android', (tester) async {
    await tester.pumpWidget(const DirkaApp());
    expect(find.text('Dirka'), findsOneWidget);
  });

  testWidgets('loads the Android engine and reports an occupied port', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socket.close);
      final random = Random.secure();
      final key = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final client = await const NativeTunnelEngine().start(
        TunnelConfig(
          relayHost: '127.0.0.1',
          relayPort: 1,
          route: 'dirka-device-test',
          key: key,
          bindHost: '127.0.0.1',
          ports: [socket.port],
          tls: false,
        ),
      );
      addTearDown(client.dispose);
      final deadline = Stopwatch()..start();
      var snapshot = client.snapshot();
      while (snapshot.status != TunnelStatus.stopped &&
          deadline.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        snapshot = client.snapshot();
      }
      expect(snapshot.status, TunnelStatus.stopped);
      expect(snapshot.error, contains('127.0.0.1:${socket.port}'));
    });
  });
}
