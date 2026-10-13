// xiom.basisu conformance suite -- vendored basis_universal v2_50 (9bebe167).
//
// Proves the real binding against the vendored encoder + transcoder compiled
// into the test binary:
//   scripts/port.ps1 -Package xiom.basisu -TimeoutSec 1200
// (port.args.json passes the C API TUs, the encoder, the transcoder and
// zstd as --c-source with --cxx-standard 17).
//
// Coverage: version pin (250/250), allocator round trip, the full format
// helper surface, a real UASTC LDR 4x4 encode -> KTX2 (mips generated),
// metadata, per-level info, transcode to BC1/ETC1/ASTC/RGBA32 (mip chain
// dims + byte sizes), RGBA32 content check against the source image, typed
// errors for corrupt/truncated payloads, an ETC1S encode pipeline and a
// zstd-supercompressed UASTC payload (exercises the vendored zstd decode).

module basisu_conformance

use xiom.io;
use xiom.convert;
use xiom.basisu;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Deterministic 32x32 RGBA gradient: r=x*8, g=y*8, b=(x+y)*4, a=255.
fn build_source_rgba(w: Int, h: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var y: Int = 0;
  while y < h {
    var x: Int = 0;
    while x < w {
      v.push(((x * 8) % 256) as UInt8);
      v.push(((y * 8) % 256) as UInt8);
      v.push((((x + y) * 4) % 256) as UInt8);
      v.push(255 as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  return v;
}

fn abs_diff_i(a: Int, b: Int) -> Int {
  if a >= b { return a - b; }
  return b - a;
}

fn main() -> Int {
  io.println("=== xiom.basisu conformance tests (vendored basis_universal v2_50) ===");
  io.flush_stdout();
  var failed: Int = 0;

  basisu_init();

  // -- Version pin: BASISD_LIB_VERSION / BASISU_LIB_VERSION are 250 = v2.50.
  let ver = basisu_versions();
  failed = failed + report(ver.transcoder_lib == 250, "transcoder version = 250 (" + to_string(ver.transcoder_lib) + ")");
  failed = failed + report(ver.encoder_lib == 250, "encoder version = 250 (" + to_string(ver.encoder_lib) + ")");

  // -- Allocator C API round trip (bt_alloc/bu_alloc + free, inside C).
  let ap = basisu_alloc_probe();
  failed = failed + report(ap.transcoder_ok && ap.encoder_ok, "bt_alloc/bu_alloc write+read+free round trip");

  // -- Format helper surface (all scalar bt_basis_* helpers).
  let fr = basisu_format_report();
  failed = failed + report(fr.bytes_per_block_rgba32 == 4 && fr.bytes_per_block_bc1 == 8 && fr.bytes_per_block_astc4 == 16 && fr.uncompressed_bpp_rgba32 == 4,
    "format helpers: bytes/block RGBA32=4 BC1=8 ASTC4x4=16, uncompressed bpp=4");
  failed = failed + report(!fr.has_alpha_bc1 && fr.has_alpha_bc3 && fr.is_astc_4x4 && !fr.is_astc_bc1 && fr.is_hdr_bc6h && fr.is_ldr_bc1 && fr.is_uncompressed_rgba32,
    "format predicates: alpha/astc/hdr/ldr/uncompressed");
  failed = failed + report(fr.size_bc1_32x32 == 512 && fr.size_astc4_32x32 == 1024 && fr.fmt_from_uastc == 10 && fr.fmt_from_etc1s == 10,
    "transcoded sizes 32x32: BC1=512 ASTC=1024; ASTC 4x4 default target");
  failed = failed + report(fr.supp_bc1_uastc && fr.supp_bc3_uastc && fr.supp_astc_uastc && fr.supp_rgba32_uastc && fr.block_w_bc1 == 4 && fr.block_h_bc1 == 4,
    "format support matrix for UASTC LDR 4x4 (BC1/BC3/ASTC/RGBA32) + BC1 blocks 4x4");
  failed = failed + report(fr.basis_xuastc_8x5 && fr.basis_astc_4x4 && fr.basis_hdr_6x6 && fr.basis_ldr_uastc && fr.basis_xubc7 && fr.basis_block_w_xuastc_8x5 == 8 && fr.basis_block_h_xuastc_8x5 == 5,
    "basis_tex_format predicates + XUASTC 8x5 block dims");

  // -- Source image (32x32 RGBA = 4096 bytes).
  var src = build_source_rgba(32, 32);
  failed = failed + report(src.len() == 4096, "source image bytes = " + to_string(src.len()));

  // =========================================================================
  // UASTC LDR 4x4 encode path (bu_* C API), mips generated.
  // =========================================================================
  let uastc_flags: Int32 = BU_COMP_FLAGS_KTX2_OUTPUT | BU_COMP_FLAGS_SRGB | BU_COMP_FLAGS_GEN_MIPS_CLAMP | BU_COMP_FLAGS_THREADED;
  var ktx2 = zeros(262144);

  let enc = basisu_encode_ktx2(&mut src, 32, 32, BTF_UASTC_LDR_4X4, uastc_flags, 85 as Int32, 2 as Int32, &mut ktx2);
  if !enc.is_ok {
    failed = failed + report(false, "UASTC encode failed -- " + enc.error);
  } else {
    let er = enc.value;
    failed = failed + report(er.copy_ok && er.size > 0, "UASTC encode: KTX2 payload " + to_string(er.size) + " bytes");

    let info = basisu_ktx2_info(&mut ktx2, er.size);
    if !info.is_ok {
      failed = failed + report(false, "UASTC info failed -- " + info.error);
    } else {
      let k = info.value;
      failed = failed + report(k.open && k.width == 32 && k.height == 32 && k.levels == 6 && k.faces == 1 && k.layers <= 1,
        "KTX2 header: 32x32, 6 mip levels, 1 face, 1 layer");
      failed = failed + report(k.basis_tex_format == BTF_UASTC_LDR_4X4 && k.is_uastc_ldr_4x4 && k.is_ldr && !k.is_etc1s && k.is_srgb && k.start_transcoding_ok && k.dfd_total_samples >= 1,
        "KTX2 mode: UASTC LDR 4x4, LDR, sRGB, start_transcoding ok");
      failed = failed + report(k.block_width == 4 && k.block_height == 4, "KTX2 block dims 4x4");

      let l0 = basisu_ktx2_level_info(&mut ktx2, er.size, 0);
      if !l0.is_ok {
        failed = failed + report(false, "level 0 info failed -- " + l0.error);
      } else {
        let lv0 = l0.value;
        failed = failed + report(lv0.orig_width == 32 && lv0.orig_height == 32 && lv0.blocks_x == 8 && lv0.blocks_y == 8 && lv0.total_blocks == 64,
          "level 0: 32x32, 8x8 blocks, 64 total");
      }

      let l1 = basisu_ktx2_level_info(&mut ktx2, er.size, 1);
      if !l1.is_ok {
        failed = failed + report(false, "level 1 info failed -- " + l1.error);
      } else {
        let lv1 = l1.value;
        failed = failed + report(lv1.orig_width == 16 && lv1.orig_height == 16 && lv1.blocks_x == 4 && lv1.blocks_y == 4 && lv1.total_blocks == 16,
          "level 1: 16x16 mip, 4x4 blocks, 16 total");
      }

      // -- Transcode: BC1 mip chain.
      var bc1_l0 = zeros(512);
      let t0 = basisu_transcode(&mut ktx2, er.size, 0, TF_BC1_RGB, &mut bc1_l0);
      if !t0.is_ok {
        failed = failed + report(false, "BC1 level 0 transcode failed -- " + t0.error);
      } else {
        let tr0 = t0.value;
        failed = failed + report(tr0.transcoded && tr0.opened && tr0.started && tr0.size == 512,
          "BC1 level 0: " + to_string(tr0.size) + " bytes transcoded");
      }

      var bc1_l1 = zeros(128);
      let t1 = basisu_transcode(&mut ktx2, er.size, 1, TF_BC1_RGB, &mut bc1_l1);
      if !t1.is_ok {
        failed = failed + report(false, "BC1 level 1 transcode failed -- " + t1.error);
      } else {
        let tr1 = t1.value;
        failed = failed + report(tr1.transcoded && tr1.size == 128,
          "BC1 level 1: " + to_string(tr1.size) + " bytes (mip chain)");
      }

      // -- Transcode: ETC1 and ASTC 4x4.
      var etc1_l0 = zeros(512);
      let te = basisu_transcode(&mut ktx2, er.size, 0, TF_ETC1_RGB, &mut etc1_l0);
      if !te.is_ok {
        failed = failed + report(false, "ETC1 level 0 transcode failed -- " + te.error);
      } else {
        failed = failed + report(te.value.transcoded && te.value.size == 512, "ETC1 level 0: 512 bytes transcoded");
      }

      var astc_l0 = zeros(1024);
      let ta = basisu_transcode(&mut ktx2, er.size, 0, TF_ASTC_LDR_4X4_RGBA, &mut astc_l0);
      if !ta.is_ok {
        failed = failed + report(false, "ASTC 4x4 level 0 transcode failed -- " + ta.error);
      } else {
        failed = failed + report(ta.value.transcoded && ta.value.size == 1024, "ASTC LDR 4x4 level 0: 1024 bytes transcoded");
      }

      // -- Transcode: RGBA32 + content check against the source gradient.
      var rgba_l0 = zeros(4096);
      let tr = basisu_transcode(&mut ktx2, er.size, 0, TF_RGBA32, &mut rgba_l0);
      if !tr.is_ok {
        failed = failed + report(false, "RGBA32 level 0 transcode failed -- " + tr.error);
      } else {
        failed = failed + report(tr.value.transcoded && tr.value.size == 4096, "RGBA32 level 0: 4096 bytes transcoded");

        var sum: Int = 0;
        var alpha_ok: Bool = true;
        var px: Int = 0;
        while px < 32 * 32 {
          sum = sum + abs_diff_i(rgba_l0[px * 4] as Int, src[px * 4] as Int);
          sum = sum + abs_diff_i(rgba_l0[px * 4 + 1] as Int, src[px * 4 + 1] as Int);
          sum = sum + abs_diff_i(rgba_l0[px * 4 + 2] as Int, src[px * 4 + 2] as Int);
          if (rgba_l0[px * 4 + 3] as Int) != 255 { alpha_ok = false; }
          px = px + 1;
        }
        let mae_milli = (sum * 1000) / (32 * 32 * 3);
        failed = failed + report(mae_milli <= 32000, "decoded RGBA matches source (mean abs err " + to_string(mae_milli) + " milli)");
        failed = failed + report(alpha_ok, "decoded RGBA alpha channel is opaque");
      }

      // -- Corrupt/truncated payloads: typed errors.
      var garbage = zeros(16);
      let gbad = basisu_ktx2_info(&mut garbage, 16);
      if gbad.is_ok {
        failed = failed + report(false, "16 zero bytes unexpectedly opened");
      } else {
        failed = failed + report(!basisu_can_open(&mut garbage, 16), "corrupt 16-byte payload rejected (" + gbad.error + ")");
      }

      let magic_bad = basisu_ktx2_info(&mut ktx2, 12);
      if magic_bad.is_ok {
        failed = failed + report(false, "KTX2 identifier-only prefix unexpectedly opened");
      } else {
        failed = failed + report(true, "identifier-only 12-byte prefix rejected (" + magic_bad.error + ")");
      }

      let cut = er.size / 2;
      let trunc = basisu_ktx2_info(&mut ktx2, cut);
      if trunc.is_ok {
        failed = failed + report(false, "truncated KTX2 (" + to_string(cut) + " bytes) unexpectedly opened");
      } else {
        failed = failed + report(true, "truncated KTX2 (" + to_string(cut) + " bytes) rejected");
      }
    }
  }

  // =========================================================================
  // ETC1S encode path (second encoder mode; classic Basis pipeline).
  // =========================================================================
  let etc1s_flags: Int32 = BU_COMP_FLAGS_KTX2_OUTPUT | BU_COMP_FLAGS_SRGB | BU_COMP_FLAGS_GEN_MIPS_CLAMP;
  var etc1_ktx2 = zeros(262144);
  let eenc = basisu_encode_ktx2(&mut src, 32, 32, BTF_ETC1S, etc1s_flags, 100 as Int32, 4 as Int32, &mut etc1_ktx2);
  if !eenc.is_ok {
    failed = failed + report(false, "ETC1S encode failed -- " + eenc.error);
  } else {
    let eer = eenc.value;
    failed = failed + report(eer.copy_ok && eer.size > 0, "ETC1S encode: KTX2 payload " + to_string(eer.size) + " bytes");

    let einfo = basisu_ktx2_info(&mut etc1_ktx2, eer.size);
    if !einfo.is_ok {
      failed = failed + report(false, "ETC1S info failed -- " + einfo.error);
    } else {
      let ek = einfo.value;
      failed = failed + report(ek.open && ek.basis_tex_format == BTF_ETC1S && ek.is_etc1s && ek.is_ldr && ek.width == 32 && ek.height == 32 && ek.levels == 6,
        "ETC1S KTX2: mode ETC1S, 32x32, 6 mip levels");
    }

    var etc1s_bc1 = zeros(512);
    let et = basisu_transcode(&mut etc1_ktx2, eer.size, 0, TF_BC1_RGB, &mut etc1s_bc1);
    if !et.is_ok {
      failed = failed + report(false, "ETC1S -> BC1 transcode failed -- " + et.error);
    } else {
      failed = failed + report(et.value.transcoded && et.value.size == 512, "ETC1S -> BC1 level 0: 512 bytes transcoded");
    }
  }

  // =========================================================================
  // Zstd-supercompressed UASTC payload (exercises the vendored zstd decode).
  // =========================================================================
  let zstd_flags: Int32 = BU_COMP_FLAGS_KTX2_OUTPUT | BU_COMP_FLAGS_KTX2_UASTC_ZSTD | BU_COMP_FLAGS_SRGB | BU_COMP_FLAGS_GEN_MIPS_CLAMP;
  var zstd_ktx2 = zeros(262144);
  let zenc = basisu_encode_ktx2(&mut src, 32, 32, BTF_UASTC_LDR_4X4, zstd_flags, 85 as Int32, 2 as Int32, &mut zstd_ktx2);
  if !zenc.is_ok {
    failed = failed + report(false, "UASTC+zstd encode failed -- " + zenc.error);
  } else {
    let zer = zenc.value;
    failed = failed + report(zer.copy_ok && zer.size > 0, "UASTC+zstd encode: KTX2 payload " + to_string(zer.size) + " bytes");

    var zbc1 = zeros(512);
    let zt = basisu_transcode(&mut zstd_ktx2, zer.size, 0, TF_BC1_RGB, &mut zbc1);
    if !zt.is_ok {
      failed = failed + report(false, "UASTC+zstd -> BC1 transcode failed -- " + zt.error);
    } else {
      failed = failed + report(zt.value.transcoded && zt.value.size == 512, "UASTC+zstd -> BC1 level 0: 512 bytes transcoded (zstd decode path)");
    }
  }

  if failed == 0 {
    io.println("xiom.basisu: all tests passed");
  } else {
    io.println("xiom.basisu: tests failed");
  }
  return failed;
}
