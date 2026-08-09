import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  EngineSnapshot _snapshot = EngineSnapshot.disconnected;
  EngineProgress? _progress;
  List<EngineCapability> _capabilities = const [];
  String? _hostError;

  final Map<String, double> _sliders = {};
  final Map<String, bool> _toggles = {};
  final Map<String, String> _choices = {};

  StreamSubscription<EngineSnapshot>? _snapshotSub;
  StreamSubscription<EngineProgress>? _progressSub;
  StreamSubscription<EngineEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    await _snapshotSub?.cancel();
    await _progressSub?.cancel();
    await _eventSub?.cancel();

    _snapshotSub = widget.engine.snapshots.listen(
      (value) {
        if (mounted) setState(() => _snapshot = value);
      },
      onError: _setHostError,
    );
    _progressSub = widget.engine.progress.listen(
      (value) {
        if (mounted) setState(() => _progress = value);
      },
      onError: _setHostError,
    );
    _eventSub = widget.engine.events.listen((_) {}, onError: _setHostError);

    try {
      await widget.engine.initialize();
      final capabilities = await widget.engine.discoverCapabilities();
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _hostError = null;
      });
    } on MissingPluginException catch (error) {
      _setHostError(error);
    } on PlatformException catch (error) {
      _setHostError(error);
    } catch (error) {
      _setHostError(error);
    }
  }

  void _setHostError(Object error) {
    if (!mounted) return;
    setState(() {
      _snapshot = EngineSnapshot.disconnected;
      _hostError = error.toString();
    });
  }

  Future<void> _dispatch(String feature, String control, [Object? value]) async {
    try {
      await widget.engine.dispatch(
        EngineIntent(
          '$feature.$control',
          value == null ? const {} : <String, Object?>{'value': value},
        ),
      );
    } catch (error) {
      _setHostError(error);
    }
  }

  Future<void> _refreshCapabilities() async {
    try {
      final value = await widget.engine.discoverCapabilities();
      if (mounted) setState(() => _capabilities = value);
    } catch (error) {
      _setHostError(error);
    }
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _progressSub?.cancel();
    _eventSub?.cancel();
    widget.engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final features = engineFeatureCatalog.where((f) => f.workspace == _workspace).toList(growable: false);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              connected: _snapshot.connected,
              progress: _progress,
              onImport: () => _dispatch('media.import', 'requestPicker'),
              onSave: () => _dispatch('project.lifecycle', 'save'),
              onUndo: () => _dispatch('project.history', 'undo'),
              onRedo: () => _dispatch('project.history', 'redo'),
              onExport: () => setState(() => _workspace = EngineWorkspace.export),
            ),
            if (_hostError != null) _HostBanner(message: _hostError!, onRetry: _connect),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  _WorkspaceRail(selected: _workspace, onSelected: (value) => setState(() => _workspace = value)),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 235,
                    child: _FeatureBrowser(
                      workspace: _workspace,
                      features: features,
                      capabilities: _capabilities,
                      onRefresh: _refreshCapabilities,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _MainCanvas(workspace: _workspace, snapshot: _snapshot, capabilities: _capabilities, onDispatch: _dispatch)),
                        const Divider(height: 1),
                        _Transport(snapshot: _snapshot, onCommand: (id) => _dispatch('playback.transport', id)),
                        const Divider(height: 1),
                        const SizedBox(height: 210, child: _TimelineSurface()),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 305,
                    child: _Inspector(
                      workspace: _workspace,
                      features: features,
                      sliders: _sliders,
                      toggles: _toggles,
                      choices: _choices,
                      onAction: _dispatch,
                      onSlider: (feature, control, value) {
                        setState(() => _sliders['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                      onToggle: (feature, control, value) {
                        setState(() => _toggles['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                      onChoice: (feature, control, value) {
                        setState(() => _choices['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            _StatusBar(snapshot: _snapshot, capabilities: _capabilities),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.connected,
    required this.progress,
    required this.onImport,
    required this.onSave,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
  });
  final bool connected;
  final EngineProgress? progress;
  final VoidCallback onImport;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.movie_filter_outlined),
              const SizedBox(width: 8),
              Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 18),
              TextButton.icon(onPressed: onImport, icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: const Text('Import')),
              IconButton(onPressed: onUndo, icon: const Icon(Icons.undo), tooltip: 'Undo'),
              IconButton(onPressed: onRedo, icon: const Icon(Icons.redo), tooltip: 'Redo'),
              IconButton(onPressed: onSave, icon: const Icon(Icons.save_outlined), tooltip: 'Save'),
              const Spacer(),
              if (progress != null && progress!.fraction < 1.0)
                SizedBox(
                  width: 160,
                  child: Row(children: [Expanded(child: LinearProgressIndicator(value: progress!.fraction)), const SizedBox(width: 8), Text('${(progress!.fraction * 100).round()}%')]),
                ),
              const SizedBox(width: 12),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(connected ? Icons.check_circle : Icons.link_off, size: 16),
                label: Text(connected ? 'Engine connected' : 'Host unavailable'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(onPressed: onExport, icon: const Icon(Icons.file_upload_outlined, size: 18), label: const Text('Export')),
            ],
          ),
        ),
      );
}

class _HostBanner extends StatelessWidget {
  const _HostBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Native DigitorEngine host unavailable — no processing is emulated in Dart. $message', maxLines: 1, overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({required this.selected, required this.onSelected});
  final EngineWorkspace selected;
  final ValueChanged<EngineWorkspace> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 86,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 5),
          children: [
            for (final item in EngineWorkspace.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: selected == item ? Theme.of(context).colorScheme.secondaryContainer : Colors.transparent,
                    ),
                    child: Column(children: [Icon(item.icon, size: 20), const SizedBox(height: 3), Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))]),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _FeatureBrowser extends StatelessWidget {
  const _FeatureBrowser({required this.workspace, required this.features, required this.capabilities, required this.onRefresh});
  final EngineWorkspace workspace;
  final List<EngineUiFeature> features;
  final List<EngineCapability> capabilities;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final known = engineFeatureCatalog.map((f) => f.id).toSet();
    final runtimeOnly = capabilities.where((c) => !known.contains(c.id)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
          child: Row(children: [Icon(workspace.icon, size: 18), const SizedBox(width: 7), Expanded(child: Text(workspace.label, style: Theme.of(context).textTheme.titleSmall)), if (workspace == EngineWorkspace.engine) IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, size: 18))]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(7, 0, 7, 10),
            children: [
              for (final feature in features)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    title: Text(feature.title),
                    subtitle: Text(feature.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _CapabilityIcon(id: feature.id, capabilities: capabilities),
                  ),
                ),
              if (workspace == EngineWorkspace.engine && runtimeOnly.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.fromLTRB(8, 14, 8, 5), child: Text('Runtime-only capabilities')),
                for (final capability in runtimeOnly)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.extension_outlined, size: 18),
                    title: Text(capability.title),
                    subtitle: Text(capability.id),
                    trailing: Icon(capability.supported ? Icons.check_circle_outline : Icons.block, size: 18),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CapabilityIcon extends StatelessWidget {
  const _CapabilityIcon({required this.id, required this.capabilities});
  final String id;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final match = capabilities.where((c) => c.id == id).toList(growable: false);
    if (match.isEmpty) return const Icon(Icons.circle_outlined, size: 12);
    return Icon(match.first.supported ? Icons.check_circle : Icons.cancel_outlined, size: 14);
  }
}

class _MainCanvas extends StatelessWidget {
  const _MainCanvas({required this.workspace, required this.snapshot, required this.capabilities, required this.onDispatch});
  final EngineWorkspace workspace;
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) {
    if (workspace == EngineWorkspace.nodes) return _NodeCanvas(onDispatch: onDispatch);
    if (workspace == EngineWorkspace.scopes) return const _ScopesCanvas();
    if (workspace == EngineWorkspace.export) return _ExportCanvas(onDispatch: onDispatch);
    if (workspace == EngineWorkspace.engine) return _EngineDashboard(snapshot: snapshot, capabilities: capabilities);
    return _Viewer(snapshot: snapshot, workspace: workspace);
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.snapshot, required this.workspace});
  final EngineSnapshot snapshot;
  final EngineWorkspace workspace;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF090909),
        child: Stack(
          children: [
            const Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.play_circle_outline, size: 58, color: Colors.white24))),
                ),
              ),
            ),
            Positioned(left: 14, top: 12, child: Text('${workspace.label} · DigitorEngine native preview')),
            Positioned(right: 14, top: 12, child: Text(snapshot.engineMessage ?? (snapshot.connected ? 'Ready' : 'Texture host pending'))),
          ],
        ),
      );
}

class _NodeCanvas extends StatelessWidget {
  const _NodeCanvas({required this.onDispatch});
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF101010),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _NodeCard('Input', Icons.input),
                  Icon(Icons.arrow_forward, color: Colors.white24),
                  _NodeCard('Serial', Icons.tune),
                  Icon(Icons.call_split, color: Colors.white24),
                  _NodeCard('Parallel', Icons.alt_route),
                  Icon(Icons.merge_type, color: Colors.white24),
                  _NodeCard('Mixer', Icons.merge),
                  Icon(Icons.arrow_forward, color: Colors.white24),
                  _NodeCard('Output', Icons.output),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addSerial'), child: const Text('+ Serial')),
                FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addParallel'), child: const Text('+ Parallel')),
                FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addMixer'), child: const Text('+ Mixer')),
              ],
            ),
          ],
        ),
      );
}

class _NodeCard extends StatelessWidget {
  const _NodeCard(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(width: 105, height: 70, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 19), const SizedBox(height: 5), Text(title)])),
      );
}

class _ScopesCanvas extends StatelessWidget {
  const _ScopesCanvas();

  @override
  Widget build(BuildContext context) => GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        childAspectRatio: 16 / 7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: const [_ScopeCard('Waveform'), _ScopeCard('RGB Parade'), _ScopeCard('Vectorscope'), _ScopeCard('Histogram')],
      );
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        child: Stack(children: [Positioned(left: 12, top: 10, child: Text(title)), const Center(child: Icon(Icons.monitor_heart_outlined, size: 54, color: Colors.white24))]),
      );
}

class _ExportCanvas extends StatelessWidget {
  const _ExportCanvas({required this.onDispatch});
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            margin: const EdgeInsets.all(26),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Delivery', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 7),
                  const Text('Shared DigitorEngine timeline/render state · async jobs · cancel/progress · resumable segments.'),
                  const SizedBox(height: 14),
                  const Wrap(spacing: 7, runSpacing: 7, children: [Chip(label: Text('MP4')), Chip(label: Text('MOV')), Chip(label: Text('Matroska')), Chip(label: Text('Image sequence')), Chip(label: Text('HW encode'))]),
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: () => onDispatch('export.production', 'configure'), icon: const Icon(Icons.settings_outlined), label: const Text('Export settings')),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: () => onDispatch('export.production', 'start'), icon: const Icon(Icons.file_upload_outlined), label: const Text('Start export')),
                ],
              ),
            ),
          ),
        ),
      );
}

class _EngineDashboard extends StatelessWidget {
  const _EngineDashboard({required this.snapshot, required this.capabilities});
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final supported = capabilities.where((c) => c.supported).length;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('DigitorEngine', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(snapshot.connected ? 'Native host connected' : 'Native host not connected'),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('Known UI ${engineFeatureCatalog.length}')),
          Chip(label: Text('Runtime ${capabilities.length}')),
          Chip(label: Text('Supported $supported')),
        ]),
        const SizedBox(height: 18),
        const Text('Runtime state'),
        const SizedBox(height: 6),
        SelectableText(snapshot.state.isEmpty ? 'No native state received.' : snapshot.state.toString()),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.snapshot, required this.onCommand});
  final EngineSnapshot snapshot;
  final ValueChanged<String> onCommand;

  String _time(Duration d) {
    final seconds = d.inSeconds;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_time(snapshot.position)),
            const SizedBox(width: 16),
            IconButton(onPressed: () => onCommand('previousFrame'), icon: const Icon(Icons.skip_previous)),
            IconButton(onPressed: () => onCommand('playReverse'), icon: const Icon(Icons.fast_rewind)),
            IconButton(onPressed: () => onCommand('playPause'), icon: Icon(snapshot.isPlaying ? Icons.pause_circle : Icons.play_circle), iconSize: 30),
            IconButton(onPressed: () => onCommand('stop'), icon: const Icon(Icons.stop_circle_outlined)),
            IconButton(onPressed: () => onCommand('nextFrame'), icon: const Icon(Icons.skip_next)),
            IconButton(onPressed: () => onCommand('loop'), icon: const Icon(Icons.repeat)),
            const SizedBox(width: 16),
            Text(_time(snapshot.duration)),
          ],
        ),
      );
}

class _TimelineSurface extends StatelessWidget {
  const _TimelineSurface();

  @override
  Widget build(BuildContext context) => Column(
        children: const [
          SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 12), child: Text('MULTITRACK TIMELINE · engine-owned state')))),
          Expanded(child: _TrackRow(label: 'V1', icon: Icons.videocam_outlined)),
          Expanded(child: _TrackRow(label: 'V2', icon: Icons.videocam_outlined)),
          Expanded(child: _TrackRow(label: 'A1', icon: Icons.audiotrack_outlined)),
        ],
      );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 78, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 15), const SizedBox(width: 5), Text(label)])),
          const VerticalDivider(width: 1),
          Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(4)), child: const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(horizontal: 9), child: Text('Engine track / clips', style: TextStyle(fontSize: 11, color: Colors.white38))))),
        ],
      );
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.workspace,
    required this.features,
    required this.sliders,
    required this.toggles,
    required this.choices,
    required this.onAction,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
  });
  final EngineWorkspace workspace;
  final List<EngineUiFeature> features;
  final Map<String, double> sliders;
  final Map<String, bool> toggles;
  final Map<String, String> choices;
  final Future<void> Function(String, String, [Object?]) onAction;
  final void Function(String, String, double) onSlider;
  final void Function(String, String, bool) onToggle;
  final void Function(String, String, String) onChoice;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text('${workspace.label} Inspector', style: Theme.of(context).textTheme.titleSmall)),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final feature in features)
                  ExpansionTile(
                    initiallyExpanded: features.length <= 4,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                    title: Text(feature.title, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(feature.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                    children: [
                      for (final control in feature.controls)
                        _Control(
                          featureId: feature.id,
                          spec: control,
                          slider: sliders['${feature.id}.${control.id}'],
                          toggle: toggles['${feature.id}.${control.id}'],
                          choice: choices['${feature.id}.${control.id}'],
                          onAction: onAction,
                          onSlider: onSlider,
                          onToggle: onToggle,
                          onChoice: onChoice,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
}

class _Control extends StatelessWidget {
  const _Control({required this.featureId, required this.spec, required this.slider, required this.toggle, required this.choice, required this.onAction, required this.onSlider, required this.onToggle, required this.onChoice});
  final String featureId;
  final EngineUiControl spec;
  final double? slider;
  final bool? toggle;
  final String? choice;
  final Future<void> Function(String, String, [Object?]) onAction;
  final void Function(String, String, double) onSlider;
  final void Function(String, String, bool) onToggle;
  final void Function(String, String, String) onChoice;

  @override
  Widget build(BuildContext context) {
    switch (spec.type) {
      case EngineControlType.action:
        return Padding(padding: const EdgeInsets.fromLTRB(7, 3, 7, 7), child: OutlinedButton(onPressed: () => onAction(featureId, spec.id), child: Text(spec.label)));
      case EngineControlType.slider:
        final value = (slider ?? spec.initial).clamp(spec.min, spec.max).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Column(children: [Row(children: [Expanded(child: Text(spec.label, style: const TextStyle(fontSize: 11))), Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10))]), Slider(value: value, min: spec.min, max: spec.max, onChanged: (v) => onSlider(featureId, spec.id, v))]),
        );
      case EngineControlType.toggle:
        return SwitchListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 7), title: Text(spec.label, style: const TextStyle(fontSize: 11)), value: toggle ?? false, onChanged: (v) => onToggle(featureId, spec.id, v));
      case EngineControlType.choice:
        if (spec.choices.isEmpty) return const SizedBox.shrink();
        final selected = spec.choices.contains(choice) ? choice! : spec.choices.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(7, 3, 7, 8),
          child: Row(children: [Expanded(child: Text(spec.label, style: const TextStyle(fontSize: 11))), DropdownButton<String>(value: selected, items: [for (final option in spec.choices) DropdownMenuItem(value: option, child: Text(option))], onChanged: (v) { if (v != null) onChoice(featureId, spec.id, v); })]),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return const SizedBox.shrink();
    }
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.snapshot, required this.capabilities});
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final supported = capabilities.where((c) => c.supported).length;
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [Icon(snapshot.connected ? Icons.circle : Icons.circle_outlined, size: 9), const SizedBox(width: 6), Text(snapshot.connected ? 'DigitorEngine online' : 'Digitor UI · native host offline', style: const TextStyle(fontSize: 10)), const Spacer(), Text('Known UI ${engineFeatureCatalog.length} · Runtime $supported/${capabilities.length}', style: const TextStyle(fontSize: 10))]),
      ),
    );
  }
}
