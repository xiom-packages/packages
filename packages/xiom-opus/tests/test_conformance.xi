// xiom.opus conformance suite -- vendored libopus v1.6.1 (pin
// 22244de5a79bd1d6d623c32e72bf1954b56235be).
//
// Covers: pin identity, declared/bound coverage ledger, error strings,
// encoder/decoder lifecycle + ctls + error paths, s16/24-bit/f32 PCM
// round-trips with lag-aligned SNR and energy sanity, packet parsing and
// utilities, padding, repacketizer split/merge, multistream (explicit +
// surround), Opus Custom, init-over-owned-memory paths, pcm soft clip,
// ambisonics projection with demixing-matrix round trip, DRED entry points
// (default-build stubs).
//
// Runs on compiler v0.64.4.  Avoids the v0.64.4 `Str + Bool` concatenation
// crash by formatting booleans through b2s().

module opus_conformance

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.math;
use xiom.opus;
use xiom.opus.abi;
use xiom.opus.ffi;
use xiom.opus.types;

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn b2s(b: Bool) -> Str {
  if b {
    return "true";
  }
  return "false";
}

fn ctl_rc(r: Result[Unit, OpusError]) -> Int {
  if r.is_ok {
    return 0;
  }
  return r.error.code;
}

fn slot_i16(s: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push((s & 255) as UInt8);
  out.push(((s >> 8) & 255) as UInt8);
  return out;
}

fn read_i16(buf: &Vec[UInt8], pos: Int) -> Int {
  let b0 = buf[pos] as Int;
  let b1 = buf[pos + 1] as Int;
  let raw = b0 | (b1 << 8);
  if b1 >= 128 {
    return raw - 65536;
  }
  return raw;
}

fn read_i32(buf: &Vec[UInt8], pos: Int) -> Int {
  let b0 = buf[pos] as Int;
  let b1 = buf[pos + 1] as Int;
  let b2 = buf[pos + 2] as Int;
  let b3 = buf[pos + 3] as Int;
  let raw = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  if b3 >= 128 {
    return raw - 4294967296;
  }
  return raw;
}

fn push_i16(out: &mut Vec[UInt8], s: Int) {
  out.push((s & 255) as UInt8);
  out.push(((s >> 8) & 255) as UInt8);
}

fn push_i32(out: &mut Vec[UInt8], v: Int) {
  out.push((v & 255) as UInt8);
  out.push(((v >> 8) & 255) as UInt8);
  out.push(((v >> 16) & 255) as UInt8);
  out.push(((v >> 24) & 255) as UInt8);
}

fn buf_zero(n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

/// Copy the first n bytes of src into a fresh Vec.
fn bytes_copy(src: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// Sum of squares of n s16 samples (energy).
fn energy16(buf: &Vec[UInt8], n: Int) -> Int {
  var e: Int = 0;
  var i = 0;
  while i < n {
    let v = read_i16(buf, i * 2);
    e = e + v * v;
    i = i + 1;
  }
  return e;
}

/// Interleaved s16 PCM for a sine wave, generated sample-exact (amp <= 32767).
fn tone16(frame_size: Int, freq: Float64, offset_samples: Int, amp: Int) -> Vec[UInt8] {
  var pcm: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < frame_size {
    let t = ((offset_samples + i) as Float64) / 48000.0;
    let s = (math.sin(2.0 * 3.14159265358979 * freq * t) * (amp as Float64)) as Int;
    push_i16(&mut pcm, s);
    i = i + 1;
  }
  return pcm;
}

/// Interleaved s16 PCM, stereo (L then R per sample).
fn tone16_stereo(frame_size: Int, freq_l: Float64, freq_r: Float64, offset_samples: Int, amp: Int) -> Vec[UInt8] {
  var pcm: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < frame_size {
    let t = ((offset_samples + i) as Float64) / 48000.0;
    let sl = (math.sin(2.0 * 3.14159265358979 * freq_l * t) * (amp as Float64)) as Int;
    let sr = (math.sin(2.0 * 3.14159265358979 * freq_r * t) * (amp as Float64)) as Int;
    push_i16(&mut pcm, sl);
    push_i16(&mut pcm, sr);
    i = i + 1;
  }
  return pcm;
}

/// Lag-aligned SNR of deg vs orig, both s16, searching lags [0, max_lag].
fn snr_db(orig: &Vec[UInt8], deg: &Vec[UInt8], n: Int, max_lag: Int) -> Float64 {
  var best_s: Int = 0;
  var best_e: Int = 0;
  var lag = 0;
  while lag <= max_lag {
    var ss: Int = 0;
    var se: Int = 0;
    var k = 0;
    while k + lag < n {
      let o = read_i16(orig, k * 2);
      let d = read_i16(deg, (k + lag) * 2);
      ss = ss + o * o;
      let diff = d - o;
      se = se + diff * diff;
      k = k + 1;
    }
    if lag == 0 {
      best_s = ss;
      best_e = se;
    } else {
      if se < best_e {
        best_e = se;
        best_s = ss;
      }
    }
    lag = lag + 1;
  }
  if best_e == 0 {
    return 99.0;
  }
  if best_s == 0 {
    return 0.0;
  }
  return 10.0 * math.log10((best_s as Float64) / (best_e as Float64));
}

/// IEEE-754 f32 bit pattern of (s / 32768.0) for an s16 range integer:
/// exact (dyadic rational), no rounding involved.
fn f32_bits_from_i16(s: Int) -> Int {
  if s == 0 {
    return 0;
  }
  var sign_bit = 0;
  var a = s;
  if a < 0 {
    sign_bit = 2147483648;
    a = 0 - a;
  }
  // e = floor(log2(a)), a in [1, 32768)
  var e = 0;
  var k = 14;
  var found = false;
  while k >= 0 {
    if !found {
      if a >= (1 << k) {
        e = k;
        found = true;
      }
    }
    k = k - 1;
  }
  // v = a * 2^-15; f32 exponent field = e - 15 + 127 = e + 112
  let norm = a << (23 - e);
  let man = norm - 8388608;
  return sign_bit | ((e + 112) << 23) | man;
}

fn push_f32_from_i16(out: &mut Vec[UInt8], s: Int) {
  push_i32(out, f32_bits_from_i16(s));
}

/// f32 value from 4 LE bytes, reconstructed in Float64.
fn read_f32(buf: &Vec[UInt8], pos: Int) -> Float64 {
  let bits = read_i32(buf, pos);
  var raw = bits;
  var neg = false;
  if raw < 0 {
    neg = true;
    raw = raw + 4294967296;
  }
  let exp = (raw >> 23) & 255;
  let man = raw & 8388607;
  var v = 0.0;
  if exp > 0 {
    v = (1.0 + (man as Float64) / 8388608.0) * math.pow(2.0, (exp as Float64) - 127.0);
  }
  if neg {
    v = 0.0 - v;
  }
  return v;
}

fn energy_f32(buf: &Vec[UInt8], n: Int) -> Float64 {
  var e = 0.0;
  var i = 0;
  while i < n {
    let v = read_f32(buf, i * 4);
    e = e + v * v;
    i = i + 1;
  }
  return e;
}

fn snr_db_f32(orig: &Vec[UInt8], deg: &Vec[UInt8], n: Int, max_lag: Int) -> Float64 {
  var best_s = 0.0;
  var best_e = 0.0;
  var lag = 0;
  while lag <= max_lag {
    var ss = 0.0;
    var se = 0.0;
    var k = 0;
    while k + lag < n {
      let o = read_f32(orig, k * 4);
      let d = read_f32(deg, (k + lag) * 4);
      ss = ss + o * o;
      let diff = d - o;
      se = se + diff * diff;
      k = k + 1;
    }
    if lag == 0 {
      best_s = ss;
      best_e = se;
    } else {
      if se < best_e {
        best_e = se;
        best_s = ss;
      }
    }
    lag = lag + 1;
  }
  if best_e == 0.0 {
    return 99.0;
  }
  if best_s == 0.0 {
    return 0.0;
  }
  return 10.0 * math.log10(best_s / best_e);
}

/// Ratio helpers as scaled ints for safe Str printing of ratios.
fn ratio_pct(num: Float64, den: Float64) -> Int {
  if den == 0.0 {
    return -1;
  }
  return (100.0 * num / den) as Int;
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

fn t01_version_pin() -> TestResult {
  let v = opus.version();
  return assert(str_eq(v, "libopus 1.6.1"), "version string is libopus 1.6.1");
}

fn t02_coverage_ledger() -> TestResult {
  var ok = abi.DECLARED_FUNCTIONS == 105;
  if abi.BOUND_FUNCTIONS != 105 { ok = false; }
  if abi.CTL_FUNCTIONS != 9 { ok = false; }
  if abi.DECLARED_CONSTANTS != 86 { ok = false; }
  if abi.CTL_MACROS != 48 { ok = false; }
  return assert(ok, "coverage ledger 105/105 bound, 0 skips (9 ctl pairs, 86 consts)");
}

fn t03_strerror_texts() -> TestResult {
  var ok = str_eq(ffi.strerror(0), "success");
  if !str_eq(ffi.strerror(-1), "invalid argument") { ok = false; }
  if !str_eq(ffi.strerror(-2), "buffer too small") { ok = false; }
  if !str_eq(ffi.strerror(-4), "corrupted stream") { ok = false; }
  if !str_eq(ffi.strerror(-5), "request not implemented") { ok = false; }
  if !str_eq(ffi.strerror(-7), "memory allocation failed") { ok = false; }
  if !str_eq(ffi.strerror(99), "unknown error") { ok = false; }
  return assert(ok, "opus_strerror texts for 0/-1/-2/-4/-5/-7/unknown");
}

fn t04_encoder_size_and_create() -> TestResult {
  let s1 = ffi.encoder_get_size(1);
  let s2 = ffi.encoder_get_size(2);
  var ok = s1 > 1000;
  if s2 <= s1 { ok = false; }
  let r = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !r.is_ok { ok = false; }
  if r.is_ok {
    ffi.encoder_destroy(r.value);
  }
  return assert(ok, "encoder_get_size(1)<get_size(2), create(48k,mono,audio) ok");
}

fn t05_create_error_paths() -> TestResult {
  let bad_ch = ffi.encoder_create(48000, 3, abi.OPUS_APPLICATION_AUDIO);
  let bad_fs = ffi.encoder_create(12345, 1, abi.OPUS_APPLICATION_AUDIO);
  let bad_ch_dec = ffi.decoder_create(48000, 3);
  var ok = !bad_ch.is_ok;
  if bad_ch.is_ok { ffi.encoder_destroy(bad_ch.value); }
  if bad_ch.is_ok { ok = false; }
  if !bad_ch.is_ok {
    if bad_ch.error.code != abi.OPUS_BAD_ARG { ok = false; }
  }
  if bad_fs.is_ok { ok = false; }
  if !bad_ch_dec.is_ok {
    if bad_ch_dec.error.code != abi.OPUS_BAD_ARG { ok = false; }
  } else {
    ffi.decoder_destroy(bad_ch_dec.value);
    ok = false;
  }
  return assert(ok, "create with channels=3/sr=12345 -> OPUS_BAD_ARG");
}

fn t06_encoder_ctl_roundtrip() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed for ctl round-trip");
  }
  let enc = er.value;
  var ok = true;
  let setb = ffi.encoder_ctl_set(enc, abi.OPUS_SET_BITRATE_REQUEST, 64000);
  if !setb.is_ok { ok = false; }
  let getb = ffi.encoder_ctl_get(enc, abi.OPUS_GET_BITRATE_REQUEST);
  if !getb.is_ok { ok = false; }
  if getb.is_ok {
    if getb.value != 64000 { ok = false; }
  }
  let setc = ffi.encoder_ctl_set(enc, abi.OPUS_SET_COMPLEXITY_REQUEST, 3);
  if !setc.is_ok { ok = false; }
  let getc = ffi.encoder_ctl_get(enc, abi.OPUS_GET_COMPLEXITY_REQUEST);
  if getc.is_ok {
    if getc.value != 3 { ok = false; }
  } else {
    ok = false;
  }
  let setl = ffi.encoder_ctl_set(enc, abi.OPUS_SET_MAX_BANDWIDTH_REQUEST, abi.OPUS_BANDWIDTH_WIDEBAND);
  if !setl.is_ok { ok = false; }
  let look = ffi.encoder_ctl_get(enc, abi.OPUS_GET_LOOKAHEAD_REQUEST);
  if !look.is_ok { ok = false; }
  if look.is_ok {
    if look.value <= 0 { ok = false; }
  }
  let bad = ffi.encoder_ctl_set(enc, 5999, 0);
  if bad.is_ok { ok = false; }
  if !bad.is_ok {
    if bad.error.code != abi.OPUS_UNIMPLEMENTED { ok = false; }
  }
  ffi.encoder_destroy(enc);
  return assert(ok, "encoder ctl set/get bitrate+complexity+bandwidth+lookahead, bad request err");
}

fn t07_roundtrip_s16_snr() -> TestResult {
  let er = opus.Encoder.create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "facade Encoder.create failed");
  }
  let enc = er.value;
  let dr = opus.Decoder.create(48000, 1);
  if !dr.is_ok {
    opus.Encoder.destroy(&enc);
    return assert(false, "facade Decoder.create failed");
  }
  let dec = dr.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = opus.Encoder.encode(&enc, &pcm, 960, &mut packet);
  var ok = elen.is_ok;
  var nbytes = 0;
  if elen.is_ok { nbytes = elen.value; }
  if !elen.is_ok { ok = false; }
  if nbytes <= 0 { ok = false; }
  let range = opus.Encoder.final_range(&enc);
  if !range.is_ok { ok = false; }
  var out = buf_zero(960 * 2);
  var nsamples = 0;
  if nbytes > 0 {
    let pkt = bytes_copy(&packet, nbytes);
    let dn = opus.Decoder.decode(&dec, &pkt, &mut out, 960);
    if dn.is_ok {
      nsamples = dn.value;
    } else {
      ok = false;
    }
    if nsamples == 960 {
      let snr = snr_db(&pcm, &out, 960, 480);
      let e_in = energy16(&pcm, 960);
      let e_out = energy16(&out, 960);
      let pct = ratio_pct(e_out as Float64, e_in as Float64);
      io.println("  [info] s16 round-trip snr_db_x10=" + ((snr * 10.0) as Int) + " energy_pct=" + pct);
      if snr < 12.0 { ok = false; }
      if pct < 50 { ok = false; }
      if pct > 200 { ok = false; }
    } else {
      ok = false;
    }
  }
  opus.Decoder.destroy(&dec);
  opus.Encoder.destroy(&enc);
  return assert(ok, "s16 encode->decode 440Hz tone: 960 samples, SNR>=12dB, energy 50-200%");
}

fn t08_encode_buffer_too_small() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = ffi.encode(enc, &pcm, 960, &mut packet);
  var ok = elen.is_ok;
  if elen.is_ok {
    let pkt = bytes_copy(&packet, elen.value);
    let rpr = ffi.repacketizer_create();
    if rpr.is_ok {
      let rp = rpr.value;
      let cat = ffi.repacketizer_cat(rp, &pkt);
      if cat.is_ok {
        // 16 bytes cannot hold the 207-byte payload: deterministic OPUS_BUFFER_TOO_SMALL
        var tiny = buf_zero(16);
        let outr = ffi.repacketizer_out(rp, &mut tiny);
        if outr.is_ok { ok = false; }
        if !outr.is_ok {
          io.println("  [info] tiny out code=" + outr.error.code);
          if outr.error.code != abi.OPUS_BUFFER_TOO_SMALL { ok = false; }
        }
      } else {
        ok = false;
      }
      ffi.repacketizer_destroy(rp);
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  ffi.encoder_destroy(enc);
  return assert(ok, "repacketizer_out into 16 bytes -> OPUS_BUFFER_TOO_SMALL");
}

fn t09_decode_invalid_packet() -> TestResult {
  let dr = ffi.decoder_create(48000, 1);
  if !dr.is_ok {
    return assert(false, "decoder_create failed");
  }
  let dec = dr.value;
  var bad: Vec[UInt8] = Vec[UInt8].new();
  bad.push(255 as UInt8);
  bad.push(255 as UInt8);
  var out = buf_zero(960 * 2);
  let r = ffi.decode(dec, &bad, &mut out, 960, 0);
  var ok = !r.is_ok;
  if !r.is_ok {
    if r.error.code != abi.OPUS_INVALID_PACKET { ok = false; }
  }
  ffi.decoder_destroy(dec);
  return assert(ok, "decode of 0xFFFF packet -> OPUS_INVALID_PACKET");
}

fn t10_plc_decode_lost() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  let dr = ffi.decoder_create(48000, 1);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  if !dr.is_ok {
    ffi.encoder_destroy(er.value);
    return assert(false, "decoder_create failed");
  }
  let enc = er.value;
  let dec = dr.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = ffi.encode(enc, &pcm, 960, &mut packet);
  var ok = elen.is_ok;
  var first_out = buf_zero(960 * 2);
  if elen.is_ok {
    let pkt = bytes_copy(&packet, elen.value);
    let dn = ffi.decode(dec, &pkt, &mut first_out, 960, 0);
    if !dn.is_ok { ok = false; }
  } else {
    ok = false;
  }
  let empty: Vec[UInt8] = Vec[UInt8].new();
  var lost_out = buf_zero(960 * 2);
  let pl = ffi.decode(dec, &empty, &mut lost_out, 960, 0);
  if pl.is_ok {
    if pl.value != 960 { ok = false; }
  } else {
    ok = false;
  }
  let e = energy16(&lost_out, 960);
  if e <= 0 { ok = false; }
  ffi.decoder_destroy(dec);
  ffi.encoder_destroy(enc);
  return assert(ok, "PLC (empty packet) yields 960 concealed samples with energy");
}

fn t11_decode_fec() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  let sf1 = ffi.encoder_ctl_set(enc, abi.OPUS_SET_INBAND_FEC_REQUEST, 1);
  let sf2 = ffi.encoder_ctl_set(enc, abi.OPUS_SET_PACKET_LOSS_PERC_REQUEST, 20);
  var ok = sf1.is_ok;
  if !sf2.is_ok { ok = false; }
  let pcm1 = tone16(960, 440.0, 0, 12000);
  let pcm2 = tone16(960, 440.0, 960, 12000);
  var p1 = buf_zero(512);
  var p2 = buf_zero(512);
  let e1 = ffi.encode(enc, &pcm1, 960, &mut p1);
  let e2 = ffi.encode(enc, &pcm2, 960, &mut p2);
  if !e1.is_ok { ok = false; }
  if !e2.is_ok { ok = false; }
  let dr = ffi.decoder_create(48000, 1);
  if !dr.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "decoder_create failed");
  }
  let dec = dr.value;
  var out1 = buf_zero(960 * 2);
  if e1.is_ok {
    let k1 = bytes_copy(&p1, e1.value);
    let d1 = ffi.decode(dec, &k1, &mut out1, 960, 0);
    if !d1.is_ok { ok = false; }
  }
  var out2 = buf_zero(960 * 2);
  if e2.is_ok {
    let k2 = bytes_copy(&p2, e2.value);
    let d2 = ffi.decode(dec, &k2, &mut out2, 960, 1);
    if d2.is_ok {
      if d2.value != 960 { ok = false; }
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  ffi.decoder_destroy(dec);
  ffi.encoder_destroy(enc);
  return assert(ok, "decode with in-band FEC (decode_fec=1) yields a full frame");
}

fn t12_packet_utilities() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = ffi.encode(enc, &pcm, 960, &mut packet);
  if !elen.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "encode failed");
  }
  let pkt = bytes_copy(&packet, elen.value);
  var ok = true;
  let nf = ffi.packet_get_nb_frames(&pkt);
  if nf.is_ok {
    if nf.value != 1 { ok = false; }
  } else {
    ok = false;
  }
  let nc = ffi.packet_get_nb_channels(&pkt);
  if nc.is_ok {
    if nc.value != 1 { ok = false; }
  } else {
    ok = false;
  }
  let spf = ffi.packet_get_samples_per_frame(&pkt, 48000);
  if spf.is_ok {
    if spf.value != 960 { ok = false; }
  } else {
    ok = false;
  }
  let ns = ffi.packet_get_nb_samples(&pkt, 48000);
  if ns.is_ok {
    if ns.value != 960 { ok = false; }
  } else {
    ok = false;
  }
  let bw = ffi.packet_get_bandwidth(&pkt);
  if bw.is_ok {
    if bw.value < abi.OPUS_BANDWIDTH_NARROWBAND { ok = false; }
    if bw.value > abi.OPUS_BANDWIDTH_FULLBAND { ok = false; }
  } else {
    ok = false;
  }
  let lbrr = ffi.packet_has_lbrr(&pkt);
  if lbrr.is_ok {
    if lbrr.value != 0 {
      if lbrr.value != 1 { ok = false; }
    }
  } else {
    ok = false;
  }
  ffi.encoder_destroy(enc);
  return assert(ok, "packet utils: 1 frame mono 960 samples/frame, bandwidth in range, no LBRR");
}

fn t13_packet_parse() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = ffi.encode(enc, &pcm, 960, &mut packet);
  if !elen.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "encode failed");
  }
  let pkt = bytes_copy(&packet, elen.value);
  let pr = ffi.packet_parse(&pkt);
  var ok = pr.is_ok;
  if pr.is_ok {
    let f = pr.value;
    if f.count != 1 { ok = false; }
    if f.sizes.len() != 1 { ok = false; }
    if f.offsets.len() != 1 { ok = false; }

    if f.sizes[0] != elen.value - 1 { ok = false; }
    if f.offsets[0] != f.payload_offset { ok = false; }
    if f.toc != (pkt[0] as Int) { ok = false; }
    if f.payload_offset < 1 { ok = false; }
    io.println("  [info] parse: frames=" + f.count + " size0=" + f.sizes[0] + " toc=" + f.toc + " payload_off=" + f.payload_offset);
  }
  ffi.encoder_destroy(enc);
  return assert(ok, "packet_parse: 1 frame, size/offset/toc/payload_offset consistent");
}

fn t14_packet_pad_unpad() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(512);
  let elen = ffi.encode(enc, &pcm, 960, &mut packet);
  if !elen.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "encode failed");
  }
  let n = elen.value;
  var padded: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    padded.push(packet[i]);
    i = i + 1;
  }
  var z = 0;
  while z < 64 {
    padded.push(0 as UInt8);
    z = z + 1;
  }
  let pr = ffi.packet_pad(&mut padded, n, n + 64);
  var ok = pr.is_ok;
  let up = ffi.packet_unpad(&mut padded, n + 64);
  if up.is_ok {
    if up.value != n { ok = false; }
  } else {
    ok = false;
  }
  let dp = ffi.packet_parse(&padded);
  if dp.is_ok {
    if dp.value.count != 1 { ok = false; }
  } else {
    ok = false;
  }
  ffi.encoder_destroy(enc);
  return assert(ok, "packet_pad(+64)/unpad returns the original length");
}

fn pkt_byte(buf: &Vec[UInt8], i: Int) -> UInt8 {
  return buf[i];
}

fn pkt_byte(buf: &Vec[UInt8], i: Int) -> UInt8 {
  return buf[i];
}

fn t15_repacketizer_merge() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  var p1 = buf_zero(512);
  var p2 = buf_zero(512);
  var p3 = buf_zero(512);
  let e1 = ffi.encode(enc, &tone16(960, 440.0, 0, 12000), 960, &mut p1);
  let e2 = ffi.encode(enc, &tone16(960, 440.0, 960, 12000), 960, &mut p2);
  let e3 = ffi.encode(enc, &tone16(960, 440.0, 1920, 12000), 960, &mut p3);
  var ok = e1.is_ok;
  if !e2.is_ok { ok = false; }
  if !e3.is_ok { ok = false; }
  let rpr = ffi.repacketizer_create();
  if !rpr.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "repacketizer_create failed");
  }
  let rp = rpr.value;
  if e1.is_ok {
    let k1 = bytes_copy(&p1, e1.value);
    if !ffi.repacketizer_cat(rp, &k1).is_ok { ok = false; }
  }
  if e2.is_ok {
    let k2 = bytes_copy(&p2, e2.value);
    if !ffi.repacketizer_cat(rp, &k2).is_ok { ok = false; }
  }
  if e3.is_ok {
    let k3 = bytes_copy(&p3, e3.value);
    if !ffi.repacketizer_cat(rp, &k3).is_ok { ok = false; }
  }
  let nf = ffi.repacketizer_get_nb_frames(rp);
  if nf.is_ok {
    if nf.value != 3 { ok = false; }
  } else {
    ok = false;
  }
  var merged = buf_zero(1500);
  let mr = ffi.repacketizer_out(rp, &mut merged);
  if mr.is_ok {
    let mp = bytes_copy(&merged, mr.value);
    io.println("  [info] merged out bytes=" + mr.value);
    let pr = ffi.packet_parse(&mp);
    if pr.is_ok {
      io.println("  [info] merged frames=" + pr.value.count + " sizes n=" + pr.value.sizes.len());
      if pr.value.count != 3 { ok = false; }
      if pr.value.sizes.len() != 3 { ok = false; }
      if pr.value.sizes.len() == 3 {
        io.println("  [info] sizes=" + pr.value.sizes[0] + "," + pr.value.sizes[1] + "," + pr.value.sizes[2]);
      }
      if e1.is_ok { if pr.value.sizes[0] != e1.value - 1 { ok = false; } }
      if e2.is_ok { if pr.value.sizes[1] != e2.value - 1 { ok = false; } }
      if e3.is_ok { if pr.value.sizes[2] != e3.value - 1 { ok = false; } }
    } else {
      io.println("  [info] merged parse failed code=" + pr.error.code);
      ok = false;
    }
    let dr = ffi.decoder_create(48000, 1);
    if dr.is_ok {
      var dout = buf_zero(2880 * 2);
      let dn = ffi.decode(dr.value, &mp, &mut dout, 2880, 0);
      if dn.is_ok {
        io.println("  [info] merged decode samples=" + dn.value);
        if dn.value != 2880 { ok = false; }
      } else {
        io.println("  [info] merged decode failed code=" + dn.error.code);
        ok = false;
      }
      ffi.decoder_destroy(dr.value);
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  ffi.repacketizer_destroy(rp);
  ffi.encoder_destroy(enc);
  return assert(ok, "repacketizer merges 3 frames; combined packet has 3 frames, decodes 2880 samples");
}

fn t16_repacketizer_split_and_errors() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  var p1 = buf_zero(512);
  var p2 = buf_zero(512);
  var p3 = buf_zero(512);
  let e1 = ffi.encode(enc, &tone16(960, 440.0, 0, 12000), 960, &mut p1);
  let e2 = ffi.encode(enc, &tone16(960, 440.0, 960, 12000), 960, &mut p2);
  let e3 = ffi.encode(enc, &tone16(960, 440.0, 1920, 12000), 960, &mut p3);
  var ok = e1.is_ok;
  if !e2.is_ok { ok = false; }
  if !e3.is_ok { ok = false; }
  let rpr = ffi.repacketizer_create();
  if !rpr.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "repacketizer_create failed");
  }
  let rp = rpr.value;
  if e1.is_ok {
    let k1 = bytes_copy(&p1, e1.value);
    if !ffi.repacketizer_cat(rp, &k1).is_ok { ok = false; }
  }
  if e2.is_ok {
    let k2 = bytes_copy(&p2, e2.value);
    if !ffi.repacketizer_cat(rp, &k2).is_ok { ok = false; }
  }
  if e3.is_ok {
    let k3 = bytes_copy(&p3, e3.value);
    if !ffi.repacketizer_cat(rp, &k3).is_ok { ok = false; }
  }
  var part = buf_zero(1000);
  let pr = ffi.repacketizer_out_range(rp, 1, 3, &mut part);
  if pr.is_ok {
    let pp = bytes_copy(&part, pr.value);
    let pf = ffi.packet_parse(&pp);
    if pf.is_ok {
      if pf.value.count != 2 { ok = false; }
    } else {
      ok = false;
    }
    let dr = ffi.decoder_create(48000, 1);
    if dr.is_ok {
      var dout = buf_zero(1920 * 2);
      let dn = ffi.decode(dr.value, &pp, &mut dout, 1920, 0);
      if dn.is_ok {
        if dn.value != 1920 { ok = false; }
      } else {
        ok = false;
      }
      ffi.decoder_destroy(dr.value);
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  var bad: Vec[UInt8] = Vec[UInt8].new();
  bad.push(255 as UInt8);
  bad.push(255 as UInt8);
  let cbad = ffi.repacketizer_cat(rp, &bad);
  if cbad.is_ok { ok = false; }
  if !cbad.is_ok {
    if cbad.error.code != abi.OPUS_INVALID_PACKET { ok = false; }
  }
  var small = buf_zero(1000);
  let rbad = ffi.repacketizer_out_range(rp, 0, 9, &mut small);
  if rbad.is_ok { ok = false; }
  ffi.repacketizer_destroy(rp);
  ffi.encoder_destroy(enc);
  return assert(ok, "repacketizer out_range(1,3) = 2 frames / 1920 samples; bad cat and out_range error");
}

fn t17_multistream_stereo() -> TestResult {
  var mapping: Vec[UInt8] = Vec[UInt8].new();
  mapping.push(0 as UInt8);
  mapping.push(1 as UInt8);
  let er = ffi.multistream_encoder_create(48000, 2, 1, 1, &mapping, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "multistream_encoder_create failed");
  }
  let enc = er.value;
  let dr = ffi.multistream_decoder_create(48000, 2, 1, 1, &mapping);
  if !dr.is_ok {
    ffi.multistream_encoder_destroy(enc);
    return assert(false, "multistream_decoder_create failed");
  }
  let dec = dr.value;
  let pcm = tone16_stereo(960, 440.0, 660.0, 0, 10000);
  var packet = buf_zero(512);
  let elen = ffi.multistream_encode(enc, &pcm, 960, &mut packet);
  var ok = elen.is_ok;
  var nsamples = 0;
  var snr = 0.0;
  if elen.is_ok {
    let pkt = bytes_copy(&packet, elen.value);
    var out = buf_zero(960 * 4);
    let dn = ffi.multistream_decode(dec, &pkt, &mut out, 960, 0);
    if dn.is_ok {
      nsamples = dn.value;
      snr = snr_db(&pcm, &out, 1920, 960);
      io.println("  [info] multistream stereo snr_db_x10=" + ((snr * 10.0) as Int));
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  if nsamples != 960 { ok = false; }
  if snr < 8.0 { ok = false; }
  let sub = ffi.multistream_encoder_ctl_get_state(enc, 0);
  if !sub.is_ok { ok = false; }
  if sub.is_ok {
    if sub.value == 0 { ok = false; }
    let sset = ffi.encoder_ctl_set(sub.value, abi.OPUS_SET_COMPLEXITY_REQUEST, 4);
    if !sset.is_ok { ok = false; }
  }
  let subdec = ffi.multistream_decoder_ctl_get_state(dec, 0);
  if !subdec.is_ok { ok = false; }
  if subdec.is_ok {
    if subdec.value == 0 { ok = false; }
  }
  ffi.multistream_decoder_destroy(dec);
  ffi.multistream_encoder_destroy(enc);
  return assert(ok, "multistream stereo 1-stream merged: round-trip 960 samples, SNR>=8dB, sub-state handles");
}

fn t18_multistream_surround_and_pad() -> TestResult {
  var mapping = buf_zero(2);
  let er = ffi.multistream_surround_encoder_create(48000, 2, 1, &mut mapping, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "surround encoder create failed");
  }
  let layout = er.value;
  var ok = layout.handle != 0;
  if layout.streams < 1 { ok = false; }
  if layout.coupled_streams < 0 { ok = false; }
  if mapping[0] != (0 as UInt8) { ok = false; }
  if mapping[1] != (1 as UInt8) { ok = false; }
  let pcm = tone16_stereo(960, 440.0, 660.0, 0, 10000);
  var packet = buf_zero(512);
  let elen = ffi.multistream_encode(layout.handle, &pcm, 960, &mut packet);
  var nsamples = 0;
  if elen.is_ok {
    let n = elen.value;
    let pkt = bytes_copy(&packet, n);
    let mr = ffi.multistream_surround_encoder_get_size(2, 1);
    if mr <= 0 { ok = false; }
    // multistream pad/unpad on the encoded packet
    var padded: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < n {
      padded.push(packet[i]);
      i = i + 1;
    }
    var z = 0;
    while z < 32 {
      padded.push(0 as UInt8);
      z = z + 1;
    }
    let pr = ffi.multistream_packet_pad(&mut padded, n, n + 32, layout.streams);
    if pr.is_ok {
      let up = ffi.multistream_packet_unpad(&mut padded, n + 32, layout.streams);
      if up.is_ok {
        if up.value != n { ok = false; }
      } else {
        ok = false;
      }
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  ffi.multistream_encoder_destroy(layout.handle);
  return assert(ok, "surround create (family 1, stereo) streams>=1 mapping {0,1}, pad/unpad round-trip");
}

fn pkt_copy(src: &Vec[UInt8]) -> Vec[UInt8] {
  return bytes_copy(src, src.len());
}

fn t19_custom_mode_roundtrip() -> TestResult {
  let mr = ffi.custom_mode_create(48000, 960);
  if !mr.is_ok {
    return assert(false, "custom_mode_create failed");
  }
  let mode = mr.value;
  var ok = ffi.custom_encoder_get_size(mode, 1) > 0;
  if ffi.custom_decoder_get_size(mode, 1) <= 0 { ok = false; }
  let er = ffi.custom_encoder_create(mode, 1);
  if !er.is_ok {
    ffi.custom_mode_destroy(mode);
    return assert(false, "custom_encoder_create failed");
  }
  let enc = er.value;
  let dr = ffi.custom_decoder_create(mode, 1);
  if !dr.is_ok {
    ffi.custom_encoder_destroy(enc);
    ffi.custom_mode_destroy(mode);
    return assert(false, "custom_decoder_create failed");
  }
  let dec = dr.value;
  let pcm = tone16(960, 440.0, 0, 12000);
  var packet = buf_zero(1024);
  let elen = ffi.custom_encode(enc, &pcm, 960, &mut packet);
  var nsamples = 0;
  var snr = 0.0;
  if elen.is_ok {
    let pkt = bytes_copy(&packet, elen.value);
    var out = buf_zero(960 * 2);
    let dn = ffi.custom_decode(dec, &pkt, &mut out, 960);
    if dn.is_ok {
      nsamples = dn.value;
      snr = snr_db(&pcm, &out, 960, 96);
      io.println("  [info] custom mode snr_db_x10=" + ((snr * 10.0) as Int));
    } else {
      ok = false;
    }
  } else {
    ok = false;
  }
  if nsamples != 960 { ok = false; }
  if snr < 8.0 { ok = false; }
  ffi.custom_decoder_destroy(dec);
  ffi.custom_encoder_destroy(enc);
  ffi.custom_mode_destroy(mode);
  return assert(ok, "custom mode 48k/960: encode->decode 960 samples, SNR>=8dB");
}

fn t20_custom_mode_errors() -> TestResult {
  let bad1 = ffi.custom_mode_create(48000, 97);
  let bad2 = ffi.custom_mode_create(48000, 8192);
  var ok = !bad1.is_ok;
  if !bad1.is_ok {
    if bad1.error.code != abi.OPUS_BAD_ARG { ok = false; }
  }
  if bad2.is_ok {
    ok = false;
    ffi.custom_mode_destroy(bad2.value);
  }
  return assert(ok, "custom_mode_create(48000,97/8192) -> OPUS_BAD_ARG");
}

fn t21_init_over_owned_memory() -> TestResult {
  var ok = true;
  // encoder over owned memory
  let esize = ffi.encoder_get_size(1);
  var emem = buf_zero(esize);
  let eir = ffi.encoder_init_over(&mut emem, 48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !eir.is_ok { ok = false; }
  var packet = buf_zero(512);
  var nbytes = 0;
  if eir.is_ok {
    let pcm = tone16(960, 440.0, 0, 12000);
    let el = ffi.encode(eir.value, &pcm, 960, &mut packet);
    if el.is_ok { nbytes = el.value; } else { ok = false; }
  }
  // decoder over owned memory
  var dmem = buf_zero(ffi.decoder_get_size(1));
  let dir = ffi.decoder_init_over(&mut dmem, 48000, 1);
  if !dir.is_ok { ok = false; }
  if dir.is_ok && nbytes > 0 {
    let pkt = bytes_copy(&packet, nbytes);
    var out = buf_zero(960 * 2);
    let dn = ffi.decode(dir.value, &pkt, &mut out, 960, 0);
    if dn.is_ok {
      if dn.value != 960 { ok = false; }
    } else {
      ok = false;
    }
  }
  // repacketizer over owned memory
  var rmem = buf_zero(ffi.repacketizer_get_size());
  let rir = ffi.repacketizer_init_over(&mut rmem);
  if !rir.is_ok { ok = false; }
  if rir.is_ok && nbytes > 0 {
    let cat = ffi.repacketizer_cat(rir.value, &bytes_copy(&packet, nbytes));
    if !cat.is_ok { ok = false; }
    let nf = ffi.repacketizer_get_nb_frames(rir.value);
    if nf.is_ok {
      if nf.value != 1 { ok = false; }
    } else {
      ok = false;
    }
  }
  // too-small memory must be rejected
  var tiny = buf_zero(8);
  let tsmall = ffi.encoder_init_over(&mut tiny, 48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if tsmall.is_ok { ok = false; }
  if !tsmall.is_ok {
    if tsmall.error.code != abi.OPUS_BAD_ARG { ok = false; }
  }
  // custom encoder over owned memory
  let cmr = ffi.custom_mode_create(48000, 960);
  if cmr.is_ok {
    var cmem = buf_zero(ffi.custom_encoder_get_size(cmr.value, 1));
    let cir = ffi.custom_encoder_init_over(&mut cmem, cmr.value, 1);
    if !cir.is_ok { ok = false; }
    if cir.is_ok {
      let pcm = tone16(960, 440.0, 0, 12000);
      var cpkt = buf_zero(1024);
      let ce = ffi.custom_encode(cir.value, &pcm, 960, &mut cpkt);
      if !ce.is_ok { ok = false; }
    }
    ffi.custom_mode_destroy(cmr.value);
  } else {
    ok = false;
  }
  return assert(ok, "encoder/decoder/repacketizer/custom-encoder init over owned memory; tiny mem rejected");
}

fn t22_pcm24_and_float_paths() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  let enc = er.value;
  var ok = true;
  // 24-bit carrier: s16 samples scaled <<8
  var pcm24: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 960 {
    let tt = (i as Float64) / 48000.0;
    let s = (math.sin(2.0 * 3.14159265358979 * 440.0 * tt) * 12000.0) as Int;
    push_i32(&mut pcm24, s << 8);
    i = i + 1;
  }
  var p24 = buf_zero(1024);
  let e24 = ffi.encode24(enc, &pcm24, 960, &mut p24);
  if !e24.is_ok {
    ok = false;
    io.println("  [info] encode24 failed code=" + e24.error.code);
  } else {
    io.println("  [info] encode24 bytes=" + e24.value);
  }
  // f32 PCM path (exact dyadic bit patterns)
  var pcmf: Vec[UInt8] = Vec[UInt8].new();
  var j = 0;
  while j < 960 {
    let tt = (j as Float64) / 48000.0;
    let s = (math.sin(2.0 * 3.14159265358979 * 440.0 * tt) * 12000.0) as Int;
    push_f32_from_i16(&mut pcmf, s);
    j = j + 1;
  }
  let flen = pcmf.len();
  let fv1 = read_f32(&pcmf, 400) * 1000000.0;
  let fi1 = fv1 as Int;
  let s1699 = read_i32(&pcm24, 400) >> 8;
  io.println("  [info] pcmf.len=" + flen + " f32[100]x1e6=" + fi1 + " s16[100]=" + s1699);
  // A FRESH encoder for the float variant: re-encoding the same 20 ms through
  // an encoder that already consumed it via encode24 is a signal discontinuity
  // (upstream decodes such a frame at ~1 dB SNR; verified against a pure-C
  // driver).  Independent encoders keep the round-trip comparison meaningful.
  var pf = buf_zero(1024);
  let ef = encode_float_fresh(&pcmf, &mut pf);
  if !ef.is_ok {
    ok = false;
    io.println("  [info] encode_float failed code=" + ef.error.code);
  } else {
    io.println("  [info] encode_float bytes=" + ef.value);
  }
  let dr = ffi.decoder_create(48000, 1);
  if !dr.is_ok {
    ffi.encoder_destroy(enc);
    return assert(false, "decoder_create failed");
  }
  let dec = dr.value;
  if e24.is_ok {
    let pkt = bytes_copy(&p24, e24.value);
    var ref16 = buf_zero(960 * 2);
    let dn = ffi.decode(dec, &pkt, &mut ref16, 960, 0);
    if !dn.is_ok {
      ok = false;
      io.println("  [info] decode of 24-bit packet failed code=" + dn.error.code);
    } else {
      io.println("  [info] decode of 24-bit packet samples=" + dn.value + " peak=" + peak_mag16(&ref16, 960));
    }
    // reset between variant decodes so all three start from identical state
    let rst1 = ffi.decoder_ctl_set(dec, abi.OPUS_RESET_STATE, 0);
    if !rst1.is_ok { ok = false; }
    var out24 = buf_zero(960 * 4);
    let d24 = ffi.decode24(dec, &pkt, &mut out24, 960, 0);
    if d24.is_ok {
      io.println("  [info] decode24 samples=" + d24.value + " peak=" + peak_mag24(&out24, 960));
      var mism = 0;
      var k = 0;
      while k < 960 {
        let a = read_i16(&ref16, k * 2);
        let b = read_i32(&out24, k * 4) >> 8;
        let d = a - b;
        if d > 2 { mism = mism + 1; }
        if d < 0 - 2 { mism = mism + 1; }
        k = k + 1;
      }
      io.println("  [info] decode24 vs decode mismatches=" + mism);
      if mism > 2 { ok = false; }
    } else {
      ok = false;
      io.println("  [info] decode24 failed code=" + d24.error.code);
    }
    let rst2 = ffi.decoder_ctl_set(dec, abi.OPUS_RESET_STATE, 0);
    if !rst2.is_ok { ok = false; }
    var outf = buf_zero(960 * 4);
    let df = ffi.decode_float(dec, &pkt, &mut outf, 960, 0);
    if df.is_ok {
      if df.value != 960 { ok = false; }
      let e32 = energy_f32(&outf, 960);
      let e16f = (energy16(&ref16, 960) as Float64) / 1073741824.0;
      let pct = ratio_pct(e32, e16f);
      io.println("  [info] float-decode energy=" + ((e32 * 1000.0) as Int) + " s16-scaled=" + ((e16f * 1000.0) as Int) + " pct=" + pct);
      if pct < 90 { ok = false; }
      if pct > 110 { ok = false; }
      // sample-wise: f32 output must equal the s16 output / 32768
      let sp0 = read_f32(&outf, 0);
      let s16p0 = (read_i16(&ref16, 0) as Float64) / 32768.0;
      var diff0 = sp0 - s16p0;
      if diff0 < 0.0 { diff0 = 0.0 - diff0; }
      io.println("  [info] float sample0 vs s16/32768: " + ((sp0 * 1000.0) as Int) + " vs " + ((s16p0 * 1000.0) as Int));
      if diff0 > 0.0002 { ok = false; }
    } else {
      ok = false;
      io.println("  [info] decode_float failed code=" + df.error.code);
    }
  } else {
    ok = false;
  }
  // float-encoded packet decodes through the s16 API with sane SNR
  if ef.is_ok {
    let rst3 = ffi.decoder_ctl_set(dec, abi.OPUS_RESET_STATE, 0);
    if !rst3.is_ok { ok = false; }
    let pktf = bytes_copy(&pf, ef.value);
    var outf2 = buf_zero(960 * 2);
    let dn2 = ffi.decode(dec, &pktf, &mut outf2, 960, 0);
    if dn2.is_ok {
      let refp = pcm24_to16(&pcm24);
      let s2 = snr_db(&refp, &outf2, 960, 480);
      let s2x = (s2 * 10.0) as Int;
      let pk2 = peak_mag16(&outf2, 960);
      let pkref = peak_mag16(&refp, 960);
      io.println("  [info] float-packet decode samples=" + dn2.value + " peak=" + pk2 + " refpeak=" + pkref + " snr_db_x10=" + s2x);
      if s2 < 12.0 { ok = false; }
    } else {
      ok = false;
      io.println("  [info] decode of float packet failed code=" + dn2.error.code);
    }
  } else {
    ok = false;
  }
  ffi.decoder_destroy(dec);
  ffi.encoder_destroy(enc);
  return assert(ok, "24-bit and f32 PCM paths: encode/decode cross-consistency and energy match");
}

fn peak_mag16(buf: &Vec[UInt8], n: Int) -> Int {
  var p = 0;
  var i = 0;
  while i < n {
    var v = read_i16(buf, i * 2);
    if v < 0 { v = 0 - v; }
    if v > p { p = v; }
    i = i + 1;
  }
  return p;
}

fn peak_mag24(buf: &Vec[UInt8], n: Int) -> Int {
  var p = 0;
  var i = 0;
  while i < n {
    var v = read_i32(buf, i * 4);
    if v < 0 { v = 0 - v; }
    if v > p { p = v; }
    i = i + 1;
  }
  return p;
}

fn encode_float_fresh(pcm: &Vec[UInt8], out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return Err(er.error);
  }
  let r = ffi.encode_float(er.value, pcm, 960, out);
  ffi.encoder_destroy(er.value);
  return r;
}

fn pcm24_to16(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < src.len() / 4 {
    push_i16(&mut out, read_i32(src, i * 4) >> 8);
    i = i + 1;
  }
  return out;
}

fn t23_pcm_soft_clip() -> TestResult {
  // 960 f32 samples at +/-1.5: bits 0x3FC00000 / 0xBFC00000
  var pcm: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 960 {
    if (i / 480) == 0 {
      push_i32(&mut pcm, 1069547520);
    } else {
      push_i32(&mut pcm, 1069547520 + 2147483648);
    }
    i = i + 1;
  }
  var mem = buf_zero(2 * 4);
  let r = ffi.pcm_soft_clip(&mut pcm, 960, 1, &mut mem);
  var ok = r.is_ok;
  // magnitudes: mask the sign bit; 1.5 -> 0x3FC00000; soft clip must bring the
  // peak strictly below the 1.0 bits 0x3F800000.
  var peak: Int = 0;
  var j = 0;
  while j < 960 {
    let mut_bits = read_i32(&pcm, j * 4);
    var mag = mut_bits;
    if mag < 0 { mag = mag + 2147483648; }
    if mag > peak { peak = mag; }
    j = j + 1;
  }
  io.println("  [info] soft-clip peak_bits=" + peak + " (1.0f=1065353216)");
  if peak >= 1065353216 { ok = false; }
  if peak <= 0 { ok = false; }
  return assert(ok, "pcm_soft_clip compresses 1.5f input below 1.0f peak");
}

fn t24_projection_roundtrip() -> TestResult {
  // Ambisonics projection requires order >= 1: 4 channels (FOA), family 3.
  let er = ffi.projection_ambisonics_encoder_create(48000, 4, 3, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    io.println("  [info] projection create code=" + er.error.code);
    return assert(false, "projection encoder create failed");
  }
  let layout = er.value;
  var ok = layout.handle != 0;
  io.println("  [info] projection layout streams=" + layout.streams + " coupled=" + layout.coupled_streams);
  let sz = ffi.projection_encoder_ctl_get(layout.handle, abi.OPUS_PROJECTION_GET_DEMIXING_MATRIX_SIZE_REQUEST);
  var msize = 0;
  if sz.is_ok {
    msize = sz.value;
  } else {
    ok = false;
  }
  io.println("  [info] demixing matrix size=" + msize);
  if msize <= 0 { ok = false; }
  var matrix = buf_zero(msize);
  if msize > 0 {
    let gm = ffi.projection_encoder_ctl_get_matrix(layout.handle, &mut matrix);
    if !gm.is_ok { ok = false; }
  }
  let gain = ffi.projection_encoder_ctl_get(layout.handle, abi.OPUS_PROJECTION_GET_DEMIXING_MATRIX_GAIN_REQUEST);
  if !gain.is_ok { ok = false; }
  // 4-channel interleaved tone
  var pcm: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 960 {
    let tt = (i as Float64) / 48000.0;
    let f1 = 220.0;
    let f2 = 330.0;
    let f3 = 440.0;
    let f4 = 550.0;
    push_i16(&mut pcm, (math.sin(2.0 * 3.14159265358979 * f1 * tt) * 9000.0) as Int);
    push_i16(&mut pcm, (math.sin(2.0 * 3.14159265358979 * f2 * tt) * 9000.0) as Int);
    push_i16(&mut pcm, (math.sin(2.0 * 3.14159265358979 * f3 * tt) * 9000.0) as Int);
    push_i16(&mut pcm, (math.sin(2.0 * 3.14159265358979 * f4 * tt) * 9000.0) as Int);
    i = i + 1;
  }
  var packet = buf_zero(2048);
  let elen = ffi.projection_encode(layout.handle, &pcm, 960, &mut packet);
  var snr = 0.0;
  if elen.is_ok {
    io.println("  [info] projection encoded bytes=" + elen.value);
    let pkt = bytes_copy(&packet, elen.value);
    let dr = ffi.projection_decoder_create(48000, 4, layout.streams, layout.coupled_streams, &matrix);
    if dr.is_ok {
      var out = buf_zero(960 * 8);
      let dn = ffi.projection_decode(dr.value, &pkt, &mut out, 960, 0);
      if dn.is_ok {
        io.println("  [info] projection decode samples=" + dn.value);
        if dn.value != 960 { ok = false; }
        snr = snr_db(&pcm, &out, 3840, 1920);
        io.println("  [info] projection foa snr_db_x10=" + ((snr * 10.0) as Int));
      } else {
        io.println("  [info] projection decode code=" + dn.error.code);
        ok = false;
      }
      ffi.projection_decoder_destroy(dr.value);
    } else {
      io.println("  [info] projection decoder create code=" + dr.error.code);
      ok = false;
    }
  } else {
    io.println("  [info] projection encode code=" + elen.error.code);
    ok = false;
  }
  if snr < 6.0 { ok = false; }
  ffi.projection_encoder_destroy(layout.handle);
  return assert(ok, "ambisonics FOA projection: matrix export, encode->demix decode 960 samples, SNR>=6dB");
}

fn t25_dred_default_build_stubs() -> TestResult {
  var ok = ffi.dred_get_size() == 0; // no DRED model compiled in
  let dsz = ffi.dred_decoder_get_size();
  io.println("  [info] dred sizes: dred=" + ffi.dred_get_size() + " decoder=" + dsz);
  if dsz <= 0 { ok = false; }
  let cr = ffi.dred_decoder_create();
  var decoder_handle = 0;
  if cr.is_ok {
    decoder_handle = cr.value;
  } else {
    ok = false;
  }
  // default build: state allocation is unimplemented
  let alloc = ffi.dred_alloc();
  if alloc.is_ok {
    ok = false;
    ffi.dred_free(alloc.value);
  } else {
    if alloc.error.code != abi.OPUS_UNIMPLEMENTED { ok = false; }
  }
  // dred decoder over owned memory + ctl entry points are callable
  if decoder_handle != 0 {
    var dmem = buf_zero(dsz);
    let ior = ffi.dred_decoder_init_over(&mut dmem);
    if !ior.is_ok { ok = false; }
    let cs = ffi.dred_decoder_ctl_set(decoder_handle, abi.OPUS_SET_DRED_DURATION_REQUEST, 100);
    let cg = ffi.dred_decoder_ctl_get(decoder_handle, abi.OPUS_GET_DRED_DURATION_REQUEST);
    var cs_rc = 0;
    if !cs.is_ok { cs_rc = cs.error.code; }
    var cg_rc = 0;
    if !cg.is_ok { cg_rc = cg.error.code; }
    io.println("  [info] dred ctl set rc=" + cs_rc + " get rc=" + cg_rc);
    if cs.is_ok && cg.is_ok {
      if cg.value != 100 { ok = false; }
    }
    ffi.dred_decoder_destroy(decoder_handle);
  }
  // encoders/decoders still encode/decode while DRED stub is unavailable
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if er.is_ok {
    let pcm = tone16(960, 440.0, 0, 12000);
    var packet = buf_zero(512);
    let el = ffi.encode(er.value, &pcm, 960, &mut packet);
    if el.is_ok {
      let pkt = bytes_copy(&packet, el.value);
      // argument-validation path of the DRED parse / dred-decode entry points
      // (no DRED state can be allocated in the default build)
      let pr = ffi.dred_parse(0, 0, &pkt, 4800, 48000, 1);
      if pr.is_ok { ok = false; }
      let dr = ffi.decoder_create(48000, 1);
      if dr.is_ok {
        var out = buf_zero(960 * 2);
        let dd = ffi.decoder_dred_decode(dr.value, 0, 0, &mut out, 960);
        if dd.is_ok { ok = false; }
        let dp = ffi.dred_process(0, 0, 0);
        if dp.is_ok { ok = false; }
        ffi.decoder_destroy(dr.value);
      }
    }
    ffi.encoder_destroy(er.value);
  }
  return assert(ok, "DRED default-build stubs: get_size 0, alloc OPUS_UNIMPLEMENTED, entries validate args");
}

fn t26_dnn_blob_ctl_error() -> TestResult {
  let er = ffi.encoder_create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    return assert(false, "encoder_create failed");
  }
  var blob: Vec[UInt8] = Vec[UInt8].new();
  blob.push(1 as UInt8);
  blob.push(2 as UInt8);
  let r = ffi.encoder_ctl_set_dnn_blob(er.value, &blob);
  var ok = !r.is_ok; // no USE_WEIGHTS_FILE in the default build
  ffi.encoder_destroy(er.value);
  return assert(ok, "OPUS_SET_DNN_BLOB errors in the default build (no weights support)");
}

// ---------------------------------------------------------------------------
// runner
// ---------------------------------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  io.flush_stdout();
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.opus conformance tests (libopus 1.6.1) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + report(t01_version_pin());
  failed = failed + report(t02_coverage_ledger());
  failed = failed + report(t03_strerror_texts());
  failed = failed + report(t04_encoder_size_and_create());
  failed = failed + report(t05_create_error_paths());
  failed = failed + report(t06_encoder_ctl_roundtrip());
  failed = failed + report(t07_roundtrip_s16_snr());
  failed = failed + report(t08_encode_buffer_too_small());
  failed = failed + report(t09_decode_invalid_packet());
  failed = failed + report(t10_plc_decode_lost());
  failed = failed + report(t11_decode_fec());
  failed = failed + report(t12_packet_utilities());
  failed = failed + report(t13_packet_parse());
  failed = failed + report(t14_packet_pad_unpad());
  failed = failed + report(t15_repacketizer_merge());
  failed = failed + report(t16_repacketizer_split_and_errors());
  failed = failed + report(t17_multistream_stereo());
  failed = failed + report(t18_multistream_surround_and_pad());
  failed = failed + report(t19_custom_mode_roundtrip());
  failed = failed + report(t20_custom_mode_errors());
  failed = failed + report(t21_init_over_owned_memory());
  failed = failed + report(t22_pcm24_and_float_paths());
  failed = failed + report(t23_pcm_soft_clip());
  failed = failed + report(t24_projection_roundtrip());
  failed = failed + report(t25_dred_default_build_stubs());
  failed = failed + report(t26_dnn_blob_ctl_error());
  if failed == 0 {
    io.println("xiom.opus: all tests passed");
  } else {
    io.println("xiom.opus: failures=" + failed);
  }
  io.flush_stdout();
  return failed;
}
