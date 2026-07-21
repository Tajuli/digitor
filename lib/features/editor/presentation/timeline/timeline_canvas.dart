import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/playback_controller.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import 'playhead.dart';
import 'time_ruler.dart';
import 'timeline_body.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';
import '../../domain/models/timeline_clip.dart';

class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({super.key, required this.projectController, required this.timelineController, required this.scrollController, required this.playbackController});
  final ProjectController projectController;
  final TimelineController timelineController;
  final TimelineScrollController scrollController;
  final PlaybackController playbackController;
  @override State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas> {
  TimelineClip? _clipboard;
  _ClipboardAttribute? _clipboardAttribute;
  Timer? _autoScroll;
  bool _scrubbing = false;
  double _scrubX = 0;
  @override void dispose() { _autoScroll?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final project = widget.projectController.project;
    return LayoutBuilder(builder: (context, constraints) {
      final width = TimelineMath.durationToPixels(project.duration, widget.timelineController.pixelsPerSecond)
          .clamp(constraints.maxWidth, double.infinity).toDouble();
      final playheadX = TimelineMath.durationToPixels(widget.timelineController.position, widget.timelineController.pixelsPerSecond);
      return Listener(
        onPointerMove: (event) => _autoScrollAt(event.position),
        onPointerUp: (_) => _autoScroll?.cancel(),
        child: SingleChildScrollView(
          controller: widget.scrollController.horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Stack(children: [
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTapUp: (details) { if (!_scrubbing) { widget.projectController.clearSelection(); _seek(widget.timelineController.snapPlayhead(TimelineMath.pixelsToDuration(details.localPosition.dx, widget.timelineController.pixelsPerSecond))); } })),
              Column(children: [
                TimeRuler(duration: project.duration, pixelsPerSecond: widget.timelineController.pixelsPerSecond),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: widget.scrollController.vertical,
                    child: TimelineBody(tracks: project.tracks, width: width, projectController: widget.projectController, timelineController: widget.timelineController, onMoveEnd: _moveEnd, onContextMenu: _showContextMenu),
                  ),
                ),
              ]),
              Positioned(
                left: playheadX - TimelineConstants.playheadHitWidth / 2,
                top: 0,
                child: Playhead(
                  height: constraints.maxHeight,
                  onScrubStart: () {
                    _scrubbing = true;
                    _scrubX = playheadX;
                    widget.playbackController.beginScrub();
                  },
                  onScrubDelta: (deltaX) {
                    _scrubX = (_scrubX + deltaX).clamp(0.0, width);
                    _scrub(
                      widget.timelineController.snapPlayhead(
                        TimelineMath.pixelsToDuration(
                          _scrubX,
                          widget.timelineController.pixelsPerSecond,
                        ),
                      ),
                    );
                  },
                  onScrubEnd: () async {
                    final position = widget.timelineController.position;
                    _seek(position);
                    await widget.playbackController.endScrub(position);
                    _scrubbing = false;
                  },
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
  void _scrub(Duration value) { widget.timelineController.setPosition(value); widget.playbackController.scrubTo(widget.timelineController.position); }
  void _seek(Duration value) { widget.timelineController.setPosition(value); }
  void _moveEnd(String clipId, String fromTrackId, Duration start, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final y = box.globalToLocal(globalPosition).dy - TimelineConstants.rulerHeight - 1 + widget.scrollController.vertical.offset;
    if (widget.projectController.tracks.isEmpty) return;
    final index = (y / TimelineConstants.trackHeight)
        .floor()
        .clamp(0, widget.projectController.tracks.length - 1) as int;
    widget.timelineController.moveClip(clipId: clipId, fromTrackId: fromTrackId, toTrackId: widget.projectController.tracks[index].id, start: start);
  }
  void _autoScrollAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final edge = TimelineConstants.autoScrollEdge;
    final horizontal = local.dx < edge ? -1.0 : local.dx > box.size.width - edge ? 1.0 : 0.0;
    final vertical = local.dy < edge ? -1.0 : local.dy > box.size.height - edge ? 1.0 : 0.0;
    _autoScroll?.cancel();
    if (horizontal == 0 && vertical == 0) return;
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _scrollBy(widget.scrollController.horizontal, horizontal * 8);
      _scrollBy(widget.scrollController.vertical, vertical * 6);
    });
  }
  void _scrollBy(ScrollController controller, double amount) { if (controller.hasClients && amount != 0) controller.jumpTo((controller.offset + amount).clamp(0.0, controller.position.maxScrollExtent)); }
  Future<void> _showContextMenu(TimelineClip clip, String trackId, Offset _) async {
    widget.projectController.selectClip(trackId: trackId, clipId: clip.id);
    final action = await showModalBottomSheet<_ClipMenuAction>(
      context: context,
      builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
        for (final item in _ClipMenuAction.values.where((item) => item != _ClipMenuAction.paste || _clipboard != null))
          ListTile(title: Text(item.label), onTap: () => Navigator.pop(context, item)),
      ])),
    );
    if (action == null) return;
    if (action.attribute != null) { _clipboard = clip; _clipboardAttribute = action.attribute; return; }
    switch (action) {
      case _ClipMenuAction.copy:
        _clipboard = clip;
        _clipboardAttribute = _ClipboardAttribute.all;
        return;
      case _ClipMenuAction.delete:
        widget.timelineController.deleteSelectedClip();
        return;
      case _ClipMenuAction.split:
        widget.timelineController.splitClip(trackId: trackId, clipId: clip.id, position: widget.timelineController.position);
        return;
      case _ClipMenuAction.duplicate:
        widget.timelineController.addClipCopy(trackId: trackId, clip: clip);
        return;
      case _ClipMenuAction.paste:
        _paste(clip);
        return;
      default:
        return;
    }
  }
  void _paste(TimelineClip target) {
    final source = _clipboard; final attribute = _clipboardAttribute;
    if (source == null || attribute == null) return;
    final replacement = switch (attribute) {
      _ClipboardAttribute.position => target.copyWith(position: source.position),
      _ClipboardAttribute.scale => target.copyWith(scale: source.scale),
      _ClipboardAttribute.rotation => target.copyWith(rotation: source.rotation),
      _ClipboardAttribute.opacity => target.copyWith(opacity: source.opacity),
      _ClipboardAttribute.effects => target.copyWith(effect: source.effect, filter: source.filter),
      _ClipboardAttribute.color => target.copyWith(colorAdjustments: source.colorAdjustments),
      _ClipboardAttribute.speed => target.copyWith(data: {...target.data, 'speed': source.data['speed']}),
      _ClipboardAttribute.volume => target.copyWith(volume: source.volume, muted: source.muted),
      _ClipboardAttribute.transform => target.copyWith(position: source.position, scale: source.scale, rotation: source.rotation, opacity: source.opacity),
      _ClipboardAttribute.animation => target.copyWith(data: {...target.data, 'animation': source.data['animation']}),
      _ClipboardAttribute.all => target.copyWith(position: source.position, scale: source.scale, rotation: source.rotation, opacity: source.opacity, colorAdjustments: source.colorAdjustments, filter: source.filter, effect: source.effect, volume: source.volume, muted: source.muted, data: {...target.data, ...source.data}),
    };
    widget.timelineController.updateClip(replacement);
  }

}


enum _ClipboardAttribute { position, scale, rotation, opacity, effects, color, animation, speed, volume, transform, all }
enum _ClipMenuAction {
  copy, copyPosition, copyScale, copyRotation, copyOpacity, copyEffects, copyColor, copyAnimation, copySpeed, copyVolume, copyTransform, copyAll, duplicate, delete, split, paste;
  _ClipboardAttribute? get attribute => switch (this) { copy => _ClipboardAttribute.all, copyPosition => _ClipboardAttribute.position, copyScale => _ClipboardAttribute.scale, copyRotation => _ClipboardAttribute.rotation, copyOpacity => _ClipboardAttribute.opacity, copyEffects => _ClipboardAttribute.effects, copyColor => _ClipboardAttribute.color, copyAnimation => _ClipboardAttribute.animation, copySpeed => _ClipboardAttribute.speed, copyVolume => _ClipboardAttribute.volume, copyTransform => _ClipboardAttribute.transform, copyAll => _ClipboardAttribute.all, _ => null };
  String get label => switch (this) { copy => 'Copy', copyPosition => 'Copy Position', copyScale => 'Copy Scale', copyRotation => 'Copy Rotation', copyOpacity => 'Copy Opacity', copyEffects => 'Copy Effects', copyColor => 'Copy Color', copyAnimation => 'Copy Animation', copySpeed => 'Copy Speed', copyVolume => 'Copy Volume', copyTransform => 'Copy Transform', copyAll => 'Copy All Attributes', duplicate => 'Duplicate', delete => 'Delete', split => 'Split', paste => 'Paste' };
}
