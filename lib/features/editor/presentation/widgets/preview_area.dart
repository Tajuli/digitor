import 'dart:io';

import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';

class PreviewArea extends StatelessWidget {
  const PreviewArea({
    super.key,
    this.session,
    required this.playbackController,
    this.hasTimelineVideo = false,
  });

  final EditorSession? session;
  final PlaybackController playbackController;
  final bool hasTimelineVideo;

  @override
  Widget build(BuildContext context) {
    final media = session?.media;
    final shouldShowVideo = hasTimelineVideo || media?.isVideo == true;

    return _PreviewFrame(
      child: shouldShowVideo
          ? VideoPreview(playbackController: playbackController)
          : media != null
              ? Image.file(
                  File(media.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_rounded, size: 60),
                  ),
                )
              : const EmptyPreviewContent(),
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
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
          ),
        ),
      );
}
