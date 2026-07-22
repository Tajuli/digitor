import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ColorNodeController extends ChangeNotifier {
  ColorNodeController(this._graph);
  ColorNodeGraph _graph;
  ColorNodeGraph get graph => _graph;

  void select(String? id) { _graph = _graph.copyWith(selectedNodeId: id, clearSelection: id == null); notifyListeners(); }
  void move(String id, Offset position) { _replaceNode(_graph.nodeById(id)!.copyWith(position: position)); }
  void toggle(String id) { final n = _graph.nodeById(id)!; _replaceNode(n.copyWith(enabled: !n.enabled)); }
  void updateGrade(String id, dynamic grade) => _replaceNode(_graph.nodeById(id)!.copyWith(grade: grade));
  void updateQualifier(HslQualifierSettings value) => _replaceNode(_graph.qualifierTarget.copyWith(qualifier: value));

  void addSerialAfter(String anchorId) {
    final anchor = _graph.nodeById(anchorId);
    if (anchor == null || anchor.type == ColorNodeType.output) return;
    final outgoing = _graph.connections.where((c) => c.from == anchorId).toList();
    final id = _newId('node');
    final node = ColorNode(id: id, type: ColorNodeType.serial, name: 'Node ${_processingCount() + 1}'.padLeft(7, '0'), position: anchor.position + const Offset(160, 0));
    final links = [..._graph.connections.where((c) => c.from != anchorId), NodeConnection(anchorId, id), ...outgoing.map((c) => NodeConnection(id, c.to))];
    _graph = _graph.copyWith(nodes: [..._graph.nodes, node], connections: links, selectedNodeId: id);
    notifyListeners();
  }

  void addParallelFrom(String anchorId) {
    final anchor = _graph.nodeById(anchorId);
    if (anchor == null || !anchor.supportsProcessing) return;
    final outgoing = _graph.connections.where((c) => c.from == anchorId).toList();
    if (outgoing.isEmpty) return;
    final existingMixer = outgoing.map((c) => _graph.nodeById(c.to)).whereType<ColorNode>().where((n) => n.type == ColorNodeType.parallelMixer).firstOrNull;
    final branchId = _newId('parallel');
    final branch = ColorNode(id: branchId, type: ColorNodeType.parallel, name: 'Parallel ${_processingCount() + 1}', position: anchor.position + const Offset(170, 85));
    if (existingMixer != null) {
      _graph = _graph.copyWith(nodes: [..._graph.nodes, branch], connections: [..._graph.connections, NodeConnection(anchorId, branchId), NodeConnection(branchId, existingMixer.id)], selectedNodeId: branchId);
      notifyListeners(); return;
    }
    final oldNext = outgoing.first.to;
    final mixerId = _newId('mixer');
    final mixer = ColorNode(id: mixerId, type: ColorNodeType.parallelMixer, name: 'Parallel Mixer', position: anchor.position + const Offset(340, 30));
    final oldBranchId = _newId('parallel');
    final oldBranch = ColorNode(id: oldBranchId, type: ColorNodeType.parallel, name: 'Parallel ${_processingCount() + 1}', position: anchor.position + const Offset(170, -45));
    final cleaned = _graph.connections.where((c) => !(c.from == anchorId && c.to == oldNext)).toList();
    _graph = _graph.copyWith(
      nodes: [..._graph.nodes, oldBranch, branch, mixer],
      connections: [...cleaned, NodeConnection(anchorId, oldBranchId), NodeConnection(oldBranchId, mixerId), NodeConnection(anchorId, branchId), NodeConnection(branchId, mixerId), NodeConnection(mixerId, oldNext)],
      selectedNodeId: branchId,
    );
    notifyListeners();
  }

  void _replaceNode(ColorNode node) { _graph = _graph.copyWith(nodes: _graph.nodes.map((n) => n.id == node.id ? node : n).toList()); notifyListeners(); }
  int _processingCount() => _graph.nodes.where((n) => n.supportsProcessing).length;
  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
