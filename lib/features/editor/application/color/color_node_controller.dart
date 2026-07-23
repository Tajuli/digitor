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
    final node = _graph.nodeById(id);
    if (node == null || !node.supportsProcessing) return;
    _graph = _graph.copyWith(selectedNodeId: id);
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
    if (outgoing.isEmpty) return;

    const spacing = 175.0;
    final downstreamIds = _collectDownstreamIds(
      outgoing.map((connection) => connection.to),
    );
    final shiftedNodes = _shiftNodes(_graph.nodes, downstreamIds, spacing);

    final id = _newId('node');
    final node = ColorNode(
      id: id,
      type: ColorNodeType.serial,
      name: 'Node ${(_processingCount() + 1).toString().padLeft(2, '0')}',
      position: anchor.position + const Offset(spacing, 0),
    );
    final links = [
      ..._graph.connections.where((connection) => connection.from != anchorId),
      NodeConnection(anchorId, id),
      ...outgoing.map((connection) => NodeConnection(id, connection.to)),
    ];
    _graph = _graph.copyWith(
      nodes: [...shiftedNodes, node],
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
      var nodes = _graph.nodes;
      final minimumMixerX = anchor.position.dx + 370;
      if (existingMixer.position.dx < minimumMixerX) {
        final downstreamIds = _collectDownstreamIds([existingMixer.id]);
        nodes = _shiftNodes(
          nodes,
          downstreamIds,
          minimumMixerX - existingMixer.position.dx,
        );
      }
      _graph = _graph.copyWith(
        nodes: [...nodes, branch],
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
    final downstreamIds = _collectDownstreamIds([oldNext]);
    final shiftedNodes = _shiftNodes(_graph.nodes, downstreamIds, 370);
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
      nodes: [...shiftedNodes, oldBranch, branch, mixer],
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

    if (node.type == ColorNodeType.serial) {
      // Rebuild every valid upstream -> downstream route.
      for (final input in incoming) {
        for (final output in outgoing) {
          if (input.from != output.to) {
            connections.add(NodeConnection(input.from, output.to));
          }
        }
      }
    }

    if (node.type == ColorNodeType.parallel) {
      // Remember the source feeding the deleted branch. It is needed when
      // this was the final input of a Parallel Mixer.
      final deletedBranchSources = incoming.map((item) => item.from).toSet();

      // A parallel node normally feeds one mixer, but process every outgoing
      // mixer defensively so malformed/older saved graphs are repaired too.
      final affectedMixerIds = outgoing
          .map((item) => item.to)
          .where((mixerId) {
            final mixer = _graph.nodeById(mixerId);
            return mixer?.type == ColorNodeType.parallelMixer;
          })
          .toSet();

      for (final mixerId in affectedMixerIds) {
        final result = _collapseMixerIfPossible(
          mixerId: mixerId,
          nodes: nodes,
          connections: connections,
          fallbackSources: deletedBranchSources,
        );
        nodes = result.nodes;
        connections = result.connections;
      }
    }

    // Normalize any orphan/single-input mixer left by old projects or by a
    // chain of deletes. Repeat because collapsing one mixer can expose another.
    var changed = true;
    while (changed) {
      changed = false;
      final mixerIds = nodes
          .where((item) => item.type == ColorNodeType.parallelMixer)
          .map((item) => item.id)
          .toList();

      for (final mixerId in mixerIds) {
        final beforeNodeCount = nodes.length;
        final beforeConnectionCount = connections.length;
        final result = _collapseMixerIfPossible(
          mixerId: mixerId,
          nodes: nodes,
          connections: connections,
        );
        nodes = result.nodes;
        connections = result.connections;
        if (nodes.length != beforeNodeCount ||
            connections.length != beforeConnectionCount) {
          changed = true;
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

  _MixerCollapseResult _collapseMixerIfPossible({
    required String mixerId,
    required List<ColorNode> nodes,
    required List<NodeConnection> connections,
    Set<String> fallbackSources = const <String>{},
  }) {
    final mixer = nodes.where((item) => item.id == mixerId).firstOrNull;
    if (mixer == null || mixer.type != ColorNodeType.parallelMixer) {
      return _MixerCollapseResult(nodes, connections);
    }

    final inputs = connections
        .where((connection) => connection.to == mixerId)
        .toList();
    final outputs = connections
        .where((connection) => connection.from == mixerId)
        .toList();

    // Two or more active branches still need the mixer.
    if (inputs.length >= 2) {
      return _MixerCollapseResult(nodes, connections);
    }

    var nextNodes = nodes.where((item) => item.id != mixerId).toList();
    var nextConnections = connections
        .where(
          (connection) =>
              connection.from != mixerId && connection.to != mixerId,
        )
        .toList();

    final sourceIds = inputs.isNotEmpty
        ? inputs.map((item) => item.from).toSet()
        : fallbackSources;

    // When only one parallel branch remains, the parallel group no longer
    // exists. Promote that remaining processing node to a true serial node so
    // all later add/delete/select and grading behavior matches a serial node.
    if (inputs.length == 1) {
      final remainingId = inputs.single.from;
      nextNodes = nextNodes.map((item) {
        if (item.id != remainingId || item.type != ColorNodeType.parallel) {
          return item;
        }
        return item.copyWith(
          type: ColorNodeType.serial,
          name: _serialNameFromParallel(item.name),
        );
      }).toList();
    }

    // One remaining branch: promoted serial node -> every former mixer
    // downstream node. No remaining branch: the deleted branch's upstream
    // source bypasses the mixer.
    for (final sourceId in sourceIds) {
      for (final output in outputs) {
        if (sourceId != output.to) {
          nextConnections.add(NodeConnection(sourceId, output.to));
        }
      }
    }

    nextConnections = _deduplicate(nextConnections);
    return _MixerCollapseResult(nextNodes, nextConnections);
  }


  String _serialNameFromParallel(String currentName) {
    final match = RegExp(r'(\d+)$').firstMatch(currentName.trim());
    if (match != null) return 'Node ${match.group(1)}';
    return 'Node ${(_processingCount()).toString().padLeft(2, '0')}';
  }

  Set<String> _collectDownstreamIds(Iterable<String> startIds) {
    final result = <String>{};
    final queue = <String>[...startIds];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!result.add(current)) continue;
      queue.addAll(
        _graph.connections
            .where((connection) => connection.from == current)
            .map((connection) => connection.to),
      );
    }
    return result;
  }

  List<ColorNode> _shiftNodes(
    List<ColorNode> nodes,
    Set<String> ids,
    double dx,
  ) {
    if (dx <= 0 || ids.isEmpty) return nodes;
    return nodes.map((node) {
      if (!ids.contains(node.id)) return node;
      return node.copyWith(position: node.position + Offset(dx, 0));
    }).toList();
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

class _MixerCollapseResult {
  const _MixerCollapseResult(this.nodes, this.connections);

  final List<ColorNode> nodes;
  final List<NodeConnection> connections;
}
