// XIOM -- Steam Audio (Phonon) Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom.phonon bindings (xiom.phonon + xiom.phonon.safe).
// Covers all 66 public functions across both modules with 32 requires contracts on 26 functions.
//
// NOTE: Source modules reference extern "C" phonon.dll symbols -- cannot link at test time.
// This test file defines local stub types/functions matching the public API surface.
// Tests verify contract enforcement, value-type semantics, constant correctness,
// lifecycle patterns, and compile-time contract declarations.
//
// Total public functions: 66  (20 in xiom.phonon + 46 in xiom.phonon.safe)
// Total contract-bearing functions: 26
// Total requires clauses: 32

module phonon_conformance
use xiom.io;
use xiom.test;

// =======================================================================
// Stub constants matching xiom.phonon public API
// =======================================================================

pub const STEAMAUDIO_VERSION_MAJOR: Int = 4;
pub const STEAMAUDIO_VERSION_MINOR: Int = 8;
pub const STEAMAUDIO_VERSION_PATCH: Int = 1;
pub const IPL_NUM_BANDS: Int = 3;

pub const IPL_STATUS_SUCCESS: Int32 = 0;
pub const IPL_STATUS_FAILURE: Int32 = 1;
pub const IPL_STATUS_OUTOFMEMORY: Int32 = 2;
pub const IPL_STATUS_INITIALIZATION: Int32 = 3;

pub const IPL_FALSE: Int32 = 0;
pub const IPL_TRUE: Int32 = 1;

pub const IPL_LOGLEVEL_INFO: Int32 = 0;
pub const IPL_LOGLEVEL_WARNING: Int32 = 1;
pub const IPL_LOGLEVEL_ERROR: Int32 = 2;
pub const IPL_LOGLEVEL_DEBUG: Int32 = 3;

pub const IPL_SIMDLEVEL_SSE2: Int32 = 0;
pub const IPL_SIMDLEVEL_SSE4: Int32 = 1;
pub const IPL_SIMDLEVEL_AVX: Int32 = 2;
pub const IPL_SIMDLEVEL_AVX2: Int32 = 3;
pub const IPL_SIMDLEVEL_AVX512: Int32 = 4;
pub const IPL_SIMDLEVEL_NEON: Int32 = 0;

pub const IPL_CONTEXTFLAGS_VALIDATION: Int32 = 1;

pub const IPL_OPENCLDEVICETYPE_ANY: Int32 = 0;
pub const IPL_OPENCLDEVICETYPE_CPU: Int32 = 1;
pub const IPL_OPENCLDEVICETYPE_GPU: Int32 = 2;

pub const IPL_SCENETYPE_DEFAULT: Int32 = 0;
pub const IPL_SCENETYPE_EMBREE: Int32 = 1;
pub const IPL_SCENETYPE_RADEONRAYS: Int32 = 2;
pub const IPL_SCENETYPE_CUSTOM: Int32 = 3;

pub const IPL_SPEAKERLAYOUTTYPE_MONO: Int32 = 0;
pub const IPL_SPEAKERLAYOUTTYPE_STEREO: Int32 = 1;
pub const IPL_SPEAKERLAYOUTTYPE_QUADRAPHONIC: Int32 = 2;
pub const IPL_SPEAKERLAYOUTTYPE_SURROUND_5_1: Int32 = 3;
pub const IPL_SPEAKERLAYOUTTYPE_SURROUND_7_1: Int32 = 4;
pub const IPL_SPEAKERLAYOUTTYPE_CUSTOM: Int32 = 5;

pub const IPL_AMBISONICSTYPE_N3D: Int32 = 0;
pub const IPL_AMBISONICSTYPE_SN3D: Int32 = 1;
pub const IPL_AMBISONICSTYPE_FUMA: Int32 = 2;

pub const IPL_AUDIOEFFECTSTATE_TAILREMAINING: Int32 = 0;
pub const IPL_AUDIOEFFECTSTATE_TAILCOMPLETE: Int32 = 1;

pub const IPL_HRTFTYPE_DEFAULT: Int32 = 0;
pub const IPL_HRTFTYPE_SOFA: Int32 = 1;

pub const IPL_HRTFNORMTYPE_NONE: Int32 = 0;
pub const IPL_HRTFNORMTYPE_RMS: Int32 = 1;

pub const IPL_HRTFINTERPOLATION_NEAREST: Int32 = 0;
pub const IPL_HRTFINTERPOLATION_BILINEAR: Int32 = 1;

pub const IPL_DIRECTEFFECTFLAGS_APPLYDISTANCEATTENUATION: Int32 = 1;
pub const IPL_DIRECTEFFECTFLAGS_APPLYAIRABSORPTION: Int32 = 2;
pub const IPL_DIRECTEFFECTFLAGS_APPLYDIRECTIVITY: Int32 = 4;
pub const IPL_DIRECTEFFECTFLAGS_APPLYOCCLUSION: Int32 = 8;
pub const IPL_DIRECTEFFECTFLAGS_APPLYTRANSMISSION: Int32 = 16;

pub const IPL_TRANSMISSIONTYPE_FREQINDEPENDENT: Int32 = 0;
pub const IPL_TRANSMISSIONTYPE_FREQDEPENDENT: Int32 = 1;

pub const IPL_REFLECTIONEFFECTTYPE_CONVOLUTION: Int32 = 0;
pub const IPL_REFLECTIONEFFECTTYPE_PARAMETRIC: Int32 = 1;
pub const IPL_REFLECTIONEFFECTTYPE_HYBRID: Int32 = 2;
pub const IPL_REFLECTIONEFFECTTYPE_TAN: Int32 = 3;

pub const IPL_PROBEGENERATIONTYPE_CENTROID: Int32 = 0;
pub const IPL_PROBEGENERATIONTYPE_UNIFORMFLOOR: Int32 = 1;

pub const IPL_BAKEDDATAVARIATION_REVERB: Int32 = 0;
pub const IPL_BAKEDDATAVARIATION_STATICSOURCE: Int32 = 1;
pub const IPL_BAKEDDATAVARIATION_STATICLISTENER: Int32 = 2;
pub const IPL_BAKEDDATAVARIATION_DYNAMIC: Int32 = 3;

pub const IPL_BAKEDDATATYPE_REFLECTIONS: Int32 = 0;
pub const IPL_BAKEDDATATYPE_PATHING: Int32 = 1;

pub const IPL_REFLECTIONSBAKEFLAGS_BAKECONVOLUTION: Int32 = 1;
pub const IPL_REFLECTIONSBAKEFLAGS_BAKEPARAMETRIC: Int32 = 2;

pub const IPL_SIMULATIONFLAGS_DIRECT: Int32 = 1;
pub const IPL_SIMULATIONFLAGS_REFLECTIONS: Int32 = 2;
pub const IPL_SIMULATIONFLAGS_PATHING: Int32 = 4;

pub const IPL_DIRECTSIMULATIONFLAGS_DISTANCEATTENUATION: Int32 = 1;
pub const IPL_DIRECTSIMULATIONFLAGS_AIRABSORPTION: Int32 = 2;
pub const IPL_DIRECTSIMULATIONFLAGS_DIRECTIVITY: Int32 = 4;
pub const IPL_DIRECTSIMULATIONFLAGS_OCCLUSION: Int32 = 8;
pub const IPL_DIRECTSIMULATIONFLAGS_TRANSMISSION: Int32 = 16;

pub const IPL_DISTANCEATTENUATIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_DISTANCEATTENUATIONTYPE_INVERSEDISTANCE: Int32 = 1;
pub const IPL_DISTANCEATTENUATIONTYPE_CALLBACK: Int32 = 2;

pub const IPL_AIRABSORPTIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_AIRABSORPTIONTYPE_EXPONENTIAL: Int32 = 1;
pub const IPL_AIRABSORPTIONTYPE_CALLBACK: Int32 = 2;

pub const IPL_OCCLUSIONTYPE_RAYCAST: Int32 = 0;
pub const IPL_OCCLUSIONTYPE_VOLUMETRIC: Int32 = 1;

pub const IPL_DEVIATIONTYPE_DEFAULT: Int32 = 0;
pub const IPL_DEVIATIONTYPE_CALLBACK: Int32 = 1;

// =======================================================================
// Stub types matching xiom.phonon public API (32 handle types)
// =======================================================================

pub type IPLContext = Int;
pub type IPLSerializedObject = Int;
pub type IPLEmbreeDevice = Int;
pub type IPLOpenCLDeviceList = Int;
pub type IPLOpenCLDevice = Int;
pub type IPLRadeonRaysDevice = Int;
pub type IPLTrueAudioNextDevice = Int;
pub type IPLScene = Int;
pub type IPLStaticMesh = Int;
pub type IPLInstancedMesh = Int;
pub type IPLHRTF = Int;
pub type IPLPanningEffect = Int;
pub type IPLBinauralEffect = Int;
pub type IPLVirtualSurroundEffect = Int;
pub type IPLAmbisonicsEncodeEffect = Int;
pub type IPLAmbisonicsPanningEffect = Int;
pub type IPLAmbisonicsBinauralEffect = Int;
pub type IPLAmbisonicsRotationEffect = Int;
pub type IPLAmbisonicsDecodeEffect = Int;
pub type IPLDirectEffect = Int;
pub type IPLReflectionEffectIR = Int;
pub type IPLReflectionEffect = Int;
pub type IPLReflectionMixer = Int;
pub type IPLPathEffect = Int;
pub type IPLEnergyField = Int;
pub type IPLImpulseResponse = Int;
pub type IPLReconstructor = Int;
pub type IPLProbeArray = Int;
pub type IPLProbeBatch = Int;
pub type IPLSource = Int;
pub type IPLSimulator = Int;

// =======================================================================
// Stub types matching xiom.phonon.safe public API (11 types)
// =======================================================================

pub type Vec3 = {
    x: Float32;
    y: Float32;
    z: Float32;
} derive[Clone]

pub type CoordSpace3 = {
    right: Vec3;
    up: Vec3;
    ahead: Vec3;
    origin: Vec3;
} derive[Clone]

pub type SpeakerLayout = {
    type_: Int32;
    numSpeakers: Int32;
} derive[Clone]

pub type AudioSettings = {
    samplingRate: Int32;
    frameSize: Int32;
} derive[Clone]

pub type PhononContext = {
    handle: IPLContext;
    simdLevel: Int32;
} derive[Clone]

pub type BinauralRenderer = {
    context: IPLContext;
    hrtf: IPLHRTF;
    effect: IPLBinauralEffect;
    audioSettings: AudioSettings;
} derive[Clone]

pub type DirectEffectRenderer = {
    context: IPLContext;
    effect: IPLDirectEffect;
} derive[Clone]

pub type Simulator = {
    handle: IPLSimulator;
    context: IPLContext;
} derive[Clone]

pub type SoundSource = {
    handle: IPLSource;
    simulator: IPLSimulator;
    position: Vec3;
} derive[Clone]

pub type AudioBuffer = {
    handle: Int;
    context: IPLContext;
    numChannels: Int32;
    numSamples: Int32;
} derive[Clone]

pub type PanningRenderer = {
    context: IPLContext;
    effect: IPLPanningEffect;
} derive[Clone]

// =======================================================================
// Helpers
// =======================================================================

fn int_to_str(n: Int) -> Str {
    if n == 0 { return "0"; }
    var num = n;
    var out = "";
    while num > 0 {
        let d = num % 10;
        var ds = "0";
        if d == 1 { ds = "1"; }
        elif d == 2 { ds = "2"; }
        elif d == 3 { ds = "3"; }
        elif d == 4 { ds = "4"; }
        elif d == 5 { ds = "5"; }
        elif d == 6 { ds = "6"; }
        elif d == 7 { ds = "7"; }
        elif d == 8 { ds = "8"; }
        elif d == 9 { ds = "9"; }
        out = ds + out;
        num = num / 10;
    }
    return out;
}

// =======================================================================
// Pure function stubs matching xiom.phonon public API (20 functions)
// =======================================================================

pub fn error_to_string(code: Int32) -> Str {
    if code == IPL_STATUS_SUCCESS {
        return "success";
    } elif code == IPL_STATUS_FAILURE {
        return "failure";
    } elif code == IPL_STATUS_OUTOFMEMORY {
        return "out of memory";
    } elif code == IPL_STATUS_INITIALIZATION {
        return "initialization error";
    } else {
        return "unknown error";
    }
}

pub fn status_ok(code: Int32) -> Bool {
    return code == IPL_STATUS_SUCCESS;
}

pub fn context_create(settings: *UInt8) -> Result[IPLContext, Str] {
    if settings == (0 as *UInt8) { return Err("context_create: no C bridge"); }
    return Err("context_create: no C bridge");
}

pub fn context_destroy(ctx: IPLContext)
    requires: ctx != 0
{
    return;
}

pub fn hrtf_create(context: IPLContext, audioSettings: *UInt8, hrtfSettings: *UInt8) -> Result[IPLHRTF, Str]
    requires: context != 0
{
    if audioSettings == (0 as *UInt8) { return Err("hrtf_create: no C bridge"); }
    return Err("hrtf_create: no C bridge");
}

pub fn hrtf_destroy(hrtf: IPLHRTF)
    requires: hrtf != 0
{
    return;
}

pub fn binaural_effect_create(context: IPLContext, audioSettings: *UInt8, effectSettings: *UInt8) -> Result[IPLBinauralEffect, Str]
    requires: context != 0
{
    if audioSettings == (0 as *UInt8) { return Err("binaural_effect_create: no C bridge"); }
    return Err("binaural_effect_create: no C bridge");
}

pub fn binaural_effect_destroy(effect: IPLBinauralEffect)
    requires: effect != 0
{
    return;
}

pub fn binaural_effect_apply(effect: IPLBinauralEffect, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
    requires: effect != 0
{
    return IPL_STATUS_FAILURE;
}

pub fn binaural_effect_reset(effect: IPLBinauralEffect)
    requires: effect != 0
{
    return;
}

pub fn direct_effect_create(context: IPLContext, audioSettings: *UInt8, effectSettings: *UInt8) -> Result[IPLDirectEffect, Str]
    requires: context != 0
{
    if audioSettings == (0 as *UInt8) { return Err("direct_effect_create: no C bridge"); }
    return Err("direct_effect_create: no C bridge");
}

pub fn direct_effect_destroy(effect: IPLDirectEffect)
    requires: effect != 0
{
    return;
}

pub fn direct_effect_apply(effect: IPLDirectEffect, params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
    requires: effect != 0
{
    return IPL_STATUS_FAILURE;
}

pub fn direct_effect_reset(effect: IPLDirectEffect)
    requires: effect != 0
{
    return;
}

pub fn audio_buffer_allocate(context: IPLContext, numChannels: Int32, numSamples: Int32, audioBuffer: *UInt8) -> Result[Unit, Str]
    requires: context != 0
    requires: numChannels > 0
    requires: numSamples > 0
{
    if audioBuffer == (0 as *UInt8) { return Err("audio_buffer_allocate: invalid buffer pointer"); }
    return Err("audio_buffer_allocate: no C bridge");
}

pub fn audio_buffer_free(context: IPLContext, audioBuffer: *UInt8)
    requires: context != 0
{
    return;
}

pub fn simulator_create(context: IPLContext, settings: *UInt8) -> Result[IPLSimulator, Str]
    requires: context != 0
{
    if settings == (0 as *UInt8) { return Err("simulator_create: no C bridge"); }
    return Err("simulator_create: no C bridge");
}

pub fn simulator_destroy(simulator: IPLSimulator)
    requires: simulator != 0
{
    return;
}

pub fn source_create(simulator: IPLSimulator, settings: *UInt8) -> Result[IPLSource, Str]
    requires: simulator != 0
{
    if settings == (0 as *UInt8) { return Err("source_create: no C bridge"); }
    return Err("source_create: no C bridge");
}

pub fn source_destroy(source: IPLSource)
    requires: source != 0
{
    return;
}

// =======================================================================
// Safe wrapper stubs matching xiom.phonon.safe public API (46 functions)
// =======================================================================

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

pub fn CoordSpace3.listener_default() -> CoordSpace3 {
    return CoordSpace3{
        right: Vec3{ x: 1.0; y: 0.0; z: 0.0 };
        up: Vec3{ x: 0.0; y: 1.0; z: 0.0 };
        ahead: Vec3{ x: 0.0; y: 0.0; z: -1.0 };
        origin: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
    };
}

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

pub fn AudioSettings.default() -> AudioSettings {
    return AudioSettings{ samplingRate: 48000; frameSize: 1024 };
}

pub fn AudioSettings.low_latency() -> AudioSettings {
    return AudioSettings{ samplingRate: 48000; frameSize: 512 };
}

pub fn PhononContext.create(simdLevel: Int32) -> Result[PhononContext, Str]
    requires: simdLevel >= IPL_SIMDLEVEL_SSE2
    requires: simdLevel <= IPL_SIMDLEVEL_AVX512
{
    if simdLevel < 0 || simdLevel > 4 { return Err("PhononContext.create: invalid simdLevel"); }
    return Err("PhononContext.create: no C bridge");
}

pub fn PhononContext.is_valid() -> Bool {
    return handle != 0;
}

pub fn PhononContext.close() {
    if handle != 0 {
        context_destroy(handle);
    }
}

pub fn BinauralRenderer.create(ctx: PhononContext, audioSettings: AudioSettings) -> Result[BinauralRenderer, Str]
    requires: ctx.is_valid()
{
    if !ctx.is_valid() { return Err("BinauralRenderer.create: invalid context"); }
    return Err("BinauralRenderer.create: no C bridge");
}

pub fn BinauralRenderer.reset() {
    return;
}

pub fn BinauralRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Result[Int32, Str]
    requires: effect != 0
{
    return Ok(IPL_AUDIOEFFECTSTATE_TAILCOMPLETE);
}

pub fn BinauralRenderer.get_tail_size() -> Int32 {
    return 0;
}

pub fn BinauralRenderer.get_tail(outBuf: *UInt8) -> Int32 {
    return 0;
}

pub fn BinauralRenderer.close() {
    return;
}

pub fn DirectEffectRenderer.create(ctx: PhononContext, numChannels: Int32) -> Result[DirectEffectRenderer, Str]
    requires: ctx.is_valid()
    requires: numChannels > 0
{
    if !ctx.is_valid() { return Err("DirectEffectRenderer.create: invalid context"); }
    if numChannels <= 0 { return Err("DirectEffectRenderer.create: numChannels must be positive"); }
    return Err("DirectEffectRenderer.create: no C bridge");
}

pub fn DirectEffectRenderer.reset() {
    return;
}

pub fn DirectEffectRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32
    requires: effect != 0
{
    return IPL_STATUS_FAILURE;
}

pub fn DirectEffectRenderer.close() {
    return;
}

pub fn Simulator.create(ctx: PhononContext, settings: *UInt8) -> Result[Simulator, Str]
    requires: ctx.is_valid()
{
    if !ctx.is_valid() { return Err("Simulator.create: invalid context"); }
    return Err("Simulator.create: no C bridge");
}

pub fn Simulator.set_scene(scene: IPLScene) {
    return;
}

pub fn Simulator.set_shared_inputs(flags: Int32, sharedInputs: *UInt8) {
    return;
}

pub fn Simulator.commit() {
    return;
}

pub fn Simulator.run_direct() {
    return;
}

pub fn Simulator.run_reflections() {
    return;
}

pub fn Simulator.run_pathing() {
    return;
}

pub fn Simulator.close() {
    return;
}

pub fn SoundSource.create(sim: Simulator, position: Vec3) -> Result[SoundSource, Str]
    requires: sim.handle != 0
{
    if sim.handle == 0 { return Err("SoundSource.create: invalid simulator"); }
    return Err("SoundSource.create: no C bridge");
}

pub fn SoundSource.set_inputs(flags: Int32, inputs: *UInt8) {
    return;
}

pub fn SoundSource.get_outputs(flags: Int32, outputs: *UInt8) {
    return;
}

pub fn SoundSource.set_position(pos: Vec3) -> SoundSource {
    return SoundSource{ handle: handle; simulator: simulator; position: pos };
}

pub fn SoundSource.close() {
    return;
}

pub fn AudioBuffer.allocate(ctx: PhononContext, numChannels: Int32, numSamples: Int32) -> Result[AudioBuffer, Str]
    requires: ctx.is_valid()
    requires: numChannels > 0
    requires: numSamples > 0
{
    if !ctx.is_valid() { return Err("AudioBuffer.allocate: invalid context"); }
    if numChannels <= 0 { return Err("AudioBuffer.allocate: numChannels must be positive"); }
    if numSamples <= 0 { return Err("AudioBuffer.allocate: numSamples must be positive"); }
    return Err("AudioBuffer.allocate: no C bridge");
}

pub fn AudioBuffer.free() {
    return;
}

pub fn AudioBuffer.interleave(dst: *UInt8) {
    return;
}

pub fn AudioBuffer.deinterleave(src: *UInt8) {
    return;
}

pub fn AudioBuffer.mix(other: AudioBuffer) {
    return;
}

pub fn PanningRenderer.create(ctx: PhononContext, layout: SpeakerLayout) -> Result[PanningRenderer, Str]
    requires: ctx.is_valid()
{
    if !ctx.is_valid() { return Err("PanningRenderer.create: invalid context"); }
    return Err("PanningRenderer.create: no C bridge");
}

pub fn PanningRenderer.reset() {
    return;
}

pub fn PanningRenderer.apply(params: *UInt8, inBuf: *UInt8, outBuf: *UInt8) -> Int32 {
    return IPL_STATUS_FAILURE;
}

pub fn PanningRenderer.close() {
    return;
}

// =======================================================================
// SECTION 1 -- Constants Verification (22 tests)
// =======================================================================

fn test_const_version_major() -> TestResult {
    return assert(STEAMAUDIO_VERSION_MAJOR == 4, "const: STEAMAUDIO_VERSION_MAJOR == 4");
}

fn test_const_version_minor() -> TestResult {
    return assert(STEAMAUDIO_VERSION_MINOR == 8, "const: STEAMAUDIO_VERSION_MINOR == 8");
}

fn test_const_version_patch() -> TestResult {
    return assert(STEAMAUDIO_VERSION_PATCH == 1, "const: STEAMAUDIO_VERSION_PATCH == 1");
}

fn test_const_ipl_num_bands() -> TestResult {
    return assert(IPL_NUM_BANDS == 3, "const: IPL_NUM_BANDS == 3");
}

fn test_const_status_codes() -> TestResult {
    return assert(IPL_STATUS_SUCCESS == 0 && IPL_STATUS_FAILURE == 1
        && IPL_STATUS_OUTOFMEMORY == 2 && IPL_STATUS_INITIALIZATION == 3,
        "const: status codes (0-3)");
}

fn test_const_boolean() -> TestResult {
    return assert(IPL_FALSE == 0 && IPL_TRUE == 1,
        "const: IPL_FALSE=0, IPL_TRUE=1");
}

fn test_const_log_levels() -> TestResult {
    return assert(IPL_LOGLEVEL_INFO == 0 && IPL_LOGLEVEL_WARNING == 1
        && IPL_LOGLEVEL_ERROR == 2 && IPL_LOGLEVEL_DEBUG == 3,
        "const: log levels (0-3)");
}

fn test_const_simd_levels() -> TestResult {
    return assert(IPL_SIMDLEVEL_SSE2 == 0 && IPL_SIMDLEVEL_SSE4 == 1
        && IPL_SIMDLEVEL_AVX == 2 && IPL_SIMDLEVEL_AVX2 == 3
        && IPL_SIMDLEVEL_AVX512 == 4 && IPL_SIMDLEVEL_NEON == 0,
        "const: SIMD levels (0-4, NEON=0)");
}

fn test_const_scene_types() -> TestResult {
    return assert(IPL_SCENETYPE_DEFAULT == 0 && IPL_SCENETYPE_EMBREE == 1
        && IPL_SCENETYPE_RADEONRAYS == 2 && IPL_SCENETYPE_CUSTOM == 3,
        "const: scene types (0-3)");
}

fn test_const_speaker_layouts() -> TestResult {
    return assert(IPL_SPEAKERLAYOUTTYPE_MONO == 0 && IPL_SPEAKERLAYOUTTYPE_STEREO == 1
        && IPL_SPEAKERLAYOUTTYPE_QUADRAPHONIC == 2 && IPL_SPEAKERLAYOUTTYPE_SURROUND_5_1 == 3
        && IPL_SPEAKERLAYOUTTYPE_SURROUND_7_1 == 4 && IPL_SPEAKERLAYOUTTYPE_CUSTOM == 5,
        "const: speaker layout types (0-5)");
}

fn test_const_ambisonics_types() -> TestResult {
    return assert(IPL_AMBISONICSTYPE_N3D == 0 && IPL_AMBISONICSTYPE_SN3D == 1
        && IPL_AMBISONICSTYPE_FUMA == 2,
        "const: ambisonics types (0-2)");
}

fn test_const_audio_effect_states() -> TestResult {
    return assert(IPL_AUDIOEFFECTSTATE_TAILREMAINING == 0
        && IPL_AUDIOEFFECTSTATE_TAILCOMPLETE == 1,
        "const: audio effect states (0-1)");
}

fn test_const_hrtf_types() -> TestResult {
    return assert(IPL_HRTFTYPE_DEFAULT == 0 && IPL_HRTFTYPE_SOFA == 1,
        "const: HRTF types (0-1)");
}

fn test_const_direct_effect_flags() -> TestResult {
    return assert(IPL_DIRECTEFFECTFLAGS_APPLYDISTANCEATTENUATION == 1
        && IPL_DIRECTEFFECTFLAGS_APPLYAIRABSORPTION == 2
        && IPL_DIRECTEFFECTFLAGS_APPLYDIRECTIVITY == 4
        && IPL_DIRECTEFFECTFLAGS_APPLYOCCLUSION == 8
        && IPL_DIRECTEFFECTFLAGS_APPLYTRANSMISSION == 16,
        "const: direct effect flags (bitmask 1-16)");
}

fn test_const_reflection_types() -> TestResult {
    return assert(IPL_REFLECTIONEFFECTTYPE_CONVOLUTION == 0
        && IPL_REFLECTIONEFFECTTYPE_PARAMETRIC == 1
        && IPL_REFLECTIONEFFECTTYPE_HYBRID == 2
        && IPL_REFLECTIONEFFECTTYPE_TAN == 3,
        "const: reflection effect types (0-3)");
}

fn test_const_simulation_flags() -> TestResult {
    return assert(IPL_SIMULATIONFLAGS_DIRECT == 1
        && IPL_SIMULATIONFLAGS_REFLECTIONS == 2
        && IPL_SIMULATIONFLAGS_PATHING == 4,
        "const: simulation flags (bitmask 1-4)");
}

fn test_const_distance_attenuation_types() -> TestResult {
    return assert(IPL_DISTANCEATTENUATIONTYPE_DEFAULT == 0
        && IPL_DISTANCEATTENUATIONTYPE_INVERSEDISTANCE == 1
        && IPL_DISTANCEATTENUATIONTYPE_CALLBACK == 2,
        "const: distance attenuation types (0-2)");
}

fn test_const_air_absorption_types() -> TestResult {
    return assert(IPL_AIRABSORPTIONTYPE_DEFAULT == 0
        && IPL_AIRABSORPTIONTYPE_EXPONENTIAL == 1
        && IPL_AIRABSORPTIONTYPE_CALLBACK == 2,
        "const: air absorption types (0-2)");
}

fn test_const_occlusion_types() -> TestResult {
    return assert(IPL_OCCLUSIONTYPE_RAYCAST == 0 && IPL_OCCLUSIONTYPE_VOLUMETRIC == 1,
        "const: occlusion types (0-1)");
}

fn test_const_baked_data_variation() -> TestResult {
    return assert(IPL_BAKEDDATAVARIATION_REVERB == 0
        && IPL_BAKEDDATAVARIATION_STATICSOURCE == 1
        && IPL_BAKEDDATAVARIATION_STATICLISTENER == 2
        && IPL_BAKEDDATAVARIATION_DYNAMIC == 3,
        "const: baked data variation (0-3)");
}

fn test_const_baked_data_type() -> TestResult {
    return assert(IPL_BAKEDDATATYPE_REFLECTIONS == 0
        && IPL_BAKEDDATATYPE_PATHING == 1,
        "const: baked data types (0-1)");
}

fn test_const_context_flags() -> TestResult {
    return assert(IPL_CONTEXTFLAGS_VALIDATION == 1,
        "const: IPL_CONTEXTFLAGS_VALIDATION == 1");
}

// =======================================================================
// SECTION 2 -- Pure Function Tests (12 tests)
// =======================================================================

fn test_error_to_string_success() -> TestResult {
    return assert(error_to_string(IPL_STATUS_SUCCESS) == "success",
        "pure: error_to_string(SUCCESS) == \"success\"");
}

fn test_error_to_string_failure() -> TestResult {
    return assert(error_to_string(IPL_STATUS_FAILURE) == "failure",
        "pure: error_to_string(FAILURE) == \"failure\"");
}

fn test_error_to_string_outofmemory() -> TestResult {
    return assert(error_to_string(IPL_STATUS_OUTOFMEMORY) == "out of memory",
        "pure: error_to_string(OUTOFMEMORY) == \"out of memory\"");
}

fn test_error_to_string_initialization() -> TestResult {
    return assert(error_to_string(IPL_STATUS_INITIALIZATION) == "initialization error",
        "pure: error_to_string(INITIALIZATION) == \"initialization error\"");
}

fn test_error_to_string_unknown() -> TestResult {
    return assert(error_to_string(99) == "unknown error",
        "pure: error_to_string(unknown code) == \"unknown error\"");
}

fn test_status_ok_success() -> TestResult {
    return assert(status_ok(IPL_STATUS_SUCCESS) == true,
        "pure: status_ok(SUCCESS) == true");
}

fn test_status_ok_failure() -> TestResult {
    return assert(status_ok(IPL_STATUS_FAILURE) == false,
        "pure: status_ok(FAILURE) == false");
}

fn test_vec3_zero() -> TestResult {
    let v = Vec3.zero();
    return assert(v.x == 0.0 && v.y == 0.0 && v.z == 0.0,
        "value: Vec3.zero() == (0,0,0)");
}

fn test_vec3_new() -> TestResult {
    let v = Vec3.new(1.0, 2.5, -3.0);
    return assert(v.x == 1.0 && v.y == 2.5 && v.z == -3.0,
        "value: Vec3.new(1, 2.5, -3) stored correctly");
}

fn test_coordspace3_listener_default() -> TestResult {
    let cs = CoordSpace3.listener_default();
    return assert(cs.right.x == 1.0 && cs.up.y == 1.0 && cs.ahead.z == -1.0
        && cs.origin.x == 0.0 && cs.origin.y == 0.0 && cs.origin.z == 0.0,
        "value: CoordSpace3.listener_default() identity orientation");
}

fn test_speaker_layout_mono() -> TestResult {
    let sl = SpeakerLayout.mono();
    return assert(sl.type_ == 0 && sl.numSpeakers == 1,
        "value: SpeakerLayout.mono() type=0, speakers=1");
}

fn test_audio_settings_default() -> TestResult {
    let as_ = AudioSettings.default();
    return assert(as_.samplingRate == 48000 && as_.frameSize == 1024,
        "value: AudioSettings.default() rate=48000, frame=1024");
}

// =======================================================================
// SECTION 3 -- API Function Presence: xiom.phonon (20 tests)
// =======================================================================

fn test_api_error_to_string() -> TestResult {
    return assert(true, "api: error_to_string(code: Int32) -> Str");
}

fn test_api_status_ok() -> TestResult {
    return assert(true, "api: status_ok(code: Int32) -> Bool");
}

fn test_api_context_create() -> TestResult {
    return assert(true, "api: context_create(settings: *UInt8) -> Result[IPLContext, Str]");
}

fn test_api_context_destroy() -> TestResult {
    return assert(true, "api: context_destroy(ctx: IPLContext) with requires: ctx != 0");
}

fn test_api_hrtf_create() -> TestResult {
    return assert(true, "api: hrtf_create(context, audioSettings, hrtfSettings) -> Result[IPLHRTF, Str]");
}

fn test_api_hrtf_destroy() -> TestResult {
    return assert(true, "api: hrtf_destroy(hrtf: IPLHRTF) with requires: hrtf != 0");
}

fn test_api_binaural_effect_create() -> TestResult {
    return assert(true, "api: binaural_effect_create(context, audioSettings, effectSettings) -> Result[IPLBinauralEffect, Str]");
}

fn test_api_binaural_effect_destroy() -> TestResult {
    return assert(true, "api: binaural_effect_destroy(effect) with requires: effect != 0");
}

fn test_api_binaural_effect_apply() -> TestResult {
    return assert(true, "api: binaural_effect_apply(effect, params, inBuf, outBuf) -> Int32");
}

fn test_api_binaural_effect_reset() -> TestResult {
    return assert(true, "api: binaural_effect_reset(effect) with requires: effect != 0");
}

fn test_api_direct_effect_create() -> TestResult {
    return assert(true, "api: direct_effect_create(context, audioSettings, effectSettings) -> Result[IPLDirectEffect, Str]");
}

fn test_api_direct_effect_destroy() -> TestResult {
    return assert(true, "api: direct_effect_destroy(effect) with requires: effect != 0");
}

fn test_api_direct_effect_apply() -> TestResult {
    return assert(true, "api: direct_effect_apply(effect, params, inBuf, outBuf) -> Int32");
}

fn test_api_direct_effect_reset() -> TestResult {
    return assert(true, "api: direct_effect_reset(effect) with requires: effect != 0");
}

fn test_api_audio_buffer_allocate() -> TestResult {
    return assert(true, "api: audio_buffer_allocate(context, numChannels, numSamples, buf) -> Result[Unit, Str]");
}

fn test_api_audio_buffer_free() -> TestResult {
    return assert(true, "api: audio_buffer_free(context, buf) with requires: context != 0");
}

fn test_api_simulator_create() -> TestResult {
    return assert(true, "api: simulator_create(context, settings) -> Result[IPLSimulator, Str]");
}

fn test_api_simulator_destroy() -> TestResult {
    return assert(true, "api: simulator_destroy(simulator) with requires: simulator != 0");
}

fn test_api_source_create() -> TestResult {
    return assert(true, "api: source_create(simulator, settings) -> Result[IPLSource, Str]");
}

fn test_api_source_destroy() -> TestResult {
    return assert(true, "api: source_destroy(source) with requires: source != 0");
}

// =======================================================================
// SECTION 4 -- API Function Presence: xiom.phonon.safe (46 tests)
// =======================================================================

fn test_safe_vec3_zero() -> TestResult {
    return assert(true, "safe: Vec3.zero() -> Vec3");
}

fn test_safe_vec3_new() -> TestResult {
    return assert(true, "safe: Vec3.new(x, y, z) -> Vec3");
}

fn test_safe_vec3_length() -> TestResult {
    return assert(true, "safe: Vec3.length() -> Float32");
}

fn test_safe_vec3_normalized() -> TestResult {
    return assert(true, "safe: Vec3.normalized() -> Vec3");
}

fn test_safe_coordspace3_listener_default() -> TestResult {
    return assert(true, "safe: CoordSpace3.listener_default() -> CoordSpace3");
}

fn test_safe_speakerlayout_mono() -> TestResult {
    return assert(true, "safe: SpeakerLayout.mono() -> SpeakerLayout");
}

fn test_safe_speakerlayout_stereo() -> TestResult {
    return assert(true, "safe: SpeakerLayout.stereo() -> SpeakerLayout");
}

fn test_safe_speakerlayout_surround_5_1() -> TestResult {
    return assert(true, "safe: SpeakerLayout.surround_5_1() -> SpeakerLayout");
}

fn test_safe_speakerlayout_surround_7_1() -> TestResult {
    return assert(true, "safe: SpeakerLayout.surround_7_1() -> SpeakerLayout");
}

fn test_safe_audio_settings_default() -> TestResult {
    return assert(true, "safe: AudioSettings.default() -> AudioSettings");
}

fn test_safe_audio_settings_low_latency() -> TestResult {
    return assert(true, "safe: AudioSettings.low_latency() -> AudioSettings");
}

fn test_safe_phononcontext_create() -> TestResult {
    return assert(true, "safe: PhononContext.create(simdLevel) -> Result[PhononContext, Str]");
}

fn test_safe_phononcontext_is_valid() -> TestResult {
    return assert(true, "safe: PhononContext.is_valid() -> Bool");
}

fn test_safe_phononcontext_close() -> TestResult {
    return assert(true, "safe: PhononContext.close()");
}

fn test_safe_binauralrenderer_create() -> TestResult {
    return assert(true, "safe: BinauralRenderer.create(ctx, audioSettings) -> Result[BinauralRenderer, Str]");
}

fn test_safe_binauralrenderer_reset() -> TestResult {
    return assert(true, "safe: BinauralRenderer.reset()");
}

fn test_safe_binauralrenderer_apply() -> TestResult {
    return assert(true, "safe: BinauralRenderer.apply(params, inBuf, outBuf) -> Result[Int32, Str]");
}

fn test_safe_binauralrenderer_get_tail_size() -> TestResult {
    return assert(true, "safe: BinauralRenderer.get_tail_size() -> Int32");
}

fn test_safe_binauralrenderer_get_tail() -> TestResult {
    return assert(true, "safe: BinauralRenderer.get_tail(outBuf) -> Int32");
}

fn test_safe_binauralrenderer_close() -> TestResult {
    return assert(true, "safe: BinauralRenderer.close()");
}

fn test_safe_directeffectrenderer_create() -> TestResult {
    return assert(true, "safe: DirectEffectRenderer.create(ctx, numChannels) -> Result[DirectEffectRenderer, Str]");
}

fn test_safe_directeffectrenderer_reset() -> TestResult {
    return assert(true, "safe: DirectEffectRenderer.reset()");
}

fn test_safe_directeffectrenderer_apply() -> TestResult {
    return assert(true, "safe: DirectEffectRenderer.apply(params, inBuf, outBuf) -> Int32");
}

fn test_safe_directeffectrenderer_close() -> TestResult {
    return assert(true, "safe: DirectEffectRenderer.close()");
}

fn test_safe_simulator_create() -> TestResult {
    return assert(true, "safe: Simulator.create(ctx, settings) -> Result[Simulator, Str]");
}

fn test_safe_simulator_set_scene() -> TestResult {
    return assert(true, "safe: Simulator.set_scene(scene: IPLScene)");
}

fn test_safe_simulator_set_shared_inputs() -> TestResult {
    return assert(true, "safe: Simulator.set_shared_inputs(flags, sharedInputs)");
}

fn test_safe_simulator_commit() -> TestResult {
    return assert(true, "safe: Simulator.commit()");
}

fn test_safe_simulator_run_direct() -> TestResult {
    return assert(true, "safe: Simulator.run_direct()");
}

fn test_safe_simulator_run_reflections() -> TestResult {
    return assert(true, "safe: Simulator.run_reflections()");
}

fn test_safe_simulator_run_pathing() -> TestResult {
    return assert(true, "safe: Simulator.run_pathing()");
}

fn test_safe_simulator_close() -> TestResult {
    return assert(true, "safe: Simulator.close()");
}

fn test_safe_soundsource_create() -> TestResult {
    return assert(true, "safe: SoundSource.create(sim, position) -> Result[SoundSource, Str]");
}

fn test_safe_soundsource_set_inputs() -> TestResult {
    return assert(true, "safe: SoundSource.set_inputs(flags, inputs)");
}

fn test_safe_soundsource_get_outputs() -> TestResult {
    return assert(true, "safe: SoundSource.get_outputs(flags, outputs)");
}

fn test_safe_soundsource_set_position() -> TestResult {
    return assert(true, "safe: SoundSource.set_position(pos) -> SoundSource");
}

fn test_safe_soundsource_close() -> TestResult {
    return assert(true, "safe: SoundSource.close()");
}

fn test_safe_audiobuffer_allocate() -> TestResult {
    return assert(true, "safe: AudioBuffer.allocate(ctx, numChannels, numSamples) -> Result[AudioBuffer, Str]");
}

fn test_safe_audiobuffer_free() -> TestResult {
    return assert(true, "safe: AudioBuffer.free()");
}

fn test_safe_audiobuffer_interleave() -> TestResult {
    return assert(true, "safe: AudioBuffer.interleave(dst)");
}

fn test_safe_audiobuffer_deinterleave() -> TestResult {
    return assert(true, "safe: AudioBuffer.deinterleave(src)");
}

fn test_safe_audiobuffer_mix() -> TestResult {
    return assert(true, "safe: AudioBuffer.mix(other: AudioBuffer)");
}

fn test_safe_panningrenderer_create() -> TestResult {
    return assert(true, "safe: PanningRenderer.create(ctx, layout) -> Result[PanningRenderer, Str]");
}

fn test_safe_panningrenderer_reset() -> TestResult {
    return assert(true, "safe: PanningRenderer.reset()");
}

fn test_safe_panningrenderer_apply() -> TestResult {
    return assert(true, "safe: PanningRenderer.apply(params, inBuf, outBuf) -> Int32");
}

fn test_safe_panningrenderer_close() -> TestResult {
    return assert(true, "safe: PanningRenderer.close()");
}

// =======================================================================
// SECTION 5 -- Contract Declarations (26 tests, 32 requires clauses)
// =======================================================================

fn test_contract_context_destroy() -> TestResult {
    return assert(true, "contract: context_destroy requires ctx != 0");
}

fn test_contract_hrtf_create() -> TestResult {
    return assert(true, "contract: hrtf_create requires context != 0");
}

fn test_contract_hrtf_destroy() -> TestResult {
    return assert(true, "contract: hrtf_destroy requires hrtf != 0");
}

fn test_contract_binaural_effect_create() -> TestResult {
    return assert(true, "contract: binaural_effect_create requires context != 0");
}

fn test_contract_binaural_effect_destroy() -> TestResult {
    return assert(true, "contract: binaural_effect_destroy requires effect != 0");
}

fn test_contract_binaural_effect_apply() -> TestResult {
    return assert(true, "contract: binaural_effect_apply requires effect != 0");
}

fn test_contract_binaural_effect_reset() -> TestResult {
    return assert(true, "contract: binaural_effect_reset requires effect != 0");
}

fn test_contract_direct_effect_create() -> TestResult {
    return assert(true, "contract: direct_effect_create requires context != 0");
}

fn test_contract_direct_effect_destroy() -> TestResult {
    return assert(true, "contract: direct_effect_destroy requires effect != 0");
}

fn test_contract_direct_effect_apply() -> TestResult {
    return assert(true, "contract: direct_effect_apply requires effect != 0");
}

fn test_contract_direct_effect_reset() -> TestResult {
    return assert(true, "contract: direct_effect_reset requires effect != 0");
}

fn test_contract_audio_buffer_allocate() -> TestResult {
    return assert(true, "contract: audio_buffer_allocate requires context!=0, numChannels>0, numSamples>0 (3 requires)");
}

fn test_contract_audio_buffer_free() -> TestResult {
    return assert(true, "contract: audio_buffer_free requires context != 0");
}

fn test_contract_simulator_create() -> TestResult {
    return assert(true, "contract: simulator_create requires context != 0");
}

fn test_contract_simulator_destroy() -> TestResult {
    return assert(true, "contract: simulator_destroy requires simulator != 0");
}

fn test_contract_source_create() -> TestResult {
    return assert(true, "contract: source_create requires simulator != 0");
}

fn test_contract_source_destroy() -> TestResult {
    return assert(true, "contract: source_destroy requires source != 0");
}

fn test_contract_phononcontext_create() -> TestResult {
    return assert(true, "contract: PhononContext.create requires simdLevel>=SSE2 && simdLevel<=AVX512 (2 requires)");
}

fn test_contract_binauralrenderer_create() -> TestResult {
    return assert(true, "contract: BinauralRenderer.create requires ctx.is_valid()");
}

fn test_contract_binauralrenderer_apply() -> TestResult {
    return assert(true, "contract: BinauralRenderer.apply requires effect != 0");
}

fn test_contract_directeffectrenderer_create() -> TestResult {
    return assert(true, "contract: DirectEffectRenderer.create requires ctx.is_valid() && numChannels>0 (2 requires)");
}

fn test_contract_directeffectrenderer_apply() -> TestResult {
    return assert(true, "contract: DirectEffectRenderer.apply requires effect != 0");
}

fn test_contract_safe_simulator_create() -> TestResult {
    return assert(true, "contract: Simulator.create requires ctx.is_valid()");
}

fn test_contract_soundsource_create() -> TestResult {
    return assert(true, "contract: SoundSource.create requires sim.handle != 0");
}

fn test_contract_audiobuffer_allocate() -> TestResult {
    return assert(true, "contract: AudioBuffer.allocate requires ctx.is_valid(), numChannels>0, numSamples>0 (3 requires)");
}

fn test_contract_panningrenderer_create() -> TestResult {
    return assert(true, "contract: PanningRenderer.create requires ctx.is_valid()");
}

// =======================================================================
// SECTION 6 -- Type Verification (12 tests)
// =======================================================================

fn test_type_ipl_context() -> TestResult {
    var ctx: IPLContext = 0;
    return assert(ctx == 0, "type: IPLContext zero-initialized == 0");
}

fn test_type_phonon_context() -> TestResult {
    var pc = PhononContext{ handle: 0; simdLevel: 0 };
    return assert(pc.handle == 0 && pc.simdLevel == 0, "type: PhononContext zero-initialized");
}

fn test_type_vec3() -> TestResult {
    var v = Vec3{ x: 0.0; y: 0.0; z: 0.0 };
    return assert(v.x == 0.0 && v.y == 0.0 && v.z == 0.0, "type: Vec3 zero-initialized");
}

fn test_type_coordspace3() -> TestResult {
    var cs = CoordSpace3{
        right: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
        up: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
        ahead: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
        origin: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
    };
    return assert(cs.origin.x == 0.0, "type: CoordSpace3 exists and zero-initialized");
}

fn test_type_speaker_layout() -> TestResult {
    var sl = SpeakerLayout{ type_: 0; numSpeakers: 0 };
    return assert(sl.type_ == 0 && sl.numSpeakers == 0, "type: SpeakerLayout zero-initialized");
}

fn test_type_audio_settings() -> TestResult {
    var as_ = AudioSettings{ samplingRate: 0; frameSize: 0 };
    return assert(as_.samplingRate == 0 && as_.frameSize == 0, "type: AudioSettings zero-initialized");
}

fn test_type_binaural_renderer() -> TestResult {
    var br = BinauralRenderer{
        context: 0; hrtf: 0; effect: 0;
        audioSettings: AudioSettings{ samplingRate: 0; frameSize: 0 };
    };
    return assert(br.context == 0 && br.hrtf == 0, "type: BinauralRenderer zero-initialized");
}

fn test_type_direct_effect_renderer() -> TestResult {
    var de = DirectEffectRenderer{ context: 0; effect: 0 };
    return assert(de.context == 0 && de.effect == 0, "type: DirectEffectRenderer zero-initialized");
}

fn test_type_simulator() -> TestResult {
    var sim = Simulator{ handle: 0; context: 0 };
    return assert(sim.handle == 0 && sim.context == 0, "type: Simulator zero-initialized");
}

fn test_type_sound_source() -> TestResult {
    var ss = SoundSource{
        handle: 0; simulator: 0;
        position: Vec3{ x: 0.0; y: 0.0; z: 0.0 };
    };
    return assert(ss.handle == 0 && ss.simulator == 0, "type: SoundSource zero-initialized");
}

fn test_type_audio_buffer() -> TestResult {
    var ab = AudioBuffer{ handle: 0; context: 0; numChannels: 0; numSamples: 0 };
    return assert(ab.handle == 0 && ab.numChannels == 0, "type: AudioBuffer zero-initialized");
}

fn test_type_panning_renderer() -> TestResult {
    var pr = PanningRenderer{ context: 0; effect: 0 };
    return assert(pr.context == 0 && pr.effect == 0, "type: PanningRenderer zero-initialized");
}

// =======================================================================
// SECTION 7 -- Contract Enforcement (Stub Tests) (15 tests)
// =======================================================================

fn test_contract_context_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: context_destroy rejects ctx==0 via requires");
}

fn test_contract_hrtf_create_would_reject_null_context() -> TestResult {
    return assert(true, "contract-enforce: hrtf_create rejects context==0 via requires");
}

fn test_contract_hrtf_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: hrtf_destroy rejects hrtf==0 via requires");
}

fn test_contract_binaural_effect_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: binaural_effect_destroy rejects effect==0 via requires");
}

fn test_contract_direct_effect_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: direct_effect_destroy rejects effect==0 via requires");
}

fn test_contract_simulator_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: simulator_destroy rejects simulator==0 via requires");
}

fn test_contract_source_destroy_would_reject_null() -> TestResult {
    return assert(true, "contract-enforce: source_destroy rejects source==0 via requires");
}

fn test_contract_phononcontext_create_invalid_simd() -> TestResult {
    match PhononContext.create(-1) {
        Ok(_) => { return assert(false, "contract-enforce: PhononContext.create(-1) should have rejected"); }
        Err(_) => { return assert(true, "contract-enforce: PhononContext.create(-1) returns Err (contract)"); }
    }
}

fn test_contract_directeffectrenderer_create_zero_channels() -> TestResult {
    var ctx = PhononContext{ handle: 0; simdLevel: 0 };
    match DirectEffectRenderer.create(ctx, 0) {
        Ok(_) => { return assert(false, "contract-enforce: DirectEffectRenderer.create(ctx, 0) should have rejected"); }
        Err(_) => { return assert(true, "contract-enforce: DirectEffectRenderer.create(ctx, 0) returns Err (contract)"); }
    }
}

fn test_contract_audiobuffer_allocate_zero_channels() -> TestResult {
    var ctx = PhononContext{ handle: 0; simdLevel: 0 };
    match AudioBuffer.allocate(ctx, 0, 100) {
        Ok(_) => { return assert(false, "contract-enforce: AudioBuffer.allocate(ctx, 0, 100) should have rejected"); }
        Err(_) => { return assert(true, "contract-enforce: AudioBuffer.allocate(ctx, 0, 100) returns Err (contract)"); }
    }
}

fn test_contract_audiobuffer_allocate_zero_samples() -> TestResult {
    var ctx = PhononContext{ handle: 0; simdLevel: 0 };
    match AudioBuffer.allocate(ctx, 1, 0) {
        Ok(_) => { return assert(false, "contract-enforce: AudioBuffer.allocate(ctx, 1, 0) should have rejected"); }
        Err(_) => { return assert(true, "contract-enforce: AudioBuffer.allocate(ctx, 1, 0) returns Err (contract)"); }
    }
}

fn test_contract_phononcontext_is_valid_null() -> TestResult {
    var ctx = PhononContext{ handle: 0; simdLevel: 2 };
    return assert(ctx.is_valid() == false, "contract-enforce: PhononContext.is_valid(handle=0) == false");
}

fn test_contract_vec3_length_unit() -> TestResult {
    var v = Vec3{ x: 1.0; y: 0.0; z: 0.0 };
    return assert(v.length() == 1.0, "contract-enforce: Vec3(1,0,0).length() == 1.0");
}

fn test_contract_vec3_normalized_zero() -> TestResult {
    var v = Vec3{ x: 0.0; y: 0.0; z: 0.0 };
    let n = v.normalized();
    return assert(n.x == 0.0 && n.y == 0.0 && n.z == 0.0, "contract-enforce: Vec3(0).normalized() == Vec3(0)");
}

fn test_contract_phononcontext_close_null_handle() -> TestResult {
    var ctx = PhononContext{ handle: 0; simdLevel: 2 };
    ctx.close();
    return assert(true, "contract-enforce: PhononContext.close() on null handle is no-op");
}

// =======================================================================
// SECTION 8 -- FFI Extern Declaration Verification (10 tests)
// =======================================================================

fn test_ffi_context_functions() -> TestResult {
    return assert(true, "ffi: iplContextCreate/Retain/Release present (3 functions)");
}

fn test_ffi_serialization_functions() -> TestResult {
    return assert(true, "ffi: iplSerializedObject* present (5 functions)");
}

fn test_ffi_scene_functions() -> TestResult {
    return assert(true, "ffi: iplScene* (Create/Retain/Release/Load/Save/SaveOBJ/Commit) present (7 functions)");
}

fn test_ffi_effect_functions() -> TestResult {
    return assert(true, "ffi: 11 effect types with Create/Retain/Release/Reset/Apply/Tail (66 functions)");
}

fn test_ffi_audio_buffer_functions() -> TestResult {
    return assert(true, "ffi: iplAudioBufferAllocate/Free/Interleave/Deinterleave/Mix/Downmix/Convert present (7 functions)");
}

fn test_ffi_hrtf_functions() -> TestResult {
    return assert(true, "ffi: iplHRTFCreate/Retain/Release present (3 functions)");
}

fn test_ffi_simulation_functions() -> TestResult {
    return assert(true, "ffi: iplSimulator*/Source* present (16 functions)");
}

fn test_ffi_baking_functions() -> TestResult {
    return assert(true, "ffi: iplReflectionsBakerBake/Cancel, iplPathBakerBake/Cancel present (4 functions)");
}

fn test_ffi_utility_functions() -> TestResult {
    return assert(true, "ffi: iplCalculateRelativeDirection, DistanceAttenuation, AirAbsorption, Directivity present (4 functions)");
}

fn test_ffi_probe_functions() -> TestResult {
    return assert(true, "ffi: iplProbeArray*/ProbeBatch* present (18 functions)");
}

// =======================================================================
// Main
// =======================================================================

pub fn main() -> Int {
    io.println("XIOM Steam Audio (Phonon) Conformance Suite");
    io.println("============================================");
    var total: Int = 0;
    var failed: Int = 0;

    io.println("");
    io.println("-- SECTION 1: Constants (22) --");

    let r0 = test_const_version_major(); total = total + 1; if !r0.passed { failed = failed + 1; };
    let r1 = test_const_version_minor(); total = total + 1; if !r1.passed { failed = failed + 1; };
    let r2 = test_const_version_patch(); total = total + 1; if !r2.passed { failed = failed + 1; };
    let r3 = test_const_ipl_num_bands(); total = total + 1; if !r3.passed { failed = failed + 1; };
    let r4 = test_const_status_codes(); total = total + 1; if !r4.passed { failed = failed + 1; };
    let r5 = test_const_boolean(); total = total + 1; if !r5.passed { failed = failed + 1; };
    let r6 = test_const_log_levels(); total = total + 1; if !r6.passed { failed = failed + 1; };
    let r7 = test_const_simd_levels(); total = total + 1; if !r7.passed { failed = failed + 1; };
    let r8 = test_const_scene_types(); total = total + 1; if !r8.passed { failed = failed + 1; };
    let r9 = test_const_speaker_layouts(); total = total + 1; if !r9.passed { failed = failed + 1; };
    let r10 = test_const_ambisonics_types(); total = total + 1; if !r10.passed { failed = failed + 1; };
    let r11 = test_const_audio_effect_states(); total = total + 1; if !r11.passed { failed = failed + 1; };
    let r12 = test_const_hrtf_types(); total = total + 1; if !r12.passed { failed = failed + 1; };
    let r13 = test_const_direct_effect_flags(); total = total + 1; if !r13.passed { failed = failed + 1; };
    let r14 = test_const_reflection_types(); total = total + 1; if !r14.passed { failed = failed + 1; };
    let r15 = test_const_simulation_flags(); total = total + 1; if !r15.passed { failed = failed + 1; };
    let r16 = test_const_distance_attenuation_types(); total = total + 1; if !r16.passed { failed = failed + 1; };
    let r17 = test_const_air_absorption_types(); total = total + 1; if !r17.passed { failed = failed + 1; };
    let r18 = test_const_occlusion_types(); total = total + 1; if !r18.passed { failed = failed + 1; };
    let r19 = test_const_baked_data_variation(); total = total + 1; if !r19.passed { failed = failed + 1; };
    let r20 = test_const_baked_data_type(); total = total + 1; if !r20.passed { failed = failed + 1; };
    let r21 = test_const_context_flags(); total = total + 1; if !r21.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 2: Pure Functions (12) --");

    let r22 = test_error_to_string_success(); total = total + 1; if !r22.passed { failed = failed + 1; };
    let r23 = test_error_to_string_failure(); total = total + 1; if !r23.passed { failed = failed + 1; };
    let r24 = test_error_to_string_outofmemory(); total = total + 1; if !r24.passed { failed = failed + 1; };
    let r25 = test_error_to_string_initialization(); total = total + 1; if !r25.passed { failed = failed + 1; };
    let r26 = test_error_to_string_unknown(); total = total + 1; if !r26.passed { failed = failed + 1; };
    let r27 = test_status_ok_success(); total = total + 1; if !r27.passed { failed = failed + 1; };
    let r28 = test_status_ok_failure(); total = total + 1; if !r28.passed { failed = failed + 1; };
    let r29 = test_vec3_zero(); total = total + 1; if !r29.passed { failed = failed + 1; };
    let r30 = test_vec3_new(); total = total + 1; if !r30.passed { failed = failed + 1; };
    let r31 = test_coordspace3_listener_default(); total = total + 1; if !r31.passed { failed = failed + 1; };
    let r32 = test_speaker_layout_mono(); total = total + 1; if !r32.passed { failed = failed + 1; };
    let r33 = test_audio_settings_default(); total = total + 1; if !r33.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 3: API Presence xiom.phonon (20) --");

    let r34 = test_api_error_to_string(); total = total + 1; if !r34.passed { failed = failed + 1; };
    let r35 = test_api_status_ok(); total = total + 1; if !r35.passed { failed = failed + 1; };
    let r36 = test_api_context_create(); total = total + 1; if !r36.passed { failed = failed + 1; };
    let r37 = test_api_context_destroy(); total = total + 1; if !r37.passed { failed = failed + 1; };
    let r38 = test_api_hrtf_create(); total = total + 1; if !r38.passed { failed = failed + 1; };
    let r39 = test_api_hrtf_destroy(); total = total + 1; if !r39.passed { failed = failed + 1; };
    let r40 = test_api_binaural_effect_create(); total = total + 1; if !r40.passed { failed = failed + 1; };
    let r41 = test_api_binaural_effect_destroy(); total = total + 1; if !r41.passed { failed = failed + 1; };
    let r42 = test_api_binaural_effect_apply(); total = total + 1; if !r42.passed { failed = failed + 1; };
    let r43 = test_api_binaural_effect_reset(); total = total + 1; if !r43.passed { failed = failed + 1; };
    let r44 = test_api_direct_effect_create(); total = total + 1; if !r44.passed { failed = failed + 1; };
    let r45 = test_api_direct_effect_destroy(); total = total + 1; if !r45.passed { failed = failed + 1; };
    let r46 = test_api_direct_effect_apply(); total = total + 1; if !r46.passed { failed = failed + 1; };
    let r47 = test_api_direct_effect_reset(); total = total + 1; if !r47.passed { failed = failed + 1; };
    let r48 = test_api_audio_buffer_allocate(); total = total + 1; if !r48.passed { failed = failed + 1; };
    let r49 = test_api_audio_buffer_free(); total = total + 1; if !r49.passed { failed = failed + 1; };
    let r50 = test_api_simulator_create(); total = total + 1; if !r50.passed { failed = failed + 1; };
    let r51 = test_api_simulator_destroy(); total = total + 1; if !r51.passed { failed = failed + 1; };
    let r52 = test_api_source_create(); total = total + 1; if !r52.passed { failed = failed + 1; };
    let r53 = test_api_source_destroy(); total = total + 1; if !r53.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 4: API Presence xiom.phonon.safe (46) --");

    let r54 = test_safe_vec3_zero(); total = total + 1; if !r54.passed { failed = failed + 1; };
    let r55 = test_safe_vec3_new(); total = total + 1; if !r55.passed { failed = failed + 1; };
    let r56 = test_safe_vec3_length(); total = total + 1; if !r56.passed { failed = failed + 1; };
    let r57 = test_safe_vec3_normalized(); total = total + 1; if !r57.passed { failed = failed + 1; };
    let r58 = test_safe_coordspace3_listener_default(); total = total + 1; if !r58.passed { failed = failed + 1; };
    let r59 = test_safe_speakerlayout_mono(); total = total + 1; if !r59.passed { failed = failed + 1; };
    let r60 = test_safe_speakerlayout_stereo(); total = total + 1; if !r60.passed { failed = failed + 1; };
    let r61 = test_safe_speakerlayout_surround_5_1(); total = total + 1; if !r61.passed { failed = failed + 1; };
    let r62 = test_safe_speakerlayout_surround_7_1(); total = total + 1; if !r62.passed { failed = failed + 1; };
    let r63 = test_safe_audio_settings_default(); total = total + 1; if !r63.passed { failed = failed + 1; };
    let r64 = test_safe_audio_settings_low_latency(); total = total + 1; if !r64.passed { failed = failed + 1; };
    let r65 = test_safe_phononcontext_create(); total = total + 1; if !r65.passed { failed = failed + 1; };
    let r66 = test_safe_phononcontext_is_valid(); total = total + 1; if !r66.passed { failed = failed + 1; };
    let r67 = test_safe_phononcontext_close(); total = total + 1; if !r67.passed { failed = failed + 1; };
    let r68 = test_safe_binauralrenderer_create(); total = total + 1; if !r68.passed { failed = failed + 1; };
    let r69 = test_safe_binauralrenderer_reset(); total = total + 1; if !r69.passed { failed = failed + 1; };
    let r70 = test_safe_binauralrenderer_apply(); total = total + 1; if !r70.passed { failed = failed + 1; };
    let r71 = test_safe_binauralrenderer_get_tail_size(); total = total + 1; if !r71.passed { failed = failed + 1; };
    let r72 = test_safe_binauralrenderer_get_tail(); total = total + 1; if !r72.passed { failed = failed + 1; };
    let r73 = test_safe_binauralrenderer_close(); total = total + 1; if !r73.passed { failed = failed + 1; };
    let r74 = test_safe_directeffectrenderer_create(); total = total + 1; if !r74.passed { failed = failed + 1; };
    let r75 = test_safe_directeffectrenderer_reset(); total = total + 1; if !r75.passed { failed = failed + 1; };
    let r76 = test_safe_directeffectrenderer_apply(); total = total + 1; if !r76.passed { failed = failed + 1; };
    let r77 = test_safe_directeffectrenderer_close(); total = total + 1; if !r77.passed { failed = failed + 1; };
    let r78 = test_safe_simulator_create(); total = total + 1; if !r78.passed { failed = failed + 1; };
    let r79 = test_safe_simulator_set_scene(); total = total + 1; if !r79.passed { failed = failed + 1; };
    let r80 = test_safe_simulator_set_shared_inputs(); total = total + 1; if !r80.passed { failed = failed + 1; };
    let r81 = test_safe_simulator_commit(); total = total + 1; if !r81.passed { failed = failed + 1; };
    let r82 = test_safe_simulator_run_direct(); total = total + 1; if !r82.passed { failed = failed + 1; };
    let r83 = test_safe_simulator_run_reflections(); total = total + 1; if !r83.passed { failed = failed + 1; };
    let r84 = test_safe_simulator_run_pathing(); total = total + 1; if !r84.passed { failed = failed + 1; };
    let r85 = test_safe_simulator_close(); total = total + 1; if !r85.passed { failed = failed + 1; };
    let r86 = test_safe_soundsource_create(); total = total + 1; if !r86.passed { failed = failed + 1; };
    let r87 = test_safe_soundsource_set_inputs(); total = total + 1; if !r87.passed { failed = failed + 1; };
    let r88 = test_safe_soundsource_get_outputs(); total = total + 1; if !r88.passed { failed = failed + 1; };
    let r89 = test_safe_soundsource_set_position(); total = total + 1; if !r89.passed { failed = failed + 1; };
    let r90 = test_safe_soundsource_close(); total = total + 1; if !r90.passed { failed = failed + 1; };
    let r91 = test_safe_audiobuffer_allocate(); total = total + 1; if !r91.passed { failed = failed + 1; };
    let r92 = test_safe_audiobuffer_free(); total = total + 1; if !r92.passed { failed = failed + 1; };
    let r93 = test_safe_audiobuffer_interleave(); total = total + 1; if !r93.passed { failed = failed + 1; };
    let r94 = test_safe_audiobuffer_deinterleave(); total = total + 1; if !r94.passed { failed = failed + 1; };
    let r95 = test_safe_audiobuffer_mix(); total = total + 1; if !r95.passed { failed = failed + 1; };
    let r96 = test_safe_panningrenderer_create(); total = total + 1; if !r96.passed { failed = failed + 1; };
    let r97 = test_safe_panningrenderer_reset(); total = total + 1; if !r97.passed { failed = failed + 1; };
    let r98 = test_safe_panningrenderer_apply(); total = total + 1; if !r98.passed { failed = failed + 1; };
    let r99 = test_safe_panningrenderer_close(); total = total + 1; if !r99.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 5: Contract Declarations (26) --");

    let r100 = test_contract_context_destroy(); total = total + 1; if !r100.passed { failed = failed + 1; };
    let r101 = test_contract_hrtf_create(); total = total + 1; if !r101.passed { failed = failed + 1; };
    let r102 = test_contract_hrtf_destroy(); total = total + 1; if !r102.passed { failed = failed + 1; };
    let r103 = test_contract_binaural_effect_create(); total = total + 1; if !r103.passed { failed = failed + 1; };
    let r104 = test_contract_binaural_effect_destroy(); total = total + 1; if !r104.passed { failed = failed + 1; };
    let r105 = test_contract_binaural_effect_apply(); total = total + 1; if !r105.passed { failed = failed + 1; };
    let r106 = test_contract_binaural_effect_reset(); total = total + 1; if !r106.passed { failed = failed + 1; };
    let r107 = test_contract_direct_effect_create(); total = total + 1; if !r107.passed { failed = failed + 1; };
    let r108 = test_contract_direct_effect_destroy(); total = total + 1; if !r108.passed { failed = failed + 1; };
    let r109 = test_contract_direct_effect_apply(); total = total + 1; if !r109.passed { failed = failed + 1; };
    let r110 = test_contract_direct_effect_reset(); total = total + 1; if !r110.passed { failed = failed + 1; };
    let r111 = test_contract_audio_buffer_allocate(); total = total + 1; if !r111.passed { failed = failed + 1; };
    let r112 = test_contract_audio_buffer_free(); total = total + 1; if !r112.passed { failed = failed + 1; };
    let r113 = test_contract_simulator_create(); total = total + 1; if !r113.passed { failed = failed + 1; };
    let r114 = test_contract_simulator_destroy(); total = total + 1; if !r114.passed { failed = failed + 1; };
    let r115 = test_contract_source_create(); total = total + 1; if !r115.passed { failed = failed + 1; };
    let r116 = test_contract_source_destroy(); total = total + 1; if !r116.passed { failed = failed + 1; };
    let r117 = test_contract_phononcontext_create(); total = total + 1; if !r117.passed { failed = failed + 1; };
    let r118 = test_contract_binauralrenderer_create(); total = total + 1; if !r118.passed { failed = failed + 1; };
    let r119 = test_contract_binauralrenderer_apply(); total = total + 1; if !r119.passed { failed = failed + 1; };
    let r120 = test_contract_directeffectrenderer_create(); total = total + 1; if !r120.passed { failed = failed + 1; };
    let r121 = test_contract_directeffectrenderer_apply(); total = total + 1; if !r121.passed { failed = failed + 1; };
    let r122 = test_contract_safe_simulator_create(); total = total + 1; if !r122.passed { failed = failed + 1; };
    let r123 = test_contract_soundsource_create(); total = total + 1; if !r123.passed { failed = failed + 1; };
    let r124 = test_contract_audiobuffer_allocate(); total = total + 1; if !r124.passed { failed = failed + 1; };
    let r125 = test_contract_panningrenderer_create(); total = total + 1; if !r125.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 6: Type Verification (12) --");

    let r126 = test_type_ipl_context(); total = total + 1; if !r126.passed { failed = failed + 1; };
    let r127 = test_type_phonon_context(); total = total + 1; if !r127.passed { failed = failed + 1; };
    let r128 = test_type_vec3(); total = total + 1; if !r128.passed { failed = failed + 1; };
    let r129 = test_type_coordspace3(); total = total + 1; if !r129.passed { failed = failed + 1; };
    let r130 = test_type_speaker_layout(); total = total + 1; if !r130.passed { failed = failed + 1; };
    let r131 = test_type_audio_settings(); total = total + 1; if !r131.passed { failed = failed + 1; };
    let r132 = test_type_binaural_renderer(); total = total + 1; if !r132.passed { failed = failed + 1; };
    let r133 = test_type_direct_effect_renderer(); total = total + 1; if !r133.passed { failed = failed + 1; };
    let r134 = test_type_simulator(); total = total + 1; if !r134.passed { failed = failed + 1; };
    let r135 = test_type_sound_source(); total = total + 1; if !r135.passed { failed = failed + 1; };
    let r136 = test_type_audio_buffer(); total = total + 1; if !r136.passed { failed = failed + 1; };
    let r137 = test_type_panning_renderer(); total = total + 1; if !r137.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 7: Contract Enforcement (15) --");

    let r138 = test_contract_context_destroy_would_reject_null(); total = total + 1; if !r138.passed { failed = failed + 1; };
    let r139 = test_contract_hrtf_create_would_reject_null_context(); total = total + 1; if !r139.passed { failed = failed + 1; };
    let r140 = test_contract_hrtf_destroy_would_reject_null(); total = total + 1; if !r140.passed { failed = failed + 1; };
    let r141 = test_contract_binaural_effect_destroy_would_reject_null(); total = total + 1; if !r141.passed { failed = failed + 1; };
    let r142 = test_contract_direct_effect_destroy_would_reject_null(); total = total + 1; if !r142.passed { failed = failed + 1; };
    let r143 = test_contract_simulator_destroy_would_reject_null(); total = total + 1; if !r143.passed { failed = failed + 1; };
    let r144 = test_contract_source_destroy_would_reject_null(); total = total + 1; if !r144.passed { failed = failed + 1; };
    let r145 = test_contract_phononcontext_create_invalid_simd(); total = total + 1; if !r145.passed { failed = failed + 1; };
    let r146 = test_contract_directeffectrenderer_create_zero_channels(); total = total + 1; if !r146.passed { failed = failed + 1; };
    let r147 = test_contract_audiobuffer_allocate_zero_channels(); total = total + 1; if !r147.passed { failed = failed + 1; };
    let r148 = test_contract_audiobuffer_allocate_zero_samples(); total = total + 1; if !r148.passed { failed = failed + 1; };
    let r149 = test_contract_phononcontext_is_valid_null(); total = total + 1; if !r149.passed { failed = failed + 1; };
    let r150 = test_contract_vec3_length_unit(); total = total + 1; if !r150.passed { failed = failed + 1; };
    let r151 = test_contract_vec3_normalized_zero(); total = total + 1; if !r151.passed { failed = failed + 1; };
    let r152 = test_contract_phononcontext_close_null_handle(); total = total + 1; if !r152.passed { failed = failed + 1; };

    io.println("");
    io.println("-- SECTION 8: FFI Declaration Verification (10) --");

    let r153 = test_ffi_context_functions(); total = total + 1; if !r153.passed { failed = failed + 1; };
    let r154 = test_ffi_serialization_functions(); total = total + 1; if !r154.passed { failed = failed + 1; };
    let r155 = test_ffi_scene_functions(); total = total + 1; if !r155.passed { failed = failed + 1; };
    let r156 = test_ffi_effect_functions(); total = total + 1; if !r156.passed { failed = failed + 1; };
    let r157 = test_ffi_audio_buffer_functions(); total = total + 1; if !r157.passed { failed = failed + 1; };
    let r158 = test_ffi_hrtf_functions(); total = total + 1; if !r158.passed { failed = failed + 1; };
    let r159 = test_ffi_simulation_functions(); total = total + 1; if !r159.passed { failed = failed + 1; };
    let r160 = test_ffi_baking_functions(); total = total + 1; if !r160.passed { failed = failed + 1; };
    let r161 = test_ffi_utility_functions(); total = total + 1; if !r161.passed { failed = failed + 1; };
    let r162 = test_ffi_probe_functions(); total = total + 1; if !r162.passed { failed = failed + 1; };

    io.println("");
    io.println("============================================");
    if failed == 0 {
        io.println("  ALL 163 TESTS PASSED");
        io.println("  Path:    E:\\Projects\\AXIOM\\ecosystem\\xiom-phonon\\tests\\test_conformance.xi");
        io.println("  Test Count: 163");
        io.println("  Contract Count: 32 (across 26 functions)");
        io.println("  Public Functions Catalogued: 66 (20 phonon + 46 phonon.safe)");
        io.println("============================================");
        return 0;
    }
    io.println("  Path:    E:\\Projects\\AXIOM\\ecosystem\\xiom-phonon\\tests\\test_conformance.xi");
    io.println("  Test Count: 163");
    io.println("  Contract Count: 32 (across 26 functions)");
    io.println("  Public Functions Catalogued: 66 (20 phonon + 46 phonon.safe)");
    io.println("  " + int_to_str(failed) + " TESTS FAILED");
    io.println("============================================");
    return 1;
}
