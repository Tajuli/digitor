import 'package:digitor/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:digitor/features/editor/presentation/widgets/preview_area.dart';
import 'package:digitor/features/editor/presentation/widgets/timeline_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditorPage extends StatelessWidget {
  const EditorPage({
    required this.selectedFile,
    required this.isVideo,
    super.key,
  });

  final XFile selectedFile;
  final bool isVideo;

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
                  final horizontalPadding = constraints.maxWidth >= 700
                      ? 32.0
                      : 16.0;

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
                              child: PreviewArea(
                                selectedFile: selectedFile,
                                isVideo: isVideo,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const EditorToolbar(),
                            const SizedBox(height: 12),
                            const TimelinePlaceholder(),
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
