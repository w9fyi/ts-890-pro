/*
 * RADEEncoder.c — see RADEEncoder.h.
 *
 * Wraps the LPCNet feature extractor from the vendored libopus. config.h (the
 * arch-dispatching header under ThirdParty/opus/include) MUST be included
 * before any opus header so this translation unit sees the same feature macros
 * its slice of libopus.a was built with (notably LPCNetEncState's layout).
 */
#include "config.h"

#include <stdlib.h>

#include "lpcnet.h"   /* LPCNetEncState, lpcnet_encoder_*, lpcnet_compute_single_frame_features */
#include "freq.h"     /* NB_TOTAL_FEATURES */

#include "RADEEncoder.h"

/* Keep the Swift-facing constants locked to the opus definitions. */
#if NB_TOTAL_FEATURES != RADE_ENC_FEATURES_PER_FRAME
#error "RADE_ENC_FEATURES_PER_FRAME out of sync with opus NB_TOTAL_FEATURES"
#endif
#if LPCNET_FRAME_SIZE != RADE_ENC_SAMPLES_PER_FRAME
#error "RADE_ENC_SAMPLES_PER_FRAME out of sync with opus LPCNET_FRAME_SIZE"
#endif

struct RADEEncoder {
    LPCNetEncState *st;
};

RADEEncoder *rade_encoder_create(void) {
    RADEEncoder *e = (RADEEncoder *)calloc(1, sizeof(RADEEncoder));
    if (!e) return NULL;
    e->st = lpcnet_encoder_create();
    if (!e->st) { free(e); return NULL; }
    lpcnet_encoder_init(e->st);
    return e;
}

void rade_encoder_destroy(RADEEncoder *e) {
    if (!e) return;
    if (e->st) lpcnet_encoder_destroy(e->st);
    free(e);
}

void rade_encoder_reset(RADEEncoder *e) {
    if (e && e->st) lpcnet_encoder_init(e->st);
}

int rade_encoder_compute_features(RADEEncoder *e, const short *pcm,
                                  float *features) {
    if (!e || !e->st || !pcm || !features) return 0;
    /* arch=0 forces the portable C path, matching how librade itself calls its
     * core encoder (rade_tx.c uses arch=0). Feature extraction is light. */
    lpcnet_compute_single_frame_features(e->st, pcm, features, 0);
    return 1;
}
