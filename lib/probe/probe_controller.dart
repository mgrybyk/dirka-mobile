import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_engine.dart';

final class ProbeController extends ChangeNotifier {
  ProbeController(this._engine);

  final TunnelEngine _engine;
  TunnelClient? _client;
  Timer? _poll;
  bool _disposed = false;
  bool starting = false;
  bool stopping = false;
  TunnelSnapshot state = (status: TunnelStatus.stopped, error: null);

  bool get active => starting || _client != null;

  Future<void> start(TunnelConfig config) async {
    if (active) return;
    starting = true;
    state = (status: TunnelStatus.connecting, error: null);
    notifyListeners();

    try {
      final client = await _engine.start(config);
      if (_disposed) {
        client.dispose();
        return;
      }
      _client = client;
      _poll = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _refresh(),
      );
    } on Object {
      state = (
        status: TunnelStatus.stopped,
        error: 'The native tunnel could not start. Check the configuration and APK.',
      );
    } finally {
      starting = false;
    }
    if (!_disposed) notifyListeners();
  }

  void stop() {
    if (stopping || _client == null) return;
    stopping = true;
    _client!.stop();
    notifyListeners();
  }

  void _refresh() {
    try {
      final next = _client!.snapshot();
      if (next == state) return;
      state = next;
      if (state.status == TunnelStatus.stopped) _release();
    } on Object {
      _release();
      state = (
        status: TunnelStatus.stopped,
        error: 'Could not read the native tunnel state.',
      );
    }
    notifyListeners();
  }

  void _release() {
    _poll?.cancel();
    _poll = null;
    _client?.dispose();
    _client = null;
    stopping = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}
