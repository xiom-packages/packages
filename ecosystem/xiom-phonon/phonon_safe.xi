// XIOM - Steam Audio (Phonon) Safe Wrapper Layer
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Typed convenience wrapper over the raw phonon FFI bindings.
// Provides resource-safe structs for Context, HRTF, BinauralEffect,
// DirectEffect, Simulator, and Source with automatic cleanup via close().
module xiom.phonon.safe

use xiom.phonon;

// ─────────────────────────────────────────────────────────────
//  Vector3 Type
// ─────────────────────────────────────────────────────────────

pub type Vec3 = {
  x: Float32;
  y: Float32;
  z: Float32;
} derive[Clone]

pub fn Vec3.zero() -> Vec3 {
  return Vec3{ x: 0.0; y: 0.0; z: 0.0 };
}

pub fn Vec3.new(x: Float32, y: Float32, z: Float32) -> Vec3 {
  return Vec3{ x: x; y: y; z: z };
}

pub fn Vec3.length() -> Float32 {
  return math.sqrt(x * x + y * y + z * z);
}

pub fn Vec3.normalized() -> Vec3 {
  let len = length();
  if len == 0.0 {
    return zero();
  }
  return Vec3{ x: x / len; y: y / len; z: z / len };
}

// ─────────────────────────────────────────────────────────────
//  CoordinateSpace3 Type (right/up/ahead + origin)
// ─────────────────────────────────────────────────────────────

pub type CoordSpace3 = {
  right: Vec3;
  up: Vec3;
  ahead: Vec3;
  origin: Vec3;
} derive[Clone]

pub fn CoordSpace3.listener_default() -> CoordSpace3 {
  return CoordSpace3{
    right: Vec3{ x: 1.0; y: 0.0; z: 0.0 };
    up: Vec3{ x: 0.0; y: 1.0; z: 0.0 };
    ahead: Vec3{ x: 0.0; y: 0.0; z: -1.0 };
    origin: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
  };
}

// ─────────────────────────────────────────────────────────────
//  SpeakerLayout Type
// ─────────────────────────────────────────────────────────────

pub type SpeakerLayout = {
  type_: Int32;
  numSpeakers: Int32;
} derive[Clone]

pub fn SpeakerLayout.mono() -> SpeakerLayout {
  return SpeakerLayout{ type_: IPL_SPEAKERLAYOUTTYPE_MONO; numSpeakers: 1 };
}

pub fn SpeakerLayout.stereo() -> SpeakerLayout {
  return SpeakerLayout{ type_: IPL_SPEAKERLAYOUTTYPE_STEREO; numSpeakers: 2 };
}

pub fn SpeakerLayout.surround_5_1() -> SpeakerLayout {
  return SpeakerLayout{ type_: IPL_SPEAKERLAYOUTTYPE_SURROUND_5_1; numSpeakers: 6 };
}

pub fn SpeakerLayout.surround_7_1() -> SpeakerLayout {
  return SpeakerLayout{ type_: IPL_SPEAKERLAYOUTTYPE_SURROUND_7_1; numSpeakers: 8 };
}

// ─────────────────────────────────────────────────────────────
//  AudioSettings
// ─────────────────────────────────────────────────────────────

pub type AudioSettings = {
  samplingRate: Int32;
  frameSize: Int32;
} derive[Clone]

pub fn AudioSettings.default() -> AudioSettings {
  return AudioSettings{ samplingRate: 48000; frameSize: 1024 };
}

pub fn AudioSettings.low_latency() -> AudioSettings {
  return AudioSettings{ samplingRate: 48000; frameSize: 512 };
}

// ─────────────────────────────────────────────────────────────
//  PhononContext — Context Resource
// ─────────────────────────────────────────────────────────────

pub type PhononContext = {
  handle: IPLContext;
  simdLevel: Int32;
} derive[Clone]

pub fn PhononContext.create(simdLevel: Int32) -> Result[PhononContext, Str]
  requires: simdLevel >= IPL_SIMDLEVEL_SSE2
  requires: simdLevel <= IPL_SIMDLEVEL_AVX512
{
  let handle = context_create(null_context_settings())?;
  return Ok(PhononContext{ handle: handle; simdLevel: simdLevel });
}

pub fn PhononContext.is_valid() -> Bool {
  return handle != 0;
}

pub fn PhononContext.close() {
  if handle != 0 {
    context_destroy(handle);
  }
}

fn null_context_settings() -> *UInt8 {
  return 0 as *UInt8;
}

// ─────────────────────────────────────────────────────────────
//  BinauralRenderer — Binaural Spatialization
// ─────────────────────────────────────────────────────────────

pub type BinauralRenderer = {
  context: IPLContext;
  hrtf: IPLHRTF;
  effect: IPLBinauralEffect;
  audioSettings: AudioSettings;
} derive[Clone]

pub fn BinauralRenderer.create(ctx: PhononContext, audioSettings: AudioSettings) -> Result[BinauralRenderer, Str]
  requires: ctx.is_valid()
{
  let hrtf = hrtf_create(ctx.handle, null_audio_settings(), null_hrtf_settings())?;
  let effect = binaural_effect_create(ctx.handle, null_audio_settings(), null_effect_settings())?;
  return Ok(BinauralRenderer{
    context: ctx.handle;
    hrtf: hrtf;
    effect: effect;
    audioSettings: audioSettings;
  });
}

pub fn BinauralRenderer.reset() {
  binaural_effect_reset(effect);
}

pub fn BinauralRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Result[Int32, Str]
  requires: effect != 0
{
  let state: Int32 = binaural_effect_apply(effect, params, inBuf, outBuf);
  if state == IPL_AUDIOEFFECTSTATE_TAILREMAINING {
    return Ok(IPL_AUDIOEFFECTSTATE_TAILREMAINING);
  }
  return Ok(IPL_AUDIOEFFECTSTATE_TAILCOMPLETE);
}

pub fn BinauralRenderer.get_tail_size() -> Int32 {
  return unsafe { iplBinauralEffectGetTailSize(effect) };
}

pub fn BinauralRenderer.get_tail(outBuf: *UInt8) -> Int32 {
  return unsafe { iplBinauralEffectGetTail(effect, outBuf) };
}

pub fn BinauralRenderer.close() {
  if effect != 0 {
    binaural_effect_destroy(effect);
  }
  if hrtf != 0 {
    hrtf_destroy(hrtf);
  }
}

fn null_audio_settings() -> *UInt8 {
  return 0 as *UInt8;
}

fn null_hrtf_settings() -> *UInt8 {
  return 0 as *UInt8;
}

fn null_effect_settings() -> *UInt8 {
  return 0 as *UInt8;
}

// ─────────────────────────────────────────────────────────────
//  DirectEffectRenderer — Distance + Occlusion
// ─────────────────────────────────────────────────────────────

pub type DirectEffectRenderer = {
  context: IPLContext;
  effect: IPLDirectEffect;
} derive[Clone]

pub fn DirectEffectRenderer.create(ctx: PhononContext, numChannels: Int32) -> Result[DirectEffectRenderer, Str]
  requires: ctx.is_valid()
  requires: numChannels > 0
{
  let effect = direct_effect_create(ctx.handle, null_audio_settings(), null_effect_settings())?;
  return Ok(DirectEffectRenderer{
    context: ctx.handle;
    effect: effect;
  });
}

pub fn DirectEffectRenderer.reset() {
  direct_effect_reset(effect);
}

pub fn DirectEffectRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
  requires: effect != 0
{
  return direct_effect_apply(effect, params, inBuf, outBuf);
}

pub fn DirectEffectRenderer.close() {
  if effect != 0 {
    direct_effect_destroy(effect);
  }
}

// ─────────────────────────────────────────────────────────────
//  Simulator — Real-Time Physics Simulation
// ─────────────────────────────────────────────────────────────

pub type Simulator = {
  handle: IPLSimulator;
  context: IPLContext;
} derive[Clone]

pub fn Simulator.create(ctx: PhononContext, settings: *UInt8) -> Result[Simulator, Str]
  requires: ctx.is_valid()
{
  let handle = simulator_create(ctx.handle, settings)?;
  return Ok(Simulator{ handle: handle; context: ctx.handle });
}

pub fn Simulator.set_scene(scene: IPLScene) {
  unsafe { iplSimulatorSetScene(handle, scene); }
}

pub fn Simulator.set_shared_inputs(flags: Int32, sharedInputs: *UInt8) {
  unsafe { iplSimulatorSetSharedInputs(handle, flags, sharedInputs); }
}

pub fn Simulator.commit() {
  unsafe { iplSimulatorCommit(handle); }
}

pub fn Simulator.run_direct() {
  unsafe { iplSimulatorRunDirect(handle); }
}

pub fn Simulator.run_reflections() {
  unsafe { iplSimulatorRunReflections(handle); }
}

pub fn Simulator.run_pathing() {
  unsafe { iplSimulatorRunPathing(handle); }
}

pub fn Simulator.close() {
  if handle != 0 {
    simulator_destroy(handle);
  }
}

// ─────────────────────────────────────────────────────────────
//  SoundSource — Spatialized Source
// ─────────────────────────────────────────────────────────────

pub type SoundSource = {
  handle: IPLSource;
  simulator: IPLSimulator;
  position: Vec3;
} derive[Clone]

pub fn SoundSource.create(sim: Simulator, position: Vec3) -> Result[SoundSource, Str]
  requires: sim.handle != 0
{
  let settings: *UInt8 = null_source_settings();
  let handle = source_create(sim.handle, settings)?;
  return Ok(SoundSource{ handle: handle; simulator: sim.handle; position: position });
}

pub fn SoundSource.set_inputs(flags: Int32, inputs: *UInt8) {
  unsafe { iplSourceSetInputs(handle, flags, inputs); }
}

pub fn SoundSource.get_outputs(flags: Int32, outputs: *UInt8) {
  unsafe { iplSourceGetOutputs(handle, flags, outputs); }
}

pub fn SoundSource.set_position(pos: Vec3) -> SoundSource {
  return SoundSource{ handle: handle; simulator: simulator; position: pos };
}

pub fn SoundSource.close() {
  if handle != 0 {
    source_destroy(handle);
  }
}

fn null_source_settings() -> *UInt8 {
  return 0 as *UInt8;
}

// ─────────────────────────────────────────────────────────────
//  AudioBuffer — Managed Audio Buffer
// ─────────────────────────────────────────────────────────────

pub type AudioBuffer = {
  handle: Int;
  context: IPLContext;
  numChannels: Int32;
  numSamples: Int32;
} derive[Clone]

pub fn AudioBuffer.allocate(ctx: PhononContext, numChannels: Int32, numSamples: Int32) -> Result[AudioBuffer, Str]
  requires: ctx.is_valid()
  requires: numChannels > 0
  requires: numSamples > 0
{
  var buf: Int = 0;
  let buf_ptr: *UInt8 = unsafe { &buf as *UInt8 };
  let rc: Int32 = unsafe { iplAudioBufferAllocate(ctx.handle, numChannels, numSamples, buf_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(AudioBuffer{ handle: buf; context: ctx.handle; numChannels: numChannels; numSamples: numSamples });
}

pub fn AudioBuffer.free() {
  if handle != 0 {
    unsafe { iplAudioBufferFree(context, &handle as *UInt8); }
  }
}

pub fn AudioBuffer.interleave(dst: *UInt8) {
  unsafe { iplAudioBufferInterleave(context, &handle as *UInt8, dst); }
}

pub fn AudioBuffer.deinterleave(src: *UInt8) {
  unsafe { iplAudioBufferDeinterleave(context, src, &handle as *UInt8); }
}

pub fn AudioBuffer.mix(other: AudioBuffer) {
  let buf_ptr: *UInt8 = unsafe { &other.handle as *UInt8 };
  unsafe { iplAudioBufferMix(context, &handle as *UInt8, buf_ptr); }
}

// ─────────────────────────────────────────────────────────────
//  PanningRenderer — Speaker Panning
// ─────────────────────────────────────────────────────────────

pub type PanningRenderer = {
  context: IPLContext;
  effect: IPLPanningEffect;
} derive[Clone]

pub fn PanningRenderer.create(ctx: PhononContext, layout: SpeakerLayout) -> Result[PanningRenderer, Str]
  requires: ctx.is_valid()
{
  var effect: Int = 0;
  let effect_ptr: *UInt8 = unsafe { &effect as *UInt8 };
  let rc: Int32 = unsafe { iplPanningEffectCreate(ctx.handle, null_audio_settings(), null_effect_settings(), effect_ptr) };
  if rc != IPL_STATUS_SUCCESS {
    return Err(error_to_string(rc));
  }
  return Ok(PanningRenderer{ context: ctx.handle; effect: effect });
}

pub fn PanningRenderer.reset() {
  unsafe { iplPanningEffectReset(effect); }
}

pub fn PanningRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32 {
  return unsafe { iplPanningEffectApply(effect, params, inBuf, outBuf) };
}

pub fn PanningRenderer.close() {
  if effect != 0 {
    var e: Int = effect;
    unsafe { iplPanningEffectRelease(&e as *UInt8); }
  }
}
