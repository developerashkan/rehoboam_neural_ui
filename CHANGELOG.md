## 1.0.0

Big feature release. No breaking API changes: every 0.0.x constructor and
parameter still works. The version moves to 1.0.0 because the API is now
considered stable.

### New widgets

* `NeuralOrb`: assistant orb with idle, listening, thinking and speaking
  states, smoothed audio level, eased state changes and tap support.
* `NeuralProgress` / `NeuralProgress.linear`: synapse-ring and glowing-bar
  loaders, determinate (animated) or indeterminate.
* `NeuralGauge`: animated KPI ring with ticks, glow, threshold colors and a
  real-text readout.
* `NeuralSparkline`: glowing monotone-cubic trend line with draw-in, morphing
  between datasets, gaps for NaN, drag / hover scrubbing and `onScrub`.
* `NeuralHeatmap`: activity calendar with glow, locale-aware week start,
  DST-safe day bucketing and `onCellTap`.
* `NeuralGlassCard`: frosted-glass panel with a living border current, hover /
  focus / press glow, and keyboard-accessible `onTap`.
* `NeuralScanRing`: scanning / verification ring (radar sweep, scan line,
  success check, failure shake) with `onResolved`.
* `NeuralAvatar`: avatar with presence aura, speaking ripples, status badge
  and grapheme-aware initials fallback.
* `NeuralNetworkBackground`: drifting node network with pulses and pointer
  attraction; allocation-free per frame.
* `NeuralThemeData` theme extension and `NeuralPalette` for app-wide colors.
  Everything defaults to the ambient `ColorScheme` (light and dark).

### Fixes

* `AiThinkingAnimation`
  * Created with `hudMode: HudMode.earth`, it showed the ring forever.
  * Switching to Earth never flew to `targetLat` / `targetLon`: the zoom ran
    before the globe was mounted. It now waits a frame and works without a
    user `DotGlobeController` too (one is created and disposed internally).
  * The texture jumped every 30 s (the controller wrapped) and had a visible
    seam (non-integer angular frequencies). It is now seamless and continuous.
  * `speed` changes made the ring skip; `speed` now scales time smoothly.
  * Painted up to 9 000 `drawPoints` calls per frame and rebuilt the whole
    stack (globe included) every frame, with `shouldRepaint` always true. It
    now batches particles into 3 draw calls from preallocated buffers,
    repaints through a listenable and caches its text.
  * The zoomed globe spilled outside the HUD; it is now clipped to a lens.
  * `mode` (`AiFaceMode`) had no visual effect; speaking is now livelier.
  * Labels ignored right-to-left; NaN `level`, NaN geo points and infinite
    `size` broke painting. Added `color`, `semanticsLabel` and `animate`.
* `VoiceWave`
  * `speed: 0` (or negative / NaN) threw; changing `speed` was ignored.
  * The breathing blob and pulse jumped back every 2.2 s.
  * Speaking bars were hairlines (stroke width 0).
  * Particles were hard-coded white, invisible on light themes; added
    `color`, `secondaryColor`, `particleColor` and `semanticsLabel`.
* `WordByWordTranscript`
  * `maxLines` was ignored.
  * Revised middle words stayed stale and removed words were never removed.
  * Replaced text did not animate in (chips had no keys).
  * The highlighted word changed font size, reflowing the line; it now scales.
  * Exposed to screen readers as one live region. Added `textAlign`.
* `AudioLevelStream` returned an always-empty stream while its docs promised
  a native channel. It is now a real broadcast hub (`add`, `addLevel`,
  `latest`).
* Every widget honors `MediaQuery.disableAnimations`.
* The pubspec claimed Flutter 3.22, but the code needs 3.27 (`Color.withValues`).
  Constraints are now `sdk: ^3.6.0`, `flutter: >=3.27.0`.

### Package

* New adaptive gallery example (phone to desktop, light / dark, LTR / RTL).
* Screenshots and GIF rendered from widget tests with real fonts.
* 103 package tests (regressions for every fix above).

## 0.0.7

* Fix: Rename `Screenshot.png` to `screenshot.png` and update `pubspec.yaml` to ensure thumbnail is correctly identified by pub.dev.
* Update: Refine screenshot descriptions for better search results.

## 0.0.6

* Update: Package description to reflect 3D Earth globe transformation capabilities.
* Fix: Ensure screenshots are correctly linked in `pubspec.yaml` for search indexing.

## 0.0.5

* Fix: Include both static screenshot and animated GIF (compressed to <4MB) in `pubspec.yaml` screenshots.
* Improve: Refine screenshot descriptions for better search indexing.

## 0.0.4

* Fix: Use Markdown table in README for side-by-side layout (more compatible with pub.dev sanitizer).
* Note: GIF in README requires a fast connection due to its size (11MB). Pub.dev carousel/search thumbnails have a 4MB limit.

## 0.0.3

* Fix: Display screenshot and demo side-by-side in README.
* Fix: Remove GIF from `screenshots` in `pubspec.yaml` to fix search thumbnail rendering (pub.dev only supports static images for thumbnails).

## 0.0.2

* Fix: Update README with absolute image URLs to ensure they display correctly on pub.dev.

## 0.0.1

* Initial release of `rehoboam_neural_ui`.
* Includes `AiThinkingAnimation` widget with organic particulate ring.
* Geographic mapping support for 3D coordinates.
* `VoiceWave` and `WordByWordTranscript` additional widgets.
