import 'dart:io';

import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
import 'package:digitor/features/projects/application/project_storage_service.dart';
import 'package:digitor/features/projects/domain/saved_editor_project.dart';
import 'package:flutter/material.dart';

class ProjectLibraryPage extends StatefulWidget {
  const ProjectLibraryPage({super.key});

  @override
  State<ProjectLibraryPage> createState() => _ProjectLibraryPageState();
}

class _ProjectLibraryPageState extends State<ProjectLibraryPage> {
  final ProjectStorageService _storage = ProjectStorageService();
  late Future<List<SavedEditorProject>> _projectsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _projectsFuture = _storage.loadProjects();
  }

  Future<void> _openNewProjectPicker() async {
    final ratio = await showModalBottomSheet<_ProjectAspectRatio>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF18191D),
      builder: (context) => const _AspectRatioPicker(),
    );
    if (ratio == null || !mounted) return;

    final now = DateTime.now();
    final projectId = 'project-${now.microsecondsSinceEpoch}';
    final projectName = 'Project ${_formattedDate(now)}';
    final canvasSize = ratio == _ProjectAspectRatio.landscape
        ? const Size(1920, 1080)
        : const Size(1080, 1920);
    final project = EditorProject(
      duration: Duration.zero,
      canvasSize: canvasSize,
      tracks: const [
        TimelineTrack(
          id: 'primary-video',
          name: 'Video 1',
          type: TrackType.video,
        ),
        TimelineTrack(
          id: 'primary-audio',
          name: 'Audio 1',
          type: TrackType.audio,
        ),
      ],
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          projectId: projectId,
          projectName: projectName,
          initialProject: project,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _openSavedProject(SavedEditorProject saved) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          projectId: saved.id,
          projectName: saved.name,
          initialProject: saved.project,
          initialThumbnailPath: saved.thumbnailPath,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _renameProject(SavedEditorProject project) async {
    final controller = TextEditingController(text: project.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'Enter project name',
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !mounted) return;
    await _storage.renameProject(id: project.id, newName: newName);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _deleteProject(SavedEditorProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('“${project.name}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteProject(project.id);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${project.name}')),
    );
  }

  static String _formattedDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Editor')),
      body: FutureBuilder<List<SavedEditorProject>>(
        future: _projectsFuture,
        builder: (context, snapshot) {
          final projects = snapshot.data ?? const <SavedEditorProject>[];
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _projectsFuture;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: _NewProjectCard(onTap: _openNewProjectPicker),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (projects.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyProjectLibrary(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final project = projects[index];
                          return _SavedProjectCard(
                            project: project,
                            onTap: () => _openSavedProject(project),
                            onRename: () => _renameProject(project),
                            onDelete: () => _deleteProject(project),
                          );
                        },
                        childCount: projects.length,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.92,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: color,
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New Project', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Choose a preview aspect ratio'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedProjectCard extends StatelessWidget {
  const _SavedProjectCard({
    required this.project,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final SavedEditorProject project;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final thumbnail = project.thumbnailPath;
    return Material(
      color: const Color(0xFF191A1F),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox.expand(
                child: thumbnail != null && File(thumbnail).existsSync()
                    ? Image.file(File(thumbnail), fit: BoxFit.cover)
                    : const ColoredBox(
                        color: Colors.black,
                        child: Center(child: Icon(Icons.movie_creation_outlined, size: 42)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _duration(project.project.duration),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ProjectCardAction>(
                    tooltip: 'Project options',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case _ProjectCardAction.rename:
                          onRename();
                          break;
                        case _ProjectCardAction.delete:
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ProjectCardAction.rename,
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined),
                            SizedBox(width: 12),
                            Text('Rename'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _ProjectCardAction.delete,
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.redAccent),
                            SizedBox(width: 12),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

enum _ProjectCardAction { rename, delete }

class _EmptyProjectLibrary extends StatelessWidget {
  const _EmptyProjectLibrary();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library_outlined, size: 54, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              const Text('No saved projects yet'),
              const SizedBox(height: 6),
              Text('Tap New Project to start editing.', style: TextStyle(color: Colors.white.withValues(alpha: 0.58))),
            ],
          ),
        ),
      );
}

enum _ProjectAspectRatio { landscape, portrait }

class _AspectRatioPicker extends StatelessWidget {
  const _AspectRatioPicker();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Project', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Select preview aspect ratio', style: TextStyle(color: Colors.white.withValues(alpha: 0.62))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _RatioOption(
                    title: 'Aspect Ratio',
                    ratio: '16:9',
                    icon: Icons.crop_landscape_rounded,
                    onTap: () => Navigator.pop(context, _ProjectAspectRatio.landscape),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RatioOption(
                    title: 'Aspect Ratio',
                    ratio: '9:16',
                    icon: Icons.crop_portrait_rounded,
                    onTap: () => Navigator.pop(context, _ProjectAspectRatio.portrait),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatioOption extends StatelessWidget {
  const _RatioOption({required this.title, required this.ratio, required this.icon, required this.onTap});

  final String title;
  final String ratio;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: const Color(0xFF23242A),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            children: [
              Icon(icon, size: 42, color: primary),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(ratio, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primary)),
            ],
          ),
        ),
      ),
    );
  }
}
