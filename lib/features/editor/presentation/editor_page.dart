import 'dart:io';
import 'package:digitor/features/editor/application/editor_controller.dart';
import 'package:digitor/features/editor/application/editor_tool_controller.dart';
import 'package:digitor/features/editor/application/timeline_provider.dart';
import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/application/video_clip.dart';
import 'package:digitor/features/editor/application/video_thumbnail_generator.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
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
  late final EditorToolController _toolController;

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
    _toolController = EditorToolController();

    if (widget.media != null) {
      _controller.loadMedia(widget.media!);
      _projectController.addVideoWithLinkedAudio(videoTrackId: 'primary-video', path: widget.media!.path, duration: widget.media!.duration, hasAudio: false);
      _playbackController.replaceMedia(widget.media!.path);
    }

    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    if (widget.media == null || !widget.media!.isVideo) return;

    await _timelineProvider.loadVideo(
      video: File(widget.media!.path),
      duration: widget.media!.duration,
    );
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.media != widget.media && widget.media != null) {
      _controller.loadMedia(widget.media!);
      _loadTimeline();
      _playbackController.replaceMedia(widget.media!.path);
    }
  }

  @override
  void dispose() {
    _timelineProvider.dispose();
    _timelineController.dispose();
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
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          children: [
                            Expanded(
                              flex: 5,
                              child: ListenableBuilder(
                                listenable: Listenable.merge([_controller, _projectController]),
                                builder: (context, _) {
                                  final session = _controller.session;

                                  if (session == null || !_projectController.hasClips) return const EmptyPreviewArea();

                                  return PreviewArea(session: session, playbackController: _playbackController);
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(height: 220, child: TimelineView(controller: _projectController, timelineController: _timelineController, playbackController: _playbackController)),
                            const SizedBox(height: 8),
                            SizedBox(height: 128, child: EditorToolbar(tools: _toolController, project: _projectController, timeline: _timelineController)),
                          ],
                        ),
                      ),
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
