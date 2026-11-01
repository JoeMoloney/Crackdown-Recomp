#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="$ROOT/game_iso"
EXTRACTED_DIR="$ROOT/extracted_game"
CODEGEN_OUT="$ROOT/out/rexglue-codegen"
SDK="$ROOT/third_party/rexglue-sdk"
SDK_SOURCE="$CODEGEN_OUT/source"
GAME_DIR="$ROOT/game"
ASSETS_DIR="$GAME_DIR/assets"
CODEGEN_XEX="$ASSETS_DIR/default.xex"
GENERATED_DIR="$ROOT/generated"

for path in "$ISO_DIR" "$EXTRACTED_DIR" "$CODEGEN_OUT" "$GAME_DIR" "$ASSETS_DIR" \
            "$CODEGEN_XEX" "$GENERATED_DIR" "$GENERATED_DIR/default" \
            "$GENERATED_DIR/codegen-inputs.stamp" "$GENERATED_DIR/codegen.log" \
            "$GENERATED_DIR/rexglue.cmake"; do
    if [[ -L "$path" ]]; then
        echo "Refusing to reset symlinked path: $path" >&2
        exit 1
    fi
done

if [[ -e "$CODEGEN_OUT" && -e "$SDK_SOURCE" ]]; then
    [[ -e "$SDK/.git" ]] || { echo "ReXGlue submodule missing; refusing to remove its worktree." >&2; exit 1; }
    git -C "$SDK" worktree list --porcelain | grep -Fxq "worktree $SDK_SOURCE" || {
        echo "Refusing to remove $SDK_SOURCE because it is not a registered ReXGlue worktree." >&2
        exit 1
    }
fi

if [[ -e "$CODEGEN_XEX" ]]; then
    [[ -f "$CODEGEN_XEX" ]] || { echo "Refusing to remove unexpected path: $CODEGEN_XEX" >&2; exit 1; }
    expected_xex=7aaa7a8920d1c3c737e58cf583debafe6013be0a96bec3ec136e5de7e3377e5a
    actual_xex="$(sha256sum "$CODEGEN_XEX" | cut -d' ' -f1)"
    [[ "$actual_xex" == "$expected_xex" ]] || {
        echo "Refusing to remove unexpected file at $CODEGEN_XEX" >&2
        exit 1
    }
fi

echo "This will remove ISO files directly inside: $ISO_DIR"
echo "This will remove the extracted game directory: $EXTRACTED_DIR"
echo "This will remove the staged codegen XEX: $CODEGEN_XEX"
echo "This will remove base-game generated code and its stamp/log under: $GENERATED_DIR"
echo "This will remove the ReXGlue codegen worktree and build cache: $CODEGEN_OUT"
echo "It will preserve game_iso/.env, the original ISO outside the repo, and the SDK submodule itself."
read -r -p 'Type RESET to continue: ' confirmation
if [[ "$confirmation" != RESET ]]; then
    echo "Reset cancelled."
    exit 0
fi

if [[ -e "$CODEGEN_OUT" ]]; then
    if [[ -e "$SDK_SOURCE" ]]; then
        git -C "$SDK" worktree remove --force "$SDK_SOURCE"
    fi
    rm -rf -- "$CODEGEN_OUT"
fi

if [[ -e "$CODEGEN_XEX" ]]; then
    rm -- "$CODEGEN_XEX"
fi

for path in "$GENERATED_DIR/default" "$GENERATED_DIR/codegen-inputs.stamp" \
            "$GENERATED_DIR/codegen.log" "$GENERATED_DIR/rexglue.cmake"; do
    [[ ! -e "$path" ]] || rm -rf -- "$path"
done

if [[ -d "$ISO_DIR" ]]; then
    find "$ISO_DIR" -maxdepth 1 -type f -iname '*.iso' -print -delete
fi

if [[ -e "$EXTRACTED_DIR" ]]; then
    rm -rf -- "$EXTRACTED_DIR"
fi

echo "Base-game staging and codegen reset complete. Run the README steps to rebuild from the original ISO."
