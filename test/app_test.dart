import 'package:dirka_mobile/app_info/app_info.dart';
import 'package:dirka_mobile/clients/client_repository.dart';
import 'package:dirka_mobile/main.dart';
import 'package:dirka_mobile/tunnel/tunnel_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _AppInfo implements AppInfo {
  int repositoryOpens = 0;

  @override
  Future<AppVersion> loadAppVersion() async =>
      (version: '2.1.4', buildNumber: '37');

  @override
  Future<EngineInfo> loadEngineInfo() async => (
    engineVersion: '0.8.1',
    protocolVersion: 12,
    upstreamRevision: 'test-revision',
    upstreamLicense: 'test-license',
  );

  @override
  Future<bool> openUpstreamRepository() async {
    repositoryOpens++;
    return true;
  }
}

class _MemoryRepository implements ClientRepository {
  StoredClients stored = const StoredClients();
  bool failWrites = false;

  @override
  Future<StoredClients> load() async => stored;

  @override
  Future<void> save(StoredClients clients) async {
    if (failWrites) throw StateError('test write failed');
    stored = clients;
  }
}

class _Engine implements TunnelEngine {
  final clients = <_Client>[];

  @override
  Future<TunnelClient> start(TunnelConfig config) async {
    final client = _Client();
    clients.add(client);
    return client;
  }
}

class _Client implements TunnelClient {
  TunnelStatus status = TunnelStatus.waitingForAgent;
  bool disposed = false;

  @override
  TunnelSnapshot snapshot() => (status: status, error: null);

  @override
  void stop() => status = TunnelStatus.stopped;

  @override
  void dispose() => disposed = true;
}

final _source =
    '''
N_T_CRYPT_KEY=${List.filled(32, 'a').join()}
N_T_RELAY_HOST=relay.example.test
N_T_RELAY_PORT=1337
N_T_ROUTE_ID=home-route
N_T_CLIENT_BIND_HOST=127.0.0.1
N_T_CLIENT_PORTS=8080
''';

void main() {
  testWidgets('opens Settings and About from the app menu', (tester) async {
    final info = _AppInfo();
    await tester.pumpWidget(
      DirkaApp(repository: _MemoryRepository(), appInfo: info),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Settings');
    expect(find.text('Settings'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('App menu'));
    await tester.pumpAndSettle();
    await _tap(tester, 'About');
    expect(find.text('2.1.4 (build 37)'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('0.8.1'), findsOneWidget);
    expect(find.text('test-revision'), findsOneWidget);
    await _tap(tester, 'node-tunnel on GitHub');
    expect(info.repositoryOpens, 1);
    await _tap(tester, 'Open-source licenses');
    expect(find.byType(LicensePage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dirka'), findsOneWidget);
  });

  testWidgets('shows Dirka and follows system brightness', (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(DirkaApp(repository: _MemoryRepository()));
    await tester.pumpAndSettle();

    final title = find.text('Dirka');
    expect(title, findsOneWidget);
    expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
    expect(find.text('No saved clients'), findsOneWidget);
  });

  testWidgets('validates, duplicates, edits, and deletes saved entries', (
    tester,
  ) async {
    final store = _MemoryRepository();
    await tester.pumpWidget(DirkaApp(repository: store));
    await tester.pumpAndSettle();

    await _tap(tester, 'Add client');
    await _tap(tester, 'Save');
    expect(find.textContaining('N_T_CRYPT_KEY'), findsOneWidget);
    await tester.enterText(find.byType(TextField), _source);
    await _tap(tester, 'Save');
    expect(find.text('home-route'), findsOneWidget);
    final firstId = store.stored.clients.single.id;

    await _action(tester, 'Duplicate');
    await _tap(tester, 'Save');
    expect(find.text('home-route'), findsNWidgets(2));
    expect(store.stored.clients.map((e) => e.id), [firstId, firstId + 1]);
    expect(store.stored.clients.map((e) => e.source).toSet(), {_source});

    await _action(tester, 'Edit');
    await tester.enterText(
      find.byType(TextField),
      _source.replaceFirst('home-route', 'new-route'),
    );
    await _tap(tester, 'Save');
    expect(find.text('new-route'), findsOneWidget);
    expect(store.stored.clients.first.id, firstId);

    await _action(tester, 'Delete');
    expect(find.text('Delete client?'), findsOneWidget);
    await _tap(tester, 'Delete');
    expect(find.text('new-route'), findsNothing);
    expect(store.stored.clients.single.id, firstId + 1);
  });

  testWidgets(
    'keeps a draft if secure storage fails and locks active entries',
    (tester) async {
      final store = _MemoryRepository()..failWrites = true;
      final engine = _Engine();
      await tester.pumpWidget(DirkaApp(repository: store, engine: engine));
      await tester.pumpAndSettle();

      await _tap(tester, 'Add client');
      await tester.enterText(find.byType(TextField), _source);
      await _tap(tester, 'Save');
      expect(find.textContaining('Could not save changes'), findsOneWidget);
      expect(store.stored.clients, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        _source,
      );
      store.failWrites = false;
      await _tap(tester, 'Save');

      await _tap(tester, 'Connect');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.textContaining('Waiting for agent'), findsOneWidget);
      await tester.tap(find.byTooltip('Client actions').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem>(
              find.ancestor(
                of: find.text('Edit'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is PopupMenuItem,
                ),
              ),
            )
            .enabled,
        isFalse,
      );
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await _tap(tester, 'Disconnect');
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.clients.single.disposed, isTrue);
    },
  );
}

Future<void> _action(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Client actions').first);
  await tester.pumpAndSettle();
  await _tap(tester, action);
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
