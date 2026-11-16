#!/usr/bin/env bash
# Build and install the pinned Himdo ReXGlue source as SDK_PARENT/linux-amd64.
# Usage: tools/setup-linux-sdk.sh [SDK_PARENT]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT/patches/rexglue-sdk"
baseline() { sed -n "s|^$1=||p" "$PATCH_DIR/baseline.env" | tr -d '\r'; }
SDK_COMMIT="$(baseline SDK_COMMIT)"
SDK_REPO="$(baseline SDK_REPO)"
SDK_TAG="$(baseline SDK_TAG)"
SDK_VERSION="$(baseline SDK_VERSION)"

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    echo "Usage: $0 [SDK_PARENT]"
    echo "Build Himdo ReXGlue $SDK_COMMIT into SDK_PARENT/linux-amd64 (default: tools/rexglue/himdo)."
    exit 0
fi
[[ $# -le 1 ]] || { echo "Usage: $0 [SDK_PARENT]" >&2; exit 2; }
SDK_PARENT="${1:-$ROOT/tools/rexglue/himdo}"
mkdir -p -- "$SDK_PARENT"
SDK_PARENT="$(cd -- "$SDK_PARENT" && pwd)"
SDK="$SDK_PARENT/linux-amd64"
SRC="$SDK_PARENT/rexglue-sdk-src"
PATCH="$PATCH_DIR/1105-himdo-port.patch"
JOBS="${JOBS:-$(nproc)}"
# Same compiler choice as tools/build-patched-rexruntime.sh: both scripts share one CMake build folder, and CMake
# drops the other -D settings (such as -march) when it sees a different compiler.
CC="${CC:-$(command -v clang-20 || command -v clang || true)}"
CXX="${CXX:-$(command -v clang++-20 || command -v clang++ || true)}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || fail "this script runs on Linux only"
[[ "$SDK_COMMIT" =~ ^[0-9a-f]{40}$ && -n "$SDK_REPO" && -n "$SDK_TAG" ]] || fail "invalid Himdo pin in baseline.env"
[[ -f "$PATCH" ]] || fail "missing $PATCH"
[[ -n "$CC" && -n "$CXX" ]] || fail "clang-20/clang++-20 (or clang/clang++) not found"
for tool in git cmake ninja "$CC" "$CXX" nproc; do command -v "$tool" >/dev/null || fail "$tool not found"; done

# The SDK install is marked with what it was built from. tools/build.sh calls this on every build; reinstalling would
# overwrite the patched runtime that tools/build-patched-rexruntime.sh put in the SDK, so skip when it is current.
MARKER="$SDK/himdo-sdk.txt"
MARKER_TEXT="sdk_commit=$SDK_COMMIT
patch_sha256=$(sha256sum "$PATCH" | cut -d' ' -f1)
compiler=$("$CXX" --version | sed -n 1p)"
if [[ -f "$MARKER" && "$(cat "$MARKER")" == "$MARKER_TEXT" && -f "$SDK/lib/cmake/rexglue/rexglueConfig.cmake" ]]; then
    echo "Himdo ReXGlue $SDK_COMMIT is already installed at $SDK"
    exit 0
fi

if [[ ! -d "$SRC/.git" ]]; then
    echo "== Fetching Himdo ReXGlue $SDK_TAG into $SRC"
    git clone --no-checkout "$SDK_REPO" "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$SDK_COMMIT"
git -C "$SRC" checkout --detach "$SDK_COMMIT"
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$SDK_COMMIT" ]] || fail "source checkout does not match the pinned commit"
git -C "$SRC" submodule update --init --recursive --jobs "$JOBS"

# Apply idempotently. Refuse to overwrite unrelated edits in an existing source folder.
if git -C "$SRC" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "== Himdo migration patch is already applied"
else
    if ! git -C "$SRC" diff --quiet || ! git -C "$SRC" diff --cached --quiet; then
        fail "$SRC has local changes unrelated to the migration patch; use a clean source directory"
    fi
    git -C "$SRC" apply --check "$PATCH" || fail "the migrated patch does not apply to Himdo $SDK_COMMIT"
    git -C "$SRC" apply "$PATCH"
fi

echo "== Configure and build Himdo ReXGlue $SDK_COMMIT"
cmake --preset linux-amd64 -S "$SRC" \
    "-DCMAKE_C_COMPILER=$CC" "-DCMAKE_CXX_COMPILER=$CXX" \
    -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2
cmake --build "$SRC/out/build/linux-amd64" --config Release \
    --target rexruntime rexgpu-xenos rexglue SDL3_test disasm --parallel "$JOBS"

echo "== Install ReXGlue SDK to $SDK"
cmake --install "$SRC/out/build/linux-amd64" --config Release --prefix "$SDK"
CONFIG_VERSION="$SDK/lib/cmake/rexglue/rexglueConfigVersion.cmake"
[[ -f "$CONFIG_VERSION" ]] || fail "installed SDK is missing rexglueConfigVersion.cmake"
grep -Eq 'set\(PACKAGE_VERSION "0\.10\.0(\.0)?"\)' "$CONFIG_VERSION" ||
    fail "installed SDK version is not compatible with project SDK $SDK_VERSION"
# The install put the plain runtime over any patched one, so the patched-runtime stamp no longer applies.
rm -f -- "$SDK/rexruntime-patch.txt"
printf '%s\n' "$MARKER_TEXT" > "$MARKER"
echo "Installed Himdo ReXGlue $SDK_COMMIT at $SDK"
