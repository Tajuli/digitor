import 'dart:io';

import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/application/preview_proxy_service.dart';
import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';

class PreviewArea extends StatefulWidget {
  const PreviewArea({
    super.key,
    this.session,
    required this.playbackController,
    required this.previewProxyService,
    this.hasTimelineVideo = false,
  });

  final EditorSession? session;
  final PlaybackController playbackController;
  final PreviewProxyService previewProxyService;
  final bool hasTimelineVideo;

  @override
  State<PreviewArea> createState() => _PreviewAreaState();
}

class _PreviewAreaState extends State<PreviewArea> {
  static const double _minScale = 0.5;
  static const double _maxScale = 4;
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _setScale(double nextScale) {
    final scale = nextScale.clamp(_minScale, _maxScale).toDouble();
    _transformationController.value = Matrix4.identity()..scale(scale);
    setState(() => _scale = scale);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.session?.media;
    final shouldShowVideo = widget.hasTimelineVideo || media?.isVideo == true;
    final content = shouldShowVideo
        ? VideoPreview(playbackController: widget.playbackController)
        : media != null
            ? Image.file(
                File(media.path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_rounded, size: 60),
                ),
              )
            : const EmptyPreviewContent();

    return _PreviewFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: _minScale,
              maxScale: _maxScale,
              panEnabled: _scale > 1,
              boundaryMargin: const EdgeInsets.all(240),
              onInteractionUpdate: (_) {
                final next = _transformationController.value
                    .getMaxScaleOnAxis()
                    .clamp(_minScale, _maxScale)
                    .toDouble();
                if ((next - _scale).abs() > 0.01) {
                  setState(() => _scale = next);
                }
              },
              child: content,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _PreviewZoomControls(
              scale: _scale,
              onZoomOut: () => _setScale(_scale - 0.25),
              onReset: () => _setScale(1),
              onZoomIn: () => _setScale(_scale + 0.25),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: AnimatedBuilder(
              animation: widget.previewProxyService,
              builder: (context, _) {
                if (!widget.previewProxyService.isGenerating) {
                  return const SizedBox.shrink();
                }
                final progress = widget.previewProxyService.progress;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Optimizing preview ${progress.round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyPreviewArea extends StatelessWidget {
  const EmptyPreviewArea({super.key});

  @override
  Widget build(BuildContext context) => const _PreviewFrame(
        child: EmptyPreviewContent(),
      );
}

class EmptyPreviewContent extends StatelessWidget {
  const EmptyPreviewContent({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 48),
            SizedBox(height: 12),
            Text('Add media to start editing'),
          ],
        ),
      );
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final idealHeight = width / (16 / 9);
            final height = idealHeight.clamp(0, constraints.maxHeight).toDouble();

            return SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
        ),
      );
}

class _PreviewZoomControls extends StatelessWidget {
  const _PreviewZoomControls({
    required this.scale,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final double scale;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withOpacity(0.68),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom out',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: scale <= _PreviewAreaState._minScale ? null : onZoomOut,
              icon: const Icon(Icons.remove_rounded, size: 19),
            ),
            InkWell(
              onTap: onReset,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  '${(scale * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Zoom in',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: scale >= _PreviewAreaState._maxScale ? null : onZoomIn,
              icon: const Icon(Icons.add_rounded, size: 19),
            ),
          ],
        ),
      );
}
