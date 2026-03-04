#ifndef FT8_BRIDGE_H
#define FT8_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Protocol identifiers
#define FT8_BRIDGE_PROTO_FT8 0
#define FT8_BRIDGE_PROTO_FT4 1

/// Callback invoked once per decoded message during ft8_bridge_decode_slot.
/// @param message  Null-terminated decoded text (e.g. "CQ K1ABC FN42")
/// @param freq_hz  Estimated audio frequency in Hz
/// @param time_sec Estimated time offset within the slot in seconds
/// @param snr      Rough signal-to-noise ratio approximation
/// @param userdata Opaque pointer forwarded from ft8_bridge_decode_slot
typedef void (*ft8_bridge_msg_cb)(const char* message,
                                  float freq_hz,
                                  float time_sec,
                                  float snr,
                                  void* userdata);

/// Decode a single FT8 or FT4 audio slot.
/// @param samples     Float PCM audio samples (range ~[-1, +1])
/// @param num_samples Number of audio samples
/// @param sample_rate Audio sample rate in Hz (12000 recommended)
/// @param protocol    FT8_BRIDGE_PROTO_FT8 or FT8_BRIDGE_PROTO_FT4
/// @param callback    Called once for each distinct decoded message
/// @param userdata    Forwarded unchanged to callback
void ft8_bridge_decode_slot(const float* samples,
                             int num_samples,
                             int sample_rate,
                             int protocol,
                             ft8_bridge_msg_cb callback,
                             void* userdata);

/// Returns the number of PCM samples ft8_bridge_encode_audio will produce.
int ft8_bridge_audio_sample_count(int protocol, int sample_rate);

/// Encode a message to GFSK audio (FT8 or FT4).
/// @param message     Text to encode (e.g. "CQ AI5OS EM10"), max 35 characters
/// @param protocol    FT8_BRIDGE_PROTO_FT8 or FT8_BRIDGE_PROTO_FT4
/// @param f0          Base audio frequency in Hz (e.g. 1500.0)
/// @param sample_rate Output sample rate in Hz (e.g. 12000)
/// @param out_samples Caller-allocated output buffer, size >= ft8_bridge_audio_sample_count(protocol, sample_rate)
/// @return 0 on success, -1 if the message cannot be encoded
int ft8_bridge_encode_audio(const char* message,
                             int protocol,
                             float f0,
                             int sample_rate,
                             float* out_samples);

/// Store a callsign-to-hash mapping for decoding non-standard (<CALLSIGN>) messages.
void ft8_bridge_add_callsign(const char* callsign, uint32_t n22);

/// Clear all stored callsign hashes.
void ft8_bridge_clear_callsigns(void);

#ifdef __cplusplus
}
#endif

#endif // FT8_BRIDGE_H
