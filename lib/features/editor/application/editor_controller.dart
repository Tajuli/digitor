import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:flutter/foundation.dart';

class EditorController extends ChangeNotifier {
  EditorSession? _session;

  EditorSession? get session => _session;

  void loadMedia(MediaItem media) {
    _session = EditorSession.initial(media);
    notifyListeners();
  }

  void updateTrimStart(Duration trimStart) {
    _updateSession((session) => session.copyWith(trimStart: trimStart));
  }

  void updateTrimEnd(Duration trimEnd) {
    _updateSession((session) => session.copyWith(trimEnd: trimEnd));
  }

  void updateRotation(double rotation) {
    _updateSession((session) => session.copyWith(rotation: rotation));
  }

  void updateScale(double scale) {
    _updateSession((session) => session.copyWith(scale: scale));
  }

  void updateOpacity(double opacity) {
    _updateSession((session) => session.copyWith(opacity: opacity));
  }

  void updateMuted(bool muted) {
    _updateSession((session) => session.copyWith(muted: muted));
  }

  void resetSession() {
    final media = _session?.media;
    if (media == null) {
      return;
    }

    _session = EditorSession.initial(media);
    notifyListeners();
  }

  void _updateSession(EditorSession Function(EditorSession session) update) {
    final session = _session;
    if (session == null) {
      return;
    }

    _session = update(session);
    notifyListeners();
  }
}
