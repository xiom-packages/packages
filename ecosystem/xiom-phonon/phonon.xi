// XIOM - Steam Audio (Phonon) FFI Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level extern "C" declarations for phonon.dll (Steam Audio SDK v4.8.1).
// Steam Audio is Valve's spatial audio library providing binaural rendering,
// physics-based sound propagation, and HRTF-based 3D audio effects.
//
// Target: phonon.dll (Windows), libphonon.so (Linux), libphonon.dylib (macOS)
// Struct parameters use *UInt8 due to compiler struct-layout gap; see AUDIT.md.
module xiom.phonon

// ─────────────────────────────────────────────────────────────
//  Version Constants
// ─────────────────────────────────────────────────────────────

pub const STEAMAUDIO_VERSION_MAJOR: Int = 4;
pub const STEAMAUDIO_VERSION_MINOR: Int = 8;
pub const STEAMAUDIO_VERSION_PATCH: Int = 1;
pub const IPL_NUM_BANDS: Int = 3;

// ─────────────────────────────────────────────────────────────
//  Opaque Handle Types (32 handles)
// ─────────────────────────────────────────────────────────────

pub type IPLContext = Int;
pub type IPLSerializedObject = Int;
pub type IPLEmbreeDevice = Int;
pub type IPLOpenCLDeviceList = Int;
pub type IPLOpenCLDevice = Int;
pub type IPLRadeonRaysDevice = Int;
pub type IPLTrueAudioNextDevice = Int;
pub type IPLScene = Int;
pub type IPLStaticMesh = Int;
pub type IPLInstancedMesh = Int;
pub type IPLHRTF = Int;
pub type IPLPanningEffect = Int;
pub type IPLBinauralEffect = Int;
pub type IPLVirtualSurroundEffect = Int;
pub type IPLAmbisonicsEncodeEffect = Int;
pub type IPLAmbisonicsPanningEffect = Int;
pub type IPLAmbisonicsBinauralEffect = Int;
pub type IPLAmbisonicsRotationEffect = Int;
pub type IPLAmbisonicsDecodeEffect = Int;
pub type IPLDirectEffect = Int;
pub type IPLReflectionEffectIR = Int;
pub type IPLReflectionEffect = Int;
pub type IPLReflectionMixer = Int;
pub type IPLPathEffect = Int;
pub type IPLEnergyField = Int;
pub type IPLImpulseResponse = Int;
pub type IPLReconstructor = Int;
pub type IPLProbeArray = Int;
pub type IPLProbeBatch = Int;
pub type IPLSource = Int;
pub type IPLSimulator = Int;

// ─────────────────────────────────────────────────────────────
//  Error Codes
// ─────────────────────────────────────────────────────────────

pub const IPL_STATUS_SUCCESS: Int32 = 0;
pub const IPL_STATUS_FAILURE: Int32 = 1;
pub const IPL_STATUS_OUTOFMEMORY: Int32 = 2;
pub const IPL_STATUS_INITIALIZATION: Int32 = 3;

// ─────────────────────────────────────────────────────────────
//  Boolean Constants
// ─────────────────────────────────────────────────────────────

pub const IPL_FALSE: Int32 = 0;
pub const IPL_TRUE: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLLogLevel
// ─────────────────────────────────────────────────────────────

pub const IPL_LOGLEVEL_INFO: Int32 = 0;
pub const IPL_LOGLEVEL_WARNING: Int32 = 1;
pub const IPL_LOGLEVEL_ERROR: Int32 = 2;
pub const IPL_LOGLEVEL_DEBUG: Int32 = 3;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLSIMDLevel
// ─────────────────────────────────────────────────────────────

pub const IPL_SIMDLEVEL_SSE2: Int32 = 0;
pub const IPL_SIMDLEVEL_SSE4: Int32 = 1;
pub const IPL_SIMDLEVEL_AVX: Int32 = 2;
pub const IPL_SIMDLEVEL_AVX2: Int32 = 3;
pub const IPL_SIMDLEVEL_AVX512: Int32 = 4;
pub const IPL_SIMDLEVEL_NEON: Int32 = 0;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLContextFlags
// ─────────────────────────────────────────────────────────────

pub const IPL_CONTEXTFLAGS_VALIDATION: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLOpenCLDeviceType
// ─────────────────────────────────────────────────────────────

pub const IPL_OPENCLDEVICETYPE_ANY: Int32 = 0;
pub const IPL_OPENCLDEVICETYPE_CPU: Int32 = 1;
pub const IPL_OPENCLDEVICETYPE_GPU: Int32 = 2;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLSceneType
// ─────────────────────────────────────────────────────────────

pub const IPL_SCENETYPE_DEFAULT: Int32 = 0;
pub const IPL_SCENETYPE_EMBREE: Int32 = 1;
pub const IPL_SCENETYPE_RADEONRAYS: Int32 = 2;
pub const IPL_SCENETYPE_CUSTOM: Int32 = 3;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLSpeakerLayoutType
// ─────────────────────────────────────────────────────────────

pub const IPL_SPEAKERLAYOUTTYPE_MONO: Int32 = 0;
pub const IPL_SPEAKERLAYOUTTYPE_STEREO: Int32 = 1;
pub const IPL_SPEAKERLAYOUTTYPE_QUADRAPHONIC: Int32 = 2;
pub const IPL_SPEAKERLAYOUTTYPE_SURROUND_5_1: Int32 = 3;
pub const IPL_SPEAKERLAYOUTTYPE_SURROUND_7_1: Int32 = 4;
pub const IPL_SPEAKERLAYOUTTYPE_CUSTOM: Int32 = 5;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLAmbisonicsType
// ─────────────────────────────────────────────────────────────

pub const IPL_AMBISONICSTYPE_N3D: Int32 = 0;
pub const IPL_AMBISONICSTYPE_SN3D: Int32 = 1;
pub const IPL_AMBISONICSTYPE_FUMA: Int32 = 2;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLAudioEffectState
// ─────────────────────────────────────────────────────────────

pub const IPL_AUDIOEFFECTSTATE_TAILREMAINING: Int32 = 0;
pub const IPL_AUDIOEFFECTSTATE_TAILCOMPLETE: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLHRTFType
// ─────────────────────────────────────────────────────────────

pub const IPL_HRTFTYPE_DEFAULT: Int32 = 0;
pub const IPL_HRTFTYPE_SOFA: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLHRTFNormType
// ─────────────────────────────────────────────────────────────

pub const IPL_HRTFNORMTYPE_NONE: Int32 = 0;
pub const IPL_HRTFNORMTYPE_RMS: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLHRTFInterpolation
// ─────────────────────────────────────────────────────────────

pub const IPL_HRTFINTERPOLATION_NEAREST: Int32 = 0;
pub const IPL_HRTFINTERPOLATION_BILINEAR: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLDirectEffectFlags
// ─────────────────────────────────────────────────────────────

pub const IPL_DIRECTEFFECTFLAGS_APPLYDISTANCEATTENUATION: Int32 = 1;
pub const IPL_DIRECTEFFECTFLAGS_APPLYAIRABSORPTION: Int32 = 2;
pub const IPL_DIRECTEFFECTFLAGS_APPLYDIRECTIVITY: Int32 = 4;
pub const IPL_DIRECTEFFECTFLAGS_APPLYOCCLUSION: Int32 = 8;
pub const IPL_DIRECTEFFECTFLAGS_APPLYTRANSMISSION: Int32 = 16;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLTransmissionType
// ─────────────────────────────────────────────────────────────

pub const IPL_TRANSMISSIONTYPE_FREQINDEPENDENT: Int32 = 0;
pub const IPL_TRANSMISSIONTYPE_FREQDEPENDENT: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLReflectionEffectType
// ─────────────────────────────────────────────────────────────

pub const IPL_REFLECTIONEFFECTTYPE_CONVOLUTION: Int32 = 0;
pub const IPL_REFLECTIONEFFECTTYPE_PARAMETRIC: Int32 = 1;
pub const IPL_REFLECTIONEFFECTTYPE_HYBRID: Int32 = 2;
pub const IPL_REFLECTIONEFFECTTYPE_TAN: Int32 = 3;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLProbeGenerationType
// ─────────────────────────────────────────────────────────────

pub const IPL_PROBEGENERATIONTYPE_CENTROID: Int32 = 0;
pub const IPL_PROBEGENERATIONTYPE_UNIFORMFLOOR: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLBakedDataVariation
// ─────────────────────────────────────────────────────────────

pub const IPL_BAKEDDATAVARIATION_REVERB: Int32 = 0;
pub const IPL_BAKEDDATAVARIATION_STATICSOURCE: Int32 = 1;
pub const IPL_BAKEDDATAVARIATION_STATICLISTENER: Int32 = 2;
pub const IPL_BAKEDDATAVARIATION_DYNAMIC: Int32 = 3;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLBakedDataType
// ─────────────────────────────────────────────────────────────

pub const IPL_BAKEDDATATYPE_REFLECTIONS: Int32 = 0;
pub const IPL_BAKEDDATATYPE_PATHING: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLReflectionsBakeFlags
// ─────────────────────────────────────────────────────────────

pub const IPL_REFLECTIONSBAKEFLAGS_BAKECONVOLUTION: Int32 = 1;
pub const IPL_REFLECTIONSBAKEFLAGS_BAKEPARAMETRIC: Int32 = 2;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLSimulationFlags
// ─────────────────────────────────────────────────────────────

pub const IPL_SIMULATIONFLAGS_DIRECT: Int32 = 1;
pub const IPL_SIMULATIONFLAGS_REFLECTIONS: Int32 = 2;
pub const IPL_SIMULATIONFLAGS_PATHING: Int32 = 4;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLDirectSimulationFlags
// ─────────────────────────────────────────────────────────────

pub const IPL_DIRECTSIMULATIONFLAGS_DISTANCEATTENUATION: Int32 = 1;
pub const IPL_DIRECTSIMULATIONFLAGS_AIRABSORPTION: Int32 = 2;
pub const IPL_DIRECTSIMULATIONFLAGS_DIRECTIVITY: Int32 = 4;
pub const IPL_DIRECTSIMULATIONFLAGS_OCCLUSION: Int32 = 8;
pub const IPL_DIRECTSIMULATIONFLAGS_TRANSMISSION: Int32 = 16;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLDistanceAttenuationModelType
// ─────────────────────────────────────────────────────────────

pub const IPL_DISTANCEATTENUATIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_DISTANCEATTENUATIONTYPE_INVERSEDISTANCE: Int32 = 1;
pub const IPL_DISTANCEATTENUATIONTYPE_CALLBACK: Int32 = 2;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLAirAbsorptionModelType
// ─────────────────────────────────────────────────────────────

pub const IPL_AIRABSORPTIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_AIRABSORPTIONTYPE_EXPONENTIAL: Int32 = 1;
pub const IPL_AIRABSORPTIONTYPE_CALLBACK: Int32 = 2;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLOcclusionType
// ─────────────────────────────────────────────────────────────

pub const IPL_OCCLUSIONTYPE_RAYCAST: Int32 = 0;
pub const IPL_OCCLUSIONTYPE_VOLUMETRIC: Int32 = 1;

// ─────────────────────────────────────────────────────────────
//  Enum: IPLDeviationModelType
// ─────────────────────────────────────────────────────────────

pub const IPL_DEVIATIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_DEVIATIONTYPE_CALLBACK: Int32 = 1;

// ═════════════════════════════════════════════════════════════
//  extern "C" FFI Declarations
// ═════════════════════════════════════════════════════════════
//
//  Conventions:
//   - IPLContext, IPLHRTF, etc.    => Int  (opaque pointer-sized handle)
//   - IPLContextSettings*, etc.     => *UInt8  (raw struct pointer)
//   - IPLerror, IPLint32, etc.      => Int32  (32-bit integer)
//   - IPLfloat32                    => Float32
//   - IPLstring (const char*)       => Str
//   - void return                   => no return type listed
//   - ipl*Release functions take pointer-to-handle (*UInt8) to null out

extern "C" {

  // ── Context ──────────────────────────────────────────────

  fn iplContextCreate(settings: *UInt8, context: *UInt8) -> Int32;
  fn iplContextRetain(context: Int) -> Int;
  fn iplContextRelease(context: *UInt8);

  // ── Serialization ────────────────────────────────────────

  fn iplSerializedObjectCreate(context: Int, settings: *UInt8, serializedObject: *UInt8) -> Int32;
  fn iplSerializedObjectRetain(serializedObject: Int) -> Int;
  fn iplSerializedObjectRelease(serializedObject: *UInt8);
  fn iplSerializedObjectGetSize(serializedObject: Int) -> Int;
  fn iplSerializedObjectGetData(serializedObject: Int) -> Int;

  // ── Embree Device ────────────────────────────────────────

  fn iplEmbreeDeviceCreate(context: Int, settings: *UInt8, device: *UInt8) -> Int32;
  fn iplEmbreeDeviceRetain(device: Int) -> Int;
  fn iplEmbreeDeviceRelease(device: *UInt8);

  // ── OpenCL Device ────────────────────────────────────────

  fn iplOpenCLDeviceListCreate(context: Int, settings: *UInt8, deviceList: *UInt8) -> Int32;
  fn iplOpenCLDeviceListRetain(deviceList: Int) -> Int;
  fn iplOpenCLDeviceListRelease(deviceList: *UInt8);
  fn iplOpenCLDeviceListGetNumDevices(deviceList: Int) -> Int32;
  fn iplOpenCLDeviceListGetDeviceDesc(deviceList: Int, index: Int32, deviceDesc: *UInt8);
  fn iplOpenCLDeviceCreate(context: Int, deviceList: Int, index: Int32, device: *UInt8) -> Int32;
  fn iplOpenCLDeviceCreateFromExisting(context: Int, convolutionQueue: *UInt8, irUpdateQueue: *UInt8, device: *UInt8) -> Int32;
  fn iplOpenCLDeviceRetain(device: Int) -> Int;
  fn iplOpenCLDeviceRelease(device: *UInt8);

  // ── Radeon Rays Device ───────────────────────────────────

  fn iplRadeonRaysDeviceCreate(openCLDevice: Int, settings: *UInt8, rrDevice: *UInt8) -> Int32;
  fn iplRadeonRaysDeviceRetain(device: Int) -> Int;
  fn iplRadeonRaysDeviceRelease(device: *UInt8);

  // ── TrueAudio Next Device ────────────────────────────────

  fn iplTrueAudioNextDeviceCreate(openCLDevice: Int, settings: *UInt8, tanDevice: *UInt8) -> Int32;
  fn iplTrueAudioNextDeviceRetain(device: Int) -> Int;
  fn iplTrueAudioNextDeviceRelease(device: *UInt8);

  // ── Scene ────────────────────────────────────────────────

  fn iplSceneCreate(context: Int, settings: *UInt8, scene: *UInt8) -> Int32;
  fn iplSceneRetain(scene: Int) -> Int;
  fn iplSceneRelease(scene: *UInt8);
  fn iplSceneLoad(context: Int, settings: *UInt8, serializedObject: Int, progressCallback: Int, progressCallbackUserData: Int, scene: *UInt8) -> Int32;
  fn iplSceneSave(scene: Int, serializedObject: Int);
  fn iplSceneSaveOBJ(scene: Int, fileBaseName: Str);
  fn iplSceneCommit(scene: Int);

  // ── Static Mesh ──────────────────────────────────────────

  fn iplStaticMeshCreate(scene: Int, settings: *UInt8, staticMesh: *UInt8) -> Int32;
  fn iplStaticMeshRetain(staticMesh: Int) -> Int;
  fn iplStaticMeshRelease(staticMesh: *UInt8);
  fn iplStaticMeshLoad(scene: Int, serializedObject: Int, progressCallback: Int, progressCallbackUserData: Int, staticMesh: *UInt8) -> Int32;
  fn iplStaticMeshSave(staticMesh: Int, serializedObject: Int);
  fn iplStaticMeshAdd(staticMesh: Int, scene: Int);
  fn iplStaticMeshRemove(staticMesh: Int, scene: Int);
  fn iplStaticMeshSetMaterial(staticMesh: Int, scene: Int, newMaterial: *UInt8, index: Int32);

  // ── Instanced Mesh ───────────────────────────────────────

  fn iplInstancedMeshCreate(scene: Int, settings: *UInt8, instancedMesh: *UInt8) -> Int32;
  fn iplInstancedMeshRetain(instancedMesh: Int) -> Int;
  fn iplInstancedMeshRelease(instancedMesh: *UInt8);
  fn iplInstancedMeshAdd(instancedMesh: Int, scene: Int);
  fn iplInstancedMeshRemove(instancedMesh: Int, scene: Int);
  fn iplInstancedMeshUpdateTransform(instancedMesh: Int, scene: Int, transform: *UInt8);

  // ── Audio Buffers ────────────────────────────────────────

  fn iplAudioBufferAllocate(context: Int, numChannels: Int32, numSamples: Int32, audioBuffer: *UInt8) -> Int32;
  fn iplAudioBufferFree(context: Int, audioBuffer: *UInt8);
  fn iplAudioBufferInterleave(context: Int, src: *UInt8, dst: *UInt8);
  fn iplAudioBufferDeinterleave(context: Int, src: *UInt8, dst: *UInt8);
  fn iplAudioBufferMix(context: Int, inBuf: *UInt8, mixBuf: *UInt8);
  fn iplAudioBufferDownmix(context: Int, inBuf: *UInt8, outBuf: *UInt8);
  fn iplAudioBufferConvertAmbisonics(context: Int, inType: Int32, outType: Int32, inBuf: *UInt8, outBuf: *UInt8);

  // ── HRTF ─────────────────────────────────────────────────

  fn iplHRTFCreate(context: Int, audioSettings: *UInt8, hrtfSettings: *UInt8, hrtf: *UInt8) -> Int32;
  fn iplHRTFRetain(hrtf: Int) -> Int;
  fn iplHRTFRelease(hrtf: *UInt8);

  // ── Panning Effect ───────────────────────────────────────

  fn iplPanningEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplPanningEffectRetain(effect: Int) -> Int;
  fn iplPanningEffectRelease(effect: *UInt8);
  fn iplPanningEffectReset(effect: Int);
  fn iplPanningEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplPanningEffectGetTailSize(effect: Int) -> Int32;
  fn iplPanningEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Binaural Effect ──────────────────────────────────────

  fn iplBinauralEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplBinauralEffectRetain(effect: Int) -> Int;
  fn iplBinauralEffectRelease(effect: *UInt8);
  fn iplBinauralEffectReset(effect: Int);
  fn iplBinauralEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplBinauralEffectGetTailSize(effect: Int) -> Int32;
  fn iplBinauralEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Virtual Surround Effect ──────────────────────────────

  fn iplVirtualSurroundEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplVirtualSurroundEffectRetain(effect: Int) -> Int;
  fn iplVirtualSurroundEffectRelease(effect: *UInt8);
  fn iplVirtualSurroundEffectReset(effect: Int);
  fn iplVirtualSurroundEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplVirtualSurroundEffectGetTailSize(effect: Int) -> Int32;
  fn iplVirtualSurroundEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Ambisonics Encode Effect ─────────────────────────────

  fn iplAmbisonicsEncodeEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplAmbisonicsEncodeEffectRetain(effect: Int) -> Int;
  fn iplAmbisonicsEncodeEffectRelease(effect: *UInt8);
  fn iplAmbisonicsEncodeEffectReset(effect: Int);
  fn iplAmbisonicsEncodeEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplAmbisonicsEncodeEffectGetTailSize(effect: Int) -> Int32;
  fn iplAmbisonicsEncodeEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Ambisonics Panning Effect ────────────────────────────

  fn iplAmbisonicsPanningEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplAmbisonicsPanningEffectRetain(effect: Int) -> Int;
  fn iplAmbisonicsPanningEffectRelease(effect: *UInt8);
  fn iplAmbisonicsPanningEffectReset(effect: Int);
  fn iplAmbisonicsPanningEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplAmbisonicsPanningEffectGetTailSize(effect: Int) -> Int32;
  fn iplAmbisonicsPanningEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Ambisonics Binaural Effect ───────────────────────────

  fn iplAmbisonicsBinauralEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplAmbisonicsBinauralEffectRetain(effect: Int) -> Int;
  fn iplAmbisonicsBinauralEffectRelease(effect: *UInt8);
  fn iplAmbisonicsBinauralEffectReset(effect: Int);
  fn iplAmbisonicsBinauralEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplAmbisonicsBinauralEffectGetTailSize(effect: Int) -> Int32;
  fn iplAmbisonicsBinauralEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Ambisonics Rotation Effect ───────────────────────────

  fn iplAmbisonicsRotationEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplAmbisonicsRotationEffectRetain(effect: Int) -> Int;
  fn iplAmbisonicsRotationEffectRelease(effect: *UInt8);
  fn iplAmbisonicsRotationEffectReset(effect: Int);
  fn iplAmbisonicsRotationEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplAmbisonicsRotationEffectGetTailSize(effect: Int) -> Int32;
  fn iplAmbisonicsRotationEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Ambisonics Decode Effect ─────────────────────────────

  fn iplAmbisonicsDecodeEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplAmbisonicsDecodeEffectRetain(effect: Int) -> Int;
  fn iplAmbisonicsDecodeEffectRelease(effect: *UInt8);
  fn iplAmbisonicsDecodeEffectReset(effect: Int);
  fn iplAmbisonicsDecodeEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplAmbisonicsDecodeEffectGetTailSize(effect: Int) -> Int32;
  fn iplAmbisonicsDecodeEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Direct Effect ────────────────────────────────────────

  fn iplDirectEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplDirectEffectRetain(effect: Int) -> Int;
  fn iplDirectEffectRelease(effect: *UInt8);
  fn iplDirectEffectReset(effect: Int);
  fn iplDirectEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplDirectEffectGetTailSize(effect: Int) -> Int32;
  fn iplDirectEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Reflection Effect ────────────────────────────────────

  fn iplReflectionEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplReflectionEffectRetain(effect: Int) -> Int;
  fn iplReflectionEffectRelease(effect: *UInt8);
  fn iplReflectionEffectReset(effect: Int);
  fn iplReflectionEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8, mixer: Int) -> Int32;
  fn iplReflectionEffectGetTailSize(effect: Int) -> Int32;
  fn iplReflectionEffectGetTail(effect: Int, outBuf: *UInt8, mixer: Int) -> Int32;

  // ── Reflection Mixer ─────────────────────────────────────

  fn iplReflectionMixerCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, mixer: *UInt8) -> Int32;
  fn iplReflectionMixerRetain(mixer: Int) -> Int;
  fn iplReflectionMixerRelease(mixer: *UInt8);
  fn iplReflectionMixerReset(mixer: Int);
  fn iplReflectionMixerApply(mixer: Int, params: *UInt8, outBuf: *UInt8) -> Int32;

  // ── Path Effect ──────────────────────────────────────────

  fn iplPathEffectCreate(context: Int, audioSettings: *UInt8, effectSettings: *UInt8, effect: *UInt8) -> Int32;
  fn iplPathEffectRetain(effect: Int) -> Int;
  fn iplPathEffectRelease(effect: *UInt8);
  fn iplPathEffectReset(effect: Int);
  fn iplPathEffectApply(effect: Int, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32;
  fn iplPathEffectGetTailSize(effect: Int) -> Int32;
  fn iplPathEffectGetTail(effect: Int, outBuf: *UInt8) -> Int32;

  // ── Energy Field ─────────────────────────────────────────

  fn iplEnergyFieldCreate(context: Int, settings: *UInt8, energyField: *UInt8) -> Int32;
  fn iplEnergyFieldRetain(energyField: Int) -> Int;
  fn iplEnergyFieldRelease(energyField: *UInt8);
  fn iplEnergyFieldGetNumChannels(energyField: Int) -> Int32;
  fn iplEnergyFieldGetNumBins(energyField: Int) -> Int32;
  fn iplEnergyFieldGetData(energyField: Int) -> Int;
  fn iplEnergyFieldGetChannel(energyField: Int, channelIndex: Int32) -> Int;
  fn iplEnergyFieldGetBand(energyField: Int, channelIndex: Int32, bandIndex: Int32) -> Int;
  fn iplEnergyFieldReset(energyField: Int);
  fn iplEnergyFieldCopy(src: Int, dst: Int);
  fn iplEnergyFieldSwap(a: Int, b: Int);
  fn iplEnergyFieldAdd(in1: Int, in2: Int, out: Int);
  fn iplEnergyFieldScale(inBuf: Int, scalar: Float32, out: Int);
  fn iplEnergyFieldScaleAccum(inBuf: Int, scalar: Float32, out: Int);

  // ── Impulse Response ─────────────────────────────────────

  fn iplImpulseResponseCreate(context: Int, settings: *UInt8, impulseResponse: *UInt8) -> Int32;
  fn iplImpulseResponseRetain(impulseResponse: Int) -> Int;
  fn iplImpulseResponseRelease(impulseResponse: *UInt8);
  fn iplImpulseResponseGetNumChannels(impulseResponse: Int) -> Int32;
  fn iplImpulseResponseGetNumSamples(impulseResponse: Int) -> Int32;
  fn iplImpulseResponseGetData(impulseResponse: Int) -> Int;
  fn iplImpulseResponseGetChannel(impulseResponse: Int, channelIndex: Int32) -> Int;
  fn iplImpulseResponseReset(impulseResponse: Int);
  fn iplImpulseResponseCopy(src: Int, dst: Int);
  fn iplImpulseResponseSwap(ir1: Int, ir2: Int);
  fn iplImpulseResponseAdd(in1: Int, in2: Int, out: Int);
  fn iplImpulseResponseScale(inBuf: Int, scalar: Float32, out: Int);
  fn iplImpulseResponseScaleAccum(inBuf: Int, scalar: Float32, out: Int);

  // ── Reconstructor ────────────────────────────────────────

  fn iplReconstructorCreate(context: Int, settings: *UInt8, reconstructor: *UInt8) -> Int32;
  fn iplReconstructorRetain(reconstructor: Int) -> Int;
  fn iplReconstructorRelease(reconstructor: *UInt8);
  fn iplReconstructorReconstruct(reconstructor: Int, numInputs: Int32, inputs: *UInt8, sharedInputs: *UInt8, outputs: *UInt8);

  // ── Probes ───────────────────────────────────────────────

  fn iplProbeArrayCreate(context: Int, probeArray: *UInt8) -> Int32;
  fn iplProbeArrayRetain(probeArray: Int) -> Int;
  fn iplProbeArrayRelease(probeArray: *UInt8);
  fn iplProbeArrayGenerateProbes(probeArray: Int, scene: Int, params: *UInt8);
  fn iplProbeArrayGetNumProbes(probeArray: Int) -> Int32;
  fn iplProbeArrayGetProbe(probeArray: Int, index: Int32) -> *UInt8;

  fn iplProbeBatchCreate(context: Int, probeBatch: *UInt8) -> Int32;
  fn iplProbeBatchRetain(probeBatch: Int) -> Int;
  fn iplProbeBatchRelease(probeBatch: *UInt8);
  fn iplProbeBatchLoad(context: Int, serializedObject: Int, probeBatch: *UInt8) -> Int32;
  fn iplProbeBatchSave(probeBatch: Int, serializedObject: Int);
  fn iplProbeBatchGetNumProbes(probeBatch: Int) -> Int32;
  fn iplProbeBatchAddProbe(probeBatch: Int, probe: *UInt8);
  fn iplProbeBatchAddProbeArray(probeBatch: Int, probeArray: Int);
  fn iplProbeBatchRemoveProbe(probeBatch: Int, index: Int32);
  fn iplProbeBatchCommit(probeBatch: Int);
  fn iplProbeBatchRemoveData(probeBatch: Int, identifier: *UInt8);
  fn iplProbeBatchGetDataSize(probeBatch: Int, identifier: *UInt8) -> Int;
  fn iplProbeBatchGetEnergyField(probeBatch: Int, identifier: *UInt8, probeIndex: Int32, energyField: Int);
  fn iplProbeBatchGetReverb(probeBatch: Int, identifier: *UInt8, probeIndex: Int32, reverbTimes: *UInt8);

  // ── Baking ───────────────────────────────────────────────

  fn iplReflectionsBakerBake(context: Int, params: *UInt8, progressCallback: Int, userData: Int);
  fn iplReflectionsBakerCancelBake(context: Int);
  fn iplPathBakerBake(context: Int, params: *UInt8, progressCallback: Int, userData: Int);
  fn iplPathBakerCancelBake(context: Int);

  // ── Real-Time Simulation ─────────────────────────────────

  fn iplSimulatorCreate(context: Int, settings: *UInt8, simulator: *UInt8) -> Int32;
  fn iplSimulatorRetain(simulator: Int) -> Int;
  fn iplSimulatorRelease(simulator: *UInt8);
  fn iplSimulatorSetScene(simulator: Int, scene: Int);
  fn iplSimulatorAddProbeBatch(simulator: Int, probeBatch: Int);
  fn iplSimulatorRemoveProbeBatch(simulator: Int, probeBatch: Int);
  fn iplSimulatorSetSharedInputs(simulator: Int, flags: Int32, sharedInputs: *UInt8);
  fn iplSimulatorCommit(simulator: Int);
  fn iplSimulatorRunDirect(simulator: Int);
  fn iplSimulatorRunReflections(simulator: Int);
  fn iplSimulatorRunPathing(simulator: Int);

  fn iplSourceCreate(simulator: Int, settings: *UInt8, source: *UInt8) -> Int32;
  fn iplSourceRetain(source: Int) -> Int;
  fn iplSourceRelease(source: *UInt8);
  fn iplSourceAdd(source: Int, simulator: Int);
  fn iplSourceRemove(source: Int, simulator: Int);
  fn iplSourceSetInputs(source: Int, flags: Int32, inputs: *UInt8);
  fn iplSourceGetOutputs(source: Int, flags: Int32, outputs: *UInt8);

  // ── Utility ──────────────────────────────────────────────

  fn iplCalculateRelativeDirection(context: Int, sourcePosition: *UInt8, listenerPosition: *UInt8, listenerAhead: *UInt8, listenerUp: *UInt8, relativeDirection: *UInt8);
  fn iplDistanceAttenuationCalculate(context: Int, source: *UInt8, listener: *UInt8, model: *UInt8) -> Float32;
  fn iplAirAbsorptionCalculate(context: Int, source: *UInt8, listener: *UInt8, model: *UInt8, airAbsorption: *UInt8);
  fn iplDirectivityCalculate(context: Int, source: *UInt8, listener: *UInt8, model: *UInt8) -> Float32;

} // extern "C"

// ═════════════════════════════════════════════════════════════
//  Safe Wrappers — Core Lifecycle
// ═════════════════════════════════════════════════════════════

pub fn error_to_string(code: Int32) -> Str {
  if code == IPL_STATUS_SUCCESS {
    return "success";
  } elif code == IPL_STATUS_FAILURE {
    return "failure";
  } elif code == IPL_STATUS_OUTOFMEMORY {
    return "out of memory";
  } elif code == IPL_STATUS_INITIALIZATION {
    return "initialization error";
  } else {
    return "unknown error";
  }
}

pub fn status_ok(code: Int32) -> Bool {
  return code == IPL_STATUS_SUCCESS;
}

pub fn context_create(settings: *UInt8) -> Result[IPLContext, Str] {
  var ctx: Int = 0;
  let ctx_ptr: *UInt8 = unsafe { &ctx as *UInt8 };
  let rc: Int32 = unsafe { iplContextCreate(settings, ctx_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(ctx);
}

pub fn context_destroy(ctx: IPLContext)
  requires: ctx != 0
{
  var c: Int = ctx;
  unsafe { iplContextRelease(&c as *UInt8); }
}

pub fn hrtf_create(context: IPLContext, audioSettings: *UInt8, hrtfSettings: *UInt8) -> Result[IPLHRTF, Str]
  requires: context != 0
{
  var hrtf: Int = 0;
  let hrtf_ptr: *UInt8 = unsafe { &hrtf as *UInt8 };
  let rc: Int32 = unsafe { iplHRTFCreate(context, audioSettings, hrtfSettings, hrtf_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(hrtf);
}

pub fn hrtf_destroy(hrtf: IPLHRTF)
  requires: hrtf != 0
{
  var h: Int = hrtf;
  unsafe { iplHRTFRelease(&h as *UInt8); }
}

pub fn binaural_effect_create(context: IPLContext, audioSettings: *UInt8, effectSettings: *UInt8) -> Result[IPLBinauralEffect, Str]
  requires: context != 0
{
  var effect: Int = 0;
  let effect_ptr: *UInt8 = unsafe { &effect as *UInt8 };
  let rc: Int32 = unsafe { iplBinauralEffectCreate(context, audioSettings, effectSettings, effect_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(effect);
}

pub fn binaural_effect_destroy(effect: IPLBinauralEffect)
  requires: effect != 0
{
  var e: Int = effect;
  unsafe { iplBinauralEffectRelease(&e as *UInt8); }
}

pub fn binaural_effect_apply(effect: IPLBinauralEffect, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
  requires: effect != 0
{
  return unsafe { iplBinauralEffectApply(effect, params, inBuf, outBuf) };
}

pub fn binaural_effect_reset(effect: IPLBinauralEffect)
  requires: effect != 0
{
  unsafe { iplBinauralEffectReset(effect); }
}

pub fn direct_effect_create(context: IPLContext, audioSettings: *UInt8, effectSettings: *UInt8) -> Result[IPLDirectEffect, Str]
  requires: context != 0
{
  var effect: Int = 0;
  let effect_ptr: *UInt8 = unsafe { &effect as *UInt8 };
  let rc: Int32 = unsafe { iplDirectEffectCreate(context, audioSettings, effectSettings, effect_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(effect);
}

pub fn direct_effect_destroy(effect: IPLDirectEffect)
  requires: effect != 0
{
  var e: Int = effect;
  unsafe { iplDirectEffectRelease(&e as *UInt8); }
}

pub fn direct_effect_apply(effect: IPLDirectEffect, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
  requires: effect != 0
{
  return unsafe { iplDirectEffectApply(effect, params, inBuf, outBuf) };
}

pub fn direct_effect_reset(effect: IPLDirectEffect)
  requires: effect != 0
{
  unsafe { iplDirectEffectReset(effect); }
}

pub fn audio_buffer_allocate(context: IPLContext, numChannels: Int32, numSamples: Int32, audioBuffer: *UInt8) -> Result[Unit, Str]
  requires: context != 0
  requires: numChannels > 0
  requires: numSamples > 0
{
  let rc: Int32 = unsafe { iplAudioBufferAllocate(context, numChannels, numSamples, audioBuffer) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(());
}

pub fn audio_buffer_free(context: IPLContext, audioBuffer: *UInt8)
  requires: context != 0
{
  unsafe { iplAudioBufferFree(context, audioBuffer); }
}

pub fn simulator_create(context: IPLContext, settings: *UInt8) -> Result[IPLSimulator, Str]
  requires: context != 0
{
  var sim: Int = 0;
  let sim_ptr: *UInt8 = unsafe { &sim as *UInt8 };
  let rc: Int32 = unsafe { iplSimulatorCreate(context, settings, sim_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(sim);
}

pub fn simulator_destroy(simulator: IPLSimulator)
  requires: simulator != 0
{
  var s: Int = simulator;
  unsafe { iplSimulatorRelease(&s as *UInt8); }
}

pub fn source_create(simulator: IPLSimulator, settings: *UInt8) -> Result[IPLSource, Str]
  requires: simulator != 0
{
  var src: Int = 0;
  let src_ptr: *UInt8 = unsafe { &src as *UInt8 };
  let rc: Int32 = unsafe { iplSourceCreate(simulator, settings, src_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(src);
}

pub fn source_destroy(source: IPLSource)
  requires: source != 0
{
  var s: Int = source;
  unsafe { iplSourceRelease(&s as *UInt8); }
}
