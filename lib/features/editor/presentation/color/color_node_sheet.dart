import 'package:digitor/features/editor/application/color/color_node_controller.dart';
import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<ColorNodeGraph?> showColorNodeSheet(
  BuildContext context,
  ColorNodeGraph graph,
) {
  return showModalBottomSheet<ColorNodeGraph>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff111318),
    builder: (_) => FractionallySizedBox(
      heightFactor: .92,
      child: ColorNodeSheet(graph: graph),
    ),
  );
}

class ColorNodeSheet extends StatefulWidget {
  const ColorNodeSheet({
    super.key,
    required this.graph,
    this.embedded = false,
    this.onDone,
  });

  final ColorNodeGraph graph;
  final bool embedded;
  final ValueChanged<ColorNodeGraph>? onDone;

  @override
  State<ColorNodeSheet> createState() => _ColorNodeSheetState();
}

class _ColorNodeSheetState extends State<ColorNodeSheet> {
  late final ColorNodeController controller;

  @override
  void initState() {
    super.initState();
    controller = ColorNodeController(widget.graph);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final selected = controller.graph.nodeById(
          controller.graph.selectedNodeId,
        );
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Color Nodes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          selected.name,
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Delete selected node',
                      onPressed: controller.canDeleteSelected
                          ? controller.deleteSelected
                          : null,
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    IconButton(
                      tooltip: 'Collapse Node Panel',
                      onPressed: () {
                        if (widget.onDone != null) {
                          widget.onDone!(controller.graph);
                        } else {
                          Navigator.pop(context, controller.graph);
                        }
                      },
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.open_with, size: 15, color: Colors.white54),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Press and hold, then drag to move a node. Release without moving to open Add/Delete options. Drag empty space to move around.',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(child: _GraphCanvas(controller: controller)),
            ],
          ),
        );
      },
    );
  }
}

class _GraphCanvas extends StatefulWidget {
  const _GraphCanvas({required this.controller});

  final ColorNodeController controller;

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas> {
  static const Size canvasSize = Size(5000, 3200);
  late final TransformationController transformationController;

  @override
  void initState() {
    super.initState();
    transformationController = TransformationController(
      Matrix4.identity()..translate(-40.0, -40.0),
    );
  }

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: transformationController,
        constrained: false,
        panEnabled: true,
        scaleEnabled: true,
        minScale: .25,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(1800),
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(),
                ),
              ),
              CustomPaint(
                size: canvasSize,
                painter: _ConnectionPainter(widget.controller.graph),
              ),
              ...widget.controller.graph.nodes.map(
                (node) => Positioned(
                  left: node.position.dx,
                  top: node.position.dy,
                  child: _NodeCard(
                    key: ValueKey(node.id),
                    node: node,
                    controller: widget.controller,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatefulWidget {
  const _NodeCard({
    super.key,
    required this.node,
    required this.controller,
  });

  final ColorNode node;
  final ColorNodeController controller;

  @override
  State<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  static const double _moveThreshold = 8;

  Offset? _longPressStartNodePosition;
  Offset? _longPressStartGlobalPosition;
  Offset? _lastGlobalPosition;
  bool _movedDuringLongPress = false;

  ColorNode get node => widget.node;
  ColorNodeController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final selected =
        node.supportsProcessing && controller.graph.selectedNodeId == node.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: node.supportsProcessing ? () => controller.select(node.id) : null,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMove,
      onLongPressEnd: _handleLongPressEnd,
      child: Container(
        width: 124,
        height: 76,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff315f8f) : const Color(0xff252a32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.lightBlueAccent : Colors.white24,
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (node.supportsProcessing)
                  GestureDetector(
                    onTap: () => controller.toggle(node.id),
                    child: Icon(
                      node.enabled ? Icons.visibility : Icons.visibility_off,
                      size: 15,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              _nodeTypeLabel(node.type),
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            if (node.qualifier.enabled)
              const Text(
                'HSL',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    _longPressStartNodePosition = node.position;
    _longPressStartGlobalPosition = details.globalPosition;
    _lastGlobalPosition = details.globalPosition;
    _movedDuringLongPress = false;
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    final startNodePosition = _longPressStartNodePosition;
    final startGlobalPosition = _longPressStartGlobalPosition;
    if (startNodePosition == null || startGlobalPosition == null) return;

    final delta = details.globalPosition - startGlobalPosition;
    if (delta.distance >= _moveThreshold) {
      _movedDuringLongPress = true;
    }
    _lastGlobalPosition = details.globalPosition;
    controller.move(node.id, startNodePosition + delta);
  }

  Future<void> _handleLongPressEnd(LongPressEndDetails details) async {
    final menuPosition = _lastGlobalPosition ?? details.globalPosition;
    final shouldShowMenu = !_movedDuringLongPress;

    _longPressStartNodePosition = null;
    _longPressStartGlobalPosition = null;
    _lastGlobalPosition = null;
    _movedDuringLongPress = false;

    if (!shouldShowMenu) return;
    await _showNodeMenu(menuPosition);
  }

  Future<void> _showNodeMenu(Offset globalPosition) async {
    final canAddSerial = node.type != ColorNodeType.output;
    final canAddParallel = node.supportsProcessing;
    final canDelete = controller.canDelete(node.id);
    if (!canAddSerial && !canAddParallel && !canDelete) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        if (canAddSerial)
          const PopupMenuItem(
            value: 'serial',
            child: Text('Add Serial Node'),
          ),
        if (canAddParallel)
          const PopupMenuItem(
            value: 'parallel',
            child: Text('Add Parallel Node'),
          ),
        if (canDelete) const PopupMenuDivider(),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent),
                SizedBox(width: 10),
                Text('Delete Node'),
              ],
            ),
          ),
      ],
    );

    if (!mounted) return;
    if (action == 'serial') controller.addSerialAfter(node.id);
    if (action == 'parallel') controller.addParallelFrom(node.id);
    if (action == 'delete') controller.deleteNode(node.id);
  }

  String _nodeTypeLabel(ColorNodeType type) => switch (type) {
        ColorNodeType.input => 'Input',
        ColorNodeType.serial => 'Serial',
        ColorNodeType.parallel => 'Parallel',
        ColorNodeType.parallelMixer => 'Parallel Mixer',
        ColorNodeType.output => 'Output',
      };
}

class _ConnectionPainter extends CustomPainter {
  _ConnectionPainter(this.graph);

  final ColorNodeGraph graph;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final connection in graph.connections) {
      final from = graph.nodeById(connection.from);
      final to = graph.nodeById(connection.to);
      if (from == null || to == null) continue;
      final start = from.position + const Offset(124, 38);
      final end = to.position + const Offset(0, 38);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          (start.dx + end.dx) / 2,
          start.dy,
          (start.dx + end.dx) / 2,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) => true;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final small = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    final large = Paint()
      ..color = Colors.white.withValues(alpha: .055)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        x % (step * 5) == 0 ? large : small,
      );
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        y % (step * 5) == 0 ? large : small,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
