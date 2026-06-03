/*
 * RADEFargan.c — see RADEFargan.h.
 *
 * Wraps the FARGAN vocoder from the vendored libopus. config.h (the
 * arch-dispatching header under ThirdParty/opus/include) MUST be included
 * before any opus header so this translation unit sees the same feature macros
 * its slice of libopus.a was built with (notably FARGANState's layout).
 */
#include "config.h"

#include <stdlib.h>
#include <string.h>

#include "fargan.h"   /* FARGANState, fargan_init/cont/synthesize, FARGAN_CONT_SAMPLES */
#include "freq.h"     /* NB_FEATURES, NB_TOTAL_FEATURES */
#include "lpcnet.h"   /* LPCNET_FRAME_SIZE */

#include "RADEFargan.h"

/* Keep the Swift-facing constants locked to the opus definitions. */
#if NB_TOTAL_FEATURES != RADE_FARGAN_FEATURES_PER_FRAME
#error "RADE_FARGAN_FEATURES_PER_FRAME out of sync with opus NB_TOTAL_FEATURES"
#endif
#if LPCNET_FRAME_SIZE != RADE_FARGAN_SAMPLES_PER_FRAME
#error "RADE_FARGAN_SAMPLES_PER_FRAME out of sync with opus LPCNET_FRAME_SIZE"
#endif

#define WARMUP_FRAMES 5

struct RADEFargan {
    FARGANState fargan;
    float       cont_buf[WARMUP_FRAMES * NB_TOTAL_FEATURES];
    int         cont_frames;   /* warm-up frames buffered so far */
    int         ready;         /* non-zero once fargan_cont has run */
};

RADEFargan *rade_fargan_create(void) {
    RADEFargan *f = (RADEFargan *)calloc(1, sizeof(RADEFargan));
    if (!f) return NULL;
    rade_fargan_reset(f);
    return f;
}

void rade_fargan_destroy(RADEFargan *f) {
    free(f);
}

void rade_fargan_reset(RADEFargan *f) {
    if (!f) return;
    fargan_init(&f->fargan);
    f->cont_frames = 0;
    f->ready = 0;
}

int rade_fargan_synthesize(RADEFargan *f, const float *features,
                           int nFrames, float *pcmOut) {
    if (!f || !features || !pcmOut || nFrames <= 0) return 0;

    int written = 0;
    for (int i = 0; i < nFrames; i++) {
        const float *feat = &features[i * NB_TOTAL_FEATURES];

        /* Warm-up: buffer the first WARMUP_FRAMES frames, then prime FARGAN
         * with fargan_cont(). These frames are consumed, not synthesized. */
        if (!f->ready) {
            memcpy(&f->cont_buf[f->cont_frames * NB_TOTAL_FEATURES],
                   feat, (size_t)NB_TOTAL_FEATURES * sizeof(float));
            if (++f->cont_frames >= WARMUP_FRAMES) {
                /* fargan_cont wants features packed at stride NB_FEATURES. */
                float packed[WARMUP_FRAMES * NB_FEATURES];
                for (int k = 0; k < WARMUP_FRAMES; k++) {
                    memcpy(&packed[k * NB_FEATURES],
                           &f->cont_buf[k * NB_TOTAL_FEATURES],
                           (size_t)NB_FEATURES * sizeof(float));
                }
                float zeros[FARGAN_CONT_SAMPLES];
                memset(zeros, 0, sizeof(zeros));
                fargan_cont(&f->fargan, zeros, packed);
                f->ready = 1;
            }
            continue;
        }

        fargan_synthesize(&f->fargan, &pcmOut[written], feat);
        written += LPCNET_FRAME_SIZE;
    }
    return written;
}
