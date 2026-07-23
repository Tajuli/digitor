import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DigLogCapturePage extends StatefulWidget {
  const DigLogCapturePage({super.key});

  @override
  State<DigLogCapturePage> createState() => _DigLogCapturePageState();
}

class _DigLogCapturePageState extends State<DigLogCapturePage>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _saving = false;
  String? _error;
  String? _lastSavedPath;
  double _exposure = 0;
  double _minExposure = 0;
  double _maxExposure = 0;
  FlashMode _flashMode = FlashMode.off;
  Timer? _timer;
  Duration _recorded = Duration.zero;

  CameraController? get controller => _controller;
  bool get isReady => controller?.value.isInitialized == true;
  bool get isRecording => controller?.value.isRecordingVideo == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = controller;
    if (active == null || !active.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _timer?.cancel();
      active.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(_cameraIndex);
    }
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('No camera was found.');
      await _initializeCamera(0);
    } on CameraException catch (e) {
      _setError(_friendlyCameraError(e));
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _initializeCamera(int index) async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    await _controller?.dispose();
    final next = CameraController(
      _cameras[index],
      ResolutionPreset.max,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = next;
    _cameraIndex = index;

    try {
      await next.initialize();
      await next.prepareForVideoRecording();
      _minExposure = await next.getMinExposureOffset();
      _maxExposure = await next.getMaxExposureOffset();
      _exposure = 0.clamp(_minExposure, _maxExposure).toDouble();
      await next.setExposureOffset(_exposure);
      await next.setFlashMode(FlashMode.off);
      if (mounted) setState(() => _initializing = false);
    } on CameraException catch (e) {
      await next.dispose();
      _setError(_friendlyCameraError(e));
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _error = message;
    });
  }

  String _friendlyCameraError(CameraException e) {
    if (e.code == 'CameraAccessDenied' ||
        e.code == 'CameraAccessDeniedWithoutPrompt') {
      return 'Camera permission is required for DigLog Capture.';
    }
    if (e.code == 'AudioAccessDenied' ||
        e.code == 'AudioAccessDeniedWithoutPrompt') {
      return 'Microphone permission is required to record video audio.';
    }
    return e.description ?? e.code;
  }

  Future<void> _toggleRecording() async {
    final active = controller;
    if (active == null || !active.value.isInitialized || _saving) return;

    try {
      if (active.value.isRecordingVideo) {
        await _stopRecording();
      } else {
        await active.startVideoRecording();
        _recorded = Duration.zero;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recorded += const Duration(seconds: 1));
        });
        setState(() {});
      }
    } on CameraException catch (e) {
      _showMessage(_friendlyCameraError(e));
    }
  }

  Future<void> _stopRecording() async {
    final active = controller;
    if (active == null || !active.value.isRecordingVideo) return;
    setState(() => _saving = true);
    _timer?.cancel();

    try {
      final captured = await active.stopVideoRecording();
      final directory = await getApplicationDocumentsDirectory();
      final digLogDir = Directory(p.join(directory.path, 'DigLog'));
      await digLogDir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = p.extension(captured.path).isEmpty
          ? '.mp4'
          : p.extension(captured.path);
      final outputPath = p.join(digLogDir.path, 'DIGLOG_$stamp$extension');
      await File(captured.path).copy(outputPath);
      await _writeSidecar(outputPath, active.description);
      _lastSavedPath = outputPath;
      if (mounted) {
        setState(() {});
        _showMessage('DigLog clip saved');
      }
    } catch (e) {
      _showMessage('Could not save recording: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _writeSidecar(
    String videoPath,
    CameraDescription camera,
  ) async {
    final metadata = <String, Object?>{
      'profile': 'DigLog Sensor Max v1',
      'capturePolicy': 'Maximum available resolution; no destructive app filter',
      'note':
          'Bit depth, dynamic range and manufacturer processing depend on device Camera API support.',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'cameraName': camera.name,
      'lensDirection': camera.lensDirection.name,
      'sensorOrientation': camera.sensorOrientation,
      'exposureOffset': _exposure,
      'resolutionPreset': 'max',
      'audio': true,
      'videoFile': p.basename(videoPath),
    };
    final sidecar = File('${p.withoutExtension(videoPath)}.diglog.json');
    await sidecar.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
      flush: true,
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || isRecording || _saving) return;
    final currentDirection = _cameras[_cameraIndex].lensDirection;
    final target = _cameras.indexWhere(
      (camera) => camera.lensDirection != currentDirection,
    );
    await _initializeCamera(target >= 0 ? target : (_cameraIndex + 1) % _cameras.length);
  }

  Future<void> _cycleFlash() async {
    final active = controller;
    if (active == null || isRecording) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await active.setFlashMode(next);
      setState(() => _flashMode = next);
    } on CameraException {
      _showMessage('Torch is not available on this lens.');
    }
  }

  Future<void> _setFocus(Offset localPosition, BoxConstraints constraints) async {
    final active = controller;
    if (active == null || !isReady) return;
    final point = Offset(
      (localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await active.setFocusPoint(point);
      await active.setExposurePoint(point);
    } on CameraException {
      // Some devices do not expose metering points. Recording still works.
    }
  }

  Future<void> _openLastClip() async {
    final path = _lastSavedPath;
    if (path == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          media: MediaItem(
            id: path,
            path: path,
            isVideo: true,
            duration: _recorded,
            createdAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isRecording,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isRecording) {
          _showMessage('Stop recording before leaving DigLog Capture.');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? _ErrorView(message: _error!, onRetry: _initialize)
              : _initializing || !isReady
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        _TopBar(
                          recording: isRecording,
                          elapsed: _recorded,
                          flashMode: _flashMode,
                          canSwitch: _cameras.length > 1,
                          onBack: () => Navigator.maybePop(context),
                          onFlash: _cycleFlash,
                          onSwitch: _switchCamera,
                        ),
                        Expanded(child: _buildPreview()),
                        _buildControls(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final active = controller!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _setFocus(details.localPosition, constraints),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: active.value.previewSize!.height,
                    height: active.value.previewSize!.width,
                    child: CameraPreview(active),
                  ),
                ),
              ),
              IgnorePointer(child: CustomPaint(painter: _ThirdsGridPainter())),
              Positioned(
                left: 12,
                bottom: 12,
                child: _ProfileBadge(
                  camera: active.description,
                  resolution: active.value.previewSize,
                ),
              ),
              if (_saving)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Container(
      color: const Color(0xFF0B0C0E),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        children: [
          Row(
            children: [
              const Text('EV', style: TextStyle(color: Colors.white70)),
              Expanded(
                child: Slider(
                  min: _minExposure,
                  max: _maxExposure <= _minExposure
                      ? _minExposure + 0.1
                      : _maxExposure,
                  value: _exposure.clamp(
                    _minExposure,
                    _maxExposure <= _minExposure
                        ? _minExposure + 0.1
                        : _maxExposure,
                  ),
                  onChanged: isRecording
                      ? null
                      : (value) async {
                          setState(() => _exposure = value);
                          try {
                            await controller?.setExposureOffset(value);
                          } on CameraException {
                            // Ignore unsupported intermediate exposure values.
                          }
                        },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _exposure.toStringAsFixed(1),
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 82,
                child: _lastSavedPath == null
                    ? const Icon(Icons.hd_rounded, color: Colors.white54)
                    : IconButton(
                        tooltip: 'Open last clip in editor',
                        onPressed: isRecording ? null : _openLastClip,
                        icon: const Icon(Icons.video_file_rounded),
                      ),
              ),
              _RecordButton(
                recording: isRecording,
                onPressed: _toggleRecording,
              ),
              const SizedBox(
                width: 82,
                child: Column(
                  children: [
                    Icon(Icons.touch_app_rounded, color: Colors.white54),
                    SizedBox(height: 2),
                    Text('Tap focus', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.recording,
    required this.elapsed,
    required this.flashMode,
    required this.canSwitch,
    required this.onBack,
    required this.onFlash,
    required this.onSwitch,
  });

  final bool recording;
  final Duration elapsed;
  final FlashMode flashMode;
  final bool canSwitch;
  final VoidCallback onBack;
  final VoidCallback onFlash;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          IconButton(onPressed: recording ? null : onBack, icon: const Icon(Icons.arrow_back_rounded)),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('DIGLOG', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
                Text('SENSOR MAX', style: TextStyle(fontSize: 10, color: Color(0xFFA78BFA), letterSpacing: 1.2)),
              ],
            ),
          ),
          if (recording)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('$minutes:$seconds', style: const TextStyle(color: Colors.redAccent, fontFeatures: [])),
            ),
          IconButton(
            onPressed: recording ? null : onFlash,
            icon: Icon(flashMode == FlashMode.torch ? Icons.flash_on_rounded : Icons.flash_off_rounded),
          ),
          IconButton(
            onPressed: canSwitch && !recording ? onSwitch : null,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.camera, required this.resolution});

  final CameraDescription camera;
  final Size? resolution;

  @override
  Widget build(BuildContext context) {
    final size = resolution;
    final label = size == null ? 'MAX' : '${size.width.round()}×${size.height.round()}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          'DigLog Sensor Max  •  $label  •  ${camera.lensDirection.name}',
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.onPressed});
  final bool recording;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: recording ? 30 : 58,
            height: recording ? 30 : 58,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(recording ? 7 : 40),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded, size: 54, color: Colors.white54),
            const SizedBox(height: 18),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
