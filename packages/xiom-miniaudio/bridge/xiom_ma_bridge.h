// XIOM -- MiniAudio C Bridge Header
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
void        xma_sound_set_pan(int64_t sound, float pan);
void        xma_sound_set_pitch(int64_t sound, float pitch);
int32_t     xma_sound_set_looping(int64_t sound, int32_t looping);
int32_t     xma_sound_seek_to_pcm_frame(int64_t sound, int64_t frame_index);

void        xma_engine_listener_set_position(int64_t engine, int32_t listener,
                                              float x, float y, float z);
void        xma_engine_listener_set_direction(int64_t engine, int32_t listener,
                                               float x, float y, float z);
void        xma_engine_listener_set_velocity(int64_t engine, int32_t listener,
                                              float x, float y, float z);
void        xma_engine_listener_set_world_up(int64_t engine, int32_t listener,
                                              float x, float y, float z);
void        xma_engine_listener_set_enabled(int64_t engine, int32_t listener,
                                             int32_t enabled);

int64_t     xma_noise_create(int32_t type, int32_t sample_rate, int32_t channels,
                              int32_t seed, float amplitude);
void        xma_noise_destroy(int64_t noise);
int32_t     xma_noise_set_type(int64_t noise, int32_t type);
int32_t     xma_noise_set_seed(int64_t noise, int32_t seed);
int32_t     xma_noise_set_amplitude(int64_t noise, float amplitude);

int64_t     xma_play_noise(int64_t engine, int64_t noise);

void        xma_sleep_ms(int32_t milliseconds);
const char* xma_result_string(int32_t result);

#ifdef __cplusplus
}
#endif

#endif // XIOM_MA_BRIDGE_H_
