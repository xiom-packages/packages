package xiom_mediandk {
  name: "xiom.mediandk";
  version: "0.1.0";
  description: "Android NDK media bindings (NDK r27b oracle; runtime libmediandk.so bridge with SKIP semantics): A7 core media head -- AMediaCodec/AMediaFormat/AMediaExtractor/AMediaMuxer/AMediaDrm/AMediaDataSource declared surface (276 symbols bound + ABI-checked) with functional AMediaFormat roundtrips (int32/float/string/buffer/toString) and an audio/opus decoder-create probe";
  categories: ["platform"];
  keywords: ["android", "ndk", "media", "mediacodec", "mediandk", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.mediandk"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
