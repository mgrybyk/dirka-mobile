# Dirka native engine

The pinned node-tunnel source is fetched to `.upstream/node-tunnel`.
`build.rs` builds its locked Rust library and links the existing C ABI.
The Android build packages `libdirka_engine.so` and its dependency
`libnode_tunnel_client.so` under `lib/arm64-v8a`. Both are build outputs.
The checked-in [C header](include/dirka_engine.h) defines the four functions
mirrored in the hand-written Dart binding. There is no binding generator.

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
caller-owned. Dart starts the engine on a worker isolate, reads snapshots
and sends stop requests from the owning isolate, and attaches a native
finalizer for abandoned handles. Destruction requests cancellation, and
polling `stopped` after an explicit stop confirms cleanup before rebinding.
FFI entry points catch Rust unwinds. A worker panic becomes a sanitized
terminal error. Invalid pointers and process-aborting failures remain
outside this contract.

Tokio supplies async TCP, timers, and backpressured bidirectional copying.
Tokio-rustls uses ring for TLS crypto, and ring also supplies nonces from
the OS random source. WebPKI roots provide portable Mozilla trust roots.
TLS verifies the chain and configured hostname or IP on control and data
connections. The probe uses these roots on Android. Device-added CAs are
outside its trust policy. Host tests inject a temporary test CA. Serde and
Serde JSON marshal the C ABI configuration, snapshots, and existing upstream
exchange messages. Dart uses the official `material_ui` package from the
Flutter template and `ffi` for native buffer allocation.

The probe uses upstream default heartbeat, setup, and reconnect timings.
Each client bounds admitted streams and its listener queue to 128 entries
each. The native API accepts one to 32 ordered ports. The temporary screen
exposes a single loopback port. The upstream dotenv parser lives in JavaScript.
The pasted format and complete configuration validation are Step 2 work.
Protocol v9 drops a wrong-key connection without an authenticated error.
That case follows the same bounded exponential retry schedule as other
relay interruptions. Authenticated fatal errors and rejected relay TLS
certificates stop the client.
