#!/usr/bin/env bash
# Build the pinned ReXGlue source on Linux and generate the base-game C++ guest.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$ROOT/third_party/rexglue-sdk"
WORK="$ROOT/out/rexglue-codegen"
SDK_SOURCE="$WORK/source"
SDK_BUILD="$WORK/build"
PATCH_DIR="$ROOT/patches/rexglue-sdk"
MSPACK_PATCH="$ROOT/patches/rexglue-codegen-linux/vendored-mspack.patch"
MANIFEST=crackdown_manifest.toml
EXTRACTED="$ROOT/extracted_game"
XEX_IN="$EXTRACTED/default.xex"
XEX_OUT="$ROOT/game/assets/default.xex"
JOBS="${JOBS:-6}"
CC="${CC:-clang}"
CXX="${CXX:-clang++}"
EXPECTED_XEX_SHA256=7AAA7A8920D1C3C737E58CF583DEBAFE6013BE0A96BEC3EC136E5DE7E3377E5A

fail() { echo "ERROR: $*" >&2; exit 1; }
sha_upper() { sha256sum "$1" | cut -d' ' -f1 | tr 'a-f' 'A-F'; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    echo "Usage: $0"
    echo "Build the pinned Linux ReXGlue codegen tool and generate the base-game guest."
    echo "Inputs: extracted_game/default.xex and the committed ReXGlue submodule pin."
    exit 0
fi
[[ $# -eq 0 ]] || fail "this script takes no arguments (use --help for details)"

[[ "$(uname -s)" == Linux ]] || fail "this script runs on Linux only"
for tool in git cmake ninja python3 sha256sum "$CC" "$CXX"; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done
[[ -e "$SDK/.git" ]] || fail "ReXGlue submodule missing; run: git submodule update --init third_party/rexglue-sdk"

SDK_PIN="$(git -C "$ROOT" ls-tree HEAD third_party/rexglue-sdk | awk '{print $3}')"
[[ -n "$SDK_PIN" ]] || fail "third_party/rexglue-sdk is not recorded in HEAD; commit the submodule reference first"
SDK_HEAD="$(git -C "$SDK" rev-parse HEAD)"
[[ "$SDK_HEAD" == "$SDK_PIN" ]] || fail "ReXGlue checkout ($SDK_HEAD) differs from the repo's pinned commit ($SDK_PIN)"

[[ -f "$XEX_IN" && ! -L "$XEX_IN" ]] || fail "missing local extracted XEX: $XEX_IN"
[[ "$(sha_upper "$XEX_IN")" == "$EXPECTED_XEX_SHA256" ]] || fail "extracted_game/default.xex is not the supported base-game XEX"
python3 -I "$ROOT/tools/make-game-manifest.py" --verify "$EXTRACTED"

# ReXGlue resolves game paths relative to the manifest's game_root. Copy only the XEX needed for codegen;
# the complete extracted game remains in extracted_game/.
[[ ! -L "$ROOT/game" ]] || fail "refusing symlinked game directory"
mkdir -p "$ROOT/game"
[[ ! -L "$ROOT/game/assets" ]] || fail "refusing symlinked game/assets directory"
mkdir -p "$ROOT/game/assets"
[[ ! -L "$XEX_OUT" ]] || fail "refusing symlinked game/assets codegen input"
if [[ ! -f "$XEX_OUT" ]] || ! cmp -s "$XEX_IN" "$XEX_OUT"; then
    cp -- "$XEX_IN" "$XEX_OUT"
fi

if [[ "${FORCE_CODEGEN:-0}" != 1 ]] && bash "$ROOT/tools/check-guest-code.sh" "$ROOT" >/dev/null 2>&1; then
    echo "Base-game guest is already current; set FORCE_CODEGEN=1 to regenerate it."
    exit 0
fi

mkdir -p "$WORK"
if [[ -e "$SDK_SOURCE" ]]; then
    git -C "$SDK_SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        fail "$SDK_SOURCE exists but is not the ReXGlue build worktree"
    [[ "$(git -C "$SDK_SOURCE" rev-parse HEAD)" == "$SDK_PIN" ]] ||
        fail "ReXGlue build worktree is not at pinned commit $SDK_PIN"
else
    git -C "$SDK" worktree add --detach "$SDK_SOURCE" "$SDK_PIN"
fi

# Initialize only the SDK dependencies used by its Linux build. libmspack is vendored in this fork, not a submodule.
SDK_DEPS=(cli11 FFmpeg tomlplusplus simde xxHash spdlog fmt utfcpp imgui sdl3
          vulkan-headers vulkan-memory-allocator spirv-headers spirv-tools glslang o1heap inja)
SDK_DEP_PATHS=()
for dep in "${SDK_DEPS[@]}"; do SDK_DEP_PATHS+=("thirdparty/$dep"); done
git -C "$SDK_SOURCE" submodule update --init --jobs "$JOBS" -- "${SDK_DEP_PATHS[@]}"

if ! grep -qF 'This fork vendors libmspack as ordinary source files' "$SDK_SOURCE/thirdparty/CMakeLists.txt"; then
    git -C "$SDK_SOURCE" apply --check "$MSPACK_PATCH" || fail "vendored-libmspack compatibility patch does not apply"
    git -C "$SDK_SOURCE" apply "$MSPACK_PATCH"
fi

codegen_patches=()
for patch in "$PATCH_DIR"/*.patch; do
    [[ -e "$patch" ]] || continue
    case "$patch" in *.windows.patch) continue ;; esac
    if grep -Eq '^diff --git a/(src/codegen|resources/templates/codegen)/' "$patch"; then
        codegen_patches+=("$patch")
    fi
done
[[ ${#codegen_patches[@]} -gt 0 ]] || fail "no ReXGlue codegen patches found"
VECTOR_BUILDER="$SDK_SOURCE/src/codegen/builders/vector.cpp"
PCH_TEMPLATE="$SDK_SOURCE/resources/templates/codegen/pch_h.inja"
if grep -qF 'Xenos float16 as in rex::float_to_xenos_half' "$VECTOR_BUILDER" &&
   grep -qF 'rex::ppc::simde_mm_vrsqrtefp' "$VECTOR_BUILDER" &&
   grep -qF 'inline simde__m128 simde_mm_vmaddfp' "$PCH_TEMPLATE"; then
    echo "Crackdown codegen patches are already applied in the SDK build worktree."
else
    if grep -qF 'Xenos float16 as in rex::float_to_xenos_half' "$VECTOR_BUILDER" ||
       grep -qF 'rex::ppc::simde_mm_vrsqrtefp' "$VECTOR_BUILDER" ||
       grep -qF 'inline simde__m128 simde_mm_vmaddfp' "$PCH_TEMPLATE"; then
        fail "SDK codegen worktree has a partial patch set; remove $SDK_SOURCE and rerun"
    fi
    for patch in "${codegen_patches[@]}"; do
        git -C "$SDK_SOURCE" apply --check "$patch" || fail "patch does not apply cleanly: $patch"
        git -C "$SDK_SOURCE" apply "$patch"
    done
fi

cmake -S "$SDK_SOURCE" -B "$SDK_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2 \
    -DREXGLUE_USE_VULKAN=ON -DREXGLUE_BUILD_TESTS=OFF \
    -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=OFF \
    -DREXGLUE_ENABLE_FIDELITYFX=OFF
cmake --build "$SDK_BUILD" --target rexglue --parallel "$JOBS"

REXGLUE="$SDK_SOURCE/out/linux-amd64/rexglue"
[[ -x "$REXGLUE" ]] || fail "ReXGlue codegen executable not found at $REXGLUE"

mkdir -p "$ROOT/generated"
rm -f "$ROOT/generated/codegen-inputs.stamp"
(cd "$ROOT" && "$REXGLUE" codegen --ignore-stamp "$MANIFEST" 2>&1 | tee "$ROOT/generated/codegen.log")
[[ -f "$ROOT/generated/default/sources.cmake" ]] || fail "ReXGlue did not produce generated/default/sources.cmake"

# Record the tool, exact source revision, and all codegen inputs for build.sh/check-guest-code.sh.
patch_lines=""
for patch in "${codegen_patches[@]}"; do
    patch_lines+="${patch_lines:+$'\n'}$(basename "$patch")=$(sha_upper "$patch")"
done
tool_id="patched-$(printf '%s' "$patch_lines" | sha256sum | cut -c1-12)"
{
    printf 'rexglue  %s %s source-%s\n' \
        "$(sed -n 's/^SDK_VERSION=//p' "$PATCH_DIR/baseline.env" | tr -d '\r')" "$tool_id" "$SDK_PIN"
    for path in "$MANIFEST" game/assets/default.xex; do
        printf '%s  %s\n' "$(sha_upper "$ROOT/$path")" "$path"
    done
    while IFS= read -r include; do
        [[ -n "$include" ]] || continue
        [[ -f "$ROOT/$include" ]] || fail "missing manifest include: $include"
        printf '%s  %s\n' "$(sha_upper "$ROOT/$include")" "$include"
    done < <(sed -n '/^[[:space:]]*includes[[:space:]]*=/s/.*\[\(.*\)\].*/\1/p' "$ROOT/$MANIFEST" |
             grep -oE '"[^"]+"' | tr -d '"')
} > "$ROOT/generated/codegen-inputs.stamp"

bash "$ROOT/tools/check-guest-code.sh" "$ROOT"
echo "Base-game codegen complete: $ROOT/generated/default"
