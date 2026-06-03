#!/usr/bin/env bash
#
# build_librade_opus.sh
#
# Rebuilds the vendored RADE (FreeDV neural voice) dependency from source and
# refreshes the committed artifacts under ThirdParty/. Run this only when
# bumping the pinned upstream versions; the produced files are committed so a
# normal app build needs nothing here.
#
# What it produces:
#   ThirdParty/opus/lib/libopus.a            universal (arm64 + x86_64) static
#                                            libopus built WITH FARGAN/OSCE/DRED
#                                            (the neural vocoder + its weights)
#   ThirdParty/opus/include/                 opus internal headers + per-arch
#                                            config_{arm64,x86_64}.h
#   ThirdParty/radae/src/                    librade pure-C library sources
#                                            (no Python, no PyTorch, no model file)
#
# Upstream: RADE is integrated the same way the official FreeDV GUI 2.2.x does —
# via the pure-C "no Python" port, not the PyTorch reference implementation.
#
# Requirements (macOS): Xcode CLT, cmake, autoconf, automake, libtool, pkg-config.
#   brew install cmake autoconf automake libtool pkg-config
# Homebrew installs libtoolize as "glibtoolize"; autoreconf is pointed at it via
# the LIBTOOLIZE env var below.
#
set -euo pipefail

# --- pinned upstream versions ---------------------------------------------
RADAE_NOPY_REPO="https://github.com/peterbmarks/radae_nopy.git"
RADAE_NOPY_COMMIT="b2891023f3aecdf8b1793618000b1be6bcb2c4d1"
# opus is fetched by radae_nopy's own CMake; this URL is pinned there and passed
# through for clarity / override.
OPUS_URL="https://github.com/xiph/opus/archive/940d4e5af64351ca8ba8390df3f555484c567fbb.zip"

# --- paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/librade_build.XXXXXX")"
trap 'echo "Build tree left at: $WORK"' EXIT

echo "==> Cloning radae_nopy @ ${RADAE_NOPY_COMMIT}"
git clone "$RADAE_NOPY_REPO" "$WORK/radae_nopy"
git -C "$WORK/radae_nopy" checkout --quiet "$RADAE_NOPY_COMMIT"

echo "==> Building universal opus(+FARGAN) and librade"
mkdir -p "$WORK/radae_nopy/build"
(
  cd "$WORK/radae_nopy/build"
  export LIBTOOLIZE="${LIBTOOLIZE:-glibtoolize}"
  cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_OSX_UNIVERSAL=ON \
        -DOPUS_URL="$OPUS_URL" ..
  make -j"$(sysctl -n hw.logicalcpu)"
)

BUILD="$WORK/radae_nopy/build"
OPUSARM="$BUILD/build_opus_arm-prefix/src/build_opus_arm"
OPUSX86="$BUILD/build_opus_x86-prefix/src/build_opus_x86"
SRC="$WORK/radae_nopy/src"

echo "==> Verifying universal libopus.a with FARGAN"
lipo -info "$BUILD/libopus.a" | grep -q "x86_64 arm64"
nm "$BUILD/libopus.a" | grep -q "T _fargan_synthesize"

echo "==> Refreshing ThirdParty/radae/src"
rm -rf "$ROOT/ThirdParty/radae/src"
mkdir -p "$ROOT/ThirdParty/radae/src"
# library translation units only (the tool/test mains are intentionally omitted;
# kiss_fft* are omitted too — librade uses opus's FFT and the names collide with
# the vendored codec2's kiss_fft.h)
for f in rade_api_nopy.c rade_enc.c rade_dec.c rade_enc_data.c rade_dec_data.c \
         rade_dsp.c rade_ofdm.c rade_bpf.c rade_acq.c rade_tx.c rade_rx.c \
         rade_api.h rade_dsp.h rade_ofdm.h rade_bpf.h rade_acq.h rade_tx.h \
         rade_rx.h rade_enc.h rade_dec.h rade_enc_data.h rade_dec_data.h \
         rade_core.h rade_constants.h; do
  cp "$SRC/$f" "$ROOT/ThirdParty/radae/src/"
done
cp "$WORK/radae_nopy/LICENSE" "$ROOT/ThirdParty/radae/LICENSE"

echo "==> Refreshing ThirdParty/opus"
mkdir -p "$ROOT/ThirdParty/opus/lib" "$ROOT/ThirdParty/opus/include"
cp "$BUILD/libopus.a" "$ROOT/ThirdParty/opus/lib/libopus.a"
# headers only, preserving subdirs (arm/, x86/, mips/ SIMD variants are referenced)
rm -rf "$ROOT/ThirdParty/opus/include"/{dnn,celt,silk,include}
for d in dnn celt silk include; do
  (cd "$OPUSARM" && find "$d" -name '*.h' -print0 |
     rsync -a --files-from=- --from0 ./ "$ROOT/ThirdParty/opus/include/")
done
cp "$OPUSARM/config.h" "$ROOT/ThirdParty/opus/include/config_arm64.h"
cp "$OPUSX86/config.h" "$ROOT/ThirdParty/opus/include/config_x86_64.h"
# NOTE: ThirdParty/opus/include/config.h is the hand-written arch dispatcher
# and is NOT overwritten here.

echo "==> Done. Pinned: radae_nopy=${RADAE_NOPY_COMMIT}"
echo "    Review 'git status ThirdParty/' and commit."
