# DigLog implementation

## User-facing behavior

- The UI exposes one mode only: **DigLog**.
- The app performs strict Camera2 capability detection in the background.
- Unsupported devices show **Not Available** and cannot record a cosmetic flat-filter clip.

## Implemented capture path

- Native Android Camera2 capture.
- Programmable pre-encode `TONEMAP_MODE_CONTRAST_CURVE` Log-like curve.
- HEVC MP4 recording at a high resolution-dependent bitrate.
- Minimal noise reduction where exposed by Camera2.
- Edge enhancement and chromatic aberration correction disabled where supported.
- White balance and exposure lock.
- `.diglog.json` sidecar metadata.

## Strict availability requirements

- Rear camera hardware level FULL or LEVEL_3.
- MANUAL_SENSOR capability.
- MANUAL_POST_PROCESSING capability.
- Programmable CONTRAST_CURVE tonemap mode.
- Hardware HEVC encoder.

## 10-bit note

The detector reports P010 and HEVC Main10 support internally, but the current programmable tone-curve recording engine intentionally remains 8-bit. Android's public 10-bit camera output profiles are HDR transfer functions; labeling one of those as a custom DigLog curve would be misleading. A genuine DigLog 10 implementation requires a P010 camera-to-GPU-to-Main10 pipeline. Until that path is implemented and validated, the app does not expose or claim 10-bit DigLog.
