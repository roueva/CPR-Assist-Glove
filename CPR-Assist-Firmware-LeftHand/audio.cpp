// =============================================================================
// audio.cpp — DFPlayer Mini driver
// Communication: UART2 (GPIO16 TX, GPIO17 RX), 9600 baud.
// DFPlayer command frame: 0x7E 0xFF 0x06 CMD 0x00 MSB LSB CHECKSUM 0xEF
// =============================================================================
#include "audio.h"
#include <Arduino.h>
#include <HardwareSerial.h>

static HardwareSerial _dfSerial(2);  // UART2
static bool _ok = false;
static bool _playing = false;
static uint8_t _curPriority = 0;
static uint8_t _volume = DFPLAYER_DEFAULT_VOLUME;
static unsigned long _trackStartMs = 0;
static uint32_t _trackTimeoutMs = 4000;

// ── DFPlayer frame builder ────────────────────────────────────────────────────
static void sendCmd(uint8_t cmd, uint8_t msb, uint8_t lsb) {
  uint8_t frame[10];
  frame[0] = 0x7E;
  frame[1] = 0xFF;
  frame[2] = 0x06;
  frame[3] = cmd;
  frame[4] = 0x00;  // no feedback
  frame[5] = msb;
  frame[6] = lsb;
  // Checksum: 0 - (FF + 06 + cmd + 00 + msb + lsb)
  int16_t cs = -(0xFF + 0x06 + cmd + 0x00 + msb + lsb);
  frame[7] = (cs >> 8) & 0xFF;
  frame[8] = cs & 0xFF;
  frame[9] = 0xEF;
  _dfSerial.write(frame, 10);
}

bool audioInit() {
  _dfSerial.begin(9600, SERIAL_8N1, PIN_DFPLAYER_RX, PIN_DFPLAYER_TX);
  delay(1000);  // DFPlayer needs ~1 s after power-up before accepting commands

  // Reset
  sendCmd(0x0C, 0x00, 0x00);
  delay(500);

  // Drain RX buffer (DFPlayer sends boot notification 0x7E 0xFF 0x06 0x3F ...)
  while (_dfSerial.available()) _dfSerial.read();

  // Select SD card source — command 0x09, parameter 0x02 = TF card
  sendCmd(0x09, 0x00, 0x02);
  delay(500);  // SD mount takes time

  // Set volume — command 0x06, range 0–30
  sendCmd(0x06, 0x00, _volume);
  delay(100);

  // EQ normal
  sendCmd(0x07, 0x00, 0x00);
  delay(100);

  // ── Presence detection ──────────────────────────────────────────────────
  // Query current status (0x42). A real DFPlayer with a mounted SD card
  // replies with a 0x7E 0xFF .. 0xEF frame. We accept ANY well-formed reply
  // frame (0x42 status, 0x3F online, or 0x40 error) as proof the module is
  // physically present and the UART link works. No reply at all = absent or
  // miswired → mark NOT ok so the self-test reports it honestly.
  while (_dfSerial.available()) _dfSerial.read();  // clear before query
  sendCmd(0x42, 0x00, 0x00);

  _ok = false;
  unsigned long _deadline = millis() + 400;  // DFPlayer replies within ~200ms
  while (millis() < _deadline) {
    if (_dfSerial.available() >= 2) {
      if (_dfSerial.read() == 0x7E) {
        if (_dfSerial.read() == 0xFF) {
          _ok = true;
          break;
        }
      }
    } else {
      delay(5);
    }
  }

  // Re-drain any trailing bytes of the reply frame so audioUpdate()'s
  // finish-frame parser starts clean.
  delay(20);
  while (_dfSerial.available()) _dfSerial.read();

  return _ok;
}

bool audioOk() {
  return _ok;
}

void audioSetVolume(uint8_t v) {
  if (v > 30) v = 30;
  _volume = v;
  if (!_ok) return;
  sendCmd(0x06, 0x00, _volume);
  delay(50);
}

uint8_t audioGetVolume() {
  return _volume;
}

void audioPlay(uint8_t track, uint8_t priority) {
  if (!_ok) return;
  if (_volume == 0) return;   // muted via slider — never start playback

  // Restore default timeout in case the previous cue was a click (which
  // shortened it to 250 ms).
  _trackTimeoutMs = 4000;

  // If something is playing at equal or higher priority, drop this cue
  if (_playing && priority <= _curPriority) return;

  // Stop current track if we're preempting
  if (_playing) sendCmd(0x16, 0x00, 0x00);

  // Play track (command 0x03 = play specific file number)
  sendCmd(0x12, 0x00, track);  // 0x12 = play track NNNN from /mp3/ folder
  _playing = true;
  _curPriority = priority;
  _trackStartMs = millis();
}

void audioClick() {
  if (!_ok) return;
  if (_volume == 0) return;   // muted via slider
  // If anything is playing, drop the click — voice cues have priority.
  if (_playing) return;
  // Direct play, no preempt logic, no priority bookkeeping for clicks.
  // We DO set _playing so a back-to-back click doesn't double-fire.
  sendCmd(0x12, 0x00, AUDIO_DEPTH_CLICK);
  _playing = true;
  _curPriority = AUDIO_PRI_CLICK;
  _trackStartMs = millis();
  // Short timeout: click is ≤ 100 ms, allow another 150 ms slack.
  _trackTimeoutMs = 250;
}

void audioStop() {
  sendCmd(0x16, 0x00, 0x00);
  _playing = false;
  _curPriority = 0;
}

void audioUpdate() {
  // Drain serial buffer — TD5580A responses are unreliable
  // but we still check for genuine 0x3D finish notification
  while (_dfSerial.available() > 0) {
    uint8_t b = _dfSerial.read();
    if (b == 0x7E) {
      uint8_t buf[9];
      int got = _dfSerial.readBytes(buf, 9);
      if (got == 9 && buf[2] == 0x3D) {
        _playing = false;
        _curPriority = 0;
        return;
      }
    }
  }

  // Time-based fallback — if 0x3D never comes, clear flag after timeout
  // This prevents the priority queue getting permanently stuck
  if (_playing && (millis() - _trackStartMs) >= _trackTimeoutMs) {
    _playing = false;
    _curPriority = 0;
  }
}
