/* xiom.basisu compile unit -- MIT OR Apache-2.0 (this file), XIOM Authors.
 *
 * The vendored basis_universal v2_50 (commit 9bebe167; Apache-2.0 + zstd
 * BSD-3) is compiled TU by TU via port.args.json; this file adds the
 * `extern "C"` probe bridge the XIOM module calls (basisu.xi).  The upstream
 * C API (encoder/basisu_wasm_api.h, encoder/basisu_wasm_transcoder_api.h)
 * speaks in `uint64_t` "wasm memory offsets" which on native builds are plain
 * pointer values (basisu_wasm_*_api.cpp: wasm_ptr = (uint8_t*)(uintptr_t)ofs).
 *
 * Buffer discipline (B-20/B-24): XIOM never reads through a C-owned pointer.
 * The bridge is the only place foreign memory is touched, and every crossing
 * follows a safe direction:
 *   - C reads XIOM-owned inputs (source RGBA, KTX2 payload) by pointer.
 *   - C writes into XIOM-owned outputs (KTX2 bytes, transcode blocks) by
 *     pointer; the XIOM side reads those bytes back byte-indexed.
 *   - The one C-owned region (comp_params' compressed data) is memcpy'd into
 *     an XIOM-owned slot inside the bridge and never handed out.
 * Out-params are 4-byte little-endian slots in XIOM-owned memory; helpers
 * write them byte-wise (B-11/B-16/B-17 discipline).  Handles and transcode
 * state never leave the bridge.
 *
 * Entry points (all return int32_t rc; rc 0 = success):
 *
 *   xbu_alloc_probe(o_bt_ok, o_bu_ok)
 *       bt_alloc/bu_alloc round trip (write+read+free inside C).
 *
 *   xbu_encode_probe(img, w, h, basis_fmt, flags, quality, effort,
 *                    out, out_cap, o_size, o_copy_ok)
 *       bu_* C API: new_comp_params -> set_image_rgba32 -> compress_texture
 *       -> get_comp_data_size/ofs -> memcpy into XIOM `out`.  rc: 1 init,
 *       2 set_image, 3 compress, 4 zero size, 5 capacity.
 *
 *   xbu_info_probe(ktx2, len, slots, slots_bytes)
 *       30 u32 slots: 0=open,4=w,8=h,12=levels,16=faces,20=layers,24=basis_fmt,
 *       28=is_etc1s,32=is_uastc_ldr_4x4,36=is_ldr,40=is_hdr,44=is_hdr_4x4,
 *       48=is_hdr_6x6,52=is_astc_ldr,56=is_xuastc_ldr,60=is_xubc7,64=is_srgb,
 *       68=has_alpha,72=is_video,76=block_w,80=block_h,84=deblock_index,
 *       88=dfd_color_model,92=dfd_primaries,96=dfd_transfer_func,100=dfd_flags,
 *       104=dfd_total_samples,108=dfd_channel_id0,112=dfd_channel_id1,
 *       116=upconversion_nit_milli,120=start_transcoding_ok.  rc 0 always
 *       (open failure is slot 0 == 0).  Requires slots_bytes >= 128.
 *
 *   xbu_level_probe(ktx2, len, level, slots, slots_bytes)
 *       9 u32 slots: 0=ok,4=orig_w,8=orig_h,12=actual_w,16=actual_h,
 *       20=blocks_x,24=blocks_y,28=total_blocks,32=alpha,36=iframe.
 *       Requires slots_bytes >= 40.
 *
 *   xbu_transcode_probe(ktx2, len, level, fmt, out, out_cap, o_size, o_flags)
 *       open -> start_transcoding -> create_transcode_state ->
 *       transcode_image_level -> destroy_state -> close.  o_flags bit0 =
 *       transcode ok, bit1 = start ok, bit2 = handle opened.  rc: 0 ran,
 *       1 invalid payload (open failed, o_flags=0), 2 slots NULL, 3 capacity.
 *       o_size = required byte size for (fmt, level) on success (0 else).
 *
 *   xbu_truncate_ok(ktx2, len) -> int32_t
 *       bt_ktx2_open on an XIOM-owned prefix; 1 = opened (then closed).
 *       Used by the corrupt/truncation tests through xbu_info_probe instead;
 *       kept for direct open/close coverage.
 */

#include "../vendor/encoder/basisu_wasm_api.h"
#include "../vendor/encoder/basisu_wasm_transcoder_api.h"

#include <stdint.h>
#include <string.h>

namespace
{
void put_u32(uint8_t* slot, uint32_t v)
{
	if (!slot)
		return;
	slot[0] = (uint8_t)(v & 0xFF);
	slot[1] = (uint8_t)((v >> 8) & 0xFF);
	slot[2] = (uint8_t)((v >> 16) & 0xFF);
	slot[3] = (uint8_t)((v >> 24) & 0xFF);
}

void* wasm_ptr(uint64_t ofs)
{
	return (void*)(uintptr_t)ofs;
}

uint64_t wasm_ofs(const void* p)
{
	return (uint64_t)(uintptr_t)p;
}
} // namespace

extern "C" {

/* bt_alloc/bu_alloc -> write -> read -> free, all inside C.  The allocated
 * region is C-owned and never handed to XIOM (B-20). */
int32_t xbu_alloc_probe(uint8_t* o_bt_ok, uint8_t* o_bu_ok)
{
	static const char kProbe[] = "XIOM-BASISU";
	const size_t kLen = sizeof(kProbe); /* includes NUL */

	uint32_t bt_ok = 0;
	uint64_t bt_ofs = bt_alloc((uint64_t)kLen);
	if (bt_ofs)
	{
		uint8_t* p = (uint8_t*)wasm_ptr(bt_ofs);
		memcpy(p, kProbe, kLen);
		bt_ok = (memcmp(p, kProbe, kLen) == 0) ? 1u : 0u;
		bt_free(bt_ofs);
	}
	put_u32(o_bt_ok, bt_ok);

	uint32_t bu_ok = 0;
	uint64_t bu_ofs = bu_alloc((uint64_t)kLen);
	if (bu_ofs)
	{
		uint8_t* p = (uint8_t*)wasm_ptr(bu_ofs);
		memcpy(p, kProbe, kLen);
		bu_ok = (memcmp(p, kProbe, kLen) == 0) ? 1u : 0u;
		bu_free(bu_ofs);
	}
	put_u32(o_bu_ok, bu_ok);

	return 0;
}

/* Encode an XIOM-owned RGBA32 image to a KTX2 payload via the bu_* C API and
 * copy the result into the XIOM-owned `out` slot. */
int32_t xbu_encode_probe(const uint8_t* img, uint32_t w, uint32_t h,
	uint32_t basis_fmt, uint32_t flags, int32_t quality, int32_t effort,
	uint8_t* out, uint32_t out_cap, uint8_t* o_size, uint8_t* o_copy_ok)
{
	put_u32(o_size, 0);
	put_u32(o_copy_ok, 0);

	if (!img || !out || !w || !h)
		return 6;

	/* Idempotent upstream (g_library_initialized guard). */
	bu_init();

	const uint32_t pitch = w * 4u;
	if (pitch / 4u != w)
		return 6;

	uint64_t params = bu_new_comp_params();
	if (!params)
		return 1;

	int32_t rc = 0;
	do
	{
		if (!bu_comp_params_set_image_rgba32(params, 0, wasm_ofs(img), w, h, pitch))
		{
			rc = 2;
			break;
		}

		if (!bu_compress_texture(params, basis_fmt, quality, effort, (uint64_t)flags, 0.0f))
		{
			rc = 3;
			break;
		}

		uint64_t size = bu_comp_params_get_comp_data_size(params);
		if (!size || size > 0xFFFFFFFFull)
		{
			rc = 4;
			break;
		}

		if ((uint64_t)out_cap < size)
		{
			rc = 5;
			break;
		}

		uint64_t ofs = bu_comp_params_get_comp_data_ofs(params);
		if (!ofs)
		{
			rc = 4;
			break;
		}

		/* C-owned comp_params bytes -> XIOM-owned slot. */
		memcpy(out, wasm_ptr(ofs), (size_t)size);
		put_u32(o_size, (uint32_t)size);
		put_u32(o_copy_ok, 1);
	} while (0);

	bu_delete_comp_params(params);

	return rc;
}

/* Open a KTX2 payload, collect the full metadata surface, start transcoding
 * and close.  All 30 values land in distinct 4-byte slots. */
int32_t xbu_info_probe(const uint8_t* ktx2, uint32_t len, uint8_t* slots, uint32_t slots_bytes)
{
	if (!ktx2 || !slots || slots_bytes < 128u)
		return 2;

	memset(slots, 0, 128);

	uint64_t handle = bt_ktx2_open(wasm_ofs(ktx2), len);
	if (!handle)
		return 0; /* slot 0 stays 0: invalid/truncated payload */

	put_u32(slots + 0, 1);
	put_u32(slots + 4, bt_ktx2_get_width(handle));
	put_u32(slots + 8, bt_ktx2_get_height(handle));
	put_u32(slots + 12, bt_ktx2_get_levels(handle));
	put_u32(slots + 16, bt_ktx2_get_faces(handle));
	put_u32(slots + 20, bt_ktx2_get_layers(handle));
	put_u32(slots + 24, bt_ktx2_get_basis_tex_format(handle));
	put_u32(slots + 28, bt_ktx2_is_etc1s(handle));
	put_u32(slots + 32, bt_ktx2_is_uastc_ldr_4x4(handle));
	put_u32(slots + 36, bt_ktx2_is_ldr(handle));
	put_u32(slots + 40, bt_ktx2_is_hdr(handle));
	put_u32(slots + 44, bt_ktx2_is_hdr_4x4(handle));
	put_u32(slots + 48, bt_ktx2_is_hdr_6x6(handle));
	put_u32(slots + 52, bt_ktx2_is_astc_ldr(handle));
	put_u32(slots + 56, bt_ktx2_is_xuastc_ldr(handle));
	put_u32(slots + 60, bt_ktx2_is_xubc7(handle));
	put_u32(slots + 64, bt_ktx2_is_srgb(handle));
	put_u32(slots + 68, bt_ktx2_has_alpha(handle));
	put_u32(slots + 72, bt_ktx2_is_video(handle));
	put_u32(slots + 76, bt_ktx2_get_block_width(handle));
	put_u32(slots + 80, bt_ktx2_get_block_height(handle));
	put_u32(slots + 84, bt_ktx2_get_deblocking_filter_index(handle));
	put_u32(slots + 88, bt_ktx2_get_dfd_color_model(handle));
	put_u32(slots + 92, bt_ktx2_get_dfd_color_primaries(handle));
	put_u32(slots + 96, bt_ktx2_get_dfd_transfer_func(handle));
	put_u32(slots + 100, bt_ktx2_get_dfd_flags(handle));
	put_u32(slots + 104, bt_ktx2_get_dfd_total_samples(handle));
	put_u32(slots + 108, bt_ktx2_get_dfd_channel_id0(handle));
	put_u32(slots + 112, bt_ktx2_get_dfd_channel_id1(handle));

	float nit = bt_ktx2_get_ldr_hdr_upconversion_nit_multiplier(handle);
	uint32_t nit_milli = 0;
	if (nit > 0.0f && nit < 4294967.0f)
		nit_milli = (uint32_t)(nit * 1000.0f + 0.5f);
	put_u32(slots + 116, nit_milli);

	put_u32(slots + 120, bt_ktx2_start_transcoding(handle) ? 1u : 0u);

	bt_ktx2_close(handle);

	return 0;
}

/* Per-level probe: all bt_ktx2_get_level_* getters for one level. */
int32_t xbu_level_probe(const uint8_t* ktx2, uint32_t len, uint32_t level, uint8_t* slots, uint32_t slots_bytes)
{
	if (!ktx2 || !slots || slots_bytes < 40u)
		return 2;

	memset(slots, 0, 40);

	uint64_t handle = bt_ktx2_open(wasm_ofs(ktx2), len);
	if (!handle)
		return 1;

	if (!bt_ktx2_start_transcoding(handle))
	{
		bt_ktx2_close(handle);
		return 3;
	}

	uint32_t ow = bt_ktx2_get_level_orig_width(handle, level, 0, 0);
	uint32_t oh = bt_ktx2_get_level_orig_height(handle, level, 0, 0);
	uint32_t aw = bt_ktx2_get_level_actual_width(handle, level, 0, 0);
	uint32_t ah = bt_ktx2_get_level_actual_height(handle, level, 0, 0);
	uint32_t bx = bt_ktx2_get_level_num_blocks_x(handle, level, 0, 0);
	uint32_t by = bt_ktx2_get_level_num_blocks_y(handle, level, 0, 0);
	uint32_t tb = bt_ktx2_get_level_total_blocks(handle, level, 0, 0);
	uint32_t al = bt_ktx2_get_level_alpha_flag(handle, level, 0, 0);
	uint32_t ifr = bt_ktx2_get_level_iframe_flag(handle, level, 0, 0);

	bt_ktx2_close(handle);

	put_u32(slots + 0, (ow && oh) ? 1u : 0u);
	put_u32(slots + 4, ow);
	put_u32(slots + 8, oh);
	put_u32(slots + 12, aw);
	put_u32(slots + 16, ah);
	put_u32(slots + 20, bx);
	put_u32(slots + 24, by);
	put_u32(slots + 28, tb);
	put_u32(slots + 32, al);
	put_u32(slots + 36, ifr);

	return 0;
}

/* Transcode one level to one target format into an XIOM-owned output. */
int32_t xbu_transcode_probe(const uint8_t* ktx2, uint32_t len, uint32_t level, uint32_t fmt,
	uint8_t* out, uint32_t out_cap, uint8_t* o_size, uint8_t* o_flags)
{
	put_u32(o_size, 0);
	put_u32(o_flags, 0);

	if (!ktx2 || !out || !o_size || !o_flags)
		return 2;

	uint64_t handle = bt_ktx2_open(wasm_ofs(ktx2), len);
	if (!handle)
		return 1; /* o_flags stays 0: invalid payload */

	uint32_t flags = 1u; /* bit0 = handle opened */

	if (!bt_ktx2_start_transcoding(handle))
	{
		bt_ktx2_close(handle);
		put_u32(o_flags, flags);
		return 4;
	}
	flags |= 2u;

	uint32_t ow = bt_ktx2_get_level_orig_width(handle, level, 0, 0);
	uint32_t oh = bt_ktx2_get_level_orig_height(handle, level, 0, 0);
	uint32_t bytes = bt_basis_compute_transcoded_image_size_in_bytes(fmt, ow, oh);
	uint32_t bpp = bt_basis_get_bytes_per_block_or_pixel(fmt);

	if (!ow || !oh || !bytes || !bpp || (uint64_t)bytes > (uint64_t)out_cap)
	{
		bt_ktx2_close(handle);
		put_u32(o_flags, flags);
		put_u32(o_size, bytes); /* required size for the caller's error text */
		return 3;
	}

	uint64_t state = bt_ktx2_create_transcode_state();

	/* Upstream C-wrapper finding: bt_ktx2_create_transcode_state() value-
	 * initializes ktx2_transcoder_state, so m_uncomp_data_level_index starts
	 * at 0 (not -1 as ktx2_transcoder_state::clear() sets).  Transcoding
	 * level 0 of a KTX2_SS_ZSTANDARD payload with such a fresh state skips
	 * the level decompression cache and trips the transcode assert
	 * (basisu_transcoder.cpp: uncomp_level_data_size ==
	 * m_uncompressed_byte_length).  The state handle is still created and
	 * destroyed here to cover both C API functions, but the transcode itself
	 * runs through the transcoder's internal default state (cleared by
	 * ktx2_transcoder::init), i.e. state_handle = 0, which is documented as
	 * valid ("thread local state: can be 0"). */
	uint32_t ok = bt_ktx2_transcode_image_level(
		handle,
		level, 0, 0,
		wasm_ofs(out),
		bytes / bpp, /* blocks or pixels, not bytes */
		fmt,
		0,          /* decode_flags */
		0, 0,       /* output_row_pitch / output_rows */
		-1, -1,     /* channel0 / channel1 */
		0);         /* internal default state (see note above) */

	if (state)
		bt_ktx2_destroy_transcode_state(state);

	bt_ktx2_close(handle);

	if (ok)
	{
		flags |= 4u;
		put_u32(o_size, bytes);
	}
	put_u32(o_flags, flags);

	return 0;
}

/* Open/close coverage on an arbitrary XIOM-owned prefix. */
int32_t xbu_open_probe(const uint8_t* data, uint32_t len)
{
	if (!data || !len)
		return 0;

	uint64_t handle = bt_ktx2_open(wasm_ofs(data), len);
	if (!handle)
		return 0;

	bt_ktx2_close(handle);
	return 1;
}

} // extern "C"
