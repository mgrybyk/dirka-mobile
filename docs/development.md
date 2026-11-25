# Development

## Toolchain

Use the latest stable patch in the Flutter release series selected by
[CI](../.github/actions/android-tools/action.yml), the Dart SDK bundled with it,
and Temurin JDK 25. Host interoperability tests use Node 26 and the OpenSSL CLI.

Install Rust with [rustup](https://rust-lang.org/tools/install/).
`rust-toolchain.toml` selects the compiler and Android ARM64 target. Install
the Android SDK Command-Line Tools and Platform-Tools. Set `JAVA_HOME` and
`ANDROID_HOME` if Flutter has trouble finding your JDK or Android SDK. Gradle
installs the Android SDK platforms, Build Tools, NDK, and CMake required by
the build once the SDK licenses are accepted. Build on macOS or Linux.

```sh
flutter doctor --android-licenses
flutter pub get --enforce-lockfile
flutter build apk --release --target-platform android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Copy it
to the device and open it to install, or use ADB as shown below.

The Android build fetches the pinned node-tunnel source on first use and
packages the ARM64 engine. If Gradle fails while transforming `android.jar`,
use `flutter doctor -v` to identify the SDK and reinstall the platform named
in the build error if its JAR is missing. The APK signing and verification
scripts use the newest compatible stable Build Tools installed in that SDK.

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

The APK requires ARM64 and Android 13 (API 33) or later. Enable USB debugging
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
reattachment to a client owned by the Android service. To test a binary round trip,
use the pinned relay fixture.

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

To check recovery after a Wi-Fi change, use USB ADB, leave Dirka in the
background, change or briefly disconnect the device's Wi-Fi, then restore
access to the fixture and repeat the binary check.

### Idle memory

On an unlocked test device with the release APK installed and Dirka's
interface in English, run both phases with Python 3 and Node.

```sh
python3 tool/device-idle-comparison.py DEVICE_SERIAL dirka-memory-results
```

The runner starts a loopback relay with no agent, creates a temporary
client, and captures relay-only memory before restarting Dirka for the
disconnected capture. Each phase takes two hours by default. Keep the
device connected to ADB and leave the app untouched during the run.

For manual captures, use the following commands.

Use the same release build and screen conditions for both runs. Start
with a fresh Dirka process each time. Keep Dirka disconnected for the
first run. For the second, connect to the relay and wait for **Waiting
for agent** before starting the capture. Leave forwarding unused.

```sh
node tool/device-memory.cjs DEVICE_SERIAL > disconnected.meminfo
node tool/device-memory.cjs DEVICE_SERIAL > relay-only.meminfo
```

Each run records 13 samples, 10 minutes apart by default, and stops if
Dirka changes processes. Compare the `Heap Alloc` column for `Native Heap`
and `Dalvik Heap`, along with `TOTAL PSS`, `TOTAL SWAP PSS`, and graphics.
Measure foreground and background separately. Press Home for a background
sample while the foreground tunnel service continues running. To measure
with the Flutter activity closed, press Back from the clients screen and
verify the service is still running before starting the capture.

## Architecture

Flutter manages saved configurations and displays the state published by
a single Android foreground service. The service owns the native handles
through JNI. Rust owns listeners, relay connections, retries, TLS, and
forwarding, and uses the existing upstream protocol library. See
[native engine documentation](../native/README.md) for the ABI and protocol limits.

The service uses Android's `specialUse` foreground service type for
user-started, ongoing TCP forwarding while another app uses the ports.
It starts from the visible app and stays active until the last client stops.
[Android foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use)

A new default network can wake a pending reconnect. Healthy connections stay
open until a socket or protocol event changes their state.

## Updating node-tunnel

Verify the upstream commit on GitHub and update `native/upstream.rev`. Run
`tool/fetch-upstream.sh`, the native checks, and the
[physical-device checks](#physical-device) before accepting a new pin. After
updating either native lockfile or the upstream pin, regenerate the bundled
Rust notices with `node tool/native-licenses.cjs`. Host fixtures use the pinned
JavaScript relay and agent directly and need no npm install.

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
upgrades. Confirm ownership of the Android application ID `com.mgrybyk.dirka`
before the first public release. [Android APK signing](https://developer.android.com/tools/apksigner)

On an ARM64 Android device, verify the downloaded checksums and install the
release. Replace `VERSION` with the release tag, including its leading `v`.
On macOS use `shasum -a 256 -c SHA256SUMS`.

```sh
sha256sum -c SHA256SUMS
adb -s DEVICE_SERIAL install -r dirka-VERSION-android-arm64.apk
```

Android requires the installed and incoming APKs to use the same signing
identity. Moving from the test build to a release with a different key
requires a fresh installation. Uninstalling clears Dirka's saved clients.
