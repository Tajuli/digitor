import 'dart:io';

import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';

class PreviewArea extends StatelessWidget {
  const PreviewArea({
    super.key,
    required this.session,
  });

  final EditorSession session;

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
                path: session.media.path,
              )
            : _ImagePreview(
                path: session.media.path,
              ),
      ),
    );
  }
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
