import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ColorNodeController extends ChangeNotifier {
  ColorNodeController(this._graph);

  ColorNodeGraph _graph;
  ColorNodeGraph get graph => _graph;

  bool get canDeleteSelected => canDelete(_graph.selectedNodeId);

  bool canDelete(String? id) {
    final node = _graph.nodeById(id);
    return node != null &&
        node.supportsProcessing &&
        node.id != _graph.defaultNodeId;
  }

  void select(String? id) {
    _graph = _graph.copyWith(
      selectedNodeId: id,
      clearSelection: id == null,
    );
    notifyListeners();
  }

  void move(String id, Offset position) {
    final node = _graph.nodeById(id);
    if (node == null) return;
    final bounded = Offset(
      position.dx.clamp(0, 4876),
      position.dy.clamp(0, 3124),
    );
    _replaceNode(node.copyWith(position: bounded));
  }

  void toggle(String id) {
    final node = _graph.nodeById(id);
    if (node == null || !node.supportsProcessing) return;
    _replaceNode(node.copyWith(enabled: !node.enabled));
  }

  void updateGrade(String id, dynamic grade) {
    final node = _graph.nodeById(id);
    if (node == null || !node.supportsProcessing) return;
    _replaceNode(node.copyWith(grade: grade));
  }

  void updateQualifier(HslQualifierSettings value) {
    final selected = _graph.selectedProcessingNode;
    if (selected == null) return;
    _replaceNode(selected.copyWith(qualifier: value));
  }

  void addSerialAfter(String anchorId) {
    final anchor = _graph.nodeById(anchorId);
    if (anchor == null || anchor.type == ColorNodeType.output) return;
    final outgoing = _graph.connections
        .where((connection) => connection.from == anchorId)
        .toList();
    final id = _newId('node');
    final node = ColorNode(
      id: id,
      type: ColorNodeType.serial,
      name: 'Node ${(_processingCount() + 1).toString().padLeft(2, '0')}',
      position: anchor.position + const Offset(175, 0),
    );
    final links = [
      ..._graph.connections.where((connection) => connection.from != anchorId),
      NodeConnection(anchorId, id),
      ...outgoing.map((connection) => NodeConnection(id, connection.to)),
    ];
    _graph = _graph.copyWith(
      nodes: [..._graph.nodes, node],
      connections: links,
      selectedNodeId: id,
    );
    notifyListeners();
  }

  void addParallelFrom(String anchorId) {
    final anchor = _graph.nodeById(anchorId);
    if (anchor == null || !anchor.supportsProcessing) return;
    final outgoing = _graph.connections
        .where((connection) => connection.from == anchorId)
        .toList();
    if (outgoing.isEmpty) return;

    final existingMixer = outgoing
        .map((connection) => _graph.nodeById(connection.to))
        .whereType<ColorNode>()
        .where((node) => node.type == ColorNodeType.parallelMixer)
        .firstOrNull;

    final branchId = _newId('parallel');
    final branch = ColorNode(
      id: branchId,
      type: ColorNodeType.parallel,
      name: 'Parallel ${(_processingCount() + 1).toString().padLeft(2, '0')}',
      position: anchor.position + const Offset(180, 95),
    );

    if (existingMixer != null) {
      _graph = _graph.copyWith(
        nodes: [..._graph.nodes, branch],
        connections: [
          ..._graph.connections,
          NodeConnection(anchorId, branchId),
          NodeConnection(branchId, existingMixer.id),
        ],
        selectedNodeId: branchId,
      );
      notifyListeners();
      return;
    }

    final oldNext = outgoing.first.to;
    final mixerId = _newId('mixer');
    final mixer = ColorNode(
      id: mixerId,
      type: ColorNodeType.parallelMixer,
      name: 'Parallel Mixer',
      position: anchor.position + const Offset(370, 35),
    );
    final oldBranchId = _newId('parallel');
    final oldBranch = ColorNode(
      id: oldBranchId,
      type: ColorNodeType.parallel,
      name: 'Parallel ${(_processingCount() + 1).toString().padLeft(2, '0')}',
      position: anchor.position + const Offset(180, -55),
    );
    final cleaned = _graph.connections
        .where(
          (connection) =>
              !(connection.from == anchorId && connection.to == oldNext),
        )
        .toList();
    _graph = _graph.copyWith(
      nodes: [..._graph.nodes, oldBranch, branch, mixer],
      connections: [
        ...cleaned,
        NodeConnection(anchorId, oldBranchId),
        NodeConnection(oldBranchId, mixerId),
        NodeConnection(anchorId, branchId),
        NodeConnection(branchId, mixerId),
        NodeConnection(mixerId, oldNext),
      ],
      selectedNodeId: branchId,
    );
    notifyListeners();
  }

  void deleteSelected() {
    final id = _graph.selectedNodeId;
    if (id != null) deleteNode(id);
  }

  void deleteNode(String id) {
    if (!canDelete(id)) return;
    final node = _graph.nodeById(id)!;
    final incoming = _graph.connections
        .where((connection) => connection.to == id)
        .toList();
    final outgoing = _graph.connections
        .where((connection) => connection.from == id)
        .toList();

    var nodes = _graph.nodes.where((item) => item.id != id).toList();
    var connections = _graph.connections
        .where((connection) => connection.from != id && connection.to != id)
        .toList();

    // A serial node can sit between a single path, before a parallel split,
    // or after a mixer. Rebuild every valid incoming -> outgoing path so
    // deleting a middle node never leaves the graph disconnected.
    if (node.type == ColorNodeType.serial) {
      for (final input in incoming) {
        for (final output in outgoing) {
          if (input.from != output.to) {
            connections.add(NodeConnection(input.from, output.to));
          }
        }
      }
    }

    if (node.type == ColorNodeType.parallel && outgoing.length == 1) {
      final mixer = _graph.nodeById(outgoing.first.to);
      if (mixer != null && mixer.type == ColorNodeType.parallelMixer) {
        final mixerId = mixer.id;
        final remainingInputs = connections
            .where((connection) => connection.to == mixerId)
            .toList();
        final mixerOutputs = connections
            .where((connection) => connection.from == mixerId)
            .toList();
        if (remainingInputs.length <= 1 && mixerOutputs.length == 1) {
          final remaining = remainingInputs.firstOrNull;
          connections = connections
              .where(
                (connection) =>
                    connection.from != mixerId && connection.to != mixerId,
              )
              .toList();
          nodes = nodes.where((item) => item.id != mixerId).toList();
          if (remaining != null) {
            connections.add(
              NodeConnection(remaining.from, mixerOutputs.first.to),
            );
          } else if (incoming.length == 1) {
            connections.add(
              NodeConnection(incoming.first.from, mixerOutputs.first.to),
            );
          }
        }
      }
    }

    final existingNodeIds = nodes.map((item) => item.id).toSet();
    final rebuiltConnections = _deduplicate(connections).where((connection) {
      return connection.from != connection.to &&
          existingNodeIds.contains(connection.from) &&
          existingNodeIds.contains(connection.to);
    }).toList();

    _graph = _graph.copyWith(
      nodes: nodes,
      connections: rebuiltConnections,
      selectedNodeId: _graph.defaultNodeId,
    );
    notifyListeners();
  }

  List<NodeConnection> _deduplicate(List<NodeConnection> values) {
    final seen = <String>{};
    return values.where((connection) {
      return seen.add('${connection.from}->${connection.to}');
    }).toList();
  }

  void _replaceNode(ColorNode node) {
    _graph = _graph.copyWith(
      nodes: _graph.nodes
          .map((current) => current.id == node.id ? node : current)
          .toList(),
    );
    notifyListeners();
  }

  int _processingCount() =>
      _graph.nodes.where((node) => node.supportsProcessing).length;

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
