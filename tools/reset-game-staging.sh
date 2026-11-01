#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="$ROOT/game_iso"
EXTRACTED_DIR="$ROOT/extracted_game"

for path in "$ISO_DIR" "$EXTRACTED_DIR"; do
    if [[ -L "$path" ]]; then
        echo "Refusing to reset symlinked path: $path" >&2
        exit 1
    fi
done

echo "This will remove ISO files directly inside: $ISO_DIR"
echo "This will remove the extracted game directory: $EXTRACTED_DIR"
echo "It will preserve game_iso/.env and the scripts."
read -r -p 'Type RESET to continue: ' confirmation
if [[ "$confirmation" != RESET ]]; then
    echo "Reset cancelled."
    exit 0
fi

if [[ -d "$ISO_DIR" ]]; then
    find "$ISO_DIR" -maxdepth 1 -type f -iname '*.iso' -print -delete
fi

if [[ -e "$EXTRACTED_DIR" ]]; then
    rm -rf -- "$EXTRACTED_DIR"
fi

echo "Game staging reset complete."
