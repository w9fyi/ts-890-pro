/*
 * Arch-dispatching opus config.h for the vendored universal libopus.a.
 *
 * The opus/FARGAN sources are built per-architecture (see
 * scripts/build_librade_opus.sh), each producing its own config.h with
 * arch-specific SIMD feature macros (NEON vs SSE/AVX). Because Xcode compiles
 * the vendored librade sources and the FARGAN shim for BOTH slices of the
 * universal build using a single header, we must hand each slice the config
 * that matches how its slice of libopus.a was compiled — otherwise struct
 * layouts (e.g. FARGANState) and RTCD declarations could diverge from the
 * archive and break at link or runtime.
 *
 * Do not edit config_arm64.h / config_x86_64.h by hand; they are copied
 * verbatim from the per-arch opus build by the rebuild script.
 */
#ifndef RADE_VENDORED_OPUS_CONFIG_H
#define RADE_VENDORED_OPUS_CONFIG_H

#if defined(__x86_64__)
#include "config_x86_64.h"
#elif defined(__aarch64__) || defined(__arm64__)
#include "config_arm64.h"
#else
#error "Vendored opus: unsupported architecture (expected arm64 or x86_64)"
#endif

#endif /* RADE_VENDORED_OPUS_CONFIG_H */
