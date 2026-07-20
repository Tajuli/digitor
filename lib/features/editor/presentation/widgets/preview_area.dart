import 'dart:io';

import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/domain/models/editor_session.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';

class PreviewArea extends StatelessWidget {
  const PreviewArea({super.key, required this.session, required this.playbackController});

  final EditorSession session;
  final PlaybackController playbackController;

  @override
  Widget build(BuildContext context) => _PreviewFrame(
        child: session.media.isVideo
            ? VideoPreview(playbackController: playbackController)
            : Image.file(
                File(session.media.path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_rounded, size: 60),
                ),
              ),
      );
}

class EmptyPreviewArea extends StatelessWidget {
  const EmptyPreviewArea({super.key});

  @override
  Widget build(BuildContext context) => const _PreviewFrame(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 48),
              SizedBox(height: 12),
              Text('Add media to start editing'),
            ],
          ),
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
