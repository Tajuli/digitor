import '../domain/models/editor_project.dart';
import 'editor_history_controller.dart';
import 'project_controller.dart';

/// Immutable project snapshots make undo resilient to later clip mutations.
class ProjectSnapshotCommand implements EditorCommand {
  ProjectSnapshotCommand(this.controller, this.before, this.after);
  final ProjectController controller;
  final EditorProject before;
  final EditorProject after;
  @override void execute() => controller.updateProject(after);
  @override void undo() => controller.updateProject(before);
}

class MoveClipCommand extends ProjectSnapshotCommand { MoveClipCommand(super.controller, super.before, super.after); }
class SplitClipCommand extends ProjectSnapshotCommand { SplitClipCommand(super.controller, super.before, super.after); }
class RippleMoveCommand extends ProjectSnapshotCommand { RippleMoveCommand(super.controller, super.before, super.after); }
class TrimClipCommand extends ProjectSnapshotCommand { TrimClipCommand(super.controller, super.before, super.after); }
