import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine/engine_feature_catalog.dart';
import '../../../core/engine/engine_gateway.dart';
import 'mobile_multitrack_timeline.dart';
import 'professional_color_wheels.dart';

class MobileEditorScreen extends StatefulWidget {
  const MobileEditorScreen({super.key, required this.engine});

  final EngineGateway engine;

  @override
  State<MobileEditorScreen> createState() => _MobileEditorScreenState();
}

class _MobileEditorScreenState extends State<MobileEditorScreen> {
  static const _toolWorkspaces = <EngineWorkspace>[
    EngineWorkspace.edit,
    EngineWorkspace.audio,
    EngineWorkspace.media,
    EngineWorkspace.transform,
    EngineWorkspace.correction,
    EngineWorkspace.color,
    EngineWorkspace.looks,
    EngineWorkspace.effects,
    EngineWorkspace.masks,
    EngineWorkspace.nodes,
    EngineWorkspace.playback,
    EngineWorkspace.scopes,
    EngineWorkspace.performance,
    EngineWorkspace.engine,
  ];

  EngineWorkspace workspace = EngineWorkspace.edit;
  EngineSnapshot snapshot = EngineSnapshot.disconnected;
  List<EngineCapability> capabilities = const <EngineCapability>[];
  EngineProgress? progress;
  String? error;
  String? exportMessage;
  String? selectedFeatureId;

  final sliders = <String, double>{};
  final toggles = <String, bool>{};
  final choices = <String, String>{};
  final subscriptions = <StreamSubscription<Object?>>[];

  List<EngineUiFeature> get features => engineFeatureCatalog
      .where((feature) => feature.workspace == workspace)
      .toList(growable: false);

  EngineUiFeature? get selectedFeature {
    final id = selectedFeatureId;
    if (id == null) return null;
    for (final feature in features) {
      if (feature.id == id) return feature;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    subscriptions.add(widget.engine.snapshots.listen((value) {
      if (mounted) setState(() => snapshot = value);
    }));
    subscriptions.add(widget.engine.progress.listen((value) {
      if (mounted) setState(() => progress = value);
    }));
    subscriptions.add(widget.engine.events.listen(_handleEngineEvent));
    unawaited(_initialize());
  }

  void _handleEngineEvent(EngineEvent value) {
    if (!mounted) return;
    switch (value.type) {
      case 'exportStarted':
        setState(() {
          exportMessage = 'Exporting video…';
          error = null;
        });
        return;
      case 'exportCompleted':
        final path = value.payload['path']?.toString();
        setState(() {
          exportMessage = path == null ? 'Export complete' : 'Export complete · $path';
          progress = const EngineProgress(operation: 'export', fraction: 1);
          error = null;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(path == null ? 'Export complete' : 'Export complete\n$path'),
            ),
          );
        return;
      case 'exportLocationRequired':
        setState(() => exportMessage = 'Export cancelled');
        return;
      case 'unsupportedAction':
      case 'engineError':
      case 'previewError':
        final message = value.payload['error']?.toString() ??
            'Engine API not exposed for ${value.payload['action']}';
        setState(() => error = message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        return;
    }
  }

  Future<void> _initialize() async {
    try {
      await widget.engine.initialize();
      final next = await widget.engine.discoverCapabilities();
      if (!mounted) return;
      setState(() {
        capabilities = next;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _dispatch(String feature, String control, [Object? value]) async {
    try {
      await widget.engine.dispatch(
        EngineIntent(
          '$feature.$control',
          value == null
              ? const <String, Object?>{}
              : <String, Object?>{'value': value},
        ),
      );
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _supported(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability.supported;
    }
    return false;
  }

  void _selectWorkspace(EngineWorkspace value) {
    setState(() {
      workspace = value;
      selectedFeatureId = null;
    });
  }

  void _selectFeature(EngineUiFeature feature) {
    setState(() => selectedFeatureId = feature.id);
  }

  void _openExport() {
    setState(() {
      workspace = EngineWorkspace.export;
      selectedFeatureId = 'export.production';
    });
  }

  String get _projectTitle {
    final mediaPath = snapshot.state['mediaPath']?.toString();
    if (mediaPath == null || mediaPath.isEmpty) return 'New project';
    return mediaPath.replaceAll('\\', '/').split('/').last;
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(widget.engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = selectedFeature;
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _MobileTopBar(
              title: _projectTitle,
              connected: snapshot.connected,
              progress: progress,
              exportMessage: exportMessage,
              onImport: () => _dispatch('media.import', 'requestPicker'),
              onExport: _openExport,
            ),
            if (progress != null &&
                progress!.operation == 'export' &&
                progress!.fraction < 1)
              LinearProgressIndicator(
                minHeight: 2,
                value: progress!.fraction,
              ),
            if (error != null)
              _MobileErrorStrip(
                message: error!,
                onRetry: _initialize,
                onDismiss: () => setState(() => error = null),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 610;
                  final veryCompact = constraints.maxHeight < 500;
                  final isAndroid =
                      Theme.of(context).platform == TargetPlatform.android;
                  final showTimeline = feature == null || !veryCompact;
                  final timelineHeight = isAndroid
                      ? (compact ? 192.0 : 224.0)
                      : (compact ? 108.0 : 132.0);
                  final inspectorHeight = veryCompact
                      ? 150.0
                      : compact
                          ? 184.0
                          : 220.0;
                  final featureHeight = compact ? 58.0 : 64.0;
                  final workspaceHeight = compact ? 66.0 : 72.0;

                  return Column(
                    children: <Widget>[
                      Expanded(
                        child: _MobilePreview(
                          snapshot: snapshot,
                          onImport: () =>
                              _dispatch('media.import', 'requestPicker'),
                        ),
                      ),
                      _MobileTransportBar(
                        snapshot: snapshot,
                        dispatch: _dispatch,
                      ),
                      if (showTimeline)
                        SizedBox(
                          height: timelineHeight,
                          child: isAndroid
                              ? MobileMultitrackTimeline(
                                  snapshot: snapshot,
                                  onImport: () => _dispatch(
                                    'media.import',
                                    'requestPicker',
                                  ),
                                  onEdit: () =>
                                      _selectWorkspace(EngineWorkspace.edit),
                                  onSeekUs: (value) => unawaited(
                                    _dispatch(
                                      'playback.transport',
                                      'seek',
                                      value,
                                    ),
                                  ),
                                )
                              : _MobileTimeline(
                                  snapshot: snapshot,
                                  onImport: () => _dispatch(
                                    'media.import',
                                    'requestPicker',
                                  ),
                                  onEdit: () =>
                                      _selectWorkspace(EngineWorkspace.edit),
                                ),
                        ),
                      if (feature != null)
                        SizedBox(
                          height: inspectorHeight,
                          child: _MobileInspectorPanel(
                            key: ValueKey(feature.id),
                            feature: feature,
                            supported: _supported(feature.id),
                            sliders: sliders,
                            toggles: toggles,
                            choices: choices,
                            dispatch: _dispatch,
                            onSlider: (key, value) =>
                                setState(() => sliders[key] = value),
                            onToggle: (key, value) =>
                                setState(() => toggles[key] = value),
                            onChoice: (key, value) =>
                                setState(() => choices[key] = value),
                            onClose: () =>
                                setState(() => selectedFeatureId = null),
                          ),
                        ),
                      SizedBox(
                        height: featureHeight,
                        child: _FeatureRibbon(
                          features: features,
                          selectedId: selectedFeatureId,
                          supported: _supported,
                          onSelected: _selectFeature,
                        ),
                      ),
                      SizedBox(
                        height: workspaceHeight,
                        child: _WorkspaceToolbar(
                          workspaces: _toolWorkspaces,
                          selected: workspace,
                          onSelected: _selectWorkspace,
                        ),
                      ),
                    ],
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

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.title,
    required this.connected,
    required this.progress,
    required this.exportMessage,
    required this.onImport,
    required this.onExport,
  });

  final String title;
  final bool connected;
  final EngineProgress? progress;
  final String? exportMessage;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final exporting = progress?.operation == 'export' && progress!.fraction < 1;
    final percent = exporting ? '${(progress!.fraction * 100).round()}%' : null;

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Import media',
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: connected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        connected ? 'DigitorEngine' : 'Engine offline',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (exportMessage != null && !exporting)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: exportMessage!,
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                ),
              ),
            FilledButton(
              onPressed: exporting ? null : onExport,
              style: FilledButton.styleFrom(
                minimumSize: const Size(76, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              child: Text(percent ?? 'Export'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileErrorStrip extends StatelessWidget {
  const _MobileErrorStrip({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, size: 16),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 17),
            ),
          ],
        ),
      );
}

class _MobilePreview extends StatelessWidget {
  const _MobilePreview({required this.snapshot, required this.onImport});

  final EngineSnapshot snapshot;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final textureId = snapshot.state['previewTextureId'] as int?;
    final width = snapshot.state['previewWidth'] as int? ?? 0;
    final height = snapshot.state['previewHeight'] as int? ?? 0;
    final aspect = width > 0 && height > 0 ? width / height : 16 / 9;

    return ColoredBox(
      color: const Color(0xFF030304),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: ColoredBox(
                  color: Colors.black,
                  child: textureId == null
                      ? _EmptyPreview(onImport: onImport)
                      : Theme.of(context).platform == TargetPlatform.android
                          ? Transform.flip(
                              flipY: true,
                              child: Texture(
                                textureId: textureId,
                                filterQuality: FilterQuality.medium,
                              ),
                            )
                          : Texture(
                              textureId: textureId,
                              filterQuality: FilterQuality.medium,
                            ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 9,
            child: _PreviewBadge(
              icon: Icons.movie_filter_outlined,
              label: 'Preview',
            ),
          ),
          Positioned(
            right: 10,
            top: 9,
            child: _PreviewBadge(
              icon: snapshot.connected
                  ? Icons.bolt_rounded
                  : Icons.link_off_rounded,
              label: snapshot.connected ? 'Engine' : 'Offline',
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.video_file_outlined,
              size: 42,
              color: Colors.white24,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add media to start editing',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add media'),
            ),
          ],
        ),
      );
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xB5141418),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.white70),
            ),
          ],
        ),
      );
}

class _MobileTransportBar extends StatelessWidget {
  const _MobileTransportBar({required this.snapshot, required this.dispatch});

  final EngineSnapshot snapshot;
  final Future<void> Function(String, String, [Object?]) dispatch;

  String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    final centiseconds = value.inMilliseconds.remainder(1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${centiseconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        color: const Color(0xFF0B0B0E),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _clock(snapshot.position),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
            IconButton(
              tooltip: 'Previous frame',
              visualDensity: VisualDensity.compact,
              onPressed: snapshot.connected
                  ? () => dispatch('playback.transport', 'previousFrame')
                  : null,
              icon: const Icon(Icons.skip_previous_rounded, size: 22),
            ),
            IconButton.filled(
              tooltip: snapshot.isPlaying ? 'Pause' : 'Play',
              onPressed: snapshot.connected
                  ? () => dispatch('playback.transport', 'playPause')
                  : null,
              icon: Icon(
                snapshot.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 22,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size(34, 34),
              ),
            ),
            IconButton(
              tooltip: 'Next frame',
              visualDensity: VisualDensity.compact,
              onPressed: snapshot.connected
                  ? () => dispatch('playback.transport', 'nextFrame')
                  : null,
              icon: const Icon(Icons.skip_next_rounded, size: 22),
            ),
            Expanded(
              child: Text(
                _clock(snapshot.duration),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      );
}

class _MobileTimeline extends StatelessWidget {
  const _MobileTimeline({
    required this.snapshot,
    required this.onImport,
    required this.onEdit,
  });

  final EngineSnapshot snapshot;
  final VoidCallback onImport;
  final VoidCallback onEdit;

  String? get _mediaPath => snapshot.state['mediaPath']?.toString();

  String get _mediaName {
    final path = _mediaPath;
    if (path == null || path.isEmpty) return 'No media';
    return path.replaceAll('\\', '/').split('/').last;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final sidePad =
              (constraints.maxWidth / 2 - 26).clamp(0.0, double.infinity).toDouble();
          return Container(
            color: const Color(0xFF0C0C10),
            child: Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    SizedBox(
                      height: 25,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.view_timeline_outlined,
                              size: 13,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Timeline',
                              style: TextStyle(fontSize: 9, color: Colors.white54),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: onEdit,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                              ),
                              icon: const Icon(Icons.content_cut_rounded, size: 13),
                              label: const Text(
                                'Edit',
                                style: TextStyle(fontSize: 9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            SizedBox(width: sidePad),
                            if (_mediaPath == null)
                              _EmptyTimelineClip(onImport: onImport)
                            else
                              _TimelineClip(
                                title: _mediaName,
                                duration: snapshot.duration,
                              ),
                            const SizedBox(width: 8),
                            _AddClipButton(onPressed: onImport),
                            SizedBox(width: sidePad),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
                Positioned(
                  left: constraints.maxWidth / 2 - 7,
                  top: 20,
                  child: const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth / 2 - 0.75,
                  top: 31,
                  bottom: 5,
                  child: Container(width: 1.5, color: Colors.white),
                ),
              ],
            ),
          );
        },
      );
}

class _TimelineClip extends StatelessWidget {
  const _TimelineClip({required this.title, required this.duration});

  final String title;
  final Duration duration;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 270,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF252A30),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Row(
                      children: List<Widget>.generate(
                        8,
                        (index) => Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: index == 7
                                      ? Colors.transparent
                                      : Colors.white10,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.movie_outlined,
                              size: 16,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 7,
                    bottom: 4,
                    right: 7,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${duration.inSeconds}s',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 17,
              decoration: BoxDecoration(
                color: const Color(0xFF163B35),
                borderRadius: BorderRadius.circular(3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.graphic_eq_rounded, size: 11, color: Colors.white54),
                  SizedBox(width: 4),
                  Text(
                    'Audio',
                    style: TextStyle(fontSize: 8, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _EmptyTimelineClip extends StatelessWidget {
  const _EmptyTimelineClip({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onImport,
        child: Container(
          width: 205,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF17171C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.add_photo_alternate_outlined, size: 18),
              SizedBox(width: 7),
              Text('Add media', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
}

class _AddClipButton extends StatelessWidget {
  const _AddClipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 38,
        height: 72,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Icon(Icons.add_rounded, size: 20),
        ),
      );
}

class _FeatureRibbon extends StatelessWidget {
  const _FeatureRibbon({
    required this.features,
    required this.selectedId,
    required this.supported,
    required this.onSelected,
  });

  final List<EngineUiFeature> features;
  final String? selectedId;
  final bool Function(String) supported;
  final ValueChanged<EngineUiFeature> onSelected;

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF101014),
        child: Center(
          child: Text(
            'No controls in this workspace',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101014),
        border: Border(top: BorderSide(color: Color(0xFF222227))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: features.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final feature = features[index];
          final selected = feature.id == selectedId;
          final enabled = supported(feature.id);
          return InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => onSelected(feature),
            child: Container(
              width: 76,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    _featureIcon(feature.id),
                    size: 18,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : enabled
                            ? Colors.white70
                            : Colors.white30,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _shortFeatureTitle(feature.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: selected
                          ? Colors.white
                          : enabled
                              ? Colors.white60
                              : Colors.white30,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({
    required this.workspaces,
    required this.selected,
    required this.onSelected,
  });

  final List<EngineWorkspace> workspaces;
  final EngineWorkspace selected;
  final ValueChanged<EngineWorkspace> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF09090C),
          border: Border(top: BorderSide(color: Color(0xFF1D1D22))),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          itemCount: workspaces.length,
          itemBuilder: (context, index) {
            final item = workspaces[index];
            final active = item == selected;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(item),
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: 20,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _workspaceLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? Colors.white : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _MobileInspectorPanel extends StatelessWidget {
  const _MobileInspectorPanel({
    super.key,
    required this.feature,
    required this.supported,
    required this.sliders,
    required this.toggles,
    required this.choices,
    required this.dispatch,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
    required this.onClose,
  });

  final EngineUiFeature feature;
  final bool supported;
  final Map<String, double> sliders;
  final Map<String, bool> toggles;
  final Map<String, String> choices;
  final Future<void> Function(String, String, [Object?]) dispatch;
  final void Function(String, double) onSlider;
  final void Function(String, bool) onToggle;
  final void Function(String, String) onChoice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111116),
          border: Border(top: BorderSide(color: Color(0xFF292930))),
        ),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 38,
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Close controls',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  Expanded(
                    child: Text(
                      feature.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: supported
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Text(
                      supported ? 'Engine' : 'Unavailable',
                      style: TextStyle(
                        fontSize: 8,
                        color: supported
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildControls(context)),
          ],
        ),
      );

  Widget _buildControls(BuildContext context) {
    if (feature.id == 'color.primaryWheels') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 16),
        child: ProfessionalPrimaryWheelsControls(
          supported: supported,
          dispatch: dispatch,
        ),
      );
    }
    if (feature.id == 'color.logWheels') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 16),
        child: ProfessionalLogWheelsControls(
          supported: supported,
          dispatch: dispatch,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 14),
      children: <Widget>[
        Text(
          feature.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9, color: Colors.white38),
        ),
        const SizedBox(height: 7),
        for (final control in feature.controls) _control(context, control),
      ],
    );
  }

  Widget _control(BuildContext context, EngineUiControl control) {
    final key = '${feature.id}.${control.id}';
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            height: 34,
            child: FilledButton.tonalIcon(
              onPressed: supported ? () => dispatch(feature.id, control.id) : null,
              icon: const Icon(Icons.touch_app_outlined, size: 15),
              label: Text(control.label, style: const TextStyle(fontSize: 10)),
            ),
          ),
        );
      case EngineControlType.slider:
        final value = (sliders[key] ?? control.initial)
            .clamp(control.min, control.max)
            .toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      control.label,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      value.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, color: Colors.white60),
                    ),
                  ),
                ],
              ),
              Slider(
                min: control.min,
                max: control.max,
                value: value,
                onChanged: !supported
                    ? null
                    : (next) {
                        onSlider(key, next);
                        unawaited(dispatch(feature.id, control.id, next));
                      },
              ),
            ],
          ),
        );
      case EngineControlType.toggle:
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(control.label, style: const TextStyle(fontSize: 10)),
          value: toggles[key] ?? false,
          onChanged: !supported
              ? null
              : (next) {
                  onToggle(key, next);
                  unawaited(dispatch(feature.id, control.id, next));
                },
        );
      case EngineControlType.choice:
        final selected = choices[key] ??
            (control.choices.isEmpty ? null : control.choices.first);
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            style: const TextStyle(fontSize: 10, color: Colors.white),
            decoration: InputDecoration(
              labelText: control.label,
              labelStyle: const TextStyle(fontSize: 10),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            ),
            items: <DropdownMenuItem<String>>[
              for (final item in control.choices)
                DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: !supported
                ? null
                : (next) {
                    if (next == null) return;
                    onChoice(key, next);
                    unawaited(dispatch(feature.id, control.id, next));
                  },
          ),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(control.label, style: const TextStyle(fontSize: 10)),
        );
    }
  }
}

IconData _featureIcon(String id) {
  if (id.startsWith('timeline.clip') || id.startsWith('timeline.trim')) {
    return Icons.content_cut_rounded;
  }
  if (id.startsWith('timeline')) return Icons.view_timeline_outlined;
  if (id.startsWith('media')) return Icons.video_library_outlined;
  if (id.startsWith('project')) return Icons.folder_open_outlined;
  if (id.startsWith('audio')) return Icons.graphic_eq_rounded;
  if (id.startsWith('transform')) return Icons.crop_rotate_rounded;
  if (id.startsWith('composite')) return Icons.layers_outlined;
  if (id.startsWith('color')) return Icons.color_lens_outlined;
  if (id.startsWith('effects')) return Icons.auto_awesome_outlined;
  if (id.startsWith('nodes')) return Icons.account_tree_outlined;
  if (id.startsWith('playback')) return Icons.play_circle_outline_rounded;
  if (id.startsWith('analysis')) return Icons.monitor_heart_outlined;
  if (id.startsWith('export')) return Icons.file_upload_outlined;
  if (id.startsWith('runtime')) return Icons.speed_rounded;
  if (id.startsWith('engine')) return Icons.memory_outlined;
  return Icons.tune_rounded;
}

String _workspaceLabel(EngineWorkspace workspace) {
  switch (workspace) {
    case EngineWorkspace.correction:
      return 'Adjust';
    case EngineWorkspace.looks:
      return 'Filters';
    case EngineWorkspace.masks:
      return 'Mask';
    case EngineWorkspace.performance:
      return 'Perf';
    default:
      return workspace.label;
  }
}

String _shortFeatureTitle(String value) {
  return value
      .replaceAll('Production ', '')
      .replaceAll('Professional ', '')
      .replaceAll('Multitrack ', '')
      .replaceAll('Engine ', '');
}
