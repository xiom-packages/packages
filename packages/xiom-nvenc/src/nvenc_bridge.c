// xiom.nvenc -- loader-only C bridge over NVIDIA NVENC (nvEncodeAPI64.dll)
// and NVDEC/cuvid (nvcuvid.dll).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// NOTHING IS VENDORED.  The driver libraries are system components shipped
// with the NVIDIA display driver; this bridge resolves them at run time with
// LoadLibraryA/GetProcAddress.  No import library and no upstream code is
// linked into the package.
//
// The struct layouts, GUIDs and version constants below are **interface
// facts** transcribed from NVIDIA's MIT-licensed nv-codec-headers at pin
// eddcea9e27f6b772057c9b3f87de2cc1737faffc (SDK 13.1.15.1); see
// PROVENANCE.md for the oracle file hashes.  The bridge is original XIOM-side
// code: the only ABI facts it encodes are the public struct offsets asserted
// at compile time below.
//
// Discipline notes (v0.64.6 findings): all foreign memory is read/written in
// C only (B-20); handles cross the FFI as small integer slot ids, never as
// foreign pointers (B-23/B-25); copy-outs land in XIOM-owned Vec buffers; no
// allocation inside confined XIOM blocks (B-05); flat integer outcomes
// (B-26); bridge locals carry the `n_` prefix (B-10).
//
// Return convention: >= 0 is success (or a byte count where documented);
// negative values are typed loader-error classes consumed by nvenc.xi:
//   -100 nvEncodeAPI64.dll missing            -115 nvcuvid.dll missing
//   -101 nvcuda.dll missing                   -116 NVDEC codec unsupported
//   -102 required entry point missing (ABI)   -117 decoder create failed
//   -103 NVENC API version unsupported        -118 parser create/parse failed
//   -104 no CUDA device / context failed      -119 frame map failed
//   -105 no encode device / session failed    -120 frame copy failed
//   -106 codec not supported                  -121 no picture decoded
//   -107 encoder initialize failed            -122 invalid picture index
//   -108 invalid handle                       -123 internal allocation failed
//   -109 invalid state / bad argument
//   -110 resource register failed
//   -111 bitstream buffer create failed
//   -112 encode picture failed
//   -113 bitstream lock failed
//   -114 caller buffer too small

#include <windows.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NVAPI __stdcall

// ---------------------------------------------------------------------------
// Interface facts: NVENCAPI version + struct versions (nvEncodeAPI.h pin)
// ---------------------------------------------------------------------------

#define NVENC_VERSION 0x0100000Du                          // major 13, minor 1
#define NVENC_STRUCT_VER(v) \
  ((uint32_t)(NVENC_VERSION | ((uint32_t)(v) << 16) | (0x7u << 28)))
#define NV_ENCODE_API_FUNCTION_LIST_VER NVENC_STRUCT_VER(2)
#define NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER NVENC_STRUCT_VER(1)
#define NV_ENC_CAPS_PARAM_VER NVENC_STRUCT_VER(1)
#define NV_ENC_CREATE_BITSTREAM_BUFFER_VER NVENC_STRUCT_VER(1)
#define NV_ENC_REGISTER_RESOURCE_VER NVENC_STRUCT_VER(5)
#define NV_ENC_MAP_INPUT_RESOURCE_VER NVENC_STRUCT_VER(4)
#define NV_ENC_PRESET_CONFIG_VER (NVENC_STRUCT_VER(5) | (1u << 31))
#define NV_ENC_CONFIG_VER (NVENC_STRUCT_VER(9) | (1u << 31))
#define NV_ENC_INITIALIZE_PARAMS_VER (NVENC_STRUCT_VER(7) | (1u << 31))
#define NV_ENC_PIC_PARAMS_VER (NVENC_STRUCT_VER(7) | (1u << 31))
#define NV_ENC_LOCK_BITSTREAM_VER (NVENC_STRUCT_VER(2) | (1u << 31))

#define NV_ENC_DEVICE_TYPE_CUDA 1
#define NV_ENC_BUFFER_FORMAT_NV12 0x00000001
#define NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR 0x00000001
#define NV_ENC_INPUT_IMAGE 0
#define NV_ENC_PIC_STRUCT_FRAME 0x01
#define NV_ENC_PIC_TYPE_I 0x02
#define NV_ENC_PIC_TYPE_IDR 0x03
#define NV_ENC_PIC_FLAG_FORCEIDR 0x2
#define NV_ENC_TUNING_INFO_LOW_LATENCY 2

#define NV_ENC_CAPS_WIDTH_MAX 16
#define NV_ENC_CAPS_HEIGHT_MAX 17
#define NV_ENC_CAPS_NUM_ENCODER_ENGINES 49

#define NV_ENC_SUCCESS 0

typedef struct {
  uint32_t Data1;
  uint16_t Data2;
  uint16_t Data3;
  uint8_t Data4[8];
} NvGuid;

typedef struct {
  uint32_t version;
  int32_t deviceType;
  void *device;
  void *reserved;
  uint32_t apiVersion;
  uint32_t reserved1[253];
  void *reserved2[64];
} NvOpenSessionEx;

typedef struct {
  uint32_t version;
  int32_t capsToQuery;
  uint32_t reserved[62];
} NvCapsParam;

typedef struct {
  uint32_t version;
  uint32_t size;
  uint32_t memoryHeap;
  uint32_t reserved;
  void *bitstreamBuffer;
  void *bitstreamBufferPtr;
  uint32_t reserved1[58];
  void *reserved2[64];
} NvCreateBitstream;

typedef struct {
  uint32_t version;
  uint32_t resourceType;
  uint32_t width;
  uint32_t height;
  uint32_t pitch;
  uint32_t subResourceIndex;
  void *resourceToRegister;
  void *registeredResource;
  uint32_t bufferFormat;
  uint32_t bufferUsage;
  void *pInputFencePoint;
  uint32_t chromaOffset[2];
  uint32_t chromaOffsetIn[2];
  uint32_t reserved1[244];
  void *reserved2[61];
} NvRegisterResource;

typedef struct {
  uint32_t version;
  uint32_t subResourceIndex;
  void *inputResource;
  void *registeredResource;
  void *mappedResource;
  uint32_t mappedBufferFmt;
  uint32_t reserved1[251];
  void *reserved2[63];
} NvMapInput;

typedef struct {
  uint32_t version;
  NvGuid encodeGUID;
  NvGuid presetGUID;
  uint32_t encodeWidth;
  uint32_t encodeHeight;
  uint32_t darWidth;
  uint32_t darHeight;
  uint32_t frameRateNum;
  uint32_t frameRateDen;
  uint32_t enableEncodeAsync;
  uint32_t enablePTD;
  uint32_t bitfields;
  uint32_t privDataSize;
  uint32_t reserved;
  void *privData;
  void *encodeConfig;
  uint32_t maxEncodeWidth;
  uint32_t maxEncodeHeight;
  uint32_t meHintCountsPerBlock[2][4];
  uint32_t tuningInfo;
  uint32_t bufferFormat;
  uint32_t numStateBuffers;
  uint32_t outputStatsLevel;
  uint32_t reserved1[284];
  void *reserved2[64];
} NvInitializeParams;

typedef struct {
  uint32_t version;
  uint32_t inputWidth;
  uint32_t inputHeight;
  uint32_t inputPitch;
  uint32_t encodePicFlags;
  uint32_t frameIdx;
  uint64_t inputTimeStamp;
  uint64_t inputDuration;
  void *inputBuffer;
  void *outputBitstream;
  void *completionEvent;
  uint32_t bufferFmt;
  uint32_t pictureStruct;
  uint32_t pictureType;
  uint32_t codecPicParams[256];
  uint32_t meHintCountsPerBlock[2][4];
  void *meExternalHints;
  uint32_t reserved2[7];
  void *reserved5[2];
  int8_t *qpDeltaMap;
  uint32_t qpDeltaMapSize;
  uint32_t reservedBitFields;
  uint16_t meHintRefPicDist[2];
  int32_t diffPicNumHint;
  void *alphaBuffer;
  void *meExternalSbHints;
  uint32_t meSbHintsCount;
  uint32_t stateBufferIdx;
  void *outputReconBuffer;
  uint32_t reserved3[284];
  void *reserved6[57];
} NvPicParams;

typedef struct {
  uint32_t version;
  uint32_t flags;
  void *outputBitstream;
  uint32_t *sliceOffsets;
  uint32_t frameIdx;
  uint32_t hwEncodeStatus;
  uint32_t numSlices;
  uint32_t bitstreamSizeInBytes;
  uint64_t outputTimeStamp;
  uint64_t outputDuration;
  void *bitstreamBufferPtr;
  uint32_t pictureType;
  uint32_t pictureStruct;
  uint32_t frameAvgQP;
  uint32_t frameSatd;
  uint32_t ltrFrameIdx;
  uint32_t ltrFrameBitmap;
  uint32_t temporalId;
  uint32_t intraMBCount;
  uint32_t interMBCount;
  int32_t averageMVX;
  int32_t averageMVY;
  uint32_t alphaLayerSizeInBytes;
  uint32_t outputStatsPtrSize;
  uint32_t reserved;
  void *outputStatsPtr;
  uint32_t frameIdxDisplay;
  uint32_t reserved1[219];
  void *reserved2[63];
  uint32_t reservedInternal[8];
} NvLockBitstream;

typedef int(NVAPI *PFN_NvEncOpenEncodeSession)(void *, uint32_t, void **);
typedef int(NVAPI *PFN_NvEncGetEncodeGUIDCount)(void *, uint32_t *);
typedef int(NVAPI *PFN_NvEncGetEncodeGUIDs)(void *, NvGuid *, uint32_t, uint32_t *);
typedef int(NVAPI *PFN_NvEncGetEncodeCaps)(void *, NvGuid, NvCapsParam *, int *);
typedef int(NVAPI *PFN_NvEncInitializeEncoder)(void *, NvInitializeParams *);
typedef int(NVAPI *PFN_NvEncCreateBitstreamBuffer)(void *, NvCreateBitstream *);
typedef int(NVAPI *PFN_NvEncDestroyBitstreamBuffer)(void *, void *);
typedef int(NVAPI *PFN_NvEncEncodePicture)(void *, NvPicParams *);
typedef int(NVAPI *PFN_NvEncLockBitstream)(void *, NvLockBitstream *);
typedef int(NVAPI *PFN_NvEncUnlockBitstream)(void *, void *);
typedef int(NVAPI *PFN_NvEncRegisterResource)(void *, NvRegisterResource *);
typedef int(NVAPI *PFN_NvEncUnregisterResource)(void *, void *);
typedef int(NVAPI *PFN_NvEncMapInputResource)(void *, NvMapInput *);
typedef int(NVAPI *PFN_NvEncUnmapInputResource)(void *, void *);
typedef int(NVAPI *PFN_NvEncDestroyEncoder)(void *);
typedef int(NVAPI *PFN_NvEncOpenEncodeSessionEx)(NvOpenSessionEx *, void **);
typedef int(NVAPI *PFN_NvEncGetEncodePresetConfigEx)(void *, NvGuid, NvGuid, int, void *);
typedef const char *(NVAPI *PFN_NvEncGetLastErrorString)(void *);
typedef int(NVAPI *PFN_NvEncodeAPIGetMaxSupportedVersion)(uint32_t *);
typedef int(NVAPI *PFN_NvEncodeAPICreateInstance)(void *);

// Full ENCODE_FUNC order (nvEncodeAPI.h @ 4607).  Only the entries this
// package calls are typed; the rest are kept as void* so the offsets stay
// exactly the header's.
typedef struct {
  uint32_t version;
  uint32_t reserved;
  PFN_NvEncOpenEncodeSession openEncodeSession;
  PFN_NvEncGetEncodeGUIDCount getEncodeGUIDCount;
  void *getEncodeProfileGUIDCount;
  void *getEncodeProfileGUIDs;
  PFN_NvEncGetEncodeGUIDs getEncodeGUIDs;
  void *getInputFormatCount;
  void *getInputFormats;
  PFN_NvEncGetEncodeCaps getEncodeCaps;
  void *getEncodePresetCount;
  void *getEncodePresetGUIDs;
  void *getEncodePresetConfig;
  PFN_NvEncInitializeEncoder initializeEncoder;
  void *createInputBuffer;
  void *destroyInputBuffer;
  PFN_NvEncCreateBitstreamBuffer createBitstreamBuffer;
  PFN_NvEncDestroyBitstreamBuffer destroyBitstreamBuffer;
  PFN_NvEncEncodePicture encodePicture;
  PFN_NvEncLockBitstream lockBitstream;
  PFN_NvEncUnlockBitstream unlockBitstream;
  void *lockInputBuffer;
  void *unlockInputBuffer;
  void *getEncodeStats;
  void *getSequenceParams;
  void *registerAsyncEvent;
  void *unregisterAsyncEvent;
  PFN_NvEncMapInputResource mapInputResource;
  PFN_NvEncUnmapInputResource unmapInputResource;
  PFN_NvEncDestroyEncoder destroyEncoder;
  void *invalidateRefFrames;
  PFN_NvEncOpenEncodeSessionEx openEncodeSessionEx;
  PFN_NvEncRegisterResource registerResource;
  PFN_NvEncUnregisterResource unregisterResource;
  void *reconfigureEncoder;
  void *reserved1;
  void *createMVBuffer;
  void *destroyMVBuffer;
  void *runMotionEstimationOnly;
  PFN_NvEncGetLastErrorString getLastErrorString;
  void *setIOCudaStreams;
  PFN_NvEncGetEncodePresetConfigEx getEncodePresetConfigEx;
  void *getSequenceParamEx;
  void *restoreEncoderState;
  void *lookaheadPicture;
  void *reserved2[275];
} NvFnList;

// ---------------------------------------------------------------------------
// Interface facts: CUDA driver API subset (dynlink_cuda.h pin)
// ---------------------------------------------------------------------------

typedef int(NVAPI *PFN_cuInit)(unsigned int);
typedef int(NVAPI *PFN_cuCtxCreate)(void **, unsigned int, int);
typedef int(NVAPI *PFN_cuCtxDestroy)(void *);
typedef int(NVAPI *PFN_cuCtxSetCurrent)(void *);
typedef int(NVAPI *PFN_cuMemAllocPitch)(unsigned long long *, unsigned long long *,
                                        size_t, size_t, unsigned int);
typedef int(NVAPI *PFN_cuMemFree)(unsigned long long);
typedef int(NVAPI *PFN_cuMemcpyHtoD)(unsigned long long, const void *, unsigned long long);
typedef int(NVAPI *PFN_cuMemcpyDtoH)(void *, unsigned long long, unsigned long long);

// ---------------------------------------------------------------------------
// Interface facts: NVDEC/cuvid (dynlink_cuviddec.h + dynlink_nvcuvid.h pin)
// ---------------------------------------------------------------------------

#define CUDA_SUCCESS 0
#define CUDA_ERROR_NO_DEVICE 100

#define CUDA_VIDEO_CODEC_H264 4
#define CUDA_VIDEO_CODEC_HEVC 8
#define CUDA_VIDEO_CHROMA_420 1
#define CUDA_VIDEO_CREATE_PREFER_CUDA 0x01
#define CUDA_VIDEO_SURFACE_NV12 0
#define CUDA_VIDEO_DEINTERLACE_WEAVE 0
#define CUVID_PKT_ENDOFSTREAM 0x01

typedef struct {
  int codecType;
  int chromaFormat;
  unsigned int bitDepthMinus8;
  unsigned int reserved1[3];
  unsigned char isSupported;
  unsigned char numNVDECs;
  unsigned short outputFormatMask;
  unsigned int maxWidth;
  unsigned int maxHeight;
  unsigned int maxMBCount;
  unsigned short minWidth;
  unsigned short minHeight;
  unsigned char isHistogramSupported;
  unsigned char counterBitDepth;
  unsigned short maxHistogramBins;
  unsigned char isDecodeStatsSupported;
  unsigned char reserved4[3];
  unsigned int reserved3[9];
} NvDecCaps;

typedef struct {
  unsigned int width;
  unsigned int height;
  unsigned int numDecodeSurfaces;
  int codecType;
  int chromaFormat;
  unsigned int creationFlags;
  unsigned int bitDepthMinus8;
  unsigned int intraDecodeOnly;
  unsigned int maxWidth;
  unsigned int maxHeight;
  unsigned int reserved1;
  short displayLeft;
  short displayTop;
  short displayRight;
  short displayBottom;
  int outputFormat;
  int deinterlaceMode;
  unsigned int targetWidth;
  unsigned int targetHeight;
  unsigned int numOutputSurfaces;
  void *vidLock;
  short targetLeft;
  short targetTop;
  short targetRight;
  short targetBottom;
  unsigned int enableHistogram;
  unsigned int enableDecodeFeatures;
  unsigned int reserved2[3];
} NvDecCreateInfo;

typedef struct {
  int codec;
  unsigned int fpsNumerator;
  unsigned int fpsDenominator;
  unsigned char progressiveSequence;
  unsigned char bitDepthLumaMinus8;
  unsigned char bitDepthChromaMinus8;
  unsigned char minNumDecodeSurfaces;
  unsigned int codedWidth;
  unsigned int codedHeight;
  int displayLeft;
  int displayTop;
  int displayRight;
  int displayBottom;
  int chromaFormat;
  unsigned int bitrate;
  int darX;
  int darY;
  unsigned char videoSignalDescription[4];
  unsigned int seqhdrDataLength;
} NvVideoFormat;

typedef struct {
  int codecType;
  unsigned int maxNumDecodeSurfaces;
  unsigned int clockRate;
  unsigned int errorThreshold;
  unsigned int maxDisplayDelay;
  unsigned int bitfields;
  unsigned int reserved1[4];
  void *userData;
  void *sequenceCallback;
  void *decodeCallback;
  void *displayCallback;
  void *operatingPointCallback;
  void *seiMsgCallback;
  void *reserved2[5];
  void *extVideoInfo;
} NvParserParams;

typedef struct {
  unsigned int flags;
  unsigned int payloadSize;
  const unsigned char *payload;
  long long timestamp;
} NvSourcePacket;

typedef struct {
  int progressiveFrame;
  int secondField;
  int topFieldFirst;
  int unpairedField;
  unsigned int reservedFlags;
  unsigned int reservedZero;
  unsigned long long rawInputDptr;
  unsigned int rawInputPitch;
  unsigned int rawInputFormat;
  unsigned long long rawOutputDptr;
  unsigned int rawOutputPitch;
  unsigned int reserved1;
  void *outputStream;
  unsigned int reserved[46];
  unsigned long long *histogramDptr;
  void *procExt;
} NvProcParams;

typedef struct {
  int pictureIndex;
  int progressiveFrame;
  int topFieldFirst;
  int repeatFirstField;
  long long timestamp;
} NvParserDispInfo;

typedef int(NVAPI *PFN_cuvidGetDecoderCaps)(NvDecCaps *);
typedef int(NVAPI *PFN_cuvidCreateDecoder)(void **, NvDecCreateInfo *);
typedef int(NVAPI *PFN_cuvidDestroyDecoder)(void *);
typedef int(NVAPI *PFN_cuvidDecodePicture)(void *, void *);
typedef int(NVAPI *PFN_cuvidMapVideoFrame64)(void *, int, unsigned long long *,
                                             unsigned int *, NvProcParams *);
typedef int(NVAPI *PFN_cuvidUnmapVideoFrame64)(void *, unsigned long long);
typedef int(NVAPI *PFN_cuvidCreateVideoParser)(void **, NvParserParams *);
typedef int(NVAPI *PFN_cuvidParseVideoData)(void *, NvSourcePacket *);
typedef int(NVAPI *PFN_cuvidDestroyVideoParser)(void *);
typedef int(NVAPI *PFN_cuvidCtxLockCreate)(void **, void *);
typedef int(NVAPI *PFN_cuvidCtxLockDestroy)(void *);

// ---------------------------------------------------------------------------
// Layout assertions (the header is the oracle; see PROVENANCE.md)
// ---------------------------------------------------------------------------

_Static_assert(sizeof(NvGuid) == 16, "GUID layout");
_Static_assert(sizeof(NvOpenSessionEx) == 1552, "NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS");
_Static_assert(offsetof(NvOpenSessionEx, apiVersion) == 24, "open session apiVersion");
_Static_assert(sizeof(NvCapsParam) == 256, "NV_ENC_CAPS_PARAM");
_Static_assert(sizeof(NvCreateBitstream) == 776, "NV_ENC_CREATE_BITSTREAM_BUFFER");
_Static_assert(sizeof(NvRegisterResource) == 1536, "NV_ENC_REGISTER_RESOURCE");
_Static_assert(offsetof(NvRegisterResource, registeredResource) == 32, "registeredResource");
_Static_assert(sizeof(NvMapInput) == 1544, "NV_ENC_MAP_INPUT_RESOURCE");
_Static_assert(offsetof(NvMapInput, mappedResource) == 24, "mappedResource");
_Static_assert(sizeof(NvInitializeParams) == 1800, "NV_ENC_INITIALIZE_PARAMS");
_Static_assert(offsetof(NvInitializeParams, encodeConfig) == 88, "initialize encodeConfig");
_Static_assert(offsetof(NvInitializeParams, tuningInfo) == 136, "initialize tuningInfo");
_Static_assert(sizeof(NvPicParams) == 2840, "NV_ENC_PIC_PARAMS");
_Static_assert(offsetof(NvPicParams, inputBuffer) == 40, "pic inputBuffer");
_Static_assert(offsetof(NvPicParams, outputBitstream) == 48, "pic outputBitstream");
_Static_assert(offsetof(NvPicParams, bufferFmt) == 64, "pic bufferFmt");
_Static_assert(sizeof(NvLockBitstream) == 1544, "NV_ENC_LOCK_BITSTREAM");
_Static_assert(offsetof(NvLockBitstream, bitstreamSizeInBytes) == 36, "lock size");
_Static_assert(offsetof(NvLockBitstream, bitstreamBufferPtr) == 56, "lock ptr");
_Static_assert(sizeof(NvFnList) == 2552, "NV_ENCODE_API_FUNCTION_LIST");
_Static_assert(sizeof(NvDecCaps) == 88, "CUVIDDECODECAPS");
_Static_assert(sizeof(NvDecCreateInfo) == 112, "CUVIDDECODECREATEINFO (108 + tail pad)");
_Static_assert(offsetof(NvDecCreateInfo, vidLock) == 72, "decode vidLock");
_Static_assert(sizeof(NvVideoFormat) == 64, "CUVIDEOFORMAT");
_Static_assert(offsetof(NvVideoFormat, codedWidth) == 16, "format codedWidth");
_Static_assert(offsetof(NvVideoFormat, chromaFormat) == 40, "format chromaFormat");
_Static_assert(sizeof(NvParserParams) == 136, "CUVIDPARSERPARAMS");
_Static_assert(offsetof(NvParserParams, sequenceCallback) == 48, "parser callbacks");
_Static_assert(sizeof(NvSourcePacket) == 24, "CUVIDSOURCEDATAPACKET");
_Static_assert(sizeof(NvProcParams) == 264, "CUVIDPROCPARAMS");
_Static_assert(offsetof(NvProcParams, outputStream) == 56, "proc outputStream");
_Static_assert(sizeof(NvParserDispInfo) == 24, "CUVIDPARSERDISPINFO");

// ---------------------------------------------------------------------------
// GUIDs (nvEncodeAPI.h @ 144-251 pin)
// ---------------------------------------------------------------------------

static const NvGuid GUID_H264 = {0x6bc82762, 0x4e63, 0x4ca4,
                                 {0xaa, 0x85, 0x1e, 0x50, 0xf3, 0x21, 0xf6, 0xbf}};
static const NvGuid GUID_HEVC = {0x790cdc88, 0x4522, 0x4d7b,
                                 {0x94, 0x25, 0xbd, 0xa9, 0x97, 0x5f, 0x76, 0x03}};
static const NvGuid GUID_PRESET_P1 = {0xfc0a8d3e, 0x45f8, 0x4cf8,
                                      {0x80, 0xc7, 0x29, 0x88, 0x71, 0x59, 0x0e, 0xbf}};
static const NvGuid GUID_PRESET_P2 = {0xf581cfb8, 0x88d6, 0x4381,
                                      {0x93, 0xf0, 0xdf, 0x13, 0xf9, 0xc2, 0x7d, 0xab}};
static const NvGuid GUID_PRESET_P3 = {0x36850110, 0x3a07, 0x441f,
                                      {0x94, 0xd5, 0x36, 0x70, 0x63, 0x1f, 0x91, 0xf6}};
static const NvGuid GUID_PRESET_P4 = {0x90a7b826, 0xdf06, 0x4862,
                                      {0xb9, 0xd2, 0xcd, 0x6d, 0x73, 0xa0, 0x86, 0x81}};
static const NvGuid GUID_PRESET_P5 = {0x21c6e6b4, 0x297a, 0x4cba,
                                      {0x99, 0x8f, 0xb6, 0xcb, 0xde, 0x72, 0xad, 0xe3}};
static const NvGuid GUID_PRESET_P6 = {0x8e75c279, 0x6299, 0x4ab6,
                                      {0x83, 0x02, 0x0b, 0x21, 0x5a, 0x33, 0x5c, 0xf5}};
static const NvGuid GUID_PRESET_P7 = {0x84848c12, 0x6f71, 0x4c13,
                                      {0x93, 0x1b, 0x53, 0xe2, 0x83, 0xf5, 0x79, 0x74}};

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

#define NV_PRESET_BUF_SIZE 65536u
#define NV_MAX_ENCODERS 4
#define NV_MAX_DECODERS 4

static char g_err_text[512];
static int g_err_stage;
static int g_err_code;

static const char *nv_stage_name(int stage) {
  switch (stage) {
    case 0: return "load";
    case 1: return "version";
    case 2: return "device";
    case 3: return "session";
    case 4: return "caps";
    case 5: return "initialize";
    case 6: return "resource";
    case 7: return "bitstream";
    case 8: return "encode";
    case 9: return "lock";
    case 10: return "decode-probe";
    case 11: return "decoder";
    case 12: return "parser";
    case 13: return "map";
    case 14: return "copy";
    default: return "state";
  }
}

static int nv_fail(int high_level, int stage, int code, const char *text) {
  g_err_stage = stage;
  g_err_code = code;
  snprintf(g_err_text, sizeof(g_err_text), "%s: %s (code=%d)",
           nv_stage_name(stage), text != NULL ? text : "failed", code);
  return -high_level;
}

static int nv_failf(int high_level, int stage, int code, const char *fmt, int value) {
  char n_buf[256];
  snprintf(n_buf, sizeof(n_buf), fmt, value);
  return nv_fail(high_level, stage, code, n_buf);
}

const char *nvb_nv_last_error_text(void) { return g_err_text; }
int nvb_nv_last_error_stage(void) { return g_err_stage; }
int nvb_nv_last_error_code(void) { return g_err_code; }

// ---------------------------------------------------------------------------
// CUDA driver subset
// ---------------------------------------------------------------------------

typedef struct {
  HMODULE mod;
  PFN_cuInit init;
  PFN_cuCtxCreate ctx_create;
  PFN_cuCtxDestroy ctx_destroy;
  PFN_cuCtxSetCurrent ctx_set_current;
  PFN_cuMemAllocPitch mem_alloc_pitch;
  PFN_cuMemFree mem_free;
  PFN_cuMemcpyHtoD htod;
  PFN_cuMemcpyDtoH dtoh;
} NvCudaApi;

static NvCudaApi g_cuda;

static int nv_cuda_load(void) {
  if (g_cuda.mod != NULL) return 0;
  HMODULE n_mod = LoadLibraryA("nvcuda.dll");
  if (n_mod == NULL) {
    return nv_fail(101, 0, (int)GetLastError(), "nvcuda.dll not found");
  }
  memset(&g_cuda, 0, sizeof(g_cuda));
  g_cuda.mod = n_mod;
  g_cuda.init = (PFN_cuInit)(void *)GetProcAddress(n_mod, "cuInit");
  g_cuda.ctx_create = (PFN_cuCtxCreate)(void *)GetProcAddress(n_mod, "cuCtxCreate_v2");
  g_cuda.ctx_destroy = (PFN_cuCtxDestroy)(void *)GetProcAddress(n_mod, "cuCtxDestroy_v2");
  g_cuda.ctx_set_current = (PFN_cuCtxSetCurrent)(void *)GetProcAddress(n_mod, "cuCtxSetCurrent");
  g_cuda.mem_alloc_pitch =
      (PFN_cuMemAllocPitch)(void *)GetProcAddress(n_mod, "cuMemAllocPitch_v2");
  g_cuda.mem_free = (PFN_cuMemFree)(void *)GetProcAddress(n_mod, "cuMemFree_v2");
  g_cuda.htod = (PFN_cuMemcpyHtoD)(void *)GetProcAddress(n_mod, "cuMemcpyHtoD_v2");
  g_cuda.dtoh = (PFN_cuMemcpyDtoH)(void *)GetProcAddress(n_mod, "cuMemcpyDtoH_v2");
  if (g_cuda.init == NULL || g_cuda.ctx_create == NULL || g_cuda.ctx_destroy == NULL ||
      g_cuda.mem_alloc_pitch == NULL || g_cuda.mem_free == NULL ||
      g_cuda.htod == NULL || g_cuda.dtoh == NULL) {
    return nv_fail(102, 0, 0, "nvcuda.dll entry points missing");
  }
  return 0;
}

static int nv_cuda_ctx_create(void **ctx) {
  int n_rc = nv_cuda_load();
  if (n_rc != 0) return n_rc;
  int n_cu = g_cuda.init(0);
  if (n_cu == CUDA_ERROR_NO_DEVICE) {
    return nv_fail(104, 2, n_cu, "no CUDA device");
  }
  if (n_cu != CUDA_SUCCESS) {
    return nv_failf(104, 2, n_cu, "cuInit failed (%d)", n_cu);
  }
  n_cu = g_cuda.ctx_create(ctx, 0, 0);
  if (n_cu != CUDA_SUCCESS || *ctx == NULL) {
    return nv_failf(104, 2, n_cu, "cuCtxCreate failed (%d)", n_cu);
  }
  return 0;
}

static void nv_cuda_ctx_destroy(void *ctx) {
  if (ctx != NULL && g_cuda.ctx_destroy != NULL) {
    g_cuda.ctx_destroy(ctx);
  }
}

static void nv_cuda_set_current(void *ctx) {
  if (ctx != NULL && g_cuda.ctx_set_current != NULL) {
    g_cuda.ctx_set_current(ctx);
  }
}

// ---------------------------------------------------------------------------
// NVENC loader
// ---------------------------------------------------------------------------

typedef struct {
  HMODULE mod;
  uint32_t max_version;
  PFN_NvEncodeAPIGetMaxSupportedVersion get_max;
  PFN_NvEncodeAPICreateInstance create_instance;
  NvFnList fn;
} NvEncApi;

static int nv_enc_load_api(NvEncApi *api, const char *dll_name) {
  memset(api, 0, sizeof(*api));
  HMODULE n_mod = LoadLibraryA(dll_name);
  if (n_mod == NULL) {
    return nv_fail(100, 0, (int)GetLastError(), "nvEncodeAPI64.dll not found");
  }
  api->mod = n_mod;
  api->get_max = (PFN_NvEncodeAPIGetMaxSupportedVersion)(void *)GetProcAddress(
      n_mod, "NvEncodeAPIGetMaxSupportedVersion");
  api->create_instance =
      (PFN_NvEncodeAPICreateInstance)(void *)GetProcAddress(n_mod, "NvEncodeAPICreateInstance");
  if (api->get_max == NULL || api->create_instance == NULL) {
    return nv_fail(102, 0, 0, "NvEncodeAPIGetMaxSupportedVersion/CreateInstance missing");
  }
  uint32_t n_max = 0;
  int n_st = api->get_max(&n_max);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(103, 1, n_st, "GetMaxSupportedVersion failed (%d)", n_st);
  }
  api->max_version = n_max;
  uint32_t n_major = (n_max >> 4) & 0x0F;
  uint32_t n_minor = n_max & 0x0F;
  if (n_major < 13 || (n_major == 13 && n_minor < 1)) {
    char n_vermsg[128];
    snprintf(n_vermsg, sizeof(n_vermsg),
             "driver NVENC API %d.%d older than the 13.1 header pin", (int)n_major,
             (int)n_minor);
    return nv_fail(103, 1, (int)n_max, n_vermsg);
  }
  api->fn.version = NV_ENCODE_API_FUNCTION_LIST_VER;
  n_st = api->create_instance(&api->fn);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(103, 1, n_st, "NvEncodeAPICreateInstance failed (%d)", n_st);
  }
  if (api->fn.openEncodeSessionEx == NULL || api->fn.getEncodeGUIDCount == NULL ||
      api->fn.getEncodeGUIDs == NULL || api->fn.getEncodeCaps == NULL ||
      api->fn.initializeEncoder == NULL || api->fn.createBitstreamBuffer == NULL ||
      api->fn.destroyBitstreamBuffer == NULL || api->fn.encodePicture == NULL ||
      api->fn.lockBitstream == NULL || api->fn.unlockBitstream == NULL ||
      api->fn.registerResource == NULL || api->fn.unregisterResource == NULL ||
      api->fn.mapInputResource == NULL || api->fn.unmapInputResource == NULL ||
      api->fn.destroyEncoder == NULL || api->fn.getEncodePresetConfigEx == NULL) {
    return nv_fail(102, 0, 0, "NVENC function list entry points missing");
  }
  return 0;
}

static const NvGuid *nv_codec_guid(int codec) {
  if (codec == 0) return &GUID_H264;
  if (codec == 1) return &GUID_HEVC;
  return NULL;
}

static const NvGuid *nv_preset_guid(int preset) {
  switch (preset) {
    case 1: return &GUID_PRESET_P1;
    case 2: return &GUID_PRESET_P2;
    case 3: return &GUID_PRESET_P3;
    case 4: return &GUID_PRESET_P4;
    case 5: return &GUID_PRESET_P5;
    case 6: return &GUID_PRESET_P6;
    case 7: return &GUID_PRESET_P7;
    default: return NULL;
  }
}

// Probe result getters (written by nvenc_probe_run).
static int g_probe_api_major;
static int g_probe_api_minor;
static int g_probe_guid_count;
static int g_probe_h264;
static int g_probe_hevc;
static int g_probe_width_max;
static int g_probe_height_max;
static int g_probe_num_engines;

int nvb_nvenc_probe_api_major(void) { return g_probe_api_major; }
int nvb_nvenc_probe_api_minor(void) { return g_probe_api_minor; }
int nvb_nvenc_probe_guid_count(void) { return g_probe_guid_count; }
int nvb_nvenc_probe_h264(void) { return g_probe_h264; }
int nvb_nvenc_probe_hevc(void) { return g_probe_hevc; }
int nvb_nvenc_probe_width_max(void) { return g_probe_width_max; }
int nvb_nvenc_probe_height_max(void) { return g_probe_height_max; }
int nvb_nvenc_probe_num_engines(void) { return g_probe_num_engines; }

int nvb_nvenc_probe_run(const char *dll_name) {
  NvEncApi n_api;
  void *n_ctx = NULL;
  void *n_enc = NULL;
  int n_rc = 0;
  g_probe_api_major = 0;
  g_probe_api_minor = 0;
  g_probe_guid_count = 0;
  g_probe_h264 = 0;
  g_probe_hevc = 0;
  g_probe_width_max = 0;
  g_probe_height_max = 0;
  g_probe_num_engines = 0;

  n_rc = nv_enc_load_api(&n_api, dll_name != NULL ? dll_name : "nvEncodeAPI64.dll");
  if (n_rc != 0) goto done;

  n_rc = nv_cuda_ctx_create(&n_ctx);
  if (n_rc != 0) goto done;

  NvOpenSessionEx n_ose;
  memset(&n_ose, 0, sizeof(n_ose));
  n_ose.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
  n_ose.deviceType = NV_ENC_DEVICE_TYPE_CUDA;
  n_ose.device = n_ctx;
  n_ose.apiVersion = NVENC_VERSION;
  int n_st = n_api.fn.openEncodeSessionEx(&n_ose, &n_enc);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 3, n_st, "NvEncOpenEncodeSessionEx failed (%d)", n_st);
    goto done;
  }

  uint32_t n_count = 0;
  n_st = n_api.fn.getEncodeGUIDCount(n_enc, &n_count);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 4, n_st, "NvEncGetEncodeGUIDCount failed (%d)", n_st);
    goto done;
  }
  NvGuid n_guids[16];
  uint32_t n_got = 0;
  memset(n_guids, 0, sizeof(n_guids));
  n_st = n_api.fn.getEncodeGUIDs(n_enc, n_guids, 16, &n_got);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 4, n_st, "NvEncGetEncodeGUIDs failed (%d)", n_st);
    goto done;
  }
  int n_h264 = 0;
  int n_hevc = 0;
  for (uint32_t n_i = 0; n_i < n_got && n_i < 16; n_i++) {
    if (memcmp(&n_guids[n_i], &GUID_H264, sizeof(NvGuid)) == 0) n_h264 = 1;
    if (memcmp(&n_guids[n_i], &GUID_HEVC, sizeof(NvGuid)) == 0) n_hevc = 1;
  }
  if (!n_h264 && !n_hevc) {
    n_rc = nv_fail(106, 4, 0, "no H.264/HEVC encode support");
    goto done;
  }

  const NvGuid *n_use = n_h264 ? &GUID_H264 : &GUID_HEVC;
  NvCapsParam n_cp;
  int n_val = 0;
  memset(&n_cp, 0, sizeof(n_cp));
  n_cp.version = NV_ENC_CAPS_PARAM_VER;
  n_cp.capsToQuery = NV_ENC_CAPS_WIDTH_MAX;
  n_st = n_api.fn.getEncodeCaps(n_enc, *n_use, &n_cp, &n_val);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 4, n_st, "caps width query failed (%d)", n_st);
    goto done;
  }
  int n_wmax = n_val;
  n_cp.capsToQuery = NV_ENC_CAPS_HEIGHT_MAX;
  n_st = n_api.fn.getEncodeCaps(n_enc, *n_use, &n_cp, &n_val);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 4, n_st, "caps height query failed (%d)", n_st);
    goto done;
  }
  int n_hmax = n_val;
  n_cp.capsToQuery = NV_ENC_CAPS_NUM_ENCODER_ENGINES;
  n_st = n_api.fn.getEncodeCaps(n_enc, *n_use, &n_cp, &n_val);
  if (n_st != NV_ENC_SUCCESS) {
    n_rc = nv_failf(105, 4, n_st, "caps engine query failed (%d)", n_st);
    goto done;
  }

  g_probe_api_major = (int)((n_api.max_version >> 4) & 0x0F);
  g_probe_api_minor = (int)(n_api.max_version & 0x0F);
  g_probe_guid_count = (int)n_got;
  g_probe_h264 = n_h264;
  g_probe_hevc = n_hevc;
  g_probe_width_max = n_wmax;
  g_probe_height_max = n_hmax;
  g_probe_num_engines = n_val;

done:
  if (n_enc != NULL && n_api.fn.destroyEncoder != NULL) {
    n_api.fn.destroyEncoder(n_enc);
  }
  nv_cuda_ctx_destroy(n_ctx);
  if (n_api.mod != NULL) FreeLibrary(n_api.mod);
  return n_rc;
}

// ---------------------------------------------------------------------------
// NVENC sessions
// ---------------------------------------------------------------------------

typedef union {
  struct {
    uint32_t version;
    uint32_t reserved;
  } head;
  unsigned char raw[NV_PRESET_BUF_SIZE];
  uint64_t align;
} NvPresetBuffer;

typedef struct {
  int in_use;
  void *enc;
  void *cu_ctx;
  uint32_t width;
  uint32_t height;
  uint32_t frame_count;
  int codec;
  int preset;
  int initialized;
  int mapped;
  void *mapped_input;
  void *registered;
  unsigned long long devptr;
  size_t pitch;
  void *bitstream;
  void *locked_ptr;
  uint32_t locked_size;
  int locked;
  int locked_picture_type;
  long long locked_timestamp;
  NvPresetBuffer *preset_buf;
} NvEncSession;

static NvEncSession g_encoders[NV_MAX_ENCODERS];
static NvEncApi g_enc;
static int g_enc_loaded;

static NvEncSession *nv_enc_slot(int handle) {
  if (handle < 1 || handle > NV_MAX_ENCODERS) return NULL;
  NvEncSession *n_s = &g_encoders[handle - 1];
  if (!n_s->in_use) return NULL;
  return n_s;
}

static int nv_enc_ensure_loaded(void) {
  if (g_enc_loaded) return 0;
  int n_rc = nv_enc_load_api(&g_enc, "nvEncodeAPI64.dll");
  if (n_rc != 0) return n_rc;
  g_enc_loaded = 1;
  return 0;
}

int nvb_nvenc_open_session(int codec) {
  const NvGuid *n_codec = nv_codec_guid(codec);
  if (n_codec == NULL) return nv_fail(109, 3, codec, "unknown codec id");
  int n_rc = nv_enc_ensure_loaded();
  if (n_rc != 0) return n_rc;

  int n_slot = -1;
  for (int n_i = 0; n_i < NV_MAX_ENCODERS; n_i++) {
    if (!g_encoders[n_i].in_use) {
      n_slot = n_i;
      break;
    }
  }
  if (n_slot < 0) return nv_fail(109, 3, 0, "encoder session slots exhausted");

  void *n_ctx = NULL;
  n_rc = nv_cuda_ctx_create(&n_ctx);
  if (n_rc != 0) return n_rc;

  void *n_enc = NULL;
  NvOpenSessionEx n_ose;
  memset(&n_ose, 0, sizeof(n_ose));
  n_ose.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
  n_ose.deviceType = NV_ENC_DEVICE_TYPE_CUDA;
  n_ose.device = n_ctx;
  n_ose.apiVersion = NVENC_VERSION;
  int n_st = g_enc.fn.openEncodeSessionEx(&n_ose, &n_enc);
  if (n_st != NV_ENC_SUCCESS) {
    nv_cuda_ctx_destroy(n_ctx);
    return nv_failf(105, 3, n_st, "NvEncOpenEncodeSessionEx failed (%d)", n_st);
  }

  uint32_t n_gcount = 0;
  n_st = g_enc.fn.getEncodeGUIDCount(n_enc, &n_gcount);
  if (n_st != NV_ENC_SUCCESS) {
    g_enc.fn.destroyEncoder(n_enc);
    nv_cuda_ctx_destroy(n_ctx);
    return nv_failf(105, 4, n_st, "NvEncGetEncodeGUIDCount failed (%d)", n_st);
  }
  NvGuid n_guids[16];
  uint32_t n_got = 0;
  memset(n_guids, 0, sizeof(n_guids));
  n_st = g_enc.fn.getEncodeGUIDs(n_enc, n_guids, 16, &n_got);
  if (n_st != NV_ENC_SUCCESS) {
    g_enc.fn.destroyEncoder(n_enc);
    nv_cuda_ctx_destroy(n_ctx);
    return nv_failf(105, 4, n_st, "NvEncGetEncodeGUIDs failed (%d)", n_st);
  }
  int n_supported = 0;
  for (uint32_t n_i = 0; n_i < n_got && n_i < 16; n_i++) {
    if (memcmp(&n_guids[n_i], n_codec, sizeof(NvGuid)) == 0) n_supported = 1;
  }
  if (!n_supported) {
    g_enc.fn.destroyEncoder(n_enc);
    nv_cuda_ctx_destroy(n_ctx);
    return nv_fail(106, 4, codec, "requested codec not supported by this GPU");
  }

  NvPresetBuffer *n_preset = (NvPresetBuffer *)calloc(1, sizeof(NvPresetBuffer));
  if (n_preset == NULL) {
    g_enc.fn.destroyEncoder(n_enc);
    nv_cuda_ctx_destroy(n_ctx);
    return nv_fail(123, 3, 0, "preset buffer allocation failed");
  }

  NvEncSession *n_s = &g_encoders[n_slot];
  memset(n_s, 0, sizeof(*n_s));
  n_s->in_use = 1;
  n_s->enc = n_enc;
  n_s->cu_ctx = n_ctx;
  n_s->codec = codec;
  n_s->preset_buf = n_preset;
  nv_cuda_set_current(n_ctx);
  return n_slot + 1;
}

int nvb_nvenc_initialize(int handle, int width, int height, int fps_num, int fps_den,
                     int preset) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 5, handle, "invalid encoder handle");
  if (n_s->initialized) return nv_fail(109, 5, 0, "session already initialized");
  const NvGuid *n_codec = nv_codec_guid(n_s->codec);
  const NvGuid *n_preset = nv_preset_guid(preset);
  if (n_codec == NULL || n_preset == NULL) return nv_fail(109, 5, preset, "unknown preset id");
  if (width < 16 || height < 16 || width > 8192 || height > 8192) {
    return nv_fail(109, 5, 0, "unsupported dimensions");
  }
  if (fps_num <= 0 || fps_den <= 0) return nv_fail(109, 5, 0, "invalid frame rate");

  nv_cuda_set_current(n_s->cu_ctx);
  n_s->preset_buf->head.version = NV_ENC_PRESET_CONFIG_VER;
  n_s->preset_buf->head.reserved = 0;
  *(uint32_t *)(n_s->preset_buf->raw + 8) = NV_ENC_CONFIG_VER;
  int n_st = g_enc.fn.getEncodePresetConfigEx(n_s->enc, *n_codec, *n_preset,
                                              NV_ENC_TUNING_INFO_LOW_LATENCY,
                                              (void *)n_s->preset_buf->raw);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(107, 5, n_st, "NvEncGetEncodePresetConfigEx failed (%d)", n_st);
  }

  NvInitializeParams n_ip;
  memset(&n_ip, 0, sizeof(n_ip));
  n_ip.version = NV_ENC_INITIALIZE_PARAMS_VER;
  n_ip.encodeGUID = *n_codec;
  n_ip.presetGUID = *n_preset;
  n_ip.encodeWidth = (uint32_t)width;
  n_ip.encodeHeight = (uint32_t)height;
  n_ip.darWidth = (uint32_t)width;
  n_ip.darHeight = (uint32_t)height;
  n_ip.frameRateNum = (uint32_t)fps_num;
  n_ip.frameRateDen = (uint32_t)fps_den;
  n_ip.enableEncodeAsync = 0;
  n_ip.enablePTD = 1;
  n_ip.encodeConfig = (void *)(n_s->preset_buf->raw + 8);
  n_ip.maxEncodeWidth = (uint32_t)width;
  n_ip.maxEncodeHeight = (uint32_t)height;
  n_ip.tuningInfo = NV_ENC_TUNING_INFO_LOW_LATENCY;
  n_ip.bufferFormat = NV_ENC_BUFFER_FORMAT_NV12;
  n_st = g_enc.fn.initializeEncoder(n_s->enc, &n_ip);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(107, 5, n_st, "NvEncInitializeEncoder failed (%d)", n_st);
  }
  n_s->width = (uint32_t)width;
  n_s->height = (uint32_t)height;
  n_s->preset = preset;
  n_s->initialized = 1;
  return 0;
}

int nvb_nvenc_register_resource(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 6, handle, "invalid encoder handle");
  if (!n_s->initialized) return nv_fail(109, 6, 0, "encoder not initialized");
  if (n_s->registered != NULL) return nv_fail(109, 6, 0, "resource already registered");

  nv_cuda_set_current(n_s->cu_ctx);
  unsigned long long n_devptr = 0;
  unsigned long long n_pitch = 0;
  int n_cu = g_cuda.mem_alloc_pitch(&n_devptr, &n_pitch, (size_t)n_s->width,
                                    (size_t)n_s->height * 3 / 2, 16);
  if (n_cu != CUDA_SUCCESS || n_devptr == 0 || n_pitch == 0) {
    return nv_failf(110, 6, n_cu, "cuMemAllocPitch failed (%d)", n_cu);
  }

  NvRegisterResource n_rr;
  memset(&n_rr, 0, sizeof(n_rr));
  n_rr.version = NV_ENC_REGISTER_RESOURCE_VER;
  n_rr.resourceType = NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR;
  n_rr.width = n_s->width;
  n_rr.height = n_s->height;
  n_rr.pitch = (uint32_t)n_pitch;
  n_rr.resourceToRegister = (void *)(uintptr_t)n_devptr;
  n_rr.bufferFormat = NV_ENC_BUFFER_FORMAT_NV12;
  n_rr.bufferUsage = NV_ENC_INPUT_IMAGE;
  int n_st = g_enc.fn.registerResource(n_s->enc, &n_rr);
  if (n_st != NV_ENC_SUCCESS) {
    g_cuda.mem_free(n_devptr);
    return nv_failf(110, 6, n_st, "NvEncRegisterResource failed (%d)", n_st);
  }
  n_s->devptr = n_devptr;
  n_s->pitch = (size_t)n_pitch;
  n_s->registered = n_rr.registeredResource;
  return 0;
}

int nvb_nvenc_fill_frame(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 6, handle, "invalid encoder handle");
  if (n_s->registered == NULL) return nv_fail(109, 6, 0, "resource not registered");

  size_t n_ysize = n_s->pitch * (size_t)n_s->height;
  size_t n_uvsize = n_s->pitch * (size_t)(n_s->height / 2);
  unsigned char *n_y = (unsigned char *)malloc(n_ysize);
  unsigned char *n_uv = (unsigned char *)malloc(n_uvsize);
  if (n_y == NULL || n_uv == NULL) {
    free(n_y);
    free(n_uv);
    return nv_fail(123, 6, 0, "frame staging allocation failed");
  }
  for (uint32_t n_row = 0; n_row < n_s->height; n_row++) {
    unsigned char *n_dst = n_y + (size_t)n_row * n_s->pitch;
    for (uint32_t n_col = 0; n_col < n_s->width; n_col++) {
      n_dst[n_col] = (unsigned char)((n_row + n_col) & 0xFF);
    }
  }
  memset(n_uv, 96, n_uvsize);

  nv_cuda_set_current(n_s->cu_ctx);
  int n_cu = g_cuda.htod(n_s->devptr, n_y, (unsigned long long)n_ysize);
  if (n_cu == CUDA_SUCCESS) {
    n_cu = g_cuda.htod(n_s->devptr + n_ysize, n_uv, (unsigned long long)n_uvsize);
  }
  free(n_y);
  free(n_uv);
  if (n_cu != CUDA_SUCCESS) {
    return nv_failf(110, 6, n_cu, "cuMemcpyHtoD failed (%d)", n_cu);
  }
  return 0;
}

int nvb_nvenc_create_bitstream(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 7, handle, "invalid encoder handle");
  if (!n_s->initialized) return nv_fail(109, 7, 0, "encoder not initialized");
  if (n_s->bitstream != NULL) return nv_fail(109, 7, 0, "bitstream buffer already exists");
  NvCreateBitstream n_bs;
  memset(&n_bs, 0, sizeof(n_bs));
  n_bs.version = NV_ENC_CREATE_BITSTREAM_BUFFER_VER;
  int n_st = g_enc.fn.createBitstreamBuffer(n_s->enc, &n_bs);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(111, 7, n_st, "NvEncCreateBitstreamBuffer failed (%d)", n_st);
  }
  n_s->bitstream = n_bs.bitstreamBuffer;
  return 0;
}

int nvb_nvenc_encode_frame(int handle, int force_idr) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 8, handle, "invalid encoder handle");
  if (!n_s->initialized || n_s->registered == NULL || n_s->bitstream == NULL) {
    return nv_fail(109, 8, 0, "encoder/bitstream not ready");
  }
  if (!n_s->mapped) {
    NvMapInput n_map;
    memset(&n_map, 0, sizeof(n_map));
    n_map.version = NV_ENC_MAP_INPUT_RESOURCE_VER;
    n_map.registeredResource = n_s->registered;
    int n_st = g_enc.fn.mapInputResource(n_s->enc, &n_map);
    if (n_st != NV_ENC_SUCCESS) {
      return nv_failf(112, 8, n_st, "NvEncMapInputResource failed (%d)", n_st);
    }
    n_s->mapped_input = n_map.mappedResource;
    n_s->mapped = 1;
  }

  NvPicParams n_pic;
  memset(&n_pic, 0, sizeof(n_pic));
  n_pic.version = NV_ENC_PIC_PARAMS_VER;
  n_pic.inputWidth = n_s->width;
  n_pic.inputHeight = n_s->height;
  n_pic.inputPitch = (uint32_t)n_s->pitch;
  n_pic.encodePicFlags = force_idr ? NV_ENC_PIC_FLAG_FORCEIDR : 0;
  n_pic.frameIdx = n_s->frame_count;
  n_pic.inputTimeStamp = (uint64_t)n_s->frame_count;
  n_pic.inputDuration = 1;
  n_pic.inputBuffer = n_s->mapped_input;
  n_pic.outputBitstream = n_s->bitstream;
  n_pic.bufferFmt = NV_ENC_BUFFER_FORMAT_NV12;
  n_pic.pictureStruct = NV_ENC_PIC_STRUCT_FRAME;
  n_pic.pictureType = force_idr ? NV_ENC_PIC_TYPE_IDR : NV_ENC_PIC_TYPE_I;
  int n_st = g_enc.fn.encodePicture(n_s->enc, &n_pic);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(112, 8, n_st, "NvEncEncodePicture failed (%d)", n_st);
  }
  n_s->frame_count++;
  return 0;
}

int nvb_nvenc_lock_bitstream(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 9, handle, "invalid encoder handle");
  if (n_s->bitstream == NULL) return nv_fail(109, 9, 0, "bitstream buffer missing");
  if (n_s->locked) return nv_fail(109, 9, 0, "bitstream already locked");
  NvLockBitstream n_lock;
  memset(&n_lock, 0, sizeof(n_lock));
  n_lock.version = NV_ENC_LOCK_BITSTREAM_VER;
  n_lock.outputBitstream = n_s->bitstream;
  int n_st = g_enc.fn.lockBitstream(n_s->enc, &n_lock);
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(113, 9, n_st, "NvEncLockBitstream failed (%d)", n_st);
  }
  if (n_lock.bitstreamSizeInBytes == 0 || n_lock.bitstreamBufferPtr == NULL) {
    g_enc.fn.unlockBitstream(n_s->enc, n_s->bitstream);
    return nv_fail(121, 9, 17, "bitstream empty (encoder needs more input)");
  }
  n_s->locked = 1;
  n_s->locked_ptr = n_lock.bitstreamBufferPtr;
  n_s->locked_size = n_lock.bitstreamSizeInBytes;
  n_s->locked_picture_type = (int)n_lock.pictureType;
  n_s->locked_timestamp = (long long)n_lock.outputTimeStamp;
  return 0;
}

int nvb_nvenc_locked_size(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  return n_s == NULL ? -1 : (int)n_s->locked_size;
}

int nvb_nvenc_locked_picture_type(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  return n_s == NULL ? -1 : n_s->locked_picture_type;
}

int nvb_nvenc_copy_bitstream(int handle, unsigned char *out, int capacity) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 9, handle, "invalid encoder handle");
  if (!n_s->locked) return nv_fail(109, 9, 0, "bitstream not locked");
  if (out == NULL || capacity < 0) return nv_fail(109, 9, 0, "invalid output buffer");
  if ((uint32_t)capacity < n_s->locked_size) {
    return nv_failf(114, 9, (int)n_s->locked_size,
                    "output buffer too small: need %d bytes", (int)n_s->locked_size);
  }
  memcpy(out, n_s->locked_ptr, n_s->locked_size);
  return (int)n_s->locked_size;
}

int nvb_nvenc_unlock_bitstream(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 9, handle, "invalid encoder handle");
  if (!n_s->locked) return nv_fail(109, 9, 0, "bitstream not locked");
  int n_st = g_enc.fn.unlockBitstream(n_s->enc, n_s->bitstream);
  n_s->locked = 0;
  n_s->locked_ptr = NULL;
  n_s->locked_size = 0;
  if (n_st != NV_ENC_SUCCESS) {
    return nv_failf(113, 9, n_st, "NvEncUnlockBitstream failed (%d)", n_st);
  }
  return 0;
}

int nvb_nvenc_destroy(int handle) {
  NvEncSession *n_s = nv_enc_slot(handle);
  if (n_s == NULL) return nv_fail(108, 15, handle, "invalid encoder handle");
  if (n_s->locked && g_enc.fn.unlockBitstream != NULL) {
    g_enc.fn.unlockBitstream(n_s->enc, n_s->bitstream);
    n_s->locked = 0;
  }
  if (n_s->mapped && g_enc.fn.unmapInputResource != NULL) {
    g_enc.fn.unmapInputResource(n_s->enc, n_s->mapped_input);
    n_s->mapped = 0;
  }
  if (n_s->registered != NULL && g_enc.fn.unregisterResource != NULL) {
    g_enc.fn.unregisterResource(n_s->enc, n_s->registered);
    n_s->registered = NULL;
  }
  if (n_s->bitstream != NULL && g_enc.fn.destroyBitstreamBuffer != NULL) {
    g_enc.fn.destroyBitstreamBuffer(n_s->enc, n_s->bitstream);
    n_s->bitstream = NULL;
  }
  if (n_s->enc != NULL && g_enc.fn.destroyEncoder != NULL) {
    g_enc.fn.destroyEncoder(n_s->enc);
    n_s->enc = NULL;
  }
  if (n_s->devptr != 0 && g_cuda.mem_free != NULL) {
    g_cuda.mem_free(n_s->devptr);
    n_s->devptr = 0;
  }
  nv_cuda_ctx_destroy(n_s->cu_ctx);
  free(n_s->preset_buf);
  memset(n_s, 0, sizeof(*n_s));
  return 0;
}

// ---------------------------------------------------------------------------
// NVDEC/cuvid loader
// ---------------------------------------------------------------------------

typedef struct {
  HMODULE mod;
  PFN_cuvidGetDecoderCaps get_caps;
  PFN_cuvidCreateDecoder create;
  PFN_cuvidDestroyDecoder destroy;
  PFN_cuvidDecodePicture decode;
  PFN_cuvidMapVideoFrame64 map64;
  PFN_cuvidUnmapVideoFrame64 unmap64;
  PFN_cuvidCreateVideoParser parser_create;
  PFN_cuvidParseVideoData parser_parse;
  PFN_cuvidDestroyVideoParser parser_destroy;
  PFN_cuvidCtxLockCreate lock_create;
  PFN_cuvidCtxLockDestroy lock_destroy;
} NvDecApi;

static int nv_dec_load_api(NvDecApi *api, const char *dll_name) {
  memset(api, 0, sizeof(*api));
  HMODULE n_mod = LoadLibraryA(dll_name);
  if (n_mod == NULL) {
    return nv_fail(115, 0, (int)GetLastError(), "nvcuvid.dll not found");
  }
  api->mod = n_mod;
  api->get_caps =
      (PFN_cuvidGetDecoderCaps)(void *)GetProcAddress(n_mod, "cuvidGetDecoderCaps");
  api->create = (PFN_cuvidCreateDecoder)(void *)GetProcAddress(n_mod, "cuvidCreateDecoder");
  api->destroy = (PFN_cuvidDestroyDecoder)(void *)GetProcAddress(n_mod, "cuvidDestroyDecoder");
  api->decode = (PFN_cuvidDecodePicture)(void *)GetProcAddress(n_mod, "cuvidDecodePicture");
  api->map64 =
      (PFN_cuvidMapVideoFrame64)(void *)GetProcAddress(n_mod, "cuvidMapVideoFrame64");
  api->unmap64 =
      (PFN_cuvidUnmapVideoFrame64)(void *)GetProcAddress(n_mod, "cuvidUnmapVideoFrame64");
  api->parser_create = (PFN_cuvidCreateVideoParser)(void *)GetProcAddress(
      n_mod, "cuvidCreateVideoParser");
  api->parser_parse =
      (PFN_cuvidParseVideoData)(void *)GetProcAddress(n_mod, "cuvidParseVideoData");
  api->parser_destroy = (PFN_cuvidDestroyVideoParser)(void *)GetProcAddress(
      n_mod, "cuvidDestroyVideoParser");
  api->lock_create =
      (PFN_cuvidCtxLockCreate)(void *)GetProcAddress(n_mod, "cuvidCtxLockCreate");
  api->lock_destroy =
      (PFN_cuvidCtxLockDestroy)(void *)GetProcAddress(n_mod, "cuvidCtxLockDestroy");
  if (api->get_caps == NULL || api->create == NULL || api->destroy == NULL ||
      api->decode == NULL || api->map64 == NULL || api->unmap64 == NULL ||
      api->parser_create == NULL || api->parser_parse == NULL ||
      api->parser_destroy == NULL || api->lock_create == NULL ||
      api->lock_destroy == NULL) {
    return nv_fail(102, 0, 0, "nvcuvid.dll entry points missing");
  }
  return 0;
}

typedef struct {
  int in_use;
  void *decoder;
  void *vid_lock;
  void *cu_ctx;
  void *parser;
  int width;
  int height;
  int codec;
  int surfaces;
  int sequence_count;
  int decoded_count;
  int display_count;
  int last_picture_index;
  int coded_width;
  int coded_height;
  int chroma_format;
  int bit_depth;
  int mapped;
  unsigned long long mapped_ptr;
  unsigned int mapped_pitch;
} NvDecSession;

static NvDecSession g_decoders[NV_MAX_DECODERS];
static NvDecApi g_dec;
static int g_dec_loaded;

static int g_dprobe_h264;
static int g_dprobe_hevc;
static int g_dprobe_h264_max_width;
static int g_dprobe_h264_max_height;
static int g_dprobe_h264_num_decoders;
static int g_dprobe_hevc_max_width;
static int g_dprobe_hevc_max_height;
static int g_dprobe_hevc_num_decoders;

int nvb_nvdec_probe_h264(void) { return g_dprobe_h264; }
int nvb_nvdec_probe_hevc(void) { return g_dprobe_hevc; }
int nvb_nvdec_probe_h264_max_width(void) { return g_dprobe_h264_max_width; }
int nvb_nvdec_probe_h264_max_height(void) { return g_dprobe_h264_max_height; }
int nvb_nvdec_probe_h264_num_decoders(void) { return g_dprobe_h264_num_decoders; }
int nvb_nvdec_probe_hevc_max_width(void) { return g_dprobe_hevc_max_width; }
int nvb_nvdec_probe_hevc_max_height(void) { return g_dprobe_hevc_max_height; }
int nvb_nvdec_probe_hevc_num_decoders(void) { return g_dprobe_hevc_num_decoders; }

int nvb_nvdec_probe_run(const char *dll_name) {
  NvDecApi n_api;
  void *n_ctx = NULL;
  int n_rc = 0;
  g_dprobe_h264 = 0;
  g_dprobe_hevc = 0;
  g_dprobe_h264_max_width = 0;
  g_dprobe_h264_max_height = 0;
  g_dprobe_h264_num_decoders = 0;
  g_dprobe_hevc_max_width = 0;
  g_dprobe_hevc_max_height = 0;
  g_dprobe_hevc_num_decoders = 0;

  n_rc = nv_dec_load_api(&n_api, dll_name != NULL ? dll_name : "nvcuvid.dll");
  if (n_rc != 0) goto done;
  n_rc = nv_cuda_ctx_create(&n_ctx);
  if (n_rc != 0) goto done;

  NvDecCaps n_caps;
  memset(&n_caps, 0, sizeof(n_caps));
  n_caps.codecType = CUDA_VIDEO_CODEC_H264;
  n_caps.chromaFormat = CUDA_VIDEO_CHROMA_420;
  n_caps.bitDepthMinus8 = 0;
  int n_cr = n_api.get_caps(&n_caps);
  if (n_cr != CUDA_SUCCESS) {
    n_rc = nv_failf(116, 10, n_cr, "cuvidGetDecoderCaps(H.264) failed (%d)", n_cr);
    goto done;
  }
  if (n_caps.isSupported) {
    g_dprobe_h264 = 1;
    g_dprobe_h264_max_width = (int)n_caps.maxWidth;
    g_dprobe_h264_max_height = (int)n_caps.maxHeight;
    g_dprobe_h264_num_decoders = (int)n_caps.numNVDECs;
  }
  memset(&n_caps, 0, sizeof(n_caps));
  n_caps.codecType = CUDA_VIDEO_CODEC_HEVC;
  n_caps.chromaFormat = CUDA_VIDEO_CHROMA_420;
  n_caps.bitDepthMinus8 = 0;
  n_cr = n_api.get_caps(&n_caps);
  if (n_cr != CUDA_SUCCESS) {
    n_rc = nv_failf(116, 10, n_cr, "cuvidGetDecoderCaps(HEVC) failed (%d)", n_cr);
    goto done;
  }
  if (n_caps.isSupported) {
    g_dprobe_hevc = 1;
    g_dprobe_hevc_max_width = (int)n_caps.maxWidth;
    g_dprobe_hevc_max_height = (int)n_caps.maxHeight;
    g_dprobe_hevc_num_decoders = (int)n_caps.numNVDECs;
  }
  if (!g_dprobe_h264 && !g_dprobe_hevc) {
    n_rc = nv_fail(116, 10, 0, "no NVDEC H.264/HEVC support");
    goto done;
  }

done:
  nv_cuda_ctx_destroy(n_ctx);
  if (n_api.mod != NULL) FreeLibrary(n_api.mod);
  return n_rc;
}

static int nv_dec_ensure_loaded(void) {
  if (g_dec_loaded) return 0;
  int n_rc = nv_dec_load_api(&g_dec, "nvcuvid.dll");
  if (n_rc != 0) return n_rc;
  g_dec_loaded = 1;
  return 0;
}

static NvDecSession *nv_dec_slot(int handle) {
  if (handle < 1 || handle > NV_MAX_DECODERS) return NULL;
  NvDecSession *n_s = &g_decoders[handle - 1];
  if (!n_s->in_use) return NULL;
  return n_s;
}

static int NVAPI nv_dec_sequence_cb(void *user_data, void *format_ptr) {
  NvDecSession *n_s = (NvDecSession *)user_data;
  if (n_s == NULL || format_ptr == NULL) return 0;
  NvVideoFormat *n_fmt = (NvVideoFormat *)format_ptr;
  n_s->sequence_count++;
  n_s->coded_width = (int)n_fmt->codedWidth;
  n_s->coded_height = (int)n_fmt->codedHeight;
  n_s->chroma_format = n_fmt->chromaFormat;
  n_s->bit_depth = (int)n_fmt->bitDepthLumaMinus8 + 8;
  int n_expected_codec = n_s->codec == 0 ? CUDA_VIDEO_CODEC_H264 : CUDA_VIDEO_CODEC_HEVC;
  if (n_fmt->codec != n_expected_codec) return 0;
  if (n_fmt->codedWidth == 0 || n_fmt->codedHeight == 0) return 0;
  return 1;
}

static int NVAPI nv_dec_decode_cb(void *user_data, void *pic_params_ptr) {
  NvDecSession *n_s = (NvDecSession *)user_data;
  if (n_s == NULL || pic_params_ptr == NULL || n_s->decoder == NULL) return 0;
  int n_cr = g_dec.decode(n_s->decoder, pic_params_ptr);
  if (n_cr != CUDA_SUCCESS) return 0;
  n_s->decoded_count++;
  return 1;
}

static int NVAPI nv_dec_display_cb(void *user_data, void *disp_ptr) {
  NvDecSession *n_s = (NvDecSession *)user_data;
  if (n_s == NULL || disp_ptr == NULL) return 0;
  NvParserDispInfo *n_disp = (NvParserDispInfo *)disp_ptr;
  n_s->display_count++;
  n_s->last_picture_index = n_disp->pictureIndex;
  return 1;
}

int nvb_nvdec_create(int codec, int width, int height, int surfaces) {
  if (codec != 0 && codec != 1) return nv_fail(109, 11, codec, "unknown codec id");
  if (width < 16 || height < 16 || width > 8192 || height > 8192) {
    return nv_fail(109, 11, 0, "unsupported dimensions");
  }
  if (surfaces <= 0) surfaces = 8;
  if (surfaces > 32) surfaces = 32;

  int n_slot = -1;
  for (int n_i = 0; n_i < NV_MAX_DECODERS; n_i++) {
    if (!g_decoders[n_i].in_use) {
      n_slot = n_i;
      break;
    }
  }
  if (n_slot < 0) return nv_fail(109, 11, 0, "decoder slots exhausted");

  int n_rc = nv_dec_ensure_loaded();
  if (n_rc != 0) return n_rc;

  void *n_ctx = NULL;
  n_rc = nv_cuda_ctx_create(&n_ctx);
  if (n_rc != 0) return n_rc;
  nv_cuda_set_current(n_ctx);

  void *n_lock = NULL;
  int n_cr = g_dec.lock_create(&n_lock, n_ctx);
  if (n_cr != CUDA_SUCCESS || n_lock == NULL) {
    nv_cuda_ctx_destroy(n_ctx);
    return nv_failf(117, 11, n_cr, "cuvidCtxLockCreate failed (%d)", n_cr);
  }

  NvDecCreateInfo n_dci;
  memset(&n_dci, 0, sizeof(n_dci));
  n_dci.width = (unsigned int)width;
  n_dci.height = (unsigned int)height;
  n_dci.numDecodeSurfaces = (unsigned int)surfaces;
  n_dci.codecType = codec == 0 ? CUDA_VIDEO_CODEC_H264 : CUDA_VIDEO_CODEC_HEVC;
  n_dci.chromaFormat = CUDA_VIDEO_CHROMA_420;
  n_dci.creationFlags = CUDA_VIDEO_CREATE_PREFER_CUDA;
  n_dci.bitDepthMinus8 = 0;
  n_dci.maxWidth = (unsigned int)width;
  n_dci.maxHeight = (unsigned int)height;
  n_dci.displayLeft = 0;
  n_dci.displayTop = 0;
  n_dci.displayRight = (short)width;
  n_dci.displayBottom = (short)height;
  n_dci.outputFormat = CUDA_VIDEO_SURFACE_NV12;
  n_dci.deinterlaceMode = CUDA_VIDEO_DEINTERLACE_WEAVE;
  n_dci.targetWidth = (unsigned int)width;
  n_dci.targetHeight = (unsigned int)height;
  n_dci.numOutputSurfaces = 1;
  n_dci.vidLock = n_lock;
  n_dci.targetLeft = 0;
  n_dci.targetTop = 0;
  n_dci.targetRight = (short)width;
  n_dci.targetBottom = (short)height;

  void *n_decoder = NULL;
  n_cr = g_dec.create(&n_decoder, &n_dci);
  if (n_cr != CUDA_SUCCESS || n_decoder == NULL) {
    g_dec.lock_destroy(n_lock);
    nv_cuda_ctx_destroy(n_ctx);
    return nv_failf(117, 11, n_cr, "cuvidCreateDecoder failed (%d)", n_cr);
  }

  NvDecSession *n_s = &g_decoders[n_slot];
  memset(n_s, 0, sizeof(*n_s));
  n_s->in_use = 1;
  n_s->decoder = n_decoder;
  n_s->vid_lock = n_lock;
  n_s->cu_ctx = n_ctx;
  n_s->width = width;
  n_s->height = height;
  n_s->codec = codec;
  n_s->surfaces = surfaces;
  return n_slot + 1;
}

int nvb_nvdec_parse(int handle, const unsigned char *data, int length) {
  NvDecSession *n_s = nv_dec_slot(handle);
  if (n_s == NULL) return nv_fail(108, 12, handle, "invalid decoder handle");
  if (data == NULL || length <= 0) return nv_fail(109, 12, 0, "empty bitstream");
  nv_cuda_set_current(n_s->cu_ctx);

  if (n_s->parser == NULL) {
    NvParserParams n_pp;
    memset(&n_pp, 0, sizeof(n_pp));
    n_pp.codecType = n_s->codec == 0 ? CUDA_VIDEO_CODEC_H264 : CUDA_VIDEO_CODEC_HEVC;
    n_pp.maxNumDecodeSurfaces = (unsigned int)n_s->surfaces;
    n_pp.clockRate = 10000000;
    n_pp.errorThreshold = 100;
    n_pp.maxDisplayDelay = 0;
    n_pp.userData = n_s;
    n_pp.sequenceCallback = (void *)nv_dec_sequence_cb;
    n_pp.decodeCallback = (void *)nv_dec_decode_cb;
    n_pp.displayCallback = (void *)nv_dec_display_cb;
    void *n_parser = NULL;
    int n_cr = g_dec.parser_create(&n_parser, &n_pp);
    if (n_cr != CUDA_SUCCESS || n_parser == NULL) {
      return nv_failf(118, 12, n_cr, "cuvidCreateVideoParser failed (%d)", n_cr);
    }
    n_s->parser = n_parser;
  }

  NvSourcePacket n_pkt;
  memset(&n_pkt, 0, sizeof(n_pkt));
  n_pkt.flags = CUVID_PKT_ENDOFSTREAM;
  n_pkt.payloadSize = (unsigned int)length;
  n_pkt.payload = data;
  int n_cr = g_dec.parser_parse(n_s->parser, &n_pkt);
  if (n_cr != CUDA_SUCCESS) {
    return nv_failf(118, 12, n_cr, "cuvidParseVideoData failed (%d)", n_cr);
  }
  if (n_s->decoded_count <= 0) {
    return nv_fail(121, 12, 0, "parser produced no decodable picture");
  }
  return 0;
}

int nvb_nvdec_sequence_count(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->sequence_count;
}
int nvb_nvdec_decoded_count(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->decoded_count;
}
int nvb_nvdec_display_count(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->display_count;
}
int nvb_nvdec_last_picture_index(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->last_picture_index;
}
int nvb_nvdec_coded_width(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->coded_width;
}
int nvb_nvdec_coded_height(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->coded_height;
}
int nvb_nvdec_chroma_format(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->chroma_format;
}
int nvb_nvdec_bit_depth(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->bit_depth;
}
int nvb_nvdec_frame_width(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->width;
}
int nvb_nvdec_frame_height(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  return n_s == NULL ? -1 : n_s->height;
}

int nvb_nvdec_map(int handle, int picture_index) {
  NvDecSession *n_s = nv_dec_slot(handle);
  if (n_s == NULL) return nv_fail(108, 13, handle, "invalid decoder handle");
  if (n_s->mapped) return nv_fail(109, 13, 0, "frame already mapped");
  if (picture_index < 0) return nv_fail(122, 13, picture_index, "invalid picture index");
  nv_cuda_set_current(n_s->cu_ctx);
  NvProcParams n_vpp;
  memset(&n_vpp, 0, sizeof(n_vpp));
  n_vpp.progressiveFrame = 1;
  n_vpp.topFieldFirst = 1;
  unsigned long long n_ptr = 0;
  unsigned int n_pitch = 0;
  int n_cr = g_dec.map64(n_s->decoder, picture_index, &n_ptr, &n_pitch, &n_vpp);
  if (n_cr != CUDA_SUCCESS || n_ptr == 0 || n_pitch == 0) {
    return nv_failf(119, 13, n_cr, "cuvidMapVideoFrame64 failed (%d)", n_cr);
  }
  n_s->mapped = 1;
  n_s->mapped_ptr = n_ptr;
  n_s->mapped_pitch = n_pitch;
  return 0;
}

int nvb_nvdec_copy_frame(int handle, unsigned char *out, int capacity) {
  NvDecSession *n_s = nv_dec_slot(handle);
  if (n_s == NULL) return nv_fail(108, 14, handle, "invalid decoder handle");
  if (!n_s->mapped) return nv_fail(109, 14, 0, "frame not mapped");
  if (out == NULL || capacity < 0) return nv_fail(109, 14, 0, "invalid output buffer");
  size_t n_w = (size_t)n_s->width;
  size_t n_h = (size_t)n_s->height;
  size_t n_needed = n_w * n_h * 3 / 2;
  if ((size_t)capacity < n_needed) {
    return nv_failf(114, 14, (int)n_needed,
                    "frame buffer too small: need %d bytes", (int)n_needed);
  }
  size_t n_plane = (size_t)n_s->mapped_pitch * (n_h + n_h / 2);
  unsigned char *n_tmp = (unsigned char *)malloc(n_plane);
  if (n_tmp == NULL) return nv_fail(123, 14, 0, "frame staging allocation failed");
  nv_cuda_set_current(n_s->cu_ctx);
  int n_cr = g_cuda.dtoh(n_tmp, n_s->mapped_ptr, (unsigned long long)n_plane);
  if (n_cr != CUDA_SUCCESS) {
    free(n_tmp);
    return nv_failf(120, 14, n_cr, "cuMemcpyDtoH failed (%d)", n_cr);
  }
  for (size_t n_row = 0; n_row < n_h; n_row++) {
    memcpy(out + n_row * n_w, n_tmp + n_row * (size_t)n_s->mapped_pitch, n_w);
  }
  unsigned char *n_uv_src = n_tmp + (size_t)n_s->mapped_pitch * n_h;
  unsigned char *n_uv_dst = out + n_w * n_h;
  for (size_t n_row = 0; n_row < n_h / 2; n_row++) {
    memcpy(n_uv_dst + n_row * n_w, n_uv_src + n_row * (size_t)n_s->mapped_pitch, n_w);
  }
  free(n_tmp);
  return (int)n_needed;
}

int nvb_nvdec_unmap(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  if (n_s == NULL) return nv_fail(108, 13, handle, "invalid decoder handle");
  if (!n_s->mapped) return nv_fail(109, 13, 0, "frame not mapped");
  int n_cr = g_dec.unmap64(n_s->decoder, n_s->mapped_ptr);
  n_s->mapped = 0;
  n_s->mapped_ptr = 0;
  n_s->mapped_pitch = 0;
  if (n_cr != CUDA_SUCCESS) {
    return nv_failf(119, 13, n_cr, "cuvidUnmapVideoFrame64 failed (%d)", n_cr);
  }
  return 0;
}

int nvb_nvdec_destroy(int handle) {
  NvDecSession *n_s = nv_dec_slot(handle);
  if (n_s == NULL) return nv_fail(108, 15, handle, "invalid decoder handle");
  if (n_s->mapped && g_dec.unmap64 != NULL) {
    g_dec.unmap64(n_s->decoder, n_s->mapped_ptr);
    n_s->mapped = 0;
  }
  if (n_s->parser != NULL && g_dec.parser_destroy != NULL) {
    g_dec.parser_destroy(n_s->parser);
    n_s->parser = NULL;
  }
  if (n_s->decoder != NULL && g_dec.destroy != NULL) {
    g_dec.destroy(n_s->decoder);
    n_s->decoder = NULL;
  }
  if (n_s->vid_lock != NULL && g_dec.lock_destroy != NULL) {
    g_dec.lock_destroy(n_s->vid_lock);
    n_s->vid_lock = NULL;
  }
  nv_cuda_ctx_destroy(n_s->cu_ctx);
  memset(n_s, 0, sizeof(*n_s));
  return 0;
}
