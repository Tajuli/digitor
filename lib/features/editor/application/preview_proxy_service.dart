import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

/// Creates lightweight proxy files for responsive editor preview playback.
///
/// `video_compress` is used only on Android/iOS. Desktop platforms gracefully
/// use the original media path, keeping the same editor codebase buildable on
/// Windows and macOS.
class PreviewProxyService extends ChangeNotifier {
  final Map<String, String> _completed = <String, String>{};
  final Map<String, Future<String>> _pending = <String, Future<String>>{};
  dynamic _progressSubscription;

  String? _activeSourcePath;
  double _progress = 0;
  bool _disposed = false;

  String? get activeSourcePath => _activeSourcePath;
  double get progress => _progress;
  bool get isGenerating => _activeSourcePath != null;
  bool get _supportsNativeCompression =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  PreviewProxyService() {
    if (_supportsNativeCompression) {
      _progressSubscription = VideoCompress.compressProgress$.subscribe((value) {
        if (_disposed || _activeSourcePath == null) return;
        _progress = value.clamp(0, 100).toDouble();
        notifyListeners();
      });
    }
  }

  Future<String> proxyFor(String originalPath) {
    if (!_supportsNativeCompression) {
      return Future<String>.value(originalPath);
    }

    final cached = _completed[originalPath];
    if (cached != null && File(cached).existsSync()) {
      return Future<String>.value(cached);
    }

    return _pending.putIfAbsent(originalPath, () => _createProxy(originalPath));
  }

  Future<String> _createProxy(String originalPath) async {
    _activeSourcePath = originalPath;
    _progress = 0;
    notifyListeners();

    try {
      final result = await VideoCompress.compressVideo(
        originalPath,
        quality: VideoQuality.LowQuality,
        deleteOrigin: false,
        includeAudio: false,
        frameRate: 30,
      );
      final proxyPath = result?.path;
      if (proxyPath == null ||
          proxyPath.isEmpty ||
          !File(proxyPath).existsSync()) {
        return originalPath;
      }

      _completed[originalPath] = proxyPath;
      return proxyPath;
    } catch (error, stackTrace) {
      debugPrint('Preview proxy generation failed: $error\n$stackTrace');
      return originalPath;
    } finally {
      _pending.remove(originalPath);
      if (_activeSourcePath == originalPath) {
        _activeSourcePath = null;
        _progress = 0;
        if (!_disposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSubscription?.unsubscribe();
    super.dispose();
  }
}
