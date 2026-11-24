# Dirka native engine

The pinned node-tunnel source is fetched to `.upstream/node-tunnel`.
`build.rs` builds its locked Rust library and links the existing C ABI.
The Android build packages the JNI bridge `libdirka_android.so`, the engine
`libdirka_engine.so`, and the upstream protocol library
`libnode_tunnel_client.so` under `lib/arm64-v8a`. The checked-in
[C header](include/dirka_engine.h) defines the native interface. The build reads the protocol version from the
pinned upstream Rust source. Its metadata and license exports point to
immutable UTF-8 data for the process lifetime. The bundled dependency
notices are generated from the locked Android Rust graphs using
`node tool/native-licenses.cjs`.

Each opaque client owns a cancellation sender and a state receiver.
The native worker binds all requested ports before publishing relay state.
Each client owns its own upstream session and preserves its relay-issued ID
across reconnects. Upstream registration events supply relay and agent
presence. Loss of control connectivity clears pending local requests.
Once a data socket forwards, it is tracked independently until it closes
or the client stops. Cancellation drops pending sockets and joins listener
and data tasks before publishing `stopped`. The runtime is shared by clients
for the process lifetime.

The caller serializes calls on one client handle and destroys it exactly
once. Rust copies the start input before returning. Snapshot bytes are
caller-owned. The Android foreground service serializes JNI calls on its
dedicated worker, and Flutter subscribes to service snapshots. Dart FFI
accesses immutable engine metadata. Destruction requests cancellation.
After an explicit stop, the service waits for `stopped` before releasing
the handle and exposing the port for another start. A default-network
signal can advance a pending reconnect without restarting a healthy socket.
FFI entry points catch Rust unwinds. A worker panic becomes a sanitized
terminal error. Invalid pointers and process-aborting failures remain
outside this contract.

Tokio supplies async TCP, timers, and backpressured bidirectional copying.
Tokio-rustls uses ring for TLS crypto, and ring also supplies nonces from
the OS random source. WebPKI roots provide portable Mozilla trust roots.
TLS verifies the chain and configured hostname or IP on control and data
connections. The Android app uses these roots. Device-added CAs are
outside its trust policy. Host tests inject a temporary test CA. Serde and
Serde JSON marshal the C ABI configuration, snapshots, and existing upstream
exchange messages. Dart uses the official `material_ui` package from the
Flutter template and `ffi` to decode borrowed native metadata.

Each client uses upstream default heartbeat, setup, and reconnect timings
unless the validated configuration supplies overrides. The engine limits
admitted streams and its listener queue to 128 entries each. The native API
accepts one to 32 ordered ports. Dart validates the supported dotenv fields
against the upstream JavaScript parser in parity tests and sends typed inputs
to Rust. The Android Keystore-backed storage plugin encrypts the original text.
Protocol v9 drops a wrong-key connection without an authenticated error.
That case follows the same bounded exponential retry schedule as other
relay interruptions. Authenticated fatal errors and rejected relay TLS
certificates stop the client.
