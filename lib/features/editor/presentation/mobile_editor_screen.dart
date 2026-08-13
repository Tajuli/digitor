import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine/engine_feature_catalog.dart';
import '../../../core/engine/engine_gateway.dart';

/// Phone-first editor shell for Digitor.
///
/// The desktop editor intentionally keeps its multi-pane layout. Phones use
/// this screen instead: a compact app bar, horizontal workspace navigation,
/// engine preview/transport, and a vertically scrollable tool inspector.
class MobileEditorScreen extends StatefulWidget {
  const MobileEditorScreen({super.key, required this.engine});

  final EngineGateway engine;

  @override
  State<MobileEditorScreen> createState() => _MobileEditorScreenState();
}

class _MobileEditorScreenState extends State<MobileEditorScreen> {
  EngineWorkspace workspace = EngineWorkspace.media;
  EngineSnapshot snapshot = EngineSnapshot.disconnected;
  List<EngineCapability> capabilities = const <EngineCapability>[];
  EngineProgress? progress;
  String? error;

  final Map<String, double> sliders = <String, double>{};
  final Map<String, bool> toggles = <String, bool>{};
  final Map<String, String> choices = <String, String>{};
  final List<StreamSubscription<Object?>> subscriptions =
      <StreamSubscription<Object?>>[];

  List<EngineUiFeature> get features => engineFeatureCatalog
      .where((feature) => feature.workspace == workspace)
      .toList(growable: false);

  int? get previewTextureId => snapshot.state['previewTextureId'] as int?;
  int get previewWidth => snapshot.state['previewWidth'] as int? ?? 0;
  int get previewHeight => snapshot.state['previewHeight'] as int? ?? 0;

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

  void _handleEngineEvent(EngineEvent event) {
    if (!mounted) return;
    if (event.type != 'unsupportedAction' &&
        event.type != 'engineError' &&
        event.type != 'previewError') {
      return;
    }
    final message = event.payload['error']?.toString() ??
        'Engine API not exposed for ${event.payload['action']}';
    setState(() => error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    }
  }

  Future<void> _dispatch(
    String feature,
    String control, [
    Object? value,
  ]) async {
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
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = '$exception');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$exception')),
      );
    }
  }

  bool _supported(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability.supported;
    }
    return false;
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
    final showTimeline = workspace == EngineWorkspace.edit ||
        workspace == EngineWorkspace.playback;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildTopBar(context),
            if (progress != null && progress!.fraction < 1)
              LinearProgressIndicator(value: progress!.fraction),
            if (error != null) _buildErrorBanner(context),
            _buildWorkspaceBar(context),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(flex: 5, child: _buildCanvas(context)),
                  const Divider(height: 1),
                  _buildTransport(context),
                  if (showTimeline) ...<Widget>[
                    const Divider(height: 1),
                    _buildTimeline(context),
                  ],
                  const Divider(height: 1),
                  Expanded(flex: 4, child: _buildToolPanel(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          children: <Widget>[
            const Icon(Icons.movie_outlined, size: 22),
            const SizedBox(width: 7),
            Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Import media',
              onPressed: () => _dispatch('media.import', 'requestPicker'),
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            Tooltip(
              message:
                  snapshot.connected ? 'Engine connected' : 'Engine disconnected',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Icon(
                  snapshot.connected ? Icons.check_circle : Icons.link_off,
                  size: 20,
                  color: snapshot.connected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Export',
              onPressed: () =>
                  setState(() => workspace = EngineWorkspace.export),
              icon: const Icon(Icons.file_upload_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: _initialize, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceBar(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        itemCount: EngineWorkspace.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final item = EngineWorkspace.values[index];
          final selected = item == workspace;
          return InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => setState(() => workspace = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(item.icon, size: 17),
                  const SizedBox(width: 5),
                  Text(item.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    if (workspace == EngineWorkspace.export) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.file_upload_outlined, size: 34),
                const SizedBox(height: 8),
                Text('Production Export',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'Preview and export use the DigitorEngine production path.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _supported('export.production')
                      ? () => _dispatch('export.production', 'start')
                      : null,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Start export'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (workspace == EngineWorkspace.engine ||
        workspace == EngineWorkspace.performance) {
      final supportedCount =
          capabilities.where((capability) => capability.supported).length;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Text('DigitorEngine', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(snapshot.connected ? 'Native engine connected' : 'Disconnected'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              Chip(label: Text('Runtime ${capabilities.length}')),
              Chip(label: Text('Supported $supportedCount')),
            ],
          ),
        ],
      );
    }

    final textureId = previewTextureId;
    return ColoredBox(
      color: const Color(0xFF080808),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: previewWidth > 0 && previewHeight > 0
                    ? previewWidth / previewHeight
                    : 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: textureId == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.video_file_outlined,
                                  size: 44, color: Colors.white24),
                              SizedBox(height: 7),
                              Text(
                                'Import media to start preview',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ],
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
            top: 8,
            child: Text(
              workspace.label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransport(BuildContext context) {
    final position = snapshot.state['positionUs'] as int? ?? 0;
    final seconds = position / 1000000.0;
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            tooltip: 'Previous frame',
            onPressed: () =>
                _dispatch('playback.transport', 'previousFrame'),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filledTonal(
            tooltip: 'Play / Pause',
            onPressed: () => _dispatch('playback.transport', 'playPause'),
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Next frame',
            onPressed: () => _dispatch('playback.transport', 'nextFrame'),
            icon: const Icon(Icons.skip_next),
          ),
          const SizedBox(width: 8),
          Text('${seconds.toStringAsFixed(2)} s',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final mediaPath = snapshot.state['mediaPath']?.toString();
    return SizedBox(
      height: 82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 10),
              const Icon(Icons.videocam_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mediaPath ?? 'No media on timeline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolPanel(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 24),
      children: <Widget>[
        for (final feature in features) _featureCard(context, feature),
      ],
    );
  }

  Widget _featureCard(BuildContext context, EngineUiFeature feature) {
    final isSupported = _supported(feature.id);
    final engineManagedZeroCopy = feature.id == 'media.zeroCopy';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(feature.title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Icon(
                  isSupported
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              feature.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (engineManagedZeroCopy) ...<Widget>[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text('Engine managed')),
              ),
            ] else
              for (final control in feature.controls)
                _control(context, feature, control, isSupported),
          ],
        ),
      ),
    );
  }

  Widget _control(
    BuildContext context,
    EngineUiFeature feature,
    EngineUiControl control,
    bool enabled,
  ) {
    final key = '${feature.id}.${control.id}';
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.only(top: 7),
          child: OutlinedButton(
            onPressed:
                enabled ? () => _dispatch(feature.id, control.id) : null,
            child: Text(control.label),
          ),
        );
      case EngineControlType.slider:
        final value = (sliders[key] ?? control.initial)
            .clamp(control.min, control.max)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(child: Text(control.label)),
                Text(value.toStringAsFixed(2)),
              ],
            ),
            Slider(
              min: control.min,
              max: control.max,
              value: value,
              onChanged: !enabled
                  ? null
                  : (next) {
                      setState(() => sliders[key] = next);
                      unawaited(_dispatch(feature.id, control.id, next));
                    },
            ),
          ],
        );
      case EngineControlType.toggle:
        return SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(control.label),
          value: toggles[key] ?? false,
          onChanged: !enabled
              ? null
              : (next) {
                  setState(() => toggles[key] = next);
                  unawaited(_dispatch(feature.id, control.id, next));
                },
        );
      case EngineControlType.choice:
        final selected = choices[key] ??
            (control.choices.isEmpty ? null : control.choices.first);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: control.label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final choice in control.choices)
                DropdownMenuItem(value: choice, child: Text(choice)),
            ],
            onChanged: !enabled
                ? null
                : (next) {
                    if (next == null) return;
                    setState(() => choices[key] = next);
                    unawaited(_dispatch(feature.id, control.id, next));
                  },
          ),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(control.label),
        );
    }
  }
}
