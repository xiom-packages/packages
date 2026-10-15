/* xiom.mediandk -- A7 core media head, on-device driver.
 * Links the package bridge (packages/xiom-mediandk/src/mediandk_bridge.c)
 * and runs the same path the conformance suite takes on Android:
 *   load -> export-set check (276) -> AMediaFormat functional roundtrips
 *   (int32/float/string/buffer/toString) -> audio/opus decoder-create
 *   probe -> key-symbol value fidelity (when keys_expected.h is present,
 *   generated from mediandk.xi by gen-keys-expected.ps1).
 *
 * Built with the NDK clang for x86_64-linux-android26; run via adb on the
 * API-36 emulator (see build-probe.ps1).  When keys_expected.h is absent
 * the driver runs in DUMP mode and prints every declared key symbol and
 * its runtime value (used to transcribe the Str constants once).
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Bridge contract (see packages/xiom-mediandk/src/mediandk_bridge.c). */
int32_t xm_load(void);
const char* xm_error(void);
int32_t xm_abi_missing_count(void);
const char* xm_abi_missing(void);
int32_t xm_export_count(void);
int32_t xm_key_count(void);
const char* xm_key_symbol(int32_t index);
const char* xm_key_value(int32_t index);
const char* xm_key_lookup(const char* symbol);
int64_t xm_format_new(void);
int32_t xm_format_delete(int64_t fmt);
const char* xm_format_to_string(int64_t fmt);
void xm_format_set_int32(int64_t fmt, const char* name, int32_t value);
int32_t xm_format_get_int32(int64_t fmt, const char* name);
int64_t xm_format_slot_int(void);
void xm_format_set_float(int64_t fmt, const char* name, float value);
int32_t xm_format_get_float(int64_t fmt, const char* name);
float xm_format_slot_float(void);
void xm_format_set_string(int64_t fmt, const char* name, const char* value);
const char* xm_format_get_string(int64_t fmt, const char* name);
int32_t xm_format_stage_begin(int32_t size);
void xm_format_stage_byte(int32_t pos, int32_t value);
int32_t xm_format_set_buffer(int64_t fmt, const char* name);
int64_t xm_format_get_buffer(int64_t fmt, const char* name);
int32_t xm_format_slot_byte(int64_t index);
int64_t xm_codec_create_decoder_by_type(const char* mime);
int32_t xm_codec_delete(int64_t codec);
void xm_unload(void);

#if defined(__has_include)
#  if __has_include("keys_expected.h")
#    include "keys_expected.h"
#    define XM_HAVE_EXPECTED 1
#  endif
#endif

static int fails = 0;

static void check(int ok, const char* what) {
    if (!ok) {
        printf("FAIL %s\n", what);
        fails++;
    }
}

int main(void) {
    printf("== xiom.mediandk on-device driver (A7 core media head) ==\n");
    int rc = xm_load();
    printf("load rc=%d", rc);
    if (rc != 0) {
        printf(" error=%s\n", xm_error());
    } else {
        printf(" error=<clean>\n");
    }
    if (rc == 1) {
        printf("RESULT: SKIP (libmediandk.so absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("RESULT: FAIL (load rc=%d)\n", rc);
        return 10;
    }
    int missing = xm_abi_missing_count();
    printf("export_count=%d missing_exports=%d\n", xm_export_count(), missing);
    if (missing != 0) {
        printf("missing: %s\n", xm_abi_missing());
        fails++;
    }

    /* Key symbols drive the functional roundtrips (values resolved at
     * runtime; the transcribed package constants are checked below). */
    const char* k_color = xm_key_lookup("AMEDIAFORMAT_KEY_COLOR_FORMAT");
    const char* k_width = xm_key_lookup("AMEDIAFORMAT_KEY_WIDTH");
    const char* k_mime = xm_key_lookup("AMEDIAFORMAT_KEY_MIME");
    const char* k_rate = xm_key_lookup("AMEDIAFORMAT_KEY_FRAME_RATE");
    const char* k_csd0 = xm_key_lookup("AMEDIAFORMAT_KEY_CSD_0");
    check(k_color && k_width && k_mime && k_rate && k_csd0,
          "key symbols resolve (color-format/width/mime/frame-rate/csd-0)");
    printf("keys: color-format=%s width=%s mime=%s frame-rate=%s csd-0=%s\n",
           k_color ? k_color : "?", k_width ? k_width : "?",
           k_mime ? k_mime : "?", k_rate ? k_rate : "?",
           k_csd0 ? k_csd0 : "?");

    /* AMediaFormat functional roundtrips. */
    int64_t fmt = xm_format_new();
    check(fmt != 0, "format new");
    if (!fmt) { printf("RESULT: FAIL (format new)\n"); return 11; }
    printf("format: new ok handle=%lld\n", (long long)fmt);

    xm_format_set_int32(fmt, k_color, 21);
    check(xm_format_get_int32(fmt, k_color) == 1 && xm_format_slot_int() == 21,
          "int32 roundtrip color-format=21");
    printf("format: int32 color-format get=%lld (want 21)\n",
           (long long)xm_format_slot_int());

    xm_format_set_int32(fmt, k_width, 640);
    check(xm_format_get_int32(fmt, k_width) == 1 && xm_format_slot_int() == 640,
          "int32 roundtrip width=640");
    printf("format: int32 width get=%lld (want 640)\n",
           (long long)xm_format_slot_int());

    xm_format_set_string(fmt, k_mime, "audio/opus");
    const char* got_s = xm_format_get_string(fmt, k_mime);
    check(got_s && strcmp(got_s, "audio/opus") == 0, "string roundtrip mime");
    printf("format: string mime get=%s (want audio/opus)\n", got_s ? got_s : "<NULL>");

    xm_format_set_float(fmt, k_rate, 2.5f);
    int ff = xm_format_get_float(fmt, k_rate);
    float got_f = xm_format_slot_float();
    check(ff == 1 && got_f == 2.5f, "float roundtrip frame-rate=2.5");
    printf("format: float frame-rate found=%d get=%f (want 2.500000)\n", ff,
           (double)got_f);

    static const uint8_t payload[4] = {0x12, 0x34, 0x56, 0x78};
    check(xm_format_stage_begin(4) == 0, "buffer stage begin");
    for (int32_t i = 0; i < 4; i++) xm_format_stage_byte(i, payload[i]);
    check(xm_format_set_buffer(fmt, k_csd0) == 0, "buffer set");
    int64_t blen = xm_format_get_buffer(fmt, k_csd0);
    int buf_ok = (blen == 4);
    for (int32_t i = 0; i < 4 && buf_ok; i++) {
        if (xm_format_slot_byte(i) != payload[i]) buf_ok = 0;
    }
    check(buf_ok, "buffer roundtrip csd-0 4 bytes");
    printf("format: buffer csd-0 size=%lld bytes=%02x%02x%02x%02x (want 4 / 12345678)\n",
           (long long)blen, xm_format_slot_byte(0) & 0xFF, xm_format_slot_byte(1) & 0xFF,
           xm_format_slot_byte(2) & 0xFF, xm_format_slot_byte(3) & 0xFF);

    const char* ts = xm_format_to_string(fmt);
    int ts_ok = ts && strlen(ts) > 0 && strstr(ts, k_color) && strstr(ts, "21")
                && strstr(ts, "audio/opus");
    check(ts_ok, "toString carries the set entries");
    printf("format: toString=%s\n", ts ? ts : "<NULL>");

    int32_t drc = xm_format_delete(fmt);
    check(drc == 0, "format delete rc==0");
    printf("format: delete rc=%d\n", drc);

    /* AMediaCodec head: decoder create/delete probe (NON-FATAL either way). */
    int64_t codec = xm_codec_create_decoder_by_type("audio/opus");
    if (codec) {
        int32_t crc = xm_codec_delete(codec);
        check(crc == 0, "codec delete rc==0");
        printf("codec: audio/opus decoder create -> handle=%lld delete rc=%d VERDICT=PRESENT\n",
               (long long)codec, crc);
    } else {
        printf("codec: audio/opus decoder create -> NULL (%s) VERDICT=ABSENT (NON-FATAL)\n",
               xm_error());
    }

    /* Key symbol fidelity: transcribed constants vs runtime values. */
    int nkeys = xm_key_count();
    printf("keys: declared=%d\n", nkeys);
#ifdef XM_HAVE_EXPECTED
    int mismatches = 0;
    if (XM_EXPECTED_KEYS_COUNT != nkeys) {
        printf("FAIL expected-table count %d != declared %d\n", XM_EXPECTED_KEYS_COUNT, nkeys);
        fails++;
    }
    for (int i = 0; i < XM_EXPECTED_KEYS_COUNT; i++) {
        const char* live = xm_key_lookup(k_expected_keys[i].symbol);
        if (!live || strcmp(live, k_expected_keys[i].value) != 0) {
            printf("FAIL key %s: constant=%s runtime=%s\n", k_expected_keys[i].symbol,
                   k_expected_keys[i].value, live ? live : "<NULL>");
            mismatches++;
        }
    }
    printf("keys: fidelity checked=%d mismatches=%d\n", XM_EXPECTED_KEYS_COUNT, mismatches);
    if (mismatches) fails++;
#else
    for (int i = 0; i < nkeys; i++) {
        const char* sym = xm_key_symbol(i);
        const char* val = xm_key_value(i);
        printf("KEY %s=%s\n", sym ? sym : "?", val ? val : "<NULL>");
    }
#endif

    xm_unload();

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
        return 10;
    }
    printf("RESULT: PASS\n");
    return 0;
}
