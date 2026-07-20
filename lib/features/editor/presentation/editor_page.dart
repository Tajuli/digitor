import 'dart:io';
import 'package:digitor/features/editor/application/editor_controller.dart';
import 'package:digitor/features/editor/application/editor_tool_controller.dart';
import 'package:digitor/features/editor/application/timeline_provider.dart';
import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/application/timeline_audio_playback_controller.dart';
import 'package:digitor/features/editor/application/timeline_render_resolver.dart';
import 'package:digitor/features/editor/application/video_thumbnail_generator.dart';
import 'package:digitor/features/editor/application/media_metadata_service.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:digitor/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:digitor/features/editor/presentation/widgets/preview_area.dart';
import 'package:digitor/features/editor/presentation/timeline/timeline_view.dart';
import 'package:flutter/material.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.media,
  });

  final MediaItem? media;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorController _controller;
  late final TimelineProvider _timelineProvider;
  late final ProjectController _projectController;
  late final TimelineController _timelineController;
  late final PlaybackController _playbackController;
  late final TimelineAudioPlaybackController _audioPlaybackController;
  late final EditorToolController _toolController;
  final MediaMetadataService _metadataService = VideoPlayerMediaMetadataService();
  String? _activeClipId;

  @override
  void initState() {
    super.initState();

    _controller = EditorController();
    if (widget.media != null) _controller.loadMedia(widget.media!);

    _timelineProvider = TimelineProvider(
      generator: VideoThumbnailGenerator(),
    );
    _projectController = ProjectController(project: EditorProject(
      duration: Duration.zero,
      tracks: [
        TimelineTrack(id: 'primary-video', name: 'Video 1', type: TrackType.video),
        TimelineTrack(id: 'primary-audio', name: 'Audio 1', type: TrackType.audio),
      ],
    ));
    _timelineController = TimelineController(projectController: _projectController);
    _playbackController = PlaybackController();
    _audioPlaybackController = TimelineAudioPlaybackController();
    _toolController = EditorToolController();

    _timelineController.addListener(_syncPreviewForTimeline);
    _projectController.addListener(_syncPreviewForTimeline);
    _playbackController.addListener(_syncTimelineForPlayback);
    _toolController.addListener(_syncMagnetState);

    if (widget.media != null) _importInitialMedia(widget.media!);

    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    if (widget.media == null || !widget.media!.isVideo) return;

    await _timelineProvider.loadVideo(
      video: File(widget.media!.path),
      duration: widget.media!.duration,
    );
  }

  Future<void> _importInitialMedia(MediaItem media) async {
    if (!media.isVideo) return;
    final metadata = await _metadataService.probeVideo(media.path);
    if (!mounted) return;
    final duration = metadata?.duration ?? media.duration;
    if (duration > Duration.zero) {
      _timelineController.addVideoWithLinkedAudio(
        trackId: 'primary-video',
        path: media.path,
        duration: duration,
        // When stream probing is unavailable, retain the embedded audio path.
        hasAudio: metadata?.hasAudio ?? true,
      );
      _syncPreviewForTimeline();
    }
  }

  void _syncMagnetState() => _timelineController.setMagnetEnabled(_toolController.magnetEnabled);

  void _syncPreviewForTimeline() {
    _syncAudioForTimeline();
    final position = _timelineController.position;
    final visual = TimelineRenderResolver.topVisualClip(
      _projectController.tracks,
      position,
    );
    if (visual == null) {
      _activeClipId = null;
      if (_playbackController.isPlaying) _playbackController.pause();
      return;
    }
    final path = visual.data['path'] as String?;
    if (path == null) return;
    final sourcePosition = position - visual.start + visual.sourceStart;
    if (_activeClipId != visual.id || _playbackController.sourcePath != path) {
      _activeClipId = visual.id;
      _playbackController.replaceMedia(path).then((_) {
        if (mounted && _activeClipId == visual.id) _playbackController.seek(sourcePosition);
      });
    } else if (!_playbackController.isPlaying) {
      _playbackController.seek(sourcePosition);
    }
  }

  void _syncTimelineForPlayback() {
    _syncAudioForTimeline();
    if (_activeClipId == null || !_playbackController.isInitialized) return;
    final clip = _projectController.tracks
        .expand((track) => track.clips)
        .where((clip) => clip.id == _activeClipId)
        .firstOrNull;
    if (clip == null) return;
    final value = clip.start + (_playbackController.position - clip.sourceStart);
    _timelineController.setPosition(value);
  }


  void _syncAudioForTimeline() {
    final position = _timelineController.position;
    final activeAudioClips = TimelineRenderResolver.activeAudioClips(
      _projectController.tracks,
      position,
    );
    _audioPlaybackController.sync(
      activeClips: activeAudioClips,
      timelinePosition: position,
      shouldPlay: _playbackController.isPlaying,
    );
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.media != widget.media && widget.media != null) {
      _controller.loadMedia(widget.media!);
      _loadTimeline();
      _importInitialMedia(widget.media!);
    }
  }

  @override
  void dispose() {
    _timelineController.removeListener(_syncPreviewForTimeline);
    _projectController.removeListener(_syncPreviewForTimeline);
    _playbackController.removeListener(_syncTimelineForPlayback);
    _toolController.removeListener(_syncMagnetState);
    _timelineProvider.dispose();
    _timelineController.dispose();
    _audioPlaybackController.dispose();
    _playbackController.dispose();
    _toolController.dispose();
    _projectController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Editor',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 700 ? 32.0 : 16.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      16,
                    ),
                      child: Column(
                          children: [
                            Expanded(
                              flex: constraints.maxHeight < 560 ? 3 : 5,
                              child: ListenableBuilder(
                                listenable: Listenable.merge([_controller, _projectController]),
                                builder: (context, _) {
                                  final session = _controller.session;
                                  final hasTimelineVideo = _projectController.tracks
                                      .where((track) => track.type == TrackType.video)
                                      .expand((track) => track.clips)
                                      .any((clip) => clip.type == ClipType.video);

                                  if (!_projectController.hasClips && session == null) {
                                    return const EmptyPreviewArea();
                                  }

                                  return PreviewArea(
                                    session: session,
                                    playbackController: _playbackController,
                                    hasTimelineVideo: hasTimelineVideo,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              flex: constraints.maxHeight < 560 ? 3 : 2,
                              child: TimelineView(controller: _projectController, timelineController: _timelineController, playbackController: _playbackController),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(height: 128, child: EditorToolbar(tools: _toolController, project: _projectController, timeline: _timelineController)),
                          ],
                        
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
