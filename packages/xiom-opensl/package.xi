package xiom_opensl {
  name: "xiom.opensl";
  version: "0.1.0";
  description: "Android legacy audio bindings (NDK r27b): OpenSL ES (SLES/OpenSLES.h + OpenSLES_Android.h: slCreateEngine/slQuery*EngineInterfaces + 53 SL_IID_* runtime interface-ID globals), OpenMAX AL (OMXAL/OpenMAXAL.h: xaCreateEngine/xaQuery*EngineInterfaces + 41 XA_IID_* globals) and AMidi (amidi/AMidi.h: 14 functions) via a runtime libOpenSLES.so/libOpenMAXAL.so/libamidi.so bridge with SKIP semantics; functional slCreateEngine -> Realize -> Destroy engine lifecycle (all vtable calls stay C-side); 114-symbol export set bound + ABI-checked";
  categories: ["media", "systems"];
  keywords: ["android", "ndk", "opensl", "opensles", "openmaxal", "amidi", "midi", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
