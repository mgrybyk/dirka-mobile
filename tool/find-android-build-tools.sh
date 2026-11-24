#!/usr/bin/env bash
set -euo pipefail

sdk="${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK.}"
# Minimum for checking 16 KiB ZIP alignment with zipalign.
minimum_major=36
versions=()
for directory in "$sdk/build-tools/"*; do
  version="${directory##*/}"
  if [[ "$version" =~ ^([1-9][0-9]*)\.[0-9]+\.[0-9]+$ ]] &&
    (( BASH_REMATCH[1] >= minimum_major )) &&
    [[ -x "$directory/zipalign" && -x "$directory/apksigner" ]]; then
    versions+=("$version")
  fi
done

if (( ${#versions[@]} == 0 )); then
  echo "Install Android SDK Build Tools $minimum_major or newer in $sdk." >&2
  exit 1
fi

latest="$(printf '%s\n' "${versions[@]}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
printf '%s\n' "$sdk/build-tools/$latest"
