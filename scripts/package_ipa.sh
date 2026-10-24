#!/bin/bash
set -euo pipefail

archive="${1:-build/OKNative.xcarchive}"
output="${2:-build/OKNative-unsigned.ipa}"
app="$archive/Products/Applications/OKNative.app"
if [[ ! -d "$app" ]]; then
  echo "App missing in archive: $app" >&2
  exit 1
fi

# mktemp owns this directory; the trap never removes the caller's build tree.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload" "$(dirname "$output")"
ditto "$app" "$stage/Payload/OKNative.app"
ditto -c -k --sequesterRsrc --keepParent "$stage/Payload" "$output"
unzip -t "$output"
echo "Unsigned IPA ready: $output"

