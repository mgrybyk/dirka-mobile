final class TunnelConfig {
  const TunnelConfig({
    required this.relayHost,
    required this.relayPort,
    required this.route,
    required this.key,
    required this.bindHost,
    required this.ports,
    required this.tls,
    this.timing = const TunnelTiming(),
  });

  final String relayHost;
  final int relayPort;
  final String route;
  final String key;
  final String bindHost;
  final List<int> ports;
  final bool tls;
  final TunnelTiming timing;

  Map<String, Object> toJson() => {
    'relayHost': relayHost,
    'relayPort': relayPort,
    'route': route,
    'key': key,
    'bindHost': bindHost,
    'ports': ports,
    'tls': tls,
    'timing': timing.toJson(),
  };
}

final class TunnelTiming {
  const TunnelTiming({
    this.handshakeMs = 5000,
    this.heartbeatMs = 2000,
    this.pongMs = 7000,
    this.reconnectMs = 4000,
    this.maxReconnectMs = 30000,
    this.jitterPercent = 10,
  });

  final int handshakeMs;
  final int heartbeatMs;
  final int pongMs;
  final int reconnectMs;
  final int maxReconnectMs;
  final int jitterPercent;

  Map<String, int> toJson() => {
    'handshakeMs': handshakeMs,
    'heartbeatMs': heartbeatMs,
    'pongMs': pongMs,
    'reconnectMs': reconnectMs,
    'maxReconnectMs': maxReconnectMs,
    'jitterPercent': jitterPercent,
  };
}

enum TunnelStatus {
  connecting('Connecting'),
  waitingForAgent('Connected to relay · Waiting for agent'),
  connected('Connected to agent'),
  stopped('Disconnected');

  const TunnelStatus(this.label);

  final String label;
}

typedef TunnelSnapshot = ({TunnelStatus status, String? error});

abstract interface class TunnelEngine {
  Future<TunnelClient> start(TunnelConfig config);
}

abstract interface class TunnelClient {
  TunnelSnapshot snapshot();
  void stop();
  void dispose();
}
