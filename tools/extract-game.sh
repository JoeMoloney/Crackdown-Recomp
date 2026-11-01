#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/out/extract-game"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <disc.iso> <output-folder>" >&2
    exit 2
fi

cmake -S "$ROOT/tools/extract_game" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --target crackdown_extract_game
exec "$BUILD/crackdown_extract_game" "$1" "$2"
rm -- "$1"
