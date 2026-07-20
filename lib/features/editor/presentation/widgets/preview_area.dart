import 'dart:io';

import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';
import '../../application/playback_controller.dart';

class PreviewArea extends StatelessWidget {
  const PreviewArea({
    super.key,
    required this.session,
    required this.playbackController,
  });

  final EditorSession session;
  final PlaybackController playbackController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: session.media.isVideo
            ? VideoPreview(
                playbackController: playbackController,
              )
            : _ImagePreview(
                path: session.media.path,
              ),
      ),
    );
  }
}

class EmptyPreviewArea extends StatelessWidget {
  const EmptyPreviewArea({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(28),
    ),
    child: const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add_photo_alternate_outlined, size: 48),
        SizedBox(height: 12),
        Text('Add media to start editing'),
      ]),
    ),
  );
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.path,
  });

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return const Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: 60,
          ),
        );
      },
    );
  }
}
