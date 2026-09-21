// XIOM -- OpenAL Audio Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.openal

pub type Source = Int;
pub type Buffer = Int;

pub fn get_error() -> Int;
pub fn get_string(param: Int) -> Str;

pub fn create_source() -> Result[Source, Str];
pub fn delete_source(source: Source)
  requires: source != 0;
pub fn source_play(source: Source)
  requires: source != 0;
pub fn source_pause(source: Source)
  requires: source != 0;
pub fn source_stop(source: Source)
  requires: source != 0;
pub fn source_rewind(source: Source)
  requires: source != 0;
pub fn is_source_playing(source: Source) -> Bool
  requires: source != 0;
pub fn set_source_position(source: Source, x: Float32, y: Float32, z: Float32)
  requires: source != 0;
pub fn set_source_velocity(source: Source, x: Float32, y: Float32, z: Float32)
  requires: source != 0;
pub fn set_source_pitch(source: Source, pitch: Float32)
  requires: source != 0;
  requires: pitch > 0.0;
pub fn set_source_gain(source: Source, gain: Float32)
  requires: source != 0;
  requires: gain >= 0.0;
pub fn set_source_looping(source: Source, loop: Bool)
  requires: source != 0;

pub fn create_buffer() -> Result[Buffer, Str];
pub fn delete_buffer(buffer: Buffer)
  requires: buffer != 0;
pub fn buffer_data_mono16(buffer: Buffer, data: &Vec[Int16], freq: Int)
  requires: buffer != 0;
  requires: data.len() > 0;
  requires: freq > 0;
pub fn buffer_data_stereo16(buffer: Buffer, data: &Vec[Int16], freq: Int)
  requires: buffer != 0;
  requires: data.len() > 0;
  requires: freq > 0;

pub fn set_listener_position(x: Float32, y: Float32, z: Float32);
pub fn set_listener_orientation(at_x: Float32, at_y: Float32, at_z: Float32, up_x: Float32, up_y: Float32, up_z: Float32);
pub fn set_listener_gain(gain: Float32)
  requires: gain >= 0.0;

pub fn load_wav(path: Str) -> Result[(Buffer, Int), Str]
  requires: path.len() > 0;
pub fn play_sound(buffer: Buffer, freq: Int) -> Result[Source, Str]
  requires: buffer != 0;
  requires: freq > 0;

pub const NO_ERROR: Int = 0;
pub const FORMAT_MONO16: Int = 0x1101;
pub const FORMAT_STEREO16: Int = 0x1103;
pub const SOURCE_STATE_PLAYING: Int = 0x1012;
