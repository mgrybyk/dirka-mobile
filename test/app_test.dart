import 'dart:async';

import 'package:dirka_mobile/app_info/app_info.dart';
import 'package:dirka_mobile/clients/client_repository.dart';
import 'package:dirka_mobile/main.dart';
import 'package:dirka_mobile/tunnel/android_tunnel_runtime.dart';
import 'package:dirka_mobile/tunnel/tunnel_engine.dart';
import 'package:flutter/services.dart';
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

class _Runtime implements TunnelRuntime {
  final _updates = StreamController<Map<int, TunnelState>>.broadcast();
  final _active = <int, TunnelState>{};
  final started = <int>[];
  final stopped = <int>[];
  bool failStart = false;
  bool failStop = false;

  void emit(int id, TunnelState state) {
    _active[id] = state;
    _updates.add(Map.of(_active));
  }

  @override
  Stream<Map<int, TunnelState>> get states => Stream.multi((listener) {
    listener.add(Map.of(_active));
    final updates = _updates.stream.listen(listener.add);
    listener.onCancel = updates.cancel;
  });

  @override
  Future<void> start(int id, TunnelConfig config) async {
    if (failStart) throw StateError('test start failed');
    started.add(id);
    emit(id, (
      status: TunnelStatus.waitingForAgent,
      active: true,
      stopping: false,
      error: null,
    ));
  }

  @override
  Future<void> stop(int id) async {
    if (failStop) throw StateError('test stop failed');
    stopped.add(id);
    _active.remove(id);
    _updates.add(Map.of(_active));
  }

  @override
  Future<void> clearStopped(int id) async {}
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
      DirkaApp(
        repository: _MemoryRepository(),
        appInfo: info,
        runtime: _Runtime(),
      ),
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
    await tester.pumpWidget(
      DirkaApp(repository: _MemoryRepository(), runtime: _Runtime()),
    );
    await tester.pumpAndSettle();

    final title = find.text('Dirka');
    expect(title, findsOneWidget);
    expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
    expect(find.text('No saved clients'), findsOneWidget);
  });

  testWidgets('removing the idle app cancels its platform state listener', (
    tester,
  ) async {
    const events = MethodChannel('com.mgrybyk.dirka/tunnel_states');
    const commands = MethodChannel('com.mgrybyk.dirka/tunnels');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(events, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(commands, (call) async {
      expect(call.method, 'snapshot');
      return <int, Object?>{};
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(commands, null);
    });

    final repository = _MemoryRepository();
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        DirkaApp(repository: repository, runtime: const AndroidTunnelRuntime()),
      );
      await tester.pumpAndSettle();
      expect(find.text('No saved clients'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    expect(calls, ['listen', 'cancel', 'listen', 'cancel', 'listen', 'cancel']);
  });

  testWidgets('validates, duplicates, edits, and deletes saved entries', (
    tester,
  ) async {
    final store = _MemoryRepository();
    await tester.pumpWidget(DirkaApp(repository: store, runtime: _Runtime()));
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

  testWidgets('ellipsizes long route and relay text on a narrow display', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final route = List.filled(120, 'r').join();
    final relay = "${List.filled(100, 'h').join()}.example.test";
    final repository = _MemoryRepository()
      ..stored = StoredClients(
        nextId: 2,
        clients: [
          StoredClient(
            id: 1,
            source: _source
                .replaceFirst('home-route', route)
                .replaceFirst('relay.example.test', relay),
          ),
        ],
      );
    await tester.pumpWidget(
      DirkaApp(repository: repository, runtime: _Runtime()),
    );
    await tester.pumpAndSettle();

    for (final label in [route, relay]) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows command errors and reattaches without starting another client',
    (tester) async {
      final repository = _MemoryRepository()
        ..stored = StoredClients(
          nextId: 2,
          clients: [StoredClient(id: 1, source: _source)],
        );
      final runtime = _Runtime()..failStart = true;
      Future<void> open() async {
        await tester.pumpWidget(
          DirkaApp(repository: repository, runtime: runtime),
        );
        await tester.pumpAndSettle();
      }

      await open();
      await _tap(tester, 'Connect');
      expect(find.textContaining('Could not start forwarding'), findsOneWidget);
      expect(runtime.started, isEmpty);
      runtime.failStart = false;
      await _tap(tester, 'Connect');
      expect(runtime.started, [1]);
      expect(find.textContaining('Could not start forwarding'), findsNothing);

      runtime.emit(1, (
        status: TunnelStatus.connecting,
        active: true,
        stopping: false,
        error: 'Relay connection interrupted.',
      ));
      await tester.pumpAndSettle();
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('Relay connection interrupted.'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(runtime.stopped, isEmpty);
      await open();
      expect(find.text('Disconnect'), findsOneWidget);
      expect(runtime.started, [1]);

      runtime.failStop = true;
      await _tap(tester, 'Disconnect');
      expect(
        find.text('Could not disconnect this client. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Disconnect'), findsOneWidget);
      runtime.failStop = false;
      await _tap(tester, 'Disconnect');
      expect(find.text('Disconnected'), findsOneWidget);
      expect(runtime.stopped, [1]);
    },
  );

  testWidgets(
    'keeps a draft if secure storage fails and locks active entries',
    (tester) async {
      final store = _MemoryRepository()..failWrites = true;
      final runtime = _Runtime();
      await tester.pumpWidget(DirkaApp(repository: store, runtime: runtime));
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
      expect(runtime.stopped, [store.stored.clients.single.id]);
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
