import 'package:digitor/features/editor/presentation/widgets/editor_toolbar_button.dart';
import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key});

  static const List<_EditorTool> _tools = [
    _EditorTool(icon: Icons.content_cut_rounded, label: 'Trim'),
    _EditorTool(icon: Icons.text_fields_rounded, label: 'Text'),
    _EditorTool(icon: Icons.filter_alt_rounded, label: 'Filter'),
    _EditorTool(icon: Icons.tune_rounded, label: 'Adjust'),
    _EditorTool(icon: Icons.crop_rounded, label: 'Crop'),
    _EditorTool(icon: Icons.emoji_emotions_rounded, label: 'Sticker'),
    _EditorTool(icon: Icons.audiotrack_rounded, label: 'Audio'),
    _EditorTool(icon: Icons.file_upload_rounded, label: 'Export'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tools.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final tool = _tools[index];
          return EditorToolbarButton(icon: tool.icon, label: tool.label);
        },
      ),
    );
  }
}

class _EditorTool {
  const _EditorTool({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
