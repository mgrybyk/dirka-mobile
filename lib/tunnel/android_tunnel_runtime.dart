import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'tunnel_engine.dart';

final class AndroidTunnelRuntime implements TunnelRuntime {
  const AndroidTunnelRuntime({this.requestNotifications = true});

  static const _commands = MethodChannel('com.mgrybyk.dirka/tunnels');
  static const _events = EventChannel('com.mgrybyk.dirka/tunnel_states');

  final bool requestNotifications;

  static final _updates = _events.receiveBroadcastStream().map(_decode);

  @override
  Stream<Map<int, TunnelState>> get states => Stream.multi((listener) {
    var received = false;
    var cancelled = false;
    final subscription = _updates.listen(
      (states) {
        received = true;
        listener.add(states);
      },
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = () {
      cancelled = true;
      return subscription.cancel();
    };
    // EventChannel has one subscription per Flutter engine. The snapshot also
    // initializes a caller that joins an already-listened-to stream.
    unawaited(
      _commands
          .invokeMethod<Object?>('snapshot')
          .then(
            (value) {
              if (!received && !cancelled) listener.add(_decode(value));
            },
            onError: (Object error, StackTrace stack) {
              if (!received && !cancelled) listener.addError(error, stack);
            },
          ),
    );
  });

  static Map<int, TunnelState> _decode(Object? event) =>
      (event as Map<Object?, Object?>).map(
        (key, value) =>
            MapEntry(key as int, _state(value as Map<Object?, Object?>)),
      );

  static TunnelState _state(Map<Object?, Object?> state) {
    final status = switch (state['status']) {
      'connecting' => TunnelStatus.connecting,
      'waiting-for-agent' => TunnelStatus.waitingForAgent,
      'connected' => TunnelStatus.connected,
      _ => TunnelStatus.stopped,
    };
    return (
      status: status,
      active: state['active'] as bool,
      stopping: state['stopping'] as bool,
      error: state['error'] as String?,
    );
  }

  @override
  Future<void> start(int id, TunnelConfig config) async {
    final bytes = utf8.encode(jsonEncode(config));
    try {
      await _commands.invokeMethod<void>('start', {
        'id': id,
        'config': bytes,
        'requestNotifications': requestNotifications,
      });
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> stop(int id) => _commands.invokeMethod<void>('stop', {'id': id});

  @override
  Future<void> clearStopped(int id) =>
      _commands.invokeMethod<void>('clearStopped', {'id': id});
}
