/* xiom.miniaudio compile unit -- MIT OR Apache-2.0 (this file), XIOM Authors.
 *
 * Builds the vendored single-header miniaudio 0.11.25 (Unlicense OR MIT-0)
 * and adds the small `extern "C"` probe bridge the XIOM module calls.
 * Compiled via `--c-source` (port.args.json); no system audio library is
 * required at link time (miniaudio resolves the platform backends itself).
 *
 * Bridge surface (see miniaudio.xi):
 *   void xma_version(unsigned* major, unsigned* minor, unsigned* rev);
 *   int  xma_context_probe(int* playback, int* capture);   0=ok, else ma_result
 *   int  xma_decode_probe(int* frames, int* channels, int* rate, int* fmt);
 *                                                         0=ok, 1=probe mismatch
 *   int  xma_encode_roundtrip(void);                       0=ok, else negative
 *   int  xma_encode_frames(void); / xma_encode_equal(void) / xma_encode_removed(void);
 *                                                         0.3.0 cached results
 *
 * 0.4.0 (A04 growth -- every complex leg caches its result in file-scope
 * statics exposed through scalar getters; no foreign pointer ever crosses
 * the XIOM boundary, the B-20 rule):
 *   int  xma_device_lifecycle(void);   live playback device: explicit WASAPI
 *                                      context (auto fallback), open -> start
 *                                      -> mix-pull callback (streams a built-in
 *                                      WAV decoder) -> stop -> close, with
 *                                      started/stopped notification counts.
 *                                      0=ok, 1=no context, 2=no device,
 *                                      3=no start, 4=no frames pulled,
 *                                      5=streamed decoder setup failed.
 *   int  xma_engine_probe(void);       live ma_engine: init/start/stop, memory
 *                                      sound (decoder data source) play/stop,
 *                                      file sound fire-and-forget. 0=ok, else
 *                                      step code.
 *   int  xma_graph_probe(void);        device-free: standalone node graph
 *                                      attach/detach, engine mix math (sound
 *                                      group + per-sound volume), sound
 *                                      detach/reattach, pitch rate effect.
 *                                      0=ok, else step code.
 *   int  xma_capture_probe(void);      capture enumerate + open attempt.
 *                                      0=open+frames, 1=no context, 2=no
 *                                      capture device (rc getter), 3=opened
 *                                      but no frames, 4=no start.
 *   int  xma_stream_decode(int which); chunked (13-frame) pull decode through
 *                                      the decoder data source: 1=in-memory
 *                                      WAV, 2=FLAC fixture, 3=MP3 fixture.
 *                                      0=ok.
 *
 * 0.5.0 (long-lived handle surface -- open once -> register render callbacks /
 * run the stream over time -> close once, alongside the lifecycle bridge):
 *   int  xma_handle_open(int which, unsigned char* slot);
 *                                      which: -1 = default priority list,
 *                                      else an explicit ma_backend id.
 *                                      0=ok (slot gets 5 u32 LE fields:
 *                                      handle/backend/rate/channels/period),
 *                                      1=no context, 2=no device,
 *                                      3=registry exhausted (4 live handles).
 *   int  xma_handle_set_render(int handle, void (*render)(unsigned char*, int));
 *   int  xma_handle_clear_render(int handle);
 *   int  xma_handle_start(int handle); / xma_handle_stop(int handle);
 *   int  xma_handle_wait(int handle, int targetCallbacks, int timeoutMs);
 *   int  xma_handle_info(int handle, unsigned char* slot);
 *                                      0=ok (slot gets 12 u32 LE fields:
 *                                      handle/backend/rate/channels/period/
 *                                      callbacks/frames/started/render_set/
 *                                      starts/stops/marked), 1=bad handle.
 *   int  xma_handle_close(int handle);
 *                                      stop when running, then uninit; the
 *                                      slot is freed (stale handle -> 1).
 *   int  xma_handle_rc(void);          ma_result of the last failed call.
 *                                      Step calls return 1=bad handle,
 *                                      2=state error, 4=device stop/start
 *                                      failed (rc getter).
 */

#define MINIAUDIO_IMPLEMENTATION
#include "../vendor/miniaudio.h"

#include <stdio.h>

/* ---------------------------------------------------------------------- */

void xma_version(unsigned int* pMajor, unsigned int* pMinor, unsigned int* pRevision) {
  ma_uint32 major = 0, minor = 0, revision = 0;
  ma_version(&major, &minor, &revision);
  *pMajor = major;
  *pMinor = minor;
  *pRevision = revision;
}

int xma_context_probe(int* playback, int* capture) {
  ma_context context;
  ma_result result = ma_context_init(NULL, 0, NULL, &context);
  if (result != MA_SUCCESS) {
    return (int)result;
  }
  ma_device_info* pPlaybackInfos = NULL;
  ma_uint32 playbackCount = 0;
  ma_device_info* pCaptureInfos = NULL;
  ma_uint32 captureCount = 0;
  result = ma_context_get_devices(&context, &pPlaybackInfos, &playbackCount, &pCaptureInfos, &captureCount);
  if (result != MA_SUCCESS) {
    ma_context_uninit(&context);
    return (int)result;
  }
  if (playback) *playback = (int)playbackCount;
  if (capture) *capture = (int)captureCount;
  ma_context_uninit(&context);
  return 0;
}

/* 16-frame 8 kHz mono s16 sine (values precomputed so the compile unit does
 * not need libm). */
static const short kSine16[16] = {
  0, 7653, 14142, 18477, 20000, 18477, 14142, 7653,
  0, -7653, -14142, -18477, -20000, -18477, -14142, -7653
};

static void put_u16(unsigned char* p, unsigned int v) {
  p[0] = (unsigned char)(v & 0xFF);
  p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void put_u32(unsigned char* p, unsigned int v) {
  p[0] = (unsigned char)(v & 0xFF);
  p[1] = (unsigned char)((v >> 8) & 0xFF);
  p[2] = (unsigned char)((v >> 16) & 0xFF);
  p[3] = (unsigned char)((v >> 24) & 0xFF);
}

static unsigned int build_wav(unsigned char* buf) {
  const unsigned int sampleRate = 8000;
  const unsigned int frames = 16;
  const unsigned int dataSize = frames * 2; /* s16 mono */
  unsigned int o = 0;
  /* RIFF header */
  buf[o++] = 'R'; buf[o++] = 'I'; buf[o++] = 'F'; buf[o++] = 'F';
  put_u32(buf + o, 36 + dataSize); o += 4;
  buf[o++] = 'W'; buf[o++] = 'A'; buf[o++] = 'V'; buf[o++] = 'E';
  /* fmt chunk */
  buf[o++] = 'f'; buf[o++] = 'm'; buf[o++] = 't'; buf[o++] = ' ';
  put_u32(buf + o, 16); o += 4;
  put_u16(buf + o, 1); o += 2;                    /* PCM */
  put_u16(buf + o, 1); o += 2;                    /* channels */
  put_u32(buf + o, sampleRate); o += 4;
  put_u32(buf + o, sampleRate * 2); o += 4;       /* byte rate */
  put_u16(buf + o, 2); o += 2;                    /* block align */
  put_u16(buf + o, 16); o += 2;                   /* bits per sample */
  /* data chunk */
  buf[o++] = 'd'; buf[o++] = 'a'; buf[o++] = 't'; buf[o++] = 'a';
  put_u32(buf + o, dataSize); o += 4;
  for (unsigned int i = 0; i < frames; i++) {
    put_u16(buf + o, (unsigned int)(unsigned short)kSine16[i]); o += 2;
  }
  return o;
}

int xma_decode_probe(int* frames, int* channels, int* rate, int* fmt) {
  unsigned char wav[128];
  unsigned int wavSize = build_wav(wav);

  ma_decoder_config config = ma_decoder_config_init(ma_format_s16, 0, 0);
  ma_decoder decoder;
  ma_result result = ma_decoder_init_memory(wav, wavSize, &config, &decoder);
  if (result != MA_SUCCESS) {
    return 1;
  }

  short out[64];
  ma_uint64 framesRead = 0;
  result = ma_decoder_read_pcm_frames(&decoder, out, 16, &framesRead);
  if (result != MA_SUCCESS || framesRead != 16) {
    ma_decoder_uninit(&decoder);
    return 2;
  }
  /* EOS: a second read must return zero frames (MA_AT_END is acceptable). */
  ma_uint64 extra = 0;
  result = ma_decoder_read_pcm_frames(&decoder, out, 16, &extra);
  if ((result != MA_SUCCESS && result != MA_AT_END) || extra != 0) {
    ma_decoder_uninit(&decoder);
    return 3;
  }
  /* Sample spot-check: first sample 0, peak sample index 4 == 20000. */
  if (out[0] != 0 || out[4] != 20000 || out[8] != 0) {
    ma_decoder_uninit(&decoder);
    return 4;
  }

  if (frames) *frames = (int)framesRead;
  if (channels) *channels = (int)decoder.outputChannels;
  if (rate) *rate = (int)decoder.outputSampleRate;
  if (fmt) *fmt = (int)decoder.outputFormat;

  ma_decoder_uninit(&decoder);
  return 0;
}

/* ---------------------------------------------------------------------- */
/* 0.3.0: encoder + file round trip (device-free, deterministic).          */
/* Encodes a 64-frame 8 kHz mono s16 tone to a temp WAV with ma_encoder,   */
/* re-decodes it with ma_decoder_init_file, compares every sample, and     */
/* removes the temp file.  Results are cached for the getters.             */

static int g_encode_frames = 0;
static int g_encode_equal = 0;
static int g_encode_removed = 0;

#define XMA_ROUNDTRIP_PATH "xma_roundtrip_tmp.wav"

int xma_encode_roundtrip(void) {
  g_encode_frames = 0;
  g_encode_equal = 0;
  g_encode_removed = 0;

  /* 64 frames: four periods of the precomputed 16-sample tone. */
  short src[64];
  for (int i = 0; i < 64; i++) {
    src[i] = kSine16[i % 16];
  }

  ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_s16, 1, 8000);
  ma_encoder enc;
  if (ma_encoder_init_file(XMA_ROUNDTRIP_PATH, &cfg, &enc) != MA_SUCCESS) {
    return -1;
  }
  ma_uint64 written = 0;
  ma_result wr = ma_encoder_write_pcm_frames(&enc, src, 64, &written);
  ma_encoder_uninit(&enc);
  if (wr != MA_SUCCESS || written != 64) {
    remove(XMA_ROUNDTRIP_PATH);
    return -2;
  }

  ma_decoder dec;
  if (ma_decoder_init_file(XMA_ROUNDTRIP_PATH, NULL, &dec) != MA_SUCCESS) {
    remove(XMA_ROUNDTRIP_PATH);
    return -3;
  }
  short back[64];
  ma_uint64 read = 0;
  ma_result rd = ma_decoder_read_pcm_frames(&dec, back, 64, &read);
  int ch = (int)dec.outputChannels;
  int rate = (int)dec.outputSampleRate;
  int fmt = (int)dec.outputFormat;
  ma_decoder_uninit(&dec);

  g_encode_removed = (remove(XMA_ROUNDTRIP_PATH) == 0) ? 1 : 0;
  if (rd != MA_SUCCESS || read != 64) return -4;
  if (ch != 1 || rate != 8000 || fmt != (int)ma_format_s16) return -5;
  for (int i = 0; i < 64; i++) {
    if (back[i] != src[i]) return -6;
  }
  g_encode_frames = (int)read;
  g_encode_equal = 1;
  return 0;
}

int xma_encode_frames(void) { return g_encode_frames; }
int xma_encode_equal(void) { return g_encode_equal; }
int xma_encode_removed(void) { return g_encode_removed; }

/* ======================================================================== */
/* 0.4.0: A04 growth -- device lifecycle, playback engine, node graph,      */
/* capture, streamed decode.  Every leg caches its outcome in file-scope    */
/* statics and exposes scalars through getters (no foreign pointers cross   */
/* the XIOM boundary).                                                      */
/* ======================================================================== */

/* Wait until *pCounter >= target, bounded by timeoutMs (1 ms sleeps). */
static void xma_wait_counter(volatile int* pCounter, int target, int timeoutMs) {
  ma_timer timer;
  ma_timer_init(&timer);
  while (*pCounter < target) {
    if (ma_timer_get_time_in_seconds(&timer) * 1000.0 >= (double)timeoutMs) {
      break;
    }
    ma_sleep(1);
  }
}

/* ------------------------------------------------------------------------ */
/* 0.4.0: live playback device lifecycle.                                   */
/* Driver negotiation: an explicit WASAPI context is requested first; if it */
/* cannot initialize the default priority list is used (auto). The mix-pull */
/* data callback streams a built-in WAV decoder (f32/2ch/48k, silence by    */
/* construction) and counts callbacks/frames/decoded frames. Device-loss    */
/* handling is wired through the notification callback: started/stopped are */
/* counted live, rerouted is wired for the unplug case (cannot be forced    */
/* in-process; recorded as a documented boundary in SPEC).                  */

#define XMA_DEV_REQUEST_RATE 48000
#define XMA_DEV_REQUEST_CHANNELS 2
#define XMA_DEV_PERIOD_FRAMES 480
#define XMA_SILENCE_FRAMES 48000

static int g_dev_rc = 0;
static int g_dev_wasapi_explicit = 0;
static int g_dev_backend = 0;
static int g_dev_requested_rate = 0;
static int g_dev_internal_rate = 0;
static int g_dev_channels = 0;
static int g_dev_internal_channels = 0;
static int g_dev_period_frames = 0;
static volatile int g_dev_frames = 0;
static volatile int g_dev_callbacks = 0;
static volatile int g_dev_decoded_frames = 0;
static volatile int g_dev_notify_started = 0;
static volatile int g_dev_notify_stopped = 0;
static volatile int g_dev_notify_rerouted = 0;

static unsigned char g_silence_wav[44 + XMA_SILENCE_FRAMES * 2];
static unsigned int g_silence_wav_size = 0;
static ma_decoder g_stream_decoder; /* shared by the device callback and the streamed-decode leg */
static int g_dev_stream_armed = 0;

/* 1 s of 8 kHz mono s16 silence in a WAV container (built once). Used as the
 * decoder source in the live callback and as the engine sound buffer; silent
 * by construction -- the live legs make no audible surprise. */
static unsigned int xma_build_silence_wav(void) {
  unsigned int o = 0;
  unsigned int dataSize = XMA_SILENCE_FRAMES * 2;
  unsigned char* buf = g_silence_wav;
  if (g_silence_wav_size != 0) return g_silence_wav_size;
  buf[o++] = 'R'; buf[o++] = 'I'; buf[o++] = 'F'; buf[o++] = 'F';
  put_u32(buf + o, 36 + dataSize); o += 4;
  buf[o++] = 'W'; buf[o++] = 'A'; buf[o++] = 'V'; buf[o++] = 'E';
  buf[o++] = 'f'; buf[o++] = 'm'; buf[o++] = 't'; buf[o++] = ' ';
  put_u32(buf + o, 16); o += 4;
  put_u16(buf + o, 1); o += 2;   /* PCM */
  put_u16(buf + o, 1); o += 2;   /* mono */
  put_u32(buf + o, 8000); o += 4;
  put_u32(buf + o, 16000); o += 4;
  put_u16(buf + o, 2); o += 2;
  put_u16(buf + o, 16); o += 2;
  buf[o++] = 'd'; buf[o++] = 'a'; buf[o++] = 't'; buf[o++] = 'a';
  put_u32(buf + o, dataSize); o += 4;
  while (o < 44 + dataSize) buf[o++] = 0;
  g_silence_wav_size = o;
  return o;
}

static void xma_dev_data_cb(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
  (void)pDevice; (void)pInput;
  g_dev_callbacks++;
  g_dev_frames += (int)frameCount;
  if (g_dev_stream_armed) {
    ma_uint64 got = 0;
    /* The decoder is configured to the exact device shape (f32/2ch/48k), so
     * decoded frames can be written straight into the output buffer; the
     * buffer arrives pre-silenced, so a short final read stays silent. */
    if (ma_data_source_read_pcm_frames((ma_data_source*)&g_stream_decoder, pOutput, frameCount, &got) == MA_SUCCESS) {
      g_dev_decoded_frames += (int)got;
    }
  }
}

static void xma_dev_notification_cb(const ma_device_notification* pNotification) {
  if (pNotification->type == ma_device_notification_type_started) {
    g_dev_notify_started++;
  } else if (pNotification->type == ma_device_notification_type_stopped) {
    g_dev_notify_stopped++;
  } else if (pNotification->type == ma_device_notification_type_rerouted) {
    g_dev_notify_rerouted++;
  }
}

int xma_device_lifecycle(void) {
  ma_backend wasapiBackends[1];
  ma_context context;
  ma_device device;
  ma_device_config config;
  ma_decoder_config decoderConfig;
  ma_result result;

  g_dev_rc = 0;
  g_dev_wasapi_explicit = 0;
  g_dev_backend = 0;
  g_dev_requested_rate = 0;
  g_dev_internal_rate = 0;
  g_dev_channels = 0;
  g_dev_internal_channels = 0;
  g_dev_period_frames = 0;
  g_dev_frames = 0;
  g_dev_callbacks = 0;
  g_dev_decoded_frames = 0;
  g_dev_notify_started = 0;
  g_dev_notify_stopped = 0;
  g_dev_notify_rerouted = 0;

  xma_build_silence_wav();
  decoderConfig = ma_decoder_config_init(ma_format_f32, XMA_DEV_REQUEST_CHANNELS, XMA_DEV_REQUEST_RATE);
  result = ma_decoder_init_memory(g_silence_wav, g_silence_wav_size, &decoderConfig, &g_stream_decoder);
  if (result != MA_SUCCESS) {
    g_dev_rc = (int)result;
    return 5;
  }

  wasapiBackends[0] = ma_backend_wasapi;
  result = ma_context_init(wasapiBackends, 1, NULL, &context);
  if (result == MA_SUCCESS) {
    g_dev_wasapi_explicit = 1;
  } else {
    result = ma_context_init(NULL, 0, NULL, &context);
    if (result != MA_SUCCESS) {
      ma_decoder_uninit(&g_stream_decoder);
      g_dev_rc = (int)result;
      return 1;
    }
  }
  g_dev_backend = (int)context.backend;

  config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = XMA_DEV_REQUEST_CHANNELS;
  config.sampleRate = XMA_DEV_REQUEST_RATE;
  config.periodSizeInFrames = XMA_DEV_PERIOD_FRAMES;
  config.dataCallback = xma_dev_data_cb;
  config.notificationCallback = xma_dev_notification_cb;

  result = ma_device_init(&context, &config, &device);
  if (result != MA_SUCCESS) {
    ma_decoder_uninit(&g_stream_decoder);
    ma_context_uninit(&context);
    g_dev_rc = (int)result;
    return 2;
  }
  g_dev_requested_rate = (int)device.sampleRate;
  g_dev_internal_rate = (int)device.playback.internalSampleRate;
  g_dev_channels = (int)device.playback.channels;
  g_dev_internal_channels = (int)device.playback.internalChannels;
  g_dev_period_frames = (int)device.playback.internalPeriodSizeInFrames;

  g_dev_stream_armed = 1;
  result = ma_device_start(&device);
  if (result != MA_SUCCESS) {
    g_dev_stream_armed = 0;
    ma_device_uninit(&device);
    ma_decoder_uninit(&g_stream_decoder);
    ma_context_uninit(&context);
    g_dev_rc = (int)result;
    return 3;
  }

  /* Wait for >= 100 ms of pulled frames (bounded: an endpoint that opened but
   * never pulls degrades to code 4 with the counters kept for evidence). */
  xma_wait_counter(&g_dev_frames, XMA_DEV_REQUEST_RATE / 10, 2000);
  ma_device_stop(&device);   /* fires the stopped notification */
  ma_device_uninit(&device);
  g_dev_stream_armed = 0;
  ma_decoder_uninit(&g_stream_decoder);
  ma_context_uninit(&context);

  if (g_dev_frames <= 0) {
    return 4;   /* opened but the endpoint never pulled -- typed non-fatal */
  }
  return 0;
}

int xma_dev_rc(void) { return g_dev_rc; }
int xma_dev_wasapi_explicit(void) { return g_dev_wasapi_explicit; }
int xma_dev_backend(void) { return g_dev_backend; }
int xma_dev_requested_rate(void) { return g_dev_requested_rate; }
int xma_dev_internal_rate(void) { return g_dev_internal_rate; }
int xma_dev_channels(void) { return g_dev_channels; }
int xma_dev_internal_channels(void) { return g_dev_internal_channels; }
int xma_dev_period_frames(void) { return g_dev_period_frames; }
int xma_dev_frames(void) { return g_dev_frames; }
int xma_dev_callbacks(void) { return g_dev_callbacks; }
int xma_dev_decoded_frames(void) { return g_dev_decoded_frames; }
int xma_dev_notify_started(void) { return g_dev_notify_started; }
int xma_dev_notify_stopped(void) { return g_dev_notify_stopped; }
int xma_dev_notify_rerouted(void) { return g_dev_notify_rerouted; }

/* ------------------------------------------------------------------------ */
/* 0.4.0: live playback engine.                                             */
/* ma_engine init (noAutoStart) -> ma_engine_start -> a sound from memory   */
/* (built-in WAV decoder as the data source, looping) play/stop -> a file   */
/* sound through ma_engine_play_sound (fire-and-forget from a temp WAV) ->  */
/* ma_engine_stop -> uninit. Frame-clock movement is the mix evidence.      */

#define XMA_ENGINE_TMP_PATH "xma_engine_tmp.wav"

static int g_eng_rc = 0;
static int g_eng_backend = 0;
static int g_eng_started = 0;
static int g_eng_playing = 0;
static int g_eng_cursor = 0;
static int g_eng_memory_stopped = 0;
static int g_eng_file_ok = 0;
static int g_eng_frames = 0;
static int g_eng_stopped = 0;

static void xma_wait_engine(ma_engine* pEngine, int targetFrames, int timeoutMs) {
  ma_timer timer;
  ma_timer_init(&timer);
  while ((int)ma_engine_get_time_in_pcm_frames(pEngine) < targetFrames) {
    if (ma_timer_get_time_in_seconds(&timer) * 1000.0 >= (double)timeoutMs) {
      break;
    }
    ma_sleep(2);
  }
}

int xma_engine_probe(void) {
  ma_engine engine;
  ma_engine_config engineConfig;
  ma_decoder_config decoderConfig;
  ma_decoder decoder;
  ma_sound sound;
  ma_result result;
  static short zeroChunk[1024];

  g_eng_rc = 0;
  g_eng_backend = 0;
  g_eng_started = 0;
  g_eng_playing = 0;
  g_eng_cursor = 0;
  g_eng_memory_stopped = 0;
  g_eng_file_ok = 0;
  g_eng_frames = 0;
  g_eng_stopped = 0;

  engineConfig = ma_engine_config_init();
  engineConfig.noAutoStart = MA_TRUE;   /* prove ma_engine_start explicitly */
  result = ma_engine_init(&engineConfig, &engine);
  if (result != MA_SUCCESS) {
    g_eng_rc = (int)result;
    return 1;
  }
  if (engine.pDevice != NULL) {
    g_eng_backend = (int)engine.pDevice->pContext->backend;
  }

  result = ma_engine_start(&engine);
  if (result != MA_SUCCESS) {
    ma_engine_uninit(&engine);
    g_eng_rc = (int)result;
    return 2;
  }
  g_eng_started = 1;

  /* Sound from memory: the built-in WAV decoder is the data source. */
  xma_build_silence_wav();
  decoderConfig = ma_decoder_config_init(ma_format_f32, 2, 48000);
  result = ma_decoder_init_memory(g_silence_wav, g_silence_wav_size, &decoderConfig, &decoder);
  if (result != MA_SUCCESS) {
    ma_engine_uninit(&engine);
    g_eng_rc = (int)result;
    return 3;
  }

  result = ma_sound_init_from_data_source(&engine, (ma_data_source*)&decoder, 0, NULL, &sound);
  if (result != MA_SUCCESS) {
    ma_decoder_uninit(&decoder);
    ma_engine_uninit(&engine);
    g_eng_rc = (int)result;
    return 4;
  }

  ma_sound_set_looping(&sound, MA_TRUE);
  result = ma_sound_start(&sound);
  if (result != MA_SUCCESS) {
    ma_sound_uninit(&sound);
    ma_decoder_uninit(&decoder);
    ma_engine_uninit(&engine);
    g_eng_rc = (int)result;
    return 5;
  }
  g_eng_playing = ma_sound_is_playing(&sound) ? 1 : 0;

  xma_wait_engine(&engine, 4800, 2000);   /* >= 100 ms of pulled frames */
  {
    ma_uint64 cursor = 0;
    if (ma_sound_get_cursor_in_pcm_frames(&sound, &cursor) == MA_SUCCESS) {
      g_eng_cursor = (int)cursor;
    }
  }
  ma_sound_stop(&sound);
  g_eng_memory_stopped = ma_sound_is_playing(&sound) ? 0 : 1;
  ma_sound_uninit(&sound);
  ma_decoder_uninit(&decoder);

  /* File sound: fire-and-forget through the resource manager (temp file). */
  {
    ma_encoder_config encoderConfig = ma_encoder_config_init(ma_encoding_format_wav, ma_format_s16, 1, 8000);
    ma_encoder encoder;
    if (ma_encoder_init_file(XMA_ENGINE_TMP_PATH, &encoderConfig, &encoder) == MA_SUCCESS) {
      int wroteOk = 1;
      int chunkIndex;
      for (chunkIndex = 0; chunkIndex < 16; chunkIndex++) {   /* 16384 silent frames */
        ma_uint64 written = 0;
        if (ma_encoder_write_pcm_frames(&encoder, zeroChunk, 1024, &written) != MA_SUCCESS || written != 1024) {
          wroteOk = 0;
          break;
        }
      }
      ma_encoder_uninit(&encoder);
      if (wroteOk) {
        result = ma_engine_play_sound(&engine, XMA_ENGINE_TMP_PATH, NULL);
        g_eng_file_ok = (result == MA_SUCCESS) ? 1 : 0;
      }
    }
  }
  xma_wait_engine(&engine, 9600, 1500);
  remove(XMA_ENGINE_TMP_PATH);

  result = ma_engine_stop(&engine);
  g_eng_stopped = (result == MA_SUCCESS) ? 1 : 0;
  g_eng_frames = (int)ma_engine_get_time_in_pcm_frames(&engine);
  ma_engine_uninit(&engine);

  g_eng_rc = (int)MA_SUCCESS;
  if (g_eng_frames <= 0) {
    return 6;
  }
  return 0;
}

int xma_eng_rc(void) { return g_eng_rc; }
int xma_eng_backend(void) { return g_eng_backend; }
int xma_eng_started(void) { return g_eng_started; }
int xma_eng_playing(void) { return g_eng_playing; }
int xma_eng_cursor(void) { return g_eng_cursor; }
int xma_eng_memory_stopped(void) { return g_eng_memory_stopped; }
int xma_eng_file_ok(void) { return g_eng_file_ok; }
int xma_eng_frames(void) { return g_eng_frames; }
int xma_eng_stopped(void) { return g_eng_stopped; }

/* ------------------------------------------------------------------------ */
/* 0.4.0: device-free node graph + engine mix math.                         */
/* (a) standalone ma_node_graph: ma_data_source_node (ma_audio_buffer of    */
/*     0.25f stereo) attached to the endpoint -> read 0.25; detached ->     */
/*     read silence;                                                       */
/* (b) noDevice engine: sound A (0.5f) through a sound group at volume 0.5  */
/*     + sound B (0.5f) at volume 0.25 -> exact 0.375 mix; B detached ->    */
/*     0.25; B re-attached -> 0.375; per-sound/group volume+pitch get/set;  */
/*     pitch 2.0 doubles the cursor rate over the same engine frames.       */

#define XMA_GRAPH_BUFFER_FRAMES 48000

static float g_graph_half[XMA_GRAPH_BUFFER_FRAMES * 2];

static int g_graph_rc = 0;
static int g_graph_standalone_read = 0;
static int g_graph_standalone_x1000 = 0;
static int g_graph_standalone_silent = 0;
static int g_graph_mix_x1000 = 0;
static int g_graph_mix_exact = 0;
static int g_graph_detach_x1000 = 0;
static int g_graph_detach_exact = 0;
static int g_graph_reattach_x1000 = 0;
static int g_graph_reattach_exact = 0;
static int g_graph_group_volume_x1000 = 0;
static int g_graph_group_volume_exact = 0;
static int g_graph_sound_volume_x1000 = 0;
static int g_graph_sound_volume_exact = 0;
static int g_graph_sound_pitch_x1000 = 0;
static int g_graph_sound_pitch_exact = 0;
static int g_graph_pitch_ratio_x1000 = 0;

static int xma_all_equal_float(const float* pValues, int count, float value) {
  int i;
  for (i = 0; i < count; i++) {
    if (pValues[i] != value) return 0;
  }
  return 1;
}

int xma_graph_probe(void) {
  ma_result result;

  g_graph_rc = 0;
  g_graph_standalone_read = 0;
  g_graph_standalone_x1000 = 0;
  g_graph_standalone_silent = 0;
  g_graph_mix_x1000 = 0;
  g_graph_mix_exact = 0;
  g_graph_detach_x1000 = 0;
  g_graph_detach_exact = 0;
  g_graph_reattach_x1000 = 0;
  g_graph_reattach_exact = 0;
  g_graph_group_volume_x1000 = 0;
  g_graph_group_volume_exact = 0;
  g_graph_sound_volume_x1000 = 0;
  g_graph_sound_volume_exact = 0;
  g_graph_sound_pitch_x1000 = 0;
  g_graph_sound_pitch_exact = 0;
  g_graph_pitch_ratio_x1000 = 0;

  /* --- (a) standalone node graph: attach + detach --------------------- */
  {
    static float constBuf[64 * 2];
    ma_audio_buffer_config abConfig;
    ma_audio_buffer buffer;
    ma_node_graph_config ngConfig;
    ma_node_graph graph;
    ma_data_source_node_config dsConfig;
    ma_data_source_node dsNode;
    float out[32 * 2];
    ma_uint64 read = 0;
    int i;

    for (i = 0; i < 64 * 2; i++) constBuf[i] = 0.25f;

    abConfig = ma_audio_buffer_config_init(ma_format_f32, 2, 64, constBuf, NULL);
    result = ma_audio_buffer_init(&abConfig, &buffer);
    if (result != MA_SUCCESS) { g_graph_rc = 10; return 10; }

    ngConfig = ma_node_graph_config_init(2);
    result = ma_node_graph_init(&ngConfig, NULL, &graph);
    if (result != MA_SUCCESS) { ma_audio_buffer_uninit(&buffer); g_graph_rc = 11; return 11; }

    dsConfig = ma_data_source_node_config_init((ma_data_source*)&buffer);
    result = ma_data_source_node_init(&graph, &dsConfig, NULL, &dsNode);
    if (result != MA_SUCCESS) { ma_node_graph_uninit(&graph, NULL); ma_audio_buffer_uninit(&buffer); g_graph_rc = 12; return 12; }

    result = ma_node_attach_output_bus(&dsNode, 0, ma_node_graph_get_endpoint(&graph), 0);
    if (result != MA_SUCCESS) { ma_data_source_node_uninit(&dsNode, NULL); ma_node_graph_uninit(&graph, NULL); ma_audio_buffer_uninit(&buffer); g_graph_rc = 13; return 13; }

    for (i = 0; i < 32 * 2; i++) out[i] = 0.0f;
    result = ma_node_graph_read_pcm_frames(&graph, out, 32, &read);
    if (result != MA_SUCCESS) { ma_data_source_node_uninit(&dsNode, NULL); ma_node_graph_uninit(&graph, NULL); ma_audio_buffer_uninit(&buffer); g_graph_rc = 14; return 14; }
    g_graph_standalone_read = (int)read;
    g_graph_standalone_x1000 = (int)(out[0] * 1000.0f + 0.5f);

    result = ma_node_detach_output_bus(&dsNode, 0);
    if (result != MA_SUCCESS) { ma_data_source_node_uninit(&dsNode, NULL); ma_node_graph_uninit(&graph, NULL); ma_audio_buffer_uninit(&buffer); g_graph_rc = 15; return 15; }

    for (i = 0; i < 32 * 2; i++) out[i] = 1.0f;   /* prove the graph overwrites with silence */
    read = 0;
    result = ma_node_graph_read_pcm_frames(&graph, out, 32, &read);
    if (result != MA_SUCCESS) { ma_data_source_node_uninit(&dsNode, NULL); ma_node_graph_uninit(&graph, NULL); ma_audio_buffer_uninit(&buffer); g_graph_rc = 16; return 16; }
    {
      int silent = 1;
      for (i = 0; i < 32 * 2; i++) {
        if (out[i] != 0.0f) silent = 0;
      }
      g_graph_standalone_silent = silent;
    }

    ma_data_source_node_uninit(&dsNode, NULL);
    ma_node_graph_uninit(&graph, NULL);
    ma_audio_buffer_uninit(&buffer);
  }

  /* --- (b) noDevice engine: mix math, group, detach/reattach, pitch --- */
  {
    ma_engine_config ecfg = ma_engine_config_init();
    ma_engine engine;
    ma_audio_buffer bufferA, bufferB;
    ma_audio_buffer_config abA, abB;
    ma_sound_group group;
    ma_sound soundA, soundB;
    static float mixChunk[480 * 2];
    int i;
    ma_uint64 framesRead = 0;

    for (i = 0; i < XMA_GRAPH_BUFFER_FRAMES * 2; i++) g_graph_half[i] = 0.5f;

    ecfg.noDevice = MA_TRUE;   /* deterministic: we pull the graph manually */
    ecfg.channels = 2;
    ecfg.sampleRate = 48000;
    ecfg.periodSizeInFrames = 480;
    result = ma_engine_init(&ecfg, &engine);
    if (result != MA_SUCCESS) { g_graph_rc = 20; return 20; }

    abA = ma_audio_buffer_config_init(ma_format_f32, 2, XMA_GRAPH_BUFFER_FRAMES, g_graph_half, NULL);
    result = ma_audio_buffer_init(&abA, &bufferA);
    if (result != MA_SUCCESS) { ma_engine_uninit(&engine); g_graph_rc = 21; return 21; }
    abB = ma_audio_buffer_config_init(ma_format_f32, 2, XMA_GRAPH_BUFFER_FRAMES, g_graph_half, NULL);
    result = ma_audio_buffer_init(&abB, &bufferB);
    if (result != MA_SUCCESS) { ma_audio_buffer_uninit(&bufferA); ma_engine_uninit(&engine); g_graph_rc = 22; return 22; }

    result = ma_sound_group_init(&engine, MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, &group);
    if (result != MA_SUCCESS) { ma_audio_buffer_uninit(&bufferA); ma_audio_buffer_uninit(&bufferB); ma_engine_uninit(&engine); g_graph_rc = 23; return 23; }
    ma_sound_group_set_volume(&group, 0.5f);
    g_graph_group_volume_x1000 = (int)(ma_sound_group_get_volume(&group) * 1000.0f + 0.5f);
    g_graph_group_volume_exact = (ma_sound_group_get_volume(&group) == 0.5f) ? 1 : 0;

    result = ma_sound_init_from_data_source(&engine, (ma_data_source*)&bufferA, MA_SOUND_FLAG_NO_SPATIALIZATION, &group, &soundA);
    if (result != MA_SUCCESS) { ma_sound_group_uninit(&group); ma_audio_buffer_uninit(&bufferA); ma_audio_buffer_uninit(&bufferB); ma_engine_uninit(&engine); g_graph_rc = 24; return 24; }
    result = ma_sound_init_from_data_source(&engine, (ma_data_source*)&bufferB, MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, &soundB);
    if (result != MA_SUCCESS) { ma_sound_uninit(&soundA); ma_sound_group_uninit(&group); ma_audio_buffer_uninit(&bufferA); ma_audio_buffer_uninit(&bufferB); ma_engine_uninit(&engine); g_graph_rc = 25; return 25; }

    ma_sound_set_looping(&soundA, MA_TRUE);
    ma_sound_set_looping(&soundB, MA_TRUE);
    ma_sound_set_volume(&soundA, 1.0f);
    ma_sound_set_volume(&soundB, 0.25f);
    g_graph_sound_volume_x1000 = (int)(ma_sound_get_volume(&soundB) * 1000.0f + 0.5f);
    g_graph_sound_volume_exact = (ma_sound_get_volume(&soundB) == 0.25f) ? 1 : 0;
    ma_sound_set_pitch(&soundB, 1.5f);
    g_graph_sound_pitch_x1000 = (int)(ma_sound_get_pitch(&soundB) * 1000.0f + 0.5f);
    g_graph_sound_pitch_exact = (ma_sound_get_pitch(&soundB) == 1.5f) ? 1 : 0;
    ma_sound_set_pitch(&soundB, 1.0f);

    ma_sound_start(&soundA);
    ma_sound_start(&soundB);

    /* Warmup (absorbs any gain smoothing), then verify the exact mix:
     * A 0.5 * group 0.5 = 0.25, B 0.5 * 0.25 = 0.125, sum 0.375 (exact f32). */
    for (i = 0; i < 10; i++) {
      ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
    }
    ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
    g_graph_mix_x1000 = (int)(mixChunk[0] * 1000.0f + 0.5f);
    g_graph_mix_exact = xma_all_equal_float(mixChunk, 480 * 2, 0.375f);

    /* Detach sound B's output bus (sound layout is node-compatible); the mix
     * drops to A only: 0.25. */
    result = ma_node_detach_output_bus((ma_node*)&soundB, 0);
    if (result != MA_SUCCESS) { ma_sound_uninit(&soundA); ma_sound_uninit(&soundB); ma_sound_group_uninit(&group); ma_audio_buffer_uninit(&bufferA); ma_audio_buffer_uninit(&bufferB); ma_engine_uninit(&engine); g_graph_rc = 26; return 26; }
    ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
    g_graph_detach_x1000 = (int)(mixChunk[0] * 1000.0f + 0.5f);
    g_graph_detach_exact = xma_all_equal_float(mixChunk, 480 * 2, 0.25f);

    /* Re-attach directly to the engine endpoint: back to 0.375. */
    result = ma_node_attach_output_bus((ma_node*)&soundB, 0, ma_engine_get_endpoint(&engine), 0);
    if (result != MA_SUCCESS) { ma_sound_uninit(&soundA); ma_sound_uninit(&soundB); ma_sound_group_uninit(&group); ma_audio_buffer_uninit(&bufferA); ma_audio_buffer_uninit(&bufferB); ma_engine_uninit(&engine); g_graph_rc = 27; return 27; }
    ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
    g_graph_reattach_x1000 = (int)(mixChunk[0] * 1000.0f + 0.5f);
    g_graph_reattach_exact = xma_all_equal_float(mixChunk, 480 * 2, 0.375f);

    /* Pitch rate effect on sound A: cursor delta over 4800 engine frames at
     * pitch 1.0 vs 2.0 (data source rate == engine rate -> ~2x cursor rate). */
    {
      ma_uint64 c0 = 0, c1 = 0, c2 = 0, c3 = 0;
      ma_sound_get_cursor_in_pcm_frames(&soundA, &c0);
      for (i = 0; i < 10; i++) {
        ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
      }
      ma_sound_get_cursor_in_pcm_frames(&soundA, &c1);
      ma_sound_set_pitch(&soundA, 2.0f);
      ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);   /* let the change land */
      ma_sound_get_cursor_in_pcm_frames(&soundA, &c2);
      for (i = 0; i < 10; i++) {
        ma_engine_read_pcm_frames(&engine, mixChunk, 480, &framesRead);
      }
      ma_sound_get_cursor_in_pcm_frames(&soundA, &c3);
      {
        int delta1 = (int)(c1 - c0);
        int delta2 = (int)(c3 - c2);
        if (delta1 > 0) {
          g_graph_pitch_ratio_x1000 = (int)(((long long)delta2 * 1000 + delta1 / 2) / delta1);
        }
      }
    }

    ma_sound_stop(&soundA);
    ma_sound_stop(&soundB);
    ma_sound_uninit(&soundA);
    ma_sound_uninit(&soundB);
    ma_sound_group_uninit(&group);
    ma_audio_buffer_uninit(&bufferA);
    ma_audio_buffer_uninit(&bufferB);
    ma_engine_uninit(&engine);
  }

  return 0;
}

int xma_graph_rc(void) { return g_graph_rc; }
int xma_graph_standalone_read(void) { return g_graph_standalone_read; }
int xma_graph_standalone_x1000(void) { return g_graph_standalone_x1000; }
int xma_graph_standalone_silent(void) { return g_graph_standalone_silent; }
int xma_graph_mix_x1000(void) { return g_graph_mix_x1000; }
int xma_graph_mix_exact(void) { return g_graph_mix_exact; }
int xma_graph_detach_x1000(void) { return g_graph_detach_x1000; }
int xma_graph_detach_exact(void) { return g_graph_detach_exact; }
int xma_graph_reattach_x1000(void) { return g_graph_reattach_x1000; }
int xma_graph_reattach_exact(void) { return g_graph_reattach_exact; }
int xma_graph_group_volume_x1000(void) { return g_graph_group_volume_x1000; }
int xma_graph_group_volume_exact(void) { return g_graph_group_volume_exact; }
int xma_graph_sound_volume_x1000(void) { return g_graph_sound_volume_x1000; }
int xma_graph_sound_volume_exact(void) { return g_graph_sound_volume_exact; }
int xma_graph_sound_pitch_x1000(void) { return g_graph_sound_pitch_x1000; }
int xma_graph_sound_pitch_exact(void) { return g_graph_sound_pitch_exact; }
int xma_graph_pitch_ratio_x1000(void) { return g_graph_pitch_ratio_x1000; }

/* ------------------------------------------------------------------------ */
/* 0.4.0: capture device -- enumerate + open attempt.                       */
/* A box without a capture endpoint is a typed, non-fatal outcome:          */
/* code 2 (no capture device, ma result in the rc getter) or code 3         */
/* (opened but no frames). The call path is always exercised.               */

static int g_cap_devices = 0;
static int g_cap_backend = 0;
static int g_cap_opened = 0;
static int g_cap_rc = 0;
static volatile int g_cap_frames = 0;
static volatile int g_cap_callbacks = 0;

static void xma_cap_data_cb(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
  (void)pDevice; (void)pOutput; (void)pInput;
  g_cap_callbacks++;
  g_cap_frames += (int)frameCount;
}

int xma_capture_probe(void) {
  ma_context context;
  ma_device_config config;
  ma_device device;
  ma_result result;
  ma_uint32 playbackCount = 0;
  ma_uint32 captureCount = 0;

  g_cap_devices = 0;
  g_cap_backend = 0;
  g_cap_opened = 0;
  g_cap_rc = 0;
  g_cap_frames = 0;
  g_cap_callbacks = 0;

  result = ma_context_init(NULL, 0, NULL, &context);
  if (result != MA_SUCCESS) {
    g_cap_rc = (int)result;
    return 1;
  }
  g_cap_backend = (int)context.backend;
  if (ma_context_get_devices(&context, NULL, &playbackCount, NULL, &captureCount) == MA_SUCCESS) {
    g_cap_devices = (int)captureCount;
  }

  config = ma_device_config_init(ma_device_type_capture);
  config.capture.format = ma_format_f32;
  config.capture.channels = 1;
  config.sampleRate = 48000;
  config.dataCallback = xma_cap_data_cb;

  result = ma_device_init(&context, &config, &device);
  if (result != MA_SUCCESS) {
    g_cap_rc = (int)result;
    ma_context_uninit(&context);
    return 2;   /* typed: no capture device on this host */
  }
  g_cap_opened = 1;

  result = ma_device_start(&device);
  if (result != MA_SUCCESS) {
    g_cap_rc = (int)result;
    ma_device_uninit(&device);
    ma_context_uninit(&context);
    return 4;
  }

  xma_wait_counter(&g_cap_frames, 2400, 1500);   /* >= 50 ms at 48 kHz */

  ma_device_stop(&device);
  ma_device_uninit(&device);
  ma_context_uninit(&context);

  if (g_cap_frames <= 0) {
    return 3;   /* typed: opened but the endpoint never delivered frames */
  }
  return 0;
}

int xma_cap_devices(void) { return g_cap_devices; }
int xma_cap_backend(void) { return g_cap_backend; }
int xma_cap_opened(void) { return g_cap_opened; }
int xma_cap_rc(void) { return g_cap_rc; }
int xma_cap_frames(void) { return g_cap_frames; }
int xma_cap_callbacks(void) { return g_cap_callbacks; }

/* ------------------------------------------------------------------------ */
/* 0.4.0: streamed decode through the decoder data-source pull path.        */
/* The whole stream is read in 13-frame chunks (chunk counter proves the    */
/* streaming shape); WAV (in-memory) and FLAC (fixture) are compared         */
/* sample-exact against the embedded kSine16 tone, MP3 (fixture) is checked  */
/* by rate/channels/frame count/peak energy (lossy codec).                  */

#define XMA_STREAM_CHUNK 13

static int g_stream_rc = 0;
static int g_stream_which = 0;
static int g_stream_frames = 0;
static int g_stream_chunks = 0;
static int g_stream_rate = 0;
static int g_stream_channels = 0;
static int g_stream_format = 0;
static int g_stream_peak = 0;
static int g_stream_exact = 0;
static int g_stream_first = -1;

int xma_stream_decode(int which) {
  ma_decoder_config config;
  ma_result result;
  short chunk[XMA_STREAM_CHUNK];
  ma_uint64 total = 0;
  int peak = 0;
  int exact = 1;
  int first = -1;
  int expectedFrames = 0;
  unsigned char wav[128];
  unsigned int wavSize;
  int guard;

  g_stream_rc = 0;
  g_stream_which = which;
  g_stream_frames = 0;
  g_stream_chunks = 0;
  g_stream_rate = 0;
  g_stream_channels = 0;
  g_stream_format = 0;
  g_stream_peak = 0;
  g_stream_exact = 0;
  g_stream_first = -1;

  config = ma_decoder_config_init(ma_format_s16, 1, 8000);
  wavSize = build_wav(wav);
  if (which == 1) {
    result = ma_decoder_init_memory(wav, wavSize, &config, &g_stream_decoder);
    expectedFrames = 16;   /* one period of kSine16 */
  } else if (which == 2) {
    result = ma_decoder_init_file("tests/fixtures/tone.flac", &config, &g_stream_decoder);
    expectedFrames = 64;   /* four periods of kSine16 (lossless) */
  } else if (which == 3) {
    result = ma_decoder_init_file("tests/fixtures/tone.mp3", &config, &g_stream_decoder);
  } else {
    return 9;
  }
  if (result != MA_SUCCESS) {
    g_stream_rc = (int)result;
    return 1;
  }
  g_stream_rate = (int)g_stream_decoder.outputSampleRate;
  g_stream_channels = (int)g_stream_decoder.outputChannels;
  g_stream_format = (int)g_stream_decoder.outputFormat;

  for (guard = 0; guard < 200000; guard++) {
    ma_uint64 got = 0;
    ma_uint64 i;
    result = ma_data_source_read_pcm_frames((ma_data_source*)&g_stream_decoder, chunk, XMA_STREAM_CHUNK, &got);
    if (result != MA_SUCCESS && result != MA_AT_END) {
      g_stream_rc = (int)result;
      ma_decoder_uninit(&g_stream_decoder);
      return 2;
    }
    if (got == 0) break;
    g_stream_chunks++;
    if (first < 0) first = chunk[0];
    for (i = 0; i < got; i++) {
      int v = (int)chunk[i];
      int a = v < 0 ? -v : v;
      if (a > peak) peak = a;
      if (expectedFrames > 0) {
        if ((int)(total + i) >= expectedFrames || v != (int)kSine16[(int)(total + i) % 16]) {
          exact = 0;
        }
      }
    }
    total += got;
  }
  ma_decoder_uninit(&g_stream_decoder);

  g_stream_frames = (int)total;
  g_stream_peak = peak;
  g_stream_exact = exact;
  g_stream_first = first;
  return 0;
}

int xma_stream_rc(void) { return g_stream_rc; }
int xma_stream_which(void) { return g_stream_which; }
int xma_stream_frames(void) { return g_stream_frames; }
int xma_stream_chunks(void) { return g_stream_chunks; }
int xma_stream_rate(void) { return g_stream_rate; }
int xma_stream_channels(void) { return g_stream_channels; }
int xma_stream_format(void) { return g_stream_format; }
int xma_stream_peak(void) { return g_stream_peak; }
int xma_stream_exact(void) { return g_stream_exact; }
int xma_stream_first(void) { return g_stream_first; }

/* ======================================================================== */
/* 0.5.0: long-lived device handles.                                        */
/* Open once -> register a render callback / run the stream over time ->    */
/* close once.  A fixed 4-slot registry; the handle token is a monotonic    */
/* id, so a closed handle can never alias a newer one (typed BAD_HANDLE     */
/* instead of a stale device).  The render callback is a XIOM top-level fn  */
/* handed over once (the direct-handoff shape proven on the v0.64.5 pin)    */
/* and invoked from the device thread -- the audio-thread contract.  It     */
/* writes interleaved f32 stereo frames at the requested 48 kHz (miniaudio  */
/* converts to the internal shape); the buffer arrives pre-silenced.  The   */
/* callback may be set/replaced/cleared while the stream runs: the          */
/* trampoline reads the pointer once per buffer, so at most one in-flight   */
/* invocation observes the previous value.  callbacks/frames/marked are     */
/* counters written on the device thread, read by the owner thread.         */
/* ======================================================================== */

#define XMA_HANDLE_SLOTS 4
#define XMA_HANDLE_RATE 48000
#define XMA_HANDLE_CHANNELS 2
#define XMA_HANDLE_PERIOD 480
#define XMA_HANDLE_MARK0 0x5A
#define XMA_HANDLE_MARK1 0xA5

typedef struct {
  int used;
  int id;
  ma_context context;
  ma_device device;
  /* read-back / negotiated shape */
  int backend;
  int rate;
  int channels;
  int period;
  volatile int started;
  /* the registered XIOM render callback (device-thread read, owner-thread write) */
  void (*volatile render)(unsigned char*, int);
  /* device-thread counters */
  volatile int callbacks;
  volatile int frames;
  volatile int marked;
  volatile int starts;
  volatile int stops;
} xma_handle_slot;

static xma_handle_slot g_handle_slots[XMA_HANDLE_SLOTS];
static int g_handle_next_id = 1;
static int g_handle_rc = 0;

static xma_handle_slot* xma_handle_find(int handle) {
  int i;
  if (handle <= 0) return NULL;
  for (i = 0; i < XMA_HANDLE_SLOTS; i++) {
    if (g_handle_slots[i].used && g_handle_slots[i].id == handle) {
      return &g_handle_slots[i];
    }
  }
  return NULL;
}

static void xma_handle_data_cb(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
  xma_handle_slot* pSlot = (xma_handle_slot*)pDevice->pUserData;
  void (*render)(unsigned char*, int);
  unsigned char* pOut;
  (void)pInput;
  if (pSlot == NULL) return;
  pSlot->callbacks++;
  pSlot->frames += (int)frameCount;
  render = pSlot->render;   /* one read per buffer (registration handoff) */
  if (render == NULL) {
    return;                 /* no render registered: the buffer stays pre-silenced */
  }
  pOut = (unsigned char*)pOutput;
  render(pOut, (int)frameCount);   /* XIOM code runs on the device thread */
  /* marker evidence: the XIOM render wrote two known bytes into the buffer */
  if (pOut[0] == XMA_HANDLE_MARK0 && pOut[16] == XMA_HANDLE_MARK1) {
    pSlot->marked++;
  }
}

/* which: -1 = default priority list, else an explicit ma_backend id.
 * slot: 20 bytes -> handle(0) backend(4) rate(8) channels(12) period(16). */
int xma_handle_open(int which, unsigned char* slot) {
  xma_handle_slot* pSlot = NULL;
  ma_backend backends[1];
  ma_device_config config;
  ma_result result;
  int i;

  g_handle_rc = 0;
  for (i = 0; i < XMA_HANDLE_SLOTS; i++) {
    if (!g_handle_slots[i].used) {
      pSlot = &g_handle_slots[i];
      break;
    }
  }
  if (pSlot == NULL) {
    return 3;   /* registry exhausted */
  }

  if (which < 0) {
    result = ma_context_init(NULL, 0, NULL, &pSlot->context);   /* default priority list */
  } else {
    backends[0] = (ma_backend)which;
    result = ma_context_init(backends, 1, NULL, &pSlot->context);
  }
  if (result != MA_SUCCESS) {
    g_handle_rc = (int)result;
    return 1;   /* no context */
  }

  config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = XMA_HANDLE_CHANNELS;
  config.sampleRate = XMA_HANDLE_RATE;
  config.periodSizeInFrames = XMA_HANDLE_PERIOD;
  config.dataCallback = xma_handle_data_cb;
  config.pUserData = pSlot;

  result = ma_device_init(&pSlot->context, &config, &pSlot->device);
  if (result != MA_SUCCESS) {
    ma_context_uninit(&pSlot->context);
    g_handle_rc = (int)result;
    return 2;   /* no device */
  }

  pSlot->backend = (int)pSlot->context.backend;
  pSlot->rate = (int)pSlot->device.sampleRate;
  pSlot->channels = (int)pSlot->device.playback.channels;
  pSlot->period = (int)pSlot->device.playback.internalPeriodSizeInFrames;
  pSlot->started = 0;
  pSlot->render = NULL;
  pSlot->callbacks = 0;
  pSlot->frames = 0;
  pSlot->marked = 0;
  pSlot->starts = 0;
  pSlot->stops = 0;
  pSlot->id = g_handle_next_id++;
  pSlot->used = 1;

  if (slot) {
    put_u32(slot + 0, (unsigned int)pSlot->id);
    put_u32(slot + 4, (unsigned int)pSlot->backend);
    put_u32(slot + 8, (unsigned int)pSlot->rate);
    put_u32(slot + 12, (unsigned int)pSlot->channels);
    put_u32(slot + 16, (unsigned int)pSlot->period);
  }
  return 0;
}

int xma_handle_set_render(int handle, void (*render)(unsigned char*, int)) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  pSlot->render = render;
  return 0;
}

int xma_handle_clear_render(int handle) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  pSlot->render = NULL;
  return 0;
}

int xma_handle_start(int handle) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  ma_result result;
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  if (pSlot->started) return 2;   /* state: already started */
  result = ma_device_start(&pSlot->device);
  if (result != MA_SUCCESS) {
    g_handle_rc = (int)result;
    return 4;
  }
  pSlot->started = 1;
  pSlot->starts++;
  return 0;
}

int xma_handle_stop(int handle) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  ma_result result;
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  if (!pSlot->started) return 2;   /* state: not started */
  result = ma_device_stop(&pSlot->device);
  if (result != MA_SUCCESS) {
    g_handle_rc = (int)result;
    return 4;
  }
  pSlot->started = 0;
  pSlot->stops++;
  return 0;
}

/* Bounded wait until at least targetCallbacks render callbacks accumulated
 * (1 ms sleeps); returns 0 either way -- the caller reads the counters. */
int xma_handle_wait(int handle, int targetCallbacks, int timeoutMs) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  ma_timer timer;
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  if (targetCallbacks <= pSlot->callbacks) return 0;
  ma_timer_init(&timer);
  while (pSlot->callbacks < targetCallbacks) {
    if (ma_timer_get_time_in_seconds(&timer) * 1000.0 >= (double)timeoutMs) {
      break;
    }
    ma_sleep(1);
  }
  return 0;
}

/* slot: 48 bytes -> handle(0) backend(4) rate(8) channels(12) period(16)
 * callbacks(20) frames(24) started(28) render_set(32) starts(36) stops(40)
 * marked(44). */
int xma_handle_info(int handle, unsigned char* slot) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  if (slot) {
    put_u32(slot + 0, (unsigned int)pSlot->id);
    put_u32(slot + 4, (unsigned int)pSlot->backend);
    put_u32(slot + 8, (unsigned int)pSlot->rate);
    put_u32(slot + 12, (unsigned int)pSlot->channels);
    put_u32(slot + 16, (unsigned int)pSlot->period);
    put_u32(slot + 20, (unsigned int)pSlot->callbacks);
    put_u32(slot + 24, (unsigned int)pSlot->frames);
    put_u32(slot + 28, (unsigned int)(pSlot->started ? 1 : 0));
    put_u32(slot + 32, (unsigned int)(pSlot->render != NULL ? 1 : 0));
    put_u32(slot + 36, (unsigned int)pSlot->starts);
    put_u32(slot + 40, (unsigned int)pSlot->stops);
    put_u32(slot + 44, (unsigned int)pSlot->marked);
  }
  return 0;
}

int xma_handle_close(int handle) {
  xma_handle_slot* pSlot = xma_handle_find(handle);
  g_handle_rc = 0;
  if (pSlot == NULL) return 1;
  if (pSlot->started) {
    ma_device_stop(&pSlot->device);   /* close while running: stop first */
    pSlot->started = 0;
    pSlot->stops++;
  }
  pSlot->render = NULL;
  ma_device_uninit(&pSlot->device);
  ma_context_uninit(&pSlot->context);
  pSlot->used = 0;   /* the id is never reused: stale handles stay typed */
  return 0;
}

int xma_handle_rc(void) { return g_handle_rc; }
