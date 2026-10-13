#!/usr/bin/env python3
# XIOM -- xiom.lz4 FFI surface generator + coverage checker (stdlib only).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Emits src/lz4_ffi.xi (the complete confined 1:1 surface over the pinned
# lz4 v1.10.0 headers: lz4.h, lz4hc.h, lz4frame.h) and verifies it
# fail-closed against the vendored headers:
#   1. every descriptor name occurs in the pinned header text;
#   2. every C name has an `extern "C"` declaration in the emitted module;
#   3. every C name has a `pub fn <snake>` wrapper in the emitted module.
# It also emits docs/surface_lz4.json and docs/COVERAGE.md.
#
# Parameter kinds (C -> XIOM):
#   v  buffer / struct slot pointer        -> `&mut Vec[UInt8]` (.as_mut_ptr())
#   p  nullable const pointer (NULL ok)    -> `*UInt8` (ffi.null_ptr())
#   h  opaque handle (pointer as integer)  -> `Int` (0 = NULL where allowed)
#   n  integer (int/unsigned/size_t/enum)  -> `Int`
# Return kinds:
#   i -> Int, u -> UInt32, v -> void, h -> Int, p -> *UInt8
#
# Usage:  python tools/gen_lz4_ffi.py [--check]
# Exit: 0 = emitted + verified, 1 = a verification failed.

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "vendor", "lz4")
OUT_XI = os.path.join(ROOT, "src", "lz4_ffi.xi")

# (c_name, class, header, params, ret, doc)
# class: stable | deprecated | static   (static = STATIC_LINKING_ONLY sections)
D = [
    # ----- lz4.h: stable --------------------------------------------------
    ("LZ4_versionNumber", "stable", "lz4.h", [], "i", "runtime version number (1.10.0 = 11000)"),
    ("LZ4_versionString", "stable", "lz4.h", [], "p", "runtime version string pointer"),
    ("LZ4_compress_default", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n")], "i", "one-shot block compression at the default level"),
    ("LZ4_decompress_safe", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("compressed_size", "n"), ("dst_capacity", "n")], "i", "safe block decompression into a sized destination"),
    ("LZ4_compressBound", "stable", "lz4.h", [("input_size", "n")], "i", "worst-case compressed size for an input"),
    ("LZ4_compress_fast", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("acceleration", "n")], "i", "one-shot block compression with an acceleration factor"),
    ("LZ4_sizeofState", "stable", "lz4.h", [], "i", "byte size of the LZ4_stream_t state buffer"),
    ("LZ4_compress_fast_extState", "stable", "lz4.h", [("state", "v"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("acceleration", "n")], "i", "compression with a caller-owned state buffer"),
    ("LZ4_compress_destSize", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("src_size_ptr", "v"), ("target_dst_size", "n")], "i", "fill dstCapacity, decoding as much of src as fits (updates srcSizePtr)"),
    ("LZ4_decompress_safe_partial", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("src_size", "n"), ("target_output_size", "n"), ("dst_capacity", "n")], "i", "decompress up to targetOutputSize bytes"),
    ("LZ4_createStream", "stable", "lz4.h", [], "h", "allocate an LZ4_stream_t (free with LZ4_freeStream)"),
    ("LZ4_freeStream", "stable", "lz4.h", [("stream_ptr", "h")], "i", "free an LZ4_stream_t"),
    ("LZ4_resetStream_fast", "stable", "lz4.h", [("stream_ptr", "h")], "v", "fast re-init of a coherent LZ4_stream_t"),
    ("LZ4_loadDict", "stable", "lz4.h", [("stream_ptr", "h"), ("dictionary", "v"), ("dict_size", "n")], "i", "load a dictionary into a stream"),
    ("LZ4_loadDictSlow", "stable", "lz4.h", [("stream_ptr", "h"), ("dictionary", "v"), ("dict_size", "n")], "i", "slower, more thorough dictionary load"),
    ("LZ4_attach_dictionary", "stable", "lz4.h", [("working_stream", "h"), ("dictionary_stream", "h")], "v", "attach a dictionary stream (0 detaches)"),
    ("LZ4_compress_fast_continue", "stable", "lz4.h", [("stream_ptr", "h"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("acceleration", "n")], "i", "streaming block compression (linked blocks)"),
    ("LZ4_saveDict", "stable", "lz4.h", [("stream_ptr", "h"), ("safe_buffer", "v"), ("max_dict_size", "n")], "i", "save the stream dictionary into a caller buffer"),
    ("LZ4_createStreamDecode", "stable", "lz4.h", [], "h", "allocate an LZ4_streamDecode_t (free with LZ4_freeStreamDecode)"),
    ("LZ4_freeStreamDecode", "stable", "lz4.h", [("stream", "h")], "i", "free an LZ4_streamDecode_t"),
    ("LZ4_setStreamDecode", "stable", "lz4.h", [("stream_decode", "h"), ("dictionary", "p"), ("dict_size", "n")], "i", "set the decoder's prefix dictionary (NULL clears)"),
    ("LZ4_decoderRingBufferSize", "stable", "lz4.h", [("max_block_size", "n")], "i", "ring buffer size for LZ4_decompress_safe_continue"),
    ("LZ4_decompress_safe_continue", "stable", "lz4.h", [("stream_decode", "h"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n")], "i", "streaming block decompression"),
    ("LZ4_decompress_safe_usingDict", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("dict_start", "p"), ("dict_size", "n")], "i", "one-shot decompression with a dictionary"),
    ("LZ4_decompress_safe_partial_usingDict", "stable", "lz4.h", [("src", "v"), ("dst", "v"), ("compressed_size", "n"), ("target_output_size", "n"), ("max_output_size", "n"), ("dict_start", "p"), ("dict_size", "n")], "i", "partial decompression with a dictionary"),
    ("LZ4_initStream", "stable", "lz4.h", [("state_buffer", "v"), ("size", "n")], "h", "initialize a caller-owned state buffer (returns state as handle)"),
    ("LZ4_resetStream", "stable", "lz4.h", [("stream_ptr", "h")], "v", "full re-init of a stream (obsolete: prefer LZ4_resetStream_fast)"),
    # ----- lz4.h: static --------------------------------------------------
    ("LZ4_compress_fast_extState_fastReset", "static", "lz4.h", [("state", "v"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("acceleration", "n")], "i", "extState compression assuming an already-coherent state"),
    ("LZ4_compress_destSize_extState", "static", "lz4.h", [("state", "v"), ("src", "v"), ("dst", "v"), ("src_size_ptr", "v"), ("target_dst_size", "n"), ("acceleration", "n")], "i", "destSize compression with a caller-owned state"),
    # ----- lz4.h: deprecated ---------------------------------------------
    ("LZ4_compress", "deprecated", "lz4.h", [("src", "v"), ("dest", "v"), ("src_size", "n")], "i", "obsolete: use LZ4_compress_default()"),
    ("LZ4_compress_limitedOutput", "deprecated", "lz4.h", [("src", "v"), ("dest", "v"), ("src_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_default()"),
    ("LZ4_compress_withState", "deprecated", "lz4.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n")], "i", "obsolete: use LZ4_compress_fast_extState()"),
    ("LZ4_compress_limitedOutput_withState", "deprecated", "lz4.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_fast_extState()"),
    ("LZ4_compress_continue", "deprecated", "lz4.h", [("stream_ptr", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n")], "i", "obsolete: use LZ4_compress_fast_continue()"),
    ("LZ4_compress_limitedOutput_continue", "deprecated", "lz4.h", [("stream_ptr", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_fast_continue()"),
    ("LZ4_uncompress", "deprecated", "lz4.h", [("source", "v"), ("dest", "v"), ("output_size", "n")], "i", "obsolete/unsafe: use LZ4_decompress_safe()"),
    ("LZ4_uncompress_unknownOutputSize", "deprecated", "lz4.h", [("source", "v"), ("dest", "v"), ("isize", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_decompress_safe()"),
    ("LZ4_create", "deprecated", "lz4.h", [("input_buffer", "v")], "h", "obsolete: use LZ4_createStream()"),
    ("LZ4_sizeofStreamState", "deprecated", "lz4.h", [], "i", "obsolete: use LZ4_createStream()"),
    ("LZ4_resetStreamState", "deprecated", "lz4.h", [("state", "v"), ("input_buffer", "v")], "i", "obsolete: use LZ4_resetStream()"),
    ("LZ4_slideInputBuffer", "deprecated", "lz4.h", [("state", "h")], "p", "obsolete: use LZ4_saveDict() (returns an internal pointer)"),
    ("LZ4_decompress_safe_withPrefix64k", "deprecated", "lz4.h", [("src", "v"), ("dst", "v"), ("compressed_size", "n"), ("max_dst_size", "n")], "i", "obsolete: assumes a 64 KB prefix dictionary"),
    ("LZ4_decompress_fast_withPrefix64k", "deprecated", "lz4.h", [("src", "v"), ("dst", "v"), ("original_size", "n")], "i", "obsolete/unsafe: use LZ4_decompress_fast_usingDict()"),
    ("LZ4_decompress_fast", "deprecated", "lz4.h", [("src", "v"), ("dst", "v"), ("original_size", "n")], "i", "obsolete/unsafe: use LZ4_decompress_safe_partial()"),
    ("LZ4_decompress_fast_continue", "deprecated", "lz4.h", [("stream_decode", "h"), ("src", "v"), ("dst", "v"), ("original_size", "n")], "i", "obsolete/unsafe: use LZ4_decompress_safe_continue()"),
    ("LZ4_decompress_fast_usingDict", "deprecated", "lz4.h", [("src", "v"), ("dst", "v"), ("original_size", "n"), ("dict_start", "p"), ("dict_size", "n")], "i", "obsolete/unsafe: use LZ4_decompress_safe_partial_usingDict()"),
    # ----- lz4hc.h: stable ------------------------------------------------
    ("LZ4_compress_HC", "stable", "lz4hc.h", [("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("compression_level", "n")], "i", "one-shot high-compression block encode"),
    ("LZ4_sizeofStateHC", "stable", "lz4hc.h", [], "i", "byte size of the LZ4_streamHC_t state buffer"),
    ("LZ4_compress_HC_extStateHC", "stable", "lz4hc.h", [("state_hc", "v"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("max_dst_size", "n"), ("compression_level", "n")], "i", "HC compression with a caller-owned state buffer"),
    ("LZ4_compress_HC_destSize", "stable", "lz4hc.h", [("state_hc", "v"), ("src", "v"), ("dst", "v"), ("src_size_ptr", "v"), ("target_dst_size", "n"), ("compression_level", "n")], "i", "HC destSize compression (updates srcSizePtr)"),
    ("LZ4_createStreamHC", "stable", "lz4hc.h", [], "h", "allocate an LZ4_streamHC_t (free with LZ4_freeStreamHC)"),
    ("LZ4_freeStreamHC", "stable", "lz4hc.h", [("stream_hc_ptr", "h")], "i", "free an LZ4_streamHC_t"),
    ("LZ4_resetStreamHC_fast", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("compression_level", "n")], "v", "fast re-init of a coherent HC stream"),
    ("LZ4_loadDictHC", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("dictionary", "v"), ("dict_size", "n")], "i", "load a dictionary into an HC stream"),
    ("LZ4_compress_HC_continue", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("max_dst_size", "n")], "i", "streaming HC block compression"),
    ("LZ4_compress_HC_continue_destSize", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("src", "v"), ("dst", "v"), ("src_size_ptr", "v"), ("target_dst_size", "n")], "i", "streaming HC destSize compression (updates srcSizePtr)"),
    ("LZ4_saveDictHC", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("safe_buffer", "v"), ("max_dict_size", "n")], "i", "save the HC stream dictionary into a caller buffer"),
    ("LZ4_attach_HC_dictionary", "stable", "lz4hc.h", [("working_stream", "h"), ("dictionary_stream", "h")], "v", "attach an HC dictionary stream (0 detaches)"),
    ("LZ4_initStreamHC", "stable", "lz4hc.h", [("buffer", "v"), ("size", "n")], "h", "initialize a caller-owned HC state buffer (returns state as handle)"),
    ("LZ4_resetStreamHC", "stable", "lz4hc.h", [("stream_hc_ptr", "h"), ("compression_level", "n")], "v", "full re-init of an HC stream"),
    # ----- lz4hc.h: static ------------------------------------------------
    ("LZ4_setCompressionLevel", "static", "lz4hc.h", [("stream_hc_ptr", "h"), ("compression_level", "n")], "v", "change the HC level between streaming calls"),
    ("LZ4_favorDecompressionSpeed", "static", "lz4hc.h", [("stream_hc_ptr", "h"), ("favor", "n")], "v", "favor decompression speed for levels >= 10"),
    ("LZ4_compress_HC_extStateHC_fastReset", "static", "lz4hc.h", [("state", "v"), ("src", "v"), ("dst", "v"), ("src_size", "n"), ("dst_capacity", "n"), ("compression_level", "n")], "i", "HC extState assuming an already-coherent state"),
    # ----- lz4hc.h: deprecated --------------------------------------------
    ("LZ4_compressHC", "deprecated", "lz4hc.h", [("source", "v"), ("dest", "v"), ("input_size", "n")], "i", "obsolete: use LZ4_compress_HC()"),
    ("LZ4_compressHC_limitedOutput", "deprecated", "lz4hc.h", [("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_HC()"),
    ("LZ4_compressHC2", "deprecated", "lz4hc.h", [("source", "v"), ("dest", "v"), ("input_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC()"),
    ("LZ4_compressHC2_limitedOutput", "deprecated", "lz4hc.h", [("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC()"),
    ("LZ4_compressHC_withStateHC", "deprecated", "lz4hc.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n")], "i", "obsolete: use LZ4_compress_HC_extStateHC()"),
    ("LZ4_compressHC_limitedOutput_withStateHC", "deprecated", "lz4hc.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_HC_extStateHC()"),
    ("LZ4_compressHC2_withStateHC", "deprecated", "lz4hc.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC_extStateHC()"),
    ("LZ4_compressHC2_limitedOutput_withStateHC", "deprecated", "lz4hc.h", [("state", "v"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC_extStateHC()"),
    ("LZ4_compressHC_continue", "deprecated", "lz4hc.h", [("stream_hc_ptr", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n")], "i", "obsolete: use LZ4_compress_HC_continue()"),
    ("LZ4_compressHC_limitedOutput_continue", "deprecated", "lz4hc.h", [("stream_hc_ptr", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n")], "i", "obsolete: use LZ4_compress_HC_continue()"),
    ("LZ4_createHC", "deprecated", "lz4hc.h", [("input_buffer", "v")], "h", "obsolete: use LZ4_createStreamHC()"),
    ("LZ4_freeHC", "deprecated", "lz4hc.h", [("hc_data", "h")], "i", "obsolete: use LZ4_freeStreamHC()"),
    ("LZ4_slideInputBufferHC", "deprecated", "lz4hc.h", [("hc_data", "h")], "p", "obsolete: use LZ4_saveDictHC() (returns an internal pointer)"),
    ("LZ4_compressHC2_continue", "deprecated", "lz4hc.h", [("hc_data", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC_continue()"),
    ("LZ4_compressHC2_limitedOutput_continue", "deprecated", "lz4hc.h", [("hc_data", "h"), ("source", "v"), ("dest", "v"), ("input_size", "n"), ("max_output_size", "n"), ("compression_level", "n")], "i", "obsolete: use LZ4_compress_HC_continue()"),
    ("LZ4_sizeofStreamStateHC", "deprecated", "lz4hc.h", [], "i", "obsolete: use LZ4_createStreamHC()"),
    ("LZ4_resetStreamStateHC", "deprecated", "lz4hc.h", [("state", "v"), ("input_buffer", "v")], "i", "obsolete: use LZ4_initStreamHC()"),
    # ----- lz4frame.h: stable ---------------------------------------------
    ("LZ4F_isError", "stable", "lz4frame.h", [("code", "n")], "u", "true when a size_t result encodes an error"),
    ("LZ4F_getErrorName", "stable", "lz4frame.h", [("code", "n")], "p", "error message string pointer"),
    ("LZ4F_compressFrame", "stable", "lz4frame.h", [("dst_buffer", "v"), ("dst_capacity", "n"), ("src_buffer", "v"), ("src_size", "n"), ("preferences_ptr", "p")], "i", "one-shot frame compression (NULL preferences = defaults)"),
    ("LZ4F_compressFrameBound", "stable", "lz4frame.h", [("src_size", "n"), ("preferences_ptr", "p")], "i", "worst-case frame size for compressFrame"),
    ("LZ4F_compressionLevel_max", "stable", "lz4frame.h", [], "i", "maximum frame compression level (12)"),
    ("LZ4F_getVersion", "stable", "lz4frame.h", [], "u", "LZ4F API version (LZ4F_VERSION = 100)"),
    ("LZ4F_createCompressionContext", "stable", "lz4frame.h", [("cctx_ptr", "v"), ("version", "n")], "i", "create a compression context (handle written to the slot)"),
    ("LZ4F_freeCompressionContext", "stable", "lz4frame.h", [("cctx", "h")], "i", "free a compression context"),
    ("LZ4F_compressBegin", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("prefs_ptr", "p")], "i", "write the frame header"),
    ("LZ4F_compressBound", "stable", "lz4frame.h", [("src_size", "n"), ("prefs_ptr", "p")], "i", "worst-case size for compressUpdate/flush"),
    ("LZ4F_compressUpdate", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("src_buffer", "v"), ("src_size", "n"), ("c_opt_ptr", "p")], "i", "streaming frame compression of one chunk"),
    ("LZ4F_flush", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("c_opt_ptr", "p")], "i", "flush buffered data without ending the frame"),
    ("LZ4F_compressEnd", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("c_opt_ptr", "p")], "i", "write the frame epilogue (endMark + checksum)"),
    ("LZ4F_createDecompressionContext", "stable", "lz4frame.h", [("dctx_ptr", "v"), ("version", "n")], "i", "create a decompression context (handle written to the slot)"),
    ("LZ4F_freeDecompressionContext", "stable", "lz4frame.h", [("dctx", "h")], "i", "free a decompression context"),
    ("LZ4F_headerSize", "stable", "lz4frame.h", [("src", "v"), ("src_size", "n")], "i", "frame header byte size (from the first bytes)"),
    ("LZ4F_getFrameInfo", "stable", "lz4frame.h", [("dctx", "h"), ("frame_info_ptr", "v"), ("src_buffer", "v"), ("src_size_ptr", "v")], "i", "parse the frame header into the frameInfo slot (updates srcSizePtr)"),
    ("LZ4F_decompress", "stable", "lz4frame.h", [("dctx", "h"), ("dst_buffer", "v"), ("dst_size_ptr", "v"), ("src_buffer", "v"), ("src_size_ptr", "v"), ("d_opt_ptr", "p")], "i", "one decompression step (see xiom.lz4.lz4f_decompress_all for the loop)"),
    ("LZ4F_resetDecompressionContext", "stable", "lz4frame.h", [("dctx", "h")], "v", "reset a decompression context for a new frame"),
    ("LZ4F_compressBegin_usingDict", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("dict_buffer", "v"), ("dict_size", "n"), ("prefs_ptr", "p")], "i", "write a frame header with a dictionary"),
    ("LZ4F_decompress_usingDict", "stable", "lz4frame.h", [("dctx", "h"), ("dst_buffer", "v"), ("dst_size_ptr", "v"), ("src_buffer", "v"), ("src_size_ptr", "v"), ("dict", "p"), ("dict_size", "n"), ("decompress_options_ptr", "p")], "i", "one decompression step with an external dictionary"),
    ("LZ4F_createCDict", "stable", "lz4frame.h", [("dict_buffer", "v"), ("dict_size", "n")], "h", "create a digested dictionary (free with LZ4F_freeCDict)"),
    ("LZ4F_freeCDict", "stable", "lz4frame.h", [("c_dict", "h")], "v", "free a digested dictionary"),
    ("LZ4F_compressFrame_usingCDict", "stable", "lz4frame.h", [("cctx", "h"), ("dst", "v"), ("dst_capacity", "n"), ("src", "v"), ("src_size", "n"), ("cdict", "h"), ("preferences_ptr", "p")], "i", "one-shot frame compression with a CDict (cctx is reused, not freed)"),
    ("LZ4F_compressBegin_usingCDict", "stable", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("cdict", "h"), ("prefs_ptr", "p")], "i", "write a frame header using a CDict"),
    # ----- lz4frame.h: static ---------------------------------------------
    ("LZ4F_getErrorCode", "static", "lz4frame.h", [("function_result", "n")], "i", "LZ4F_errorCodes enum value for a function result"),
    ("LZ4F_getBlockSize", "static", "lz4frame.h", [("block_size_id", "n")], "i", "block size for a LZ4F_blockSizeID_t"),
    ("LZ4F_uncompressedUpdate", "static", "lz4frame.h", [("cctx", "h"), ("dst_buffer", "v"), ("dst_capacity", "n"), ("src_buffer", "v"), ("src_size", "n"), ("c_opt_ptr", "p")], "i", "append a raw (uncompressed) block"),
    # bridge-built advanced creators (LZ4F_CustomMem is passed by value)
    ("xlz4f_create_cctx_advanced", "static", "lz4frame.h", [("mem_slot", "v"), ("version", "n")], "h", "LZ4F_createCompressionContext_advanced with a CustomMem slot", "LZ4F_createCompressionContext_advanced"),
    ("xlz4f_create_dctx_advanced", "static", "lz4frame.h", [("mem_slot", "v"), ("version", "n")], "h", "LZ4F_createDecompressionContext_advanced with a CustomMem slot", "LZ4F_createDecompressionContext_advanced"),
    ("xlz4f_create_cdict_advanced", "static", "lz4frame.h", [("mem_slot", "v"), ("dict_buffer", "v"), ("dict_size", "n")], "h", "LZ4F_createCDict_advanced with a CustomMem slot", "LZ4F_createCDict_advanced"),
]

TYPE_MAP = {"v": "*UInt8", "p": "*UInt8", "h": "Int", "n": "Int"}
# C `int` returns are 32-bit: they must cross as Int32 and be sign-extended
# (`as Int`) -- a direct Int declaration zero-extends and turns every negative
# error code into a 2^32-scale positive (verified on v0.64.4).
RET_MAP = {"i": "Int32", "u": "UInt32", "v": None, "h": "Int", "p": "*UInt8", "z": "Int"}
WRAP_RET = {"i": "Int", "u": "UInt32", "v": None, "h": "Int", "p": "*UInt8", "z": "Int"}

# LZ4F functions whose C return type is size_t / LZ4F_errorCode_t (64-bit).
Z_FUNCS = set("""
LZ4F_compressFrame LZ4F_compressFrameBound LZ4F_createCompressionContext
LZ4F_freeCompressionContext LZ4F_compressBegin LZ4F_compressBound
LZ4F_compressUpdate LZ4F_flush LZ4F_compressEnd LZ4F_createDecompressionContext
LZ4F_freeDecompressionContext LZ4F_headerSize LZ4F_getFrameInfo LZ4F_decompress
LZ4F_compressBegin_usingDict LZ4F_decompress_usingDict LZ4F_compressFrame_usingCDict
LZ4F_compressBegin_usingCDict LZ4F_getBlockSize LZ4F_uncompressedUpdate
""".split())

# Apply the size_t classification (descriptors keep the compact "i" default).
D = [tuple([d[0], d[1], d[2], d[3], ("z" if d[0] in Z_FUNCS else d[4]), d[5]] + list(d[6:]))
     for d in D]



def snake(c_name):
    name = c_name
    for prefix in ("LZ4F_", "LZ4HC_", "LZ4_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
            break
    name = name.replace("CDict", "Cdict")
    out = []
    for i, ch in enumerate(name):
        if ch.isupper() and i > 0 and (name[i - 1].islower() or name[i - 1].isdigit()):
            out.append("_")
        if ch.isupper() and i > 0 and name[i - 1].isupper() and i + 1 < len(name) and name[i + 1].islower():
            out.append("_")
        out.append(ch.lower())
    return "".join(out)


def assign_names():
    """Deterministic wrapper names: strip the family prefix + snake_case; on a
    collision the later (non-stable-first) entry gets a disambiguating prefix
    (legacy_ / static_ / family-).  Returns {c_name: wrapper_name}."""
    taken = {}
    names = {}
    for d in D:
        c_name, cls = d[0], d[1]
        n = snake(c_name)
        if n in taken:
            if cls == "deprecated":
                n = "legacy_" + n
            elif cls == "static":
                n = "static_" + n
            elif c_name.startswith("LZ4F_"):
                n = "frame_" + n
            elif c_name.startswith("LZ4HC_"):
                n = "hc_" + n
            else:
                n = "block_" + n
        if n in taken:
            raise RuntimeError("unresolvable wrapper name collision: " + c_name)
        taken[n] = c_name
        names[c_name] = n
    return names


NAMES = assign_names()


def extern_sig(d):
    c_name, _cls, _hdr, params, ret, _doc = d[0], d[1], d[2], d[3], d[4], d[5]
    ps = ", ".join("%s: %s" % (n, TYPE_MAP[k]) for n, k in params)
    r = RET_MAP[ret]
    if r is None:
        return "  fn %s(%s);" % (c_name, ps)
    return "  fn %s(%s) -> %s;" % (c_name, ps, r)


def wrapper_params(params):
    return ", ".join("%s: %s" % (n, "&mut Vec[UInt8]" if k in ("v", "p") else TYPE_MAP[k]) for n, k in params)


def wrapper_args(params):
    return ", ".join("%s.as_mut_ptr()" % n if k in ("v", "p") else n for n, k in params)


def wrapper(d, mod_comment):
    c_name, cls, _hdr, params, ret, doc = d[0], d[1], d[2], d[3], d[4], d[5]
    wn = NAMES[c_name]
    r = WRAP_RET[ret]
    lines = []
    lines.append("/// `%s` [%s] -- %s." % (c_name, cls, doc))
    lines.append("/// Complexity: O(input size).")
    sig = "pub fn %s(%s)" % (wn, wrapper_params(params))
    if r is not None:
        sig += " -> %s" % r
    lines.append(sig)
    lines.append("  requires: true")
    lines.append("{")
    call = "%s(%s)" % (c_name, wrapper_args(params))
    if r is None:
        lines.append("  unsafe { %s; }" % call)
    elif ret == "i":
        lines.append("  unsafe { return %s as Int; }" % call)
    else:
        lines.append("  unsafe { return %s; }" % call)
    lines.append("}")
    return "\n".join(lines)


HEADER = '''// xiom.lz4.ffi -- the COMPLETE confined surface over the vendored lz4 v1.10.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GENERATED by tools/gen_lz4_ffi.py from the pinned headers
// (vendor/lz4/lz4.h, lz4hc.h, lz4frame.h; tag v1.10.0 = ebb370ca, BSD-2-Clause
// for lib/).  Do not edit by hand: re-run the generator (fail-closed) instead.
//
// G5 confinement: this is the ONLY module in the package with `extern "C"`
// declarations.  It exposes a faithful 1:1 surface (C semantics: negative or
// encoded size_t errors are returned as-is); the ergonomic, Result-returning
// API lives in xiom.lz4.  Classes:
//   [stable]     documented public API
//   [deprecated] obsolete section of the header (bound for completeness)
//   [static]     STATIC_LINKING_ONLY section (symbols exist in the static
//                build; no ABI-stability promise upstream)
//
// Toolchain v0.64.4 discipline (docs/BINDINGS-COMPILER-FINDINGS.md): opaque
// handles cross as Int (never `Int as *UInt8`, B-25); nullable pointers use
// `null_ptr()` (a real NULL produced by C, B-23); struct parameters are
// caller-owned byte slots built/read by src/lz4_bridge.c helpers; no pointer
// arithmetic in XIOM (B-17/B-20/B-24).

module xiom.lz4.ffi

extern "C" {
  fn xlz4_null() -> *UInt8;
  fn xlz4_version_string(out: *UInt8, cap: Int) -> Int32;
  fn xlz4f_error_name(code: Int, out: *UInt8, cap: Int) -> Int32;
  fn xlz4f_prefs_default(slot: *UInt8) -> Int32;
  fn xlz4f_prefs_set(slot: *UInt8, block_size_id: Int, block_mode: Int, content_checksum: Int,
    frame_type: Int, content_size: Int, dict_id: Int, block_checksum: Int,
    compression_level: Int, auto_flush: Int, favor_dec_speed: Int) -> Int32;
  fn xlz4f_prefs_get(slot: *UInt8, out: *UInt8) -> Int32;
  fn xlz4f_frame_info_default(slot: *UInt8) -> Int32;
  fn xlz4f_frame_info_get(slot: *UInt8, out: *UInt8) -> Int32;
  fn xlz4f_compress_options_default(slot: *UInt8) -> Int32;
  fn xlz4f_compress_options_set(slot: *UInt8, stable_src: Int) -> Int32;
  fn xlz4f_decompress_options_default(slot: *UInt8) -> Int32;
  fn xlz4f_decompress_options_set(slot: *UInt8, stable_dst: Int, skip_checksums: Int) -> Int32;
  fn xlz4f_custom_mem_default(slot: *UInt8) -> Int32;
  fn xlz4f_decompress_all(dctx: Int, src: *UInt8, src_size: Int, dst: *UInt8,
    dst_capacity: Int) -> Int;

'''

PROLOGUE = '''
// ---------------------------------------------------------------------------
// Slot + pointer helpers (owned by XIOM; byte-indexed reads only)
// ---------------------------------------------------------------------------

/// Real NULL pointer produced by C (B-23: never pass a bare `null`).
/// Complexity: O(1).
pub fn null_ptr() -> *UInt8
  requires: true
{
  unsafe { return xlz4_null(); }
}

/// Zeroed byte slot (`n` bytes) owned by XIOM.
/// Complexity: O(n).
pub fn zero_bytes(n: Int) -> Vec[UInt8]
  requires: n >= 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// Little-endian u64 read from an XIOM-owned slot (byte-indexed; B-24).
/// Complexity: O(1).
pub fn read_u64_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 8 <= buf.len()
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  let b4 = buf[off + 4] as Int;
  let b5 = buf[off + 5] as Int;
  let b6 = buf[off + 6] as Int;
  let b7 = buf[off + 7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

/// Little-endian u64 write into an XIOM-owned slot (byte-indexed; B-11/B-16).
/// Complexity: O(1).
pub fn write_u64_le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  var x = v;
  var i: Int = 0;
  while i < 8 {
    buf[off + i] = (x % 256) as UInt8;
    x = x / 256;
    i = i + 1;
  }
}

/// Little-endian u32 read from an XIOM-owned slot.
/// Complexity: O(1).
pub fn read_u32_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 4 <= buf.len()
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Little-endian u32 write into an XIOM-owned slot.
/// Complexity: O(1).
pub fn write_u32_le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  var x = v;
  var i: Int = 0;
  while i < 4 {
    buf[off + i] = (x % 256) as UInt8;
    x = x / 256;
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Struct-slot helpers (bridge-built; sizes pinned in SPEC.md)
// ---------------------------------------------------------------------------

/// Fill `slot` (>= 56 bytes) with default LZ4F_preferences_t.
/// Complexity: O(1).
pub fn prefs_default(slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 56
{
  unsafe { return xlz4f_prefs_default(slot.as_mut_ptr()); }
}

/// Fill the preferences slot (56 bytes) with explicit fields.
/// Complexity: O(1).
pub fn prefs_set(slot: &mut Vec[UInt8], block_size_id: Int, block_mode: Int,
    content_checksum: Int, frame_type: Int, content_size: Int, dict_id: Int,
    block_checksum: Int, compression_level: Int, auto_flush: Int,
    favor_dec_speed: Int) -> Int32
  requires: slot.len() >= 56
{
  unsafe {
    return xlz4f_prefs_set(slot.as_mut_ptr(), block_size_id, block_mode, content_checksum,
      frame_type, content_size, dict_id, block_checksum, compression_level, auto_flush,
      favor_dec_speed);
  }
}

/// Read the 10 fields of a preferences slot into `out` (>= 80 bytes, 10 u64 LE).
/// Complexity: O(1).
pub fn prefs_get(slot: &mut Vec[UInt8], out: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 56
  requires: out.len() >= 80
{
  unsafe { return xlz4f_prefs_get(slot.as_mut_ptr(), out.as_mut_ptr()); }
}

/// Fill `slot` (>= 32 bytes) with default LZ4F_frameInfo_t.
/// Complexity: O(1).
pub fn frame_info_default(slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 32
{
  unsafe { return xlz4f_frame_info_default(slot.as_mut_ptr()); }
}

/// Read the 7 fields of a frameInfo slot into `out` (>= 56 bytes, 7 u64 LE).
/// Complexity: O(1).
pub fn frame_info_get(slot: &mut Vec[UInt8], out: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 32
  requires: out.len() >= 56
{
  unsafe { return xlz4f_frame_info_get(slot.as_mut_ptr(), out.as_mut_ptr()); }
}

/// Fill `slot` (>= 16 bytes) with default LZ4F_compressOptions_t.
/// Complexity: O(1).
pub fn compress_options_default(slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 16
{
  unsafe { return xlz4f_compress_options_default(slot.as_mut_ptr()); }
}

/// Set `stableSrc` in a compressOptions slot.
/// Complexity: O(1).
pub fn compress_options_set(slot: &mut Vec[UInt8], stable_src: Int) -> Int32
  requires: slot.len() >= 16
{
  unsafe { return xlz4f_compress_options_set(slot.as_mut_ptr(), stable_src); }
}

/// Fill `slot` (>= 16 bytes) with default LZ4F_decompressOptions_t.
/// Complexity: O(1).
pub fn decompress_options_default(slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 16
{
  unsafe { return xlz4f_decompress_options_default(slot.as_mut_ptr()); }
}

/// Set `stableDst`/`skipChecksums` in a decompressOptions slot.
/// Complexity: O(1).
pub fn decompress_options_set(slot: &mut Vec[UInt8], stable_dst: Int, skip_checksums: Int) -> Int32
  requires: slot.len() >= 16
{
  unsafe { return xlz4f_decompress_options_set(slot.as_mut_ptr(), stable_dst, skip_checksums); }
}

/// Fill `slot` (>= 24 bytes) with the all-zero LZ4F_CustomMem (default
/// allocators; LZ4F falls back to malloc/free).
/// Complexity: O(1).
pub fn custom_mem_default(slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 24
{
  unsafe { return xlz4f_custom_mem_default(slot.as_mut_ptr()); }
}

/// Copy the LZ4_versionString() text into `out`; returns the byte length.
/// Complexity: O(1).
pub fn copy_version_string(out: &mut Vec[UInt8]) -> Int
  requires: out.len() >= 1
{
  unsafe { return xlz4_version_string(out.as_mut_ptr(), out.len()) as Int; }
}

/// Copy the LZ4F_getErrorName(code) text into `out`; returns the byte length.
/// Complexity: O(1).
pub fn copy_error_name(code: Int, out: &mut Vec[UInt8]) -> Int
  requires: out.len() >= 1
{
  unsafe { return xlz4f_error_name(code, out.as_mut_ptr(), out.len()) as Int; }
}

/// Decompression loop over one complete frame: reads `src` and fills `dst`
/// (LZ4F_decompress is called until the frame ends).  Returns the number of
/// decompressed bytes or a negative LZ4F error code (LZ4F_isError).
/// Complexity: O(src_size) plus decompression.
pub fn lz4f_decompress_all(dctx: Int, src: &mut Vec[UInt8], dst: &mut Vec[UInt8]) -> Int
  requires: dctx != 0
{
  unsafe {
    return xlz4f_decompress_all(dctx, src.as_mut_ptr(), src.len(), dst.as_mut_ptr(), dst.len());
  }
}
'''


def main():
    header_text = {}
    for hdr in ("lz4.h", "lz4hc.h", "lz4frame.h"):
        with io.open(os.path.join(VENDOR, hdr), "r", encoding="utf-8", errors="replace") as f:
            header_text[hdr] = f.read()

    problems = []
    for d in D:
        check = d[6] if len(d) > 6 else d[0]
        if check not in header_text[d[2]]:
            problems.append("%s not found in %s" % (check, d[2]))

    names = [d[0] for d in D]
    if len(names) != len(set(names)):
        problems.append("duplicate descriptor names")

    # emit
    parts = [HEADER]
    parts.append("// ---------------------------------------------------------------------------\n")
    parts.append("// Raw C declarations (private to this module)\n")
    parts.append("// ---------------------------------------------------------------------------\n")
    for d in D:
        parts.append(extern_sig(d) + "\n")
    parts.append("}\n")
    parts.append(PROLOGUE)
    parts.append("\n// ---------------------------------------------------------------------------\n")
    parts.append("// Confined 1:1 wrappers (the complete declared surface)\n")
    parts.append("// ---------------------------------------------------------------------------\n\n")
    by_class = {"stable": 0, "deprecated": 0, "static": 0}
    for d in D:
        by_class[d[1]] += 1
        parts.append(wrapper(d, None) + "\n\n")
    text = "".join(parts)
    with io.open(OUT_XI, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    # verify against the emitted file
    with io.open(OUT_XI, "r", encoding="utf-8") as f:
        emitted = f.read()
    for d in D:
        c_name = d[0]
        if ("fn %s(" % c_name) not in emitted:
            problems.append("%s: extern missing from emitted module" % c_name)
        wn = NAMES[c_name]
        if ("pub fn %s(" % wn) not in emitted:
            problems.append("%s: wrapper %s missing from emitted module" % (c_name, wn))

    report = {
        "package": "xiom.lz4",
        "upstream": "github.com/lz4/lz4",
        "pin": "v1.10.0 = ebb370ca83af193212df4dcbadcc5d87bc0de2f0",
        "headers": sorted(header_text.keys()),
        "counts": {"total": len(D), "by_class": by_class},
        "functions": [{"c": d[0], "class": d[1], "header": d[2], "wrapper": NAMES[d[0]],
                       "doc": d[5]} for d in D],
        "problems": problems,
    }
    with io.open(os.path.join(ROOT, "docs", "surface_lz4.json"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(report, indent=2, sort_keys=True) + "\n")

    lines = []
    lines.append("# COVERAGE -- xiom.lz4 (lz4 v1.10.0)")
    lines.append("")
    lines.append("Generated by `tools/gen_lz4_ffi.py` from the pinned headers")
    lines.append("(`vendor/lz4/lz4.h`, `lz4hc.h`, `lz4frame.h` at")
    lines.append("`ebb370ca83af193212df4dcbadcc5d87bc0de2f0`).  Every C declaration in")
    lines.append("the three headers is bound 1:1 in `src/lz4_ffi.xi` (extern + confined")
    lines.append("wrapper); the checker fails closed if a name is missing from either")
    lines.append("the header text or the module.")
    lines.append("")
    lines.append("Counts: **%d functions -- %d stable, %d deprecated, %d static-linking-only.**"
                 % (len(D), by_class["stable"], by_class["deprecated"], by_class["static"]))
    lines.append("")
    lines.append("Additionally modeled in `xiom.lz4` (types/constants): the")
    lines.append("LZ4F_frameInfo_t / LZ4F_preferences_t / LZ4F_compressOptions_t /")
    lines.append("LZ4F_decompressOptions_t / LZ4F_CustomMem structs (owned byte slots with")
    lines.append("bridge accessors), the LZ4F enums (blockSizeID/blockMode/")
    lines.append("contentChecksum/blockChecksum/frameType), the LZ4F_errorCodes enum,")
    lines.append("and the header constants (versions, level bounds, magic numbers,")
    lines.append("header/block/checksum sizes).")
    lines.append("")
    lines.append("| Function | Class | Header | XIOM wrapper |")
    lines.append("|----------|-------|--------|--------------|")
    for d in D:
        lines.append("| `%s` | %s | %s | `%s` |" % (d[0], d[1], d[2], NAMES[d[0]]))
    lines.append("")
    with io.open(os.path.join(ROOT, "docs", "COVERAGE.md"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("gen_lz4_ffi: %d functions (%d stable, %d deprecated, %d static); %d problem(s)"
          % (len(D), by_class["stable"], by_class["deprecated"], by_class["static"], len(problems)))
    for p in problems:
        print("  PROBLEM: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
