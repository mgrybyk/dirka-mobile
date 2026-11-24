import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../tunnel/tunnel_engine.dart';

final class ClientConfig {
  const ClientConfig({required this.tunnel, required this.portsText});

  final TunnelConfig tunnel;
  final String portsText;

  bool get exposesNetwork =>
      tunnel.bindHost.toLowerCase() != 'localhost' &&
      !(InternetAddress.tryParse(tunnel.bindHost)?.isLoopback ?? false);
}

final _setting = RegExp(r'^(?:export +)?([A-Za-z_][A-Za-z_0-9]*)[ \t]*=');
final _leadingSpace = RegExp(r'^[ \t]+');
final _dotenvSpace = RegExp(r'^[ \t\n]+|[ \t\n]+$');
const _blank =
    r'[\u0009-\u000d \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]';
final _jsTrim = RegExp('^$_blank+|$_blank+\$');
final _portRange = RegExp('^([0-9]+)(?:$_blank*-$_blank*([0-9]+))?\$');
final _decimal = RegExp(
  r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
);
final _radix = RegExp(r'^0([bBoOxX])([0-9a-fA-F]+)$');

const _supported = {
  'N_T_CRYPT_KEY',
  'N_T_RELAY_HOST',
  'N_T_RELAY_PORT',
  'N_T_USE_TLS',
  'N_T_ROUTE_ID',
  'N_T_CLIENT_BIND_HOST',
  'N_T_CLIENT_PORTS',
  'N_T_RECONNECT_DELAY_MS',
  'N_T_RECONNECT_MAX_DELAY_MS',
  'N_T_RECONNECT_JITTER_PERCENT',
  'N_T_HANDSHAKE_TIMEOUT_MS',
  'N_T_HEARTBEAT_INTERVAL_MS',
  'N_T_HEARTBEAT_TIMEOUT_MS',
};

ClientConfig parseClientConfig(String source) {
  final env = _parseDotenv(source);
  for (final MapEntry(:key, :value) in env.entries) {
    if (_supported.contains(key)) continue;
    if ((key == 'N_T_LOG_DEBUG' || key == 'N_T_LOG_ERROR') &&
        (value.isEmpty || value == 'false')) {
      continue;
    }
    throw FormatException('Unsupported setting $key.');
  }

  String required(String key) {
    final value = env[key];
    if (value == null || _trim(value).isEmpty) {
      throw FormatException('$key is required.');
    }
    return value;
  }

  int integer(String key, int min, int max, {int? fallback}) {
    final raw = env[key];
    if (raw == null || raw.isEmpty) {
      if (fallback != null) return fallback;
      throw FormatException('$key is required.');
    }
    final value = _number(_trim(raw));
    if (value == null ||
        !value.isFinite ||
        value < min ||
        value > max ||
        value.truncateToDouble() != value) {
      throw FormatException('$key must be an integer between $min and $max.');
    }
    return value.toInt();
  }

  final key = env['N_T_CRYPT_KEY'] ?? '';
  if (utf8.encode(key).length != 32) {
    throw const FormatException(
      'N_T_CRYPT_KEY must contain exactly 32 UTF-8 bytes.',
    );
  }
  final relayHost = required('N_T_RELAY_HOST');
  final relayPort = integer('N_T_RELAY_PORT', 1, 65535);
  final route = required('N_T_ROUTE_ID');
  if (route.length > 128) {
    throw const FormatException(
      'N_T_ROUTE_ID must not exceed 128 UTF-16 code units.',
    );
  }
  final bindHost = required('N_T_CLIENT_BIND_HOST');
  final portsText = required('N_T_CLIENT_PORTS');
  final ports = _ports(portsText);
  final reconnect = integer(
    'N_T_RECONNECT_DELAY_MS',
    100,
    300000,
    fallback: 4000,
  );
  final tunnel = TunnelConfig(
    relayHost: relayHost,
    relayPort: relayPort,
    route: route,
    key: key,
    bindHost: bindHost,
    ports: ports,
    tls: env['N_T_USE_TLS'] == 'true',
    timing: TunnelTiming(
      handshakeMs: integer(
        'N_T_HANDSHAKE_TIMEOUT_MS',
        100,
        300000,
        fallback: 5000,
      ),
      heartbeatMs: integer(
        'N_T_HEARTBEAT_INTERVAL_MS',
        100,
        300000,
        fallback: 2000,
      ),
      pongMs: integer('N_T_HEARTBEAT_TIMEOUT_MS', 100, 3600000, fallback: 7000),
      reconnectMs: reconnect,
      maxReconnectMs: integer(
        'N_T_RECONNECT_MAX_DELAY_MS',
        reconnect,
        3600000,
        fallback: max(30000, reconnect),
      ),
      jitterPercent: integer(
        'N_T_RECONNECT_JITTER_PERCENT',
        0,
        100,
        fallback: 10,
      ),
    ),
  );
  if (utf8.encode(jsonEncode(tunnel)).length > 4096) {
    throw const FormatException(
      'The relay and bind configuration exceeds the engine input limit.',
    );
  }
  return ClientConfig(tunnel: tunnel, portsText: portsText);
}

// Node's dotenv syntax accepts comments, export, and three quote styles.
// Surface malformed assignments instead of silently skipping them.
Map<String, String> _parseDotenv(String source) {
  final lines = source.replaceAll('\r', '').split('\n');
  final result = <String, String>{};
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].replaceFirst(_leadingSpace, '');
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = _setting.matchAsPrefix(line);
    if (match == null) {
      throw FormatException(
        'Expected a configuration assignment on line ${index + 1}.',
      );
    }
    final key = match[1]!;
    final inline = line.substring(match.end);
    var value = inline.replaceFirst(_leadingSpace, '');
    if (inline.isNotEmpty) {
      // Node trims leading space across lines when spacing follows '='.
      while (value.isEmpty && index + 1 < lines.length) {
        value = lines[++index].replaceFirst(_leadingSpace, '');
      }
    }
    if (value.startsWith('"') ||
        value.startsWith("'") ||
        value.startsWith('`')) {
      final quote = value[0];
      final startLine = index + 1;
      var end = value.indexOf(quote, 1);
      while (end == -1 && index + 1 < lines.length) {
        final next = lines[++index];
        end = next.indexOf(quote);
        if (end != -1) {
          end += value.length + 1;
        }
        value += '\n$next';
      }
      if (end == -1) {
        throw FormatException('Unclosed quoted value on line $startLine.');
      }
      final remainder = value.substring(end + 1).replaceAll(_dotenvSpace, '');
      if (remainder.isNotEmpty && !remainder.startsWith('#')) {
        throw FormatException(
          'Unexpected text after a quoted value on line ${index + 1}.',
        );
      }
      value = value.substring(1, end);
      if (quote == '"') value = value.replaceAll(r'\n', '\n');
    } else {
      value = value.split('#').first.replaceAll(_dotenvSpace, '');
    }
    result[key] = value;
  }
  return result;
}

String _trim(String value) => value.replaceAll(_jsTrim, '');

num? _number(String value) {
  if (value.isEmpty) return 0;
  final prefixed = _radix.firstMatch(value);
  if (prefixed != null) {
    return int.tryParse(
      prefixed[2]!,
      radix: switch (prefixed[1]!.toLowerCase()) {
        'b' => 2,
        'o' => 8,
        _ => 16,
      },
    );
  }
  return _decimal.hasMatch(value) ? double.tryParse(value) : null;
}

List<int> _ports(String value) {
  const key = 'N_T_CLIENT_PORTS';
  final ports = <int>[];
  for (final entry in value.split(',')) {
    final match = _portRange.firstMatch(_trim(entry));
    if (match == null) {
      throw const FormatException(
        '$key must contain ports or ascending ranges separated by commas.',
      );
    }
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last > 65535 ||
        last < first) {
      throw const FormatException(
        '$key ranges must be ascending and between 1 and 65535.',
      );
    }
    if (ports.length + last - first + 1 > 32) {
      throw const FormatException('$key must not exceed 32 ports.');
    }
    for (var port = first; port <= last; port++) {
      ports.add(port);
    }
  }
  if (ports.toSet().length != ports.length) {
    throw const FormatException(
      '$key contains duplicate or overlapping ports.',
    );
  }
  return List.unmodifiable(ports);
}
