// xiom.openpgl conformance suite -- vendored Open PGL v0.7.1 core.
//
// Build+run (the --c-source list rides in port.args.json; the vendored core
// needs C++17, carried by the pinned compiler):
//   scripts/port.ps1 -Package xiom.openpgl -TimeoutSec 1500
//
// Covers the declared 0.1.0 surface: device creation, guiding field creation,
// sample storage create/reserve/clear + deterministic sample feed, training
// iterations, surface sampling distribution init/sample/PDF/samplePDF queries,
// field statistics snapshots (owned-buffer byte-indexed reads), typed misuse
// errors, and bit-reproducible repeat runs.

module openpgl_conformance

use xiom.io;
use xiom.math;
use xiom.string;
use xiom.openpgl;

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

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

// Float diagnostics: two decimals via integer scaling (no printf dependency).
fn f2s(x: Float32) -> Str {
  var v = x;
  var neg = false;
  if v < 0.0 {
    neg = true;
    v = 0.0 - v;
  }
  let scaled = (v * 100.0 + 0.5) as Int;
  let ip = scaled / 100;
  let fp = scaled % 100;
  var frac = i2s(fp);
  if fp < 10 { frac = "0" + frac; }
  if neg { return "-" + i2s(ip) + "." + frac; }
  return i2s(ip) + "." + frac;
}

fn finite32(x: Float32) -> Bool {
  // NaN fails x == x; infinities fail the magnitude bound.
  return x == x && x <= 3.4e38 && x >= -3.4e38;
}

// --- deterministic sample feed ----------------------------------------------

const NUM_SAMPLES: Int = 256;

// Exact grid (binary-representable): x/z in [-1, 0.875] at 1/8 steps,
// y in {0, 1/8, 1/4}; directions lean towards +y with a deterministic spread.
fn sample_px(i: Int) -> Float32 {
  return ((i % 16) - 8) as Float32 * 0.125;
}

fn sample_py(i: Int) -> Float32 {
  return (i % 3) as Float32 * 0.125;
}

fn sample_pz(i: Int) -> Float32 {
  return ((i / 16) % 16 - 8) as Float32 * 0.125;
}

fn build_samples() -> Vec[Float32] {
  var buf: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < NUM_SAMPLES {
    let u = ((i * 37) % 100) as Float32 / 100.0;
    let v = ((i * 61) % 100) as Float32 / 100.0;
    let dx0 = (u - 0.5) * 0.5;
    let dz0 = (v - 0.5) * 0.5;
    let len = math.sqrt((dx0 as Float64) * (dx0 as Float64) + 1.0 + (dz0 as Float64) * (dz0 as Float64));
    let inv = (1.0 / len) as Float32;
    sample_push(&mut buf, sample_px(i), sample_py(i), sample_pz(i), dx0 * inv, 1.0 * inv, dz0 * inv,
      1.0, 1.0, 1.0 + (i % 7) as Float32 * 0.25, PGL_FLAG_SURFACE);
    i = i + 1;
  }
  return buf;
}

// --- pipeline result + full training flow -----------------------------------

type PipelineResult = {
  ok: Bool;
  step: Str;
  iteration: Int;
  pdf_fixed: Float32;
  pdf_sampled_a: Float32;
  pdf_sampled_b: Float32;
  sx: Float32;
  sy: Float32;
  sz: Float32;
  dist_id: Int;
  stats_len: Int;
  bounds_ok: Bool;
}

fn fail_at(step: Str, err: PglError) -> PipelineResult {
  return PipelineResult{
    ok: false;
    step: step + " code=" + i2s(err.code);
    iteration: -1; pdf_fixed: -1.0; pdf_sampled_a: -1.0; pdf_sampled_b: -1.0;
    sx: 0.0; sy: 0.0; sz: 0.0; dist_id: -1; stats_len: 0; bounds_ok: false;
  };
}

fn pipeline_ok(iter: Int, pdf_fixed: Float32, pdf_a: Float32, pdf_b: Float32,
    sx: Float32, sy: Float32, sz: Float32, dist_id: Int, stats_len: Int,
    bounds_ok: Bool) -> PipelineResult {
  return PipelineResult{
    ok: true;
    step: "done";
    iteration: iter; pdf_fixed: pdf_fixed; pdf_sampled_a: pdf_a; pdf_sampled_b: pdf_b;
    sx: sx; sy: sy; sz: sz; dist_id: dist_id; stats_len: stats_len; bounds_ok: bounds_ok;
  };
}

// Feed -> train x3 -> init distribution at a trained-grid position -> sample +
// PDF queries -> statistics snapshot.  Everything owned is released here;
// the caller only keeps exported scalar copies.
fn run_pipeline() -> PipelineResult {
  let dev_r = device_create(PGL_DEVICE_CPU_4, 1);
  if !dev_r.is_ok { return fail_at("device_create", dev_r.error); }
  let dev = dev_r.value;

  let field_r = field_create(dev, true, 5000);
  if !field_r.is_ok { return fail_at("field_create", field_r.error); }
  let field = field_r.value;

  let stor_r = storage_create();
  if !stor_r.is_ok { return fail_at("storage_create", stor_r.error); }
  let storage = stor_r.value;

  let reserve_r = storage_reserve(storage, NUM_SAMPLES, 0);
  if !reserve_r.is_ok { return fail_at("storage_reserve", reserve_r.error); }

  var buf = build_samples();
  let add_r = storage_add_samples(storage, &mut buf, NUM_SAMPLES);
  if !add_r.is_ok { return fail_at("storage_add_samples", add_r.error); }

  var iter: Int = 0;
  while iter < 3 {
    let train_r = field_train(field, storage);
    if !train_r.is_ok { return fail_at("field_train", train_r.error); }
    iter = iter + 1;
  }
  let it_r = field_iteration(field);
  if !it_r.is_ok { return fail_at("field_iteration", it_r.error); }

  let bounds_r = field_scene_bounds(field);
  if !bounds_r.is_ok { return fail_at("field_scene_bounds", bounds_r.error); }
  let in_bounds = bounds_r.value.lx <= 0.25 && bounds_r.value.ux >= 0.25
    && bounds_r.value.ly <= 0.125 && bounds_r.value.uy >= 0.125
    && bounds_r.value.lz <= 0.25 && bounds_r.value.uz >= 0.25;

  let dist_r = sampling_distribution_create(field);
  if !dist_r.is_ok { return fail_at("sampling_distribution_create", dist_r.error); }
  let dist = dist_r.value;

  let pos = PglVec3{ x: 0.25; y: 0.125; z: 0.25 };
  let init_r = sampling_distribution_init(field, dist, pos, 0.5);
  if !init_r.is_ok { return fail_at("sampling_distribution_init", init_r.error); }

  // Fixed-direction PDF query.
  let ref_dir = PglVec3{ x: 0.0; y: 1.0; z: 0.0 };
  let pdf_r = sampling_distribution_pdf(dist, ref_dir);
  if !pdf_r.is_ok { return fail_at("sampling_distribution_pdf", pdf_r.error); }

  // Sampled direction + SamplePDF cross-check.
  let s_r = sampling_distribution_sample(dist, 0.25, 0.75);
  if !s_r.is_ok { return fail_at("sampling_distribution_sample", s_r.error); }
  let pdf_dir_r = sampling_distribution_pdf(dist, s_r.value);
  if !pdf_dir_r.is_ok { return fail_at("sampling_distribution_pdf(sampled)", pdf_dir_r.error); }
  let sp_r = sampling_distribution_sample_pdf(dist, 0.25, 0.75);
  if !sp_r.is_ok { return fail_at("sampling_distribution_sample_pdf", sp_r.error); }

  let id_r = sampling_distribution_id(dist);
  if !id_r.is_ok { return fail_at("sampling_distribution_id", id_r.error); }

  let stats_r = statistics_snapshot(field);
  if !stats_r.is_ok { return fail_at("statistics_snapshot", stats_r.error); }
  let text_r = statistics_text(stats_r.value);
  if !text_r.is_ok { return fail_at("statistics_text", text_r.error); }
  let stats_d = statistics_destroy(stats_r.value);
  if !stats_d.is_ok { return fail_at("statistics_destroy", stats_d.error); }

  let dist_d = sampling_distribution_destroy(dist);
  if !dist_d.is_ok { return fail_at("sampling_distribution_destroy", dist_d.error); }
  let stor_d = storage_destroy(storage);
  if !stor_d.is_ok { return fail_at("storage_destroy", stor_d.error); }
  let field_d = field_destroy(field);
  if !field_d.is_ok { return fail_at("field_destroy", field_d.error); }
  let dev_d = device_destroy(dev);
  if !dev_d.is_ok { return fail_at("device_destroy", dev_d.error); }

  return pipeline_ok(it_r.value, pdf_r.value, pdf_dir_r.value, sp_r.value.pdf,
    s_r.value.x, s_r.value.y, s_r.value.z, id_r.value, text_r.value.len(), in_bounds);
}

// --- misuse / typed-error probes ---------------------------------------------

// Each probe returns true when the call failed with the expected typed code.
fn misuse_probe() -> Bool {
  // 1. invalid device types (3, and 8 = the AVX2 device this port does not
  // build: only CPU_4/SSE2-baseline kernels are compiled, see SPEC.md 1).
  let d1 = device_create(3, 1);
  if d1.is_ok { return false; }
  if d1.error.code != PGL_ERR_INVALID_ARG { return false; }
  let d8 = device_create(PGL_DEVICE_CPU_8, 1);
  if d8.is_ok { return false; }
  if d8.error.code != PGL_ERR_INVALID_ARG { return false; }

  // 2. stale device handle + field creation on a stale device.
  let d2 = device_create(PGL_DEVICE_CPU_4, 1);
  if !d2.is_ok { return false; }
  let dev = d2.value;
  let r1 = device_destroy(dev);
  if !r1.is_ok { return false; }
  let r2 = device_destroy(dev);
  if r2.is_ok { return false; }
  if r2.error.code != PGL_ERR_INVALID_HANDLE { return false; }
  let f1 = field_create(dev, true, 5000);
  if f1.is_ok { return false; }
  if f1.error.code != PGL_ERR_INVALID_HANDLE { return false; }

  // 3. empty-storage training.
  let d3 = device_create(PGL_DEVICE_CPU_4, 1);
  if !d3.is_ok { return false; }
  let dev3 = d3.value;
  let f3 = field_create(dev3, true, 5000);
  if !f3.is_ok { return false; }
  let s3 = storage_create();
  if !s3.is_ok { return false; }
  let train = field_train(f3.value, s3.value);
  if train.is_ok { return false; }
  if train.error.code != PGL_ERR_EMPTY_STORAGE { return false; }

  // 4. invalid sample (pdf = 0) is rejected atomically: storage stays empty.
  var bad: Vec[Float32] = Vec[Float32].new();
  sample_push(&mut bad, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, PGL_FLAG_SURFACE);
  sample_push(&mut bad, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, PGL_FLAG_SURFACE);
  let add = storage_add_samples(s3.value, &mut bad, 2);
  if add.is_ok { return false; }
  if add.error.code != PGL_ERR_INVALID_ARG { return false; }
  let sz = storage_size_surface(s3.value);
  if !sz.is_ok { return false; }
  if sz.value != 0 { return false; }

  // 5. uncovered position after a real training run.
  var good = build_samples();
  let add2 = storage_add_samples(s3.value, &mut good, NUM_SAMPLES);
  if !add2.is_ok { return false; }
  let t2 = field_train(f3.value, s3.value);
  if !t2.is_ok { return false; }
  let dist4 = sampling_distribution_create(f3.value);
  if !dist4.is_ok { return false; }
  let far = PglVec3{ x: 1000.0; y: 1000.0; z: 1000.0 };
  let init_far = sampling_distribution_init(f3.value, dist4.value, far, 0.5);
  if init_far.is_ok { return false; }
  if init_far.error.code != PGL_ERR_UNCOVERED { return false; }

  // 6. stale storage handle.
  let sd = storage_destroy(s3.value);
  if !sd.is_ok { return false; }
  let sz2 = storage_size_surface(s3.value);
  if sz2.is_ok { return false; }
  if sz2.error.code != PGL_ERR_INVALID_HANDLE { return false; }

  // 7. statistics capacity misuse (2-byte slot for a much larger text).
  let stats = statistics_snapshot(f3.value);
  if !stats.is_ok { return false; }
  var tiny = blank_bytes(2);
  let into = statistics_text_into(stats.value, &mut tiny, 2);
  if into.is_ok { return false; }
  if into.error.code != PGL_ERR_CAPACITY { return false; }
  let big = statistics_text(stats.value);
  if !big.is_ok { return false; }
  if big.value.len() <= 2 { return false; }
  let std_ = statistics_destroy(stats.value);
  if !std_.is_ok { return false; }

  let dd4 = sampling_distribution_destroy(dist4.value);
  if !dd4.is_ok { return false; }
  let fd3 = field_destroy(f3.value);
  if !fd3.is_ok { return false; }
  let dd3 = device_destroy(dev3);
  if !dd3.is_ok { return false; }
  return true;
}

// --- statistics content (owned-buffer byte-indexed reads) ---------------------

type StatsProbeResult = {
  ok: Bool;
  step: Str;
  len: Int;
  printable: Bool;
  same_header: Bool;
  csv_len: Int;
}

fn stats_fail(step: Str) -> StatsProbeResult {
  return StatsProbeResult{
    ok: false; step: step; len: 0; printable: false; same_header: false; csv_len: 0;
  };
}

fn stats_probe() -> StatsProbeResult {
  let dev_r = device_create(PGL_DEVICE_CPU_4, 1);
  if !dev_r.is_ok { return stats_fail("device_create"); }
  let dev = dev_r.value;
  let field_r = field_create(dev, true, 5000);
  if !field_r.is_ok { return stats_fail("field_create"); }
  let field = field_r.value;
  let stor_r = storage_create();
  if !stor_r.is_ok { return stats_fail("storage_create"); }
  let storage = stor_r.value;
  var buf = build_samples();
  let add_r = storage_add_samples(storage, &mut buf, NUM_SAMPLES);
  if !add_r.is_ok { return stats_fail("storage_add_samples"); }
  let train_r = field_train(field, storage);
  if !train_r.is_ok { return stats_fail("field_train"); }

  // Snapshot 1: raw owned-slot read, byte-indexed by our own loop.  The
  // statistics text is ASCII plus tab/newline control bytes.
  let stats1 = statistics_snapshot(field);
  if !stats1.is_ok { return stats_fail("statistics_snapshot(1)"); }
  let cap: Int = 65536;
  var slot = blank_bytes(cap);
  let len_r = statistics_text_into(stats1.value, &mut slot, cap);
  if !len_r.is_ok { return stats_fail("statistics_text_into"); }
  let len = len_r.value;
  var printable = true;
  var i: Int = 0;
  while i < len {
    let b = slot[i] as Int;
    let ok_byte = b == 9 || b == 10 || b == 13 || (b >= 32 && b <= 126);
    if !ok_byte { printable = false; }
    i = i + 1;
  }
  let header1_r = statistics_csv_header(stats1.value);
  if !header1_r.is_ok { return stats_fail("statistics_csv_header(1)"); }

  // Snapshot 2 (same field): CSV header must be byte-identical (str_compare).
  let stats2 = statistics_snapshot(field);
  if !stats2.is_ok { return stats_fail("statistics_snapshot(2)"); }
  let header2_r = statistics_csv_header(stats2.value);
  if !header2_r.is_ok { return stats_fail("statistics_csv_header(2)"); }
  let same_header = string.str_compare(header1_r.value, header2_r.value) == 0;

  let csv_r = statistics_csv(stats2.value);
  if !csv_r.is_ok { return stats_fail("statistics_csv"); }
  let csv_len = csv_r.value.len();

  let d1 = statistics_destroy(stats1.value);
  let d2 = statistics_destroy(stats2.value);
  let ds = storage_destroy(storage);
  let df = field_destroy(field);
  let dv = device_destroy(dev);

  if !(d1.is_ok && d2.is_ok && ds.is_ok && df.is_ok && dv.is_ok) {
    return stats_fail("release sequence");
  }
  return StatsProbeResult{
    ok: true; step: "done"; len: len; printable: printable;
    same_header: same_header; csv_len: csv_len;
  };
}

fn main() -> Int {
  io.println("=== xiom.openpgl conformance tests (vendored Open PGL v0.7.1) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Full pipeline: feed + train + query.
  let p = run_pipeline();
  if p.ok {
    failed = failed + report(p.bounds_ok, "pipeline: scene bounds contain the query position");
    failed = failed + report(p.iteration == 3, "pipeline: 3 training iterations recorded");
    failed = failed + report(finite32(p.pdf_fixed) && p.pdf_fixed >= 0.0 && p.pdf_fixed <= 200000.0,
      "query: fixed-direction PDF in range (" + f2s(p.pdf_fixed) + ")");
    let dir2 = p.sx * p.sx + p.sy * p.sy + p.sz * p.sz;
    failed = failed + report(finite32(p.sx) && finite32(p.sy) && finite32(p.sz)
      && dir2 >= 0.99 && dir2 <= 1.01,
      "query: sampled direction is unit length (n2=" + f2s(dir2) + ")");
    failed = failed + report(finite32(p.pdf_sampled_a) && p.pdf_sampled_a >= 0.0 && p.pdf_sampled_a <= 200000.0,
      "query: sampled-direction PDF in range (" + f2s(p.pdf_sampled_a) + ")");
    let pdf_match = p.pdf_sampled_a >= p.pdf_sampled_b - 0.001 && p.pdf_sampled_a <= p.pdf_sampled_b + 0.001;
    failed = failed + report(finite32(p.pdf_sampled_b) && pdf_match,
      "query: PDF and SamplePDF agree (" + f2s(p.pdf_sampled_a) + " vs " + f2s(p.pdf_sampled_b) + ")");
    failed = failed + report(p.dist_id >= 0, "query: distribution id present (" + i2s(p.dist_id) + ")");
    failed = failed + report(p.stats_len > 0, "stats: statistics text non-empty (" + i2s(p.stats_len) + " bytes)");
  } else {
    failed = failed + report(false, "pipeline failed at " + p.step);
  }

  // 2. Deterministic repeat runs: the field content of a second full pipeline
  // is bit-identical.  (The statistics *text* embeds upstream wall-clock
  // timing fields -- timeLastUpdate* -- so it is deliberately not compared;
  // its CSV header stability is checked separately in the stats probe.)
  let p2 = run_pipeline();
  let same = p.ok && p2.ok && p.iteration == p2.iteration
    && p.pdf_fixed == p2.pdf_fixed
    && p.pdf_sampled_a == p2.pdf_sampled_a
    && p.pdf_sampled_b == p2.pdf_sampled_b
    && p.sx == p2.sx && p.sy == p2.sy && p.sz == p2.sz
    && p.dist_id == p2.dist_id;
  failed = failed + report(same, "determinism: repeat run bit-identical");
  if !same && p.ok && p2.ok {
    io.println("    fixed pdf: " + f2s(p.pdf_fixed) + " vs " + f2s(p2.pdf_fixed));
    io.println("    sampled dir: (" + f2s(p.sx) + "," + f2s(p.sy) + "," + f2s(p.sz)
      + ") vs (" + f2s(p2.sx) + "," + f2s(p2.sy) + "," + f2s(p2.sz) + ")");
  }

  // 3. Typed misuse errors.
  failed = failed + report(misuse_probe(), "misuse: typed errors (arg/handle/empty/capacity/uncovered)");

  // 4. Statistics content via owned-buffer byte-indexed reads.
  let sp = stats_probe();
  if sp.ok {
    failed = failed + report(sp.len > 0, "stats: statistics text non-empty (" + i2s(sp.len) + " bytes)");
    failed = failed + report(sp.printable, "stats: statistics text is ASCII (tab/newline allowed)");
    failed = failed + report(sp.same_header, "stats: CSV header byte-stable across snapshots (str_compare)");
    failed = failed + report(sp.csv_len > 0, "stats: CSV row non-empty (" + i2s(sp.csv_len) + " bytes)");
  } else {
    failed = failed + report(false, "stats probe failed at " + sp.step);
  }

  if failed == 0 {
    io.println("xiom.openpgl: all tests passed");
  } else {
    io.println("xiom.openpgl: tests failed");
  }
  return failed;
}
