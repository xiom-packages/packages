// XIOM -- xiom.jni A11 head: Java host for the live JNIEnv seam probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Run through app_process (the consumer-app stand-in): System.load()
// triggers JNI_OnLoad, which performs the whole seam battery through
// xiom.jni's bridge and RegisterNatives("runProbe").  main() then
// creates a real ARGB_8888 Bitmap, calls runProbe (the native side
// writes/reads/compresses through libjnigraphics), and reads the
// written pixels back on the Java side.
//
// Build+run: powershell -File build-and-run.ps1

package com.xiom.jniprobe;

import android.graphics.Bitmap;
import android.graphics.Bitmap.Config;

public class Probe {
    static {
        System.load("/data/local/tmp/xiom-spike/libxjniprobe.so");
    }

    public static native int runProbe(Bitmap bitmap);

    public static int inc(int a) { return a + 1; }

    public static long tick() { return 1234567890123L; }

    public static double ratio() { return 1.5; }

    // compile-time constant -> ConstantValue set at class preparation, so
    // it is readable through JNI even while <clinit> is still running
    // (JNI_OnLoad fires inside the static initializer's System.load).
    public static final String tag = "probe-tag";

    public static void main(String[] args) {
        Bitmap bmp = Bitmap.createBitmap(64, 64, Config.ARGB_8888);
        int rc = runProbe(bmp);
        // The native side writes raw little-endian uint32s through
        // lockPixels: memory bytes are R,G,B,A, so the Java ARGB int
        // reads back byte-swapped in the low 24 bits (documented in
        // README.md):
        //   raw 0xFF223344 -> bytes 44 33 22 FF -> ARGB 0xFF443322
        //   raw 0xFFADBEEF -> bytes EF BE AD FF -> ARGB 0xFFEFBEAD
        int pixel75 = bmp.getPixel(7, 5);
        int pixel00 = bmp.getPixel(0, 0);
        System.out.println("JNI_PROBE_DONE rc=" + rc
                + " pixel75=0x" + Integer.toHexString(pixel75)
                + " pixel00=0x" + Integer.toHexString(pixel00));
        boolean ok = rc == 0 && pixel75 == 0xFF443322 && pixel00 == 0xFFEFBEAD;
        System.out.println(ok ? "JNI_PROBE JAVA SIDE: PASS" : "JNI_PROBE JAVA SIDE: FAIL");
        // Keep the process alive a moment so logcat flushes.
        try { Thread.sleep(200); } catch (InterruptedException e) { }
    }
}
