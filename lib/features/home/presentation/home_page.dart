import 'package:digitor/core/services/media_picker_service.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
import 'package:digitor/features/home/presentation/widgets/home_action_card.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final MediaPickerService _mediaPickerService = MediaPickerService();

  static const List<_HomeAction> _actions = [
    _HomeAction(
      title: 'Video Editor',
      subtitle: 'Create and edit videos professionally',
      icon: Icons.video_library_rounded,
      type: _HomeActionType.videoEditor,
    ),
    _HomeAction(
      title: 'Image Editor',
      subtitle: 'Enhance and edit your photos',
      icon: Icons.photo_library_rounded,
      type: _HomeActionType.imageEditor,
    ),
    _HomeAction(
      title: 'Share Digitor',
      subtitle: 'Invite your friends',
      icon: Icons.share_rounded,
      type: _HomeActionType.shareDigitor,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 40.0 : 24.0;
            final topPadding = constraints.maxHeight >= 700 ? 72.0 : 40.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HomeHeader(),
                      const SizedBox(height: 48),
                      for (final action in _actions) ...[
                        HomeActionCard(
                          title: action.title,
                          subtitle: action.subtitle,
                          icon: action.icon,
                          onTap: () => _handleActionTap(context, action.type),
                        ),
                        if (action != _actions.last) const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleActionTap(
    BuildContext context,
    _HomeActionType type,
  ) async {
    switch (type) {
      case _HomeActionType.videoEditor:
        await _pickAndOpenEditor(context, isVideo: true);
        break;
      case _HomeActionType.imageEditor:
        await _pickAndOpenEditor(context, isVideo: false);
        break;
      case _HomeActionType.shareDigitor:
        // TODO: Integrate sharing for Digitor.
        break;
    }
  }

  Future<void> _pickAndOpenEditor(
    BuildContext context, {
    required bool isVideo,
  }) async {
    final selectedFile = isVideo
        ? await _mediaPickerService.pickVideo()
        : await _mediaPickerService.pickImage();

    if (selectedFile == null || !context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorPage(
          media: MediaItem(
            id: selectedFile.path,
            path: selectedFile.path,
            isVideo: isVideo,
            duration: Duration.zero,
            createdAt: DateTime.now(),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DIGITOR',
          style: theme.textTheme.headlineLarge?.copyWith(
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Professional Video & Image Editor',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _HomeAction {
  const _HomeAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _HomeActionType type;
}

enum _HomeActionType { videoEditor, imageEditor, shareDigitor }
