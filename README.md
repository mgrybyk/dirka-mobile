# Dirka

Android-first Flutter client for node-tunnel. The Android application ID is
`com.mgrybyk.dirka`. Confirm ownership before the first public release.

## Toolchain

Use Flutter 3.50.1 (Dart 3.14.0), Rust 1.100.0 via rustup, Temurin JDK 25.0.5.1+2,
Android SDK Platform 36, Build Tools 36.0.0, and NDK 28.2.13676358. The wrapper
pins Gradle 9.5.0. The Flutter template pins AGP 9.3.1 and Kotlin 2.4.20.
Host interoperability tests use Node 26.13.0 and the OpenSSL CLI.

Set `JAVA_HOME` and `ANDROID_HOME`. Install the SDK packages using Android
command-line tools. Android Studio is optional. Build on macOS or Linux.

```sh
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
rustup target add aarch64-linux-android
tool/fetch-upstream.sh
flutter pub get --enforce-lockfile
flutter build apk --release --target-platform android-arm64
```

## Checks

```sh
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

The integration test calls the real Android native library and checks that
it reports an occupied loopback port. Use this procedure for a binary round trip.

1. Run `node tool/interop-relay.cjs --device` on the development host.
   It starts the pinned JavaScript relay and agent plus two loopback echo
   servers, and prints a temporary port, route ID, and key. Use a trusted LAN.
2. Open the installed APK and enter the host's reachable LAN address
   and the relay port, route, and key from the fixture. Keep local port
   `18080`, switch off TLS for this temporary LAN fixture, and tap **Connect**.
3. Wait for **Connected to agent**, then run
   `node tool/device-round-trip.cjs DEVICE_SERIAL`. The script checks the
   echo and server greeting using a socket opened on the phone by ADB,
   outside Dirka. Tap **Disconnect** and wait for **Disconnected**.
4. Stop the fixture with Ctrl+C when finished. For an on-device TLS
   round trip, use a reachable TLS-terminating relay with a hostname and
   certificate chain trusted by Mozilla and a binary echo target.

## Architecture and releases

Flutter provides a temporary one-client probe. Rust owns listeners, relay
connections, retries, TLS, and forwarding. A small C ABI carries
configuration, state, and cancellation. The upstream shared library handles
authenticated protocol operations through its existing C ABI. Gradle generates
and packages both shared libraries. See [native/README.md](native/README.md)
for ownership, dependency choices, and protocol limits.

For an upstream update, verify the PR commit on GitHub and update
`native/upstream.rev`. Run `tool/fetch-upstream.sh`, the native checks, and
the physical-device proof before accepting a new pin. Host fixtures use
the pinned JavaScript relay and agent directly and need no npm install.

GitHub Actions builds and publishes a debug-key-signed test APK for PRs,
main, and manual runs. The version name and build number come from
`pubspec.yaml`. Increase the build number for releases. Public release
signing needs the owner's release key, stored outside the repository and
reused across upgrades. The signed-release workflow is part of Step 5.
Android requires matching signatures for `adb install -r`. CI runs generate
a fresh debug key, so use a consistently signed local build if retaining
an existing installation across builds.

Saved configurations and Android foreground service ownership are later
steps. The probe keeps its values in memory and ties its handle lifetime
to the screen. It makes no background or process-recovery guarantees.
