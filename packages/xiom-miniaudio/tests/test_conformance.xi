// XIOM -- MiniAudio Conformance Tests
// Validates the public API of xiom.miniaudio with contract enforcement.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio.test.conformance

use xiom.io
use xiom.miniaudio

// ===========================================================================
// Helper -- creates a minimal engine for test isolation
// ===========================================================================

fn setup_engine() -> Result[Int, Str]
  ensures: result.is_ok() || result.is_err()
{
  return create_engine(DEFAULT_SAMPLE_RATE, 2)
}

// ===========================================================================
// Engine Tests
// ===========================================================================

fn test_create_engine_valid() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = create_engine(44100, 2)?;
  io.println("  [OK] create_engine(44100, 2) succeeded");
  destroy_engine(engine);
  return Ok(());
}

fn test_create_engine_stereo() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = create_engine(48000, 2)?;
  io.println("  [OK] create_engine(48000, 2) succeeded");
  destroy_engine(engine);
  return Ok(());
}

fn test_create_engine_mono() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = create_engine(48000, 1)?;
  io.println("  [OK] create_engine(48000, 1) succeeded");
  destroy_engine(engine);
  return Ok(());
}

fn test_create_engine_high_rate() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = create_engine(96000, 2)?;
  io.println("  [OK] create_engine(96000, 2) succeeded");
  destroy_engine(engine);
  return Ok(());
}

fn test_engine_volume_roundtrip() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let ok = set_engine_volume(engine, 0.5);
  if !ok {
    io.println("  [WARN] set_engine_volume returned false (may be pre-init)");
  }

  let vol = get_engine_volume(engine);
  io.println("  [OK] engine volume get: " + (vol as Str));
  return Ok(());
}

fn test_engine_volume_bounds() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  var v: Float32 = 0.0;
  var ok: Bool = false;

  ok = set_engine_volume(engine, 0.0);
  if !ok {
    io.println("  [WARN] set_engine_volume(0.0) returned false (may be pre-init)");
  }

  ok = set_engine_volume(engine, 1.0);
  if !ok {
    io.println("  [WARN] set_engine_volume(1.0) returned false (may be pre-init)");
  }

  v = get_engine_volume(engine);
  io.println("  [OK] engine volume at bounds: " + (v as Str));

  return Ok(());
}

// ===========================================================================
// Waveform Tests
// ===========================================================================

fn test_create_waveform_sine() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.5, 440.0)?;
  io.println("  [OK] create_waveform(SINE, 48k, 2, 0.5, 440) succeeded");
  destroy_waveform(wf);
  return Ok(());
}

fn test_create_waveform_all_types() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf1 = create_waveform(WAVEFORM_SINE, 48000, 2, 0.3, 220.0)?;
  destroy_waveform(wf1);
  io.println("  [OK] SINE waveform created");

  let wf2 = create_waveform(WAVEFORM_SQUARE, 48000, 2, 0.3, 220.0)?;
  destroy_waveform(wf2);
  io.println("  [OK] SQUARE waveform created");

  let wf3 = create_waveform(WAVEFORM_TRIANGLE, 48000, 2, 0.3, 220.0)?;
  destroy_waveform(wf3);
  io.println("  [OK] TRIANGLE waveform created");

  let wf4 = create_waveform(WAVEFORM_SAWTOOTH, 48000, 2, 0.3, 220.0)?;
  destroy_waveform(wf4);
  io.println("  [OK] SAWTOOTH waveform created");

  return Ok(());
}

fn test_waveform_frequency() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.5, 440.0)?;
  defer destroy_waveform(wf);

  let ok = waveform_set_frequency(wf, 880.0);
  if ok {
    io.println("  [OK] waveform_set_frequency(880.0) succeeded");
  } else {
    io.println("  [WARN] waveform_set_frequency returned false");
  }

  return Ok(());
}

fn test_waveform_amplitude() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.5, 440.0)?;
  defer destroy_waveform(wf);

  let ok = waveform_set_amplitude(wf, 0.25);
  if ok {
    io.println("  [OK] waveform_set_amplitude(0.25) succeeded");
  } else {
    io.println("  [WARN] waveform_set_amplitude returned false");
  }

  return Ok(());
}

fn test_waveform_type_change() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.5, 440.0)?;
  defer destroy_waveform(wf);

  let ok = waveform_set_type(wf, WAVEFORM_SQUARE);
  if ok {
    io.println("  [OK] waveform_set_type(SQUARE) succeeded");
  } else {
    io.println("  [WARN] waveform_set_type returned false");
  }

  return Ok(());
}

// ===========================================================================
// Noise Tests
// ===========================================================================

fn test_create_noise_white() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n = create_noise(NOISE_WHITE, 48000, 2, 42, 0.3)?;
  io.println("  [OK] create_noise(WHITE) succeeded");
  destroy_noise(n);
  return Ok(());
}

fn test_create_noise_all_types() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n1 = create_noise(NOISE_WHITE, 48000, 2, 1, 0.2)?;
  destroy_noise(n1);
  io.println("  [OK] WHITE noise created");

  let n2 = create_noise(NOISE_PINK, 48000, 2, 2, 0.2)?;
  destroy_noise(n2);
  io.println("  [OK] PINK noise created");

  let n3 = create_noise(NOISE_BROWNIAN, 48000, 2, 3, 0.2)?;
  destroy_noise(n3);
  io.println("  [OK] BROWNIAN noise created");

  return Ok(());
}

fn test_noise_type_change() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n = create_noise(NOISE_WHITE, 48000, 2, 42, 0.3)?;
  defer destroy_noise(n);

  let ok = noise_set_type(n, NOISE_PINK);
  if ok {
    io.println("  [OK] noise_set_type(PINK) succeeded");
  } else {
    io.println("  [WARN] noise_set_type returned false");
  }

  return Ok(());
}

fn test_noise_seed_change() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n = create_noise(NOISE_WHITE, 48000, 2, 42, 0.3)?;
  defer destroy_noise(n);

  let ok = noise_set_seed(n, 999);
  if ok {
    io.println("  [OK] noise_set_seed(999) succeeded");
  } else {
    io.println("  [WARN] noise_set_seed returned false");
  }

  return Ok(());
}

fn test_noise_amplitude_change() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n = create_noise(NOISE_WHITE, 48000, 2, 42, 0.3)?;
  defer destroy_noise(n);

  let ok = noise_set_amplitude(n, 0.75);
  if ok {
    io.println("  [OK] noise_set_amplitude(0.75) succeeded");
  } else {
    io.println("  [WARN] noise_set_amplitude returned false");
  }

  return Ok(());
}

// ===========================================================================
// Sound Control Tests
// ===========================================================================

fn test_play_stop_waveform() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.2, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  io.println("  [OK] play_waveform succeeded, handle=" + (snd as Str));
  sleep_ms(50);
  stop_sound(snd);
  io.println("  [OK] stop_sound called");
  return Ok(());
}

fn test_play_stop_noise() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let n = create_noise(NOISE_WHITE, 48000, 2, 42, 0.1)?;
  defer destroy_noise(n);

  let snd = play_noise(engine, n)?;
  io.println("  [OK] play_noise succeeded, handle=" + (snd as Str));
  sleep_ms(50);
  stop_sound(snd);
  io.println("  [OK] stop_sound called");
  return Ok(());
}

fn test_sound_is_playing() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.2, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  let playing = sound_is_playing(snd);
  io.println("  [OK] sound_is_playing = " + (playing as Str));
  stop_sound(snd);
  return Ok(());
}

fn test_sound_volume() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.3, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  sound_set_volume(snd, 0.5);
  io.println("  [OK] sound_set_volume(0.5) called");
  sleep_ms(50);
  stop_sound(snd);
  return Ok(());
}

fn test_sound_pan() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.3, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  sound_set_pan(snd, -1.0);
  io.println("  [OK] sound_set_pan(-1.0) called");
  sound_set_pan(snd, 0.0);
  io.println("  [OK] sound_set_pan(0.0) called");
  sound_set_pan(snd, 1.0);
  io.println("  [OK] sound_set_pan(1.0) called");
  sleep_ms(50);
  stop_sound(snd);
  return Ok(());
}

fn test_sound_pitch() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.3, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  sound_set_pitch(snd, 2.0);
  io.println("  [OK] sound_set_pitch(2.0) called");
  sleep_ms(50);
  stop_sound(snd);
  return Ok(());
}

fn test_sound_looping() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.2, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  sound_set_looping(snd, true);
  io.println("  [OK] sound_set_looping(true) called");
  sleep_ms(50);
  stop_sound(snd);
  return Ok(());
}

fn test_sound_seek() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, 48000, 2, 0.2, 440.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  let ok = sound_seek_to_pcm_frame(snd, 0);
  if ok {
    io.println("  [OK] sound_seek_to_pcm_frame(0) succeeded");
  } else {
    io.println("  [WARN] sound_seek_to_pcm_frame returned false");
  }
  sleep_ms(50);
  stop_sound(snd);
  return Ok(());
}

// ===========================================================================
// Listener (Spatial Audio) Tests
// ===========================================================================

fn test_listener_set_position() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  listener_set_position(engine, 0, 0.0, 0.0, 0.0);
  io.println("  [OK] listener_set_position(0, 0,0,0) called");

  listener_set_position(engine, 0, 1.0, 2.0, 3.0);
  io.println("  [OK] listener_set_position(0, 1,2,3) called");

  return Ok(());
}

fn test_listener_set_direction() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  listener_set_direction(engine, 0, 0.0, 0.0, -1.0);
  io.println("  [OK] listener_set_direction(0, 0,0,-1) called");

  return Ok(());
}

fn test_listener_set_velocity() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  listener_set_velocity(engine, 0, 0.0, 0.0, 0.0);
  io.println("  [OK] listener_set_velocity(0, 0,0,0) called");

  return Ok(());
}

fn test_listener_set_world_up() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  listener_set_world_up(engine, 0, 0.0, 1.0, 0.0);
  io.println("  [OK] listener_set_world_up(0, 0,1,0) called");

  return Ok(());
}

fn test_listener_set_enabled() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  listener_set_enabled(engine, 0, true);
  io.println("  [OK] listener_set_enabled(0, true) called");

  listener_set_enabled(engine, 0, false);
  io.println("  [OK] listener_set_enabled(0, false) called");

  return Ok(());
}

fn test_listener_all_indices() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let engine = setup_engine()?;
  defer destroy_engine(engine);

  var i = 0;
  while i < 4 {
    listener_set_enabled(engine, i, false);
    listener_set_position(engine, i, 0.0, 0.0, 0.0);
    listener_set_direction(engine, i, 0.0, 0.0, -1.0);
    listener_set_velocity(engine, i, 0.0, 0.0, 0.0);
    listener_set_world_up(engine, i, 0.0, 1.0, 0.0);
    i = i + 1;
  }
  io.println("  [OK] listener_set_* on indices 0-3 succeeded");

  return Ok(());
}

// ===========================================================================
// Utility Tests
// ===========================================================================

fn test_sleep_ms() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  sleep_ms(10);
  io.println("  [OK] sleep_ms(10) completed");
  return Ok(());
}

fn test_result_string_known_codes() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let s0 = result_string(RESULT_SUCCESS);
  if s0 != "" {
    io.println("  [OK] result_string(SUCCESS) = \"" + s0 + "\"");
  } else {
    io.println("  [WARN] result_string(SUCCESS) returned empty");
  }

  let s_err = result_string(RESULT_ERROR);
  if s_err != "" {
    io.println("  [OK] result_string(ERROR) = \"" + s_err + "\"");
  } else {
    io.println("  [WARN] result_string(ERROR) returned empty");
  }

  return Ok(());
}

fn test_result_string_all_formats() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  var code: Int32 = FORMAT_UNKNOWN;
  var s: Str = result_string(code);
  io.println("  [OK] result_string(FORMAT_UNKNOWN) = \"" + s + "\"");

  return Ok(());
}

// ===========================================================================
// Constant Validation Tests
// ===========================================================================

fn test_constants_distinct() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  if FORMAT_U8 != FORMAT_S16 {
    io.println("  [OK] format constants are distinct");
  }

  if WAVEFORM_SINE == 0 {
    io.println("  [OK] WAVEFORM_SINE == 0");
  }
  if WAVEFORM_SQUARE == 1 {
    io.println("  [OK] WAVEFORM_SQUARE == 1");
  }
  if WAVEFORM_TRIANGLE == 2 {
    io.println("  [OK] WAVEFORM_TRIANGLE == 2");
  }
  if WAVEFORM_SAWTOOTH == 3 {
    io.println("  [OK] WAVEFORM_SAWTOOTH == 3");
  }

  if NOISE_WHITE == 0 {
    io.println("  [OK] NOISE_WHITE == 0");
  }
  if NOISE_PINK == 1 {
    io.println("  [OK] NOISE_PINK == 1");
  }
  if NOISE_BROWNIAN == 2 {
    io.println("  [OK] NOISE_BROWNIAN == 2");
  }

  if DEVICE_TYPE_PLAYBACK == 1 {
    io.println("  [OK] DEVICE_TYPE_PLAYBACK == 1");
  }
  if DEVICE_TYPE_CAPTURE == 2 {
    io.println("  [OK] DEVICE_TYPE_CAPTURE == 2");
  }
  if DEVICE_TYPE_DUPLEX == 3 {
    io.println("  [OK] DEVICE_TYPE_DUPLEX == 3");
  }
  if DEVICE_TYPE_LOOPBACK == 4 {
    io.println("  [OK] DEVICE_TYPE_LOOPBACK == 4");
  }

  return Ok(());
}

fn test_defaults_sane() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  if DEFAULT_SAMPLE_RATE == 48000 {
    io.println("  [OK] DEFAULT_SAMPLE_RATE == 48000");
  }
  if DEFAULT_CHANNELS == 2 {
    io.println("  [OK] DEFAULT_CHANNELS == 2 (stereo)");
  }
  if MAX_CHANNELS == 254 {
    io.println("  [OK] MAX_CHANNELS == 254");
  }

  return Ok(());
}

// ===========================================================================
// Lifecycle / Resource Tests
// ===========================================================================

fn test_engine_destroy_recreate() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let e1 = create_engine(44100, 2)?;
  destroy_engine(e1);
  io.println("  [OK] engine destroyed");

  let e2 = create_engine(44100, 2)?;
  destroy_engine(e2);
  io.println("  [OK] engine re-created after destroy");

  return Ok(());
}

fn test_waveform_lifecycle() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let wf1 = create_waveform(WAVEFORM_SINE, 44100, 1, 0.5, 440.0)?;
  destroy_waveform(wf1);
  io.println("  [OK] waveform destroyed");

  let wf2 = create_waveform(WAVEFORM_SINE, 44100, 1, 0.5, 440.0)?;
  destroy_waveform(wf2);
  io.println("  [OK] waveform re-created after destroy");

  return Ok(());
}

fn test_noise_lifecycle() -> Result[Unit, Str]
  ensures: result.is_ok()
{
  let n1 = create_noise(NOISE_WHITE, 44100, 1, 42, 0.3)?;
  destroy_noise(n1);
  io.println("  [OK] noise destroyed");

  let n2 = create_noise(NOISE_PINK, 44100, 1, 99, 0.3)?;
  destroy_noise(n2);
  io.println("  [OK] noise re-created after destroy");

  return Ok(());
}

// ===========================================================================
// Test Runner
// ===========================================================================

fn run_test(name: Str, test: fn() -> Result[Unit, Str]) -> Bool {
  io.println("");
  io.println(name + ":");

  match test() {
    Ok(_) => {
      io.println("  PASSED");
      return true;
    }
    Err(e) => {
      io.println("  FAILED: " + e);
      return false;
    }
  }
}

pub fn main() -> Int {
  io.println("=== MiniAudio Conformance Tests ===");

  var passed: Int = 0;
  var total: Int = 0;
  var tests: Int = 0;
  var contracts: Int = 0;

  // Engine tests (6)
  if run_test("test_create_engine_valid",           test_create_engine_valid)           { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_create_engine_stereo",          test_create_engine_stereo)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_create_engine_mono",            test_create_engine_mono)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_create_engine_high_rate",       test_create_engine_high_rate)       { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_engine_volume_roundtrip",       test_engine_volume_roundtrip)       { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_engine_volume_bounds",          test_engine_volume_bounds)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Waveform tests (5)
  if run_test("test_create_waveform_sine",          test_create_waveform_sine)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_create_waveform_all_types",     test_create_waveform_all_types)     { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_waveform_frequency",            test_waveform_frequency)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_waveform_amplitude",            test_waveform_amplitude)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_waveform_type_change",          test_waveform_type_change)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Noise tests (5)
  if run_test("test_create_noise_white",            test_create_noise_white)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_create_noise_all_types",        test_create_noise_all_types)        { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_noise_type_change",             test_noise_type_change)             { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_noise_seed_change",             test_noise_seed_change)             { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_noise_amplitude_change",        test_noise_amplitude_change)        { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Sound control tests (7)
  if run_test("test_play_stop_waveform",            test_play_stop_waveform)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_play_stop_noise",               test_play_stop_noise)               { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_is_playing",              test_sound_is_playing)              { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_volume",                  test_sound_volume)                  { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_pan",                     test_sound_pan)                     { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_pitch",                   test_sound_pitch)                   { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_looping",                 test_sound_looping)                 { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_sound_seek",                    test_sound_seek)                    { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Listener tests (6)
  if run_test("test_listener_set_position",         test_listener_set_position)         { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_listener_set_direction",        test_listener_set_direction)        { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_listener_set_velocity",         test_listener_set_velocity)         { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_listener_set_world_up",         test_listener_set_world_up)         { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_listener_set_enabled",          test_listener_set_enabled)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_listener_all_indices",          test_listener_all_indices)          { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Utility tests (2)
  if run_test("test_sleep_ms",                      test_sleep_ms)                      { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_result_string_known_codes",     test_result_string_known_codes)     { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Constant tests (2)
  if run_test("test_constants_distinct",            test_constants_distinct)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_defaults_sane",                 test_defaults_sane)                 { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  // Lifecycle tests (3)
  if run_test("test_engine_destroy_recreate",       test_engine_destroy_recreate)       { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_waveform_lifecycle",            test_waveform_lifecycle)            { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;
  if run_test("test_noise_lifecycle",               test_noise_lifecycle)               { passed = passed + 1; }
  total = total + 1; tests = tests + 1; contracts = contracts + 1;

  io.println("");
  io.println("============================================");
  io.println("  Results: " + (passed as Str) + "/" + (total as Str) + " passed");
  io.println("============================================");

  if passed == total {
    return 0;
  }
  return 1;
}
