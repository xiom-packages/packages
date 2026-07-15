// XIOM — MiniAudio C Bridge Implementation
// Provides flat ABI wrappers around miniaudio's transparent-struct API.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

#include "xiom_ma_bridge.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    ma_engine  engine;
    ma_device* pDevice;
    int        ownsDevice;
} xma_engine_t;

typedef struct {
    ma_waveform waveform;
    int         sampleRate;
    int         channels;
} xma_waveform_t;

typedef struct {
    ma_sound sound;
    int      ownsDataSource;
} xma_sound_t;

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

    e->pDevice     = e->engine.pDevice;
    e->ownsDevice  = 0;  // engine owns the device

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
    float vol = 0.0f;
    ma_engine_get_volume(&e->engine, &vol);
    return vol;
}

// ---- Waveform ----

int64_t xma_waveform_create(int32_t type, int32_t sample_rate,
                            int32_t channels, float amplitude, float frequency)
{
    xma_waveform_t* w = (xma_waveform_t*)calloc(1, sizeof(xma_waveform_t));
    if (!w) return 0;

    w->sampleRate = (int)sample_rate;
    w->channels   = (int)channels;

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

int64_t xma_play_waveform(int64_t engine, int64_t waveform)
{
    if (!engine || !waveform) return 0;
    xma_engine_t*   e = (xma_engine_t*)(intptr_t)engine;
    xma_waveform_t* w = (xma_waveform_t*)(intptr_t)waveform;

    xma_sound_t* snd = (xma_sound_t*)calloc(1, sizeof(xma_sound_t));
    if (!snd) return 0;

    snd->ownsDataSource = 0;  // waveform is externally managed

    ma_result r = ma_sound_init_from_data_source(
        &e->engine,
        &w->waveform,
        0,
        NULL,
        &snd->sound
    );

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
    if (!sound) return 0;
    xma_sound_t* snd = (xma_sound_t*)(intptr_t)sound;
    ma_sound_set_volume(&snd->sound, volume);
    return 0;
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
