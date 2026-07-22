import 'package:digitor/features/editor/application/mobile_export_service.dart';
import 'package:digitor/features/editor/domain/export/export_settings.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:flutter/material.dart';

Future<ExportSettings?> showExportSheet({
  required BuildContext context,
  required EditorProject project,
  required String projectName,
}) {
  return showModalBottomSheet<ExportSettings>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .62),
    builder: (_) => _ExportSheet(project: project, projectName: projectName),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.project, required this.projectName});

  final EditorProject project;
  final String projectName;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportSettings settings;
  late final TextEditingController fileNameController;
  bool advancedOpen = false;
  bool useTimelineResolution = true;
  bool useTimelineFrameRate = true;
  final MobileExportService exportService = MobileExportService();
  bool choosingLocation = false;

  static const resolutions = <Size>[
    Size(3840, 2160),
    Size(2560, 1440),
    Size(1920, 1080),
    Size(1280, 720),
    Size(1080, 1920),
    Size(1080, 1080),
  ];

  static const frameRates = <int>[24, 25, 30, 50, 60];

  @override
  void initState() {
    super.initState();
    final safeName = widget.projectName.trim().isEmpty
        ? 'Digitor Export'
        : widget.projectName.trim();
    settings = ExportSettings(
      resolution: widget.project.canvasSize,
      frameRate: widget.project.fps,
      fileName: safeName,
    );
    fileNameController = TextEditingController(text: safeName);
  }

  @override
  void dispose() {
    fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return FractionallySizedBox(
      heightFactor: .94,
      child: Material(
        color: const Color(0xFF15171B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.rocket_launch_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Export Video', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Render settings', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, media.viewInsets.bottom + 18),
                children: [
                  _section(
                    title: 'File',
                    children: [
                      TextField(
                        controller: fileNameController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'File name',
                          suffixText: '.mp4',
                          prefixIcon: Icon(Icons.drive_file_rename_outline),
                        ),
                        onChanged: (value) => settings = settings.copyWith(fileName: value.trim()),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: choosingLocation
                            ? null
                            : () async {
                                setState(() => choosingLocation = true);
                                try {
                                  final location = await exportService.chooseLocation(fileNameController.text);
                                  if (!mounted || location == null) return;
                                  setState(() {
                                    settings = settings.copyWith(
                                      outputUri: location.uri,
                                      outputLabel: location.label,
                                    );
                                  });
                                } finally {
                                  if (mounted) setState(() => choosingLocation = false);
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Export location',
                            prefixIcon: Icon(Icons.folder_open_outlined),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  settings.outputLabel ?? 'Choose folder / file location',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (choosingLocation)
                                const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dropdown<ExportFormat>(
                        label: 'Format',
                        icon: Icons.video_file_outlined,
                        value: settings.format,
                        items: const {ExportFormat.mp4: 'MP4'},
                        onChanged: (value) => setState(() => settings = settings.copyWith(format: value)),
                      ),
                    ],
                  ),
                  _section(
                    title: 'Video',
                    children: [
                      _segmented<ExportVideoCodec>(
                        label: 'Codec',
                        values: ExportVideoCodec.values,
                        selected: settings.videoCodec,
                        labelFor: (value) => value == ExportVideoCodec.h264 ? 'H.264' : 'H.265',
                        onChanged: (value) => setState(() => settings = settings.copyWith(videoCodec: value)),
                      ),
                      const SizedBox(height: 16),
                      _switchRow(
                        title: 'Use timeline resolution',
                        subtitle: '${widget.project.canvasSize.width.round()} × ${widget.project.canvasSize.height.round()}',
                        value: useTimelineResolution,
                        onChanged: (value) {
                          setState(() {
                            useTimelineResolution = value;
                            if (value) settings = settings.copyWith(resolution: widget.project.canvasSize);
                          });
                        },
                      ),
                      if (!useTimelineResolution) ...[
                        const SizedBox(height: 10),
                        _dropdown<Size>(
                          label: 'Resolution',
                          icon: Icons.aspect_ratio,
                          value: resolutions.contains(settings.resolution) ? settings.resolution : resolutions[2],
                          items: {for (final size in resolutions) size: '${size.width.round()} × ${size.height.round()}'},
                          onChanged: (value) => setState(() => settings = settings.copyWith(resolution: value)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _switchRow(
                        title: 'Use timeline frame rate',
                        subtitle: '${widget.project.fps} fps',
                        value: useTimelineFrameRate,
                        onChanged: (value) {
                          setState(() {
                            useTimelineFrameRate = value;
                            if (value) settings = settings.copyWith(frameRate: widget.project.fps);
                          });
                        },
                      ),
                      if (!useTimelineFrameRate) ...[
                        const SizedBox(height: 10),
                        _dropdown<int>(
                          label: 'Frame rate',
                          icon: Icons.speed,
                          value: frameRates.contains(settings.frameRate) ? settings.frameRate : 30,
                          items: {for (final fps in frameRates) fps: '$fps fps'},
                          onChanged: (value) => setState(() => settings = settings.copyWith(frameRate: value)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _segmented<ExportQuality>(
                        label: 'Quality',
                        values: ExportQuality.values,
                        selected: settings.quality,
                        labelFor: (value) => switch (value) {
                          ExportQuality.best => 'Best',
                          ExportQuality.high => 'High',
                          ExportQuality.medium => 'Medium',
                          ExportQuality.low => 'Low',
                          ExportQuality.least => 'Least',
                        },
                        onChanged: (value) => setState(() => settings = settings.copyWith(quality: value)),
                        scrollable: true,
                      ),
                    ],
                  ),
                  _section(
                    title: 'Audio',
                    children: [
                      _switchRow(
                        title: 'Export audio',
                        subtitle: settings.includeAudio ? 'AAC stereo audio included' : 'Video only',
                        value: settings.includeAudio,
                        onChanged: (value) => setState(() => settings = settings.copyWith(includeAudio: value)),
                      ),
                      if (settings.includeAudio) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _dropdown<int>(
                                label: 'Bitrate',
                                icon: Icons.graphic_eq,
                                value: settings.audioBitrateKbps,
                                items: const {128: '128 kbps', 192: '192 kbps', 256: '256 kbps', 320: '320 kbps'},
                                onChanged: (value) => setState(() => settings = settings.copyWith(audioBitrateKbps: value)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dropdown<int>(
                                label: 'Sample rate',
                                icon: Icons.multiline_chart,
                                value: settings.audioSampleRate,
                                items: const {44100: '44.1 kHz', 48000: '48 kHz'},
                                onChanged: (value) => setState(() => settings = settings.copyWith(audioSampleRate: value)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  _section(
                    title: 'Advanced',
                    children: [
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        initiallyExpanded: advancedOpen,
                        onExpansionChanged: (value) => setState(() => advancedOpen = value),
                        title: const Text('Encoding details'),
                        subtitle: const Text('Automatic settings based on quality'),
                        children: [
                          _detail('Video bitrate', '${settings.targetVideoBitrateKbps} kbps'),
                          _detail('Pixel format', 'YUV 4:2:0'),
                          _detail('Rate control', 'Variable bitrate'),
                          _detail('Keyframe interval', '${settings.frameRate * 2} frames'),
                          _detail('Color space', 'Rec.709'),
                          _detail('Fast start', 'Enabled'),
                        ],
                      ),
                    ],
                  ),
                  _summaryCard(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF111216),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: widget.project.duration <= Duration.zero || settings.outputUri == null
                        ? null
                        : () {
                            final name = fileNameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a file name.')));
                              return;
                            }
                            Navigator.pop(context, settings.copyWith(fileName: name));
                          },
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Export Video'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _switchRow({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _dropdown<T>({required String label, required IconData icon, required T value, required Map<T, String> items, required ValueChanged<T> onChanged}) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: items.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  Widget _segmented<T>({required String label, required List<T> values, required T selected, required String Function(T) labelFor, required ValueChanged<T> onChanged, bool scrollable = false}) {
    final content = SegmentedButton<T>(
      segments: values.map((value) => ButtonSegment<T>(value: value, label: Text(labelFor(value)))).toList(),
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
        if (scrollable) SingleChildScrollView(scrollDirection: Axis.horizontal, child: content) else SizedBox(width: double.infinity, child: content),
      ],
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.white60))), Text(value)]),
    );
  }

  Widget _summaryCard() {
    final estimated = settings.estimatedSizeMb(widget.project.duration);
    final duration = widget.project.duration;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _detail('Output', '${settings.resolutionLabel} • ${settings.frameRate} fps'),
          _detail('Codec', '${settings.codecLabel} • MP4'),
          _detail('Duration', '$minutes:$seconds'),
          _detail('Estimated size', estimated < 1 ? '< 1 MB' : '≈ ${estimated.toStringAsFixed(1)} MB'),
          _detail('Location', settings.outputLabel ?? 'Not selected'),
        ],
      ),
    );
  }
}
