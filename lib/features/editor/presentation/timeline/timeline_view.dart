import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/services/media_picker_service.dart';
import '../../application/media_metadata_service.dart';
import '../../application/playback_controller.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import '../../domain/models/timeline_track.dart';
import 'timeline_canvas.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';
import 'track_header_column.dart';

/// A single horizontal canvas keeps ruler, clips, and playhead aligned.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.controller,
    required this.timelineController,
    required this.playbackController,
  });

  final ProjectController controller;
  final TimelineController timelineController;
  final PlaybackController playbackController;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  late final TimelineScrollController _scroll;
  final MediaPickerService _picker = MediaPickerService();
  final MediaMetadataService _metadata = VideoPlayerMediaMetadataService();

  @override
  void initState() {
    super.initState();
    _scroll = TimelineScrollController()
      ..horizontal.addListener(_onScroll)
      ..synchronizeVerticalScrollers();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.horizontal.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final timelineViewportWidth =
            (constraints.maxWidth - TimelineConstants.headerWidth)
                .clamp(1.0, double.infinity)
                .toDouble();

        return AnimatedBuilder(
          animation: Listenable.merge([
            widget.controller,
            widget.timelineController,
          ]),
          builder: (context, _) => Column(
            children: [
              _Toolbar(
                controller: widget.timelineController,
                projectController: widget.controller,
                onZoomIn: () => _changeZoom(widget.timelineController.zoomIn),
                onZoomOut: () => _changeZoom(widget.timelineController.zoomOut),
                onFit: () => _fitTimeline(timelineViewportWidth),
              ),
              const Divider(height: 1),
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (_) => false,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: TimelineConstants.headerWidth,
                          ),
                          child: TimelineCanvas(
                            projectController: widget.controller,
                            timelineController: widget.timelineController,
                            scrollController: _scroll,
                            playbackController: widget.playbackController,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: TimelineConstants.headerWidth,
                        child: TrackHeaderColumn(
                          tracks: widget.controller.tracks,
                          verticalController: _scroll.headerVertical,
                          onAdd: _showTrackAddMenu,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeZoom(VoidCallback change) {
    final oldPixelsPerSecond = widget.timelineController.pixelsPerSecond;
    final oldPlayheadX = TimelineMath.durationToPixels(
      widget.timelineController.position,
      oldPixelsPerSecond,
    );
    final oldOffset = _scroll.horizontal.hasClients
        ? _scroll.horizontal.offset
        : 0.0;
    final playheadViewportX = oldPlayheadX - oldOffset;

    change();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.horizontal.hasClients) return;
      final newPlayheadX = TimelineMath.durationToPixels(
        widget.timelineController.position,
        widget.timelineController.pixelsPerSecond,
      );
      final targetOffset = (newPlayheadX - playheadViewportX).clamp(
        0.0,
        _scroll.horizontal.position.maxScrollExtent,
      );
      _scroll.horizontal.jumpTo(targetOffset.toDouble());
    });
  }

  void _fitTimeline(double viewportWidth) {
    widget.timelineController.fitToWidth(viewportWidth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.horizontal.hasClients) {
        _scroll.horizontal.jumpTo(0);
      }
    });
  }

  Future<void> _showTrackAddMenu(TimelineTrack track) async {
    if (track.locked) return;
    if (track.type.name == 'audio') {
      final file = await _picker.pickAudio();
      if (!mounted || file == null) return;
      final duration = await _metadata.probeAudioDuration(file.path);
      if (!mounted) return;
      if (duration == null || duration <= Duration.zero) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read this audio file.')),
        );
        return;
      }
      widget.timelineController.addAudioClip(
        trackId: track.id,
        path: file.path,
        duration: duration,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _addOption(sheetContext, track, Icons.videocam_outlined, 'Video'),
            _addOption(sheetContext, track, Icons.image_outlined, 'Image'),
            _addOption(sheetContext, track, Icons.text_fields, 'Text'),
            _addOption(sheetContext, track, Icons.layers_outlined, 'Overlay'),
          ],
        ),
      ),
    );
  }

  Widget _addOption(
    BuildContext context,
    TimelineTrack track,
    IconData icon,
    String label,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () async {
        Navigator.pop(context);
        await _addToVideoTrack(track, label);
      },
    );
  }

  Future<void> _addToVideoTrack(TimelineTrack track, String kind) async {
    try {
      if (kind == 'Text') {
        widget.timelineController.addTextClip(
          trackId: track.id,
          text: 'Text',
        );
        return;
      }

      final file = kind == 'Video'
          ? await _picker.pickVideo()
          : await _picker.pickImage();
      if (!mounted || file == null) return;

      if (kind == 'Video') {
        final metadata = await _metadata.probeVideo(file.path);
        if (!mounted || metadata == null) return;
        widget.timelineController.addVideoWithLinkedAudio(
          trackId: track.id,
          path: file.path,
          duration: metadata.duration,
          hasAudio: metadata.hasAudio,
        );
      } else if (kind == 'Image') {
        widget.timelineController.addImageClip(
          trackId: track.id,
          path: file.path,
          duration: const Duration(seconds: 3),
        );
      } else {
        widget.timelineController.addOverlayClip(
          trackId: track.id,
          path: file.path,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to add this media file.')),
        );
      }
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.projectController,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final TimelineController controller;
  final ProjectController projectController;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final zoomPercent =
        controller.pixelsPerSecond / TimelineConstants.pixelsPerSecond * 100;
    final zoomLabel = zoomPercent >= 10
        ? '${zoomPercent.round()}%'
        : '${zoomPercent.toStringAsFixed(1)}%';

    return SizedBox(
      height: TimelineConstants.toolbarHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: TimelineConstants.headerWidth),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(width: 58, child: Center(child: Text(zoomLabel))),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: onZoomIn,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Fit entire timeline',
              onPressed: onFit,
              icon: const Icon(Icons.fit_screen_outlined),
            ),
            IconButton(
              tooltip: 'New video track',
              onPressed: controller.addVideoTrack,
              icon: const Icon(Icons.video_call_outlined),
            ),
            IconButton(
              tooltip: 'New audio track',
              onPressed: controller.addAudioTrack,
              icon: const Icon(Icons.library_music_outlined),
            ),
            if (projectController.selectedClipId != null &&
                projectController
                    .getLinkedClips(projectController.selectedClipId!)
                    .isNotEmpty)
              IconButton(
                tooltip: 'Unlink clips',
                onPressed: () => controller.unlinkClipGroup(
                  projectController.selectedClipId!,
                ),
                icon: const Icon(Icons.link_off),
              ),
            TextButton(
              onPressed: () => controller.setPosition(Duration.zero),
              child: const Text('00:00'),
            ),
          ],
        ),
      ),
    );
  }
}
