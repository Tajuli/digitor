from pathlib import Path


def replace_block(text: str, start: str, end: str, replacement: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[:a] + replacement.rstrip() + "\n\n" + text[b:]


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match, found {count}: {old[:80]!r}")
    return text.replace(old, new, 1)


gateway_path = Path("lib/core/engine/ffi_engine_gateway.dart")
text = gateway_path.read_text()

text = replace_once(
    text,
    "import 'engine_feature_catalog.dart';\nimport 'engine_gateway.dart';",
    "import 'edit_timeline.dart';\nimport 'engine_feature_catalog.dart';\nimport 'engine_gateway.dart';",
)

text = replace_once(
    text,
    "  String? _mediaPath;\n  int? _previewTextureId;",
    "  String? _mediaPath;\n"
    "  final LinearEditTimeline _editTimeline = LinearEditTimeline();\n"
    "  String? _selectedClipId;\n"
    "  String? _activeClipId;\n"
    "  int _timelinePositionUs = 0;\n"
    "  bool _clipTransitionInFlight = false;\n"
    "  int? _previewTextureId;",
)

new_poll = r'''  Future<void> _pollEngine() async {
    if (_disposed || _workspace == null) return;
    var status = _w.timelineStatus();
    if (_editTimeline.isNotEmpty && !_clipTransitionInFlight) {
      _syncTimelinePositionFromStatus(status);
      if (status.playbackState == DigitorPlaybackState.playing) {
        final transitioned = await _advancePlaybackIfNeeded(status);
        if (transitioned) {
          status = _w.timelineStatus();
        }
      }
    }
    _emitSnapshot();
    if (_mediaPath == null ||
        !_w.productionReady ||
        _previewInFlight ||
        _clipTransitionInFlight ||
        _exportPreparing ||
        _exportRequested ||
        _exportInFlight) {
      return;
    }
    final graphChanged = _lastPreviewGraphRevision != _w.graphRevision ||
        _lastPreviewParameterRevision != _w.parameterRevision;
    final previewPositionUs = _editTimeline.isEmpty
        ? status.positionUs
        : _timelinePositionUs;
    final positionChanged = _lastPreviewPositionUs != previewPositionUs;
    if (status.playbackState == DigitorPlaybackState.playing ||
        graphChanged ||
        positionChanged ||
        _previewTextureId == null) {
      await _renderPreview();
    }
  }

  void _syncTimelinePositionFromStatus(DigitorTimelineStatus status) {
    final clip = _editTimeline.byId(_activeClipId);
    if (clip == null) return;
    final localOffset = status.positionUs - clip.sourceInUs;
    _timelinePositionUs = (clip.timelineStartUs + localOffset)
        .clamp(clip.timelineStartUs, clip.timelineEndUs)
        .toInt();
  }

  Future<bool> _advancePlaybackIfNeeded(DigitorTimelineStatus status) async {
    final clip = _editTimeline.byId(_activeClipId);
    if (clip == null) return false;
    final guardUs = (clip.frameDurationUs ~/ 2).clamp(1, 50000);
    if (status.positionUs < clip.sourceOutUs - guardUs) return false;

    final next = _editTimeline.nextAfter(clip.id);
    if (next == null) {
      _w.pause();
      _timelinePositionUs = _editTimeline.durationUs;
      _lastPreviewPositionUs = -1;
      return true;
    }
    await _activateClip(
      next,
      timelinePositionUs: next.timelineStartUs,
      playAfter: true,
    );
    return true;
  }

  int _safeSourceTimestamp(EditTimelineClip clip, int timelinePositionUs) {
    final mapped = clip.sourceTimestampForTimeline(timelinePositionUs);
    final lastRenderable = math.max(
      clip.sourceInUs,
      clip.sourceOutUs - math.max(1, clip.frameDurationUs),
    );
    return mapped.clamp(clip.sourceInUs, lastRenderable).toInt();
  }

  Future<void> _activateClip(
    EditTimelineClip clip, {
    required int timelinePositionUs,
    required bool playAfter,
  }) async {
    if (_clipTransitionInFlight) return;
    _clipTransitionInFlight = true;
    try {
      final activePreview = _activePreview;
      if (activePreview != null) await activePreview;
      if (_mediaPath != clip.sourcePath || !_w.productionReady) {
        await _openMediaPath(
          clip.sourcePath,
          appendToTimeline: false,
          displayName: clip.displayName,
          emitMediaEvent: false,
          renderAfterOpen: false,
        );
      }
      _activeClipId = clip.id;
      _timelinePositionUs = timelinePositionUs
          .clamp(clip.timelineStartUs, clip.timelineEndUs)
          .toInt();
      _w.seek(_safeSourceTimestamp(clip, _timelinePositionUs));
      if (playAfter) {
        _w.play();
      } else {
        _w.pause();
      }
      _lastPreviewPositionUs = -1;
      _lastPreviewGraphRevision = -1;
      _lastPreviewParameterRevision = -1;
      await _renderPreview(force: true);
    } finally {
      _clipTransitionInFlight = false;
    }
  }

  Future<void> _seekTimeline(int positionUs) async {
    if (_editTimeline.isEmpty) {
      _w.seek(positionUs);
      return;
    }
    final target = positionUs.clamp(0, _editTimeline.durationUs).toInt();
    final lookup = target == _editTimeline.durationUs && target > 0
        ? target - 1
        : target;
    final clip = _editTimeline.clipAt(lookup);
    if (clip == null) return;
    final wasPlaying =
        _w.timelineStatus().playbackState == DigitorPlaybackState.playing;
    await _activateClip(
      clip,
      timelinePositionUs: target,
      playAfter: wasPlaying,
    );
  }
'''
text = replace_block(
    text,
    "  Future<void> _pollEngine() async {",
    "  Future<void> _renderPreview({bool force = false}) {",
    new_poll,
)

new_render_impl = r'''  Future<void> _renderPreviewImpl({required bool force}) async {
    final media = _w.media;
    if (media == null) return;
    final status = _w.timelineStatus();
    final globalPositionUs = _editTimeline.isEmpty
        ? status.positionUs
        : _timelinePositionUs;
    final clip = _editTimeline.isEmpty
        ? null
        : _editTimeline.clipAt(
            globalPositionUs == _editTimeline.durationUs && globalPositionUs > 0
                ? globalPositionUs - 1
                : globalPositionUs,
          );
    final previewTimestampUs = clip == null
        ? status.positionUs
        : _safeSourceTimestamp(clip, globalPositionUs);
    if (!force &&
        _previewTextureId != null &&
        _lastPreviewPositionUs == globalPositionUs &&
        _lastPreviewGraphRevision == _w.graphRevision &&
        _lastPreviewParameterRevision == _w.parameterRevision) {
      return;
    }

    _previewInFlight = true;
    try {
      final graphRevision = _w.graphRevision;
      final parameterRevision = _w.parameterRevision;
      final preview = await _w.presentPreview(
        timestampUs: previewTimestampUs,
        width: media.firstFrame.width,
        height: media.firstFrame.height,
      );
      _previewTextureId = preview.textureId;
      _previewWidth = preview.width;
      _previewHeight = preview.height;
      _previewGeneration = preview.generation;
      _lastPreviewPositionUs = globalPositionUs;
      _lastPreviewGraphRevision = graphRevision;
      _lastPreviewParameterRevision = parameterRevision;
      _debug(
        'preview generation=${preview.generation} texture=${preview.textureId} '
        '${preview.width}x${preview.height} timelineT=$globalPositionUs '
        'sourceT=$previewTimestampUs graph=$graphRevision params=$parameterRevision',
      );
      _emitSnapshot(message: 'Preview frame ${preview.generation}');
    } catch (error, stack) {
      _debug('preview failed: $error\n$stack');
      _event('previewError', <String, Object?>{'error': '$error'});
    } finally {
      _previewInFlight = false;
    }
  }
'''
text = replace_block(
    text,
    "  Future<void> _renderPreviewImpl({required bool force}) async {",
    "  @override\n  Future<List<EngineCapability>> discoverCapabilities() async {",
    new_render_impl,
)

text = replace_once(
    text,
    "        _projectOpen = true;\n        _mediaPath = null;\n        _previewTextureId = null;",
    "        _projectOpen = true;\n"
    "        _mediaPath = null;\n"
    "        _editTimeline.clear();\n"
    "        _selectedClipId = null;\n"
    "        _activeClipId = null;\n"
    "        _timelinePositionUs = 0;\n"
    "        _previewTextureId = null;",
)

clip_dispatch = r'''
      if (action == 'timeline.clip.select') {
        final id = value?.toString();
        _selectedClipId = _editTimeline.byId(id) == null ? null : id;
        _emitSnapshot();
        return;
      }
      if (action == 'timeline.clip.split') {
        final selected = _selectedClipId;
        if (selected == null) {
          throw StateError('Select a clip before splitting.');
        }
        _w.pause();
        final result = _editTimeline.split(selected, _timelinePositionUs);
        _selectedClipId = result.right.id;
        _activeClipId = result.right.id;
        _w.seek(_safeSourceTimestamp(result.right, _timelinePositionUs));
        _lastPreviewPositionUs = -1;
        _emitSnapshot(message: 'Clip split');
        await _renderPreview(force: true);
        _event('timelineClipSplit', <String, Object?>{
          'leftClipId': result.left.id,
          'rightClipId': result.right.id,
          'positionUs': _timelinePositionUs,
        });
        return;
      }
      if (action == 'timeline.clip.deleteSelected') {
        final selected = _selectedClipId;
        if (selected == null) {
          throw StateError('Select a clip before deleting.');
        }
        _w.pause();
        final removed = _editTimeline.byId(selected)!;
        final oldPositionUs = _timelinePositionUs;
        _editTimeline.delete(selected);
        _selectedClipId = null;
        if (_editTimeline.isEmpty) {
          _mediaPath = null;
          _activeClipId = null;
          _timelinePositionUs = 0;
          _previewTextureId = null;
          _previewGeneration = 0;
          _emitSnapshot(message: 'Clip deleted');
        } else {
          final shiftedPosition = oldPositionUs >= removed.timelineEndUs
              ? oldPositionUs - removed.durationUs
              : oldPositionUs >= removed.timelineStartUs
                  ? removed.timelineStartUs
                  : oldPositionUs;
          final target = shiftedPosition
              .clamp(0, _editTimeline.durationUs)
              .toInt();
          final lookup = target == _editTimeline.durationUs && target > 0
              ? target - 1
              : target;
          final nextClip = _editTimeline.clipAt(lookup)!;
          await _activateClip(
            nextClip,
            timelinePositionUs: target,
            playAfter: false,
          );
          _emitSnapshot(message: 'Clip deleted');
        }
        _event('timelineClipDeleted', <String, Object?>{
          'clipId': selected,
          'durationUs': _editTimeline.durationUs,
        });
        return;
      }
'''
text = replace_once(
    text,
    "\n      if (action.startsWith('color.correction.')) {",
    clip_dispatch + "\n      if (action.startsWith('color.correction.')) {",
)

new_import = r'''  Future<void> _importMedia() async {
    late final String mediaPath;
    String? displayName;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final selected = await _androidExportChannel.invokeMapMethod<String, Object?>(
        'pickMediaImport',
      );
      if (selected == null) return;
      final path = selected['path'];
      if (path is! String || path.trim().isEmpty) {
        throw StateError('Android media picker returned no staged file path.');
      }
      mediaPath = path.trim();
      displayName = selected['displayName']?.toString();
      _debug(
        'Android media staged path=$mediaPath '
        'name=${selected['displayName']} size=${selected['size']} '
        'mime=${selected['mimeType']}',
      );
    } else {
      final file = await openFile();
      if (file == null) return;
      mediaPath = file.path;
      displayName = file.name;
    }

    final clip = await _openMediaPath(
      mediaPath,
      appendToTimeline: true,
      displayName: displayName,
      emitMediaEvent: true,
      renderAfterOpen: false,
    );
    if (clip == null) return;
    _selectedClipId = clip.id;
    _activeClipId = clip.id;
    _timelinePositionUs = clip.timelineStartUs;
    _w.pause();
    _w.seek(_safeSourceTimestamp(clip, _timelinePositionUs));
    _lastPreviewPositionUs = -1;
    _emitSnapshot(message: 'Video added to timeline');
    _event('timelineClipAdded', <String, Object?>{
      'clipId': clip.id,
      'path': clip.sourcePath,
      'timelineStartUs': clip.timelineStartUs,
      'durationUs': clip.durationUs,
      'clipCount': _editTimeline.length,
    });
    await _renderPreview(force: true);
  }

  Future<EditTimelineClip?> _openMediaPath(
    String mediaPath, {
    required bool appendToTimeline,
    required String? displayName,
    required bool emitMediaEvent,
    required bool renderAfterOpen,
  }) async {
    final activePreview = _activePreview;
    if (activePreview != null) await activePreview;
    _debug('opening $mediaPath');
    final media = _w.openMedia(mediaPath);
    _mediaPath = mediaPath;
    _projectOpen = true;
    _lastPreviewPositionUs = -1;
    _lastPreviewGraphRevision = -1;
    _lastPreviewParameterRevision = -1;

    EditTimelineClip? clip;
    if (appendToTimeline) {
      final name = (displayName == null || displayName.trim().isEmpty)
          ? mediaPath.replaceAll('\\', '/').split('/').last
          : displayName.trim();
      clip = _editTimeline.append(
        sourcePath: mediaPath,
        displayName: name,
        sourceDurationUs: media.duration.inMicroseconds,
        frameDurationUs: media.firstFrame.duration.inMicroseconds,
        firstFrameNumber: media.firstFrame.frameNumber,
        width: media.firstFrame.width,
        height: media.firstFrame.height,
      );
    }

    if (emitMediaEvent) {
      _event('mediaOpened', <String, Object?>{
        'path': media.path,
        'decoder': media.decoder.implementation,
        'hardwareAccelerated': media.decoder.hardwareAccelerated,
        'nativeSurfaceOutput': media.decoder.nativeSurfaceOutput,
        'strictGpuPath': media.strictGpuPath,
        'durationUs': media.duration.inMicroseconds,
        'frameDurationUs': media.firstFrame.duration.inMicroseconds,
        'width': media.firstFrame.width,
        'height': media.firstFrame.height,
        'pixelFormat': media.firstFrame.pixelFormat.name,
        'gpuResident': media.firstFrame.gpuResident,
        'cpuResident': media.firstFrame.cpuResident,
      });
    }
    _debug(
      'media durationUs=${media.duration.inMicroseconds} '
      'frameDurationUs=${media.firstFrame.duration.inMicroseconds}',
    );
    if (renderAfterOpen) await _renderPreview(force: true);
    return clip;
  }
'''
text = replace_block(
    text,
    "  Future<void> _importMedia() async {",
    "  Future<void> _handleTransport(String action, Object? value) async {",
    new_import,
)

new_transport = r'''  Future<void> _handleTransport(String action, Object? value) async {
    final status = _w.timelineStatus();
    if (_editTimeline.isEmpty) {
      switch (action) {
        case 'playback.transport.playPause':
          if (status.playbackState == DigitorPlaybackState.playing) {
            _w.pause();
          } else {
            _w.play();
          }
          break;
        case 'playback.transport.previousFrame':
          _w.seek((status.positionUs - 33333).clamp(0, 1 << 62).toInt());
          break;
        case 'playback.transport.nextFrame':
          _w.seek((status.positionUs + 33333).clamp(0, 1 << 62).toInt());
          break;
        case 'playback.transport.stop':
          _w.stop();
          break;
        case 'playback.transport.seek':
          if (value is num) _w.seek(value.toInt());
          break;
        default:
          _eventUnsupported(action);
          return;
      }
      _emitSnapshot();
      await _renderPreview(force: true);
      return;
    }

    switch (action) {
      case 'playback.transport.playPause':
        if (status.playbackState == DigitorPlaybackState.playing) {
          _syncTimelinePositionFromStatus(status);
          _w.pause();
        } else {
          final lookup = _timelinePositionUs == _editTimeline.durationUs &&
                  _timelinePositionUs > 0
              ? _timelinePositionUs - 1
              : _timelinePositionUs;
          final clip = _editTimeline.clipAt(lookup);
          if (clip != null) {
            await _activateClip(
              clip,
              timelinePositionUs: _timelinePositionUs,
              playAfter: true,
            );
          }
        }
        break;
      case 'playback.transport.previousFrame':
        await _seekTimeline(_timelinePositionUs - 33333);
        break;
      case 'playback.transport.nextFrame':
        await _seekTimeline(_timelinePositionUs + 33333);
        break;
      case 'playback.transport.stop':
        _w.stop();
        _timelinePositionUs = 0;
        final first = _editTimeline.clipAt(0);
        if (first != null) {
          await _activateClip(first, timelinePositionUs: 0, playAfter: false);
        }
        break;
      case 'playback.transport.seek':
        if (value is num) await _seekTimeline(value.toInt());
        break;
      default:
        _eventUnsupported(action);
        return;
    }
    _emitSnapshot();
    await _renderPreview(force: true);
  }
'''
text = replace_block(
    text,
    "  Future<void> _handleTransport(String action, Object? value) async {",
    "  void _applyAudioControls() {",
    new_transport,
)

# Keep export correct for a single full/trimmed clip and fail explicitly for an
# unsupported multi-source sequence rather than silently exporting only the
# currently active source. Sequence stitching will be added behind the same
# timeline model without changing edit semantics.
text = replace_once(
    text,
    "      final media = _w.media;\n      if (media == null || _mediaPath == null) {\n        throw StateError('Import media before export.');\n      }",
    "      if (_editTimeline.length > 1) {\n"
    "        throw StateError(\n"
    "          'Multi-clip editing is active. Sequence export stitching is not enabled in this build yet.',\n"
    "        );\n"
    "      }\n"
    "      final exportClip = _editTimeline.length == 1 ? _editTimeline.clips.single : null;\n"
    "      if (exportClip != null && _mediaPath != exportClip.sourcePath) {\n"
    "        await _activateClip(\n"
    "          exportClip,\n"
    "          timelinePositionUs: _timelinePositionUs.clamp(0, exportClip.timelineEndUs).toInt(),\n"
    "          playAfter: false,\n"
    "        );\n"
    "      }\n"
    "      final media = _w.media;\n"
    "      if (media == null || _mediaPath == null) {\n"
    "        throw StateError('Import media before export.');\n"
    "      }",
)

text = replace_once(
    text,
    "      final durationUs = status.durationUs > 0\n          ? status.durationUs\n          : media.duration.inMicroseconds;",
    "      final durationUs = exportClip?.durationUs ??\n"
    "          (status.durationUs > 0 ? status.durationUs : media.duration.inMicroseconds);",
)

text = replace_once(
    text,
    "      final firstFrame = media.firstFrame.frameNumber;\n      final lastFrame = firstFrame + frameCount - 1;",
    "      final firstFrame = exportClip == null\n"
    "          ? media.firstFrame.frameNumber\n"
    "          : exportClip.firstFrameNumber +\n"
    "              (exportClip.sourceInUs ~/ frameDurationUs);\n"
    "      final lastFrame = firstFrame + frameCount - 1;",
)

new_snapshot = r'''  void _emitSnapshot({String? message}) {
    if (_disposed || _workspace == null) return;
    final status = _w.timelineStatus();
    final hasEditTimeline = _editTimeline.isNotEmpty;
    final durationUs = hasEditTimeline ? _editTimeline.durationUs : status.durationUs;
    final positionUs = hasEditTimeline
        ? _timelinePositionUs.clamp(0, durationUs).toInt()
        : status.positionUs;
    final selected = _editTimeline.byId(_selectedClipId);
    final active = _editTimeline.byId(_activeClipId);
    _snapshotController.add(
      EngineSnapshot(
        connected: true,
        projectOpen: _projectOpen,
        isPlaying: hasEditTimeline
            ? status.playbackState == DigitorPlaybackState.playing
            : status.playbackState == DigitorPlaybackState.playing,
        position: Duration(microseconds: positionUs),
        duration: Duration(microseconds: durationUs),
        state: <String, Object?>{
          'backend': _w.renderer.backendName,
          'device': _w.renderer.deviceName,
          'isGpu': _w.renderer.isGpu,
          'mediaPath': hasEditTimeline ? active?.sourcePath : _mediaPath,
          'timelineClips': _editTimeline.clips
              .map((clip) => clip.toState())
              .toList(growable: false),
          'timelineClipCount': _editTimeline.length,
          'selectedClipId': selected?.id,
          'activeClipId': active?.id,
          'canSplitSelected': selected != null &&
              _editTimeline.canSplit(selected.id, positionUs),
          'recipeIdentity': _w.recipeIdentity,
          'graphRevision': _w.graphRevision,
          'parameterRevision': _w.parameterRevision,
          'productionHostRegistered': _w.productionHostRegistered,
          'productionReady': hasEditTimeline ? _w.productionReady : _w.productionReady,
          'previewTextureId': hasEditTimeline || _mediaPath != null
              ? _previewTextureId
              : null,
          'previewWidth': _previewWidth,
          'previewHeight': _previewHeight,
          'previewGeneration': _previewGeneration,
        },
        engineMessage: message,
      ),
    );
  }
'''
text = replace_block(
    text,
    "  void _emitSnapshot({String? message}) {",
    "  void _event(String type, Map<String, Object?> payload) {",
    new_snapshot,
)

gateway_path.write_text(text)

screen_path = Path("lib/features/editor/presentation/mobile_editor_screen.dart")
screen = screen_path.read_text()
old = '''                          onEdit: () =>
                              _selectWorkspace(EngineWorkspace.edit),
                          onSeekUs: (value) => unawaited(
                            _dispatch(
                              'playback.transport',
                              'seek',
                              value,
                            ),
                          ),'''
new = '''                          onEdit: () =>
                              _selectWorkspace(EngineWorkspace.edit),
                          onSeekUs: (value) => unawaited(
                            _dispatch(
                              'playback.transport',
                              'seek',
                              value,
                            ),
                          ),
                          onSelectClip: (clipId) => unawaited(
                            _dispatch('timeline.clip', 'select', clipId),
                          ),
                          onSplitSelected: () => unawaited(
                            _dispatch('timeline.clip', 'split'),
                          ),
                          onDeleteSelected: () => unawaited(
                            _dispatch('timeline.clip', 'deleteSelected'),
                          ),'''
screen = replace_once(screen, old, new)
screen_path.write_text(screen)
