#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
revision="$(cat "$root/native/upstream.rev")"
upstream="$root/.upstream/node-tunnel"

if [[ ! -d "$upstream/.git" ]]; then
  git init --quiet "$upstream"
fi
if ! git -C "$upstream" cat-file -e "$revision^{commit}" 2>/dev/null; then
  git -C "$upstream" fetch --depth 1 https://github.com/mgrybyk/node-tunnel.git "$revision"
fi
git -C "$upstream" checkout --quiet --detach "$revision"
git -C "$upstream" diff --exit-code HEAD --
