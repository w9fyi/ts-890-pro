/*
 * RADEEncoder.h
 *
 * Minimal, Swift-facing C shim around the LPCNet feature extractor that lives
 * inside the vendored libopus (ThirdParty/opus). RADE's transmitter
 * (rade_tx) consumes 36-float feature vectors, not audio; this shim turns
 * 16 kHz speech into those feature vectors — the encode-side counterpart to
 * RADEFargan, which turns the decoder's feature vectors back into speech.
 *
 * Like RADEFargan it deliberately exposes NONE of opus's internal headers so
 * the Swift bridging header stays clean (the opus dnn/celt headers collide with
 * codec2 and rnnoise and must not leak into the global Swift compile).
 *
 * Mirrors the feature-extraction path used by FreeDV's RADE transmitter:
 *   16 kHz Int16 speech, one LPCNET_FRAME_SIZE (160-sample, 10 ms) frame at a
 *   time → lpcnet_compute_single_frame_features() → NB_TOTAL_FEATURES floats.
 * The extractor is stateful (it carries pitch/cepstral history across calls),
 * so feed consecutive, non-overlapping 160-sample frames in order and reset at
 * the start of each over.
 */
#ifndef RADEEncoder_h
#define RADEEncoder_h

/* RADE feature frame size (NB_TOTAL_FEATURES) and the speech frame size the
 * extractor consumes (LPCNET_FRAME_SIZE, samples at RADE_SPEECH_SAMPLE_RATE =
 * 16 kHz). Kept in sync with the opus headers; verified at compile time in .c. */
#define RADE_ENC_FEATURES_PER_FRAME 36
#define RADE_ENC_SAMPLES_PER_FRAME  160

typedef struct RADEEncoder RADEEncoder;

/* Create / destroy an extractor instance. Returns NULL on allocation failure. */
RADEEncoder *rade_encoder_create(void);
void         rade_encoder_destroy(RADEEncoder *e);

/* Discard continuation state so the next compute() starts from a clean history.
 * Call at the start of each over (PTT down). */
void rade_encoder_reset(RADEEncoder *e);

/* Compute the RADE feature vector for ONE 16 kHz speech frame.
 *
 *   pcm      : RADE_ENC_SAMPLES_PER_FRAME (160) Int16 samples at 16 kHz.
 *   features : caller buffer of at least RADE_ENC_FEATURES_PER_FRAME (36)
 *              floats; receives the feature vector for this 10 ms frame.
 *
 * Returns 1 on success, 0 on invalid arguments. */
int rade_encoder_compute_features(RADEEncoder *e, const short *pcm,
                                  float *features);

#endif /* RADEEncoder_h */
