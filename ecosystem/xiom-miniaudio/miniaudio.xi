// XIOM — MiniAudio FFI Bindings (C Bridge)
// Low-level extern "C" declarations and safe wrappers for the xma C bridge.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.miniaudio

// ===========================================================================
// Constants — format / device / waveform / result codes
// ===========================================================================

pub const FORMAT_UNKNOWN: Int32 = 0
pub const FORMAT_U8:       Int32 = 1
pub const FORMAT_S16:      Int32 = 2
pub const FORMAT_S24:      Int32 = 3
pub const FORMAT_S32:      Int32 = 4
pub const FORMAT_F32:      Int32 = 5

pub const DEVICE_TYPE_PLAYBACK: Int32 = 1
pub const DEVICE_TYPE_CAPTURE:  Int32 = 2
pub const DEVICE_TYPE_DUPLEX:   Int32 = 3
pub const DEVICE_TYPE_LOOPBACK: Int32 = 4

pub const WAVEFORM_SINE:      Int32 = 0
pub const WAVEFORM_SQUARE:    Int32 = 1
pub const WAVEFORM_TRIANGLE:  Int32 = 2
pub const WAVEFORM_SAWTOOTH:  Int32 = 3

pub const NOISE_WHITE:    Int32 = 0
pub const NOISE_PINK:     Int32 = 1
pub const NOISE_BROWNIAN: Int32 = 2

pub const BACKEND_WASAPI:     Int32 = 0
pub const BACKEND_DSOUND:     Int32 = 1
pub const BACKEND_WINMM:      Int32 = 2
pub const BACKEND_COREAUDIO:  Int32 = 3
pub const BACKEND_SNDIO:      Int32 = 4
pub const BACKEND_AUDIO4:     Int32 = 5
pub const BACKEND_OSS:        Int32 = 6
pub const BACKEND_PULSEAUDIO: Int32 = 7
pub const BACKEND_ALSA:       Int32 = 8
pub const BACKEND_JACK:       Int32 = 9
pub const BACKEND_AAUDIO:     Int32 = 10
pub const BACKEND_OPENSL:     Int32 = 11
pub const BACKEND_WEBAUDIO:   Int32 = 12
pub const BACKEND_NULL:       Int32 = 14

pub const RESULT_SUCCESS:                       Int32 = 0
pub const RESULT_ERROR:                         Int32 = -1
pub const RESULT_INVALID_ARGS:                  Int32 = -2
pub const RESULT_INVALID_OPERATION:             Int32 = -3
pub const RESULT_OUT_OF_MEMORY:                 Int32 = -4
pub const RESULT_OUT_OF_RANGE:                  Int32 = -5
pub const RESULT_ACCESS_DENIED:                 Int32 = -6
pub const RESULT_DOES_NOT_EXIST:                Int32 = -7
pub const RESULT_ALREADY_EXISTS:                Int32 = -8
pub const RESULT_TOO_MANY_OPEN_FILES:           Int32 = -9
pub const RESULT_INVALID_FILE:                  Int32 = -10
pub const RESULT_TOO_BIG:                       Int32 = -11
pub const RESULT_PATH_TOO_LONG:                 Int32 = -12
pub const RESULT_NAME_TOO_LONG:                 Int32 = -13
pub const RESULT_NOT_DIRECTORY:                 Int32 = -14
pub const RESULT_IS_DIRECTORY:                  Int32 = -15
pub const RESULT_DIRECTORY_NOT_EMPTY:           Int32 = -16
pub const RESULT_AT_END:                        Int32 = -17
pub const RESULT_NO_SPACE:                      Int32 = -18
pub const RESULT_BUSY:                          Int32 = -19
pub const RESULT_IO_ERROR:                      Int32 = -20
pub const RESULT_INTERRUPT:                     Int32 = -21
pub const RESULT_UNAVAILABLE:                   Int32 = -22
pub const RESULT_ALREADY_IN_USE:                Int32 = -23
pub const RESULT_BAD_ADDRESS:                   Int32 = -24
pub const RESULT_BAD_SEEK:                      Int32 = -25
pub const RESULT_BAD_PIPE:                      Int32 = -26
pub const RESULT_DEADLOCK:                      Int32 = -27
pub const RESULT_TOO_MANY_LINKS:                Int32 = -28
pub const RESULT_NOT_IMPLEMENTED:               Int32 = -29
pub const RESULT_NO_MESSAGE:                    Int32 = -30
pub const RESULT_BAD_MESSAGE:                   Int32 = -31
pub const RESULT_NO_DATA_AVAILABLE:             Int32 = -32
pub const RESULT_INVALID_DATA:                  Int32 = -33
pub const RESULT_TIMEOUT:                       Int32 = -34
pub const RESULT_NO_NETWORK:                    Int32 = -35
pub const RESULT_NOT_UNIQUE:                    Int32 = -36
pub const RESULT_NOT_SOCKET:                    Int32 = -37
pub const RESULT_NO_ADDRESS:                    Int32 = -38
pub const RESULT_BAD_PROTOCOL:                  Int32 = -39
pub const RESULT_PROTOCOL_UNAVAILABLE:          Int32 = -40
pub const RESULT_PROTOCOL_NOT_SUPPORTED:        Int32 = -41
pub const RESULT_PROTOCOL_FAMILY_NOT_SUPPORTED: Int32 = -42
pub const RESULT_ADDRESS_FAMILY_NOT_SUPPORTED:  Int32 = -43
pub const RESULT_SOCKET_NOT_SUPPORTED:          Int32 = -44
pub const RESULT_CONNECTION_RESET:              Int32 = -45
pub const RESULT_ALREADY_CONNECTED:             Int32 = -46
pub const RESULT_NOT_CONNECTED:                 Int32 = -47
pub const RESULT_CONNECTION_REFUSED:            Int32 = -48
pub const RESULT_NO_HOST:                       Int32 = -49
pub const RESULT_IN_PROGRESS:                   Int32 = -50
pub const RESULT_CANCELLED:                     Int32 = -51
pub const RESULT_MEMORY_ALREADY_MAPPED:         Int32 = -52

pub const RESULT_CRC_MISMATCH:                  Int32 = -100
pub const RESULT_FORMAT_NOT_SUPPORTED:          Int32 = -200
pub const RESULT_DEVICE_TYPE_NOT_SUPPORTED:     Int32 = -201
pub const RESULT_SHARE_MODE_NOT_SUPPORTED:      Int32 = -202
pub const RESULT_NO_BACKEND:                    Int32 = -203
pub const RESULT_NO_DEVICE:                     Int32 = -204
pub const RESULT_API_NOT_FOUND:                 Int32 = -205
pub const RESULT_INVALID_DEVICE_CONFIG:         Int32 = -206
pub const RESULT_LOOP:                          Int32 = -207
pub const RESULT_BACKEND_NOT_ENABLED:           Int32 = -208

pub const RESULT_DEVICE_NOT_INITIALIZED:        Int32 = -300
pub const RESULT_DEVICE_ALREADY_INITIALIZED:    Int32 = -301
pub const RESULT_DEVICE_NOT_STARTED:            Int32 = -302
pub const RESULT_DEVICE_NOT_STOPPED:            Int32 = -303

pub const RESULT_FAILED_TO_INIT_BACKEND:          Int32 = -400
pub const RESULT_FAILED_TO_OPEN_BACKEND_DEVICE:   Int32 = -401
pub const RESULT_FAILED_TO_START_BACKEND_DEVICE:  Int32 = -402
pub const RESULT_FAILED_TO_STOP_BACKEND_DEVICE:   Int32 = -403

pub const DEFAULT_SAMPLE_RATE: Int = 48000
pub const DEFAULT_CHANNELS:    Int = 2
pub const MAX_CHANNELS:        Int = 254
pub const DEFAULT_FORMAT:      Int32 = FORMAT_F32

// ===========================================================================
// extern "C" — C bridge declarations (xiom_ma_bridge)
// ===========================================================================

extern "C" {
  fn xma_engine_create(sample_rate: Int32, channels: Int32) -> Int;
  fn xma_engine_destroy(engine: Int);
  fn xma_engine_set_volume(engine: Int, volume: Float32) -> Int32;
  fn xma_engine_get_volume(engine: Int) -> Float32;

  fn xma_waveform_create(type_: Int32, sample_rate: Int32,
                         channels: Int32, amplitude: Float32,
                         frequency: Float32) -> Int;
  fn xma_waveform_destroy(waveform: Int);
  fn xma_waveform_set_frequency(waveform: Int, frequency: Float32) -> Int32;
  fn xma_waveform_set_amplitude(waveform: Int, amplitude: Float32) -> Int32;
  fn xma_waveform_set_type(waveform: Int, type_: Int32) -> Int32;

  fn xma_play_waveform(engine: Int, waveform: Int) -> Int;
  fn xma_sound_stop(sound: Int);
  fn xma_sound_is_playing(sound: Int) -> Int32;
  fn xma_sound_set_volume(sound: Int, volume: Float32) -> Int32;
  fn xma_sound_set_pan(sound: Int, pan: Float32);
  fn xma_sound_set_pitch(sound: Int, pitch: Float32);
  fn xma_sound_set_looping(sound: Int, looping: Int32);
  fn xma_sound_seek_to_pcm_frame(sound: Int, frame_index: Int) -> Int32;

  fn xma_engine_listener_set_position(engine: Int, listener: Int32,
                                       x: Float32, y: Float32, z: Float32);
  fn xma_engine_listener_set_direction(engine: Int, listener: Int32,
                                        x: Float32, y: Float32, z: Float32);
  fn xma_engine_listener_set_velocity(engine: Int, listener: Int32,
                                       x: Float32, y: Float32, z: Float32);
  fn xma_engine_listener_set_world_up(engine: Int, listener: Int32,
                                       x: Float32, y: Float32, z: Float32);
  fn xma_engine_listener_set_enabled(engine: Int, listener: Int32, enabled: Int32);

  fn xma_noise_create(type_: Int32, sample_rate: Int32, channels: Int32,
                      seed: Int32, amplitude: Float32) -> Int;
  fn xma_noise_destroy(noise: Int);
  fn xma_noise_set_type(noise: Int, type_: Int32) -> Int32;
  fn xma_noise_set_seed(noise: Int, seed: Int32) -> Int32;
  fn xma_noise_set_amplitude(noise: Int, amplitude: Float32) -> Int32;

  fn xma_play_noise(engine: Int, noise: Int) -> Int;

  fn xma_sleep_ms(milliseconds: Int32);
  fn xma_result_string(result: Int32) -> Str;
}

// ===========================================================================
// Safe Engine Wrappers
// ===========================================================================

pub fn create_engine(sample_rate: Int, channels: Int) -> Result[Int, Str]
  requires: sample_rate > 0
  requires: channels > 0
  requires: channels <= 8
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe { xma_engine_create(sample_rate as Int32, channels as Int32) };
  if raw == 0 {
    return Err("failed to create engine");
  }
  return Ok(raw);
}

pub fn destroy_engine(engine: Int)
  requires: engine != 0
{
  unsafe { xma_engine_destroy(engine); }
}

pub fn set_engine_volume(engine: Int, volume: Float32) -> Bool
  requires: engine != 0
  requires: volume >= 0.0
{
  let r = unsafe { xma_engine_set_volume(engine, volume) };
  return r == RESULT_SUCCESS;
}

pub fn get_engine_volume(engine: Int) -> Float32
  requires: engine != 0
{
  return unsafe { xma_engine_get_volume(engine) };
}

// ===========================================================================
// Safe Int Wrappers
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
  };
  if raw == 0 {
    return Err("failed to create waveform");
  }
  return Ok(raw);
}

pub fn destroy_waveform(waveform: Int)
  requires: waveform != 0
{
  unsafe { xma_waveform_destroy(waveform); }
}

pub fn waveform_set_frequency(waveform: Int, frequency: Float32) -> Bool
  requires: waveform != 0
  requires: frequency > 0.0
{
  let r = unsafe { xma_waveform_set_frequency(waveform, frequency) };
  return r == RESULT_SUCCESS;
}

pub fn waveform_set_amplitude(waveform: Int, amplitude: Float32) -> Bool
  requires: waveform != 0
  requires: amplitude >= 0.0
  requires: amplitude <= 1.0
{
  let r = unsafe { xma_waveform_set_amplitude(waveform, amplitude) };
  return r == RESULT_SUCCESS;
}

pub fn waveform_set_type(waveform: Int, type_: Int) -> Bool
  requires: waveform != 0
  requires: type_ >= 0
  requires: type_ <= 3
{
  let r = unsafe { xma_waveform_set_type(waveform, type_ as Int32) };
  return r == RESULT_SUCCESS;
}

// ===========================================================================
// Safe Int Wrappers
// ===========================================================================

pub fn play_waveform(engine: Int, waveform: Int) -> Result[Int, Str]
  requires: engine != 0
  requires: waveform != 0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe { xma_play_waveform(engine, waveform) };
  if raw == 0 {
    return Err("failed to play waveform");
  }
  return Ok(raw);
}

pub fn play_noise(engine: Int, noise: Int) -> Result[Int, Str]
  requires: engine != 0
  requires: noise != 0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe { xma_play_noise(engine, noise) };
  if raw == 0 {
    return Err("failed to play noise");
  }
  return Ok(raw);
}

pub fn stop_sound(sound: Int)
  requires: sound != 0
{
  unsafe { xma_sound_stop(sound); }
}

pub fn sound_is_playing(sound: Int) -> Bool
  requires: sound != 0
{
  let r: Int32 = unsafe { xma_sound_is_playing(sound) };
  return r != 0;
}

pub fn sound_set_volume(sound: Int, volume: Float32)
  requires: sound != 0
  requires: volume >= 0.0
{
  unsafe { xma_sound_set_volume(sound, volume); }
}

pub fn sound_set_pan(sound: Int, pan: Float32)
  requires: sound != 0
  requires: pan >= -1.0
  requires: pan <= 1.0
{
  unsafe { xma_sound_set_pan(sound, pan); }
}

pub fn sound_set_pitch(sound: Int, pitch: Float32)
  requires: sound != 0
  requires: pitch > 0.0
{
  unsafe { xma_sound_set_pitch(sound, pitch); }
}

pub fn sound_set_looping(sound: Int, looping: Bool)
  requires: sound != 0
{
  var val: Int32 = 0;
  if looping {
    val = 1;
  }
  unsafe { xma_sound_set_looping(sound, val); }
}

pub fn sound_seek_to_pcm_frame(sound: Int, frame_index: Int) -> Bool
  requires: sound != 0
  requires: frame_index >= 0
{
  let r = unsafe { xma_sound_seek_to_pcm_frame(sound, frame_index) };
  return r == RESULT_SUCCESS;
}

// ===========================================================================
// Safe Engine Listener (Spatial Audio) Wrappers
// ===========================================================================

pub fn listener_set_position(engine: Int, listener: Int,
                              x: Float32, y: Float32, z: Float32)
  requires: engine != 0
  requires: listener >= 0
  requires: listener < 4
{
  unsafe { xma_engine_listener_set_position(engine, listener as Int32, x, y, z); }
}

pub fn listener_set_direction(engine: Int, listener: Int,
                               x: Float32, y: Float32, z: Float32)
  requires: engine != 0
  requires: listener >= 0
  requires: listener < 4
{
  unsafe { xma_engine_listener_set_direction(engine, listener as Int32, x, y, z); }
}

pub fn listener_set_velocity(engine: Int, listener: Int,
                              x: Float32, y: Float32, z: Float32)
  requires: engine != 0
  requires: listener >= 0
  requires: listener < 4
{
  unsafe { xma_engine_listener_set_velocity(engine, listener as Int32, x, y, z); }
}

pub fn listener_set_world_up(engine: Int, listener: Int,
                              x: Float32, y: Float32, z: Float32)
  requires: engine != 0
  requires: listener >= 0
  requires: listener < 4
{
  unsafe { xma_engine_listener_set_world_up(engine, listener as Int32, x, y, z); }
}

pub fn listener_set_enabled(engine: Int, listener: Int, enabled: Bool)
  requires: engine != 0
  requires: listener >= 0
  requires: listener < 4
{
  var val: Int32 = 0;
  if enabled {
    val = 1;
  }
  unsafe { xma_engine_listener_set_enabled(engine, listener as Int32, val); }
}

// ===========================================================================
// Safe Int Wrappers
// ===========================================================================

pub fn create_noise(type_: Int, sample_rate: Int, channels: Int,
                     seed: Int, amplitude: Float32) -> Result[Int, Str]
  requires: type_ >= 0
  requires: type_ <= 2
  requires: sample_rate > 0
  requires: channels > 0
  requires: amplitude >= 0.0
  requires: amplitude <= 1.0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let raw = unsafe {
    xma_noise_create(type_ as Int32, sample_rate as Int32,
                     channels as Int32, seed as Int32, amplitude)
  };
  if raw == 0 {
    return Err("failed to create noise");
  }
  return Ok(raw);
}

pub fn destroy_noise(noise: Int)
  requires: noise != 0
{
  unsafe { xma_noise_destroy(noise); }
}

pub fn noise_set_type(noise: Int, type_: Int) -> Bool
  requires: noise != 0
  requires: type_ >= 0
  requires: type_ <= 2
{
  let r = unsafe { xma_noise_set_type(noise, type_ as Int32) };
  return r == RESULT_SUCCESS;
}

pub fn noise_set_seed(noise: Int, seed: Int) -> Bool
  requires: noise != 0
{
  let r = unsafe { xma_noise_set_seed(noise, seed as Int32) };
  return r == RESULT_SUCCESS;
}

pub fn noise_set_amplitude(noise: Int, amplitude: Float32) -> Bool
  requires: noise != 0
  requires: amplitude >= 0.0
  requires: amplitude <= 1.0
{
  let r = unsafe { xma_noise_set_amplitude(noise, amplitude) };
  return r == RESULT_SUCCESS;
}

// ===========================================================================
// Utility
// ===========================================================================

pub fn sleep_ms(ms: Int)
  requires: ms > 0
{
  unsafe { xma_sleep_ms(ms as Int32); }
}

pub fn result_string(code: Int32) -> Str
  ensures: result != ""
{
  return unsafe { xma_result_string(code) };
}
