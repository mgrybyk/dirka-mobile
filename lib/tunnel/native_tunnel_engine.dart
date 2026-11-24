import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'tunnel_engine.dart';

final class _Client extends Opaque {}

typedef _StartNative = Pointer<_Client> Function(Pointer<Uint8>, Size);
typedef _SnapshotNative = Int32 Function(
  Pointer<_Client>,
  Pointer<Uint8>,
  Size,
);
typedef _StopNative = Void Function(Pointer<_Client>);

const _snapshotCapacity = 8192;
DynamicLibrary _openLibrary() => DynamicLibrary.open('libdirka_engine.so');

int _start(String json) {
  final library = _openLibrary();
  final start = library
      .lookupFunction<
        _StartNative,
        Pointer<_Client> Function(Pointer<Uint8>, int)
      >('dirka_client_start');
  final bytes = utf8.encode(json);
  final input = calloc<Uint8>(bytes.length);
  try {
    final buffer = input.asTypedList(bytes.length);
    try {
      buffer.setAll(0, bytes);
      return start(input, bytes.length).address;
    } finally {
      buffer.fillRange(0, bytes.length, 0);
    }
  } finally {
    calloc.free(input);
  }
}

final class NativeTunnelEngine implements TunnelEngine {
  const NativeTunnelEngine();

  @override
  Future<TunnelClient> start(TunnelConfig config) async {
    final json = jsonEncode(config);
    final address = await Isolate.run(() => _start(json));
    if (address == 0) {
      throw StateError('The native engine could not start this configuration.');
    }
    return _NativeClient(Pointer<_Client>.fromAddress(address));
  }
}

final class _NativeClient implements TunnelClient, Finalizable {
  _NativeClient(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  // Keep the library and its finalizer alive for the process lifetime.
  static final _library = _openLibrary();
  static final _read = _library
      .lookupFunction<
        _SnapshotNative,
        int Function(Pointer<_Client>, Pointer<Uint8>, int)
      >('dirka_client_snapshot');
  static final _stop = _library
      .lookupFunction<_StopNative, void Function(Pointer<_Client>)>(
        'dirka_client_stop',
      );
  static final _destroy = _library
      .lookupFunction<_StopNative, void Function(Pointer<_Client>)>(
        'dirka_client_destroy',
      );
  static final _finalizer = NativeFinalizer(
    _library.lookup<NativeFunction<_StopNative>>('dirka_client_destroy').cast(),
  );

  Pointer<_Client> _pointer;

  @override
  TunnelSnapshot snapshot() {
    if (_pointer == nullptr) {
      throw StateError('Tunnel client is closed.');
    }
    final output = calloc<Uint8>(_snapshotCapacity);
    try {
      final length = _read(_pointer, output, _snapshotCapacity);
      if (length <= 0 || length > _snapshotCapacity) {
        throw StateError('The native engine could not report its state.');
      }
      final state = jsonDecode(
        utf8.decode(output.asTypedList(length)),
      ) as Map<String, Object?>;
      final status = switch (state['status']) {
        'connecting' => TunnelStatus.connecting,
        'waiting-for-agent' => TunnelStatus.waitingForAgent,
        'connected' => TunnelStatus.connected,
        'stopped' => TunnelStatus.stopped,
        _ => throw StateError('Unknown native tunnel status.'),
      };
      return (status: status, error: state['error'] as String?);
    } finally {
      calloc.free(output);
    }
  }

  @override
  void stop() {
    if (_pointer != nullptr) _stop(_pointer);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) return;
    _finalizer.detach(this);
    _destroy(_pointer);
    _pointer = nullptr;
  }
}
