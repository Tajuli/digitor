import 'package:flutter/foundation.dart';

abstract class EditorCommand {
  void execute();
  void undo();
}

class EditorHistoryController extends ChangeNotifier {
  EditorHistoryController({this.maximumCommands = 100});
  final int maximumCommands;
  final List<EditorCommand> _undo = [];
  final List<EditorCommand> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void execute(EditorCommand command) { command.execute(); _undo.add(command); if (_undo.length > maximumCommands) _undo.removeAt(0); _redo.clear(); notifyListeners(); }
  void record(EditorCommand command) { _undo.add(command); if (_undo.length > maximumCommands) _undo.removeAt(0); _redo.clear(); notifyListeners(); }
  void undo() { if (!canUndo) return; final command = _undo.removeLast(); command.undo(); _redo.add(command); notifyListeners(); }
  void redo() { if (!canRedo) return; final command = _redo.removeLast(); command.execute(); _undo.add(command); notifyListeners(); }
  void clear() { _undo.clear(); _redo.clear(); notifyListeners(); }
}
