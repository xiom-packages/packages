#include <stdio.h>
#include <stddef.h>
#include "phonon.h"
#define P(s) printf("%s %zu\n", #s, sizeof(s))
#define O(s,f) printf("%s.%s %zu\n", #s, #f, offsetof(s,f))
int main(void) {
  P(IPLContextSettings); O(IPLContextSettings, version); O(IPLContextSettings, simdLevel); O(IPLContextSettings, flags);
  P(IPLHRTFSettings); O(IPLHRTFSettings, type); O(IPLHRTFSettings, sofaFileName); O(IPLHRTFSettings, sofaData); O(IPLHRTFSettings, sofaDataSize); O(IPLHRTFSettings, volume); O(IPLHRTFSettings, normType);
  P(IPLAudioSettings); O(IPLAudioSettings, samplingRate); O(IPLAudioSettings, frameSize);
  P(IPLAudioBuffer); O(IPLAudioBuffer, numChannels); O(IPLAudioBuffer, numSamples); O(IPLAudioBuffer, data);
  P(IPLSpeakerLayout); O(IPLSpeakerLayout, type); O(IPLSpeakerLayout, numSpeakers); O(IPLSpeakerLayout, speakers);
  P(IPLVector3); P(IPLCoordinateSpace3);
  P(IPLPanningEffectSettings); P(IPLPanningEffectParams); O(IPLPanningEffectParams, direction);
  P(IPLBinauralEffectSettings); P(IPLBinauralEffectParams); O(IPLBinauralEffectParams, direction); O(IPLBinauralEffectParams, interpolation); O(IPLBinauralEffectParams, spatialBlend); O(IPLBinauralEffectParams, hrtf); O(IPLBinauralEffectParams, peakDelays);
  P(IPLVirtualSurroundEffectSettings); P(IPLVirtualSurroundEffectParams);
  P(IPLAmbisonicsEncodeEffectSettings); P(IPLAmbisonicsEncodeEffectParams); O(IPLAmbisonicsEncodeEffectParams, direction); O(IPLAmbisonicsEncodeEffectParams, order);
  P(IPLAmbisonicsPanningEffectSettings); P(IPLAmbisonicsPanningEffectParams);
  P(IPLAmbisonicsBinauralEffectSettings); P(IPLAmbisonicsBinauralEffectParams);
  P(IPLAmbisonicsRotationEffectSettings); P(IPLAmbisonicsRotationEffectParams); O(IPLAmbisonicsRotationEffectParams, orientation); O(IPLAmbisonicsRotationEffectParams, order);
  P(IPLAmbisonicsDecodeEffectSettings); P(IPLAmbisonicsDecodeEffectParams); O(IPLAmbisonicsDecodeEffectParams, order); O(IPLAmbisonicsDecodeEffectParams, hrtf); O(IPLAmbisonicsDecodeEffectParams, orientation); O(IPLAmbisonicsDecodeEffectParams, binaural);
  P(IPLDirectEffectSettings); P(IPLDirectEffectParams); O(IPLDirectEffectParams, flags); O(IPLDirectEffectParams, transmissionType); O(IPLDirectEffectParams, distanceAttenuation); O(IPLDirectEffectParams, airAbsorption); O(IPLDirectEffectParams, directivity); O(IPLDirectEffectParams, occlusion); O(IPLDirectEffectParams, transmission);
  P(IPLPathEffectSettings); P(IPLPathEffectParams); O(IPLPathEffectParams, eqCoeffs); O(IPLPathEffectParams, shCoeffs); O(IPLPathEffectParams, order); O(IPLPathEffectParams, binaural); O(IPLPathEffectParams, hrtf); O(IPLPathEffectParams, listener); O(IPLPathEffectParams, normalizeEQ);
  return 0;
}
