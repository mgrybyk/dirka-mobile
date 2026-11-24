import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_controller.dart';
import '../tunnel/tunnel_engine.dart';
import 'client_config.dart';
import 'client_repository.dart';

final class ClientEntry {
  const ClientEntry(this.stored, this.config);

  final StoredClient stored;
  final ClientConfig config;

  int get id => stored.id;
  String get source => stored.source;
}

final class ClientEditError implements Exception {
  const ClientEditError(this.message);

  final String message;
}

final class ClientsController extends ChangeNotifier {
  ClientsController(this._repository, this._engine);

  final ClientRepository _repository;
  final TunnelEngine _engine;
  final _runtime = <int, TunnelController>{};
  List<ClientEntry> _entries = const [];
  int _nextId = 1;
  bool _disposed = false;
  bool loading = false;
  bool ready = false;
  bool saving = false;
  String? loadError;

  List<ClientEntry> get entries => _entries;

  TunnelController? runtime(int id) => _runtime[id];

  Future<void> load() async {
    if (ready || loading) return;
    loading = true;
    loadError = null;
    _notify();
    try {
      final saved = await _repository.load();
      _entries = List.unmodifiable(
        saved.clients.map(
          (row) => ClientEntry(row, parseClientConfig(row.source)),
        ),
      );
      _nextId = saved.nextId;
      ready = true;
    } on Object {
      loadError = 'Could not read saved clients from secure storage.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> save(String source, {int? id}) async {
    _checkWritable(id);
    final config = parseClientConfig(source);
    final newEntry = ClientEntry(
      StoredClient(id: id ?? _nextId, source: source),
      config,
    );
    final updated = [
      for (final entry in _entries)
        if (entry.id == id) newEntry else entry,
      if (id == null) newEntry,
    ];
    await _write(updated, id == null ? _nextId + 1 : _nextId, id);
  }

  Future<void> delete(int id) async {
    _checkWritable(id);
    await _write(
      _entries.where((entry) => entry.id != id).toList(),
      _nextId,
      id,
    );
  }

  void _checkWritable(int? id) {
    if (!ready || saving || _disposed) {
      throw const ClientEditError('Saved clients are unavailable. Try again.');
    }
    if (id != null && !_entries.any((entry) => entry.id == id)) {
      throw const ClientEditError('This client no longer exists.');
    }
    if (_runtime[id]?.active ?? false) {
      throw const ClientEditError('Disconnect this client first.');
    }
  }

  Future<void> _write(
    List<ClientEntry> updated,
    int nextId,
    int? resetRuntime,
  ) async {
    saving = true;
    _notify();
    try {
      await _repository.save(
        StoredClients(
          nextId: nextId,
          clients: [for (final entry in updated) entry.stored],
        ),
      );
      _entries = List.unmodifiable(updated);
      _nextId = nextId;
      _runtime.remove(resetRuntime)?.dispose();
    } on Object {
      throw const ClientEditError(
        'Could not save changes to secure storage. Try again.',
      );
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> connect(ClientEntry entry) async {
    if (!ready || saving || !_entries.contains(entry)) return;
    final controller = _runtime.putIfAbsent(entry.id, () {
      return TunnelController(_engine)..addListener(_notify);
    });
    await controller.start(entry.config.tunnel);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _runtime.values) {
      controller.dispose();
    }
    _runtime.clear();
    super.dispose();
  }
}
