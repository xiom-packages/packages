package xiom_camera2ndk {
  name: "xiom.camera2ndk";
  version: "0.1.0";
  description: "Android camera2 NDK bindings (NDK r27b A8 camera head: NdkCameraManager.h + NdkCameraDevice.h + NdkCameraCaptureSession.h + NdkCaptureRequest.h + NdkCameraMetadata.h + NdkCameraMetadataTags.h + NdkCameraError.h) via a runtime libcamera2ndk.so bridge with SKIP semantics; functional ACameraManager create/delete + camera-id list (typed ACAMERA_ERROR_* outcomes are non-fatal); 70-symbol export set bound + ABI-checked (device/session/request async surfaces are export-set only this wave; data callbacks staged later)";
  categories: ["platform"];
  keywords: ["android", "ndk", "camera", "camera2", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
