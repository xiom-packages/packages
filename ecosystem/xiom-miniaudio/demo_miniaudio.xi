// XIOM — MiniAudio Demo: Sine Wave Playback
// Plays a 440 Hz (A4) sine wave for 3 seconds, then sweeps 220–880 Hz for 2 s.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio.demo

use xiom.io
use xiom.miniaudio
use xiom.miniaudio.safe

fn demo_sine_tone() -> Result[Unit, Str] {
  io.println("=== MiniAudio Sine Wave Demo ===")

  let srate = 48000
  let ch    = 2

  io.println("creating engine...")
  let engine = create_engine(srate, ch)?
  defer destroy_engine(engine)

  io.println("creating 440 Hz sine waveform...")
  let wf = create_waveform(WAVEFORM_SINE, srate, ch, 0.3, 440.0)?
  defer destroy_waveform(wf)

  io.println("playing tone...")
  let snd = play_waveform(engine, wf)?
  defer stop_sound(snd)

  io.println("playing 440 Hz for 3 seconds...")
  sleep_ms(3000)

  if sound_is_playing(snd) {
    io.println("440 Hz tone is playing.")
  } else {
    io.println("440 Hz tone stopped unexpectedly.")
  }

  stop_sound(snd)
  return Ok(())
}

fn demo_frequency_sweep() -> Result[Unit, Str] {
  io.println("")
  io.println("=== Frequency Sweep Demo ===")

  let srate = 48000
  let ch    = 2

  let engine = create_engine(srate, ch)?
  defer destroy_engine(engine)

  let wf = create_waveform(WAVEFORM_SINE, srate, ch, 0.25, 220.0)?
  defer destroy_waveform(wf)

  let snd = play_waveform(engine, wf)?
  defer stop_sound(snd)

  io.println("sweeping 220 Hz -> 880 Hz over 2 seconds...")

  var step = 0
  while step < 20 {
    let freq = 220.0 + (step as Float32) * 33.0
    let _ = waveform_set_frequency(wf, freq)
    sleep_ms(100)
    step = step + 1
  }

  io.println("sweep complete.")
  stop_sound(snd)

  return Ok(())
}

fn main() -> Int {
  match demo_sine_tone() {
    Err(e) => {
      io.println("demo_sine_tone error: " + e)
      return 1
    }
    Ok(_) => { }
  }

  match demo_frequency_sweep() {
    Err(e) => {
      io.println("demo_frequency_sweep error: " + e)
      return 1
    }
    Ok(_) => { }
  }

  io.println("all demos complete.")
  return 0
}
