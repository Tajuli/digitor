import 'package:flutter/foundation.dart';

enum EditorToolType { edit, color, filter, effect, audio }

class EditorToolController extends ChangeNotifier {
  EditorToolType selected = EditorToolType.edit;
  bool magnetEnabled = true;
  void select(EditorToolType value) { selected = value; notifyListeners(); }
  void toggleMagnet() { magnetEnabled = !magnetEnabled; notifyListeners(); }
}
