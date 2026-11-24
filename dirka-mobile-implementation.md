# Dirka — mobile client implementation specification

## Goal and scope

Build a maintainable Android-first Flutter POC for node-tunnel, with future iOS support in mind. The app exposes local TCP ports for other applications and forwards traffic through an existing node-tunnel relay to an agent. Multiple independently configured clients may run simultaneously. Simplicity comes first, but avoid throwaway architecture and UI.

Upstream: https://github.com/mgrybyk/node-tunnel/pull/9 (branch `wasm`, now containing a portable Rust implementation). Do not require this PR to be merged before development. Inspect the actual source, native API, configuration parser, JS client behavior and tests before designing the integration. Pin a verified upstream commit; do not depend on a floating branch in reproducible builds. Existing JS users must remain unaffected: no npm runtime dependencies, WASM, compilation or native binaries required for them. WASM remains an upstream CI compatibility target, not the mobile runtime.

Repository: `dirka-mobile`; Flutter package: `dirka_mobile`; app display name: `Dirka`. Proposed Android application ID and future iOS bundle ID: `com.mgrybyk.dirka` (confirm ownership/availability before first release). Separate repository and release lifecycle; do not rename upstream node-tunnel now.

## Step 0 — Project foundation

Before implementing features:

- Consult current official Flutter architecture, testing and Android deployment guidance (https://docs.flutter.dev/app-architecture/recommendations). Use current stable compatible Flutter/Dart, Rust, Android SDK/NDK, JDK and Gradle versions; pin toolchain versions in CI and document them. Commit application lockfiles and Gradle wrapper.
- Use Flutter Material 3, system light/dark theme, responsive layouts, accessible labels, sufficient contrast and touch targets. No custom design system or heavy state management framework unless justified. Prefer straightforward view/view-model or controller separation, repositories for persistence and explicit constructor injection. Use feature-oriented directories where useful. Keep widgets free of networking and FFI details.
- Configure `flutter_lints`, `flutter analyze` with fatal warnings/infos, `dart format`, Flutter unit/widget tests and an integration-test entry point. Use `cargo fmt`, Clippy and Cargo tests for native Rust. Keep generated code separate and document generation. Choose a minimal, maintained dependency set; record why each nontrivial dependency is necessary.
- Set up GitHub Actions for checks and Android APK builds; use Dependabot (supported Pub/Cargo/GitHub Actions ecosystems as applicable). Provide manual rebuild workflow dispatch for toolchain/dependency maintenance. Do not require an emulator in CI.
- Document setup using CLI tooling and a physical Android device via ADB (USB or wireless debugging). Android Studio is optional; no emulator required due to limited RAM. Start with ARM64 Android if appropriate for the actual device; document supported ABIs. Do not unnecessarily constrain future Android ABI support.
- Keep README concise: prerequisites, build, tests, device installation, release process, upstream pin updates, architecture and known limitations. Commit no credentials, local SDK paths or signing keys.

## Step 1 — Native engine and integration proof

### Architecture

- Flutter/Dart: presentation, saved configurations, validation feedback, application state and interaction with a tunnel-engine abstraction.
- Native Rust: reusable TCP/TLS tunnel engine, local listeners, session protocol, connection negotiation, direct bidirectional byte forwarding, reconnect scheduling and resource cleanup. Reuse upstream Rust protocol/crypto implementation; do not reimplement protocol in Dart or Kotlin. Keep native networking code portable to iOS. Use a minimal asynchronous networking stack with justified dependencies. No UDP/QUIC yet.
- Native API: use upstream C ABI where applicable; extend or wrap it only as necessary. Prefer a small handle-based API and generated or carefully checked Dart FFI bindings. Explicitly document ownership, thread safety, buffer lifetimes, errors, cancellation and panic containment. Do not block the Flutter UI isolate with native operations. No bulk traffic across FFI. Each runtime client must own independent state. Avoid leaking pointers or handles when clients stop or the UI detaches.
- Platform adapter: Android-specific foreground service, notification and connectivity monitoring behind a small platform interface. Future iOS may provide a different implementation. Do not implement iOS or assume its background constraints are solved.
- Separate mobile-specific integration from portable Rust protocol code. Decide the minimal engine crate location after inspecting upstream (a mobile-local Rust crate depending on pinned upstream source is acceptable; coordinate any necessary upstream fixes separately). Do not copy upstream protocol sources or introduce a second protocol implementation.

### Prove interoperability before UI investment

1. Verify the pinned upstream native library builds for the development host and Android target; inspect the actual ABI and dependencies. Establish a host-side integration test using the existing JS relay and agent and a local TCP echo service.
2. Implement a single native client, establish verified TLS where configured, bind a local listener, and forward a binary round trip through relay and agent. Match upstream framing, authentication, limits, nonce generation, agent availability and reconnection semantics. Preserve bytes already read beyond setup frames. Use secure randomness and proper certificate/hostname verification; never disable TLS verification merely to make a test pass. Handle EOF, half-close, cancellation and backpressure correctly.
3. Package native library in a minimal Flutter Android APK, prove native calls and a binary round trip on a physical device. Use a reachable test relay (LAN or existing relay); do not assume emulator addresses or that the development host's loopback is reachable from the phone. Document a reproducible device test.
4. Test multiple independent clients and shutdown/resource cleanup before expanding the UI. If the upstream ABI or protocol does not support a needed behavior, report it and make the smallest justified compatible change; do not invent wire semantics.

## Step 2 — Saved configurations

- Support add, edit, duplicate and delete. No custom display name. Generate an internal stable ID per saved entry (UUID or integer); it is never displayed and does not impose uniqueness on route IDs or configuration content. Identical configurations are allowed. Runtime port or upstream session conflicts must be surfaced rather than preventing duplicates from being saved.
- Provide one multiline plain-text configuration editor, Paste action, validation feedback, Save and Cancel. Reuse for add/edit/duplicate. Inspect upstream to determine the exact supported pasted format and parsing rules; do not assume JSON if upstream uses another format. Prefer supporting the existing native configuration syntax. Validate on save using the same semantics/defaults as node-tunnel, including required fields, connection settings, credentials, bind host and port syntax. Prefer one validation implementation in portable Rust if practical; otherwise add parity tests against upstream. Explicitly report unsupported fields/options rather than silently ignoring them. Limit POC support to fields required for connection, authentication and port exposure; document supported fields.
- Preserve `N_T_ROUTE_ID`, `N_T_RELAY_HOST`, `N_T_CLIENT_BIND_HOST`, `N_T_CLIENT_PORTS` and relevant required/defaulted connection settings. Support single port, comma-separated list and ranges (e.g. `443, 8000, 32000-32010`) according to upstream parser rules. Validate range boundaries and duplicates as upstream does. Use configured bind addresses intentionally; prefer loopback as safe default where compatible with upstream semantics. Warn about non-loopback exposure; never silently change an explicit valid bind address.
- Store saved configs persistently using platform-backed secure storage for credentials (or entire config if simplest). Avoid plaintext secrets in logs, crash diagnostics, backups or CI fixtures. Do not auto-read the clipboard; paste only on user action. Configure backup behavior appropriately. No sync/export in POC.
- Require disconnect before editing or deleting an active client. Duplication produces a separate inactive entry. No auto-connect after process restart or reboot for POC.

## Step 3 — UI

### Main screen

One primary screen, no bottom navigation. App bar title `Dirka`; overflow menu contains Settings and About. A small summary such as `3 clients · 2 active` is acceptable. Add client action as Material floating/extended action button. Empty state offers add client. Client cards in a scrollable list; each shows:

1. `N_T_ROUTE_ID` as first line, primary emphasis, single line with ellipsis when too long.
2. `N_T_RELAY_HOST` as second line, secondary emphasis, single line with ellipsis.
3. Status row with colored dot and label (see below). Allow status to wrap on narrow screens.
4. `Bind host: ${N_T_CLIENT_BIND_HOST}` (configured value, even when disconnected; do not imply the socket is actually listening when it is not).
5. `Ports: ${N_T_CLIENT_PORTS}` (show single/list/range representation; allow wrapping or accessible expansion). No per-port service names or host-to-port arrows.
6. Inline actionable error when relevant; a bounded, sanitized per-client diagnostic log/details view is useful but keep it simple.
7. Connect or Disconnect button determined by desired active state, not whether relay/agent is currently available.

Per-client overflow menu: Edit, Duplicate, Delete. No display-name field anywhere. Confirm destructive deletion. Use standard Material components and theme-aware colors. Example:

```text
Dirka                                  ⋮
3 clients · 2 active

┌──────────────────────────────────────┐
│ home-mac                           ⋮ │
│ relay.example.com                    │
│ ● Connected to agent                 │
│ Bind host: 127.0.0.1                  │
│ Ports: 3389, 5900                     │
│           [ Disconnect ]             │
└──────────────────────────────────────┘
┌──────────────────────────────────────┐
│ development                        ⋮ │
│ relay.example.com                    │
│ ● Connected to relay · Waiting for  │
│   agent                              │
│ Bind host: 0.0.0.0                    │
│ Ports: 443, 8000, 32000-32010         │
│           [ Disconnect ]             │
└──────────────────────────────────────┘
                           [ + Add client ]
```

### Status colors and semantics

- Disconnected: neutral gray.
- Connecting: yellow/orange (amber), including reconnect attempts.
- Connected to relay · Waiting for agent: green dot and green `Connected to relay`; neutral theme foreground/gray separator `·`; amber `Waiting for agent` text (same color as Connecting).
- Connected to agent: green dot and green text.

Use theme-aware accessible colors; no exact hex values required. Relay-connected is a successful client state; waiting for agent is informational. Do not infer agent availability merely from a TCP connection: map states to actual upstream protocol events. If upstream cannot distinguish these states, identify the gap and resolve it compatibly or report it; do not fake status.

### Settings and About

Settings: stub page, no speculative settings. About: app version/build number from package metadata, supported protocol version from engine/upstream metadata (not a duplicated constant), engine source version/commit, upstream repository link, open-source licenses. Use normal system back navigation.

## Step 4 — Runtime lifecycle and Android integration

Distinguish saved configurations, desired active state and observed connection state. Active means the user requested a client to run and it has not been stopped, irrespective of relay/agent connectivity. Connecting includes transient network recovery. Errors are separate from the four displayed states.

- Connect starts client; Disconnect cancels retries, closes sockets/listeners and releases all resources. Start/stop operations must be race-safe and idempotent. Clients run independently. UI reattachment must retrieve authoritative engine state, not recreate clients or assume they are stopped.
- Bind failures: report address/port and sanitized cause (e.g. address already in use, permission denied, invalid local address). Prefer all-or-nothing startup: if any requested port fails, release all listeners already opened for that client, stop it, show Disconnected with actionable error. Inspect existing JS behavior and document any deliberate difference. Test conflicts with another active client and external application. Terminal failures such as invalid credentials/config should stop or avoid endless retries according to upstream behavior; transient failures retry using bounded exponential backoff with jitter, respecting upstream semantics. Clear stale errors appropriately.
- Observe Android default network changes with `ConnectivityManager` callbacks. Communicate relevant events to the engine; recover when connectivity returns, but do not tear down healthy sockets on every event. Socket failures and protocol events remain authoritative. Avoid duplicate retry loops, races and unbounded retries at high frequency. Unregister callbacks when no longer needed.
- A single Android foreground service owns/supervises all active clients independently of Flutter activity/widget lifecycle. Define one authoritative owner of native engine handles; if service owns them, expose commands/state to Flutter via a minimal bridge rather than creating a second engine via FFI. Keep native bulk networking in Rust regardless of bridge choice. Starting, minimizing, reopening and activity recreation must not accidentally stop or duplicate tunnels. Start service when first client becomes active and stop when last is stopped.
- Verify current Android foreground service type/permission/start restrictions for a user-initiated local TCP forwarding utility targeting the chosen SDK. Investigate `specialUse` if appropriate; do not arbitrarily declare dataSync, VPN or unrelated types. Document the rationale and test on physical device. Handle notification permission behavior correctly. No VPN integration.
- Single minimal ongoing notification: app name `Dirka`, text `1 active client` or `N active clients`. Count desired-active clients, including Connecting and Waiting for agent, not only successful connections. No names, hostnames, action buttons or connection details. Tapping notification opens the app. Update on count changes; remove when zero. Disconnect all is deferred.
- Required: forwarding continues when app is minimized and another Android app is in use with screen unlocked. Screen-off survival is best effort; do not intentionally stop on lock. No guarantee of indefinite background operation, process-death recovery, boot startup or battery exemptions. Do not use misleading background modes. Future iOS lifecycle/background feasibility is a separate investigation; shared Flutter/Rust code does not bypass iOS restrictions.

## Step 5 — Tests, CI and delivery

Host-side tests should cover most logic without a device:

- Rust: upstream interop, binary round trip, verified TLS success and rejection, multiple independent clients, agent arrival/departure, relay reconnect, cancellation, port binding conflict and cleanup, parser parity and resource lifecycle. Use local JS relay/agent fixtures from pinned upstream, not public production infrastructure.
- Dart: configuration parsing/validation presentation, secure persistence abstraction, duplicate identity, state mapping, active count, command errors and controller lifecycle using fake engine/platform adapters.
- Widget tests: empty/list states, add/edit/duplicate/delete, long route/host ellipsis, status text/color semantics, errors, buttons and Settings/About navigation. Avoid fragile pixel snapshots unless useful.
- Physical device acceptance: install APK via ADB; use another Android app to connect to forwarded local TCP ports; test simultaneous clients, bind conflicts, minimize/reopen, Wi-Fi/network changes and stop/rebind. Check notification count and removal. Test lock/unlock opportunistically; record actual behavior. Do not claim device tests passed unless executed.

CI baseline (adapt paths/flags to actual project):

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --locked
flutter build apk --release
```

Include native Android cross-build and packaging in the APK pipeline; a desktop Rust build alone is insufficient. Run checks on PRs; publish build artifacts and support manual builds. Signed GitHub Releases on tags or manual workflow dispatch. Keep signing keys/passwords in CI secrets; reuse signing identity for upgrades, separate debug/test builds from release builds. Signing setup may require owner action; do not fabricate secrets or publish automatically without configured credentials. No Play Store distribution. Document supported ABI(s), version/build number strategy and installation/update commands. No in-app updater.

## Acceptance criteria and implementation order

- Step 0 foundation and reproducible build established.
- Native Rust interop proven on host and Android before extensive UI work.
- All four states reflect real upstream events, multiple saved entries and active clients operate independently, duplicate configs can be saved, bind failures are visible and cleaned up.
- Real external Android application uses forwarded TCP ports while Dirka is minimized; notification reflects active count; network recovery and manual disconnect work.
- CI passes formatting, analysis, tests and APK build; device-only checks clearly identified. Existing upstream JS/WASM compatibility remains intact; upstream PR #9 should only be merged by the owner after working Android validation.

Non-goals: actual iOS implementation, UDP/QUIC, VPN, advanced forms, traffic analytics, sync, persistent payload logs, extensive frameworks, guaranteed screen-off/background survival, automatic startup, in-app updates.

Work incrementally and prefer small reviewable commits. Report decisions, actual test results, blockers and deviations from this specification. Verify repository facts before implementing; do not assume earlier architectural proposals are already implemented. If a material conflict arises (especially protocol semantics, FFI lifecycle, Android service restrictions or upstream changes), explain it before expanding scope. Keep the simplest maintainable solution.
