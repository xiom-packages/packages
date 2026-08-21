// XIOM -- MiniAudio Demo: Sine Wave, Sweep, Waveform Types, Noise, Panning
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio.demo

use xiom.io
use xiom.miniaudio

fn demo_sine_tone() -> Result[Unit, Str] {
  io.println("=== MiniAudio Sine Wave Demo ===");

  let srate = DEFAULT_SAMPLE_RATE;
  let ch    = DEFAULT_CHANNELS;

  io.println("creating engine...");
  let engine = create_engine(srate, ch)?;
  defer destroy_engine(engine);

  io.println("creating 440 Hz sine waveform...");
  let wf = create_waveform(WAVEFORM_SINE, srate, ch, 0.3, 440.0)?;
  defer destroy_waveform(wf);

  io.println("playing tone...");
  let snd = play_waveform(engine, wf)?;
  defer stop_sound(snd);

  io.println("playing 440 Hz for 3 seconds...");
  sleep_ms(3000);

  if sound_is_playing(snd) {
    io.println("440 Hz tone is playing.");
  }
  if !sound_is_playing(snd) {
    io.println("440 Hz tone stopped unexpectedly.");
  }

  stop_sound(snd);
  return Ok(());
}

fn demo_frequency_sweep() -> Result[Unit, Str] {
  io.println("");
  io.println("=== Frequency Sweep Demo ===");

  let srate = DEFAULT_SAMPLE_RATE;
  let ch    = DEFAULT_CHANNELS;

  let engine = create_engine(srate, ch)?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, srate, ch, 0.25, 220.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  defer stop_sound(snd);

  io.println("sweeping 220 Hz -> 880 Hz over 2 seconds...");

  var step = 0;
  while step < 20 {
    let freq = 220.0 + (step as Float32) * 33.0;
    waveform_set_frequency(wf, freq);
    sleep_ms(100);
    step = step + 1;
  }

  io.println("sweep complete.");
  stop_sound(snd);

  return Ok(());
}

fn demo_waveform_types() -> Result[Unit, Str] {
  io.println("");
  io.println("=== Waveform Types Demo ===");

  let srate = DEFAULT_SAMPLE_RATE;
  let ch    = DEFAULT_CHANNELS;

  let engine = create_engine(srate, ch)?;
  defer destroy_engine(engine);

  io.println("sine wave (1 second)...");
  let wf1 = create_waveform(WAVEFORM_SINE, srate, ch, 0.2, 440.0)?;
  defer destroy_waveform(wf1);
  let snd1 = play_waveform(engine, wf1)?;
  defer stop_sound(snd1);
  sleep_ms(1000);
  stop_sound(snd1);

  io.println("square wave (1 second)...");
  let wf2 = create_waveform(WAVEFORM_SQUARE, srate, ch, 0.15, 440.0)?;
  defer destroy_waveform(wf2);
  let snd2 = play_waveform(engine, wf2)?;
  defer stop_sound(snd2);
  sleep_ms(1000);
  stop_sound(snd2);

  io.println("triangle wave (1 second)...");
  let wf3 = create_waveform(WAVEFORM_TRIANGLE, srate, ch, 0.2, 440.0)?;
  defer destroy_waveform(wf3);
  let snd3 = play_waveform(engine, wf3)?;
  defer stop_sound(snd3);
  sleep_ms(1000);
  stop_sound(snd3);

  io.println("sawtooth wave (1 second)...");
  let wf4 = create_waveform(WAVEFORM_SAWTOOTH, srate, ch, 0.15, 440.0)?;
  defer destroy_waveform(wf4);
  let snd4 = play_waveform(engine, wf4)?;
  defer stop_sound(snd4);
  sleep_ms(1000);
  stop_sound(snd4);

  io.println("waveform types complete.");
  return Ok(());
}

fn demo_noise() -> Result[Unit, Str] {
  io.println("");
  io.println("=== Noise Demo ===");

  let srate = DEFAULT_SAMPLE_RATE;
  let ch    = DEFAULT_CHANNELS;

  let engine = create_engine(srate, ch)?;
  defer destroy_engine(engine);

  io.println("white noise (2 seconds)...");
  let wn = create_noise(NOISE_WHITE, srate, ch, 42, 0.15)?;
  defer destroy_noise(wn);
  let snd = play_noise(engine, wn)?;
  defer stop_sound(snd);
  sleep_ms(2000);
  stop_sound(snd);

  io.println("pink noise (2 seconds)...");
  let pn = create_noise(NOISE_PINK, srate, ch, 123, 0.15)?;
  defer destroy_noise(pn);
  let snd2 = play_noise(engine, pn)?;
  defer stop_sound(snd2);
  sleep_ms(2000);
  stop_sound(snd2);

  io.println("brownian noise (2 seconds)...");
  let bn = create_noise(NOISE_BROWNIAN, srate, ch, 999, 0.15)?;
  defer destroy_noise(bn);
  let snd3 = play_noise(engine, bn)?;
  defer stop_sound(snd3);
  sleep_ms(2000);
  stop_sound(snd3);

  io.println("noise demo complete.");
  return Ok(());
}

fn demo_panning() -> Result[Unit, Str] {
  io.println("");
  io.println("=== Stereo Panning Demo ===");

  let srate = DEFAULT_SAMPLE_RATE;
  let ch    = DEFAULT_CHANNELS;

  let engine = create_engine(srate, ch)?;
  defer destroy_engine(engine);

  let wf = create_waveform(WAVEFORM_SINE, srate, ch, 0.3, 660.0)?;
  defer destroy_waveform(wf);

  let snd = play_waveform(engine, wf)?;
  defer stop_sound(snd);

  io.println("left channel...");
  sound_set_pan(snd, -1.0);
  sleep_ms(1500);

  io.println("center...");
  sound_set_pan(snd, 0.0);
  sleep_ms(1500);

  io.println("right channel...");
  sound_set_pan(snd, 1.0);
  sleep_ms(1500);

  stop_sound(snd);
  io.println("panning demo complete.");
  return Ok(());
}

fn main() -> Int {
  match demo_sine_tone() {
    Err(e) => {
      io.println("demo_sine_tone error: " + e);
      return 1;
    }
    Ok(_) => { }
  }

  match demo_frequency_sweep() {
    Err(e) => {
      io.println("demo_frequency_sweep error: " + e);
      return 1;
    }
    Ok(_) => { }
  }

  match demo_waveform_types() {
    Err(e) => {
      io.println("demo_waveform_types error: " + e);
      return 1;
    }
    Ok(_) => { }
  }

  match demo_noise() {
    Err(e) => {
      io.println("demo_noise error: " + e);
      return 1;
    }
    Ok(_) => { }
  }

  match demo_panning() {
    Err(e) => {
      io.println("demo_panning error: " + e);
      return 1;
    }
    Ok(_) => { }
  }

  io.println("all demos complete.");
  return 0;
}
