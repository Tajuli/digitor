import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../application/playback_controller.dart';
import '../../application/media_metadata_service.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../domain/models/timeline_track.dart';
import 'timeline_canvas.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';
import 'track_header_column.dart';
import '../../../../core/services/media_picker_service.dart';

/// A single horizontal canvas keeps ruler, clips, and playhead perfectly aligned.
class TimelineView extends StatefulWidget {
  const TimelineView({super.key, required this.controller, required this.timelineController, required this.playbackController});
  final ProjectController controller;
  final TimelineController timelineController;
  final PlaybackController playbackController;
  @override State<TimelineView> createState() => _TimelineViewState();
}
class _TimelineViewState extends State<TimelineView> {
  late final TimelineScrollController _scroll;
  bool _manualScroll = false;
  final MediaPickerService _picker = MediaPickerService();
  final MediaMetadataService _metadata = VideoPlayerMediaMetadataService();
  @override void initState() { super.initState(); _scroll = TimelineScrollController()..horizontal.addListener(_onScroll)..synchronizeVerticalScrollers(); }
  void _onScroll() { if (mounted) setState(() {}); }
  @override void dispose() { _scroll.horizontal.removeListener(_onScroll); _scroll.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.timelineController]),
    builder: (context, _) => Column(children: [
      _Toolbar(controller: widget.timelineController, projectController: widget.controller), const Divider(height: 1),
      Expanded(child: NotificationListener<UserScrollNotification>(onNotification: (n) { _manualScroll = n.direction != ScrollDirection.idle; return false; }, child: Stack(children: [
        Positioned.fill(child: Padding(padding: const EdgeInsets.only(left: TimelineConstants.headerWidth), child: TimelineCanvas(projectController: widget.controller, timelineController: widget.timelineController, scrollController: _scroll, playbackController: widget.playbackController))),
        Positioned(left: 0, top: 0, bottom: 0, width: TimelineConstants.headerWidth, child: TrackHeaderColumn(tracks: widget.controller.tracks, verticalController: _scroll.headerVertical, onAdd: _showTrackAddMenu)),
      ]))),
    ]),
  );
  Future<void> _showTrackAddMenu(TimelineTrack track) async {
    if (track.locked) return;
    if (track.type.name == 'audio') {
      final file = await _picker.pickAudio();
      if (!mounted || file == null) return;
      widget.timelineController.addAudioClip(trackId: track.id, path: file.path, duration: const Duration(seconds: 3));
      return;
    }
    await showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      _addOption(sheetContext, track, Icons.videocam_outlined, 'Video'),
      _addOption(sheetContext, track, Icons.image_outlined, 'Image'),
      _addOption(sheetContext, track, Icons.text_fields, 'Text'),
      _addOption(sheetContext, track, Icons.layers_outlined, 'Overlay'),
    ])));
  }
  Widget _addOption(BuildContext context, TimelineTrack track, IconData icon, String label) => ListTile(leading: Icon(icon), title: Text(label), onTap: () async { Navigator.pop(context); await _addToVideoTrack(track, label); });
  Future<void> _addToVideoTrack(TimelineTrack track, String kind) async {
    try {
      if (kind == 'Text') { widget.timelineController.addTextClip(trackId: track.id, text: 'Text'); return; }
      final file = kind == 'Video' ? await _picker.pickVideo() : await _picker.pickImage();
      if (!mounted || file == null) return;
      if (kind == 'Video') {
        final metadata = await _metadata.probeVideo(file.path);
        if (!mounted || metadata == null) return;
        widget.timelineController.addVideoWithLinkedAudio(trackId: track.id, path: file.path, duration: metadata.duration, hasAudio: metadata.hasAudio);
      } else if (kind == 'Image') {
        widget.timelineController.addImageClip(trackId: track.id, path: file.path, duration: const Duration(seconds: 3));
      } else {
        widget.timelineController.addOverlayClip(trackId: track.id, path: file.path, duration: const Duration(seconds: 3));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to add this media file.')));
    }
  }
}
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.projectController}); final TimelineController controller; final ProjectController projectController;
  @override Widget build(BuildContext context) => SizedBox(height: TimelineConstants.toolbarHeight, child: Row(children: [
    const SizedBox(width: TimelineConstants.headerWidth), IconButton(tooltip: 'Zoom out', onPressed: controller.zoomOut, icon: const Icon(Icons.remove)), Text('${(controller.pixelsPerSecond / TimelineConstants.pixelsPerSecond * 100).round()}%'), IconButton(tooltip: 'Zoom in', onPressed: controller.zoomIn, icon: const Icon(Icons.add)),
    IconButton(tooltip: 'New video track', onPressed: controller.addVideoTrack, icon: const Icon(Icons.video_call_outlined)), IconButton(tooltip: 'New audio track', onPressed: controller.addAudioTrack, icon: const Icon(Icons.library_music_outlined)), if (projectController.selectedClipId != null && projectController.getLinkedClips(projectController.selectedClipId!).isNotEmpty) IconButton(tooltip: 'Unlink clips', onPressed: () => controller.unlinkClipGroup(projectController.selectedClipId!), icon: const Icon(Icons.link_off)), const Spacer(), TextButton(onPressed: () => controller.setPosition(Duration.zero), child: const Text('00:00')),
  ]));
}
