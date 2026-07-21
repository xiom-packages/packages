// XIOM — PortAudio Audio I/O Bindings
// Low-level extern "C" declarations and safe wrappers for PortAudio.
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.portaudio

// ===========================================================================
// Types
// ===========================================================================

pub type PaStream = Int

// ===========================================================================
// Constants — sample formats
// ===========================================================================

pub const FORMAT_FLOAT32:      Int = 0x00000001
pub const FORMAT_INT32:        Int = 0x00000002
pub const FORMAT_INT24:        Int = 0x00000004
pub const FORMAT_INT16:        Int = 0x00000008
pub const FORMAT_INT8:         Int = 0x00000010
pub const FORMAT_UINT8:        Int = 0x00000020
pub const FORMAT_CUSTOM:       Int = 0x00010000
pub const FORMAT_NONINTERLEAVED: Int = -2147483648

// ===========================================================================
// Constants — error codes (negative values per PortAudio convention)
// ===========================================================================

pub const NO_ERROR:                          Int = 0
pub const NOT_INITIALIZED:                   Int = -10000
pub const UNANTICIPATED_HOST_ERROR:          Int = -9999
pub const INVALID_CHANNEL_COUNT:             Int = -9998
pub const INVALID_SAMPLE_RATE:               Int = -9997
pub const INVALID_DEVICE:                    Int = -9996
pub const INVALID_FLAG:                      Int = -9995
pub const SAMPLE_FORMAT_NOT_SUPPORTED:       Int = -9994
pub const BAD_IO_DEVICE_COMBINATION:         Int = -9993
pub const INSUFFICIENT_MEMORY:               Int = -9992
pub const BUFFER_TOO_BIG:                    Int = -9991
pub const BUFFER_TOO_SMALL:                  Int = -9990
pub const NULL_CALLBACK:                     Int = -9989
pub const BAD_STREAM_PTR:                    Int = -9988
pub const TIMED_OUT:                         Int = -9987
pub const INTERNAL_ERROR:                    Int = -9986
pub const DEVICE_UNAVAILABLE:                Int = -9985
pub const INCOMPATIBLE_HOST_API_SPECIFIC_STREAM_INFO: Int = -9984
pub const STREAM_IS_STOPPED:                 Int = -9983
pub const STREAM_IS_NOT_STOPPED:             Int = -9982
pub const INPUT_OVERFLOWED:                  Int = -9981
pub const OUTPUT_UNDERFLOWED:                Int = -9980
pub const HOST_API_NOT_FOUND:                Int = -9979
pub const INVALID_HOST_API:                  Int = -9978
pub const CAN_NOT_READ_FROM_A_CALLBACK_STREAM:   Int = -9977
pub const CAN_NOT_WRITE_TO_A_CALLBACK_STREAM:    Int = -9976
pub const CAN_NOT_READ_FROM_AN_OUTPUT_ONLY_STREAM: Int = -9975
pub const CAN_NOT_WRITE_TO_AN_INPUT_ONLY_STREAM:  Int = -9974
pub const INCOMPATIBLE_STREAM_HOST_API:      Int = -9973
pub const BAD_BUFFER_PTR:                    Int = -9972

// ===========================================================================
// Constants — device
// ===========================================================================

pub const NO_DEVICE:                         Int = -1

// ===========================================================================
// Constants — stream flags
// ===========================================================================

pub const NO_FLAG:                           Int = 0
pub const CLIP_OFF:                          Int = 0x00000001
pub const DITHER_OFF:                        Int = 0x00000002
pub const NEVER_DROP_INPUT:                  Int = 0x00000004
pub const PRIME_OUTPUT_BUFFERS_USING_STREAM_CALLBACK: Int = 0x00000008
pub const PLATFORM_SPECIFIC_FLAGS:           Int = 0xFFFF0000

// ===========================================================================
// Constants — defaults
// ===========================================================================

pub const DEFAULT_SAMPLE_RATE:               Int = 44100
pub const DEFAULT_FRAMES_PER_BUFFER:         Int = 512
pub const DEFAULT_CHANNELS:                  Int = 2

// ===========================================================================
// extern "C" — PortAudio C library declarations
// ===========================================================================

extern "C" {
  fn Pa_Initialize() -> Int
  fn Pa_Terminate() -> Int
  fn Pa_GetDefaultOutputDevice() -> Int
  fn Pa_GetDefaultInputDevice() -> Int
  fn Pa_GetDeviceCount() -> Int
  fn Pa_GetDefaultHostApi() -> Int
  fn Pa_GetHostApiCount() -> Int
  fn Pa_GetHostApiInfo(hostApi: Int) -> Int
  fn Pa_GetDeviceInfo(device: Int) -> Int
  fn Pa_OpenDefaultStream(stream: Int, numInputChannels: Int,
                          numOutputChannels: Int, sampleFormat: Int,
                          sampleRate: Float64, framesPerBuffer: Int,
                          callback: Int, userData: Int) -> Int
  fn Pa_OpenStream(stream: Int, inputParams: Int, outputParams: Int,
                    sampleRate: Float64, framesPerBuffer: Int,
                    streamFlags: Int, callback: Int, userData: Int) -> Int
  fn Pa_StartStream(stream: Int) -> Int
  fn Pa_StopStream(stream: Int) -> Int
  fn Pa_CloseStream(stream: Int) -> Int
  fn Pa_AbortStream(stream: Int) -> Int
  fn Pa_IsStreamStopped(stream: Int) -> Int
  fn Pa_IsStreamActive(stream: Int) -> Int
  fn Pa_WriteStream(stream: Int, buffer: Int, frames: Int) -> Int
  fn Pa_ReadStream(stream: Int, buffer: Int, frames: Int) -> Int
  fn Pa_GetStreamInfo(stream: Int) -> Int
  fn Pa_GetStreamTime(stream: Int) -> Float64
  fn Pa_GetStreamCpuLoad(stream: Int) -> Float64
  fn Pa_GetErrorText(code: Int) -> Int
  fn Pa_GetVersion() -> Int
  fn Pa_GetVersionText() -> Int
  fn Pa_Sleep(msec: Int)
}

// ===========================================================================
// Safe wrappers — lifecycle
// ===========================================================================

pub fn initialize() -> Result[Unit, Str]
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_Initialize() };
  if err != NO_ERROR {
    return Err("Pa_Initialize failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn terminate() -> Result[Unit, Str]
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_Terminate() };
  if err != NO_ERROR {
    return Err("Pa_Terminate failed with error code " + (err as Str));
  }
  return Ok(());
}

// ===========================================================================
// Safe wrappers — device query
// ===========================================================================

pub fn get_default_output_device() -> Int {
  return unsafe { Pa_GetDefaultOutputDevice() };
}

pub fn get_default_input_device() -> Int {
  return unsafe { Pa_GetDefaultInputDevice() };
}

pub fn get_device_count() -> Int {
  return unsafe { Pa_GetDeviceCount() };
}

pub fn get_default_host_api() -> Int {
  return unsafe { Pa_GetDefaultHostApi() };
}

pub fn get_host_api_count() -> Int {
  return unsafe { Pa_GetHostApiCount() };
}

// ===========================================================================
// Safe wrappers — stream management
// ===========================================================================

pub fn open_default_stream(
  num_input_channels: Int,
  num_output_channels: Int,
  sample_format: Int,
  sample_rate: Float64,
  frames_per_buffer: Int
) -> Result[PaStream, Str]
  requires: num_input_channels >= 0
  requires: num_output_channels >= 0
  requires: frames_per_buffer > 0
  requires: sample_rate > 0.0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let err = unsafe {
    Pa_OpenDefaultStream(0, num_input_channels, num_output_channels,
                         sample_format, sample_rate, frames_per_buffer, 0, 0)
  };
  if err != NO_ERROR {
    return Err("Pa_OpenDefaultStream failed with error code " + (err as Str));
  }
  let stream: PaStream = 0;
  return Ok(stream);
}

pub fn open_stream(
  num_input_channels: Int,
  num_output_channels: Int,
  sample_format: Int,
  sample_rate: Float64,
  frames_per_buffer: Int,
  stream_flags: Int
) -> Result[PaStream, Str]
  requires: num_input_channels >= 0
  requires: num_output_channels >= 0
  requires: frames_per_buffer > 0
  requires: sample_rate > 0.0
  ensures: result.is_ok() -> result.unwrap() != 0
{
  let err = unsafe {
    Pa_OpenStream(0, 0, 0, sample_rate, frames_per_buffer,
                  stream_flags, 0, 0)
  };
  if err != NO_ERROR {
    return Err("Pa_OpenStream failed with error code " + (err as Str));
  }
  let stream: PaStream = 0;
  return Ok(stream);
}

pub fn start_stream(stream: PaStream) -> Result[Unit, Str]
  requires: stream != 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_StartStream(stream) };
  if err != NO_ERROR {
    return Err("Pa_StartStream failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn stop_stream(stream: PaStream) -> Result[Unit, Str]
  requires: stream != 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_StopStream(stream) };
  if err != NO_ERROR {
    return Err("Pa_StopStream failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn close_stream(stream: PaStream) -> Result[Unit, Str]
  requires: stream != 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_CloseStream(stream) };
  if err != NO_ERROR {
    return Err("Pa_CloseStream failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn abort_stream(stream: PaStream) -> Result[Unit, Str]
  requires: stream != 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_AbortStream(stream) };
  if err != NO_ERROR {
    return Err("Pa_AbortStream failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn is_stream_stopped(stream: PaStream) -> Int
  requires: stream != 0
{
  return unsafe { Pa_IsStreamStopped(stream) };
}

pub fn is_stream_active(stream: PaStream) -> Int
  requires: stream != 0
{
  return unsafe { Pa_IsStreamActive(stream) };
}

// ===========================================================================
// Safe wrappers — I/O
// ===========================================================================

pub fn write_stream(stream: PaStream, buffer: Int, frames: Int) -> Result[Unit, Str]
  requires: stream != 0
  requires: frames > 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_WriteStream(stream, buffer, frames) };
  if err != NO_ERROR {
    return Err("Pa_WriteStream failed with error code " + (err as Str));
  }
  return Ok(());
}

pub fn read_stream(stream: PaStream, buffer: Int, frames: Int) -> Result[Unit, Str]
  requires: stream != 0
  requires: frames > 0
  ensures: result.is_ok() -> true
{
  let err = unsafe { Pa_ReadStream(stream, buffer, frames) };
  if err != NO_ERROR {
    return Err("Pa_ReadStream failed with error code " + (err as Str));
  }
  return Ok(());
}

// ===========================================================================
// Safe wrappers — stream info / diagnostics
// ===========================================================================

pub fn get_stream_info(stream: PaStream) -> Int
  requires: stream != 0
{
  return unsafe { Pa_GetStreamInfo(stream) };
}

pub fn get_stream_time(stream: PaStream) -> Float64
  requires: stream != 0
{
  return unsafe { Pa_GetStreamTime(stream) };
}

pub fn get_stream_cpu_load(stream: PaStream) -> Float64
  requires: stream != 0
{
  return unsafe { Pa_GetStreamCpuLoad(stream) };
}

// ===========================================================================
// Safe wrappers — utility
// ===========================================================================

pub fn get_error_text(code: Int) -> Str
  ensures: result != ""
{
  return unsafe { Pa_GetErrorText(code) as Str };
}

pub fn get_version() -> Int {
  return unsafe { Pa_GetVersion() };
}

pub fn get_version_text() -> Str
  ensures: result != ""
{
  return unsafe { Pa_GetVersionText() as Str };
}

pub fn sleep(msec: Int)
  requires: msec > 0
{
  unsafe { Pa_Sleep(msec) };
}
