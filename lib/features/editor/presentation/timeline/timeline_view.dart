import 'package:flutter/material.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import 'timeline_canvas.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';
import 'track_header_column.dart';

/// A single horizontal canvas keeps ruler, clips, and playhead perfectly aligned.
class TimelineView extends StatefulWidget { const TimelineView({super.key, required this.controller, required this.timelineController}); final ProjectController controller; final TimelineController timelineController; @override State<TimelineView> createState() => _TimelineViewState(); }
class _TimelineViewState extends State<TimelineView> { late final TimelineScrollController _scroll; @override void initState() { super.initState(); _scroll = TimelineScrollController()..horizontal.addListener(_onScroll); } void _onScroll() { if (mounted) setState(() {}); } @override void dispose() { _scroll.horizontal.removeListener(_onScroll); _scroll.dispose(); super.dispose(); }
@override Widget build(BuildContext context) => AnimatedBuilder(animation: Listenable.merge([widget.controller, widget.timelineController]), builder: (context, _) => Column(children: [_Toolbar(controller: widget.timelineController), const Divider(height: 1), Expanded(child: Stack(children: [TimelineCanvas(projectController: widget.controller, timelineController: widget.timelineController, scrollController: _scroll), IgnorePointer(child: Transform.translate(offset: Offset(_scroll.horizontal.hasClients ? _scroll.horizontal.offset : 0, 0), child: TrackHeaderColumn(tracks: widget.controller.tracks)))]))])); }
class _Toolbar extends StatelessWidget { const _Toolbar({required this.controller}); final TimelineController controller; @override Widget build(BuildContext context) => SizedBox(height: TimelineConstants.toolbarHeight, child: Row(children: [const SizedBox(width: TimelineConstants.headerWidth), IconButton(tooltip: 'Zoom out', onPressed: controller.zoomOut, icon: const Icon(Icons.remove)), Text('${(controller.pixelsPerSecond / TimelineConstants.pixelsPerSecond * 100).round()}%'), IconButton(tooltip: 'Zoom in', onPressed: controller.zoomIn, icon: const Icon(Icons.add)), const Spacer(), TextButton(onPressed: () => controller.setPosition(Duration.zero), child: const Text('00:00'))])); }
