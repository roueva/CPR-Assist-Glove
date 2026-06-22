// =============================================================================
// neopixel.cpp — WS2812B 8-LED strip driver
// Uses Adafruit_NeoPixel library.
// =============================================================================
#include "neopixel.h"
#include <Adafruit_NeoPixel.h>
#include <Arduino.h>

static Adafruit_NeoPixel _strip(NEO_NUM_LEDS, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);

static uint8_t _brightness = NEOPIXEL_DEFAULT_BRIGHTNESS;

// ── Color helpers ─────────────────────────────────────────────────────────────
static uint32_t rgb(uint8_t r, uint8_t g, uint8_t b) {
  return _strip.Color(r, g, b);
}
// Scale a color to a given brightness factor (0.0–1.0)
static uint32_t dimColor(uint32_t c, float factor) {
  uint8_t r = ((c >> 16) & 0xFF) * factor;
  uint8_t g = ((c >> 8) & 0xFF) * factor;
  uint8_t b = (c & 0xFF) * factor;
  return _strip.Color(r, g, b);
}

// ── Named colors (at max brightness NEO_MAX_BRIGHTNESS scale) ─────────────────
// Pre-scaled to NEO_MAX_BRIGHTNESS/255
static const float kBrightScale = (float)NEO_MAX_BRIGHTNESS / 255.0f;

static uint32_t COL_OFF() {
  return rgb(0, 0, 0);
}
static uint32_t COL_LIGHTBLUE() {
  return rgb(0 * kBrightScale, 180 * kBrightScale, 220 * kBrightScale);
}
static uint32_t COL_GREEN() {
  return rgb(0, NEO_MAX_BRIGHTNESS, 0);
}
static uint32_t COL_RED() {
  return rgb(NEO_MAX_BRIGHTNESS, 0, 0);
}
static uint32_t COL_ORANGE() {
  return rgb(NEO_MAX_BRIGHTNESS, 80 * kBrightScale, 0);
}
static uint32_t COL_WHITE() {
  return rgb(NEO_MAX_BRIGHTNESS, NEO_MAX_BRIGHTNESS, NEO_MAX_BRIGHTNESS);
}
static uint32_t COL_YELLOW() {
  return rgb(NEO_MAX_BRIGHTNESS, NEO_MAX_BRIGHTNESS, 0);
}
static uint32_t COL_BLUE() {
  return rgb(0, 0, NEO_MAX_BRIGHTNESS);
}
static uint32_t COL_EMERALD() {
  return rgb(0, 200 * kBrightScale, 80 * kBrightScale);
}  // app emergency green
static uint32_t COL_CYAN() {
  return rgb(0, NEO_MAX_BRIGHTNESS, NEO_MAX_BRIGHTNESS);
}

// ── Slow blink state ──────────────────────────────────────────────────────────
static unsigned long _lastBlinkMs = 0;
static bool _blinkState = false;

static bool blinkTick(uint32_t periodMs = 1000) {
  unsigned long now = millis();
  if (now - _lastBlinkMs >= periodMs / 2) {
    _lastBlinkMs = now;
    _blinkState = !_blinkState;
  }
  return _blinkState;
}

// ── Init ──────────────────────────────────────────────────────────────────────
void neoInit() {
  _strip.begin();
  _strip.setBrightness(_brightness);   // apply NEOPIXEL_DEFAULT_BRIGHTNESS at boot
  _strip.clear();
  _strip.show();
}

void neoSetBrightness(uint8_t brightness) {
  _brightness = brightness;
  _strip.setBrightness(brightness);
  _strip.show();
}

uint8_t neoGetBrightness() {
  return _brightness;
}

void neoDiagLedTest() {
  // Chase: red pass, green pass, blue pass, all white, all off
  const uint32_t colours[] = {
    _strip.Color(255, 0, 0), _strip.Color(0, 255, 0),
    _strip.Color(0, 0, 255), _strip.Color(255, 255, 255)
  };
  for (uint32_t c : colours) {
    for (int i = 0; i < _strip.numPixels(); i++) {
      _strip.clear();
      _strip.setPixelColor(i, c);
      _strip.show();
      delay(60);
    }
  }
  _strip.clear();
  _strip.show();
}

// ── Depth bar (LEDs 0–5) ──────────────────────────────────────────────────────
static void updateDepthBar(const SharedState& s) {
  float depthCm = s.depth;
  float force = s.force;
  bool session = s.sessionActive;
  Scenario sc = s.currentScenario;

  float minTarget = s.targetDepthMinMM / 10.0f;  // mm → cm
  float maxTarget = s.targetDepthMaxMM / 10.0f;

  // No session or no feedback: all off
  if (!session || !s.visualFeedbackEnabled) {
    for (int i = 0; i <= 5; i++) _strip.setPixelColor(i, COL_OFF());
    return;
  }

  // Residual pressure while released (leaning)
  if (!s.sessionActive || (depthCm < 0.1f && force > FORCE_LEANING_THRESHOLD)) {
    _strip.setPixelColor(0, COL_RED());
    for (int i = 1; i <= 5; i++) _strip.setPixelColor(i, COL_OFF());
    return;
  }

  // Full recoil — all off
  if (depthCm < 0.1f && !s.leaningDetected) {
    for (int i = 0; i <= 5; i++) _strip.setPixelColor(i, COL_OFF());
    return;
  }

  // Over target → all red
  if (depthCm > maxTarget) {
    for (int i = 0; i <= 5; i++) _strip.setPixelColor(i, COL_RED());
    return;
  }

  // At or above target → all green
  if (depthCm >= minTarget) {
    for (int i = 0; i <= 5; i++) _strip.setPixelColor(i, COL_GREEN());
    return;
  }

  // Below target: fill light blue proportionally (0 → minTarget maps to 0 → 6 LEDs)
  float fraction = depthCm / minTarget;  // 0.0–1.0
  float ledsLit = fraction * 6.0f;
  int fullLeds = (int)ledsLit;
  fullLeds = constrain(fullLeds, 0, 5);

  for (int i = 0; i <= 5; i++) {
    if (i < fullLeds) _strip.setPixelColor(i, COL_LIGHTBLUE());
    else if (i == fullLeds && fullLeds < 5) {
      // Partial LED: scale brightness
      float part = ledsLit - fullLeds;
      _strip.setPixelColor(i, dimColor(COL_LIGHTBLUE(), part));
    } else {
      _strip.setPixelColor(i, COL_OFF());
    }
  }
}

// ── Rate LED (LED 6) ──────────────────────────────────────────────────────────
static void updateRateLED(const SharedState& s) {
  if (!s.sessionActive || !s.visualFeedbackEnabled) {
    _strip.setPixelColor(NEO_LED_RATE, COL_OFF());
    return;
  }
  float rate = s.frequency;
  if (rate < 10.0f) {
    _strip.setPixelColor(NEO_LED_RATE, COL_OFF());  // no rate established yet
    return;
  }
  if (rate < s.targetRateMin) _strip.setPixelColor(NEO_LED_RATE, COL_YELLOW());       // too slow
  else if (rate > s.targetRateMax) _strip.setPixelColor(NEO_LED_RATE, COL_ORANGE());  // too fast
  else _strip.setPixelColor(NEO_LED_RATE, COL_WHITE());                               // correct
}

// ── Status LED (LED 7) ────────────────────────────────────────────────────────
static void updateStatusLED(const SharedState& s) {
  if (!s.visualFeedbackEnabled || s.currentMode == GloveMode::NoFeedback) {
    _strip.setPixelColor(NEO_LED_STATUS, COL_OFF());
    return;
  }

  // During active compressions: dim to 30%
  float dimFactor = s.sessionActive ? (float)NEO_DIM_BRIGHTNESS / NEO_MAX_BRIGHTNESS : 1.0f;

  // Leaning/bad posture: slow orange blink (overrides mode color)
  if (s.leaningDetected || fabsf(s.wristAlignmentAngle) >= WRIST_ALIGN_WARN_DEG) {
    bool on = blinkTick(1000);
    _strip.setPixelColor(NEO_LED_STATUS, on ? dimColor(COL_ORANGE(), dimFactor) : COL_OFF());
    return;
  }

  // Mode color
  uint32_t modeColor;
  switch (s.currentMode) {
    case GloveMode::Emergency: modeColor = COL_EMERALD(); break;
    case GloveMode::Training: modeColor = COL_BLUE(); break;
    default: modeColor = COL_OFF(); break;
  }
  _strip.setPixelColor(NEO_LED_STATUS, dimColor(modeColor, dimFactor));
}

// ── Main update ───────────────────────────────────────────────────────────────
void neoUpdate(const SharedState& s) {
  // NoFeedback: everything off
  if (s.currentMode == GloveMode::NoFeedback) {
    _strip.clear();
    _strip.show();
    return;
  }

  // Ventilation window: all cyan
  if (s.inVentilationWindow) {
    for (int i = 0; i < NEO_NUM_LEDS; i++) _strip.setPixelColor(i, COL_CYAN());
    _strip.show();
    return;
  }

  // Pulse check: all slow-blue-pulse
  if (s.pulseCheckActive) {
    bool on = blinkTick(1200);
    uint32_t c = on ? COL_BLUE() : dimColor(COL_BLUE(), 0.2f);
    for (int i = 0; i < NEO_NUM_LEDS; i++) _strip.setPixelColor(i, c);
    _strip.show();
    return;
  }

  updateDepthBar(s);
  updateRateLED(s);
  updateStatusLED(s);
  _strip.show();
}

// ── One-shot animations ───────────────────────────────────────────────────────
void neoSessionStart() {
  // All white for 1 second
  for (int i = 0; i < NEO_NUM_LEDS; i++) _strip.setPixelColor(i, COL_WHITE());
  _strip.show();
  vTaskDelay(pdMS_TO_TICKS(1000));
}

void neoSessionEnd() {
  // Fade out all LEDs over 1 second
  for (int step = NEO_MAX_BRIGHTNESS; step >= 0; step -= 5) {
    float f = (float)step / NEO_MAX_BRIGHTNESS;
    for (int i = 0; i < NEO_NUM_LEDS; i++)
      _strip.setPixelColor(i, dimColor(COL_WHITE(), f));
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(25));
  }
  _strip.clear();
  _strip.show();
}

void neoModeChange(GloveMode mode) {
  if (mode == GloveMode::NoFeedback) {
    // Blink blue once then off
    _strip.setPixelColor(NEO_LED_STATUS, COL_BLUE());
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(300));
    _strip.clear();
    _strip.show();
    return;
  }
  // Flash status LED in new mode color
  uint32_t c = (mode == GloveMode::Emergency) ? COL_EMERALD() : COL_BLUE();
  for (int i = 0; i < 2; i++) {
    _strip.setPixelColor(NEO_LED_STATUS, c);
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(200));
    _strip.setPixelColor(NEO_LED_STATUS, COL_OFF());
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void neoScenarioChange(Scenario sc) {
  // Adult = 1 white blink, Pediatric = 2 white blinks
  int blinks = (sc == Scenario::Pediatric) ? 2 : 1;
  for (int i = 0; i < blinks; i++) {
    _strip.setPixelColor(NEO_LED_STATUS, COL_WHITE());
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(250));
    _strip.setPixelColor(NEO_LED_STATUS, COL_OFF());
    _strip.show();
    if (i < blinks - 1) vTaskDelay(pdMS_TO_TICKS(150));
  }
}

void neoSelftestAnimation() {
  // Chase: light each LED white in sequence
  for (int i = 0; i < NEO_NUM_LEDS; i++) {
    _strip.clear();
    _strip.setPixelColor(i, COL_WHITE());
    _strip.show();
    vTaskDelay(pdMS_TO_TICKS(80));
  }
  _strip.clear();
  _strip.show();
}
