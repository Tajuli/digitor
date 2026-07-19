import 'dart:io';

import 'package:flutter/foundation.dart';

import 'thumbnail_generator.dart';

class TimelineProvider extends ChangeNotifier {
  TimelineProvider({
    required ThumbnailGenerator generator,
  }) : _generator = generator;

  final ThumbnailGenerator _generator;

  List<ThumbnailFrame> _thumbnails = [];
  bool _isLoading = false;
  String? _error;

  List<ThumbnailFrame> get thumbnails =>
      List.unmodifiable(_thumbnails);

  bool get isLoading => _isLoading;

  String? get error => _error;

  Future<void> loadVideo({
    required File video,
    required Duration duration,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _thumbnails = await _generator.generate(
        video: video,
        duration: duration,
      );
    } catch (e) {
      _error = e.toString();
      _thumbnails = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _thumbnails = [];
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
