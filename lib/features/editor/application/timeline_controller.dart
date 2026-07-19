import 'package:flutter/foundation.dart';

class TimelineController extends ChangeNotifier {
  TimelineController({
    this.pixelsPerSecond = 80,
  });

  double pixelsPerSecond;

  Duration _position = Duration.zero;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = const Duration(minutes: 1);

  Duration get position => _position;
  Duration get trimStart => _trimStart;
  Duration get trimEnd => _trimEnd;

  double get zoom => pixelsPerSecond;

  void setPosition(Duration value) {
    if (value == _position) return;

    _position = value;
    notifyListeners();
  }

  void setTrimStart(Duration value) {
    if (value == _trimStart) return;

    _trimStart = value;

    if (_trimStart > _trimEnd) {
      _trimStart = _trimEnd;
    }

    notifyListeners();
  }

  void setTrimEnd(Duration value) {
    if (value == _trimEnd) return;

    _trimEnd = value;

    if (_trimEnd < _trimStart) {
      _trimEnd = _trimStart;
    }

    notifyListeners();
  }

  void zoomIn() {
    pixelsPerSecond =
        (pixelsPerSecond + 20).clamp(40.0, 300.0);

    notifyListeners();
  }

  void zoomOut() {
    pixelsPerSecond =
        (pixelsPerSecond - 20).clamp(40.0, 300.0);

    notifyListeners();
  }

  void reset() {
    _position = Duration.zero;
    _trimStart = Duration.zero;
    _trimEnd = const Duration(minutes: 1);
    pixelsPerSecond = 80;

    notifyListeners();
  }
}
