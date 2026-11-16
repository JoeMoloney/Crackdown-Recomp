#!/usr/bin/env bash
# Starts the game built by ./setup-linux.sh, reading the game files from extracted_game/.
# Settings: edit config/crackdown.toml, then run ./setup-linux.sh again to copy it into the build.
# Extra arguments are passed to the game and win over the file, e.g. ./play-linux.sh --fullscreen=true
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME="$ROOT/out/build/linux-amd64-release/crackdown"

[[ -x "$GAME" ]] || { echo "play-linux: no build yet, run ./setup-linux.sh first" >&2; exit 1; }
[[ -f "$ROOT/extracted_game/default.xex" ]] || { echo "play-linux: no game files, run ./setup-linux.sh /path/to/Crackdown.iso" >&2; exit 1; }

exec "$GAME" --game_data_root="$ROOT/extracted_game" --crackdown_skip_launcher=true "$@"
