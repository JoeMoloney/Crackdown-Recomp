#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Check if .env file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE. Create it from .env.example and set CRACKDOWN_GAME to your ISO path." >&2
    exit 1
fi

# .env is a shell-style file containing CRACKDOWN_GAME=/path/to/game.iso.
# shellcheck disable=SC1090
source "$ENV_FILE"

# Check if .env variable is populated
if [[ -z "${CRACKDOWN_GAME:-}" ]]; then
    echo "CRACKDOWN_GAME is empty in $ENV_FILE." >&2
    exit 1
fi
# Check if files exist at its location
if [[ ! -f "$CRACKDOWN_GAME" ]]; then
    echo "Game ISO not found: $CRACKDOWN_GAME" >&2
    exit 1
fi
# Check if files is of the .iso persuasion
if [[ "${CRACKDOWN_GAME,,}" != *.iso ]]; then
    echo "CRACKDOWN_GAME must point to an ISO file: $CRACKDOWN_GAME" >&2
    exit 1
fi

source_path="$(realpath -- "$CRACKDOWN_GAME")"
destination="$SCRIPT_DIR/$(basename -- "$CRACKDOWN_GAME")"

# Check if .iso has already been copied here
if [[ "$source_path" == "$destination" ]]; then
    echo "The ISO is already in $SCRIPT_DIR; nothing to copy." >&2
    exit 1
fi

if [[ -e "$destination" ]]; then
    echo "Destination already exists: $destination" >&2
    echo "Remove or move it before copying again; the script will not overwrite it." >&2
    exit 1
fi

temporary="$(mktemp "$SCRIPT_DIR/.game-iso-copy.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT

if command -v pv >/dev/null 2>&1; then
    pv --progress --timer --eta --rate --bytes "$source_path" > "$temporary"
elif command -v rsync >/dev/null 2>&1; then
    rsync -a --info=progress2 -- "$source_path" "$temporary"
else
    echo "Install 'pv' or 'rsync' to copy with progress (e.g. sudo apt install pv)." >&2
    exit 1
fi

chmod --reference="$source_path" "$temporary"
touch --reference="$source_path" "$temporary"
mv -- "$temporary" "$destination"
trap - EXIT
echo "Copied game ISO to: $destination"
