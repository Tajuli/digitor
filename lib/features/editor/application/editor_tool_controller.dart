import 'package:flutter/foundation.dart';

enum EditorToolType { edit, color, filter, effect, audio }

class EditorToolController extends ChangeNotifier {
  EditorToolType selected = EditorToolType.edit;
  bool magnetEnabled = true;
  bool trimModeEnabled = false;
  void select(EditorToolType value) { selected = value; notifyListeners(); }
  void toggleMagnet() { magnetEnabled = !magnetEnabled; notifyListeners(); }
  void toggleTrimMode() { trimModeEnabled = !trimModeEnabled; notifyListeners(); }
}
