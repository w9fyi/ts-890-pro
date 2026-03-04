#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVPROJECTS_ROOT="${DEVPROJECTS_ROOT:-$HOME/Desktop/devprojects}"

# Allow override, with new default tree under ~/Desktop/devprojects.
if [ -n "${RNNOISE_SRC_DIR:-}" ]; then
  SRC_DIR="$RNNOISE_SRC_DIR"
else
  SRC_CANDIDATES=(
    "$DEVPROJECTS_ROOT/apache-thetis/Project Files/lib/NR_Algorithms_x64/src/rnnoise"
    "$HOME/Downloads/apache-thetis/Project Files/lib/NR_Algorithms_x64/src/rnnoise"
  )
  SRC_DIR="${SRC_CANDIDATES[0]}"
  for candidate in "${SRC_CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
      SRC_DIR="$candidate"
      break
    fi
  done
fi

OUT_DIR="${RNNOISE_OUT_DIR:-$ROOT_DIR/ThirdParty/NR/build}"

if [ ! -d "$SRC_DIR" ]; then
  echo "RNNoise source directory not found: $SRC_DIR" >&2
  echo "Set RNNOISE_SRC_DIR to your rnnoise source checkout and retry." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
pushd "$SRC_DIR" >/dev/null

# Configure and build static library for macOS without x86 rtcd.
CC=clang CFLAGS="-O3 -fPIC" ./configure --disable-x86-rtcd --disable-examples --enable-static --enable-shared=no || true
make clean || true
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make -j"$JOBS" || true

# Copy produced static library to OUT_DIR.
if [ -f src/.libs/librnnoise.a ]; then
  cp src/.libs/librnnoise.a "$OUT_DIR/rnnoise.a"
elif [ -f librnnoise.a ]; then
  cp librnnoise.a "$OUT_DIR/rnnoise.a"
fi

# Copy model weights if present.
cp -v models/* "$OUT_DIR/" 2>/dev/null || true
popd >/dev/null
