// XIOM — MiniAudio C Bridge Implementation
// Provides flat ABI wrappers around miniaudio's transparent-struct API.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

#include "xiom_ma_bridge.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    ma_engine  engine;
    int        owned;
} xma_engine_t;

typedef struct {
    ma_waveform waveform;
} xma_waveform_t;

typedef struct {
    ma_sound sound;
    int      ownsDataSource;
} xma_sound_t;

typedef struct {
    ma_noise noise;
} xma_noise_t;

// ---- Engine ----

int64_t xma_engine_create(int32_t sample_rate, int32_t channels)
{
    xma_engine_t* e = (xma_engine_t*)calloc(1, sizeof(xma_engine_t));
    if (!e) return 0;

    ma_engine_config config = ma_engine_config_init();
    config.sampleRate = (ma_uint32)sample_rate;
    config.channels   = (ma_uint32)channels;
    config.noAutoStart = MA_FALSE;

    ma_result r = ma_engine_init(&config, &e->engine);
    if (r != MA_SUCCESS) {
        free(e);
        return 0;
    }

    e->owned = 1;

    return (int64_t)(intptr_t)e;
}

void xma_engine_destroy(int64_t engine)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_uninit(&e->engine);
    free(e);
}

int32_t xma_engine_set_volume(int64_t engine, float volume)
{
    if (!engine) return -1;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    return (int32_t)ma_engine_set_volume(&e->engine, volume);
}

float xma_engine_get_volume(int64_t engine)
{
    if (!engine) return 0.0f;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    float vol = 1.0f;
    ma_engine_get_volume(&e->engine, &vol);
    return vol;
}

// ---- Waveform ----

int64_t xma_waveform_create(int32_t type, int32_t sample_rate,
                            int32_t channels, float amplitude, float frequency)
{
    xma_waveform_t* w = (xma_waveform_t*)calloc(1, sizeof(xma_waveform_t));
    if (!w) return 0;

    ma_waveform_config config = ma_waveform_config_init(
        ma_format_f32,
        (ma_uint32)channels,
        (ma_uint32)sample_rate,
        (ma_waveform_type)type,
        (double)amplitude,
        (double)frequency
    );

    ma_result r = ma_waveform_init(&config, &w->waveform);
    if (r != MA_SUCCESS) {
        free(w);
        return 0;
    }

    return (int64_t)(intptr_t)w;
}

void xma_waveform_destroy(int64_t waveform)
{
    if (!waveform) return;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;
    ma_waveform_uninit(&w->waveform);
    free(w);
}

int32_t xma_waveform_set_frequency(int64_t waveform, float frequency)
{
    if (!waveform) return -1;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;
    return (int32_t)ma_waveform_set_frequency(&w->waveform, (double)frequency);
}

int32_t xma_waveform_set_amplitude(int64_t waveform, float amplitude)
{
    if (!waveform) return -1;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;
    return (int32_t)ma_waveform_set_amplitude(&w->waveform, (double)amplitude);
}

int32_t xma_waveform_set_type(int64_t waveform, int32_t type)
{
    if (!waveform) return -1;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;
    return (int32_t)ma_waveform_set_type(&w->waveform, (ma_waveform_type)type);
}

// ---- Sound (from waveform) ----

static ma_sound* xma_sound_from_data_source(xma_engine_t* e, ma_data_source* ds)
{
    xma_sound_t* snd = (xma_sound_t*)calloc(1, sizeof(xma_sound_t));
    if (!snd) return NULL;

    snd->ownsDataSource = 0;

    ma_result r = ma_sound_init_from_data_source(
        &e->engine, ds, 0, NULL, &snd->sound);
    if (r != MA_SUCCESS) {
        free(snd);
        return NULL;
    }

    ma_sound_start(&snd->sound);
    return &snd->sound;
}

int64_t xma_play_waveform(int64_t engine, int64_t waveform)
{
    if (!engine || !waveform) return 0;
    xma_engine_t*   e = (xma_engine_t*)(intptr_t)engine;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;

    xma_sound_t* snd = (xma_sound_t*)calloc(1, sizeof(xma_sound_t));
    if (!snd) return 0;

    snd->ownsDataSource = 0;

    ma_result r = ma_sound_init_from_data_source(
        &e->engine, &w->waveform, 0, NULL, &snd->sound);
    if (r != MA_SUCCESS) {
        free(snd);
        return 0;
    }

    ma_sound_start(&snd->sound);

    return (int64_t)(intptr_t)snd;
}

int64_t xma_play_noise(int64_t engine, int64_t noise)
{
    if (!engine || !noise) return 0;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    xma_noise_t*  n = (xma_noise_t*)(intptr_t)noise;

    xma_sound_t* snd = (xma_sound_t*)calloc(1, sizeof(xma_sound_t));
    if (!snd) return 0;

    snd->ownsDataSource = 0;

    ma_result r = ma_sound_init_from_data_source(
        &e->engine, &n->noise, 0, NULL, &snd->sound);
    if (r != MA_SUCCESS) {
        free(snd);
        return 0;
    }

    ma_sound_start(&snd->sound);

    return (int64_t)(intptr_t)snd;
}

void xma_sound_stop(int64_t sound)
{
    if (!sound) return;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_stop(&snd->sound);
    ma_sound_uninit(&snd->sound);
    free(snd);
}

int32_t xma_sound_is_playing(int64_t sound)
{
    if (!sound) return 0;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    return (int32_t)ma_sound_is_playing(&snd->sound);
}

int32_t xma_sound_set_volume(int64_t sound, float volume)
{
    if (!sound) return -1;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_set_volume(&snd->sound, volume);
    return 0;
}

void xma_sound_set_pan(int64_t sound, float pan)
{
    if (!sound) return;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_set_pan(&snd->sound, pan);
}

void xma_sound_set_pitch(int64_t sound, float pitch)
{
    if (!sound) return;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_set_pitch(&snd->sound, pitch);
}

int32_t xma_sound_set_looping(int64_t sound, int32_t looping)
{
    if (!sound) return -1;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_set_looping(&snd->sound, (ma_bool32)looping);
    return 0;
}

int32_t xma_sound_seek_to_pcm_frame(int64_t sound, int64_t frame_index)
{
    if (!sound) return -1;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    return (int32_t)ma_sound_seek_to_pcm_frame(&snd->sound, (ma_uint64)frame_index);
}

// ---- Engine Listeners ----

void xma_engine_listener_set_position(int64_t engine, int32_t listener,
                                       float x, float y, float z)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_listener_set_position(&e->engine, (ma_uint32)listener, x, y, z);
}

void xma_engine_listener_set_direction(int64_t engine, int32_t listener,
                                        float x, float y, float z)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_listener_set_direction(&e->engine, (ma_uint32)listener, x, y, z);
}

void xma_engine_listener_set_velocity(int64_t engine, int32_t listener,
                                       float x, float y, float z)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_listener_set_velocity(&e->engine, (ma_uint32)listener, x, y, z);
}

void xma_engine_listener_set_world_up(int64_t engine, int32_t listener,
                                       float x, float y, float z)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_listener_set_world_up(&e->engine, (ma_uint32)listener, x, y, z);
}

void xma_engine_listener_set_enabled(int64_t engine, int32_t listener,
                                      int32_t enabled)
{
    if (!engine) return;
    xma_engine_t* e = (xma_engine_t*)(intptr_t)engine;
    ma_engine_listener_set_enabled(&e->engine, (ma_uint32)listener,
                                    (ma_bool32)enabled);
}

// ---- Noise ----

int64_t xma_noise_create(int32_t type, int32_t sample_rate, int32_t channels,
                          int32_t seed, float amplitude)
{
    xma_noise_t* n = (xma_noise_t*)calloc(1, sizeof(xma_noise_t));
    if (!n) return 0;

    ma_noise_config config = ma_noise_config_init(
        ma_format_f32,
        (ma_uint32)channels,
        (ma_noise_type)type,
        (ma_int32)seed,
        (double)amplitude
    );

    ma_result r = ma_noise_init(&config, NULL, &n->noise);
    if (r != MA_SUCCESS) {
        free(n);
        return 0;
    }

    return (int64_t)(intptr_t)n;
}

void xma_noise_destroy(int64_t noise)
{
    if (!noise) return;
    xma_noise_t* n = (xma_noise_t*)(intptr_t)noise;
    ma_noise_uninit(&n->noise, NULL);
    free(n);
}

int32_t xma_noise_set_type(int64_t noise, int32_t type)
{
    if (!noise) return -1;
    xma_noise_t* n = (xma_noise_t*)(intptr_t)noise;
    return (int32_t)ma_noise_set_type(&n->noise, (ma_noise_type)type);
}

int32_t xma_noise_set_seed(int64_t noise, int32_t seed)
{
    if (!noise) return -1;
    xma_noise_t* n = (xma_noise_t*)(intptr_t)noise;
    return (int32_t)ma_noise_set_seed(&n->noise, (ma_int32)seed);
}

int32_t xma_noise_set_amplitude(int64_t noise, float amplitude)
{
    if (!noise) return -1;
    xma_noise_t* n = (xma_noise_t*)(intptr_t)noise;
    return (int32_t)ma_noise_set_amplitude(&n->noise, (double)amplitude);
}

// ---- Utility ----

void xma_sleep_ms(int32_t milliseconds)
{
    if (milliseconds <= 0) return;
    ma_sleep((ma_uint32)milliseconds);
}

const char* xma_result_string(int32_t result)
{
    return ma_result_description((ma_result)result);
}
