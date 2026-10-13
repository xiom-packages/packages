// xiom.phonon conformance suite -- generated-surface + dynamic-loader path.
//
// Layered:
//   1. SURFACE (DLL-independent): the generated export manifest and ABI
//      layouts must match the pinned phonon.h counts/values; the f32
//      bit encoder is table-checked; the owned-buffer layer round-trips
//      without any library.
//   2. RUNTIME (SKIP-green when phonon.dll is absent): resolve all 216
//      public entry points, create a context + HRTF, then drive every
//      declared effect group on XIOM-owned planar buffers: binaural,
//      ambisonics encode/decode, panning, direct (attenuation 0.5) and
//      path (SH coefficients).  The expected output energies are the C
//      ground truth from tools/path_check.c (same DLL, same inputs).
//
// Discipline (v0.64.4): byte-indexed slot writes (B-11/B-16), one owned
// slot per out-param (B-17), no `null` literals to C (B-23), no foreign
// pointer reads (B-20/B-24), no Int->pointer casts (B-25), flat outcome
// structs (B-26), every `ptr as Int` cast isolated in its own unsafe block
// (B-27).
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.phonon
// Present path: put the directory containing phonon.dll on PATH (for the
// local recording: the official 4.8.1 release DLL).

module phonon_conformance

use xiom.io;
use xiom.io.fs;
use xiom.convert;
use xiom.test;
use xiom.phonon;
use xiom.phonon.abi;
use xiom.phonon.exports;

// C ground truth from tools/path_check.c (binaural/amb/panning/direct/path).
const ORACLE_BINAURAL: Float64 = 2.90202510392322;
const ORACLE_AMB_ENCODE: Float64 = 0.0795812234760862;
const ORACLE_AMB_DECODE: Float64 = 0.173141100497635;
const ORACLE_PANNING: Float64 = 1.00161929197569;
const ORACLE_DIRECT: Float64 = 0.25;
const ORACLE_PATH: Float64 = 9.88665086850774;
const ORACLE_PATH_NOSPATIAL: Float64 = 1.328125;

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

fn approx(a: Float64, b: Float64, rel: Float64) -> Bool {
  let d = a - b;
  let ad = if d < 0.0 { 0.0 - d } else { d };
  let scale = if b < 1.0 { 1.0 } else { b };
  return ad <= rel * scale;
}

// ---------------------------------------------------------------------------
// 1. SURFACE: generated manifest + ABI + pure helpers (no DLL)
// ---------------------------------------------------------------------------

fn t_manifest() -> Bool {
  var ok = true;
  if exports.PHONON_PUBLIC_FN_COUNT != 216 { ok = false; }
  if exports.PHONON_DECLARED_FN_COUNT != 87 { ok = false; }
  if exports.PHONON_GROUP_COUNT != 14 { ok = false; }
  var total = 0;
  var g = 0;
  while g < exports.PHONON_GROUP_COUNT {
    total = total + exports.phonon_group_export_count(g);
    g = g + 1;
  }
  if total != 87 { ok = false; }
  let names = exports.phonon_all_export_names();
  if names.len() != 216 { ok = false; }
  let declared = exports.phonon_declared_export_names();
  if declared.len() != 87 { ok = false; }
  return ok;
}

fn t_abi() -> Bool {
  var ok = true;
  if abi.STEAMAUDIO_VERSION != 0x040801 { ok = false; }
  if abi.STEAMAUDIO_VERSION_MAJOR != 4 { ok = false; }
  if abi.STEAMAUDIO_VERSION_MINOR != 8 { ok = false; }
  if abi.STEAMAUDIO_VERSION_PATCH != 1 { ok = false; }
  if abi.IPL_STATUS_SUCCESS != 0 { ok = false; }
  if abi.IPL_STATUS_INITIALIZATION != 3 { ok = false; }
  if abi.IPL_SIMDLEVEL_SSE2 != 0 { ok = false; }
  if abi.IPL_SIMDLEVEL_AVX2 != 3 { ok = false; }
  if abi.IPL_CONTEXTFLAGS_VALIDATION != 1 { ok = false; }
  if abi.IPL_HRTFTYPE_DEFAULT != 0 { ok = false; }
  if abi.IPL_HRTFTYPE_SOFA != 1 { ok = false; }
  if abi.IPL_HRTFINTERPOLATION_NEAREST != 0 { ok = false; }
  if abi.IPL_AMBISONICSTYPE_N3D != 0 { ok = false; }
  if abi.IPL_SPEAKERLAYOUTTYPE_STEREO != 1 { ok = false; }
  if abi.IPL_SPEAKERLAYOUTTYPE_SURROUND_7_1 != 4 { ok = false; }
  if abi.IPL_AUDIOEFFECTSTATE_TAILCOMPLETE != 1 { ok = false; }
  if abi.IPL_NUM_BANDS != 3 { ok = false; }
  // generated struct layouts (cross-verified with tools/layout_check.c)
  if abi.IPL_CONTEXT_SETTINGS_SIZE != 40 { ok = false; }
  if abi.IPL_CONTEXT_SETTINGS_SIMD_LEVEL != 32 { ok = false; }
  if abi.IPL_CONTEXT_SETTINGS_FLAGS != 36 { ok = false; }
  if abi.IPL_AUDIO_SETTINGS_SIZE != 8 { ok = false; }
  if abi.IPL_AUDIO_BUFFER_SIZE != 16 { ok = false; }
  if abi.IPL_AUDIO_BUFFER_DATA != 8 { ok = false; }
  if abi.IPL_HRTF_SETTINGS_SIZE != 40 { ok = false; }
  if abi.IPL_HRTF_SETTINGS_VOLUME != 28 { ok = false; }
  if abi.IPL_BINAURAL_EFFECT_PARAMS_SIZE != 40 { ok = false; }
  if abi.IPL_DIRECT_EFFECT_PARAMS_SIZE != 44 { ok = false; }
  if abi.IPL_PATH_EFFECT_PARAMS_SIZE != 96 { ok = false; }
  if abi.IPL_PATH_EFFECT_PARAMS_SH_COEFFS != 16 { ok = false; }
  if abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_SIZE != 72 { ok = false; }
  if abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_BINAURAL != 64 { ok = false; }
  return ok;
}

fn t_f32_encoder() -> Bool {
  var ok = true;
  if phonon_f32_bits(0.0) != 0 { ok = false; }
  if phonon_f32_bits(1.0) != 0x3F800000 { ok = false; }
  if phonon_f32_bits(-1.0) != 0xBF800000 { ok = false; }
  if phonon_f32_bits(0.5) != 0x3F000000 { ok = false; }
  if phonon_f32_bits(1.5) != 0x3FC00000 { ok = false; }
  if phonon_f32_bits(2.0) != 0x40000000 { ok = false; }
  if phonon_f32_bits(-2.5) != 0xC0200000 { ok = false; }
  if phonon_f32_bits(100.0) != 0x42C80000 { ok = false; }
  if phonon_f32_bits(1e40) != 0x7F800000 { ok = false; }
  if phonon_f32_bits(-1e40) != 0xFF800000 { ok = false; }
  if phonon_f32_bits(1e-40) != 0x000116C2 { ok = false; }
  if phonon_f32_bits(3.1415927410125732) != 0x40490FDB { ok = false; }
  if phonon_f32_bits(16777216.0) != 0x4B800000 { ok = false; }
  if phonon_f32_bits(16777217.0) != 0x4B800000 { ok = false; }
  if phonon_f32_bits(16777218.0) != 0x4B800001 { ok = false; }
  if phonon_f32_bits(0.1) != 0x3DCCCCCD { ok = false; }
  // decode round-trip on exact values
  if !approx(phonon_f32_from_bits(0x3F800000), 1.0, 1e-9) { ok = false; }
  if !approx(phonon_f32_from_bits(0xBF800000), -1.0, 1e-9) { ok = false; }
  if !approx(phonon_f32_from_bits(0x42C80000), 100.0, 1e-9) { ok = false; }
  if !approx(phonon_f32_from_bits(0x3DCCCCCD), 0.1, 1e-6) { ok = false; }
  return ok;
}

fn t_owned_buffer() -> Bool {
  var buf = phonon_audio_buffer_new(2, 8);
  var ok = true;
  if buf.num_channels != 2 { ok = false; }
  if buf.num_samples != 8 { ok = false; }
  if buf.data.len() != 16 { ok = false; }
  if buf.ptrs.len() != 16 { ok = false; }
  if buf.slot.len() != 16 { ok = false; }
  phonon_audio_buffer_set(&mut buf, 0, 0, 1.0);
  phonon_audio_buffer_set(&mut buf, 0, 3, 0.5);
  phonon_audio_buffer_set(&mut buf, 1, 7, 2.0);
  if !approx(phonon_audio_buffer_get(&buf, 0, 0), 1.0, 1e-9) { ok = false; }
  if !approx(phonon_audio_buffer_get(&buf, 0, 3), 0.5, 1e-9) { ok = false; }
  if !approx(phonon_audio_buffer_get(&buf, 1, 7), 2.0, 1e-9) { ok = false; }
  if !approx(phonon_audio_buffer_channel_energy(&buf, 0), 1.25, 1e-9) { ok = false; }
  if !approx(phonon_audio_buffer_channel_energy(&buf, 1), 4.0, 1e-9) { ok = false; }
  if !approx(phonon_audio_buffer_total_energy(&buf), 5.25, 1e-9) { ok = false; }
  return ok;
}

// ---------------------------------------------------------------------------
// 2. RUNTIME (present path)
// ---------------------------------------------------------------------------

// Local-only SOFA fixture from the upstream clone (not vendored/shipped;
// the check SKIPs when the clone is absent).
fn sofa_fixture() -> Str {
  return "E:\\repos\\steam-audio\\core\\data\\hrtf\\cipic_124.sofa";
}

fn impulse(buf: &mut PhononAudioBuffer, ch: Int) {
  var i = 0;
  while i < buf.num_samples {
    phonon_audio_buffer_set(buf, ch, i, 0.0);
    i = i + 1;
  }
  phonon_audio_buffer_set(buf, ch, 0, 1.0);
}

fn t_runtime_context(lib: &PhononLibrary) -> Int {
  var failed = 0;
  let caps = phonon_capabilities(lib);
  failed = failed + report(caps.resolved_fn_count == 216,
    "capabilities: 216/216 public entry points resolved (version " + to_string(caps.version) + ")");
  failed = failed + report(caps.has_context && caps.has_hrtf && caps.has_audio_buffers
    && caps.has_binaural && caps.has_panning && caps.has_virtual_surround
    && caps.has_ambisonics && caps.has_direct && caps.has_path,
    "capabilities: every declared group resolvable");
  failed = failed + report(phonon_export_index("iplBinauralEffectApply") >= 0,
    "manifest: iplBinauralEffectApply indexed in the header-order table");

  let ctx = phonon_context_create(&lib, abi.STEAMAUDIO_VERSION, abi.IPL_SIMDLEVEL_SSE2, 0);
  if !ctx.ok {
    failed = failed + report(false, "context: create failed (" + ctx.error + ")");
    return failed;
  }
  failed = failed + report(true, "context: created (handle " + int_to_str(ctx.handle) + ")");
  let again = phonon_context_retain(lib, ctx.handle);
  failed = failed + report(again == ctx.handle, "context: retain returned the same handle");
  let r1 = phonon_context_release(lib, ctx.handle);
  let r2 = phonon_context_release(lib, again);
  failed = failed + report(r1.ok && r2.ok, "context: retain/release balanced");
  return failed;
}

fn t_runtime_hrtf(lib: &PhononLibrary, ctx: Int) -> Int {
  var failed = 0;
  let hrtf = phonon_hrtf_create(lib, ctx, 48000, 256, abi.IPL_HRTFTYPE_DEFAULT,
    abi.IPL_HRTFNORMTYPE_NONE, 1.0);
  if !hrtf.ok {
    failed = failed + report(false, "hrtf: default create failed (" + hrtf.error + ")");
    return failed;
  }
  failed = failed + report(true, "hrtf: default (built-in) created");
  let again = phonon_hrtf_retain(lib, hrtf.handle);
  failed = failed + report(again == hrtf.handle, "hrtf: retain returned the same handle");
  let rel = phonon_hrtf_release(lib, again);
  failed = failed + report(rel.ok, "hrtf: release (retained reference)");

  let fixture = sofa_fixture();
  if fs_is_file(fixture) {
    let sofa = phonon_hrtf_create_sofa_file(lib, ctx, 48000, 256, fixture,
      abi.IPL_HRTFNORMTYPE_NONE, 1.0);
    failed = failed + report(sofa.ok, "hrtf: SOFA file create (upstream CIPIC fixture)");
    if sofa.ok {
      let srel = phonon_hrtf_release(lib, sofa.handle);
      failed = failed + report(srel.ok, "hrtf: SOFA release");
    }
  } else {
    failed = failed + report(true, "hrtf: SOFA file create SKIP -- fixture not present (" + fixture + ")");
  }
  let href = phonon_hrtf_release(lib, hrtf.handle);
  failed = failed + report(href.ok, "hrtf: release");
  return failed;
}

fn t_runtime_effects(lib: &PhononLibrary, ctx: Int) -> Int {
  var failed = 0;
  let hrtf = phonon_hrtf_create(lib, ctx, 48000, 256, abi.IPL_HRTFTYPE_DEFAULT,
    abi.IPL_HRTFNORMTYPE_NONE, 1.0);
  if !hrtf.ok {
    failed = failed + report(false, "effects: HRTF unavailable (" + hrtf.error + ")");
    return failed;
  }
  var in_buf = phonon_audio_buffer_new(1, 256);
  var out2 = phonon_audio_buffer_new(2, 256);
  var out4 = phonon_audio_buffer_new(4, 256);
  let dir = PhononVector3{ x: 1.0; y: 0.0; z: 0.0 };
  let identity = phonon_orientation_identity();

  // binaural
  let be = phonon_binaural_create(lib, ctx, 48000, 256, hrtf.handle);
  if be.ok {
    impulse(&mut in_buf, 0);
    let st = phonon_binaural_apply(lib, be.handle, &in_buf, &mut out2, &dir,
      abi.IPL_HRTFINTERPOLATION_NEAREST, 1.0, hrtf.handle);
    let e = phonon_audio_buffer_total_energy(&out2);
    let el = phonon_audio_buffer_channel_energy(&out2, 0);
    let er = phonon_audio_buffer_channel_energy(&out2, 1);
    failed = failed + report(st.ok && approx(e, ORACLE_BINAURAL, 1e-3),
      "binaural: apply matches C ground truth (" + float_to_string(e) + ")");
    failed = failed + report(el > 0.0 && er > 0.0 && !approx(el, er, 1e-6),
      "binaural: left/right energies differ (spatialized)");
    let ts = phonon_binaural_tail_size(lib, be.handle);
    failed = failed + report(ts >= 0, "binaural: tail size readable (" + int_to_str(ts) + ")");
    let tail = phonon_binaural_get_tail(lib, be.handle, &mut out2);
    failed = failed + report(tail.ok, "binaural: get_tail");
    let rs = phonon_binaural_retain(lib, be.handle);
    failed = failed + report(rs == be.handle, "binaural: retain");
    let rl = phonon_binaural_release(lib, be.handle);
    failed = failed + report(rl.ok, "binaural: release");
  } else {
    failed = failed + report(false, "binaural: create failed (" + be.error + ")");
  }

  // ambisonics encode -> ambisonics decode (binaural)
  let ee = phonon_ambisonics_encode_create(lib, ctx, 48000, 256, 1);
  if ee.ok {
    impulse(&mut in_buf, 0);
    let st = phonon_ambisonics_encode_apply(lib, ee.handle, &in_buf, &mut out4, &dir, 1);
    let e = phonon_audio_buffer_total_energy(&out4);
    failed = failed + report(st.ok && approx(e, ORACLE_AMB_ENCODE, 1e-3),
      "ambisonics: encode order 1 (4ch) matches C ground truth (" + float_to_string(e) + ")");
    let ts = phonon_ambisonics_encode_tail_size(lib, ee.handle);
    failed = failed + report(ts >= 0, "ambisonics: encode tail size readable");
    let rl = phonon_ambisonics_encode_release(lib, ee.handle);
    failed = failed + report(rl.ok, "ambisonics: encode release");
  } else {
    failed = failed + report(false, "ambisonics: encode create failed (" + ee.error + ")");
  }

  let ed = phonon_ambisonics_decode_create(lib, ctx, 48000, 256,
    abi.IPL_SPEAKERLAYOUTTYPE_STEREO, hrtf.handle, 1);
  if ed.ok {
    // out4 still holds the encoded field from the encode check above.
    let st = phonon_ambisonics_decode_apply(lib, ed.handle, &out4, &mut out2, 1,
      hrtf.handle, &identity, true);
    let e = phonon_audio_buffer_total_energy(&out2);
    failed = failed + report(st.ok && approx(e, ORACLE_AMB_DECODE, 1e-3),
      "ambisonics: decode binaural matches C ground truth (" + float_to_string(e) + ")");
    let rl = phonon_ambisonics_decode_release(lib, ed.handle);
    failed = failed + report(rl.ok, "ambisonics: decode release");
  } else {
    failed = failed + report(false, "ambisonics: decode create failed (" + ed.error + ")");
  }

  // panning
  let pe = phonon_panning_create(lib, ctx, 48000, 256, abi.IPL_SPEAKERLAYOUTTYPE_STEREO);
  if pe.ok {
    impulse(&mut in_buf, 0);
    let st = phonon_panning_apply(lib, pe.handle, &in_buf, &mut out2, &dir);
    let e = phonon_audio_buffer_total_energy(&out2);
    failed = failed + report(st.ok && approx(e, ORACLE_PANNING, 1e-3),
      "panning: stereo apply matches C ground truth (" + float_to_string(e) + ")");
    let rl = phonon_panning_release(lib, pe.handle);
    failed = failed + report(rl.ok, "panning: release");
  } else {
    failed = failed + report(false, "panning: create failed (" + pe.error + ")");
  }

  // direct (in-place, distance attenuation 0.5)
  let de = phonon_direct_create(lib, ctx, 48000, 256, 1);
  if de.ok {
    impulse(&mut in_buf, 0);
    let one = PhononVector3{ x: 1.0; y: 1.0; z: 1.0 };
    let st = phonon_direct_apply_inplace(lib, de.handle, &mut in_buf,
      abi.IPL_DIRECTEFFECTFLAGS_APPLYDISTANCEATTENUATION, abi.IPL_TRANSMISSIONTYPE_FREQINDEPENDENT,
      0.5, &one, 1.0, 1.0, &one);
    let e = phonon_audio_buffer_channel_energy(&in_buf, 0);
    failed = failed + report(st.ok && approx(e, ORACLE_DIRECT, 1e-3),
      "direct: in-place apply (attenuation 0.5) matches C ground truth (" + float_to_string(e) + ")");
    let rl = phonon_direct_release(lib, de.handle);
    failed = failed + report(rl.ok, "direct: release");
  } else {
    failed = failed + report(false, "direct: create failed (" + de.error + ")");
  }

  // path (spatialized panning + ambisonic output)
  let pa = phonon_path_create(lib, ctx, 48000, 256, 1, true,
    abi.IPL_SPEAKERLAYOUTTYPE_STEREO, hrtf.handle);
  if pa.ok {
    var sh: Vec[Float32] = Vec[Float32].new();
    sh.push(1.0);
    sh.push(0.5);
    sh.push(0.25);
    sh.push(0.125);
    let one = PhononVector3{ x: 1.0; y: 1.0; z: 1.0 };
    impulse(&mut in_buf, 0);
    let st = phonon_path_apply(lib, pa.handle, &in_buf, &mut out2, &sh, &one, 1, false,
      hrtf.handle, &identity, false);
    let e = phonon_audio_buffer_total_energy(&out2);
    failed = failed + report(st.ok && approx(e, ORACLE_PATH, 1e-3),
      "path: spatialized apply with SH coeffs matches C ground truth (" + float_to_string(e) + ")");
    let rl = phonon_path_release(lib, pa.handle);
    failed = failed + report(rl.ok, "path: release");
  } else {
    failed = failed + report(false, "path: create failed (" + pa.error + ")");
  }

  let pa2 = phonon_path_create(lib, ctx, 48000, 256, 1, false, 0, hrtf.handle);
  if pa2.ok {
    var sh2: Vec[Float32] = Vec[Float32].new();
    sh2.push(1.0);
    sh2.push(0.5);
    sh2.push(0.25);
    sh2.push(0.125);
    let one = PhononVector3{ x: 1.0; y: 1.0; z: 1.0 };
    impulse(&mut in_buf, 0);
    let st = phonon_path_apply(lib, pa2.handle, &in_buf, &mut out4, &sh2, &one, 1, false,
      hrtf.handle, &identity, false);
    let e = phonon_audio_buffer_total_energy(&out4);
    failed = failed + report(st.ok && approx(e, ORACLE_PATH_NOSPATIAL, 1e-3),
      "path: ambisonic (non-spatialized, 4ch) matches C ground truth (" + float_to_string(e) + ")");
    let rl = phonon_path_release(lib, pa2.handle);
    failed = failed + report(rl.ok, "path: non-spatialized release");
  } else {
    failed = failed + report(false, "path: non-spatialized create failed (" + pa2.error + ")");
  }

  let hrel = phonon_hrtf_release(lib, hrtf.handle);
  failed = failed + report(hrel.ok, "effects: HRTF released");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.phonon conformance tests (generated surface + dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_manifest(), "manifest: 216 public / 87 declared / 14 groups (generated from phonon.h)");
  failed = failed + report(t_abi(), "abi: generated enum values + Win64 struct layouts");
  failed = failed + report(t_f32_encoder(), "f32: IEEE-754 binary32 encoder/decoder table");
  failed = failed + report(t_owned_buffer(), "buffers: XIOM-owned planar buffer round-trip");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = phonon_load_named("xiom-absent-phonon-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == PHONON_LOAD_ABSENT,
      "skip-path: absent library classified as PHONON_LOAD_ABSENT (SKIP)");
  }

  // Present path: needs phonon.dll resolvable by name (PATH on Windows).
  let l = phonon_load();
  if !l.is_ok {
    if l.error.kind == PHONON_LOAD_ABSENT {
      failed = failed + report(true, "present-path: SKIP -- Steam Audio not present (" + l.error.message + ")");
    } else {
      failed = failed + report(false, "present-path: ABI mismatch -- " + l.error.message);
    }
  } else {
    let lib: PhononLibrary = l.value;
    let ctx = phonon_context_create(&lib, abi.STEAMAUDIO_VERSION, abi.IPL_SIMDLEVEL_SSE2, 0);
    if !ctx.ok {
      failed = failed + report(false, "present-path: context create failed (" + ctx.error + ")");
    } else {
      failed = failed + t_runtime_context(&lib);
      failed = failed + t_runtime_hrtf(&lib, ctx.handle);
      failed = failed + t_runtime_effects(&lib, ctx.handle);
      let r = phonon_context_release(&lib, ctx.handle);
      failed = failed + report(r.ok, "present-path: context released");
    }
    let cl = phonon_close(&lib);
    if !cl.is_ok {
      failed = failed + report(false, "present-path: close failed");
    }
  }

  if failed == 0 {
    io.println("xiom.phonon: all tests passed");
  } else {
    io.println("xiom.phonon: tests failed");
  }
  return failed;
}
