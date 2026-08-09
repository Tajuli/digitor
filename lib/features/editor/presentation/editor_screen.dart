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
  EngineWorkspace workspace = EngineWorkspace.media;
  EngineSnapshot snapshot = EngineSnapshot.disconnected;
  List<EngineCapability> capabilities = const [];
  EngineProgress? progress;
  String? error;
  final sliders = <String, double>{};
  final toggles = <String, bool>{};
  final choices = <String, String>{};
  final subscriptions = <StreamSubscription<Object?>>[];

  List<EngineUiFeature> get features => engineFeatureCatalog
      .where((feature) => feature.workspace == workspace)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    subscriptions.add(widget.engine.snapshots.listen((value) {
      if (mounted) setState(() => snapshot = value);
    }));
    subscriptions.add(widget.engine.progress.listen((value) {
      if (mounted) setState(() => progress = value);
    }));
    subscriptions.add(widget.engine.events.listen((value) {
      if (!mounted || value.type != 'unsupportedAction') return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Engine API not exposed for ${value.payload['action']}')),
      );
    }));
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      await widget.engine.initialize();
      final next = await widget.engine.discoverCapabilities();
      if (mounted) setState(() { capabilities = next; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> dispatch(String feature, String control, [Object? value]) async {
    try {
      await widget.engine.dispatch(EngineIntent(
        '$feature.$control',
        value == null ? const {} : <String, Object?>{'value': value},
      ));
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool supported(String id) {
    for (final item in capabilities) {
      if (item.id == id) return item.supported;
    }
    return false;
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
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.movie_outlined),
                const SizedBox(width: 8),
                Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 18),
                TextButton.icon(
                  onPressed: () => dispatch('media.import', 'requestPicker'),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Import'),
                ),
                const Spacer(),
                if (progress != null && progress!.fraction < 1)
                  SizedBox(
                    width: 170,
                    child: Row(children: [
                      Expanded(child: LinearProgressIndicator(value: progress!.fraction)),
                      const SizedBox(width: 8),
                      Text('${(progress!.fraction * 100).round()}%'),
                    ]),
                  ),
                const SizedBox(width: 10),
                Chip(
                  avatar: Icon(snapshot.connected ? Icons.check_circle : Icons.link_off, size: 16),
                  label: Text(snapshot.connected ? 'Engine connected' : 'Disconnected'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => setState(() => workspace = EngineWorkspace.export),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Export'),
                ),
              ]),
            ),
          ),
          if (error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: initialize, child: const Text('Retry')),
                ]),
              ),
            ),
          Expanded(
            child: Row(children: [
              SizedBox(
                width: 88,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  children: [
                    for (final item in EngineWorkspace.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => setState(() => workspace = item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              color: workspace == item
                                  ? Theme.of(context).colorScheme.secondaryContainer
                                  : Colors.transparent,
                            ),
                            child: Column(children: [
                              Icon(item.icon, size: 20),
                              const SizedBox(height: 3),
                              Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 245,
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final feature in features)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: ListTile(
                          dense: true,
                          title: Text(feature.title),
                          subtitle: Text(feature.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Icon(
                            supported(feature.id) ? Icons.check_circle_outline : Icons.circle_outlined,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(children: [
                  Expanded(child: _Canvas(
                    workspace: workspace,
                    snapshot: snapshot,
                    capabilities: capabilities,
                    dispatch: dispatch,
                  )),
                  const Divider(height: 1),
                  SizedBox(
                    height: 46,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_time(snapshot.position)),
                      const SizedBox(width: 14),
                      IconButton(onPressed: () => dispatch('playback.transport', 'previousFrame'), icon: const Icon(Icons.skip_previous)),
                      IconButton(
                        onPressed: () => dispatch('playback.transport', 'playPause'),
                        icon: Icon(snapshot.isPlaying ? Icons.pause_circle : Icons.play_circle),
                        iconSize: 30,
                      ),
                      IconButton(onPressed: () => dispatch('playback.transport', 'stop'), icon: const Icon(Icons.stop_circle_outlined)),
                      IconButton(onPressed: () => dispatch('playback.transport', 'nextFrame'), icon: const Icon(Icons.skip_next)),
                      const SizedBox(width: 14),
                      Text(_time(snapshot.duration)),
                    ]),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 150, child: _Timeline()),
                ]),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 330,
                child: ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final feature in features)
                      _FeatureControls(
                        feature: feature,
                        supported: supported(feature.id),
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
            ]),
          ),
        ]),
      ),
    );
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
        '${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.workspace, required this.snapshot, required this.capabilities, required this.dispatch});
  final EngineWorkspace workspace;
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;
  final Future<void> Function(String, String, [Object?]) dispatch;

  @override
  Widget build(BuildContext context) {
    if (workspace == EngineWorkspace.nodes) {
      return Container(
        color: const Color(0xFF0D0D0D),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Node('Input', Icons.input),
              Icon(Icons.arrow_forward, color: Colors.white24),
              _Node('Grade', Icons.tune),
              Icon(Icons.arrow_forward, color: Colors.white24),
              _Node('Output', Icons.output),
            ]),
          ),
          Wrap(spacing: 8, children: [
            FilledButton.tonal(onPressed: () => dispatch('nodes.graph', 'addSerial'), child: const Text('+ Serial')),
            FilledButton.tonal(onPressed: () => dispatch('nodes.graph', 'addParallel'), child: const Text('+ Parallel')),
          ]),
        ]),
      );
    }
    if (workspace == EngineWorkspace.scopes) {
      return GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        childAspectRatio: 16 / 7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: const [
          _Scope('Waveform'), _Scope('RGB Parade'), _Scope('Vectorscope'), _Scope('Histogram'),
        ],
      );
    }
    if (workspace == EngineWorkspace.export) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            margin: const EdgeInsets.all(26),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Delivery', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 7),
                const Text('Production export uses the same DigitorEngine node recipe and native render path as preview.'),
                const SizedBox(height: 14),
                const Wrap(spacing: 7, runSpacing: 7, children: [
                  Chip(label: Text('MP4')), Chip(label: Text('MOV')), Chip(label: Text('Matroska')), Chip(label: Text('Image sequence')), Chip(label: Text('HW encode')),
                ]),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => dispatch('export.production', 'start'),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Start export'),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    if (workspace == EngineWorkspace.engine || workspace == EngineWorkspace.performance) {
      final count = capabilities.where((item) => item.supported).length;
      return ListView(padding: const EdgeInsets.all(18), children: [
        Text('DigitorEngine', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(snapshot.connected ? 'Native engine connected' : 'Engine unavailable'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          Chip(label: Text('UI ${engineFeatureCatalog.length}')),
          Chip(label: Text('Runtime ${capabilities.length}')),
          Chip(label: Text('Direct $count')),
        ]),
        const SizedBox(height: 12),
        SelectableText(snapshot.state.toString()),
      ]);
    }
    return Container(
      color: const Color(0xFF080808),
      child: Stack(children: [
        const Positioned.fill(
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: Center(child: Icon(Icons.play_circle_outline, size: 58, color: Colors.white24)),
              ),
            ),
          ),
        ),
        Positioned(left: 14, top: 12, child: Text('${workspace.label} · DigitorEngine')),
        Positioned(right: 14, top: 12, child: Text(snapshot.engineMessage ?? 'Native production viewer')),
      ]),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: SizedBox(width: 110, height: 72, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 19), const SizedBox(height: 5), Text(title),
    ])),
  );
}

class _Scope extends StatelessWidget {
  const _Scope(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Card(
    child: Stack(children: [
      Positioned(left: 12, top: 10, child: Text(title)),
      const Center(child: Icon(Icons.monitor_heart_outlined, size: 54, color: Colors.white24)),
    ]),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline();
  @override
  Widget build(BuildContext context) => Column(children: const [
    SizedBox(height: 28, child: Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 12), child: Text('MULTITRACK TIMELINE · engine-owned state')))),
    Expanded(child: _Track('V1', Icons.videocam_outlined)),
    Expanded(child: _Track('V2', Icons.videocam_outlined)),
    Expanded(child: _Track('A1', Icons.audiotrack_outlined)),
  ]);
}

class _Track extends StatelessWidget {
  const _Track(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 72, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 15), const SizedBox(width: 5), Text(label)])),
    const VerticalDivider(width: 1),
    Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(4)),
      child: const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(horizontal: 9), child: Text('Engine track / clips', style: TextStyle(fontSize: 11, color: Colors.white38)))),
    )),
  ]);
}

class _FeatureControls extends StatelessWidget {
  const _FeatureControls({
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(feature.title, style: Theme.of(context).textTheme.titleSmall)),
          Icon(supported ? Icons.check_circle_outline : Icons.info_outline, size: 15),
        ]),
        const SizedBox(height: 6),
        for (final control in feature.controls) _control(context, control),
      ]),
    ),
  );

  Widget _control(BuildContext context, EngineUiControl control) {
    final key = '${feature.id}.${control.id}';
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: OutlinedButton(onPressed: () => dispatch(feature.id, control.id), child: Text(control.label)),
        );
      case EngineControlType.slider:
        final value = (sliders[key] ?? control.initial).clamp(control.min, control.max).toDouble();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(control.label)), Text(value.toStringAsFixed(2))]),
          Slider(
            min: control.min,
            max: control.max,
            value: value,
            onChanged: (next) { onSlider(key, next); unawaited(dispatch(feature.id, control.id, next)); },
          ),
        ]);
      case EngineControlType.toggle:
        return SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(control.label),
          value: toggles[key] ?? false,
          onChanged: (next) { onToggle(key, next); unawaited(dispatch(feature.id, control.id, next)); },
        );
      case EngineControlType.choice:
        final selected = choices[key] ?? (control.choices.isEmpty ? null : control.choices.first);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(labelText: control.label, isDense: true, border: const OutlineInputBorder()),
            items: [for (final item in control.choices) DropdownMenuItem(value: item, child: Text(item))],
            onChanged: (next) { if (next != null) { onChoice(key, next); unawaited(dispatch(feature.id, control.id, next)); } },
          ),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(control.label));
    }
  }
}
