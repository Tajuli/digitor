import 'package:digitor/features/editor/application/editor_tool_controller.dart';
import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:flutter/material.dart';

/// Two-level tool surface. Tool selection is independent from timeline selection.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tools,
    required this.project,
    required this.timeline,
    required this.onExport,
    required this.onOpenNodes,
    required this.onOpenColorWheels,
    required this.onOpenCurves,
    required this.onOpenQualifier,
  });

  final EditorToolController tools;
  final ProjectController project;
  final TimelineController timeline;
  final VoidCallback onExport;
  final VoidCallback onOpenNodes;
  final VoidCallback onOpenColorWheels;
  final VoidCallback onOpenCurves;
  final VoidCallback onOpenQualifier;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([tools, project]),
      builder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SubToolbar(tools: tools, project: project, timeline: timeline, onOpenNodes: onOpenNodes, onOpenColorWheels: onOpenColorWheels, onOpenCurves: onOpenCurves, onOpenQualifier: onOpenQualifier),
          const Divider(height: 1),
          SizedBox(
            height: 70,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _main(context, EditorToolType.edit, Icons.edit_outlined, 'Edit'),
                _main(context, EditorToolType.color, Icons.tune, 'Color'),
                _main(
                  context,
                  EditorToolType.filter,
                  Icons.filter_alt_outlined,
                  'Filter',
                ),
                _main(
                  context,
                  EditorToolType.effect,
                  Icons.auto_awesome_outlined,
                  'Effect',
                ),
                _main(context, EditorToolType.audio, Icons.audiotrack, 'Audio'),
                _ActionTool(
                  icon: Icons.file_upload_outlined,
                  label: 'Export',
                  onTap: onExport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _main(BuildContext context, EditorToolType type, IconData icon, String label) {
    return _ActionTool(
      icon: icon,
      label: label,
      selected: tools.selected == type,
      onTap: () => tools.select(type),
    );
  }
}

class _SubToolbar extends StatelessWidget {
  const _SubToolbar({
    required this.tools,
    required this.project,
    required this.timeline,
    required this.onOpenNodes,
    required this.onOpenColorWheels,
    required this.onOpenCurves,
    required this.onOpenQualifier,
  });

  final EditorToolController tools;
  final ProjectController project;
  final TimelineController timeline;
  final VoidCallback onOpenNodes;
  final VoidCallback onOpenColorWheels;
  final VoidCallback onOpenCurves;
  final VoidCallback onOpenQualifier;

  @override
  Widget build(BuildContext context) {
    final clip = project.selectedClip;
    final visual = project.supportsVisualTools(clip);
    final audio = project.supportsAudioControls(clip);
    final linked = clip != null && project.isLinked(clip.id);

    final List<Widget> actions = switch (tools.selected) {
      EditorToolType.edit => _editActions(context, clip, linked),
      EditorToolType.color => _colorActions(clip, visual),
      EditorToolType.filter => ClipFilterType.values
          .map(
            (value) => _button(
              value == ClipFilterType.none ? 'Original' : value.name,
              Icons.filter,
              visual,
              () {
                if (clip != null) timeline.updateClip(clip.copyWith(filter: value));
              },
              active: clip?.filter == value,
            ),
          )
          .toList(),
      EditorToolType.effect => ClipEffectType.values
          .map(
            (value) => _button(
              value.name,
              Icons.auto_awesome,
              visual,
              () {
                if (clip != null) timeline.updateClip(clip.copyWith(effect: value));
              },
              active: clip?.effect == value,
            ),
          )
          .toList(),
      EditorToolType.audio => _audioActions(context, clip, audio, linked),
    };

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (!visual &&
              (tools.selected == EditorToolType.color ||
                  tools.selected == EditorToolType.filter ||
                  tools.selected == EditorToolType.effect))
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select a visual clip'),
            ),
          ...actions,
        ],
      ),
    );
  }

  List<Widget> _editActions(BuildContext context, TimelineClip? clip, bool linked) {
    final selectedTrackId = project.selectedTrackId;
    return [
      _button('Split', Icons.content_cut, clip != null && selectedTrackId != null, () {
        if (clip == null || selectedTrackId == null) return;
        timeline.splitClip(trackId: selectedTrackId, clipId: clip.id, position: timeline.position);
      }),
      _button(
        'Magnet',
        Icons.grid_on,
        true,
        tools.toggleMagnet,
        active: tools.magnetEnabled,
      ),
      _button('Speed', Icons.speed, clip != null, _unsupported(context)),
      _button('Duplicate', Icons.copy, clip != null, _unsupported(context)),
      _button('Delete', Icons.delete_outline, clip != null, timeline.deleteSelectedClip),
      _button(
        linked
            ? 'Unlink'
            : project.isLinkSelectionActive
                ? 'Cancel Link'
                : 'Link',
        linked
            ? Icons.link_off
            : project.isLinkSelectionActive
                ? Icons.close
                : Icons.link,
        clip != null,
        () {
          if (clip == null) return;
          if (linked) {
            timeline.unlinkClipGroup(clip.id);
          } else if (project.isLinkSelectionActive) {
            project.cancelLinkSelection();
          } else {
            project.beginLinkSelection(clip.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tap an unlinked audio or video clip to link.')),
            );
          }
        },
      ),
    ];
  }

  List<Widget> _audioActions(
    BuildContext context,
    TimelineClip? clip,
    bool audio,
    bool linked,
  ) {
    final isVideo = clip?.type.name == 'video';
    final audioClip = audio ? clip : null;
    return [
      if (audioClip != null)
        _button(audioClip.muted ? 'Unmute' : 'Mute', Icons.volume_off, true, () {
          timeline.updateClip(audioClip.copyWith(muted: !audioClip.muted));
        }),
      _button('Volume', Icons.volume_up, audio, _unsupported(context)),
      _button('Fade In', Icons.trending_up, audio, _unsupported(context)),
      _button('Fade Out', Icons.trending_down, audio, _unsupported(context)),
      _button('Extract Audio', Icons.graphic_eq, isVideo && !linked, _unsupported(context)),
      _button('Voice', Icons.mic_none, clip == null, _unsupported(context)),
    ];
  }

  List<Widget> _colorActions(TimelineClip? clip, bool enabled) {
    final selectedNode = clip?.colorNodeGraph.selectedProcessingNode;
    final canGrade = enabled && selectedNode != null;
    return [
      _button('Color Wheels', Icons.color_lens_outlined, canGrade, onOpenColorWheels),
      _button('Curves', Icons.show_chart_rounded, canGrade, onOpenCurves),
      _button('Node', Icons.account_tree_outlined, enabled, onOpenNodes),
      _button('Qualifier HSL', Icons.colorize_outlined, canGrade, onOpenQualifier),
      _button('Reset', Icons.restart_alt, canGrade, () {
        if (clip == null || selectedNode == null) return;
        final graph = clip.colorNodeGraph;
        final updatedGraph = graph.copyWith(
          nodes: graph.nodes
              .map(
                (node) => node.id == selectedNode.id
                    ? node.copyWith(grade: const ClipColorAdjustments())
                    : node,
              )
              .toList(),
        );
        timeline.updateClip(
          clip.copyWith(
            colorNodeGraph: updatedGraph,
            colorAdjustments: updatedGraph.combinedGrade,
          ),
        );
      }),
    ];
  }

  void _nudgeSelectedNode(TimelineClip clip, String field) {
    final graph = clip.colorNodeGraph;
    final selectedNode = graph.selectedProcessingNode;
    if (selectedNode == null) return;
    final value = selectedNode.grade;
    final next = switch (field) {
      'Exposure' => value.copyWith(exposure: (value.exposure + .1).clamp(-1.0, 1.0).toDouble()),
      'Contrast' => value.copyWith(contrast: (value.contrast + .1).clamp(-1.0, 1.0).toDouble()),
      'Saturation' => value.copyWith(saturation: (value.saturation + .1).clamp(-1.0, 1.0).toDouble()),
      'Temperature' => value.copyWith(temperature: (value.temperature + .1).clamp(-1.0, 1.0).toDouble()),
      'Tint' => value.copyWith(tint: (value.tint + .1).clamp(-1.0, 1.0).toDouble()),
      'Highlights' => value.copyWith(highlights: (value.highlights + .1).clamp(-1.0, 1.0).toDouble()),
      _ => value.copyWith(shadows: (value.shadows + .1).clamp(-1.0, 1.0).toDouble()),
    };
    final updatedGraph = graph.copyWith(
      nodes: graph.nodes
          .map(
            (node) => node.id == selectedNode.id
                ? node.copyWith(grade: next)
                : node,
          )
          .toList(),
    );
    timeline.updateClip(
      clip.copyWith(
        colorNodeGraph: updatedGraph,
        colorAdjustments: updatedGraph.combinedGrade,
      ),
    );
  }

  VoidCallback _unsupported(BuildContext context) {
    return () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This control is ready for renderer integration.')),
        );
  }

  Widget _button(
    String label,
    IconData icon,
    bool enabled,
    VoidCallback action, {
    bool active = false,
  }) {
    return _ActionTool(
      icon: icon,
      label: label,
      selected: active,
      enabled: enabled,
      onTap: action,
    );
  }
}

class _ActionTool extends StatelessWidget {
  const _ActionTool({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 5,
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
