import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine/engine_feature_catalog.dart';
import '../../../core/engine/engine_gateway.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.engine});

  final EngineGateway engine;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EngineWorkspace _workspace = EngineWorkspace.media;
  EngineSnapshot _snapshot = EngineSnapshot.disconnected();
  List<EngineCapability> _capabilities = const <EngineCapability>[];
  EngineProgress? _progress;
  String? _error;

  final Map<String, double> _sliders = <String, double>{};
  final Map<String, bool> _toggles = <String, bool>{};
  final Map<String, String> _choices = <String, String>{};
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      widget.engine.snapshots.listen((value) {
        if (mounted) setState(() => _snapshot = value);
      }),
    );
    _subscriptions.add(
      widget.engine.progress.listen((value) {
        if (mounted) setState(() => _progress = value);
      }),
    );
    _subscriptions.add(
      widget.engine.events.listen((value) {
        if (!mounted) return;
        if (value.type == 'unsupportedAction') {
          final action = value.payload['action'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Engine API not exposed for $action')),
          );
        }
      }),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.engine.initialize();
      final capabilities = await widget.engine.discoverCapabilities();
      if (mounted) {
        setState(() {
          _capabilities = capabilities;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _dispatch(String feature, String control, [Object? value]) async {
    try {
      await widget.engine.dispatch(
        EngineIntent(
          '$feature.$control',
          value == null ? const <String, Object?>{} : <String, Object?>{'value': value},
        ),
      );
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  List<EngineUiFeature> get _features => engineFeatureCatalog
      .where((feature) => feature.workspace == _workspace)
      .toList(growable: false);

  bool _supported(String id) {
    for (final capability in _capabilities) {
      if (capability.id == id) return capability.supported;
    }
    return false;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(widget.engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              snapshot: _snapshot,
              progress: _progress,
              onImport: () => _dispatch('media.import', 'requestPicker'),
              onExport: () {
                setState(() => _workspace = EngineWorkspace.export);
              },
            ),
            if (_error != null)
              _ErrorBanner(message: _error!, onRetry: _initialize),
            Expanded(
              child: Row(
                children: <Widget>[
                  _WorkspaceRail(
                    selected: _workspace,
                    onSelected: (value) => setState(() => _workspace = value),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 245,
                    child: _FeatureList(
                      features: _features,
                      capabilities: _capabilities,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: _WorkspaceCanvas(
                            workspace: _workspace,
                            snapshot: _snapshot,
                            capabilities: _capabilities,
                            onDispatch: _dispatch,
                          ),
                        ),
                        const Divider(height: 1),
                        _Transport(
                          snapshot: _snapshot,
                          onCommand: (command) =>
                              _dispatch('playback.transport', command),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 150, child: _Timeline()),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 330,
                    child: _Inspector(
                      features: _features,
                      supported: _supported,
                      sliders: _sliders,
                      toggles: _toggles,
                      choices: _choices,
                      onAction: _dispatch,
                      onSlider: (feature, control, value) {
                        setState(() => _sliders['$feature.$control'] = value);
                        unawaited(_dispatch(feature, control, value));
                      },
                      onToggle: (feature, control, value) {
                        setState(() => _toggles['$feature.$control'] = value);
                        unawaited(_dispatch(feature, control, value));
                      },
                      onChoice: (feature, control, value) {
                        setState(() => _choices['$feature.$control'] = value);
                        unawaited(_dispatch(feature, control, value));
                      },
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
    required this.onImport,
    required this.onExport,
  });

  final EngineSnapshot snapshot;
  final EngineProgress? progress;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.movie_edit_outlined),
            const SizedBox(width: 8),
            Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 18),
            TextButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Import'),
            ),
            const Spacer(),
            if (progress != null && progress!.fraction < 1)
              SizedBox(
                width: 170,
                child: Row(
                  children: <Widget>[
                    Expanded(child: LinearProgressIndicator(value: progress!.fraction)),
                    const SizedBox(width: 8),
                    Text('${(progress!.fraction * 100).round()}%'),
                  ],
                ),
              ),
            const SizedBox(width: 12),
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
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({required this.selected, required this.onSelected});
  final EngineWorkspace selected;
  final ValueChanged<EngineWorkspace> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 5),
        children: <Widget>[
          for (final workspace in EngineWorkspace.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onSelected(workspace),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: selected == workspace
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Colors.transparent,
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(workspace.icon, size: 20),
                      const SizedBox(height: 3),
                      Text(
                        workspace.label,
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
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.features, required this.capabilities});
  final List<EngineUiFeature> features;
  final List<EngineCapability> capabilities;

  bool _supported(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability.supported;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        for (final feature in features)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              dense: true,
              title: Text(feature.title),
              subtitle: Text(
                feature.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _supported(feature.id)
                    ? Icons.check_circle_outline
                    : Icons.circle_outlined,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkspaceCanvas extends StatelessWidget {
  const _WorkspaceCanvas({
    required this.workspace,
    required this.snapshot,
    required this.capabilities,
    required this.onDispatch,
  });
  final EngineWorkspace workspace;
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) {
    if (workspace == EngineWorkspace.nodes) {
      return _NodeCanvas(onDispatch: onDispatch);
    }
    if (workspace == EngineWorkspace.scopes) return const _ScopesCanvas();
    if (workspace == EngineWorkspace.export) {
      return _ExportCanvas(onDispatch: onDispatch);
    }
    if (workspace == EngineWorkspace.engine ||
        workspace == EngineWorkspace.performance) {
      return _EngineDashboard(snapshot: snapshot, capabilities: capabilities);
    }
    return _Viewer(snapshot: snapshot, workspace: workspace);
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.snapshot, required this.workspace});
  final EngineSnapshot snapshot;
  final EngineWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080808),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      size: 58,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 12,
            child: Text('${workspace.label} · DigitorEngine'),
          ),
          Positioned(
            right: 14,
            top: 12,
            child: Text(snapshot.engineMessage ?? 'Native production viewer'),
          ),
          if (snapshot.state['mediaPath'] != null)
            Positioned(
              left: 14,
              bottom: 12,
              right: 14,
              child: Text(
                '${snapshot.state['mediaPath']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _NodeCanvas extends StatelessWidget {
  const _NodeCanvas({required this.onDispatch});
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          const Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _NodeCard('Input', Icons.input),
                Icon(Icons.arrow_forward, color: Colors.white24),
                _NodeCard('Grade', Icons.tune),
                Icon(Icons.arrow_forward, color: Colors.white24),
                _NodeCard('Output', Icons.output),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: () => onDispatch('nodes.graph', 'addSerial'),
                child: const Text('+ Serial'),
              ),
              FilledButton.tonal(
                onPressed: () => onDispatch('nodes.graph', 'addParallel'),
                child: const Text('+ Parallel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
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
}

class _ScopesCanvas extends StatelessWidget {
  const _ScopesCanvas();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2,
      childAspectRatio: 16 / 7,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: const <Widget>[
        _ScopeCard('Waveform'),
        _ScopeCard('RGB Parade'),
        _ScopeCard('Vectorscope'),
        _ScopeCard('Histogram'),
      ],
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Stack(
        children: <Widget>[
          Positioned(left: 12, top: 10, child: Text(title)),
          const Center(
            child: Icon(
              Icons.monitor_heart_outlined,
              size: 54,
              color: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCanvas extends StatelessWidget {
  const _ExportCanvas({required this.onDispatch});
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    Chip(label: Text('MP4')),
                    Chip(label: Text('MOV')),
                    Chip(label: Text('Matroska')),
                    Chip(label: Text('Image sequence')),
                    Chip(label: Text('HW encode')),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => onDispatch('export.production', 'start'),
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
}

class _EngineDashboard extends StatelessWidget {
  const _EngineDashboard({required this.snapshot, required this.capabilities});
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final supported = capabilities.where((item) => item.supported).length;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Text('DigitorEngine', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(snapshot.connected ? 'Native engine connected' : 'Engine unavailable'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Chip(label: Text('UI features ${engineFeatureCatalog.length}')),
            Chip(label: Text('Runtime capabilities ${capabilities.length}')),
            Chip(label: Text('Directly exposed $supported')),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(snapshot.state.toString()),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.snapshot, required this.onCommand});
  final EngineSnapshot snapshot;
  final ValueChanged<String> onCommand;

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
        '${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(_time(snapshot.position)),
          const SizedBox(width: 14),
          IconButton(
            onPressed: () => onCommand('previousFrame'),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            onPressed: () => onCommand('playPause'),
            icon: Icon(snapshot.isPlaying ? Icons.pause_circle : Icons.play_circle),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () => onCommand('stop'),
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            onPressed: () => onCommand('nextFrame'),
            icon: const Icon(Icons.skip_next),
          ),
          const SizedBox(width: 14),
          Text(_time(snapshot.duration)),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const <Widget>[
        SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('MULTITRACK TIMELINE · engine-owned state'),
            ),
          ),
        ),
        Expanded(child: _TrackRow(label: 'V1', icon: Icons.videocam_outlined)),
        Expanded(child: _TrackRow(label: 'V2', icon: Icons.videocam_outlined)),
        Expanded(child: _TrackRow(label: 'A1', icon: Icons.audiotrack_outlined)),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
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
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 9),
                child: Text(
                  'Engine track / clips',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.features,
    required this.supported,
    required this.sliders,
    required this.toggles,
    required this.choices,
    required this.onAction,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
  });

  final List<EngineUiFeature> features;
  final bool Function(String id) supported;
  final Map<String, double> sliders;
  final Map<String, bool> toggles;
  final Map<String, String> choices;
  final Future<void> Function(String, String, [Object?]) onAction;
  final void Function(String, String, double) onSlider;
  final void Function(String, String, bool) onToggle;
  final void Function(String, String, String) onChoice;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: <Widget>[
        Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final feature in features)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          feature.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Icon(
                        supported(feature.id)
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 15,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final control in feature.controls)
                    _Control(
                      feature: feature.id,
                      control: control,
                      sliderValue: sliders['${feature.id}.${control.id}'],
                      toggleValue: toggles['${feature.id}.${control.id}'],
                      choiceValue: choices['${feature.id}.${control.id}'],
                      onAction: onAction,
                      onSlider: onSlider,
                      onToggle: onToggle,
                      onChoice: onChoice,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.feature,
    required this.control,
    required this.sliderValue,
    required this.toggleValue,
    required this.choiceValue,
    required this.onAction,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
  });

  final String feature;
  final EngineUiControl control;
  final double? sliderValue;
  final bool? toggleValue;
  final String? choiceValue;
  final Future<void> Function(String, String, [Object?]) onAction;
  final void Function(String, String, double) onSlider;
  final void Function(String, String, bool) onToggle;
  final void Function(String, String, String) onChoice;

  @override
  Widget build(BuildContext context) {
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: OutlinedButton(
            onPressed: () => onAction(feature, control.id),
            child: Text(control.label),
          ),
        );
      case EngineControlType.slider:
        final value = (sliderValue ?? control.initial).clamp(control.min, control.max);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
                onChanged: (next) => onSlider(feature, control.id, next),
              ),
            ],
          ),
        );
      case EngineControlType.toggle:
        return SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(control.label),
          value: toggleValue ?? false,
          onChanged: (next) => onToggle(feature, control.id, next),
        );
      case EngineControlType.choice:
        final selected = choiceValue ??
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
                DropdownMenuItem<String>(value: item, child: Text(item)),
            ],
            onChanged: (next) {
              if (next != null) onChoice(feature, control.id, next);
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
