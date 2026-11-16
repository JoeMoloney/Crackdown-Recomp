#!/usr/bin/env bash
# Bring your own disc: turns your own Crackdown disc image into a playable build on this machine.
#
#   ./setup-linux.sh /path/to/Crackdown.iso     first time (or a folder of files extracted from the disc)
#   ./setup-linux.sh                            later: updates the build after a `git pull`
#
# Steps, each skipped when already done:
#   1. check the build tools
#   2. check the disc is the supported version, then extract it into extracted_game/
#   3. recompile the game code (tools/codegen-linux.sh)
#   4. build the game (tools/build.sh release)
# Then start the game with ./play-linux.sh. Nothing here downloads or uploads game files.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME_DIR="$ROOT/extracted_game"
MANIFEST_TOOL="$ROOT/tools/make-game-manifest.py"

step() { printf '\n== %s\n' "$*"; }
fail() { printf '\nsetup-linux: %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi
[[ $# -le 1 ]] || fail "usage: $0 [/path/to/Crackdown.iso | extracted folder]"
SOURCE="${1:-}"
[[ "$(uname -s)" == Linux ]] || fail "this script is for Linux"

step "1/4 Build tools"
missing=()
for tool in git cmake ninja python3; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
command -v clang-20 >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 || missing+=(clang)
command -v clang++-20 >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1 || missing+=(clang++)
if (( ${#missing[@]} )); then
  printf 'Missing: %s\n' "${missing[*]}" >&2
  printf 'On CachyOS / Arch:  sudo pacman -S --needed git cmake ninja python clang20 lld20 llvm20\n' >&2
  printf 'See README.md for making clang-20 visible on your PATH.\n' >&2
  fail "install the missing tools and run this again"
fi
git -C "$ROOT" submodule update --init third_party/rexglue-sdk third_party/trg-launcher
echo "OK"

step "2/4 Game files"
verify() { python3 -I "$MANIFEST_TOOL" --verify "$1" >/dev/null 2>&1; }
if [[ -d "$GAME_DIR" ]] && verify "$GAME_DIR"; then
  echo "extracted_game/ is already the supported version, skipping."
else
  [[ -n "$SOURCE" ]] || fail "no game files yet: run $0 /path/to/Crackdown.iso"
  [[ -e "$SOURCE" ]] || fail "not found: $SOURCE"
  echo "Checking $SOURCE is the supported version..."
  python3 -I "$MANIFEST_TOOL" --verify "$SOURCE" ||
    fail "this disc image is not the supported Crackdown version (see README.md)"
  PARTIAL="$GAME_DIR.partial"
  rm -rf -- "$PARTIAL"
  if [[ -d "$SOURCE" ]]; then
    echo "Copying the game files..."
    cp -a -- "$SOURCE/." "$PARTIAL/"
  else
    echo "Extracting the disc image (about 6 GB, this takes a few minutes)..."
    bash "$ROOT/tools/extract-game.sh" "$SOURCE" "$PARTIAL"
  fi
  verify "$PARTIAL" || fail "the extracted files failed the version check; $PARTIAL kept for inspection"
  [[ ! -e "$GAME_DIR" ]] || mv -- "$GAME_DIR" "$GAME_DIR.old-$(date +%Y%m%d-%H%M%S)"
  mv -- "$PARTIAL" "$GAME_DIR"
  echo "Game files ready in extracted_game/"
fi

step "3/4 Recompile the game code"
if bash "$ROOT/tools/check-guest-code.sh" "$ROOT" >/dev/null 2>&1; then
  echo "Already up to date, skipping."
else
  echo "This takes a while the first time..."
  bash "$ROOT/tools/codegen-linux.sh"
fi

step "4/4 Build"
bash "$ROOT/tools/build.sh" release

printf '\nAll done. Start the game with:  ./play-linux.sh\n'
