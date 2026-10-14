/* XIOM -- xiom.ktx2 probe bridge (MIT OR Apache-2.0, XIOM Authors).
 *
 * This file is the only non-vendored C code in the package (with the zstd
 * shim). It links against the vendored libktx v4.4.2 (KTX-Software commit
 * 4d6fc70e) built by port.args.json and exposes the `x2_*` probe surface the
 * XIOM module (ktx2.xi) calls. XIOM never touches a libktx struct or a
 * pointer returned by C: handles live in XIOM-owned 8-byte slots, every
 * other out-parameter is an XIOM-owned byte slot read back little-endian
 * (B-11/B-16/B-17/B-20/B-25 discipline), and status values travel as C
 * return values (B-24 free).
 *
 * The kx2_symbols table below takes the address of every function declared
 * in the pinned public header (tools/oracle_ktx.py emits the inventory and
 * verifies this table). Linking the suite therefore fails if any declared
 * surface function is missing from the vendored build: the table IS the
 * 100%-coverage proof at link time.
 *
 * Probe record layouts (little-endian, slots zero-filled by the bridge
 * before use) are documented in SPEC.md section 3.
 */

#include "../vendor/ktx/xiom_build_config.h" /* KHRONOS_STATIC, LIBKTX, ... */

#include "../vendor/ktx/include/ktx.h"
#include "../vendor/ktx/lib/ktxint.h"
#include "../vendor/ktx/lib/texture1.h"
#include "../vendor/ktx/lib/texture2.h"
#include "../vendor/ktx/lib/vkformat_enum.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ======================================================================== */
/* 1. Declared-surface symbol table (link-time 93/93 proof).                */
/* ======================================================================== */

typedef void (*kx2_pfn)(void);

typedef struct kx2_symbol {
    const char* name;
    kx2_pfn pfn;
} kx2_symbol;

static const kx2_symbol kx2_symbols[] = {
    { "ktxLoadOpenGL", (kx2_pfn)ktxLoadOpenGL },
    { "ktxTexture_CreateFromStdioStream", (kx2_pfn)ktxTexture_CreateFromStdioStream },
    { "ktxTexture_CreateFromNamedFile", (kx2_pfn)ktxTexture_CreateFromNamedFile },
    { "ktxTexture_CreateFromMemory", (kx2_pfn)ktxTexture_CreateFromMemory },
    { "ktxTexture_CreateFromStream", (kx2_pfn)ktxTexture_CreateFromStream },
    { "ktxTexture_GetData", (kx2_pfn)ktxTexture_GetData },
    { "ktxTexture_GetRowPitch", (kx2_pfn)ktxTexture_GetRowPitch },
    { "ktxTexture_GetElementSize", (kx2_pfn)ktxTexture_GetElementSize },
    { "ktxTexture_GetDataSize", (kx2_pfn)ktxTexture_GetDataSize },
    { "ktxTexture_GLUpload", (kx2_pfn)ktxTexture_GLUpload },
    { "ktxTexture_IterateLevelFaces", (kx2_pfn)ktxTexture_IterateLevelFaces },
    { "ktxTexture1_Create", (kx2_pfn)ktxTexture1_Create },
    { "ktxTexture1_CreateFromStdioStream", (kx2_pfn)ktxTexture1_CreateFromStdioStream },
    { "ktxTexture1_CreateFromNamedFile", (kx2_pfn)ktxTexture1_CreateFromNamedFile },
    { "ktxTexture1_CreateFromMemory", (kx2_pfn)ktxTexture1_CreateFromMemory },
    { "ktxTexture1_CreateFromStream", (kx2_pfn)ktxTexture1_CreateFromStream },
    { "ktxTexture1_Destroy", (kx2_pfn)ktxTexture1_Destroy },
    { "ktxTexture1_NeedsTranscoding", (kx2_pfn)ktxTexture1_NeedsTranscoding },
    { "ktxTexture1_LoadImageData", (kx2_pfn)ktxTexture1_LoadImageData },
    { "ktxTexture1_WriteToStdioStream", (kx2_pfn)ktxTexture1_WriteToStdioStream },
    { "ktxTexture1_WriteToNamedFile", (kx2_pfn)ktxTexture1_WriteToNamedFile },
    { "ktxTexture1_WriteToMemory", (kx2_pfn)ktxTexture1_WriteToMemory },
    { "ktxTexture1_WriteToStream", (kx2_pfn)ktxTexture1_WriteToStream },
    { "ktxTexture1_WriteKTX2ToStdioStream", (kx2_pfn)ktxTexture1_WriteKTX2ToStdioStream },
    { "ktxTexture1_WriteKTX2ToNamedFile", (kx2_pfn)ktxTexture1_WriteKTX2ToNamedFile },
    { "ktxTexture1_WriteKTX2ToMemory", (kx2_pfn)ktxTexture1_WriteKTX2ToMemory },
    { "ktxTexture1_WriteKTX2ToStream", (kx2_pfn)ktxTexture1_WriteKTX2ToStream },
    { "ktxTexture2_Create", (kx2_pfn)ktxTexture2_Create },
    { "ktxTexture2_CreateCopy", (kx2_pfn)ktxTexture2_CreateCopy },
    { "ktxTexture2_CreateFromStdioStream", (kx2_pfn)ktxTexture2_CreateFromStdioStream },
    { "ktxTexture2_CreateFromNamedFile", (kx2_pfn)ktxTexture2_CreateFromNamedFile },
    { "ktxTexture2_CreateFromMemory", (kx2_pfn)ktxTexture2_CreateFromMemory },
    { "ktxTexture2_CreateFromStream", (kx2_pfn)ktxTexture2_CreateFromStream },
    { "ktxTexture2_Destroy", (kx2_pfn)ktxTexture2_Destroy },
    { "ktxTexture2_CompressBasis", (kx2_pfn)ktxTexture2_CompressBasis },
    { "ktxTexture2_DeflateZstd", (kx2_pfn)ktxTexture2_DeflateZstd },
    { "ktxTexture2_DeflateZLIB", (kx2_pfn)ktxTexture2_DeflateZLIB },
    { "ktxTexture2_GetComponentInfo", (kx2_pfn)ktxTexture2_GetComponentInfo },
    { "ktxTexture2_GetImageOffset", (kx2_pfn)ktxTexture2_GetImageOffset },
    { "ktxTexture2_GetNumComponents", (kx2_pfn)ktxTexture2_GetNumComponents },
    { "ktxTexture2_GetTransferFunction_e", (kx2_pfn)ktxTexture2_GetTransferFunction_e },
    { "ktxTexture2_GetOETF_e", (kx2_pfn)ktxTexture2_GetOETF_e },
    { "ktxTexture2_GetOETF", (kx2_pfn)ktxTexture2_GetOETF },
    { "ktxTexture2_GetColorModel_e", (kx2_pfn)ktxTexture2_GetColorModel_e },
    { "ktxTexture2_GetPremultipliedAlpha", (kx2_pfn)ktxTexture2_GetPremultipliedAlpha },
    { "ktxTexture2_GetPrimaries_e", (kx2_pfn)ktxTexture2_GetPrimaries_e },
    { "ktxTexture2_NeedsTranscoding", (kx2_pfn)ktxTexture2_NeedsTranscoding },
    { "ktxTexture2_SetTransferFunction", (kx2_pfn)ktxTexture2_SetTransferFunction },
    { "ktxTexture2_SetOETF", (kx2_pfn)ktxTexture2_SetOETF },
    { "ktxTexture2_SetPrimaries", (kx2_pfn)ktxTexture2_SetPrimaries },
    { "ktxTexture2_LoadImageData", (kx2_pfn)ktxTexture2_LoadImageData },
    { "ktxTexture2_LoadDeflatedImageData", (kx2_pfn)ktxTexture2_LoadDeflatedImageData },
    { "ktxTexture2_WriteToStdioStream", (kx2_pfn)ktxTexture2_WriteToStdioStream },
    { "ktxTexture2_WriteToNamedFile", (kx2_pfn)ktxTexture2_WriteToNamedFile },
    { "ktxTexture2_WriteToMemory", (kx2_pfn)ktxTexture2_WriteToMemory },
    { "ktxTexture2_WriteToStream", (kx2_pfn)ktxTexture2_WriteToStream },
    { "ktxTexture2_CompressAstcEx", (kx2_pfn)ktxTexture2_CompressAstcEx },
    { "ktxTexture2_CompressAstc", (kx2_pfn)ktxTexture2_CompressAstc },
    { "ktxTexture2_DecodeAstc", (kx2_pfn)ktxTexture2_DecodeAstc },
    { "ktxTexture2_CompressBasisEx", (kx2_pfn)ktxTexture2_CompressBasisEx },
    { "ktxTexture2_TranscodeBasis", (kx2_pfn)ktxTexture2_TranscodeBasis },
    { "ktxErrorString", (kx2_pfn)ktxErrorString },
    { "ktxSupercompressionSchemeString", (kx2_pfn)ktxSupercompressionSchemeString },
    { "ktxTranscodeFormatString", (kx2_pfn)ktxTranscodeFormatString },
    { "ktxHashList_Create", (kx2_pfn)ktxHashList_Create },
    { "ktxHashList_CreateCopy", (kx2_pfn)ktxHashList_CreateCopy },
    { "ktxHashList_Construct", (kx2_pfn)ktxHashList_Construct },
    { "ktxHashList_ConstructCopy", (kx2_pfn)ktxHashList_ConstructCopy },
    { "ktxHashList_Destroy", (kx2_pfn)ktxHashList_Destroy },
    { "ktxHashList_Destruct", (kx2_pfn)ktxHashList_Destruct },
    { "ktxHashList_AddKVPair", (kx2_pfn)ktxHashList_AddKVPair },
    { "ktxHashList_DeleteEntry", (kx2_pfn)ktxHashList_DeleteEntry },
    { "ktxHashList_DeleteKVPair", (kx2_pfn)ktxHashList_DeleteKVPair },
    { "ktxHashList_FindEntry", (kx2_pfn)ktxHashList_FindEntry },
    { "ktxHashList_FindValue", (kx2_pfn)ktxHashList_FindValue },
    { "ktxHashList_Next", (kx2_pfn)ktxHashList_Next },
    { "ktxHashList_Sort", (kx2_pfn)ktxHashList_Sort },
    { "ktxHashList_Serialize", (kx2_pfn)ktxHashList_Serialize },
    { "ktxHashList_Deserialize", (kx2_pfn)ktxHashList_Deserialize },
    { "ktxHashListEntry_GetKey", (kx2_pfn)ktxHashListEntry_GetKey },
    { "ktxHashListEntry_GetValue", (kx2_pfn)ktxHashListEntry_GetValue },
    { "ktxPrintInfoForStdioStream", (kx2_pfn)ktxPrintInfoForStdioStream },
    { "ktxPrintInfoForNamedFile", (kx2_pfn)ktxPrintInfoForNamedFile },
    { "ktxPrintInfoForMemory", (kx2_pfn)ktxPrintInfoForMemory },
    { "ktxPrintKTX1InfoTextForStream", (kx2_pfn)ktxPrintKTX1InfoTextForStream },
    { "ktxPrintKTX2InfoTextForMemory", (kx2_pfn)ktxPrintKTX2InfoTextForMemory },
    { "ktxPrintKTX2InfoTextForNamedFile", (kx2_pfn)ktxPrintKTX2InfoTextForNamedFile },
    { "ktxPrintKTX2InfoTextForStdioStream", (kx2_pfn)ktxPrintKTX2InfoTextForStdioStream },
    { "ktxPrintKTX2InfoTextForStream", (kx2_pfn)ktxPrintKTX2InfoTextForStream },
    { "ktxPrintKTX2InfoJSONForMemory", (kx2_pfn)ktxPrintKTX2InfoJSONForMemory },
    { "ktxPrintKTX2InfoJSONForNamedFile", (kx2_pfn)ktxPrintKTX2InfoJSONForNamedFile },
    { "ktxPrintKTX2InfoJSONForStdioStream", (kx2_pfn)ktxPrintKTX2InfoJSONForStdioStream },
    { "ktxPrintKTX2InfoJSONForStream", (kx2_pfn)ktxPrintKTX2InfoJSONForStream },
};

int32_t x2_symbol_count(void)
{
    return (int32_t)(sizeof(kx2_symbols) / sizeof(kx2_symbols[0]));
}

/* Copy the i-th symbol name (NUL terminated) into an owned slot. */
int32_t x2_symbol_name(int32_t index, uint8_t* dst, int32_t capacity)
{
    const char* name;
    int32_t len;
    if (dst == NULL || capacity <= 0)
        return -1;
    if (index < 0 || index >= x2_symbol_count())
        return -1;
    name = kx2_symbols[index].name;
    len = (int32_t)strlen(name);
    if (len + 1 > capacity)
        return -1;
    memcpy(dst, name, (size_t)len + 1);
    return len;
}

/* Exact-name lookup over an owned input buffer; returns the index or -1. */
int32_t x2_symbol_lookup(const uint8_t* name, int32_t name_len)
{
    int32_t i;
    if (name == NULL || name_len <= 0)
        return -1;
    for (i = 0; i < x2_symbol_count(); ++i) {
        const char* n = kx2_symbols[i].name;
        size_t ln = strlen(n);
        if ((int32_t)ln == name_len && memcmp(n, name, (size_t)name_len) == 0)
            return i;
    }
    return -1;
}

/* ======================================================================== */
/* 2. Little-endian slot helpers.                                           */
/* ======================================================================== */

static void put_u32(uint8_t* p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static void put_u64(uint8_t* p, uint64_t v)
{
    put_u32(p, (uint32_t)(v & 0xFFFFFFFFu));
    put_u32(p + 4, (uint32_t)(v >> 32));
}

static uint64_t get_u64(const uint8_t* p)
{
    uint64_t lo = (uint64_t)p[0] | ((uint64_t)p[1] << 8)
                | ((uint64_t)p[2] << 16) | ((uint64_t)p[3] << 24);
    uint64_t hi = (uint64_t)p[4] | ((uint64_t)p[5] << 8)
                | ((uint64_t)p[6] << 16) | ((uint64_t)p[7] << 24);
    return lo | (hi << 32);
}

/* ======================================================================== */
/* 3. Texture lifecycle probes.                                             */
/* ======================================================================== */

/* kind: 1 = ktxTexture1, 2 = ktxTexture2. Writes the handle (8 bytes, zero
 * when creation failed) into `handle`. Returns the KTX status. */
int32_t x2_texture_create(int32_t kind, uint32_t vk_format,
                          uint32_t gl_internalformat, uint32_t width,
                          uint32_t height, uint32_t depth,
                          uint32_t levels, uint32_t layers, uint32_t faces,
                          int32_t is_array, int32_t generate_mipmaps,
                          uint8_t* handle)
{
    ktxTextureCreateInfo info;
    KTX_error_code rc = KTX_SUCCESS;
    void* tex = NULL;

    if (handle == NULL)
        return KTX_INVALID_VALUE;
    memset(handle, 0, 8);
    memset(&info, 0, sizeof(info));
    info.glInternalformat = gl_internalformat;
    info.vkFormat = vk_format;
    info.baseWidth = width;
    info.baseHeight = height;
    info.baseDepth = depth;
    info.numDimensions = depth > 1 ? 3 : (height > 1 ? 2 : 1);
    info.numLevels = levels;
    info.numLayers = layers;
    info.numFaces = faces;
    info.isArray = is_array != 0;
    info.generateMipmaps = generate_mipmaps != 0;

    if (kind == 2) {
        ktxTexture2* t2 = NULL;
        rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &t2);
        if (rc == KTX_SUCCESS)
            tex = t2;
    } else if (kind == 1) {
        ktxTexture1* t1 = NULL;
        rc = ktxTexture1_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &t1);
        if (rc == KTX_SUCCESS)
            tex = t1;
    } else {
        return KTX_INVALID_VALUE;
    }
    if (rc != KTX_SUCCESS)
        return rc;
    put_u64(handle, (uint64_t)(uintptr_t)tex);
    return KTX_SUCCESS;
}

int32_t x2_texture_destroy(int32_t kind, uint8_t* handle)
{
    void* tex;
    if (handle == NULL)
        return KTX_INVALID_VALUE;
    tex = (void*)(uintptr_t)get_u64(handle);
    if (tex == NULL)
        return KTX_INVALID_VALUE;
    if (kind == 2)
        ktxTexture2_Destroy((ktxTexture2*)tex);
    else if (kind == 1)
        ktxTexture1_Destroy((ktxTexture1*)tex);
    else
        return KTX_INVALID_VALUE;
    memset(handle, 0, 8);
    return KTX_SUCCESS;
}

/* Write image data from an XIOM-owned input buffer into level/layer/face. */
int32_t x2_set_image(uint8_t* handle, int32_t kind, uint32_t level,
                     uint32_t layer, uint32_t face_slice,
                     const uint8_t* src, int32_t src_len)
{
    void* tex;
    if (handle == NULL || src == NULL || src_len <= 0)
        return KTX_INVALID_VALUE;
    tex = (void*)(uintptr_t)get_u64(handle);
    if (tex == NULL)
        return KTX_INVALID_VALUE;
    if (kind == 2)
        return ktxTexture2_SetImageFromMemory((ktxTexture2*)tex, level,
                                              layer, face_slice, src,
                                              (ktx_size_t)src_len);
    if (kind == 1)
        return ktxTexture1_SetImageFromMemory((ktxTexture1*)tex, level,
                                              layer, face_slice, src,
                                              (ktx_size_t)src_len);
    return KTX_INVALID_VALUE;
}

/* KTX1 GL format trim for ktxTexture1_Create: the public struct fields
 * must be set directly after creation (upstream API contract). */
int32_t x2_texture1_set_gl(uint8_t* handle, uint32_t gl_format,
                           uint32_t gl_type)
{
    ktxTexture1* tex;
    if (handle == NULL)
        return KTX_INVALID_VALUE;
    tex = (ktxTexture1*)(uintptr_t)get_u64(handle);
    if (tex == NULL)
        return KTX_INVALID_VALUE;
    tex->glFormat = gl_format;
    tex->glType = gl_type;
    return KTX_SUCCESS;
}

/* Serialize the texture (WriteToMemory) into an owned slot. On a short
 * buffer returns KTX_FILE_OVERFLOW and stores the needed size in out_len. */
int32_t x2_write_memory(uint8_t* handle, int32_t kind, uint8_t* dst,
                        int32_t capacity, uint8_t* out_len)
{
    ktx_uint8_t* bytes = NULL;
    ktx_size_t size = 0;
    KTX_error_code rc;
    void* tex;
    if (handle == NULL || dst == NULL || out_len == NULL || capacity < 0)
        return KTX_INVALID_VALUE;
    tex = (void*)(uintptr_t)get_u64(handle);
    if (tex == NULL)
        return KTX_INVALID_VALUE;
    put_u64(out_len, 0);
    if (kind == 2)
        rc = ktxTexture2_WriteToMemory((ktxTexture2*)tex, &bytes, &size);
    else if (kind == 1)
        rc = ktxTexture1_WriteToMemory((ktxTexture1*)tex, &bytes, &size);
    else
        return KTX_INVALID_VALUE;
    if (rc != KTX_SUCCESS)
        return rc;
    if ((ktx_size_t)capacity < size) {
        put_u64(out_len, (uint64_t)size);
        free(bytes);
        return KTX_FILE_OVERFLOW;
    }
    memcpy(dst, bytes, (size_t)size);
    free(bytes);
    put_u64(out_len, (uint64_t)size);
    return KTX_SUCCESS;
}

/* Read a KTX1/KTX2 texture from an owned buffer, copy a fixed 128-byte
 * info record, and destroy it. Returns the create status.
 * Record layout (all little-endian):
 *   +0  class_id u32        +4  vk_format u32
 *   +8  base_width          +12 base_height
 *   +16 base_depth          +20 num_levels
 *   +24 num_layers          +28 num_faces
 *   +32 is_array            +36 is_cubemap
 *   +40 is_compressed       +44 generate_mipmaps
 *   +48 supercompression    +52 num_components
 *   +56 needs_transcoding   +60 orientation_x
 *   +64 orientation_y       +68 orientation_z
 *   +72 data_size u64       +80 component_byte_length
 *   +84 format (vk or GL internal)  +88 gl_format
 *   +92 gl_type             +96 is_video
 *   +100 duration           +104 timescale
 *   +108 loopcount          +112..127 reserved
 */
int32_t x2_read_info(const uint8_t* src, int32_t src_len, uint8_t* out)
{
    ktxTexture* tex = NULL;
    KTX_error_code rc;
    if (src == NULL || src_len <= 0 || out == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 128);
    rc = ktxTexture_CreateFromMemory(src, (ktx_size_t)src_len,
                                     KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
                                     &tex);
    if (rc != KTX_SUCCESS)
        return rc;
    put_u32(out + 0, (uint32_t)tex->classId);
    put_u32(out + 8, tex->baseWidth);
    put_u32(out + 12, tex->baseHeight);
    put_u32(out + 16, tex->baseDepth);
    put_u32(out + 20, tex->numLevels);
    put_u32(out + 24, tex->numLayers);
    put_u32(out + 28, tex->numFaces);
    put_u32(out + 32, tex->isArray ? 1u : 0u);
    put_u32(out + 36, tex->isCubemap ? 1u : 0u);
    put_u32(out + 40, tex->isCompressed ? 1u : 0u);
    put_u32(out + 44, tex->generateMipmaps ? 1u : 0u);
    put_u32(out + 60, (uint32_t)tex->orientation.x);
    put_u32(out + 64, (uint32_t)tex->orientation.y);
    put_u32(out + 68, (uint32_t)tex->orientation.z);
    put_u64(out + 72, (uint64_t)tex->dataSize);
    if (tex->classId == ktxTexture2_c) {
        ktxTexture2* t2 = (ktxTexture2*)tex;
        ktx_uint32_t num_components = 0;
        ktx_uint32_t component_byte_length = 0;
        put_u32(out + 4, t2->vkFormat);
        put_u32(out + 48, (uint32_t)t2->supercompressionScheme);
        ktxTexture2_GetComponentInfo(t2, &num_components,
                                     &component_byte_length);
        put_u32(out + 52, num_components);
        put_u32(out + 80, component_byte_length);
        put_u32(out + 56, ktxTexture2_NeedsTranscoding(t2) ? 1u : 0u);
        put_u32(out + 96, t2->isVideo ? 1u : 0u);
        put_u32(out + 100, t2->duration);
        put_u32(out + 104, t2->timescale);
        put_u32(out + 108, t2->loopcount);
        put_u32(out + 84, t2->vkFormat);
    } else {
        ktxTexture1* t1 = (ktxTexture1*)tex;
        put_u32(out + 84, t1->glInternalformat);
        put_u32(out + 88, t1->glFormat);
        put_u32(out + 92, t1->glType);
    }
    ktxTexture_Destroy(tex);
    return KTX_SUCCESS;
}

/* Copy one level's image bytes out of a KTX1/KTX2 buffer into an owned slot.
 * Returns the create/copy status; `out_len` (u64) gets the byte count. */
int32_t x2_read_level(const uint8_t* src, int32_t src_len, uint32_t level,
                      uint8_t* dst, int32_t capacity, uint8_t* out_len)
{
    ktxTexture* tex = NULL;
    KTX_error_code rc;
    ktx_size_t offset = 0;
    ktx_size_t level_size;
    const ktx_uint8_t* data;
    if (src == NULL || src_len <= 0 || dst == NULL || out_len == NULL
        || capacity < 0)
        return KTX_INVALID_VALUE;
    put_u64(out_len, 0);
    rc = ktxTexture_CreateFromMemory(src, (ktx_size_t)src_len,
                                     KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
                                     &tex);
    if (rc != KTX_SUCCESS)
        return rc;
    rc = ktxTexture_GetImageOffset(tex, level, 0, 0, &offset);
    if (rc != KTX_SUCCESS) {
        ktxTexture_Destroy(tex);
        return rc;
    }
    level_size = ktxTexture_GetLevelSize(tex, level);
    if ((ktx_size_t)capacity < level_size) {
        put_u64(out_len, (uint64_t)level_size);
        ktxTexture_Destroy(tex);
        return KTX_FILE_OVERFLOW;
    }
    data = ktxTexture_GetData(tex);
    if (data == NULL || level_size == 0) {
        ktxTexture_Destroy(tex);
        return KTX_INVALID_OPERATION;
    }
    memcpy(dst, data + offset, (size_t)level_size);
    put_u64(out_len, (uint64_t)level_size);
    ktxTexture_Destroy(tex);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 4. In-memory write/read round-trip probe.                                */
/* ======================================================================== */

typedef struct kx2_iter_stats {
    int32_t images;
    uint64_t bytes;
    uint32_t first_byte;
} kx2_iter_stats;

static KTX_error_code kx2_iter_cb(int miplevel, int face, int width,
                                  int height, int depth,
                                  ktx_uint64_t face_lod_size, void* pixels,
                                  void* userdata)
{
    kx2_iter_stats* stats = (kx2_iter_stats*)userdata;
    (void)miplevel; (void)face; (void)width; (void)height; (void)depth;
    stats->images += 1;
    stats->bytes += (uint64_t)face_lod_size;
    if (pixels != NULL && stats->first_byte == 0xFFFFFFFFu)
        stats->first_byte = *(const uint8_t*)pixels;
    return KTX_SUCCESS;
}

/* mode 0: plain in-memory write/read/iterate round trip
 * mode 1: DeflateZstd then round trip (KTX_SS_ZSTD)
 * mode 2: DeflateZLIB then round trip (KTX_SS_ZLIB)
 * Record (128 bytes):
 *   +0  write_rc           +4  write_len u32 (low)
 *   +8  read_rc            +12 class_id
 *   +16 vk_format          +20 num_levels
 *   +24 data_size u64      +32 level0_len
 *   +36 level0_cmp_fail    +40 iter_rc
 *   +44 iter_images        +48 iter_bytes u64
 *   +56 iter_first_byte    +60 supercompression_after_deflate
 *   +64 deflated_size_hint +68 load_deflated_rc
 *   +72 row_pitch          +76 element_size
 *   +80 copy_rc            +84 copy_levels
 *   +88 oetf_e             +92 oetf
 *   +96 color_model        +100 premultiplied
 *   +104 primaries_e       +108 set_tf_rc
 *   +112 set_oetf_rc       +116 set_primaries_rc
 *   +120 num_components
 * `generated` (owned) receives the serialized KTX2 bytes.
 */
int32_t x2_roundtrip_probe(int32_t mode, uint32_t width, uint32_t height,
                           uint8_t* out, uint8_t* generated,
                           int32_t generated_capacity,
                           const uint8_t* image, int32_t image_len,
                           const uint8_t* expected, int32_t expected_len)
{
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    uint8_t* bytes = NULL;
    ktx_size_t size = 0;

    if (out == NULL || generated == NULL || image == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 128);
    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = width;
    info.baseHeight = height;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;

    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS) {
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }

    if (mode == 1)
        rc = ktxTexture2_DeflateZstd(tex, 3);
    else if (mode == 2)
        rc = ktxTexture2_DeflateZLIB(tex, 6);
    else
        rc = KTX_SUCCESS;
    put_u32(out + 60, (uint32_t)tex->supercompressionScheme);
    put_u32(out + 64, (uint32_t)tex->dataSize);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }

    rc = ktxTexture2_WriteToMemory(tex, (ktx_uint8_t**)&bytes, &size);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }
    put_u32(out + 0, (uint32_t)rc);
    put_u32(out + 4, (uint32_t)size);
    if ((ktx_size_t)generated_capacity < size) {
        free(bytes);
        ktxTexture2_Destroy(tex);
        return KTX_FILE_OVERFLOW;
    }
    memcpy(generated, bytes, (size_t)size);
    free(bytes);

    /* Read back from the serialized bytes. */
    {
        ktxTexture2* back = NULL;
        rc = ktxTexture2_CreateFromMemory(generated, size,
                                          KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
                                          &back);
        put_u32(out + 8, (uint32_t)rc);
        if (rc != KTX_SUCCESS) {
            ktxTexture2_Destroy(tex);
            return rc;
        }
        put_u32(out + 12, (uint32_t)back->classId);
        put_u32(out + 16, back->vkFormat);
        put_u32(out + 20, back->numLevels);
        put_u64(out + 24, (uint64_t)back->dataSize);
        put_u32(out + 72, ktxTexture_GetRowPitch(ktxTexture(back), 0));
        put_u32(out + 76, ktxTexture_GetElementSize(ktxTexture(back)));
        put_u32(out + 124, ktxTexture2_GetNumComponents(back));

        {
            ktx_size_t offset = 0;
            ktx_size_t level0 = ktxTexture_GetLevelSize(ktxTexture(back), 0);
            const ktx_uint8_t* data = ktxTexture_GetData(ktxTexture(back));
            put_u32(out + 32, (uint32_t)level0);
            if (expected != NULL && expected_len > 0 && data != NULL
                && ktxTexture2_GetImageOffset(back, 0, 0, 0, &offset)
                   == KTX_SUCCESS) {
                size_t cmp_len = (size_t)level0;
                if (cmp_len > (size_t)expected_len)
                    cmp_len = (size_t)expected_len;
                if ((ktx_size_t)expected_len < level0
                    || memcmp(data + offset, expected, cmp_len) != 0)
                    put_u32(out + 36, 1);
            }
        }

        {
            kx2_iter_stats stats;
            stats.images = 0;
            stats.bytes = 0;
            stats.first_byte = 0xFFFFFFFFu;
            rc = ktxTexture_IterateLevelFaces(ktxTexture(back), kx2_iter_cb,
                                              &stats);
            put_u32(out + 40, (uint32_t)rc);
            put_u32(out + 44, (uint32_t)stats.images);
            put_u64(out + 48, stats.bytes);
            put_u32(out + 56, stats.first_byte);
        }
        ktxTexture2_Destroy(back);
    }

    /* CreateCopy + transfer-function/primaries getters and setters. A UNORM
     * (non-sRGB) format only accepts KHR_DF_TRANSFER_LINEAR: the sRGB value
     * is rejected with KTX_INVALID_OPERATION by the upstream guard. */
    {
        ktxTexture2* copy = NULL;
        rc = ktxTexture2_CreateCopy(tex, &copy);
        put_u32(out + 80, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            put_u32(out + 84, copy->numLevels);
            put_u32(out + 88, (uint32_t)ktxTexture2_GetTransferFunction_e(copy));
            put_u32(out + 92, (uint32_t)ktxTexture2_GetOETF_e(copy));
            put_u32(out + 96, (uint32_t)ktxTexture2_GetOETF(copy));
            put_u32(out + 100, (uint32_t)ktxTexture2_GetColorModel_e(copy));
            put_u32(out + 104, ktxTexture2_GetPremultipliedAlpha(copy) ? 1u : 0u);
            put_u32(out + 108, (uint32_t)ktxTexture2_GetPrimaries_e(copy));
            put_u32(out + 112, (uint32_t)ktxTexture2_SetTransferFunction(
                                    copy, KHR_DF_TRANSFER_LINEAR));
            put_u32(out + 116, (uint32_t)ktxTexture2_SetOETF(
                                    copy, KHR_DF_TRANSFER_LINEAR));
            put_u32(out + 120,
                    (uint32_t)ktxTexture2_SetPrimaries(copy,
                                                       KHR_DF_PRIMARIES_BT709));
            ktxTexture2_Destroy(copy);
        }
    }

    ktxTexture2_Destroy(tex);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 5. Named-file probe (temp file).                                         */
/* ======================================================================== */

/* Round trip through WriteToNamedFile / CreateFromNamedFile in %TEMP%.
 * Record (64 bytes): +0 create_rc +4 write_rc +8 read_rc +12 class_id
 * +16 data_size u64 +24 file_bytes +28 removed +32 path_len.
 * `path_out` (owned) receives the temp path used. */
int32_t x2_named_file_probe(uint8_t* out, const uint8_t* image,
                            int32_t image_len, uint8_t* path_out,
                            int32_t path_capacity)
{
    char path[512];
    const char* tmp = getenv("TEMP");
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    int32_t path_len;
    FILE* f;
    long file_bytes = -1;

    if (out == NULL || image == NULL || path_out == NULL
        || path_capacity < 16)
        return KTX_INVALID_VALUE;
    if (tmp == NULL || tmp[0] == '\0')
        tmp = ".";
    snprintf(path, sizeof(path), "%s\\xiom_ktx2_probe.ktx2", tmp);
    path_len = (int32_t)strlen(path);
    if (path_len + 1 > path_capacity)
        return KTX_INVALID_VALUE;
    memcpy(path_out, path, (size_t)path_len + 1);
    memset(out, 0, 64);
    put_u32(out + 32, (uint32_t)path_len);

    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    put_u32(out + 0, (uint32_t)rc);
    if (rc != KTX_SUCCESS)
        return rc;
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc == KTX_SUCCESS)
        rc = ktxTexture2_WriteToNamedFile(tex, path);
    put_u32(out + 4, (uint32_t)rc);
    ktxTexture2_Destroy(tex);
    if (rc != KTX_SUCCESS)
        return rc;

    f = fopen(path, "rb");
    if (f != NULL) {
        if (fseek(f, 0, SEEK_END) == 0)
            file_bytes = ftell(f);
        fclose(f);
    }
    put_u32(out + 24, (uint32_t)(file_bytes < 0 ? 0 : file_bytes));

    {
        ktxTexture2* back = NULL;
        rc = ktxTexture2_CreateFromNamedFile(path,
                                        KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
                                             &back);
        put_u32(out + 8, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            put_u32(out + 12, (uint32_t)back->classId);
            put_u64(out + 16, (uint64_t)back->dataSize);
            ktxTexture2_Destroy(back);
        }
    }
    put_u32(out + 28, (remove(path) == 0) ? 1u : 0u);
    return KTX_SUCCESS;
}

/* Deflated-image load path for file-stream textures (the only texture kind
 * upstream allows ktxTexture2_LoadDeflatedImageData on: it requires
 * prtctd->_stream.data.file != NULL and pData == NULL; the call also
 * consumes/destructs the texture's stream, so the inflated read must use a
 * SECOND texture from the same file).
 *
 * Record (96 bytes):
 *   +0 deflate_rc      +4 write_rc        +8 scheme        +12 deflated_size
 *   +16 raw_load_rc    +20 raw_match      +24 pdata_null   +28 raw_head
 *   +32 inflate_read_rc+36 inflated_mismatch +40 data_size_after u64
 *   +48 is_compressed  +52 file_bytes     +56 removed      +60 loaded_head
 *   +64 mismatch_index +68 mismatch_raw_byte +72 mismatch_loaded_byte
 * `raw` (in/out) receives the captured deflated bytes from Deflate*; the
 * deflated-load target is `inflated` (must hold both). */
int32_t x2_deflated_probe(int32_t mode, uint8_t* out, uint8_t* raw,
                          int32_t raw_capacity, uint8_t* inflated,
                          int32_t inflated_capacity, const uint8_t* image,
                          int32_t image_len)
{
    char path[512];
    const char* tmp = getenv("TEMP");
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    ktx_size_t deflated_size = 0;

    if (out == NULL || raw == NULL || inflated == NULL || image == NULL)
        return KTX_INVALID_VALUE;
    if (tmp == NULL || tmp[0] == '\0')
        tmp = ".";
    snprintf(path, sizeof(path), "%s\\xiom_ktx2_probe_def.ktx2", tmp);
    memset(out, 0, 96);

    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS)
        return rc;
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        return rc;
    }
    if (mode == 0)
        rc = ktxTexture2_DeflateZstd(tex, 3);
    else
        rc = ktxTexture2_DeflateZLIB(tex, 6);
    put_u32(out + 0, (uint32_t)rc);
    put_u32(out + 8, (uint32_t)tex->supercompressionScheme);
    put_u32(out + 48, tex->isCompressed ? 1u : 0u);
    if (rc == KTX_SUCCESS) {
        /* capture the deflated bytes Deflate* left in the texture */
        deflated_size = tex->dataSize;
        put_u32(out + 12, (uint32_t)deflated_size);
        if ((ktx_size_t)raw_capacity >= deflated_size && tex->pData != NULL)
            memcpy(raw, tex->pData, (size_t)deflated_size);
        rc = ktxTexture2_WriteToNamedFile(tex, path);
        put_u32(out + 4, (uint32_t)rc);
    }
    ktxTexture2_Destroy(tex);
    if (rc != KTX_SUCCESS) {
        remove(path);
        return rc;
    }

    /* (1) fresh read: LoadDeflatedImageData into the `inflated` buffer */
    {
        ktxTexture2* back = NULL;
        rc = ktxTexture2_CreateFromNamedFile(path, KTX_TEXTURE_CREATE_NO_FLAGS,
                                             &back);
        if (rc != KTX_SUCCESS) {
            remove(path);
            return rc;
        }
        put_u64(out + 40, (uint64_t)back->dataSize);
        {
            KTX_error_code lrc = ktxTexture2_LoadDeflatedImageData(
                back, inflated, (ktx_size_t)inflated_capacity);
            put_u32(out + 16, (uint32_t)lrc);
            put_u32(out + 24, back->pData == NULL ? 1u : 0u);
            put_u32(out + 28, (uint32_t)raw[0] | ((uint32_t)raw[1] << 8)
                             | ((uint32_t)raw[2] << 16)
                             | ((uint32_t)raw[3] << 24));
            put_u32(out + 60, (uint32_t)inflated[0]
                             | ((uint32_t)inflated[1] << 8)
                             | ((uint32_t)inflated[2] << 16)
                             | ((uint32_t)inflated[3] << 24));
            if (lrc == KTX_SUCCESS) {
                ktx_size_t i;
                ktx_size_t first_bad = (ktx_size_t)0xFFFFFFFFFFFFFFFFull;
                for (i = 0; i < deflated_size; ++i) {
                    if (inflated[i] != raw[i]) {
                        first_bad = i;
                        break;
                    }
                }
                if (first_bad == (ktx_size_t)0xFFFFFFFFFFFFFFFFull) {
                    if (deflated_size > (ktx_size_t)inflated_capacity)
                        put_u32(out + 20, 1u);
                } else {
                    put_u32(out + 20, 1u);
                    put_u32(out + 64, (uint32_t)first_bad);
                    put_u32(out + 68, (uint32_t)raw[first_bad]);
                    put_u32(out + 72, (uint32_t)inflated[first_bad]);
                }
            }
        }
        ktxTexture2_Destroy(back);
    }

    /* (2) second fresh read: LoadImageData inflates to the pixels */
    {
        ktxTexture2* back = NULL;
        rc = ktxTexture2_CreateFromNamedFile(path,
                                        KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
                                             &back);
        put_u32(out + 32, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            const ktx_uint8_t* data = ktxTexture_GetData(ktxTexture(back));
            if (data == NULL || (ktx_size_t)image_len > back->dataSize
                || memcmp(data, image, (size_t)image_len) != 0)
                put_u32(out + 36, 1u);
            ktxTexture2_Destroy(back);
        }
    }
    {
        FILE* f = fopen(path, "rb");
        long file_bytes = -1;
        if (f != NULL) {
            if (fseek(f, 0, SEEK_END) == 0)
                file_bytes = ftell(f);
            fclose(f);
        }
        put_u32(out + 52, (uint32_t)(file_bytes < 0 ? 0 : file_bytes));
    }
    put_u32(out + 56, (remove(path) == 0) ? 1u : 0u);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 6. KTX1 write + KTX1->KTX2 conversion probe.                             */
/* ======================================================================== */

/* Record (96 bytes):
 *   +0  create_rc      +4  set_rc
 *   +8  write_rc       +12 write_len u32 (low)
 *   +16 ktx2_rc        +20 ktx2_len u32 (low)
 *   +24 read_rc        +28 class_id
 *   +32 data_size u64  +40 load_rc
 *   +44 cmp_fail       +48 needs_transcoding
 *   +52 gl_internalformat +56 gl_format +60 gl_type
 *   +64 ktx2_read_rc   +68 ktx2_super
 *   +72 ktx2_vkformat  +76 level0_len
 *   +80 destroy2_ok    +84 level0_len2
 * `ktx1_bytes` and `ktx2_bytes` (owned) receive the two serializations;
 * `probe_buf` receives the loaded image bytes. */
int32_t x2_ktx1_probe(uint8_t* out, const uint8_t* image, int32_t image_len,
                      uint8_t* ktx1_bytes, int32_t ktx1_capacity,
                      uint8_t* ktx2_bytes, int32_t ktx2_capacity,
                      uint8_t* probe_buf, int32_t probe_capacity)
{
    ktxTexture1* t1 = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    ktx_uint8_t* bytes = NULL;
    ktx_size_t size = 0;

    if (out == NULL || image == NULL || ktx1_bytes == NULL
        || ktx2_bytes == NULL || probe_buf == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 96);

    memset(&info, 0, sizeof(info));
    info.glInternalformat = 0x8051; /* GL_RGB8 */
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture1_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &t1);
    put_u32(out + 0, (uint32_t)rc);
    if (rc != KTX_SUCCESS)
        return rc;
    t1->glFormat = 0x1907; /* GL_RGB */
    t1->glType = 0x1401;   /* GL_UNSIGNED_BYTE */
    rc = ktxTexture1_SetImageFromMemory(t1, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    put_u32(out + 4, (uint32_t)rc);
    if (rc != KTX_SUCCESS) {
        ktxTexture1_Destroy(t1);
        return rc;
    }
    put_u32(out + 48, ktxTexture1_NeedsTranscoding(t1) ? 1u : 0u);
    put_u32(out + 52, t1->glInternalformat);
    put_u32(out + 56, t1->glFormat);
    put_u32(out + 60, t1->glType);

    rc = ktxTexture1_WriteToMemory(t1, &bytes, &size);
    put_u32(out + 8, (uint32_t)rc);
    if (rc != KTX_SUCCESS) {
        ktxTexture1_Destroy(t1);
        return rc;
    }
    put_u32(out + 12, (uint32_t)size);
    if ((ktx_size_t)ktx1_capacity < size) {
        free(bytes);
        ktxTexture1_Destroy(t1);
        return KTX_FILE_OVERFLOW;
    }
    memcpy(ktx1_bytes, bytes, (size_t)size);
    free(bytes);
    bytes = NULL;
    size = 0;

    rc = ktxTexture1_WriteKTX2ToMemory(t1, &bytes, &size);
    put_u32(out + 16, (uint32_t)rc);
    if (rc == KTX_SUCCESS) {
        put_u32(out + 20, (uint32_t)size);
        if ((ktx_size_t)ktx2_capacity >= size)
            memcpy(ktx2_bytes, bytes, (size_t)size);
        free(bytes);
        bytes = NULL;
        size = 0;
    }

    /* read the KTX1 bytes back and load the image */
    {
        ktxTexture1* back = NULL;
        ktx_size_t ktx1_len;
        {
            uint32_t len32 = (uint32_t)out[12] | ((uint32_t)out[13] << 8)
                           | ((uint32_t)out[14] << 16)
                           | ((uint32_t)out[15] << 24);
            ktx1_len = (ktx_size_t)len32;
        }
        rc = ktxTexture1_CreateFromMemory(ktx1_bytes, ktx1_len,
                                          KTX_TEXTURE_CREATE_NO_FLAGS, &back);
        put_u32(out + 24, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            put_u32(out + 28, (uint32_t)back->classId);
            put_u64(out + 32, (uint64_t)back->dataSize);
            rc = ktxTexture1_LoadImageData(back, probe_buf,
                                           (ktx_size_t)probe_capacity);
            put_u32(out + 40, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                size_t cmp_len = (size_t)image_len;
                if (cmp_len > (size_t)probe_capacity)
                    cmp_len = (size_t)probe_capacity;
                put_u32(out + 44, memcmp(probe_buf, image, cmp_len) == 0
                                       ? 0u : 1u);
            }
            ktxTexture1_Destroy(back);
        }
    }

    /* read the KTX2 conversion back */
    {
        ktx_uint32_t ktx2_len = 0;
        ktx2_len = (uint32_t)out[20] | ((uint32_t)out[21] << 8)
                 | ((uint32_t)out[22] << 16) | ((uint32_t)out[23] << 24);
        if (ktx2_len > 0) {
            ktxTexture2* back2 = NULL;
            rc = ktxTexture2_CreateFromMemory(ktx2_bytes, (ktx_size_t)ktx2_len,
                                              KTX_TEXTURE_CREATE_NO_FLAGS,
                                              &back2);
            put_u32(out + 64, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                put_u32(out + 68, (uint32_t)back2->supercompressionScheme);
                put_u32(out + 72, back2->vkFormat);
                put_u32(out + 76,
                        (uint32_t)ktxTexture_GetLevelSize(ktxTexture(back2),
                                                          0));
                ktxTexture2_Destroy(back2);
            }
        }
    }

    put_u32(out + 80, 0); /* reserved */
    ktxTexture1_Destroy(t1);
    put_u32(out + 84, 0);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 7. ktxStream + stdio probes (custom memory stream, tmpfile).             */
/* ======================================================================== */

typedef struct kx2_memstream {
    uint8_t* base;
    size_t capacity;
    size_t size;
    size_t pos;
} kx2_memstream;

static KTX_error_code kx2_ms_read(ktxStream* str, void* dst,
                                  const ktx_size_t count)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    if (ms == NULL || dst == NULL)
        return KTX_INVALID_VALUE;
    if (ms->pos + (size_t)count > ms->size)
        return KTX_FILE_UNEXPECTED_EOF;
    memcpy(dst, ms->base + ms->pos, (size_t)count);
    ms->pos += (size_t)count;
    return KTX_SUCCESS;
}

static KTX_error_code kx2_ms_skip(ktxStream* str, const ktx_size_t count)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    if (ms == NULL)
        return KTX_INVALID_VALUE;
    if (ms->pos + (size_t)count > ms->size)
        return KTX_FILE_UNEXPECTED_EOF;
    ms->pos += (size_t)count;
    return KTX_SUCCESS;
}

static KTX_error_code kx2_ms_write(ktxStream* str, const void* src,
                                   const ktx_size_t size,
                                   const ktx_size_t count)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    size_t n;
    if (ms == NULL)
        return KTX_INVALID_VALUE;
    n = (size_t)size * (size_t)count;
    if (ms->pos + n > ms->capacity)
        return KTX_FILE_WRITE_ERROR;
    if (src != NULL)
        memcpy(ms->base + ms->pos, src, n);
    else
        memset(ms->base + ms->pos, 0, n);
    ms->pos += n;
    if (ms->pos > ms->size)
        ms->size = ms->pos;
    return KTX_SUCCESS;
}

static KTX_error_code kx2_ms_getpos(ktxStream* str, ktx_off_t* const offset)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    if (ms == NULL || offset == NULL)
        return KTX_INVALID_VALUE;
    *offset = (ktx_off_t)ms->pos;
    return KTX_SUCCESS;
}

static KTX_error_code kx2_ms_setpos(ktxStream* str, const ktx_off_t offset)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    if (ms == NULL || offset < 0 || (size_t)offset > ms->size)
        return KTX_INVALID_VALUE;
    ms->pos = (size_t)offset;
    return KTX_SUCCESS;
}

static KTX_error_code kx2_ms_getsize(ktxStream* str, ktx_size_t* const size)
{
    kx2_memstream* ms = (kx2_memstream*)str->data.custom_ptr.address;
    if (ms == NULL || size == NULL)
        return KTX_INVALID_VALUE;
    *size = (ktx_size_t)ms->size;
    return KTX_SUCCESS;
}

static void kx2_ms_destruct(ktxStream* str)
{
    /* the buffer is XIOM-owned: nothing to release (libktx calls this on
     * its private copy of the stream struct) */
    (void)str;
}

static void kx2_ms_init(ktxStream* str, kx2_memstream* ms, uint8_t* base,
                        size_t capacity)
{
    memset(str, 0, sizeof(*str));
    ms->base = base;
    ms->capacity = capacity;
    ms->size = 0;
    ms->pos = 0;
    str->read = kx2_ms_read;
    str->skip = kx2_ms_skip;
    str->write = kx2_ms_write;
    str->getpos = kx2_ms_getpos;
    str->setpos = kx2_ms_setpos;
    str->getsize = kx2_ms_getsize;
    str->destruct = kx2_ms_destruct;
    str->type = eStreamTypeCustom;
    str->data.custom_ptr.address = ms;
    str->data.custom_ptr.allocatorAddress = NULL;
    str->data.custom_ptr.size = capacity;
    str->readpos = 0;
    str->closeOnDestruct = KTX_FALSE;
}

static ktxTexture2* kx2_make_rgb_texture(const uint8_t* image,
                                         int32_t image_len)
{
    ktxTextureCreateInfo info;
    ktxTexture2* tex = NULL;
    KTX_error_code rc;
    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS)
        return NULL;
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        return NULL;
    }
    return tex;
}

static ktxTexture1* kx2_make_ktx1_texture(const uint8_t* image,
                                          int32_t image_len)
{
    ktxTextureCreateInfo info;
    ktxTexture1* tex = NULL;
    KTX_error_code rc;
    memset(&info, 0, sizeof(info));
    info.glInternalformat = 0x8051; /* GL_RGB8 */
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture1_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS)
        return NULL;
    tex->glFormat = 0x1907;
    tex->glType = 0x1401;
    rc = ktxTexture1_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        ktxTexture1_Destroy(tex);
        return NULL;
    }
    return tex;
}

/* Record (96 bytes):
 *   +0  wstream_rc        +4  wstream_len
 *   +8  rstream_rc        +12 rstream_class
 *   +16 rstream_data_size u64   +24 rstream_cmp_fail
 *   +28 stdio_write_rc    +32 stdio_base_read_rc
 *   +36 stdio_class       +40 stdio2_read_rc
 *   +44 stdio2_data_size u64    +52 stdio_rewind_rc
 *   +56 ktx1_wstream_rc   +60 ktx1_wstream_len
 *   +64 ktx1_rstream_rc   +68 ktx1_class
 *   +72 ktx1_ktx2stream_rc +76 ktx1_ktx2stream_len
 *   +80 ktx2_from_ktx1stream_rc +84 ktx2_from_ktx1_data_size u64
 *   +92 stream_getsize_ok
 * `payload` (owned, >= 4096 bytes) is split into two stream regions. */
int32_t x2_stream_probe(uint8_t* out, uint8_t* payload,
                        int32_t payload_capacity, const uint8_t* image,
                        int32_t image_len)
{
    kx2_memstream ms_a;
    kx2_memstream ms_b;
    ktxStream stream;
    uint8_t* region_a;
    uint8_t* region_b;
    size_t half;
    ktxTexture2* tex;
    ktxTexture1* tex1;

    if (out == NULL || payload == NULL || image == NULL
        || payload_capacity < 4096)
        return KTX_INVALID_VALUE;
    memset(out, 0, 96);
    half = (size_t)payload_capacity / 2;
    region_a = payload;
    region_b = payload + half;

    tex = kx2_make_rgb_texture(image, image_len);
    if (tex == NULL)
        return KTX_INVALID_VALUE;

    /* (a) ktxTexture2_WriteToStream -> ktxTexture_CreateFromStream */
    {
        KTX_error_code rc;
        size_t written;
        kx2_ms_init(&stream, &ms_a, region_a, half);
        rc = ktxTexture2_WriteToStream(tex, &stream);
        written = ms_a.size;
        put_u32(out + 0, (uint32_t)rc);
        put_u32(out + 4, (uint32_t)written);
        if (rc == KTX_SUCCESS) {
            ktxTexture* back = NULL;
            kx2_ms_init(&stream, &ms_a, region_a, half);
            ms_a.size = written; /* re-stage the written bytes for reading */
            ms_a.pos = 0;
            rc = ktxTexture_CreateFromStream(
                &stream, KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &back);
            put_u32(out + 8, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                const ktx_uint8_t* data;
                put_u32(out + 12, (uint32_t)back->classId);
                put_u64(out + 16, (uint64_t)back->dataSize);
                data = ktxTexture_GetData(back);
                if (data == NULL || (size_t)image_len > back->dataSize
                    || memcmp(data, image, (size_t)image_len) != 0)
                    put_u32(out + 24, 1u);
                ktxTexture_Destroy(back);
            }
            {
                ktx_size_t gs = 0;
                ktxStream* st = (ktxStream*)&stream;
                KTX_error_code grc = st->getsize(st, &gs);
                put_u32(out + 92, (uint32_t)(grc == KTX_SUCCESS ? gs : 0));
            }
        }
    }

    /* (b) stdio: WriteToStdioStream -> CreateFromStdioStream */
    {
        FILE* f = tmpfile();
        if (f != NULL) {
            KTX_error_code rc = ktxTexture2_WriteToStdioStream(tex, f);
            put_u32(out + 28, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                long pos = ftell(f);
                int32_t rewind_ok = (pos >= 0 && fseek(f, 0, SEEK_SET) == 0);
                put_u32(out + 52, (uint32_t)rewind_ok);
                if (rewind_ok) {
                    ktxTexture* back = NULL;
                    rc = ktxTexture_CreateFromStdioStream(
                        f, KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &back);
                    put_u32(out + 32, (uint32_t)rc);
                    if (rc == KTX_SUCCESS) {
                        put_u32(out + 36, (uint32_t)back->classId);
                        ktxTexture_Destroy(back);
                    }
                }
                if (fseek(f, 0, SEEK_SET) == 0) {
                    ktxTexture2* back2 = NULL;
                    rc = ktxTexture2_CreateFromStdioStream(
                        f, KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &back2);
                    put_u32(out + 40, (uint32_t)rc);
                    if (rc == KTX_SUCCESS) {
                        put_u64(out + 44, (uint64_t)back2->dataSize);
                        ktxTexture2_Destroy(back2);
                    }
                }
            }
            fclose(f);
        }
    }

    /* (c) KTX1 streams: WriteToStream -> CreateFromStream, and
     * WriteKTX2ToStream -> ktxTexture2_CreateFromStream */
    tex1 = kx2_make_ktx1_texture(image, image_len);
    if (tex1 != NULL) {
        KTX_error_code rc;
        size_t ktx1_written;
        size_t ktx2_written;
        kx2_ms_init(&stream, &ms_a, region_a, half);
        rc = ktxTexture1_WriteToStream(tex1, &stream);
        ktx1_written = ms_a.size;
        put_u32(out + 56, (uint32_t)rc);
        put_u32(out + 60, (uint32_t)ktx1_written);
        if (rc == KTX_SUCCESS) {
            ktxTexture1* back = NULL;
            kx2_ms_init(&stream, &ms_a, region_a, half);
            ms_a.size = ktx1_written; /* re-stage for reading */
            ms_a.pos = 0;
            rc = ktxTexture1_CreateFromStream(&stream,
                                              KTX_TEXTURE_CREATE_NO_FLAGS,
                                              &back);
            put_u32(out + 64, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                put_u32(out + 68, (uint32_t)back->classId);
                ktxTexture1_Destroy(back);
            }
        }
        kx2_ms_init(&stream, &ms_b, region_b, half);
        rc = ktxTexture1_WriteKTX2ToStream(tex1, &stream);
        ktx2_written = ms_b.size;
        put_u32(out + 72, (uint32_t)rc);
        put_u32(out + 76, (uint32_t)ktx2_written);
        if (rc == KTX_SUCCESS) {
            ktxTexture2* back2 = NULL;
            kx2_ms_init(&stream, &ms_b, region_b, half);
            ms_b.size = ktx2_written; /* re-stage for reading */
            ms_b.pos = 0;
            rc = ktxTexture2_CreateFromStream(
                &stream, KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT, &back2);
            put_u32(out + 80, (uint32_t)rc);
            if (rc == KTX_SUCCESS) {
                put_u64(out + 84, (uint64_t)back2->dataSize);
                ktxTexture2_Destroy(back2);
            }
        }
        ktxTexture1_Destroy(tex1);
    }

    ktxTexture2_Destroy(tex);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 8. Basis transcode probe.                                                */
/* ======================================================================== */

/* mode 0: ETC1S encode (CompressBasis) then TranscodeBasis(BC1_RGB)
 * mode 1: UASTC encode (CompressBasisEx) then TranscodeBasis(BC7_RGBA)
 * mode 2: ETC1S encode then TranscodeBasis(ETC1_RGB)
 * mode 3: ETC1S encode then TranscodeBasis(RGBA32)
 * Record (128 bytes):
 *   +0  encode_rc          +4  needs_transcoding
 *   +8  transcode_rc       +12 vk_format_after
 *   +16 super_after        +20 data_size_after u64
 *   +28 num_levels         +32 write2_rc
 *   +36 write2_len u32     +40 level0_size
 *   +44 num_components     +48 transcode2_rc
 *   +52 super_final        +56 is_compressed
 *   +60 encode_file_vk_format (written payload vkFormat from re-read)
 * `payload` (owned) receives the serialized transcoded KTX2. */
int32_t x2_basis_probe(int32_t mode, uint8_t* out, uint8_t* payload,
                       int32_t payload_capacity, const uint8_t* image,
                       int32_t image_len)
{
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    ktx_uint8_t* bytes = NULL;
    ktx_size_t size = 0;

    if (out == NULL || payload == NULL || image == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 128);

    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS) {
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        put_u32(out + 0, (uint32_t)rc);
        ktxTexture2_Destroy(tex);
        return rc;
    }

    if (mode == 1) {
        ktxBasisParams params;
        memset(&params, 0, sizeof(params));
        params.structSize = sizeof(params);
        params.uastc = KTX_TRUE;
        params.uastcFlags = KTX_PACK_UASTC_LEVEL_DEFAULT;
        rc = ktxTexture2_CompressBasisEx(tex, &params);
    } else {
        rc = ktxTexture2_CompressBasis(tex, 128);
    }
    put_u32(out + 0, (uint32_t)rc);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        return rc;
    }
    put_u32(out + 4, ktxTexture2_NeedsTranscoding(tex) ? 1u : 0u);

    if (mode == 1)
        rc = ktxTexture2_TranscodeBasis(tex, KTX_TTF_BC7_RGBA, 0);
    else if (mode == 2)
        rc = ktxTexture2_TranscodeBasis(tex, KTX_TTF_ETC1_RGB, 0);
    else if (mode == 3)
        rc = ktxTexture2_TranscodeBasis(tex, KTX_TTF_RGBA32, 0);
    else
        rc = ktxTexture2_TranscodeBasis(tex, KTX_TTF_BC1_RGB, 0);
    put_u32(out + 8, (uint32_t)rc);
    put_u32(out + 12, tex->vkFormat);
    put_u32(out + 16, (uint32_t)tex->supercompressionScheme);
    put_u64(out + 20, (uint64_t)tex->dataSize);
    put_u32(out + 28, tex->numLevels);
    put_u32(out + 40, (uint32_t)ktxTexture_GetLevelSize(ktxTexture(tex), 0));
    put_u32(out + 44, ktxTexture2_GetNumComponents(tex));
    put_u32(out + 56, tex->isCompressed ? 1u : 0u);

    if (rc == KTX_SUCCESS) {
        /* a second transcode of the same texture must be a typed error */
        rc = ktxTexture2_TranscodeBasis(tex, KTX_TTF_BC1_RGB, 0);
        put_u32(out + 48, (uint32_t)rc);
        put_u32(out + 52, (uint32_t)tex->supercompressionScheme);
    }

    if (mode == 0 || mode == 1) {
        rc = ktxTexture2_WriteToMemory(tex, &bytes, &size);
        put_u32(out + 32, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            put_u32(out + 36, (uint32_t)size);
            if ((ktx_size_t)payload_capacity >= size) {
                uint8_t info_record[128];
                memcpy(payload, bytes, (size_t)size);
                free(bytes);
                bytes = NULL;
                /* re-read the payload to report the serialized vkFormat */
                if (x2_read_info(payload, (int32_t)size, info_record)
                        == KTX_SUCCESS) {
                    uint32_t vk = (uint32_t)info_record[4]
                                | ((uint32_t)info_record[5] << 8)
                                | ((uint32_t)info_record[6] << 16)
                                | ((uint32_t)info_record[7] << 24);
                    put_u32(out + 60, vk);
                }
            } else {
                free(bytes);
                bytes = NULL;
            }
        }
    }

    ktxTexture2_Destroy(tex);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 8. ASTC compress/decode probe.                                           */
/* ======================================================================== */

/* Record (64 bytes):
 *   +0  compress_rc        +4  vk_after_compress
 *   +8  is_compressed      +12 data_size_after u32
 *   +16 decode_rc          +20 vk_after_decode
 *   +24 data_size_after_decode u32
 *   +28 level0_after_compress  +32 level0_after_decode
 *   +36 write_rc           +40 write_len u32
 *   +44 block_dim          +48 quality
 *   +52 decoded_copied     +56 decode_matches_input */
int32_t x2_astc_probe(uint8_t* out, uint8_t* payload, int32_t payload_capacity,
                      const uint8_t* image, int32_t image_len,
                      uint8_t* decoded, int32_t decoded_capacity)
{
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;
    ktx_uint8_t* bytes = NULL;
    ktx_size_t size = 0;
    ktxAstcParams params;

    if (out == NULL || payload == NULL || image == NULL || decoded == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 64);

    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8A8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS) {
        put_u32(out + 0, (uint32_t)rc);
        return rc;
    }
    rc = ktxTexture2_SetImageFromMemory(tex, 0, 0, 0, image,
                                        (ktx_size_t)image_len);
    if (rc != KTX_SUCCESS) {
        put_u32(out + 0, (uint32_t)rc);
        ktxTexture2_Destroy(tex);
        return rc;
    }

    memset(&params, 0, sizeof(params));
    params.structSize = sizeof(params);
    params.blockDimension = KTX_PACK_ASTC_BLOCK_DIMENSION_4x4;
    params.mode = KTX_PACK_ASTC_ENCODER_MODE_LDR;
    params.qualityLevel = KTX_PACK_ASTC_QUALITY_LEVEL_FASTEST;
    params.threadCount = 1;
    rc = ktxTexture2_CompressAstcEx(tex, &params);
    put_u32(out + 0, (uint32_t)rc);
    put_u32(out + 44, params.blockDimension);
    put_u32(out + 48, params.qualityLevel);
    if (rc != KTX_SUCCESS) {
        ktxTexture2_Destroy(tex);
        return rc;
    }
    put_u32(out + 4, tex->vkFormat);
    put_u32(out + 8, tex->isCompressed ? 1u : 0u);
    put_u32(out + 12, (uint32_t)tex->dataSize);
    put_u32(out + 28, (uint32_t)ktxTexture_GetLevelSize(ktxTexture(tex), 0));

    rc = ktxTexture2_WriteToMemory(tex, &bytes, &size);
    put_u32(out + 36, (uint32_t)rc);
    if (rc == KTX_SUCCESS) {
        put_u32(out + 40, (uint32_t)size);
        if ((ktx_size_t)payload_capacity >= size)
            memcpy(payload, bytes, (size_t)size);
        free(bytes);
        bytes = NULL;
    }

    rc = ktxTexture2_DecodeAstc(tex);
    put_u32(out + 16, (uint32_t)rc);
    put_u32(out + 20, tex->vkFormat);
    put_u32(out + 24, (uint32_t)tex->dataSize);
    put_u32(out + 32, (uint32_t)ktxTexture_GetLevelSize(ktxTexture(tex), 0));
    if (rc == KTX_SUCCESS) {
        const ktx_uint8_t* data = ktxTexture_GetData(ktxTexture(tex));
        ktx_size_t level0 = ktxTexture_GetLevelSize(ktxTexture(tex), 0);
        if (data != NULL && level0 <= (ktx_size_t)decoded_capacity) {
            memcpy(decoded, data, (size_t)level0);
            put_u32(out + 52, (uint32_t)level0);
            if ((ktx_size_t)image_len == level0
                && memcmp(decoded, image, (size_t)level0) == 0)
                put_u32(out + 56, 1u);
        }
    }

    ktxTexture2_Destroy(tex);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 9. Hash-list probe (metadata API).                                       */
/* ======================================================================== */

/* Record (96 bytes):
 *   +0  create_rc      +4  add_rc        +8  find_rc       +12 value_len
 *   +16 value[4]       +20 next_count    +24 sort_rc       +28 ser_rc
 *   +32 ser_len        +36 deser_rc      +40 find2_rc      +44 value2_len
 *   +48 value2[4]      +52 getkey_rc     +56 key_len       +60 key[4]
 *   +64 getval_rc      +68 delete_rc     +72 destroy_rc    +76 delete_entry_rc
 *   +80 copy_rc        +84 copy_entries  +88 construct_ok  +92 destruct_ok */
int32_t x2_hashlist_probe(uint8_t* out)
{
    ktxHashList* hl = NULL; /* heap list handle from ktxHashList_Create */
    ktxHashList hl_stack = NULL;
    unsigned int kvd_len = 0;
    unsigned char* kvd = NULL;
    int32_t count = 0;

    if (out == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 96);

    {
        KTX_error_code rc = ktxHashList_Create(&hl);
        put_u32(out + 0, (uint32_t)rc);
        if (rc != KTX_SUCCESS)
            return rc;
    }
    {
        KTX_error_code rc = ktxHashList_AddKVPair(hl, "xiomKeyOne", 9,
                                                  "value-one");
        put_u32(out + 4, (uint32_t)rc);
        rc = ktxHashList_AddKVPair(hl, "xiomKeyTwo", 9, "value-two");
        if (rc != KTX_SUCCESS)
            put_u32(out + 4, (uint32_t)rc);
    }
    {
        unsigned int value_len = 0;
        void* value = NULL;
        KTX_error_code rc = ktxHashList_FindValue(hl, "xiomKeyOne",
                                                  &value_len, &value);
        put_u32(out + 8, (uint32_t)rc);
        if (rc == KTX_SUCCESS && value != NULL) {
            put_u32(out + 12, value_len);
            memcpy(out + 16, value, value_len < 4 ? value_len : 4);
        }
    }
    {
        ktxHashListEntry* e = *hl;
        while (e != NULL) {
            count += 1;
            e = ktxHashList_Next(e);
        }
        put_u32(out + 20, (uint32_t)count);
    }
    put_u32(out + 24, (uint32_t)ktxHashList_Sort(hl));
    {
        KTX_error_code rc = ktxHashList_Serialize(hl, &kvd_len, &kvd);
        put_u32(out + 28, (uint32_t)rc);
        put_u32(out + 32, kvd_len);
    }
    if (kvd != NULL) {
        ktxHashList hl2 = NULL;
        KTX_error_code rc;
        ktxHashList_Construct(&hl2);
        rc = ktxHashList_Deserialize(&hl2, kvd_len, kvd);
        put_u32(out + 36, (uint32_t)rc);
        if (rc == KTX_SUCCESS) {
            ktxHashListEntry* entry = NULL;
            unsigned int vl2 = 0;
            void* v2 = NULL;
            rc = ktxHashList_FindValue(&hl2, "xiomKeyTwo", &vl2, &v2);
            put_u32(out + 40, (uint32_t)rc);
            if (rc == KTX_SUCCESS && v2 != NULL) {
                put_u32(out + 44, vl2);
                memcpy(out + 48, v2, vl2 < 4 ? vl2 : 4);
            }
            rc = ktxHashList_FindEntry(&hl2, "xiomKeyOne", &entry);
            put_u32(out + 52, (uint32_t)rc);
            if (rc == KTX_SUCCESS && entry != NULL) {
                unsigned int kl = 0;
                char* k = NULL;
                rc = ktxHashListEntry_GetKey(entry, &kl, &k);
                put_u32(out + 56, kl);
                if (rc == KTX_SUCCESS && k != NULL)
                    memcpy(out + 60, k, kl < 4 ? kl : 4);
                {
                    unsigned int vl3 = 0;
                    void* v3 = NULL;
                    rc = ktxHashListEntry_GetValue(entry, &vl3, &v3);
                    put_u32(out + 64, (uint32_t)rc);
                }
            }
        }
        ktxHashList_Destruct(&hl2);
        free(kvd);
        kvd = NULL;
    }
    /* DeleteEntry via FindEntry on the live list */
    {
        ktxHashListEntry* entry = NULL;
        KTX_error_code rc = ktxHashList_FindEntry(hl, "xiomKeyTwo", &entry);
        if (rc == KTX_SUCCESS)
            rc = ktxHashList_DeleteEntry(hl, entry);
        put_u32(out + 76, (uint32_t)rc);
    }
    put_u32(out + 68, (uint32_t)ktxHashList_DeleteKVPair(hl, "xiomKeyOne"));
    ktxHashList_Destroy(hl);
    put_u32(out + 72, 0);

    /* stack lifecycle: Construct / ConstructCopy / Destruct */
    ktxHashList_Construct(&hl_stack);
    {
        KTX_error_code rc = ktxHashList_AddKVPair(&hl_stack, "stackKey", 5,
                                                  "abcde");
        put_u32(out + 88, (uint32_t)rc);
    }
    {
        ktxHashList stack_copy = NULL;
        ktxHashList_ConstructCopy(&stack_copy, hl_stack);
        {
            ktxHashListEntry* e = stack_copy;
            int32_t n = 0;
            while (e != NULL) {
                n += 1;
                e = ktxHashList_Next(e);
            }
            put_u32(out + 84, (uint32_t)n);
        }
        ktxHashList_Destruct(&stack_copy);
    }
    ktxHashList_Destruct(&hl_stack);

    /* CreateCopy of a fresh list */
    {
        ktxHashList* src = NULL;
        ktxHashList* copy = NULL;
        KTX_error_code rc = ktxHashList_Create(&src);
        if (rc == KTX_SUCCESS) {
            ktxHashList_AddKVPair(src, "copyKey", 7, "abcdefg");
            rc = ktxHashList_CreateCopy(&copy, *src);
        }
        put_u32(out + 80, (uint32_t)rc);
        if (copy != NULL)
            ktxHashList_Destroy(copy);
        if (src != NULL)
            ktxHashList_Destroy(src);
    }
    put_u32(out + 92, 1);
    return KTX_SUCCESS;
}

/* ======================================================================== */
/* 10. Strings + GL probes.                                                 */
/* ======================================================================== */

/* Copy ktxErrorString(code) / ktxSupercompressionSchemeString(scheme) /
 * ktxTranscodeFormatString(fmt) into an owned slot. selector: 0/1/2.
 * `out_len` (u64) receives the copied byte count (excluding NUL). */
int32_t x2_c_string(int32_t selector, int32_t arg, uint8_t* dst,
                    int32_t capacity, uint8_t* out_len)
{
    const char* s;
    int32_t len;
    if (dst == NULL || out_len == NULL || capacity <= 0)
        return KTX_INVALID_VALUE;
    put_u64(out_len, 0);
    if (selector == 0)
        s = ktxErrorString((KTX_error_code)arg);
    else if (selector == 1)
        s = ktxSupercompressionSchemeString((ktxSupercmpScheme)arg);
    else if (selector == 2)
        s = ktxTranscodeFormatString((ktx_transcode_fmt_e)arg);
    else
        return KTX_INVALID_VALUE;
    len = (int32_t)strlen(s);
    if (len + 1 > capacity)
        return KTX_FILE_OVERFLOW;
    memcpy(dst, s, (size_t)len + 1);
    put_u64(out_len, (uint64_t)len);
    return KTX_SUCCESS;
}

/* Record (32 bytes): +0 load_rc +4 upload_rc +8 gl_error +12 texture
 * +16 target +20 class_id. upload_rc carries the 0xFFFFFFFF "not attempted"
 * sentinel because a failed ktxLoadOpenGL leaves no texture to upload.
 * Returns load_rc. */
int32_t x2_gl_probe(uint8_t* out)
{
    KTX_error_code load_rc;
    KTX_error_code upload_rc = KTX_INVALID_OPERATION;
    GLuint texture = 0;
    GLenum target = 0;
    GLenum gl_error = 0;
    ktxTexture2* tex = NULL;
    ktxTextureCreateInfo info;
    KTX_error_code rc;

    if (out == NULL)
        return KTX_INVALID_VALUE;
    memset(out, 0, 32);
    put_u32(out + 4, 0xFFFFFFFFu); /* upload not attempted */

    load_rc = ktxLoadOpenGL(NULL);
    put_u32(out + 0, (uint32_t)load_rc);
    if (load_rc != KTX_SUCCESS)
        return load_rc;

    memset(&info, 0, sizeof(info));
    info.vkFormat = VK_FORMAT_R8G8B8_UNORM;
    info.baseWidth = 4;
    info.baseHeight = 4;
    info.baseDepth = 1;
    info.numDimensions = 2;
    info.numLevels = 1;
    info.numLayers = 1;
    info.numFaces = 1;
    rc = ktxTexture2_Create(&info, KTX_TEXTURE_CREATE_ALLOC_STORAGE, &tex);
    if (rc != KTX_SUCCESS)
        return rc;
    /* no GL context in a console process: the upload must fail typed */
    upload_rc = ktxTexture_GLUpload(ktxTexture(tex), &texture, &target,
                                    &gl_error);
    put_u32(out + 4, (uint32_t)upload_rc);
    put_u32(out + 8, (uint32_t)gl_error);
    put_u32(out + 12, (uint32_t)texture);
    put_u32(out + 16, (uint32_t)target);
    put_u32(out + 20, (uint32_t)tex->classId);
    ktxTexture2_Destroy(tex);
    return load_rc;
}

/* ======================================================================== */
/* 11. Corrupt-input probe.                                                 */
/* ======================================================================== */

/* Record (32 bytes): +0 status +4 class_id +8 data_size u32(low)
 * +12 num_levels. */
int32_t x2_corrupt_probe(const uint8_t* src, int32_t src_len, uint8_t* out)
{
    if (out == NULL || src == NULL || src_len < 0)
        return KTX_INVALID_VALUE;
    memset(out, 0, 32);
    {
        uint8_t info[128];
        int32_t rc = x2_read_info(src, src_len, info);
        if (rc != KTX_SUCCESS) {
            put_u32(out + 0, (uint32_t)rc);
            return rc;
        }
        put_u32(out + 0, (uint32_t)KTX_SUCCESS);
        memcpy(out + 4, info + 0, 4);   /* class_id */
        memcpy(out + 8, info + 72, 4);  /* data_size low */
        memcpy(out + 12, info + 20, 4); /* num_levels */
    }
    return KTX_SUCCESS;
}
