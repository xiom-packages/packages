/* xiom.opus -- Android NDK spike harness.
 * Loads libopus.so via dlopen (mirrors the xiom.ffi.dl runtime-load
 * semantics) and runs an encoder->decoder roundtrip through the xo_*
 * bridge ABI.  Built with the NDK clang for x86_64/aarch64; run on the
 * API-36 emulator via adb.  Evidence for the Android vendor-C path.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int64_t (*size_fn)(int32_t);
typedef int64_t (*create_fn)(int32_t, int32_t, int32_t, unsigned char*);
typedef int64_t (*dec_create_fn)(int32_t, int32_t, unsigned char*);
typedef int64_t (*encode_fn)(int64_t, const unsigned char*, int32_t,
                             unsigned char*, int32_t);
typedef int64_t (*decode_fn)(int64_t, const unsigned char*, int32_t,
                             unsigned char*, int32_t, int32_t);
typedef int64_t (*destroy_fn)(int64_t);

static void* must_sym(void* h, const char* name) {
    void* p = dlsym(h, name);
    if (!p) {
        printf("FAIL dlsym %s: %s\n", name, dlerror());
    }
    return p;
}

int main(int argc, char** argv) {
    const char* path = (argc > 1) ? argv[1] : "./libopus.so";
    int fails = 0;

    void* h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        printf("FAIL dlopen %s: %s\n", path, dlerror());
        return 1;
    }
    printf("OK dlopen %s\n", path);

    size_fn enc_size = (size_fn)must_sym(h, "xo_encoder_get_size");
    create_fn enc_create = (create_fn)must_sym(h, "xo_encoder_create");
    encode_fn enc = (encode_fn)must_sym(h, "xo_encode");
    size_fn dec_size = (size_fn)must_sym(h, "xo_decoder_get_size");
    dec_create_fn dec_create = (dec_create_fn)must_sym(h, "xo_decoder_create");
    decode_fn dec = (decode_fn)must_sym(h, "xo_decode");
    destroy_fn enc_destroy = (destroy_fn)must_sym(h, "xo_encoder_destroy");
    destroy_fn dec_destroy = (destroy_fn)must_sym(h, "xo_decoder_destroy");
    if (!enc_size || !enc_create || !enc || !dec_size || !dec_create || !dec ||
        !enc_destroy || !dec_destroy) {
        return 2;
    }

    int64_t sz = enc_size(1);
    printf("INFO encoder_size=%lld\n", (long long)sz);
    if (sz <= 0) {
        fails++;
    }

    unsigned char err[4] = {0x7f, 0x7f, 0x7f, 0x7f};
    /* Fs=48000, 1ch, OPUS_APPLICATION_AUDIO=2049 */
    int64_t encoder = enc_create(48000, 1, 2049, err);
    if (encoder <= 0) {
        printf("FAIL encoder_create rc=%lld err=%d,%d,%d,%d\n",
               (long long)encoder, err[0], err[1], err[2], err[3]);
        return 3;
    }
    printf("OK encoder_create\n");

    int64_t decoder = dec_create(48000, 1, err);
    if (decoder <= 0) {
        printf("FAIL decoder_create rc=%lld\n", (long long)decoder);
        return 4;
    }
    printf("OK decoder_create\n");

    enum { FRAME = 960, MAXPKT = 4000 };
    unsigned char pcm[FRAME * 2];
    /* deterministic 440 Hz-ish square pattern, i16 little-endian */
    for (int i = 0; i < FRAME; i++) {
        int16_t v = (int16_t)((i % 32) < 16 ? 12000 : -12000);
        pcm[2 * i] = (unsigned char)(v & 0xff);
        pcm[2 * i + 1] = (unsigned char)((v >> 8) & 0xff);
    }

    unsigned char packet[MAXPKT];
    int64_t nbytes = enc(encoder, pcm, FRAME, packet, MAXPKT);
    if (nbytes <= 0) {
        printf("FAIL encode rc=%lld\n", (long long)nbytes);
        fails++;
    } else {
        printf("OK encode bytes=%lld\n", (long long)nbytes);
    }

    unsigned char outpcm[FRAME * 2];
    memset(outpcm, 0xAB, sizeof(outpcm));
    int64_t samples = dec(decoder, packet, (int32_t)nbytes, outpcm, FRAME, 0);
    if (samples != FRAME) {
        printf("FAIL decode rc=%lld want=%d\n", (long long)samples, FRAME);
        fails++;
    } else {
        int16_t first = (int16_t)((uint16_t)outpcm[0] |
                                  ((uint16_t)outpcm[1] << 8));
        printf("OK decode samples=%lld first=%d\n", (long long)samples, first);
    }

    enc_destroy(encoder);
    dec_destroy(decoder);
    dlclose(h);

    if (fails) {
        printf("SPIKE RESULT: FAIL (%d)\n", fails);
    } else {
        printf("SPIKE RESULT: PASS\n");
    }
    return fails ? 10 : 0;
}
