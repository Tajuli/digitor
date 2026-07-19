import 'dart:io';
import 'package:digitor/features/editor/application/editor_controller.dart';
import 'package:digitor/features/editor/application/timeline_provider.dart';
import 'package:digitor/features/editor/application/video_thumbnail_generator.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:digitor/features/editor/presentation/widgets/preview_area.dart';
import 'package:digitor/features/editor/presentation/widgets/timeline_widget.dart';
import 'package:flutter/material.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.media,
  });

  final MediaItem media;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorController _controller;
  late final TimelineProvider _timelineProvider;

  @override
  void initState() {
    super.initState();

    _controller = EditorController()..loadMedia(widget.media);

    _timelineProvider = TimelineProvider(
      generator: VideoThumbnailGenerator(),
    );

    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    if (!widget.media.isVideo) return;

    await _timelineProvider.loadVideo(
      video: File(widget.media.path),
      duration: widget.media.duration,
    );
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.media != widget.media) {
      _controller.loadMedia(widget.media);
      _loadTimeline();
    }
  }

  @override
  void dispose() {
    _timelineProvider.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Editor',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 700 ? 32.0 : 16.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          children: [
                            Expanded(
                              flex: 5,
                              child: ListenableBuilder(
                                listenable: _controller,
                                builder: (context, _) {
                                  final session = _controller.session;

                                  if (session == null) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  return PreviewArea(session: session);
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListenableBuilder(
                              listenable: Listenable.merge([
                                _controller,
                                _timelineProvider,
                              ]),
                              builder: (context, _) {
                                final session = _controller.session;

                                if (session == null) {
                                  return const SizedBox.shrink();
                                }

                                return TimelineWidget(
                                  duration: session.trimEnd,
                                  frames: _timelineProvider.frames,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            const EditorToolbar(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
