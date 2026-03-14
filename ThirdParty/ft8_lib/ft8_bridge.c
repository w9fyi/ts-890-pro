#include "ft8_bridge.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdbool.h>

#include <ft8/decode.h>
#include <ft8/encode.h>
#include <ft8/message.h>
#include <ft8/constants.h>
#include <common/monitor.h>

// ---------------------------------------------------------------------------
// Decoder configuration
// ---------------------------------------------------------------------------
#define FT8B_MIN_SCORE       5    // lowered from 10 — catches weaker candidates on noisy bands
#define FT8B_MAX_CANDIDATES  200  // raised from 140 — don't discard weak signals on busy bands
#define FT8B_LDPC_ITER       40   // raised from 25 — matches WSJT-X normal depth, better weak-signal convergence
#define FT8B_MAX_DECODED     50
#define FT8B_FREQ_OSR        2
#define FT8B_TIME_OSR        2
#define FT8B_HASH_SIZE       256

// ---------------------------------------------------------------------------
// Callsign hash table (algorithm from ft8_lib demo/decode_ft8.c)
// ---------------------------------------------------------------------------

static struct {
    char     callsign[12]; // up to 11 chars + NUL
    uint32_t hash;         // upper 8 bits = age, lower 22 bits = n22
} s_ht[FT8B_HASH_SIZE];

static int s_ht_size = 0;

void ft8_bridge_clear_callsigns(void) {
    memset(s_ht, 0, sizeof(s_ht));
    s_ht_size = 0;
}

void ft8_bridge_add_callsign(const char* callsign, uint32_t n22) {
    uint16_t h10 = (uint16_t)((n22 >> 12) & 0x3FFu);
    int idx = (h10 * 23) % FT8B_HASH_SIZE;
    while (s_ht[idx].callsign[0] != '\0') {
        if (((s_ht[idx].hash & 0x3FFFFFu) == (n22 & 0x3FFFFFu)) &&
            strcmp(s_ht[idx].callsign, callsign) == 0) {
            s_ht[idx].hash &= 0x3FFFFFu; // reset age
            return;
        }
        idx = (idx + 1) % FT8B_HASH_SIZE;
    }
    if (s_ht_size < FT8B_HASH_SIZE) {
        s_ht_size++;
        strncpy(s_ht[idx].callsign, callsign, 11);
        s_ht[idx].callsign[11] = '\0';
        s_ht[idx].hash = n22 & 0x3FFFFFu;
    }
}

static bool s_lookup_hash(ftx_callsign_hash_type_t hash_type, uint32_t hash, char* callsign) {
    uint8_t shift = (hash_type == FTX_CALLSIGN_HASH_10_BITS) ? 12u :
                    (hash_type == FTX_CALLSIGN_HASH_12_BITS) ? 10u : 0u;
    uint16_t h10 = (uint16_t)((hash >> (12u - shift)) & 0x3FFu);
    int idx = (h10 * 23) % FT8B_HASH_SIZE;
    while (s_ht[idx].callsign[0] != '\0') {
        if (((s_ht[idx].hash & 0x3FFFFFu) >> shift) == hash) {
            strcpy(callsign, s_ht[idx].callsign);
            return true;
        }
        idx = (idx + 1) % FT8B_HASH_SIZE;
    }
    callsign[0] = '\0';
    return false;
}

static void s_save_hash(const char* callsign, uint32_t n22) {
    ft8_bridge_add_callsign(callsign, n22);
}

static ftx_callsign_hash_interface_t s_hash_if = {
    .lookup_hash = s_lookup_hash,
    .save_hash   = s_save_hash
};

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

void ft8_bridge_decode_slot(const float* samples,
                             int num_samples,
                             int sample_rate,
                             int protocol,
                             ft8_bridge_msg_cb callback,
                             void* userdata)
{
    ftx_protocol_t proto = (protocol == FT8_BRIDGE_PROTO_FT4)
        ? FTX_PROTOCOL_FT4 : FTX_PROTOCOL_FT8;

    monitor_config_t cfg = {
        .f_min       = 100.0f,
        .f_max       = 3000.0f,
        .sample_rate = sample_rate,
        .time_osr    = FT8B_TIME_OSR,
        .freq_osr    = FT8B_FREQ_OSR,
        .protocol    = proto
    };

    monitor_t mon;
    monitor_init(&mon, &cfg);

    // Feed audio into the waterfall one block at a time
    for (int pos = 0; pos + mon.block_size <= num_samples; pos += mon.block_size) {
        monitor_process(&mon, samples + pos);
    }

    // Find sync candidates
    ftx_candidate_t cands[FT8B_MAX_CANDIDATES];
    int n_cands = ftx_find_candidates(&mon.wf, FT8B_MAX_CANDIDATES, cands, FT8B_MIN_SCORE);

    // Deduplication hash table for decoded messages
    ftx_message_t decoded_msgs[FT8B_MAX_DECODED];
    ftx_message_t* decoded_ht[FT8B_MAX_DECODED];
    for (int i = 0; i < FT8B_MAX_DECODED; ++i) decoded_ht[i] = NULL;

    for (int ci = 0; ci < n_cands; ++ci) {
        const ftx_candidate_t* cand = &cands[ci];

        ftx_message_t msg;
        ftx_decode_status_t st;
        if (!ftx_decode_candidate(&mon.wf, cand, FT8B_LDPC_ITER, &msg, &st)) continue;

        // Deduplicate
        int dh = msg.hash % FT8B_MAX_DECODED;
        bool dup = false, empty = false;
        do {
            if (decoded_ht[dh] == NULL) {
                empty = true;
            } else if (decoded_ht[dh]->hash == msg.hash &&
                       memcmp(decoded_ht[dh]->payload, msg.payload, sizeof(msg.payload)) == 0) {
                dup = true;
            } else {
                dh = (dh + 1) % FT8B_MAX_DECODED;
            }
        } while (!empty && !dup);

        if (dup) continue;

        memcpy(&decoded_msgs[dh], &msg, sizeof(msg));
        decoded_ht[dh] = &decoded_msgs[dh];

        // Unpack to text
        char text[FTX_MAX_MESSAGE_LENGTH];
        ftx_message_offsets_t offsets;
        ftx_message_rc_t rc = ftx_message_decode(&msg, &s_hash_if, text, &offsets);
        if (rc != FTX_MESSAGE_RC_OK) continue;

        float freq_hz  = (mon.min_bin + cand->freq_offset +
                          (float)cand->freq_sub / mon.wf.freq_osr) / mon.symbol_period;
        float time_sec = (cand->time_offset +
                          (float)cand->time_sub / mon.wf.time_osr) * mon.symbol_period;
        float snr      = cand->score * 0.5f;

        if (callback) callback(text, freq_hz, time_sec, snr, userdata);
    }

    monitor_free(&mon);
}

// ---------------------------------------------------------------------------
// GFSK synthesis (logic from ft8_lib demo/gen_ft8.c, reproduced here
// because gen_ft8.c defines main() and is excluded from the build)
// ---------------------------------------------------------------------------

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define FT8B_GFSK_K 5.336446f  // == pi * sqrt(2 / log(2))

static void ft8b_gfsk_pulse(int n_spsym, float symbol_bt, float* pulse) {
    for (int i = 0; i < 3 * n_spsym; ++i) {
        float t  = (float)i / n_spsym - 1.5f;
        float a1 = FT8B_GFSK_K * symbol_bt * (t + 0.5f);
        float a2 = FT8B_GFSK_K * symbol_bt * (t - 0.5f);
        pulse[i] = (erff(a1) - erff(a2)) * 0.5f;
    }
}

static void ft8b_synth_gfsk(const uint8_t* symbols, int n_sym,
                              float f0, float symbol_bt, float symbol_period,
                              int signal_rate, float* signal)
{
    int n_spsym = (int)(0.5f + signal_rate * symbol_period);
    int n_wave  = n_sym * n_spsym;

    float dphi_peak = 2.0f * (float)M_PI / n_spsym;

    int dphi_len = n_wave + 2 * n_spsym;
    float* dphi  = (float*)calloc((size_t)dphi_len, sizeof(float));
    float* pulse = (float*)malloc((size_t)(3 * n_spsym) * sizeof(float));
    if (!dphi || !pulse) { free(dphi); free(pulse); return; }

    // Shift carrier frequency by f0
    for (int i = 0; i < dphi_len; ++i) {
        dphi[i] = 2.0f * (float)M_PI * f0 / signal_rate;
    }

    ft8b_gfsk_pulse(n_spsym, symbol_bt, pulse);

    // Apply symbol shaping
    for (int i = 0; i < n_sym; ++i) {
        int ib = i * n_spsym;
        for (int j = 0; j < 3 * n_spsym; ++j) {
            dphi[j + ib] += dphi_peak * (float)symbols[i] * pulse[j];
        }
    }

    // Dummy symbols at start and end for continuous phase
    for (int j = 0; j < 2 * n_spsym; ++j) {
        dphi[j]                    += dphi_peak * pulse[j + n_spsym]   * (float)symbols[0];
        dphi[j + n_sym * n_spsym]  += dphi_peak * pulse[j]             * (float)symbols[n_sym - 1];
    }

    // Integrate phase and compute waveform
    float phi = 0.0f;
    for (int k = 0; k < n_wave; ++k) {
        signal[k] = sinf(phi);
        phi = fmodf(phi + dphi[k + n_spsym], 2.0f * (float)M_PI);
    }

    // Ramp in/out envelope
    int n_ramp = n_spsym / 8;
    for (int i = 0; i < n_ramp; ++i) {
        float env = (1.0f - cosf(2.0f * (float)M_PI * (float)i / (float)(2 * n_ramp))) * 0.5f;
        signal[i]              *= env;
        signal[n_wave - 1 - i] *= env;
    }

    free(dphi);
    free(pulse);
}

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

int ft8_bridge_audio_sample_count(int protocol, int sample_rate) {
    if (protocol == FT8_BRIDGE_PROTO_FT4) {
        return FT4_NN * (int)(0.5f + sample_rate * FT4_SYMBOL_PERIOD);
    } else {
        return FT8_NN * (int)(0.5f + sample_rate * FT8_SYMBOL_PERIOD);
    }
}

int ft8_bridge_encode_audio(const char* message,
                             int protocol,
                             float f0,
                             int sample_rate,
                             float* out_samples)
{
    ftx_message_t msg;
    ftx_message_init(&msg);

    ftx_message_rc_t rc = ftx_message_encode(&msg, &s_hash_if, message);
    if (rc != FTX_MESSAGE_RC_OK) return -1;

    if (protocol == FT8_BRIDGE_PROTO_FT4) {
        uint8_t tones[FT4_NN];
        ft4_encode(msg.payload, tones);
        ft8b_synth_gfsk(tones, FT4_NN, f0,
                        1.0f,              // FT4 symbol BT
                        FT4_SYMBOL_PERIOD,
                        sample_rate, out_samples);
    } else {
        uint8_t tones[FT8_NN];
        ft8_encode(msg.payload, tones);
        ft8b_synth_gfsk(tones, FT8_NN, f0,
                        2.0f,              // FT8 symbol BT
                        FT8_SYMBOL_PERIOD,
                        sample_rate, out_samples);
    }

    return 0;
}
