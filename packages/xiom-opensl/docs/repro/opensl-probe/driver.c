/* xiom.opensl -- A6 legacy-audio bridge, on-device driver (W2d evidence).
 * Links the package bridge (packages/xiom-opensl/src/opensl_bridge.c)
 * and runs the same path the conformance suite takes on Android:
 * load -> 114-symbol export-table check -> slCreateEngine lifecycle ->
 * interface-table queries -> AMidi verdict.
 *
 * This driver also includes the REAL NDK r27b headers, so it doubles as
 * the constants oracle: the `CONST ...` lines are printed from the
 * headers and can be cross-read against the transcribed values in
 * packages/xiom-opensl/opensl.xi.  The direct `DIRECT ...` lifecycle
 * block uses the real SLObjectItf types as the control for the bridge's
 * pinned vtable facts.  Built with the NDK clang for
 * x86_64-linux-android26; run via adb on the API-36 emulator (see
 * run-probe.ps1).
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>
#include <OMXAL/OpenMAXAL.h>
#include <amidi/AMidi.h>

/* Bridge contract (see packages/xiom-opensl/src/opensl_bridge.c). */
int xo_load(void);
const char* xo_error(void);
int xo_loaded_mask(void);
int xo_sl_missing_count(void);
const char* xo_sl_missing(void);
int xo_xa_missing_count(void);
const char* xo_xa_missing(void);
int xo_amidi_missing_count(void);
const char* xo_amidi_missing(void);
int xo_sl_iid_null_values(void);
int xo_sl_engine_lifecycle(void);
int xo_sl_engine_last_state(void);
int xo_sl_query_num_engine_interfaces(void);
int xo_sl_query_engine_interfaces_ok(void);
int xo_amidi_get_device_info_present(void);
int xo_amidi_device_count_attempt(void);
void xo_unload(void);

static void dump_constants(void) {
    /* Printed from the real r27b headers; transcribed mirror:
     * packages/xiom-opensl/opensl.xi. */
    printf("CONST sl-result %u %u %u %u %u %u\n",
           SL_RESULT_SUCCESS, SL_RESULT_PRECONDITIONS_VIOLATED, SL_RESULT_PARAMETER_INVALID,
           SL_RESULT_CONTENT_NOT_FOUND, SL_RESULT_FEATURE_UNSUPPORTED, SL_RESULT_CONTROL_LOST);
    printf("CONST sl-bool-state %u %u %u %u\n",
           SL_BOOLEAN_FALSE, SL_BOOLEAN_TRUE, SL_OBJECT_STATE_REALIZED, SL_OBJECT_STATE_SUSPENDED);
    printf("CONST sl-play-time %u %u %u %u\n",
           SL_PLAYSTATE_STOPPED, SL_PLAYSTATE_PLAYING, SL_PLAYEVENT_HEADSTALLED, SL_TIME_UNKNOWN);
    printf("CONST sl-device-format %u %u %u %u\n",
           SL_DEFAULTDEVICEID_AUDIOOUTPUT, SL_DATALOCATOR_MIDIBUFFERQUEUE,
           SL_DATAFORMAT_PCM, SL_BYTEORDER_LITTLEENDIAN);
    printf("CONST sl-pcm %u %u %u %d %u\n",
           SL_SAMPLINGRATE_44_1, SL_SAMPLINGRATE_48, SL_PCMSAMPLEFORMAT_FIXED_16,
           (int)SL_MILLIBEL_MIN, SL_SPEAKER_FRONT_LEFT);
    printf("CONST sl-android-loc %u %u %u %u %u\n",
           SL_ANDROID_DATAFORMAT_PCM_EX, SL_DATALOCATOR_ANDROIDFD,
           SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE, SL_DATALOCATOR_ANDROIDBUFFERQUEUE,
           SL_ANDROID_JAVA_PROXY_ROUTING);
    printf("CONST sl-android-cfg %u %u %u %u\n",
           SL_ANDROID_STREAM_MEDIA, SL_ANDROID_PERFORMANCE_LATENCY,
           SL_ANDROID_RECORDING_PRESET_UNPROCESSED, SL_ANDROID_ITEMKEY_FORMAT_CHANGE);
    printf("CONST xa-result %u %u %u %u\n",
           XA_RESULT_SUCCESS, XA_RESULT_CONTROL_LOST, XA_OBJECT_STATE_REALIZED, XA_OBJECTID_CAMERADEVICE);
    printf("CONST xa-misc %u %u %u %u\n",
           XA_DEFAULTDEVICEID_CAMERA, XA_DATAFORMAT_RAWIMAGE, XA_DATALOCATOR_NATIVEDISPLAY,
           XA_ENGINEOPTION_LOSSOFCONTROL);
    printf("CONST amidi %d %d %d %d %d %d\n",
           AMIDI_OPCODE_DATA, AMIDI_DEVICE_TYPE_BLUETOOTH,
           AMIDI_DEVICE_PROTOCOL_UMP_MIDI_2_0, AMIDI_DEVICE_PROTOCOL_UNKNOWN,
           AMEDIA_OK, AMEDIA_ERROR_INVALID_PARAMETER);
}

int main(void) {
    int fails = 0;

    /* 1. Bridge load + 114-symbol export-table check. */
    int rc = xo_load();
    printf("INFO load rc=%d error=%s\n", rc, xo_error());
    if (rc == 1) {
        printf("RESULT: SKIP (legacy-audio runtime absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("FAIL load rc=%d (%s)\n", rc, xo_error());
        return 10;
    }
    printf("OK load (loaded_mask=%d sl_missing=%d xa_missing=%d amidi_missing=%d)\n",
           xo_loaded_mask(), xo_sl_missing_count(), xo_xa_missing_count(),
           xo_amidi_missing_count());
    if (xo_sl_missing_count() != 0) {
        printf("FAIL OpenSLES missing: %s\n", xo_sl_missing());
        fails++;
    }
    if (xo_xa_missing_count() != 0) {
        printf("FAIL OpenMAXAL missing: %s\n", xo_xa_missing());
        fails++;
    }
    if (xo_amidi_missing_count() != 0) {
        printf("FAIL AMidi missing: %s\n", xo_amidi_missing());
        fails++;
    }
    printf("INFO export-set resolved sl=%d/%d xa=%d/%d amidi=%d/%d\n",
           56 - xo_sl_missing_count(), 56, 44 - xo_xa_missing_count(), 44,
           14 - xo_amidi_missing_count(), 14);

    int nulls = xo_sl_iid_null_values();
    printf("INFO sl_iid_null_values=%d\n", nulls);
    if (nulls != 0) {
        printf("FAIL SL_IID_* null GUID slots: %d\n", nulls);
        fails++;
    }

    /* 2. Bridge slCreateEngine lifecycle (all vtable calls C-side). */
    int life = xo_sl_engine_lifecycle();
    printf("INFO bridge lifecycle rc=%d state=%d error=%s\n",
           life, xo_sl_engine_last_state(), xo_error());
    if (life != 0) {
        printf("FAIL bridge engine lifecycle rc=%d\n", life);
        fails++;
    }
    if (xo_sl_engine_last_state() != (int)SL_OBJECT_STATE_REALIZED) {
        printf("FAIL bridge engine state != REALIZED\n");
        fails++;
    }

    /* 3. Direct control lifecycle through the real header types. */
    {
        void* h = dlopen("libOpenSLES.so", RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            printf("FAIL direct dlopen libOpenSLES.so\n");
            fails++;
        } else {
            SLresult (*create)(SLObjectItf*, SLuint32, const SLEngineOption*, SLuint32,
                               const SLInterfaceID*, const SLboolean*) =
                (SLresult (*)(SLObjectItf*, SLuint32, const SLEngineOption*, SLuint32,
                              const SLInterfaceID*, const SLboolean*))dlsym(h, "slCreateEngine");
            if (!create) {
                printf("FAIL direct dlsym slCreateEngine\n");
                fails++;
            } else {
                SLObjectItf engine = 0;
                SLresult r = create(&engine, 0, 0, 0, 0, 0);
                printf("DIRECT create rc=%u engine=%s\n", (unsigned)r, engine ? "non-null" : "null");
                if (r != SL_RESULT_SUCCESS || !engine) {
                    printf("FAIL direct create\n");
                    fails++;
                } else {
                    r = (*engine)->Realize(engine, SL_BOOLEAN_FALSE);
                    printf("DIRECT realize rc=%u\n", (unsigned)r);
                    if (r != SL_RESULT_SUCCESS) fails++;
                    SLuint32 state = 0;
                    r = (*engine)->GetState(engine, &state);
                    printf("DIRECT state rc=%u state=%u\n", (unsigned)r, (unsigned)state);
                    if (r != SL_RESULT_SUCCESS || state != SL_OBJECT_STATE_REALIZED) fails++;
                    (*engine)->Destroy(engine);
                    printf("DIRECT destroy ok\n");
                }
            }
            dlclose(h);
        }
    }

    /* 4. Interface-table queries through the bridge. */
    int num = xo_sl_query_num_engine_interfaces();
    int iid_ok = xo_sl_query_engine_interfaces_ok();
    printf("INFO sl engine interfaces num=%d queried_ok=%d\n", num, iid_ok);
    if (num < 0 || iid_ok != num) {
        printf("FAIL interface-table queries\n");
        fails++;
    }

    /* 5. AMidi verdict. */
    int present = xo_amidi_get_device_info_present();
    int count = xo_amidi_device_count_attempt();
    printf("INFO amidi getDeviceInfo_present=%d count_attempt=%d (%s)\n",
           present, count, xo_error());
    if ((!present && count != -1) || (present && count != -2 && count < 0)) {
        printf("FAIL amidi count-attempt verdict\n");
        fails++;
    }

    /* 6. Constants oracle dump (real headers). */
    dump_constants();

    xo_unload();
    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
    } else {
        printf("RESULT: PASS\n");
    }
    return fails ? 10 : 0;
}
