import 'dart:convert';
import 'dart:io';

import 'package:dirka_mobile/clients/client_config.dart';
import 'package:flutter_test/flutter_test.dart';

final _example =
    '''
N_T_CRYPT_KEY=${List.filled(16, 'é').join()}
N_T_RELAY_HOST='relay.example.test'
N_T_RELAY_PORT=0x539
N_T_ROUTE_ID="home#office"
N_T_CLIENT_BIND_HOST=127.0.0.2
N_T_CLIENT_PORTS=443, 8000, 32000 - 32002
N_T_LOG_DEBUG=false
N_T_LOG_ERROR=false
''';

void main() {
  test('reads ordered ports, byte-length credentials and defaults', () {
    final config = parseClientConfig(_example);
    expect(config.tunnel.route, 'home#office');
    expect(config.tunnel.ports, [443, 8000, 32000, 32001, 32002]);
    expect(config.portsText, '443, 8000, 32000 - 32002');
    expect(config.tunnel.relayPort, 1337);
    expect(config.tunnel.tls, isFalse);
    expect(config.exposesNetwork, isFalse);
    expect(config.tunnel.timing.maxReconnectMs, 30000);
  });

  test(
    'reports unsupported, malformed, and missing settings without values',
    () {
      for (final (source, message) in [
        (
          '$_example\nN_T_SHUTDOWN_TIMEOUT_MS=2000',
          'Unsupported setting N_T_SHUTDOWN_TIMEOUT_MS.',
        ),
        ('$_example\nN_T_LOG_DEBUG=true', 'Unsupported setting N_T_LOG_DEBUG.'),
        (
          '$_example\ninvalid assignment',
          'Expected a configuration assignment',
        ),
        ('$_example\nN_T_ROUTE_ID="unclosed', 'Unclosed quoted value'),
        (
          _example.replaceFirst('N_T_CLIENT_BIND_HOST=127.0.0.2', ''),
          'N_T_CLIENT_BIND_HOST is required.',
        ),
        (
          _example.replaceAll('32000 - 32002', '443'),
          'duplicate or overlapping',
        ),
        (_example.replaceAll('32000 - 32002', '32000-32040'), '32 ports'),
        (_example.replaceAll('32000 - 32002', '0'), 'between 1 and 65535'),
      ]) {
        expect(
          () => parseClientConfig(source),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      }
    },
  );

  test('preserves an explicitly exposed bind host', () {
    final config = parseClientConfig(
      _example.replaceFirst('127.0.0.2', '0.0.0.0'),
    );
    expect(config.tunnel.bindHost, '0.0.0.0');
    expect(config.exposesNetwork, isTrue);
  });

  test('matches the pinned Node client for supported environment settings', () async {
    final sources = [
      _example,
      '$_example\nexport N_T_ROUTE_ID=`two\nlines`\nN_T_USE_TLS=true # yes\nN_T_HANDSHAKE_TIMEOUT_MS=1e2',
      '$_example\nN_T_RECONNECT_DELAY_MS=40000\nN_T_RECONNECT_JITTER_PERCENT=" "',
      '$_example\nN_T_ROUTE_ID="hello\\nworld"\nN_T_RELAY_PORT=0b101\nN_T_USE_TLS=True',
      _example.replaceAll('127.0.0.2', '::1').replaceAll('\n', '\r\n'),
      '$_example\nN_T_RELAY_PORT=12.5',
      '$_example\nN_T_RECONNECT_DELAY_MS=10000\nN_T_RECONNECT_MAX_DELAY_MS=9999',
      '$_example\nN_T_CLIENT_PORTS=1-33',
      '$_example\nN_T_CRYPT_KEY=${List.filled(33, 'x').join()}',
    ];
    final node = await Process.start('node', [
      '-e',
      r'''
const { getClientConfig } = require('./.upstream/node-tunnel/config');
const { readFileSync } = require('node:fs');
const { parseEnv } = require('node:util');
const results = JSON.parse(readFileSync(0, 'utf8')).map(source => {
  try {
    const c = getClientConfig(parseEnv(source));
    return {
      relayHost: c.relayHost, relayPort: c.relayPort, route: c.name,
      key: c.cryptKey, bindHost: c.localHost, ports: c.localPorts, tls: c.useTLS,
      timing: {
        handshakeMs: c.handshakeTimeout, heartbeatMs: c.heartbeatInterval,
        pongMs: c.heartbeatTimeout, reconnectMs: c.reconnectDelay,
        maxReconnectMs: c.reconnectMaxDelay, jitterPercent: c.reconnectJitterPercent
      }
    };
  } catch (error) {
    return { error: error.message.split(' ')[0] };
  }
});
process.stdout.write(JSON.stringify(results));
''',
    ]);
    final output = node.stdout.transform(utf8.decoder).join();
    final errors = node.stderr.transform(utf8.decoder).join();
    node.stdin.write(jsonEncode(sources));
    await node.stdin.close();

    expect(await node.exitCode, 0, reason: await errors);
    final fromNode = jsonDecode(await output) as List;
    final fromDart = [for (final source in sources) _parseOrError(source)];
    expect(fromDart, fromNode);
  });
}

Map<String, Object> _parseOrError(String source) {
  try {
    return parseClientConfig(source).tunnel.toJson();
  } on FormatException catch (error) {
    return {'error': error.message.split(' ').first};
  }
}
