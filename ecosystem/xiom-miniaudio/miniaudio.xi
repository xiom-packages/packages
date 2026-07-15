// XIOM — MiniAudio FFI Bindings (C Bridge)
// Low-level extern "C" declarations for the xma C bridge library.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio

// ---------------------------------------------------------------------------
// Constants — device / format / waveform types
// ---------------------------------------------------------------------------

pub const FORMAT_U8:    Int32 = 1
pub const FORMAT_S16:   Int32 = 2
pub const FORMAT_S24:   Int32 = 3
pub const FORMAT_S32:   Int32 = 4
pub const FORMAT_F32:   Int32 = 5

pub const DEVICE_TYPE_PLAYBACK: Int32 = 1
pub const DEVICE_TYPE_CAPTURE:  Int32 = 2
pub const DEVICE_TYPE_DUPLEX:   Int32 = 3
pub const DEVICE_TYPE_LOOPBACK: Int32 = 4

pub const WAVEFORM_SINE:      Int32 = 0
pub const WAVEFORM_SQUARE:    Int32 = 1
pub const WAVEFORM_TRIANGLE:  Int32 = 2
pub const WAVEFORM_SAWTOOTH:  Int32 = 3

pub const RESULT_SUCCESS: Int32 = 0

// ---------------------------------------------------------------------------
// Opaque handle types
// ---------------------------------------------------------------------------

pub type EngineHandle    = Int
pub type WaveformHandle  = Int
pub type SoundHandle     = Int

// ---------------------------------------------------------------------------
// extern "C" — C bridge declarations (xiom_ma_bridge)
// ---------------------------------------------------------------------------

extern "C" {
  fn xma_engine_create(sample_rate: Int32, channels: Int32) -> Int
  fn xma_engine_destroy(engine: Int)
  fn xma_engine_set_volume(engine: Int, volume: Float32) -> Int32
  fn xma_engine_get_volume(engine: Int) -> Float32

  fn xma_waveform_create(type_: Int32, sample_rate: Int32,
                         channels: Int32, amplitude: Float32,
                         frequency: Float32) -> Int
  fn xma_waveform_destroy(waveform: Int)
  fn xma_waveform_set_frequency(waveform: Int, frequency: Float32) -> Int32
  fn xma_waveform_set_amplitude(waveform: Int, amplitude: Float32) -> Int32
  fn xma_waveform_set_type(waveform: Int, type_: Int32) -> Int32

  fn xma_play_waveform(engine: Int, waveform: Int) -> Int
  fn xma_sound_stop(sound: Int)
  fn xma_sound_is_playing(sound: Int) -> Int32
  fn xma_sound_set_volume(sound: Int, volume: Float32) -> Int32

  fn xma_sleep_ms(milliseconds: Int32)
  fn xma_result_string(result: Int32) -> Str
}
