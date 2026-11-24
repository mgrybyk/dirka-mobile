#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ndk="$1"
destination="$2"
min_sdk="$3"
case "$(uname -s)" in
  Linux) host=linux-x86_64 ;;
  Darwin) host=darwin-x86_64 ;;
  *) echo "Android native builds are supported on Linux and macOS" >&2; exit 1 ;;
esac

bin="$ndk/toolchains/llvm/prebuilt/$host/bin"
target=aarch64-linux-android
linker="$bin/$target$min_sdk-clang"
if [[ ! -x "$linker" ]]; then
  echo "Android NDK compiler missing at $linker" >&2
  exit 1
fi

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker"
export CC_aarch64_linux_android="$linker"
export AR_aarch64_linux_android="$bin/llvm-ar"
export DIRKA_UPSTREAM_TARGET_DIR="$root/native/target/upstream-android"

cd "$root"
cargo build --locked --release --target "$target" --target-dir native/target --manifest-path native/Cargo.toml
install -d "$destination/arm64-v8a"
install -m 644 "native/target/$target/release/libdirka_engine.so" "$destination/arm64-v8a/"
install -m 644 "$DIRKA_UPSTREAM_TARGET_DIR/$target/release/libnode_tunnel_client.so" "$destination/arm64-v8a/"
