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

rustup_bin="${CARGO_HOME:-$HOME/.cargo}/bin"
if [[ -x "$rustup_bin/cargo" ]]; then
  export PATH="$rustup_bin:$PATH"
fi
if ! command -v cargo >/dev/null; then
  echo "Cargo is required for Dirka's native engine. Install Rust with rustup (https://rust-lang.org/tools/install/)." >&2
  exit 1
fi

cd "$root"
cargo build --locked --release --target "$target" --target-dir native/target --manifest-path native/Cargo.toml
install -d "$destination/arm64-v8a"
install -m 644 "native/target/$target/release/libdirka_engine.so" "$destination/arm64-v8a/"
install -m 644 "$DIRKA_UPSTREAM_TARGET_DIR/$target/release/libnode_tunnel_client.so" "$destination/arm64-v8a/"

"$linker" -shared -fPIC -Wall -Wextra -Werror -Wl,-z,defs,-soname,libdirka_android.so \
  -I "$root/native/include" "$root/android/app/src/main/native/tunnel_bridge.c" \
  -L "$destination/arm64-v8a" -ldirka_engine -o "$destination/arm64-v8a/libdirka_android.so"
