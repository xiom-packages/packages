// XIOM -- MiniAudio Safe Wrappers
// High-level, safe XIOM wrappers around the raw C bridge handle functions.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio.safe

use xiom.miniaudio

// ===========================================================================
// Engine
// ===========================================================================

pub fn create_engine(sample_rate: Int, channels: Int) -> Result[Int, Str]
  requires: sample_rate > 0
  requires: channels > 0
  requires: channels <= 8
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe { xma_engine_create(sample_rate as Int32, channels as Int32) }
  if raw == 0 {
    return Err("xma_engine_create: failed to create engine")
  }
  return Ok(raw)
}

pub fn destroy_engine(engine: Int)
  requires: engine != 0
{
  unsafe { xma_engine_destroy(engine) }
}

pub fn set_engine_volume(engine: Int, volume: Float32) -> Bool
  requires: engine != 0
  requires: volume >= 0.0
{
  let r = unsafe { xma_engine_set_volume(engine, volume) }
  return r == RESULT_SUCCESS
}

pub fn get_engine_volume(engine: Int) -> Float32
  requires: engine != 0
{
  return unsafe { xma_engine_get_volume(engine) }
}

// ===========================================================================
// Waveform (sine, square, triangle, sawtooth generator)
// ===========================================================================

pub fn create_waveform(type_: Int, sample_rate: Int, channels: Int,
                        amplitude: Float32, frequency: Float32) -> Result[Int, Str]
  requires: type_ >= 0
  requires: type_ <= 3
  requires: sample_rate > 0
  requires: channels > 0
  requires: amplitude >= 0.0
  requires: amplitude <= 1.0
  requires: frequency > 0.0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe {
    xma_waveform_create(type_ as Int32, sample_rate as Int32,
                        channels as Int32, amplitude, frequency)
  }
  if raw == 0 {
    return Err("xma_waveform_create: failed to create waveform")
  }
  return Ok(raw)
}

pub fn destroy_waveform(waveform: Int)
  requires: waveform != 0
{
  unsafe { xma_waveform_destroy(waveform) }
}

pub fn waveform_set_frequency(waveform: Int, frequency: Float32) -> Bool
  requires: waveform != 0
  requires: frequency > 0.0
{
  let r = unsafe { xma_waveform_set_frequency(waveform, frequency) }
  return r == RESULT_SUCCESS
}

pub fn waveform_set_amplitude(waveform: Int, amplitude: Float32) -> Bool
  requires: waveform != 0
  requires: amplitude >= 0.0
  requires: amplitude <= 1.0
{
  let r = unsafe { xma_waveform_set_amplitude(waveform, amplitude) }
  return r == RESULT_SUCCESS
}

pub fn waveform_set_type(waveform: Int, type_: Int) -> Bool
  requires: waveform != 0
  requires: type_ >= 0
  requires: type_ <= 3
{
  let r = unsafe { xma_waveform_set_type(waveform, type_ as Int32) }
  return r == RESULT_SUCCESS
}

// ===========================================================================
// Playback -- attach a waveform to an engine, returning a sound handle
// ===========================================================================

pub fn play_waveform(engine: Int, waveform: Int) -> Result[Int, Str]
  requires: engine != 0
  requires: waveform != 0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe { xma_play_waveform(engine, waveform) }
  if raw == 0 {
    return Err("xma_play_waveform: failed to play waveform")
  }
  return Ok(raw)
}

pub fn stop_sound(sound: Int)
  requires: sound != 0
{
  unsafe { xma_sound_stop(sound) }
}

pub fn sound_is_playing(sound: Int) -> Bool
  requires: sound != 0
{
  let r: Int32 = unsafe { xma_sound_is_playing(sound) }
  return r != 0
}

pub fn sound_set_volume(sound: Int, volume: Float32) -> Bool
  requires: sound != 0
  requires: volume >= 0.0
{
  let r = unsafe { xma_sound_set_volume(sound, volume) }
  return r == 0
}

// ===========================================================================
// Utility
// ===========================================================================

pub fn sleep_ms(ms: Int)
  requires: ms > 0
{
  unsafe { xma_sleep_ms(ms as Int32) }
}

pub fn result_string(code: Int32) -> Str
  ensures: result != ""
{
  return unsafe { xma_result_string(code) }
}
