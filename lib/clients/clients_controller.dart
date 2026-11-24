import 'dart:async';

import 'package:flutter/foundation.dart';

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
  ClientsController(this._repository, this._runtime);

  final ClientRepository _repository;
  final TunnelRuntime _runtime;
  final _commands = <int>{};
  final _commandErrors = <int, String>{};
  Map<int, TunnelState> _states = const {};
  StreamSubscription<Map<int, TunnelState>>? _subscription;
  List<ClientEntry> _entries = const [];
  int _nextId = 1;
  bool _disposed = false;
  bool loading = false;
  bool ready = false;
  bool saving = false;
  String? loadError;

  List<ClientEntry> get entries => _entries;

  TunnelState? runtime(int id) => _states[id];

  bool commandPending(int id) => _commands.contains(id);
  String? commandError(int id) => _commandErrors[id];

  Future<void> load() async {
    if (ready || loading || _disposed) return;
    loading = true;
    loadError = null;
    _notify();
    try {
      await _listenToRuntime();
    } on Object {
      await _subscription?.cancel();
      _subscription = null;
      loadError = 'Could not read the Android tunnel service state.';
      loading = false;
      _notify();
      return;
    }
    try {
      final saved = await _repository.load();
      _entries = List.unmodifiable(
        saved.clients.map(
          (row) => ClientEntry(row, parseClientConfig(row.source)),
        ),
      );
      _nextId = saved.nextId;
      ready = _subscription != null;
    } on Object {
      loadError = 'Could not read saved clients from secure storage.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _listenToRuntime() async {
    if (_subscription != null || _disposed) return;
    final initial = Completer<void>();
    _subscription = _runtime.states.listen(
      (states) {
        _states = states;
        if (!initial.isCompleted) initial.complete();
        _notify();
      },
      onError: (Object error, StackTrace stack) {
        if (!initial.isCompleted) {
          initial.completeError(error, stack);
        } else {
          ready = false;
          loadError = 'Could not read the Android tunnel service state.';
          unawaited(_subscription?.cancel());
          _subscription = null;
          _notify();
        }
      },
    );
    await initial.future.timeout(const Duration(seconds: 5));
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
    if ((_states[id]?.active ?? false) || _commands.contains(id)) {
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
      if (resetRuntime != null) {
        _commandErrors.remove(resetRuntime);
        try {
          await _runtime.clearStopped(resetRuntime);
        } on Object {
          // The saved change already succeeded. Keep the local state consistent.
          _states = Map.of(_states)..remove(resetRuntime);
        }
      }
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
    if (!ready ||
        saving ||
        !_entries.contains(entry) ||
        (_states[entry.id]?.active ?? false)) {
      return;
    }
    await _command(
      entry.id,
      () => _runtime.start(entry.id, entry.config.tunnel),
      'Could not start forwarding. Reopen Dirka and try again.',
    );
  }

  Future<void> disconnect(int id) async {
    final state = _states[id];
    if (state == null || !state.active || state.stopping) return;
    await _command(
      id,
      () => _runtime.stop(id),
      'Could not disconnect this client. Try again.',
    );
  }

  Future<void> _command(
    int id,
    Future<void> Function() action,
    String failure,
  ) async {
    if (!_commands.add(id)) return;
    _commandErrors.remove(id);
    _notify();
    try {
      await action();
    } on Object {
      _commandErrors[id] = failure;
    } finally {
      _commands.remove(id);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
