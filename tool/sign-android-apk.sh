#!/usr/bin/env bash
set -euo pipefail

input="${1:?usage: sign-android-apk.sh UNSIGNED_APK OUTPUT_APK}"
output="${2:?usage: sign-android-apk.sh UNSIGNED_APK OUTPUT_APK}"
root="$(cd "$(dirname "$0")/.." && pwd)"
build_tools="${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK.}/build-tools/36.0.0"

: "${DIRKA_RELEASE_KEYSTORE:?Set DIRKA_RELEASE_KEYSTORE to the release keystore file.}"
: "${DIRKA_RELEASE_STORE_PASSWORD:?Set DIRKA_RELEASE_STORE_PASSWORD.}"
: "${DIRKA_RELEASE_KEY_ALIAS:?Set DIRKA_RELEASE_KEY_ALIAS.}"
: "${DIRKA_RELEASE_KEY_PASSWORD:?Set DIRKA_RELEASE_KEY_PASSWORD.}"
: "${DIRKA_RELEASE_CERT_SHA256:?Set DIRKA_RELEASE_CERT_SHA256 to the release certificate fingerprint.}"

if "$build_tools/apksigner" verify "$input" >/dev/null 2>&1; then
  echo "Use an unsigned build from DIRKA_UNSIGNED_RELEASE=1 flutter build apk --release." >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
"$build_tools/zipalign" -P 16 4 "$input" "$scratch/aligned.apk"
"$build_tools/apksigner" sign \
  --ks "$DIRKA_RELEASE_KEYSTORE" --ks-key-alias "$DIRKA_RELEASE_KEY_ALIAS" \
  --ks-pass env:DIRKA_RELEASE_STORE_PASSWORD --key-pass env:DIRKA_RELEASE_KEY_PASSWORD \
  --v4-signing-enabled false --out "$scratch/signed.apk" "$scratch/aligned.apk"

"$root/tool/verify-android-apk.sh" "$scratch/signed.apk" "$DIRKA_RELEASE_CERT_SHA256"
install -m 644 "$scratch/signed.apk" "$output"
