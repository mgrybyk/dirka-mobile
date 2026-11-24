#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: verify-android-apk.sh APK [expected-certificate-sha256]}"
root="$(cd "$(dirname "$0")/.." && pwd)"
build_tools="$(bash "$root/tool/find-android-build-tools.sh")"
expected="${2:-}"

entries="$(unzip -Z1 "$apk")"
for library in libapp.so libflutter.so libdirka_android.so libdirka_engine.so libnode_tunnel_client.so; do
  if ! printf '%s\n' "$entries" | awk -v path="lib/arm64-v8a/$library" '$0 == path {found=1} END {exit !found}'; then
    echo "APK is missing ARM64 library $library." >&2
    exit 1
  fi
done
if printf '%s\n' "$entries" | awk '/^lib\// && /\.so$/ && !/^lib\/arm64-v8a\// {found=1} END {exit !found}'; then
  echo "APK contains native libraries outside arm64-v8a." >&2
  exit 1
fi

"$build_tools/zipalign" -c -P 16 4 "$apk"
signers="$("$build_tools/apksigner" verify --print-certs "$apk")"
if [[ -n "$expected" ]]; then
  fingerprint="$(printf '%s\n' "$signers" | awk '/^Signer #[0-9]+ certificate SHA-256 digest: / { print $NF }')"
  expected="$(printf '%s' "$expected" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
  if [[ ! "$expected" =~ ^[a-f0-9]{64}$ || "$fingerprint" != "$expected" ]]; then
    echo "APK certificate does not match DIRKA_RELEASE_CERT_SHA256." >&2
    exit 1
  fi
fi
printf '%s\n' "$signers"
