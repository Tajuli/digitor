# Digitor Android export engine

- Uses Android Storage Access Framework (`ACTION_CREATE_DOCUMENT`) for the export destination.
- Uses Jetpack Media3 Transformer 1.10.1 with MediaCodec/OpenGL hardware acceleration and device fallback.
- Supports sequential visible video and image clips, source trimming, embedded clip audio, H.264/H.265, resolution, frame rate, bitrate presets, progress and cancellation.
- The current first native engine intentionally does not yet composite Flutter text/sticker/overlay tracks or mix independent audio tracks. Those require mapping Digitor's overlay model into Media3 Composition video compositor/audio mixer APIs.
