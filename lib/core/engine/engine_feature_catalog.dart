import 'package:flutter/material.dart';

/// Source-backed UI inventory for DigitorEngine v0.0.1.
///
/// This catalog is intentionally presentation-only. Runtime support is decided
/// by discoverCapabilities(); any capability returned by the engine but absent
/// from this known catalog is still surfaced in the Engine Features workspace.
enum EngineWorkspace {
  media('Media', Icons.video_library_outlined),
  edit('Edit', Icons.content_cut_outlined),
  transform('Transform', Icons.crop_rotate_outlined),
  correction('Correction', Icons.tune_outlined),
  color('Color', Icons.color_lens_outlined),
  scopes('Scopes', Icons.monitor_heart_outlined),
  looks('LUT / Look', Icons.auto_awesome_outlined),
  masks('Masks', Icons.gesture_outlined),
  effects('Effects', Icons.blur_on_outlined),
  nodes('Nodes', Icons.account_tree_outlined),
  audio('Audio', Icons.graphic_eq_outlined),
  playback('Playback', Icons.play_circle_outline),
  performance('Performance', Icons.speed_outlined),
  export('Export', Icons.file_upload_outlined),
  engine('Engine', Icons.memory_outlined);

  const EngineWorkspace(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum EngineControlType { action, slider, toggle, choice, vector, text }

final class EngineUiFeature {
  const EngineUiFeature({
    required this.id,
    required this.workspace,
    required this.title,
    required this.summary,
    this.controls = const <EngineUiControl>[],
  });

  final String id;
  final EngineWorkspace workspace;
  final String title;
  final String summary;
  final List<EngineUiControl> controls;
}

final class EngineUiControl {
  const EngineUiControl.action(this.id, this.label)
      : type = EngineControlType.action,
        min = 0,
        max = 1,
        initial = 0,
        choices = const <String>[];

  const EngineUiControl.slider(
    this.id,
    this.label, {
    this.min = -1,
    this.max = 1,
    this.initial = 0,
  })  : type = EngineControlType.slider,
        choices = const <String>[];

  const EngineUiControl.toggle(this.id, this.label)
      : type = EngineControlType.toggle,
        min = 0,
        max = 1,
        initial = 0,
        choices = const <String>[];

  const EngineUiControl.choice(this.id, this.label, this.choices)
      : type = EngineControlType.choice,
        min = 0,
        max = 1,
        initial = 0;

  final String id;
  final String label;
  final EngineControlType type;
  final double min;
  final double max;
  final double initial;
  final List<String> choices;
}

const List<EngineUiFeature> engineFeatureCatalog = <EngineUiFeature>[
  // Media / project / decode
  EngineUiFeature(id: 'project.lifecycle', workspace: EngineWorkspace.media, title: 'Project', summary: 'New, open, save and authoritative project state.', controls: [EngineUiControl.action('new', 'New'), EngineUiControl.action('open', 'Open'), EngineUiControl.action('save', 'Save')]),
  EngineUiFeature(id: 'media.import', workspace: EngineWorkspace.media, title: 'Import Media', summary: 'Open/probe media through DigitorEngine and its platform host.', controls: [EngineUiControl.action('requestPicker', 'Import'), EngineUiControl.action('relink', 'Relink')]),
  EngineUiFeature(id: 'media.decode', workspace: EngineWorkspace.media, title: 'Decode', summary: 'FFmpeg and qualified hardware decode paths including native surfaces.', controls: [EngineUiControl.choice('decoder', 'Decoder', ['Auto', 'Hardware', 'Software'])]),
  EngineUiFeature(id: 'media.metadata', workspace: EngineWorkspace.media, title: 'Media Info', summary: 'Codec, dimensions, frame rate, timestamps and stream metadata.', controls: [EngineUiControl.action('inspect', 'Inspect')]),
  EngineUiFeature(id: 'media.zeroCopy', workspace: EngineWorkspace.media, title: 'Zero-copy Media', summary: 'Production native-surface import path and zero-copy qualification.', controls: [EngineUiControl.toggle('enabled', 'Prefer zero-copy')]),

  // Timeline / professional editing
  EngineUiFeature(id: 'timeline.multitrack', workspace: EngineWorkspace.edit, title: 'Multitrack Timeline', summary: 'Engine-owned video/audio tracks and timeline completion state.', controls: [EngineUiControl.action('addVideoTrack', 'Video Track'), EngineUiControl.action('addAudioTrack', 'Audio Track')]),
  EngineUiFeature(id: 'timeline.clip', workspace: EngineWorkspace.edit, title: 'Clip Editing', summary: 'Insert, append, overwrite, split, trim and clip/track operations.', controls: [EngineUiControl.action('split', 'Split'), EngineUiControl.action('delete', 'Delete'), EngineUiControl.action('duplicate', 'Duplicate')]),
  EngineUiFeature(id: 'timeline.trim', workspace: EngineWorkspace.edit, title: 'Professional Trim', summary: 'Ripple, roll, slip and slide editing surfaces.', controls: [EngineUiControl.choice('mode', 'Trim Mode', ['Trim', 'Ripple', 'Roll', 'Slip', 'Slide'])]),
  EngineUiFeature(id: 'timeline.track', workspace: EngineWorkspace.edit, title: 'Track Controls', summary: 'Enable, disable, remove, lock, mute and solo where advertised by runtime.', controls: [EngineUiControl.toggle('enabled', 'Enabled'), EngineUiControl.toggle('locked', 'Lock')]),
  EngineUiFeature(id: 'timeline.speed', workspace: EngineWorkspace.edit, title: 'Speed / Reverse', summary: 'Forward/reverse rate and timeline frame-selection foundation.', controls: [EngineUiControl.slider('rate', 'Speed', min: -4, max: 4, initial: 1), EngineUiControl.toggle('reverse', 'Reverse')]),

  // Transform / compositing
  EngineUiFeature(id: 'transform.geometry', workspace: EngineWorkspace.transform, title: 'Transform', summary: 'Presentation for engine-owned position, scale and rotation parameters.', controls: [EngineUiControl.slider('positionX', 'Position X', min: -1, max: 1), EngineUiControl.slider('positionY', 'Position Y', min: -1, max: 1), EngineUiControl.slider('scale', 'Scale', min: 0, max: 4, initial: 1), EngineUiControl.slider('rotation', 'Rotation', min: -180, max: 180)]),
  EngineUiFeature(id: 'transform.crop', workspace: EngineWorkspace.transform, title: 'Crop', summary: 'Crop controls routed to engine effect/timeline state.', controls: [EngineUiControl.slider('left', 'Left', min: 0, max: 1), EngineUiControl.slider('right', 'Right', min: 0, max: 1), EngineUiControl.slider('top', 'Top', min: 0, max: 1), EngineUiControl.slider('bottom', 'Bottom', min: 0, max: 1)]),
  EngineUiFeature(id: 'composite.opacity', workspace: EngineWorkspace.transform, title: 'Opacity / Composite', summary: 'Layer opacity and compositing presentation.', controls: [EngineUiControl.slider('opacity', 'Opacity', min: 0, max: 1, initial: 1)]),

  // Correction
  EngineUiFeature(id: 'color.correction', workspace: EngineWorkspace.correction, title: 'Correction', summary: 'Engine correction controls.', controls: [
    EngineUiControl.slider('exposure', 'Exposure', min: -5, max: 5),
    EngineUiControl.slider('contrast', 'Contrast', min: -1, max: 1),
    EngineUiControl.slider('saturation', 'Saturation', min: 0, max: 2, initial: 1),
    EngineUiControl.slider('temperature', 'Temperature', min: -1, max: 1),
    EngineUiControl.slider('tint', 'Tint', min: -1, max: 1),
    EngineUiControl.slider('highlights', 'Highlights', min: -1, max: 1),
    EngineUiControl.slider('shadows', 'Shadows', min: -1, max: 1),
    EngineUiControl.slider('hue', 'Hue', min: -180, max: 180),
    EngineUiControl.slider('colorBoost', 'Color Boost', min: -1, max: 1),
  ]),

  // Color grading
  EngineUiFeature(
    id: 'color.primaryWheels',
    workspace: EngineWorkspace.color,
    title: 'Primary Wheels',
    summary: 'Lift, Gamma, Gain and Offset primary grading.',
    controls: [
      EngineUiControl.action('open', 'Open Wheels'),
      EngineUiControl.action('reset', 'Reset'),
      EngineUiControl.slider('liftR', 'Lift R', min: -4, max: 4),
      EngineUiControl.slider('liftG', 'Lift G', min: -4, max: 4),
      EngineUiControl.slider('liftB', 'Lift B', min: -4, max: 4),
      EngineUiControl.slider('liftMaster', 'Lift Master', min: -4, max: 4),
      EngineUiControl.slider('gammaR', 'Gamma R', min: 0.01, max: 10, initial: 1),
      EngineUiControl.slider('gammaG', 'Gamma G', min: 0.01, max: 10, initial: 1),
      EngineUiControl.slider('gammaB', 'Gamma B', min: 0.01, max: 10, initial: 1),
      EngineUiControl.slider('gammaMaster', 'Gamma Master', min: 0.01, max: 10, initial: 1),
      EngineUiControl.slider('gainR', 'Gain R', min: 0, max: 16, initial: 1),
      EngineUiControl.slider('gainG', 'Gain G', min: 0, max: 16, initial: 1),
      EngineUiControl.slider('gainB', 'Gain B', min: 0, max: 16, initial: 1),
      EngineUiControl.slider('gainMaster', 'Gain Master', min: 0, max: 16, initial: 1),
      EngineUiControl.slider('offsetR', 'Offset R', min: -4, max: 4),
      EngineUiControl.slider('offsetG', 'Offset G', min: -4, max: 4),
      EngineUiControl.slider('offsetB', 'Offset B', min: -4, max: 4),
      EngineUiControl.slider('offsetMaster', 'Offset Master', min: -4, max: 4),
    ],
  ),
  EngineUiFeature(id: 'color.logWheels', workspace: EngineWorkspace.color, title: 'Log Wheels', summary: 'Logarithmic tonal-range grading.', controls: [EngineUiControl.action('open', 'Open Log Wheels'), EngineUiControl.action('reset', 'Reset')]),
  EngineUiFeature(id: 'color.rgbCurves', workspace: EngineWorkspace.color, title: 'RGB Curves', summary: 'Master/R/G/B curve editor backed by engine curve state.', controls: [EngineUiControl.choice('channel', 'Channel', ['Master', 'Red', 'Green', 'Blue']), EngineUiControl.action('reset', 'Reset Curve')]),
  EngineUiFeature(id: 'color.hslQualifier', workspace: EngineWorkspace.color, title: 'HSL Qualifier', summary: 'Hue, saturation and luminance key selection.', controls: [EngineUiControl.action('pick', 'Eyedropper'), EngineUiControl.toggle('highlight', 'Highlight')]),

  // Scopes / analysis
  EngineUiFeature(id: 'analysis.scopes', workspace: EngineWorkspace.scopes, title: 'Scopes', summary: 'Analysis viewport for engine/runtime scope data where advertised.', controls: [EngineUiControl.choice('scope', 'Scope', ['Waveform', 'RGB Parade', 'Vectorscope', 'Histogram'])]),

  // LUTs / looks
  EngineUiFeature(id: 'color.lut1d', workspace: EngineWorkspace.looks, title: '1D LUT', summary: 'Engine 1D LUT support.', controls: [EngineUiControl.action('load', 'Load 1D LUT'), EngineUiControl.slider('mix', 'Mix', min: 0, max: 1, initial: 1)]),
  EngineUiFeature(id: 'color.lut3d', workspace: EngineWorkspace.looks, title: '3D LUT', summary: 'Engine 3D LUT support.', controls: [EngineUiControl.action('load', 'Load 3D LUT'), EngineUiControl.slider('mix', 'Mix', min: 0, max: 1, initial: 1)]),

  // Masks/windows
  EngineUiFeature(id: 'effects.masksWindows', workspace: EngineWorkspace.masks, title: 'Masks / Windows', summary: 'Mask/window effect infrastructure.', controls: [EngineUiControl.choice('shape', 'Shape', ['Circle', 'Rectangle', 'Polygon', 'Gradient']), EngineUiControl.slider('feather', 'Feather', min: 0, max: 1), EngineUiControl.toggle('invert', 'Invert')]),

  // Effects / filters
  EngineUiFeature(id: 'effects.blur', workspace: EngineWorkspace.effects, title: 'Blur', summary: 'Native/CPU-qualified blur infrastructure.', controls: [EngineUiControl.slider('amount', 'Amount', min: 0, max: 1)]),
  EngineUiFeature(id: 'effects.sharpen', workspace: EngineWorkspace.effects, title: 'Sharpen', summary: 'Sharpen effect.', controls: [EngineUiControl.slider('amount', 'Amount', min: 0, max: 1)]),
  EngineUiFeature(id: 'effects.glow', workspace: EngineWorkspace.effects, title: 'Glow', summary: 'Glow effect.', controls: [EngineUiControl.slider('amount', 'Amount', min: 0, max: 1)]),
  EngineUiFeature(id: 'effects.grain', workspace: EngineWorkspace.effects, title: 'Film Grain', summary: 'Grain effect.', controls: [EngineUiControl.slider('amount', 'Amount', min: 0, max: 1)]),
  EngineUiFeature(id: 'effects.vignette', workspace: EngineWorkspace.effects, title: 'Vignette', summary: 'Vignette effect.', controls: [EngineUiControl.slider('amount', 'Amount', min: -1, max: 1)]),
  EngineUiFeature(id: 'effects.motionBlur', workspace: EngineWorkspace.effects, title: 'Motion Blur', summary: 'Motion blur effect infrastructure.', controls: [EngineUiControl.slider('amount', 'Amount', min: 0, max: 1)]),

  // Nodes
  EngineUiFeature(id: 'nodes.graph', workspace: EngineWorkspace.nodes, title: 'Node Graph', summary: 'Production node graph and native node execution runtime.', controls: [EngineUiControl.action('addSerial', 'Serial'), EngineUiControl.action('addParallel', 'Parallel'), EngineUiControl.action('addMixer', 'Mixer'), EngineUiControl.action('addOutput', 'Output')]),
  EngineUiFeature(id: 'nodes.connections', workspace: EngineWorkspace.nodes, title: 'Node Connections', summary: 'Connect, disconnect, bypass and graph validation.', controls: [EngineUiControl.action('connect', 'Connect'), EngineUiControl.action('disconnect', 'Disconnect'), EngineUiControl.toggle('bypass', 'Bypass')]),

  // Audio
  EngineUiFeature(id: 'audio.sync', workspace: EngineWorkspace.audio, title: 'Audio-master Sync', summary: 'Audio-master synchronization and latency compensation.', controls: [EngineUiControl.slider('latencyMs', 'Latency', min: -500, max: 500)]),
  EngineUiFeature(id: 'audio.track', workspace: EngineWorkspace.audio, title: 'Audio Track', summary: 'Track presentation routed to authoritative engine state.', controls: [EngineUiControl.slider('gain', 'Gain', min: -60, max: 12), EngineUiControl.slider('pan', 'Pan', min: -1, max: 1), EngineUiControl.toggle('mute', 'Mute')]),

  // Playback / preview
  EngineUiFeature(id: 'playback.transport', workspace: EngineWorkspace.playback, title: 'Transport', summary: 'Play, pause, stop, seek, scrub, frame-step, loop and rates.', controls: [EngineUiControl.action('previousFrame', 'Previous'), EngineUiControl.action('playPause', 'Play/Pause'), EngineUiControl.action('nextFrame', 'Next'), EngineUiControl.toggle('loop', 'Loop')]),
  EngineUiFeature(id: 'playback.scheduler', workspace: EngineWorkspace.playback, title: 'Production Playback', summary: 'Decode-ahead, bounded GPU queue, stale-frame rejection and deadline hold/drop behavior.', controls: [EngineUiControl.action('stats', 'Playback Stats')]),
  EngineUiFeature(id: 'playback.quality', workspace: EngineWorkspace.playback, title: 'Preview Quality', summary: 'Adaptive Full, Half, Quarter and Proxy quality.', controls: [EngineUiControl.choice('quality', 'Quality', ['Adaptive', 'Full', 'Half', 'Quarter', 'Proxy'])]),

  // Performance/runtime infrastructure
  EngineUiFeature(id: 'runtime.backend', workspace: EngineWorkspace.performance, title: 'GPU Backend', summary: 'Vulkan, D3D12, Metal, OpenGL ES or CPU fallback selection/qualification.', controls: [EngineUiControl.choice('backend', 'Backend', ['Auto', 'Vulkan', 'Direct3D 12', 'Metal', 'OpenGL ES', 'CPU'])]),
  EngineUiFeature(id: 'runtime.renderGraph', workspace: EngineWorkspace.performance, title: 'Render Graph', summary: 'Engine render-graph execution and command infrastructure.', controls: [EngineUiControl.action('inspect', 'Inspect')]),
  EngineUiFeature(id: 'runtime.pipelineCache', workspace: EngineWorkspace.performance, title: 'Shader / Pipeline Cache', summary: 'Shader compilation/reflection and pipeline-cache infrastructure.', controls: [EngineUiControl.action('stats', 'Cache Stats')]),
  EngineUiFeature(id: 'runtime.pressure', workspace: EngineWorkspace.performance, title: 'Thermal / Memory Pressure', summary: 'Adaptive thermal and memory-pressure controls.', controls: [EngineUiControl.action('status', 'Status')]),

  // Export
  EngineUiFeature(id: 'export.format', workspace: EngineWorkspace.export, title: 'File Type / Codec', summary: 'Native production MP4 export with the selected video codec.', controls: [EngineUiControl.choice('profile', 'File Type / Codec', ['MP4 · H.264', 'MP4 · H.265 (HEVC)'])]),
  EngineUiFeature(id: 'export.production', workspace: EngineWorkspace.export, title: 'Production Export', summary: 'Shared timeline render path with progress, errors and cancellation.', controls: [EngineUiControl.action('start', 'Export')]),
  EngineUiFeature(id: 'export.jobs', workspace: EngineWorkspace.export, title: 'Async Export Jobs', summary: 'Asynchronous jobs, progress, cancellation and error reporting.', controls: [EngineUiControl.action('queue', 'Queue'), EngineUiControl.action('cancel', 'Cancel')]),
  EngineUiFeature(id: 'export.resume', workspace: EngineWorkspace.export, title: 'Resumable Segment Export', summary: 'Segmented/resumable export workflow.', controls: [EngineUiControl.toggle('enabled', 'Resumable')]),

  // Engine observability/completeness
  EngineUiFeature(id: 'engine.capabilities', workspace: EngineWorkspace.engine, title: 'Capability Discovery', summary: 'Runtime-reported DigitorEngine features; unknown/new capabilities are surfaced automatically.', controls: [EngineUiControl.action('refresh', 'Refresh')]),
  EngineUiFeature(id: 'engine.telemetry', workspace: EngineWorkspace.engine, title: 'Telemetry', summary: 'Playback/runtime performance and health information.', controls: [EngineUiControl.action('refresh', 'Refresh')]),
  EngineUiFeature(id: 'engine.qualification', workspace: EngineWorkspace.engine, title: 'Qualification', summary: 'Backend, decode/import, zero-copy and device qualification state.', controls: [EngineUiControl.action('inspect', 'Inspect')]),
  EngineUiFeature(id: 'engine.errors', workspace: EngineWorkspace.engine, title: 'Errors / Diagnostics', summary: 'Native execution errors are surfaced; GPU failure never silently changes active work to CPU.', controls: [EngineUiControl.action('copyReport', 'Copy Report')]),
];
