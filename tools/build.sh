#!/usr/bin/env bash
# The normal Linux build. Makes sure tools/rexglue/himdo/linux-amd64 holds the pinned Himdo ReXGlue SDK and that its runtime and GPU plugin
# branch's patches, building them with tools/build-patched-rexruntime.sh when it does not (git and network access the
# first time), then configures and builds the matching preset into out/build/<preset>. The Debug libraries stay stock.
#
#   tools/build.sh                  linux-amd64-release
#   tools/build.sh relwithdebinfo   linux-amd64-relwithdebinfo (or debug)
#
# Bootstraps the pinned Linux SDK when needed. Also needs generated/default (tools/codegen-linux.sh). See
# docs/linux.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$ROOT/tools/rexglue/himdo/linux-amd64"
PATCHED="$ROOT/tools/build-patched-rexruntime.sh"

fail() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-release}" in
  release) CONFIG=Release ;;
  relwithdebinfo) CONFIG=RelWithDebInfo ;;
  debug) CONFIG=Debug ;;
  *) fail "usage: $0 [release|relwithdebinfo|debug]" ;;
esac
PRESET="linux-amd64-${1:-release}"
[ "$(uname -s)" = Linux ] || fail "builds on Linux only"
bash "$ROOT/tools/setup-linux-sdk.sh" "$(dirname "$SDK")"
bash "$ROOT/tools/check-guest-code.sh" "$ROOT" || fail "generated/default is not current (run tools/codegen-linux.sh)"

if [ "$CONFIG" != Debug ] && ! bash "$PATCHED" --check "$SDK" >/dev/null 2>&1; then
  echo "== Building the patched ReXGlue runtime and GPU plugin"
  bash "$PATCHED" "$SDK" "$ROOT/tools/rexglue/himdo/rexglue-sdk-src"
fi

cd "$ROOT"
cmake --preset "$PRESET"
cmake --build --preset "$PRESET"
echo "Built out/build/$PRESET/crackdown"
