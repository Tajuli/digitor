import 'dart:io';

import 'package:flutter/foundation.dart';

import 'thumbnail_generator.dart';

class TimelineProvider extends ChangeNotifier {
  TimelineProvider({
    required ThumbnailGenerator generator,
  }) : _generator = generator;

  final ThumbnailGenerator _generator;

  List<ThumbnailFrame> _frames = [];

  bool _isLoading = false;

  String? _error;

  List<ThumbnailFrame> get frames => List.unmodifiable(_frames);

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
      _frames = await _generator.generate(
        video: video,
        duration: duration,
      );
    } catch (e) {
      _frames = [];
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _frames = [];
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
