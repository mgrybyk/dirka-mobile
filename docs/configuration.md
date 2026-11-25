# Configuration

Dirka uses the same protocol as its pinned node-tunnel version. The **About**
screen shows the supported protocol version and upstream commit. Use a relay
and agent with the same protocol version.

## Saved configurations

Dirka requires `N_T_CRYPT_KEY`, `N_T_RELAY_HOST`, `N_T_RELAY_PORT`,
`N_T_ROUTE_ID`, `N_T_CLIENT_BIND_HOST`, and `N_T_CLIENT_PORTS`.

Dirka preserves explicit bind hosts. Use `127.0.0.1` or `::1` to keep a listener local.
Port lists and ascending ranges map to agent ports in the displayed order,
with up to 32 entries. An exact `N_T_USE_TLS=true` enables TLS.

Optional settings are `N_T_RECONNECT_DELAY_MS`, `N_T_RECONNECT_MAX_DELAY_MS`,
`N_T_RECONNECT_JITTER_PERCENT`, `N_T_HANDSHAKE_TIMEOUT_MS`,
`N_T_HEARTBEAT_INTERVAL_MS`, and `N_T_HEARTBEAT_TIMEOUT_MS`. They use the
upstream defaults and limits. Dirka accepts `N_T_LOG_DEBUG` and `N_T_LOG_ERROR`
when set to `false` or left empty. Other fields, including the JS/WASM backend selector
and graceful shutdown timeout, produce a validation error. The editor flags
malformed dotenv lines that Node's loader would silently skip.

Dirka stores the complete entries in Keystore-backed encrypted storage and
excludes the preferences from Android backup and transfer. Each entry has
its own internal ID. Identical configurations can be saved and run
independently, subject to the ports available on the phone. Disconnect a
client to edit or delete it.

## Background operation

Switching away from Dirka and reopening it preserves running clients while
the service lives. Saved entries load disconnected after a process restart
or a reboot. Android can stop the service, and prolonged screen-off
operation depends on the device.

Allow notifications to see the active-client count in the notification drawer.
If permission is denied, forwarding continues and Android shows Dirka under
**Active apps**.
