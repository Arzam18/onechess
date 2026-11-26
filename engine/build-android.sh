#!/usr/bin/env bash
# Build a standalone Onechess Android ARM64/NEON executable.
# The NNUE file is fetched from the matching upstream release and embedded.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "${NDK_HOME}" || ! -d "${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
    echo "ERROR: ANDROID_NDK_HOME/ANDROID_NDK_ROOT must point to the Android NDK." >&2
    exit 1
fi

TOOLCHAIN="${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
CXX="${TOOLCHAIN}/aarch64-linux-android24-clang++"
CC="${TOOLCHAIN}/aarch64-linux-android24-clang"
READELF="${TOOLCHAIN}/llvm-readelf"
NM="${TOOLCHAIN}/llvm-nm"
if [[ ! -x "${CXX}" || ! -x "${CC}" ]]; then
    echo "ERROR: Android ARM64 compiler not found in ${TOOLCHAIN}." >&2
    exit 1
fi

# This source snapshot identifies itself as Onechess 1.2.1. Its release page
# publishes the matching optional network as onechess.nnue (same network as 1.1/1.2).
NETWORK_URL="https://github.com/ovnice-dev/onechess/releases/download/v1.2.1/onechess.nnue"
NETWORK="${ENGINE_DIR}/onechess.nnue"
mkdir -p "${ENGINE_DIR}/bin"
printf 'Downloading the Onechess 1.2.1 NNUE network...\n'
curl --fail --location --retry 5 --retry-delay 2 --retry-all-errors \
    "${NETWORK_URL}" --output "${NETWORK}"
test -s "${NETWORK}"

cd "${ENGINE_DIR}"
OUT="bin/onechess-android-arm64-neon"
EMBED_OBJ="bin/nnue-embedded.o"
printf 'Building the standalone NNUE embedding object...\n'
"${CC}" -c -fPIC -o "${EMBED_OBJ}" nnue-embedded.S

printf 'Building Onechess for Android ARM64/NEON...\n'
"${CXX}" \
    -std=c++20 -O3 -DNDEBUG -flto=thin -fno-exceptions \
    -march=armv8-a+simd \
    -pthread -fPIE -ffunction-sections -fdata-sections \
    -static-libstdc++ -Wl,--gc-sections -Wl,-z,max-page-size=16384 \
    -DONE_FIGE -DONE_RESEAU='"onechess.nnue"' -DONE_RESEAU_EXTERNAL \
    -Ifathom src/*.cpp fathom/tbprobe.c "${EMBED_OBJ}" \
    -pie -o "${OUT}"

# Confirm this is an AArch64 Android executable and that the embedded NNUE
# boundaries survived linking. Capture tool output before grepping: with
# `set -o pipefail`, `nm | grep -q` can report a false failure when grep exits
# early and nm receives SIGPIPE on a large symbol table.
ELF_HEADER="$("${READELF}" -h "${OUT}")"
grep -Eq 'Machine:.*AArch64' <<< "${ELF_HEADER}" || {
    echo "ERROR: output is not an AArch64 executable." >&2
    exit 1
}
SYMBOL_TABLE="$("${NM}" -g "${OUT}")"
grep -Eq '[[:space:]]one_reseau_debut$' <<< "${SYMBOL_TABLE}" || {
    echo "ERROR: embedded NNUE start symbol is missing." >&2
    exit 1
}
grep -Eq '[[:space:]]one_reseau_fin$' <<< "${SYMBOL_TABLE}" || {
    echo "ERROR: embedded NNUE end symbol is missing." >&2
    exit 1
}

printf '\nBuild complete: %s\n' "${ENGINE_DIR}/${OUT}"
file "${OUT}"
sha256sum "${OUT}"
