// XIOM — MiniAudio C Bridge Header
// Flat ABI for XIOM FFI consumption. No struct passing, no callbacks.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

#ifndef XIOM_MA_BRIDGE_H_
#define XIOM_MA_BRIDGE_H_

#include <stdint.h>

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

int64_t     xma_engine_create(int32_t sample_rate, int32_t channels);
void        xma_engine_destroy(int64_t engine);
int32_t     xma_engine_set_volume(int64_t engine, float volume);
float       xma_engine_get_volume(int64_t engine);

int64_t     xma_waveform_create(int32_t type, int32_t sample_rate,
                                int32_t channels, float amplitude, float frequency);
void        xma_waveform_destroy(int64_t waveform);
int32_t     xma_waveform_set_frequency(int64_t waveform, float frequency);
int32_t     xma_waveform_set_amplitude(int64_t waveform, float amplitude);
int32_t     xma_waveform_set_type(int64_t waveform, int32_t type);

int64_t     xma_play_waveform(int64_t engine, int64_t waveform);
void        xma_sound_stop(int64_t sound);
int32_t     xma_sound_is_playing(int64_t sound);
int32_t     xma_sound_set_volume(int64_t sound, float volume);

void        xma_sleep_ms(int32_t milliseconds);
const char* xma_result_string(int32_t result);

#ifdef __cplusplus
}
#endif

#endif // XIOM_MA_BRIDGE_H_
