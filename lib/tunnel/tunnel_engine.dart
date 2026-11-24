final class TunnelConfig {
  const TunnelConfig({
    required this.relayHost,
    required this.relayPort,
    required this.route,
    required this.key,
    required this.bindHost,
    required this.ports,
    required this.tls,
  });

  final String relayHost;
  final int relayPort;
  final String route;
  final String key;
  final String bindHost;
  final List<int> ports;
  final bool tls;

  Map<String, Object> toJson() => {
    'relayHost': relayHost,
    'relayPort': relayPort,
    'route': route,
    'key': key,
    'bindHost': bindHost,
    'ports': ports,
    'tls': tls,
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
