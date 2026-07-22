import 'dart:async';

import 'package:digitor/features/editor/application/mobile_export_service.dart';
import 'package:digitor/features/editor/domain/export/export_settings.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:flutter/foundation.dart';

enum ExportQueueState { waiting, exporting, completed, failed, cancelled }

@immutable
class ExportQueueItem {
  const ExportQueueItem({
    required this.id,
    required this.project,
    required this.settings,
    this.state = ExportQueueState.waiting,
    this.progress = 0,
    this.output,
    this.error,
  });

  final String id;
  final EditorProject project;
  final ExportSettings settings;
  final ExportQueueState state;
  final int progress;
  final String? output;
  final String? error;

  ExportQueueItem copyWith({
    ExportQueueState? state,
    int? progress,
    String? output,
    String? error,
  }) {
    return ExportQueueItem(
      id: id,
      project: project,
      settings: settings,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      output: output ?? this.output,
      error: error ?? this.error,
    );
  }
}

/// Runs exports sequentially and exposes queue/progress state to the UI.
///
/// Android-native foreground execution should own long exports when the app is
/// backgrounded. This controller is the Flutter-side queue and remains useful
/// for queue presentation, cancellation and retry.
class ExportQueueController extends ChangeNotifier {
  ExportQueueController({MobileExportService? exportService})
      : _exportService = exportService ?? MobileExportService();

  final MobileExportService _exportService;
  final List<ExportQueueItem> _items = <ExportQueueItem>[];
  Timer? _progressTimer;
  bool _processing = false;

  List<ExportQueueItem> get items => List.unmodifiable(_items);
  bool get isProcessing => _processing;

  void enqueue({
    required EditorProject project,
    required ExportSettings settings,
  }) {
    _items.add(
      ExportQueueItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        project: project,
        settings: settings,
      ),
    );
    notifyListeners();
    unawaited(_processNext());
  }

  Future<void> cancelActive() async {
    await _exportService.cancel();
    final index = _items.indexWhere(
      (item) => item.state == ExportQueueState.exporting,
    );
    if (index >= 0) {
      _items[index] = _items[index].copyWith(
        state: ExportQueueState.cancelled,
      );
      notifyListeners();
    }
  }

  Future<void> _processNext() async {
    if (_processing) return;
    final index = _items.indexWhere(
      (item) => item.state == ExportQueueState.waiting,
    );
    if (index < 0) return;

    _processing = true;
    _items[index] = _items[index].copyWith(
      state: ExportQueueState.exporting,
      progress: 0,
    );
    notifyListeners();

    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final progress = await _exportService.progress();
      final activeIndex = _items.indexWhere(
        (item) => item.state == ExportQueueState.exporting,
      );
      if (activeIndex >= 0) {
        _items[activeIndex] = _items[activeIndex].copyWith(
          progress: progress.percent,
        );
        notifyListeners();
      }
    });

    try {
      final output = await _exportService.export(
        project: _items[index].project,
        settings: _items[index].settings,
      );
      _items[index] = _items[index].copyWith(
        state: ExportQueueState.completed,
        progress: 100,
        output: output,
      );
    } catch (error) {
      _items[index] = _items[index].copyWith(
        state: ExportQueueState.failed,
        error: error.toString(),
      );
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      _processing = false;
      notifyListeners();
      unawaited(_processNext());
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }
}
