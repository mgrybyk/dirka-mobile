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

The integration test checks encrypted storage, bind-conflict reporting, and
reattachment to a client owned by the Android service. Use this procedure for a binary round trip.

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

To verify forwarding while another app is in use, run the same fixture with
`--device --browser`, set `N_T_CLIENT_PORTS=18080,18081`, and connect. Open
`http://127.0.0.1:18081/dirka-background-check` in the device's browser with
the screen unlocked. The browser displays the forwarded response and the
fixture reports the request. The binary check still works on port 18080.
Return via the **Dirka** notification and disconnect. Check that the
notification disappears and the ports can be reused. Add `--control` to the
fixture to accept `stop-relay` and `start-relay` on standard input for testing
reconnects while Dirka stays in the background.

[Recorded Android device checks](docs/android-acceptance.md)

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

Flutter manages saved configurations and displays the state published by
a single Android foreground service. The service owns the native handles
through JNI. Rust owns listeners, relay connections, retries, TLS, and
forwarding, and uses the existing upstream protocol library. See
[native/README.md](native/README.md) for the ABI and protocol limits.

The service uses Android's `specialUse` foreground service type for
user-started, ongoing TCP forwarding while another app uses the ports.
It starts from the visible app and stays active until the last client stops.
[Android foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use)

On Android 13 and later, allow notifications to see the active-client count
in the notification drawer. If permission is denied, forwarding continues
and Android shows the foreground service under Active apps. A new default
network can wake a pending reconnect. Healthy connections stay open until
a socket or protocol event changes their state.

For an upstream update, verify the PR commit on GitHub and update
`native/upstream.rev`. Run `tool/fetch-upstream.sh`, the native checks, and
the physical-device proof before accepting a new pin. After updating either
native lockfile or the upstream pin, regenerate the bundled Rust notices with
`node tool/native-licenses.cjs`. About shows the installed app version, the
engine build metadata, and the bundled licenses. Host fixtures use
the pinned JavaScript relay and agent directly and need no npm install.

## Releases

The **Checks and Android APK** workflow runs on PRs, pushes to main, and
manual runs. It publishes the debug-key-signed `dirka-android-arm64-test`
artifact. GitHub runners generate a fresh debug key per run. Locally built
test APKs reuse the machine's debug key.

The **Signed Android release** workflow builds an unsigned APK and signs
it after compilation. It publishes the APK and `SHA256SUMS` to GitHub Releases
for a pushed `vMAJOR.MINOR.PATCH` tag. Manual dispatch accepts an existing
tag and builds the source at that tag. A tag with a prerelease suffix is
published as a prerelease. The tag must match the version name in
`pubspec.yaml`, for example `v0.1.0` for `0.1.0+1`. Increase the integer
after `+` for every release so Android can install it as an upgrade.

Configure the `android-release` GitHub environment with these secrets.

- `DIRKA_RELEASE_KEYSTORE_BASE64` contains the release keystore encoded as Base64.
- `DIRKA_RELEASE_STORE_PASSWORD` unlocks the keystore.
- `DIRKA_RELEASE_KEY_ALIAS` identifies the release key inside it.
- `DIRKA_RELEASE_KEY_PASSWORD` unlocks that key.

Set `DIRKA_RELEASE_CERT_SHA256` as a variable in the same environment. Use
the signing certificate's SHA-256 fingerprint from `keytool -list -v`.
The workflow checks the signer against that fingerprint before publication.
Keep a secure backup of the keystore and use the same signing key for future
upgrades. Confirm ownership of the application ID before the first public
release. [Android APK signing](https://developer.android.com/tools/apksigner)

On an ARM64 Android device, verify the downloaded checksums and install the
release. On macOS use `shasum -a 256 -c SHA256SUMS`.

```sh
sha256sum -c SHA256SUMS
adb -s DEVICE_SERIAL install -r dirka-v0.1.0-android-arm64.apk
```

Android requires the installed and incoming APKs to use the same signing
identity. Moving from the test build to a release with a different key
requires a fresh installation. Uninstalling clears Dirka's saved clients.

Switching away from Dirka and reopening it preserves running clients while
the service lives. Saved entries load disconnected after a process restart
or a reboot. Android can stop the service, and prolonged screen-off
operation depends on the device.
