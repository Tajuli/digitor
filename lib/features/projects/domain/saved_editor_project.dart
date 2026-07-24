import 'package:digitor/features/editor/domain/models/editor_project.dart';

class SavedEditorProject {
  const SavedEditorProject({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.project,
    this.thumbnailPath,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final String? thumbnailPath;
  final EditorProject project;
}
