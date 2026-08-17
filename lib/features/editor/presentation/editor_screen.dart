import 'dart:async';

import 'package:flutter/material.dart';

import 'professional_color_wheels.dart';

import '../../../core/engine/engine_feature_catalog.dart';
import '../../../core/engine/engine_gateway.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.engine});
  final EngineGateway engine;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EngineWorkspace workspace = EngineWorkspace.media;
  EngineSnapshot snapshot = EngineSnapshot.disconnected;
  List<EngineCapability> capabilities = const <EngineCapability>[];
  EngineProgress? progress;
  String? error;
  String? selectedFeatureId;
  String? exportMessage;
  final sliders = <String, double>{};
  final toggles = <String, bool>{};
  final choices = <String, String>{};
  final subscriptions = <StreamSubscription<Object?>>[];

  List<EngineUiFeature> get features => engineFeatureCatalog
      .where((feature) => feature.workspace == workspace)
      .toList(growable: false);

  EngineUiFeature? get selectedFeature {
    final current = features;
    if (current.isEmpty) return null;
    for (final feature in current) {
      if (feature.id == selectedFeatureId) return feature;
    }
    return current.first;
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
    unawaited(initialize());
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
              duration: const Duration(seconds: 7),
              content: Text(path == null ? 'Export complete' : 'Export complete\n$path'),
              action: SnackBarAction(label: 'OK', onPressed: () {}),
            ),
          );
        return;
      case 'exportLocationRequired':
        setState(() => exportMessage = 'Export cancelled');
        return;
      case 'unsupportedAction':
      case 'engineError':
      case 'previewError':
        final isExportFailure = value.type == 'engineError' &&
            value.payload['action']?.toString() == 'export.production.start';
        final message = value.payload['error']?.toString() ??
            'Engine API not exposed for ${value.payload['action']}';
        setState(() {
          error = message;
          if (isExportFailure) exportMessage = 'Export failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isExportFailure ? 'Export failed\n$message' : message)),
        );
        return;
    }
  }

  Future<void> initialize() async {
    try {
      await widget.engine.initialize();
      final next = await widget.engine.discoverCapabilities();
      if (mounted) {
        setState(() {
          capabilities = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> dispatch(String feature, String control, [Object? value]) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  bool supported(String id) {
    for (final item in capabilities) {
      if (item.id == id) return item.supported;
    }
    return false;
  }

  void _selectWorkspace(EngineWorkspace value) {
    final next = engineFeatureCatalog
        .where((feature) => feature.workspace == value)
        .toList(growable: false);
    setState(() {
      workspace = value;
      selectedFeatureId = next.isEmpty ? null : next.first.id;
    });
  }

  @override
  void dispose() {
    for (final item in subscriptions) {
      unawaited(item.cancel());
    }
    unawaited(widget.engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inspectorFeature = selectedFeature;
    final wideColorWheels = inspectorFeature?.id == 'color.primaryWheels' ||
        inspectorFeature?.id == 'color.logWheels';
    final nodeWorkspace = workspace == EngineWorkspace.nodes;
    final inspectorWidth = nodeWorkspace ? 430.0 : (wideColorWheels ? 620.0 : 350.0);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              snapshot: snapshot,
              progress: progress,
              exportMessage: exportMessage,
              onImport: () => dispatch('media.import', 'requestPicker'),
              onExport: () => _selectWorkspace(EngineWorkspace.export),
            ),
            if (error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.warning_amber_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: SelectableText(error!, maxLines: 2)),
                      TextButton(onPressed: initialize, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: <Widget>[
                  _WorkspaceRail(selected: workspace, onSelected: _selectWorkspace),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 245,
                    child: _FeatureList(
                      features: features,
                      supported: supported,
                      selectedId: inspectorFeature?.id,
                      onSelected: (feature) =>
                          setState(() => selectedFeatureId = feature.id),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: _Canvas(
                            workspace: workspace,
                            snapshot: snapshot,
                            capabilities: capabilities,
                            progress: progress,
                            exportMessage: exportMessage,
                            dispatch: dispatch,
                          ),
                        ),
                        const Divider(height: 1),
                        _Transport(snapshot: snapshot, dispatch: dispatch),
                        const Divider(height: 1),
                        SizedBox(height: 150, child: _Timeline(snapshot: snapshot)),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: inspectorWidth,
                    child: nodeWorkspace
                        ? _NodeGraphPanel(dispatch: dispatch)
                        : ListView(
                            padding: const EdgeInsets.all(10),
                            children: <Widget>[
                              Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              if (inspectorFeature == null)
                                const Text('Select a feature to edit its controls.')
                              else
                                _FeatureControls(
                                  key: ValueKey(inspectorFeature.id),
                                  feature: inspectorFeature,
                                  supported: supported(inspectorFeature.id),
                                  sliders: sliders,
                                  toggles: toggles,
                                  choices: choices,
                                  dispatch: dispatch,
                                  onSlider: (key, value) => setState(() => sliders[key] = value),
                                  onToggle: (key, value) => setState(() => toggles[key] = value),
                                  onChoice: (key, value) => setState(() => choices[key] = value),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.snapshot,
    required this.progress,
    required this.exportMessage,
    required this.onImport,
    required this.onExport,
  });

  final EngineSnapshot snapshot;
  final EngineProgress? progress;
  final String? exportMessage;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              const Icon(Icons.movie_outlined),
              const SizedBox(width: 8),
              Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 18),
              TextButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Import'),
              ),
              const Spacer(),
              if (progress != null && progress!.operation == 'export') ...<Widget>[
                SizedBox(
                  width: 165,
                  child: Row(
                    children: <Widget>[
                      Expanded(child: LinearProgressIndicator(value: progress!.fraction)),
                      const SizedBox(width: 8),
                      Text('${(progress!.fraction * 100).round()}%'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (exportMessage != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    exportMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(width: 10),
              Chip(
                avatar: Icon(
                  snapshot.connected ? Icons.check_circle : Icons.link_off,
                  size: 16,
                ),
                label: Text(snapshot.connected ? 'Engine connected' : 'Disconnected'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Export'),
              ),
            ],
          ),
        ),
      );
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({required this.selected, required this.onSelected});
  final EngineWorkspace selected;
  final ValueChanged<EngineWorkspace> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 88,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 5),
          children: <Widget>[
            for (final item in EngineWorkspace.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onSelected(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: selected == item
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Colors.transparent,
                    ),
                    child: Column(
                      children: <Widget>[
                        Icon(item.icon, size: 20),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({
    required this.features,
    required this.supported,
    required this.selectedId,
    required this.onSelected,
  });
  final List<EngineUiFeature> features;
  final bool Function(String) supported;
  final String? selectedId;
  final ValueChanged<EngineUiFeature> onSelected;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(8),
        children: <Widget>[
          for (final feature in features)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              color: selectedId == feature.id
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              child: ListTile(
                dense: true,
                selected: selectedId == feature.id,
                onTap: () => onSelected(feature),
                title: Text(feature.title),
                subtitle: Text(
                  feature.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  supported(feature.id)
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  size: 16,
                ),
              ),
            ),
        ],
      );
}

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.workspace,
    required this.snapshot,
    required this.capabilities,
    required this.progress,
    required this.exportMessage,
    required this.dispatch,
  });

  final EngineWorkspace workspace;
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;
  final EngineProgress? progress;
  final String? exportMessage;
  final Future<void> Function(String, String, [Object?]) dispatch;

  int? get textureId => snapshot.state['previewTextureId'] as int?;
  int get width => snapshot.state['previewWidth'] as int? ?? 0;
  int get height => snapshot.state['previewHeight'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    if (workspace == EngineWorkspace.scopes) {
      return GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        childAspectRatio: 16 / 7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: const <Widget>[
          _Scope('Waveform'),
          _Scope('RGB Parade'),
          _Scope('Vectorscope'),
          _Scope('Histogram'),
        ],
      );
    }

    if (workspace == EngineWorkspace.export) {
      final exportProgress = progress?.operation == 'export' ? progress!.fraction : null;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            margin: const EdgeInsets.all(26),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Delivery', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 7),
                  const Text(
                    'Production export uses the same DigitorEngine node recipe and native render path as preview.',
                  ),
                  if (exportProgress != null) ...<Widget>[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(value: exportProgress),
                    const SizedBox(height: 6),
                    Text(
                      exportProgress >= 1
                          ? '100% · Export complete'
                          : '${(exportProgress * 100).round()}% · Exporting…',
                    ),
                  ],
                  if (exportMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    SelectableText(exportMessage!),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => dispatch('export.production', 'start'),
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Start export'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (workspace == EngineWorkspace.engine ||
        workspace == EngineWorkspace.performance) {
      final count = capabilities.where((item) => item.supported).length;
      return ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Text('DigitorEngine', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(snapshot.connected ? 'Native engine connected' : 'Engine unavailable'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              Chip(label: Text('UI ${engineFeatureCatalog.length}')),
              Chip(label: Text('Runtime ${capabilities.length}')),
              Chip(label: Text('Direct $count')),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(snapshot.state.toString()),
        ],
      );
    }

    final id = textureId;
    return ColoredBox(
      color: const Color(0xFF080808),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: width > 0 && height > 0 ? width / height : 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: id == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.video_file_outlined, size: 54, color: Colors.white24),
                              SizedBox(height: 8),
                              Text(
                                'Import media to start Engine preview',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ],
                          ),
                        )
                      : Texture(textureId: id, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          ),
          Positioned(left: 14, top: 12, child: Text('${workspace.label} · DigitorEngine')),
          Positioned(
            right: 14,
            top: 12,
            child: Text(
              id == null
                  ? (snapshot.engineMessage ?? 'Waiting for Engine frame')
                  : 'GPU Texture $id · ${width}×$height',
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.snapshot, required this.dispatch});
  final EngineSnapshot snapshot;
  final Future<void> Function(String, String, [Object?]) dispatch;

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
        '${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_time(snapshot.position)),
            const SizedBox(width: 14),
            IconButton(
              onPressed: () => dispatch('playback.transport', 'previousFrame'),
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              onPressed: () => dispatch('playback.transport', 'playPause'),
              icon: Icon(snapshot.isPlaying ? Icons.pause_circle : Icons.play_circle),
              iconSize: 30,
            ),
            IconButton(
              onPressed: () => dispatch('playback.transport', 'stop'),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
            IconButton(
              onPressed: () => dispatch('playback.transport', 'nextFrame'),
              icon: const Icon(Icons.skip_next),
            ),
            const SizedBox(width: 14),
            Text(_time(snapshot.duration)),
          ],
        ),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.snapshot});
  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          const SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('MULTITRACK TIMELINE · engine-owned state'),
              ),
            ),
          ),
          if (snapshot.state['mediaPath'] != null)
            Expanded(
              child: _Track('V1', Icons.videocam_outlined, snapshot.state['mediaPath']!.toString()),
            )
          else
            const Expanded(child: _Track('V1', Icons.videocam_outlined, 'No media')),
          const Expanded(child: _Track('A1', Icons.audiotrack_outlined, 'Engine audio')),
        ],
      );
}

class _NodeGraphPanel extends StatelessWidget {
  const _NodeGraphPanel({required this.dispatch});

  final Future<void> Function(String, String, [Object?]) dispatch;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF0D0D0D),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.account_tree_outlined, size: 18),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Node Graph',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF090909),
                    border: Border.all(color: Colors.white10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        _Node('Input', Icons.input),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: Colors.white24, size: 18),
                        SizedBox(width: 8),
                        _Node('Grade', Icons.tune),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: Colors.white24, size: 18),
                        SizedBox(width: 8),
                        _Node('Output', Icons.output),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => dispatch('nodes.graph', 'addSerial'),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Serial'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => dispatch('nodes.graph', 'addParallel'),
                    icon: const Icon(Icons.call_split, size: 17),
                    label: const Text('Parallel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _Node extends StatelessWidget {
  const _Node(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(
          width: 110,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 19),
              const SizedBox(height: 5),
              Text(title),
            ],
          ),
        ),
      );
}

class _Scope extends StatelessWidget {
  const _Scope(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        child: Stack(
          children: <Widget>[
            Positioned(left: 12, top: 10, child: Text(title)),
            const Center(
              child: Icon(Icons.monitor_heart_outlined, size: 54, color: Colors.white24),
            ),
          ],
        ),
      );
}

class _Track extends StatelessWidget {
  const _Track(this.label, this.icon, this.content);
  final String label;
  final IconData icon;
  final String content;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 15),
                const SizedBox(width: 5),
                Text(label),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          ),
        ],
      );
}

class _FeatureControls extends StatelessWidget {
  const _FeatureControls({
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

  @override
  Widget build(BuildContext context) {
    if (feature.id == 'color.primaryWheels') {
      return ProfessionalPrimaryWheelsControls(
        supported: supported,
        dispatch: dispatch,
      );
    }
    if (feature.id == 'color.logWheels') {
      return ProfessionalLogWheelsControls(
        supported: supported,
        dispatch: dispatch,
      );
    }
    if (feature.id == 'color.rgbCurves') {
      return _RgbCurvesControls(supported: supported, dispatch: dispatch);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _FeatureHeader(feature: feature, supported: supported),
            const SizedBox(height: 6),
            for (final control in feature.controls) _control(context, control),
          ],
        ),
      ),
    );
  }

  Widget _control(BuildContext context, EngineUiControl control) {
    final key = '${feature.id}.${control.id}';
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: OutlinedButton(
            onPressed: supported ? () => dispatch(feature.id, control.id) : null,
            child: Text(control.label),
          ),
        );
      case EngineControlType.slider:
        final value = (sliders[key] ?? control.initial)
            .clamp(control.min, control.max)
            .toDouble();
        return _LabeledSlider(
          label: control.label,
          value: value,
          min: control.min,
          max: control.max,
          enabled: supported,
          onChanged: (next) {
            onSlider(key, next);
            unawaited(dispatch(feature.id, control.id, next));
          },
        );
      case EngineControlType.toggle:
        return SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(control.label),
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: control.label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final item in control.choices)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: !supported
                ? null
                : (next) {
                    if (next != null) {
                      onChoice(key, next);
                      unawaited(dispatch(feature.id, control.id, next));
                    }
                  },
          ),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(control.label),
        );
    }
  }
}

class _FeatureHeader extends StatelessWidget {
  const _FeatureHeader({required this.feature, required this.supported});
  final EngineUiFeature feature;
  final bool supported;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: Text(feature.title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Icon(
            supported ? Icons.check_circle_outline : Icons.info_outline,
            size: 15,
          ),
        ],
      );
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label)),
              Text(value.toStringAsFixed(2)),
            ],
          ),
          Slider(
            min: min,
            max: max,
            value: value.clamp(min, max).toDouble(),
            onChanged: enabled ? onChanged : null,
          ),
        ],
      );
}

class _LogWheelsControls extends StatefulWidget {
  const _LogWheelsControls({required this.supported, required this.dispatch});
  final bool supported;
  final Future<void> Function(String, String, [Object?]) dispatch;

  @override
  State<_LogWheelsControls> createState() => _LogWheelsControlsState();
}

class _LogWheelsControlsState extends State<_LogWheelsControls> {
  String range = 'shadows';
  final values = <String, double>{
    'shadowPivot': 0.33,
    'highlightPivot': 0.67,
    'transitionWidth': 0.10,
  };

  double value(String key, [double fallback = 0]) => values[key] ?? fallback;

  void setValue(String key, double next) {
    setState(() => values[key] = next);
    unawaited(widget.dispatch('color.logWheels', key, next));
  }

  void reset() {
    setState(() {
      values
        ..clear()
        ..addAll(<String, double>{
          'shadowPivot': 0.33,
          'highlightPivot': 0.67,
          'transitionWidth': 0.10,
        });
    });
    unawaited(widget.dispatch('color.logWheels', 'reset'));
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Log Wheels', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Icon(
                    widget.supported ? Icons.check_circle_outline : Icons.info_outline,
                    size: 15,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment(value: 'shadows', label: Text('Shadows')),
                  ButtonSegment(value: 'midtones', label: Text('Midtones')),
                  ButtonSegment(value: 'highlights', label: Text('Highlights')),
                  ButtonSegment(value: 'global', label: Text('Global')),
                ],
                selected: <String>{range},
                showSelectedIcon: false,
                onSelectionChanged: widget.supported
                    ? (next) => setState(() => range = next.first)
                    : null,
              ),
              const SizedBox(height: 10),
              for (final component in const <(String, String)>[
                ('r', 'Red'),
                ('g', 'Green'),
                ('b', 'Blue'),
                ('master', 'Master'),
              ])
                _LabeledSlider(
                  label: component.$2,
                  value: value('$range.${component.$1}'),
                  min: -2,
                  max: 2,
                  enabled: widget.supported,
                  onChanged: (next) => setValue('$range.${component.$1}', next),
                ),
              const Divider(),
              _LabeledSlider(
                label: 'Shadow Pivot',
                value: value('shadowPivot', 0.33),
                min: 0.05,
                max: 0.60,
                enabled: widget.supported,
                onChanged: (next) => setValue('shadowPivot', next),
              ),
              _LabeledSlider(
                label: 'Highlight Pivot',
                value: value('highlightPivot', 0.67),
                min: 0.40,
                max: 0.95,
                enabled: widget.supported,
                onChanged: (next) => setValue('highlightPivot', next),
              ),
              _LabeledSlider(
                label: 'Transition',
                value: value('transitionWidth', 0.10),
                min: 0.01,
                max: 0.30,
                enabled: widget.supported,
                onChanged: (next) => setValue('transitionWidth', next),
              ),
              const SizedBox(height: 5),
              OutlinedButton.icon(
                onPressed: widget.supported ? reset : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset Log Wheels'),
              ),
            ],
          ),
        ),
      );
}

class _RgbCurvesControls extends StatefulWidget {
  const _RgbCurvesControls({required this.supported, required this.dispatch});
  final bool supported;
  final Future<void> Function(String, String, [Object?]) dispatch;

  @override
  State<_RgbCurvesControls> createState() => _RgbCurvesControlsState();
}

class _RgbCurvesControlsState extends State<_RgbCurvesControls> {
  String channel = 'master';
  int? selectedPoint;
  final curves = <String, List<Offset>>{
    'master': <Offset>[const Offset(0, 0), const Offset(1, 1)],
    'red': <Offset>[const Offset(0, 0), const Offset(1, 1)],
    'green': <Offset>[const Offset(0, 0), const Offset(1, 1)],
    'blue': <Offset>[const Offset(0, 0), const Offset(1, 1)],
  };

  List<Offset> get points => curves[channel]!;

  void _commit() {
    final payload = <String, Object?>{
      'channel': channel,
      'points': <Map<String, double>>[
        for (final point in points) <String, double>{'x': point.dx, 'y': point.dy},
      ],
    };
    unawaited(widget.dispatch('color.rgbCurves', 'points', payload));
  }

  void _resetChannel() {
    setState(() {
      curves[channel] = <Offset>[const Offset(0, 0), const Offset(1, 1)];
      selectedPoint = null;
    });
    _commit();
  }

  void _resetAll() {
    setState(() {
      for (final key in curves.keys) {
        curves[key] = <Offset>[const Offset(0, 0), const Offset(1, 1)];
      }
      selectedPoint = null;
    });
    unawaited(widget.dispatch('color.rgbCurves', 'reset'));
  }

  void _addPoint(Offset normalized) {
    if (!widget.supported) return;
    final next = Offset(
      normalized.dx.clamp(0.001, 0.999).toDouble(),
      normalized.dy.clamp(0.0, 1.0).toDouble(),
    );
    setState(() {
      points.add(next);
      points.sort((a, b) => a.dx.compareTo(b.dx));
      selectedPoint = points.indexOf(next);
    });
    _commit();
  }

  void _movePoint(int index, Offset normalized) {
    if (!widget.supported || index < 0 || index >= points.length) return;
    final endpoint = index == 0 || index == points.length - 1;
    final minX = index == 0 ? 0.0 : points[index - 1].dx + 0.001;
    final maxX = index == points.length - 1 ? 1.0 : points[index + 1].dx - 0.001;
    final next = Offset(
      endpoint
          ? (index == 0 ? 0.0 : 1.0)
          : normalized.dx.clamp(minX, maxX).toDouble(),
      normalized.dy.clamp(0.0, 1.0).toDouble(),
    );
    setState(() {
      points[index] = next;
      selectedPoint = index;
    });
    _commit();
  }

  void _deleteSelected() {
    final index = selectedPoint;
    if (index == null || index <= 0 || index >= points.length - 1) return;
    setState(() {
      points.removeAt(index);
      selectedPoint = null;
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('RGB Curves', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Icon(
                    widget.supported ? Icons.check_circle_outline : Icons.info_outline,
                    size: 15,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment(value: 'master', label: Text('Master')),
                  ButtonSegment(value: 'red', label: Text('R')),
                  ButtonSegment(value: 'green', label: Text('G')),
                  ButtonSegment(value: 'blue', label: Text('B')),
                ],
                selected: <String>{channel},
                showSelectedIcon: false,
                onSelectionChanged: widget.supported
                    ? (next) => setState(() {
                          channel = next.first;
                          selectedPoint = null;
                        })
                    : null,
              ),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 1.15,
                child: _CurveSurface(
                  enabled: widget.supported,
                  points: points,
                  selectedPoint: selectedPoint,
                  onSelect: (index) => setState(() => selectedPoint = index),
                  onAdd: _addPoint,
                  onMove: _movePoint,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Long-press to add a point. Drag points to shape the curve.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: widget.supported &&
                            selectedPoint != null &&
                            selectedPoint! > 0 &&
                            selectedPoint! < points.length - 1
                        ? _deleteSelected
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete point'),
                  ),
                  OutlinedButton(
                    onPressed: widget.supported ? _resetChannel : null,
                    child: const Text('Reset channel'),
                  ),
                  OutlinedButton(
                    onPressed: widget.supported ? _resetAll : null,
                    child: const Text('Reset all'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _CurveSurface extends StatefulWidget {
  const _CurveSurface({
    required this.enabled,
    required this.points,
    required this.selectedPoint,
    required this.onSelect,
    required this.onAdd,
    required this.onMove,
  });
  final bool enabled;
  final List<Offset> points;
  final int? selectedPoint;
  final ValueChanged<int> onSelect;
  final ValueChanged<Offset> onAdd;
  final void Function(int, Offset) onMove;

  @override
  State<_CurveSurface> createState() => _CurveSurfaceState();
}

class _CurveSurfaceState extends State<_CurveSurface> {
  int? dragging;

  Offset _normalized(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
        (1 - local.dy / size.height).clamp(0.0, 1.0).toDouble(),
      );

  int? _hit(Offset local, Size size) {
    var best = 18.0;
    int? index;
    for (var i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      final screen = Offset(point.dx * size.width, (1 - point.dy) * size.height);
      final distance = (screen - local).distance;
      if (distance <= best) {
        best = distance;
        index = i;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: !widget.enabled
                ? null
                : (details) {
                    final hit = _hit(details.localPosition, size);
                    if (hit != null) widget.onSelect(hit);
                  },
            onLongPressStart: !widget.enabled
                ? null
                : (details) => widget.onAdd(_normalized(details.localPosition, size)),
            onPanStart: !widget.enabled
                ? null
                : (details) {
                    dragging = _hit(details.localPosition, size);
                    if (dragging != null) widget.onSelect(dragging!);
                  },
            onPanUpdate: !widget.enabled
                ? null
                : (details) {
                    final index = dragging;
                    if (index != null) {
                      widget.onMove(index, _normalized(details.localPosition, size));
                    }
                  },
            onPanEnd: (_) => dragging = null,
            child: CustomPaint(
              painter: _CurvePainter(
                points: widget.points,
                selectedPoint: widget.selectedPoint,
              ),
            ),
          );
        },
      );
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter({required this.points, required this.selectedPoint});
  final List<Offset> points;
  final int? selectedPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke,
    );

    if (points.isEmpty) return;
    final sorted = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
    Offset screen(Offset point) =>
        Offset(point.dx * size.width, (1 - point.dy) * size.height);
    final first = screen(sorted.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (var i = 1; i < sorted.length; i++) {
      final previous = screen(sorted[i - 1]);
      final current = screen(sorted[i]);
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < points.length; i++) {
      final center = screen(points[i]);
      canvas.drawCircle(
        center,
        i == selectedPoint ? 6 : 5,
        Paint()..color = i == selectedPoint ? Colors.white : Colors.white70,
      );
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
