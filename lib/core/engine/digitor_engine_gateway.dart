import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';

/// The single media/editing boundary used by the Flutter application.
///
/// Flutter owns UI/UX state only. Media opening, timeline transport, decode,
/// render, node/color processing, preview and export are delegated to
/// [DigitorEditorWorkspace] in DigitorEngine.
final class DigitorEngineGateway {
  DigitorEngineGateway._();

  static final DigitorEngineGateway instance = DigitorEngineGateway._();

  DigitorEditorWorkspace? _workspace;

  bool get isInitialized => _workspace != null;

  DigitorEditorWorkspace get workspace {
    final value = _workspace;
    if (value == null) {
      throw StateError('DigitorEngineGateway has not been initialized.');
    }
    return value;
  }

  Future<void> initialize() async {
    if (_workspace != null) return;
    _workspace = await DigitorEditorWorkspace.create();
  }

  DigitorProductionMediaSnapshot openMedia(String path) =>
      workspace.openMedia(path);

  DigitorRendererInfo get renderer => workspace.renderer;

  bool get productionReady => workspace.productionReady;

  DigitorPreviewCapabilities productionPreviewCapabilities() =>
      workspace.productionPreviewCapabilities();

  DigitorWorkspacePreviewState renderPreview({
    required int timestampUs,
    required int width,
    required int height,
  }) =>
      workspace.renderPreview(
        timestampUs: timestampUs,
        width: width,
        height: height,
      );

  void previewConsumed([int? generation]) =>
      workspace.previewConsumed(generation);

  void play() => workspace.play();

  void pause() => workspace.pause();

  void stop() => workspace.stop();

  void seek(int positionUs) => workspace.seek(positionUs);

  DigitorTimelineStatus timelineStatus() => workspace.timelineStatus();

  DigitorTimelineTelemetry timelineTelemetry() => workspace.timelineTelemetry();

  int? get selectedNode => workspace.selectedNode;

  void selectNode(int node) => workspace.selectNode(node);

  int addSerialNode({String name = 'Serial Node'}) =>
      workspace.addSerialNode(name: name);

  DigitorParallelNodes addParallelNodes() => workspace.addParallelNodes();

  void removeSelectedNode() => workspace.removeSelectedNode();

  void moveSelectedNode(double x, double y) =>
      workspace.moveSelectedNode(x, y);

  void addCorrection(DigitorCorrection value) =>
      workspace.addCorrection(value);

  void addPrimaryWheels(DigitorPrimaryWheels value) =>
      workspace.addPrimaryWheels(value);

  void addLogWheels(DigitorLogWheels value) => workspace.addLogWheels(value);

  void addRgbCurves(DigitorRgbCurves value) => workspace.addRgbCurves(value);

  void addHslQualifier(DigitorHslQualifier value) =>
      workspace.addHslQualifier(value);

  void addEffect(DigitorNodeEffect value) => workspace.addEffect(value);

  void addPowerWindow(DigitorPowerWindow value) =>
      workspace.addPowerWindow(value);

  void exportMedia({
    required String path,
    required int firstFrame,
    required int lastFrame,
    required int width,
    required int height,
    DigitorExportFormat format = DigitorExportFormat.mp4,
    DigitorVideoCodec codec = DigitorVideoCodec.h264,
    void Function(DigitorExportProgress progress)? onProgress,
  }) =>
      workspace.exportMedia(
        path: path,
        firstFrame: firstFrame,
        lastFrame: lastFrame,
        width: width,
        height: height,
        format: format,
        codec: codec,
        onProgress: onProgress,
      );

  void cancelExport() => workspace.cancelExport();

  Future<void> close() async {
    final current = _workspace;
    _workspace = null;
    if (current != null) await current.close();
  }
}
