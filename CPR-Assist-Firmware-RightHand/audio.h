#pragma once
#include <Arduino.h>
// =============================================================================
// audio.h — DFPlayer Mini audio driver with priority queue
// =============================================================================
#include "config.h"

bool audioInit();
bool audioOk();

// Play a track with priority. Higher priority preempts lower priority.
// If same or lower priority is playing, the new cue is dropped.
void audioPlay(uint8_t track, uint8_t priority);

// Direct click: plays AUDIO_DEPTH_CLICK with minimum latency. Skipped if any
// other cue is currently playing (don't preempt voice). Reentrant-safe.
void audioClick();

// Must be called periodically from comms task to check if playback finished
void audioUpdate();

void audioStop();

void audioSetVolume(uint8_t vol);  // 0–30
uint8_t audioGetVolume();
