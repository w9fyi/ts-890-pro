/*
 * RADEFargan.h
 *
 * Minimal, Swift-facing C shim around the FARGAN neural vocoder that lives
 * inside the vendored libopus (ThirdParty/opus). RADE's decoder emits FARGAN
 * feature vectors, not audio; this shim turns those features into 16 kHz
 * speech. It deliberately exposes NONE of opus's internal headers so the Swift
 * bridging header stays clean (the opus dnn/celt headers collide with codec2
 * and rnnoise and must not leak into the global Swift compile).
 *
 * Mirrors the proven warm-up + synthesis loop in radae_nopy's rade_demod_wav.c.
 */
#ifndef RADEFargan_h
#define RADEFargan_h

/* RADE feature frame size (NB_TOTAL_FEATURES) and FARGAN output frame size
 * (LPCNET_FRAME_SIZE, samples at RADE_SPEECH_SAMPLE_RATE = 16 kHz). Kept in
 * sync with the opus headers; verified against them at compile time in the .c. */
#define RADE_FARGAN_FEATURES_PER_FRAME 36
#define RADE_FARGAN_SAMPLES_PER_FRAME  160

typedef struct RADEFargan RADEFargan;

/* Create / destroy a vocoder instance. Returns NULL on allocation failure. */
RADEFargan *rade_fargan_create(void);
void        rade_fargan_destroy(RADEFargan *f);

/* Discard continuation state so the next synthesize() re-primes the vocoder
 * with a fresh 5-frame warm-up. Call on open and whenever the feature stream
 * has a discontinuity you want a clean restart for. */
void rade_fargan_reset(RADEFargan *f);

/* Synthesize speech from RADE feature frames.
 *
 *   features : nFrames * RADE_FARGAN_FEATURES_PER_FRAME floats (row-major).
 *   nFrames  : number of feature frames.
 *   pcmOut   : caller buffer of at least
 *              nFrames * RADE_FARGAN_SAMPLES_PER_FRAME floats; receives 16 kHz
 *              audio in roughly [-1, 1].
 *
 * Returns the number of float samples written to pcmOut. The first 5 frames
 * after a reset prime the vocoder (fargan_cont) and produce no output, so the
 * returned count can be less than nFrames * RADE_FARGAN_SAMPLES_PER_FRAME. */
int rade_fargan_synthesize(RADEFargan *f, const float *features,
                           int nFrames, float *pcmOut);

#endif /* RADEFargan_h */
