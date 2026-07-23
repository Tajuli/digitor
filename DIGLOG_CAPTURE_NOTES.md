# DigLog Capture v1

Implemented:
- Home page `DigLog Capture` card below Video Editor and Image Editor.
- Working rear/front camera preview and video recording using the device camera pipeline.
- Maximum available camera resolution request (`ResolutionPreset.max`).
- Audio recording, tap-to-focus/metering, exposure compensation, torch and lens switching.
- Recording timer and safe stop-before-exit behavior.
- Clips copied into the app documents `DigLog` directory.
- A `.diglog.json` sidecar is saved with each clip for profile and capture metadata.
- One-tap import of the last recorded clip into the Digitor video editor.
- Android/iOS camera and microphone permissions.

Technical honesty:
This version preserves the highest-quality stream the public Flutter/device camera API exposes and does not apply a destructive fake flat filter. Actual sensor bit depth, HDR/log transfer curve, codec bitrate and manufacturer image processing remain device-dependent. A universal S-Log-equivalent 10-bit pipeline requires a later native Camera2/CameraX + MediaCodec implementation and per-device capability testing.
