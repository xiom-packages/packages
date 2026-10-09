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
 */

#define MINIAUDIO_IMPLEMENTATION
#include "../vendor/miniaudio.h"

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
