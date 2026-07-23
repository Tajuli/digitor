# DigLog 10 implementation

The app exposes one UI mode: **DigLog**.

Runtime selection:

- Android 13+, Camera2 P010 output, HEVC Main10 encoder, FULL/LEVEL_3,
  manual sensor/post processing and programmable tone-map support: hidden 10-bit engine.
- Same strict camera controls without the complete 10-bit chain: hidden 8-bit engine.
- Missing minimum grading-oriented controls: Not Available.

10-bit video path:

`Camera2 YCBCR_P010 -> padded-plane unpack -> OpenGL ES 3 16-bit integer textures -> DigLog Gamma v1 shader -> 10-bit EGL encoder surface -> HEVC Main10 -> MP4`

This is not HLG or PQ. The output uses DigLog's custom logarithmic transfer and a
sidecar `.diglog.json` file records the actual engine, codec, dimensions and bitrate.

OEMs sometimes advertise stream/codec capabilities but reject a combined session.
The app treats runtime configuration as the final authority and automatically falls
back to the strict 8-bit DigLog engine instead of producing a broken or fake 10-bit file.

Current 10-bit engine records the grading-critical video stream without microphone
audio. The 8-bit compatibility engine retains AAC audio. Audio does not affect image-data
preservation and can be captured separately until a synchronized AAC muxer is added.
