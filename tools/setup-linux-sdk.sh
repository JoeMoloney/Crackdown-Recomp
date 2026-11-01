#!/usr/bin/env bash
# Download and verify the pinned ReXGlue Linux SDK release archive.
# Usage: tools/setup-linux-sdk.sh [SDK_PARENT]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/patches/rexglue-sdk/baseline.env"
SDK_VERSION="$(sed -n 's/^SDK_VERSION=//p' "$BASELINE" | tr -d '\r')"
SDK_SHA256="$(sed -n 's/^SDK_LINUX_ZIP_SHA256=//p' "$BASELINE" | tr 'A-F' 'a-f' | tr -d '\r')"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    echo "Usage: $0 [SDK_PARENT]"
    echo "Install the pinned ReXGlue SDK as SDK_PARENT/linux-amd64 (default: tools/rexglue/linux-amd64)."
    exit 0
fi
[[ $# -le 1 ]] || { echo "Usage: $0 [SDK_PARENT]" >&2; exit 2; }
SDK_PARENT="${1:-$ROOT/tools/rexglue}"
mkdir -p -- "$SDK_PARENT"
SDK_PARENT="$(cd -- "$SDK_PARENT" && pwd)"
SDK="$SDK_PARENT/linux-amd64"
ZIP="$SDK_PARENT/rexglue-sdk-$SDK_VERSION-linux-amd64.zip"
CONFIG_VERSION="$SDK/lib/cmake/rexglue/rexglueConfigVersion.cmake"
URL="https://github.com/rexglue/rexglue-sdk/releases/download/v$SDK_VERSION/rexglue-sdk-$SDK_VERSION-linux-amd64.zip"

fail() { echo "ERROR: $*" >&2; exit 1; }
verify_sdk() {
    [[ -f "$CONFIG_VERSION" ]] && grep -qF "set(PACKAGE_VERSION \"$SDK_VERSION\")" "$CONFIG_VERSION"
}

[[ "$(uname -s)" == Linux ]] || fail "this script runs on Linux only"
[[ -n "$SDK_VERSION" && "$SDK_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid SDK version or SHA-256 pin in $BASELINE"
for tool in sha256sum grep; do command -v "$tool" >/dev/null || fail "required tool not found: $tool"; done

if verify_sdk; then
    echo "ReXGlue SDK $SDK_VERSION is already installed at $SDK"
    exit 0
fi
[[ ! -e "$SDK" ]] || fail "$SDK exists but is not the pinned ReXGlue $SDK_VERSION SDK; move it aside before continuing"

if [[ ! -f "$ZIP" ]] || ! echo "$SDK_SHA256  $ZIP" | sha256sum -c --status -; then
    rm -f -- "$ZIP"
    if command -v wget >/dev/null; then
        wget -q -O "$ZIP" "$URL"
    elif command -v curl >/dev/null; then
        curl -fsSL -o "$ZIP" "$URL"
    else
        fail "wget or curl is required to download the ReXGlue SDK"
    fi
fi
echo "$SDK_SHA256  $ZIP" | sha256sum -c --status - || fail "$ZIP does not match its pinned SHA-256"

EXTRACT="$SDK_PARENT/.linux-amd64-extract.$$"
trap 'rm -rf -- "$EXTRACT"' EXIT
mkdir -p "$EXTRACT"
if command -v unzip >/dev/null; then
    unzip -q "$ZIP" -d "$EXTRACT"
elif command -v python3 >/dev/null; then
    python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ZIP" "$EXTRACT"
else
    fail "unzip or python3 is required to extract the ReXGlue SDK"
fi
[[ -d "$EXTRACT/linux-amd64" ]] || fail "SDK archive does not contain linux-amd64/"
grep -qF "set(PACKAGE_VERSION \"$SDK_VERSION\")" \
    "$EXTRACT/linux-amd64/lib/cmake/rexglue/rexglueConfigVersion.cmake" ||
    fail "downloaded archive does not contain ReXGlue $SDK_VERSION"
mv -- "$EXTRACT/linux-amd64" "$SDK"
echo "Installed verified ReXGlue SDK $SDK_VERSION at $SDK"
