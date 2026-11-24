# Dirka

Android-first Flutter client for node-tunnel. The Android application ID is
`com.mgrybyk.dirka`. Confirm ownership before the first public release.

## Toolchain

Use Flutter 3.50.1 (Dart 3.14.0), Rust 1.100.0 via rustup, Temurin JDK 25.0.5.1+2,
Android SDK Platform 36, Build Tools 36.0.0, and NDK 28.2.13676358. The wrapper
pins Gradle 9.5.0. The Flutter template pins AGP 9.3.1 and Kotlin 2.4.20.
Host interoperability tests use Node 26.13.0 and the OpenSSL CLI.
The secure-storage dependencies also use Android SDK Platform 35 and
CMake 3.22.1.

Install Rust with [rustup](https://rust-lang.org/tools/install/). The
toolchain file selects Rust 1.100.0 and the Android ARM64 target. Set
`JAVA_HOME` and `ANDROID_HOME` to your JDK and Android SDK if Flutter
does not discover them. Android Studio is optional. Build on macOS or Linux.

```sh
sdkmanager 'platform-tools' 'platforms;android-36' 'platforms;android-35' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
flutter pub get --enforce-lockfile
flutter build apk --release
```

The Android build fetches the pinned node-tunnel source on first use and
packages the ARM64 engine. If Gradle fails while transforming `android.jar`,
check that API 36 is fully installed in the SDK Flutter reports in
`flutter doctor -v`. Reinstall `platforms;android-36` if its JAR is missing.

## Checks

If Cargo is missing from your shell's PATH after installing rustup, open
a new shell or source `~/.cargo/env` before running the Rust checks.

```sh
tool/fetch-upstream.sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-warnings --fatal-infos
flutter test
cargo fmt --manifest-path native/Cargo.toml --all -- --check
cargo clippy --manifest-path native/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path native/Cargo.toml --locked
```

## Physical device

The APK targets ARM64 (Android 7.0/API 24 or later). Enable USB debugging
and authorize the development computer. For wireless debugging, use
`adb pair` and `adb connect` with the respective endpoints shown in Android
Settings.

```sh
adb devices -l
adb -s DEVICE_SERIAL shell getprop ro.product.cpu.abilist
adb -s DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-release.apk
flutter test integration_test/app_test.dart -d DEVICE_SERIAL
```

The integration test checks both encrypted storage and native bind-conflict
reporting. Use this procedure for a binary round trip.

1. Run `node tool/interop-relay.cjs --device` on the development host.
   It starts the pinned JavaScript relay and agent plus two loopback echo
   servers, and prints a temporary port, route ID, and key. Use a trusted LAN.
2. Open **Add client** in Dirka. Paste the following configuration with
   the host's reachable LAN address and the relay port, route, and key from
   the fixture, then save and tap **Connect**.

   ```dotenv
   N_T_RELAY_HOST=HOST_LAN_ADDRESS
   N_T_RELAY_PORT=FIXTURE_PORT
   N_T_CRYPT_KEY=FIXTURE_KEY
   N_T_ROUTE_ID=dirka-interop
   N_T_CLIENT_BIND_HOST=127.0.0.1
   N_T_CLIENT_PORTS=18080
   N_T_USE_TLS=false
   ```
3. Wait for **Connected to agent**, then run
   `node tool/device-round-trip.cjs DEVICE_SERIAL`. The script checks the
   echo and server greeting using a socket opened on the phone by ADB,
   outside Dirka. Tap **Disconnect** and wait for **Disconnected**.
4. Stop the fixture with Ctrl+C when finished. For an on-device TLS
   round trip, use a reachable TLS-terminating relay with a hostname and
   certificate chain trusted by Mozilla and a binary echo target.

## Saved configurations

Paste the supported fields from node-tunnel's `client.env`. Explicit bind
hosts are preserved. Use `127.0.0.1` or `::1` to keep a listener local.
Port lists and ascending ranges map to agent ports in the displayed order,
with up to 32 entries. An exact `N_T_USE_TLS=true` enables TLS.

Optional settings are `N_T_RECONNECT_DELAY_MS`, `N_T_RECONNECT_MAX_DELAY_MS`,
`N_T_RECONNECT_JITTER_PERCENT`, `N_T_HANDSHAKE_TIMEOUT_MS`,
`N_T_HEARTBEAT_INTERVAL_MS`, and `N_T_HEARTBEAT_TIMEOUT_MS`. They use the
upstream defaults and limits. Explicitly disabled diagnostic flags from the
example are accepted. Other fields, including the JS/WASM backend selector
and graceful shutdown timeout, produce a validation error. The editor flags
malformed dotenv lines that Node's loader would silently skip.

Dirka stores the complete entries in Keystore-backed encrypted storage and
excludes the preferences from Android backup and transfer. Each entry has
its own internal ID. Identical configurations can be saved and run
independently, subject to the ports available on the phone. Disconnect a
client to edit or delete it.

## Architecture and releases

Flutter manages saved configurations and supervises each client handle.
Rust owns listeners, relay
connections, retries, TLS, and forwarding. A small C ABI carries
configuration, state, and cancellation. The upstream shared library handles
authenticated protocol operations through its existing C ABI. Gradle generates
and packages both shared libraries. See [native/README.md](native/README.md)
for ownership, dependency choices, and protocol limits.

For an upstream update, verify the PR commit on GitHub and update
`native/upstream.rev`. Run `tool/fetch-upstream.sh`, the native checks, and
the physical-device proof before accepting a new pin. After updating either
native lockfile or the upstream pin, regenerate the bundled Rust notices with
`node tool/native-licenses.cjs`. About shows the installed app version, the
engine build metadata, and the bundled licenses. Host fixtures use
the pinned JavaScript relay and agent directly and need no npm install.

GitHub Actions builds and publishes a debug-key-signed test APK for PRs,
main, and manual runs. The version name and build number come from
`pubspec.yaml`. Increase the build number for releases. Public release
signing needs the owner's release key, stored outside the repository and
reused across upgrades. The signed-release workflow is part of Step 5.
Android requires matching signatures for `adb install -r`. CI runs generate
a fresh debug key, so use a consistently signed local build if retaining
an existing installation across builds.

The screen owns live handles until Android foreground service supervision is
implemented. Saved entries load disconnected after a process restart.
