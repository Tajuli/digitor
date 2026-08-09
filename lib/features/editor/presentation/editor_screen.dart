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
  List<EngineCapability> _capabilities = const <EngineCapability>[];
  String? _hostError;
  final Map<String, double> _sliderValues = <String, double>{};
  final Map<String, bool> _toggleValues = <String, bool>{};
  final Map<String, String> _choiceValues = <String, String>{};
  StreamSubscription<EngineSnapshot>? _snapshotSub;
  StreamSubscription<EngineProgress>? _progressSub;
  StreamSubscription<EngineEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _connectEngine();
  }

  Future<void> _connectEngine() async {
    _snapshotSub = widget.engine.snapshots.listen(
      (value) {
        if (mounted) setState(() => _snapshot = value);
      },
      onError: _rememberHostError,
    );
    _progressSub = widget.engine.progress.listen(
      (value) {
        if (mounted) setState(() => _progress = value);
      },
      onError: _rememberHostError,
    );
    _eventSub = widget.engine.events.listen(
      (_) {},
      onError: _rememberHostError,
    );

    try {
      await widget.engine.initialize();
      final capabilities = await widget.engine.discoverCapabilities();
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _hostError = null;
      });
    } on MissingPluginException catch (error) {
      _rememberHostError(error);
    } on PlatformException catch (error) {
      _rememberHostError(error);
    } catch (error) {
      _rememberHostError(error);
    }
  }

  void _rememberHostError(Object error) {
    if (!mounted) return;
    setState(() {
      _snapshot = EngineSnapshot.disconnected;
      _hostError = error.toString();
    });
  }

  Future<void> _dispatch(
    String featureId,
    String controlId, [
    Object? value,
  ]) async {
    try {
      await widget.engine.dispatch(
        EngineIntent(
          '$featureId.$controlId',
          value == null ? const <String, Object?>{} : <String, Object?>{'value': value},
        ),
      );
    } catch (error) {
      _rememberHostError(error);
    }
  }

  Future<void> _refreshCapabilities() async {
    try {
      final capabilities = await widget.engine.discoverCapabilities();
      if (mounted) setState(() => _capabilities = capabilities);
    } catch (error) {
      _rememberHostError(error);
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
    final features = engineFeatureCatalog
        .where((feature) => feature.workspace == _workspace)
        .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              snapshot: _snapshot,
              progress: _progress,
              onImport: () => _dispatch('media.import', 'requestPicker'),
              onUndo: () => _dispatch('project.history', 'undo'),
              onRedo: () => _dispatch('project.history', 'redo'),
              onSave: () => _dispatch('project.lifecycle', 'save'),
              onExport: () => setState(() => _workspace = EngineWorkspace.export),
            ),
            if (_hostError != null)
              _HostBanner(message: _hostError!, onRetry: _connectEngine),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  _WorkspaceRail(
                    selected: _workspace,
                    onSelected: (value) => setState(() => _workspace = value),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 245,
                    child: _FeatureBrowser(
                      workspace: _workspace,
                      features: features,
                      capabilities: _capabilities,
                      onRefreshCapabilities: _refreshCapabilities,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: _MainWorkspace(
                            workspace: _workspace,
                            snapshot: _snapshot,
                            capabilities: _capabilities,
                            onDispatch: _dispatch,
                          ),
                        ),
                        const Divider(height: 1),
                        _TransportBar(
                          snapshot: _snapshot,
                          onCommand: (id) => _dispatch('playback.transport', id),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 210, child: _Timeline()),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 310,
                    child: _Inspector(
                      workspace: _workspace,
                      features: features,
                      sliderValues: _sliderValues,
                      toggleValues: _toggleValues,
                      choiceValues: _choiceValues,
                      onAction: _dispatch,
                      onSlider: (feature, control, value) {
                        setState(() => _sliderValues['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                      onToggle: (feature, control, value) {
                        setState(() => _toggleValues['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                      onChoice: (feature, control, value) {
                        setState(() => _choiceValues['$feature.$control'] = value);
                        _dispatch(feature, control, value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            _StatusBar(
              snapshot: _snapshot,
              knownFeatures: engineFeatureCatalog.length,
              runtimeCapabilities: _capabilities,
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
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExport,
  });

  final EngineSnapshot snapshot;
  final EngineProgress? progress;
  final VoidCallback onImport;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.movie_filter_outlined),
            const SizedBox(width: 8),
            Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 18),
            _TopAction(icon: Icons.add_photo_alternate_outlined, label: 'Import', onPressed: onImport),
            _TopAction(icon: Icons.undo, label: 'Undo', onPressed: onUndo),
            _TopAction(icon: Icons.redo, label: 'Redo', onPressed: onRedo),
            _TopAction(icon: Icons.save_outlined, label: 'Save', onPressed: onSave),
            const Spacer(),
            if (progress != null && progress!.fraction < 1)
              SizedBox(
                width: 170,
                child: Row(
                  children: [
                    Expanded(child: LinearProgressIndicator(value: progress!.fraction)),
                    const SizedBox(width: 8),
                    Text('${(progress!.fraction * 100).round()}%'),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            _ConnectionChip(connected: snapshot.connected),
            const SizedBox(width: 12),
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

class _TopAction extends StatelessWidget {
  const _TopAction({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(connected ? Icons.check_circle : Icons.link_off, size: 16),
        label: Text(connected ? 'Engine connected' : 'Host unavailable'),
        visualDensity: VisualDensity.compact,
      );
}

class _HostBanner extends StatelessWidget {
  const _HostBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
        content: Text(
          'DigitorEngine native host is not available. UI remains usable for inspection; media processing is intentionally not emulated in Dart.\n$message',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            for (final item in EngineWorkspace.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: selected == item
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Colors.transparent,
                    ),
                    child: Column(
                      children: [
                        Icon(item.icon, size: 20),
                        const SizedBox(height: 4),
                        Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _FeatureBrowser extends StatelessWidget {
  const _FeatureBrowser({
    required this.workspace,
    required this.features,
    required this.capabilities,
    required this.onRefreshCapabilities,
  });

  final EngineWorkspace workspace;
  final List<EngineUiFeature> features;
  final List<EngineCapability> capabilities;
  final VoidCallback onRefreshCapabilities;

  @override
  Widget build(BuildContext context) {
    final knownIds = engineFeatureCatalog.map((item) => item.id).toSet();
    final unknown = capabilities.where((item) => !knownIds.contains(item.id)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Row(
            children: [
              Icon(workspace.icon, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(workspace.label, style: Theme.of(context).textTheme.titleSmall)),
              if (workspace == EngineWorkspace.engine)
                IconButton(onPressed: onRefreshCapabilities, icon: const Icon(Icons.refresh, size: 18), tooltip: 'Refresh capabilities'),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              for (final feature in features)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    title: Text(feature.title),
                    subtitle: Text(feature.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _CapabilityDot(id: feature.id, capabilities: capabilities),
                  ),
                ),
              if (workspace == EngineWorkspace.engine && unknown.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 16, 8, 6),
                  child: Text('Runtime-only capabilities'),
                ),
                for (final capability in unknown)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.extension_outlined, size: 18),
                    title: Text(capability.title),
                    subtitle: Text(capability.id),
                    trailing: Icon(
                      capability.supported ? Icons.check_circle_outline : Icons.block,
                      size: 18,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CapabilityDot extends StatelessWidget {
  const _CapabilityDot({required this.id, required this.capabilities});
  final String id;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final matches = capabilities.where((item) => item.id == id);
    if (matches.isEmpty) return const Tooltip(message: 'Awaiting runtime report', child: Icon(Icons.circle_outlined, size: 12));
    final supported = matches.first.supported;
    return Tooltip(
      message: supported ? 'Runtime supported' : 'Runtime unavailable',
      child: Icon(supported ? Icons.check_circle : Icons.cancel_outlined, size: 14),
    );
  }
}

class _MainWorkspace extends StatelessWidget {
  const _MainWorkspace({
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
    if (workspace == EngineWorkspace.nodes) return _NodeCanvas(onDispatch: onDispatch);
    if (workspace == EngineWorkspace.scopes) return const _ScopeCanvas();
    if (workspace == EngineWorkspace.engine) return _EngineDashboard(snapshot: snapshot, capabilities: capabilities);
    if (workspace == EngineWorkspace.export) return _ExportCanvas(onDispatch: onDispatch);
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
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Icon(Icons.play_circle_outline, size: 58, color: Colors.white24),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 12,
              child: Text('${workspace.label} · DigitorEngine preview surface'),
            ),
            Positioned(
              right: 14,
              top: 12,
              child: Text(snapshot.engineMessage ?? (snapshot.connected ? 'Ready' : 'Native texture pending')),
            ),
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
        padding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            const Positioned(left: 42, top: 96, child: _NodeCard(title: 'Input', icon: Icons.input)),
            const Positioned(left: 220, top: 96, child: _NodeCard(title: 'Serial 01', icon: Icons.tune)),
            const Positioned(left: 410, top: 38, child: _NodeCard(title: 'Parallel A', icon: Icons.call_split)),
            const Positioned(left: 410, top: 158, child: _NodeCard(title: 'Parallel B', icon: Icons.call_split)),
            const Positioned(left: 600, top: 96, child: _NodeCard(title: 'Mixer', icon: Icons.merge_type)),
            const Positioned(left: 785, top: 96, child: _NodeCard(title: 'Output', icon: Icons.output)),
            Positioned(
              left: 12,
              bottom: 12,
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addSerial'), child: const Text('+ Serial')),
                  FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addParallel'), child: const Text('+ Parallel')),
                  FilledButton.tonal(onPressed: () => onDispatch('nodes.graph', 'addMixer'), child: const Text('+ Mixer')),
                ],
              ),
            ),
          ],
        ),
      );
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(
          width: 130,
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 18), const SizedBox(width: 7), Text(title)],
          ),
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.035)..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScopeCanvas extends StatelessWidget {
  const _ScopeCanvas();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 16 / 7,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: const [
            _ScopeCard('Waveform'),
            _ScopeCard('RGB Parade'),
            _ScopeCard('Vectorscope'),
            _ScopeCard('Histogram'),
          ],
        ),
      );
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        child: Stack(
          children: [
            Positioned(left: 12, top: 10, child: Text(title)),
            const Center(child: Icon(Icons.monitor_heart_outlined, size: 54, color: Colors.white24)),
          ],
        ),
      );
}

class _ExportCanvas extends StatelessWidget {
  const _ExportCanvas({required this.onDispatch});
  final Future<void> Function(String, String, [Object?]) onDispatch;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Card(
            margin: const EdgeInsets.all(28),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Delivery', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Production export stays in DigitorEngine and uses the shared timeline/render state.'),
                  const SizedBox(height: 18),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [Chip(label: Text('MP4')), Chip(label: Text('MOV')), Chip(label: Text('Matroska')), Chip(label: Text('Image sequence')), Chip(label: Text('HW encode')), Chip(label: Text('Resumable'))],
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: () => onDispatch('export.production', 'configure'),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Export settings'),
                  ),
                  const SizedBox(height: 8),
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

class _EngineDashboard extends StatelessWidget {
  const _EngineDashboard({required this.snapshot, required this.capabilities});
  final EngineSnapshot snapshot;
  final List<EngineCapability> capabilities;

  @override
  Widget build(BuildContext context) {
    final supported = capabilities.where((item) => item.supported).length;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('DigitorEngine', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(snapshot.connected ? 'Native host connected' : 'Native host not connected'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(label: 'Runtime capabilities', value: '${capabilities.length}'),
            _MetricCard(label: 'Supported now', value: '$supported'),
            _MetricCard(label: 'Known UI surfaces', value: '${engineFeatureCatalog.length}'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Runtime state'),
        const SizedBox(height: 8),
        SelectableText(snapshot.state.isEmpty ? 'No native state received.' : snapshot.state.toString()),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(
          width: 180,
          height: 82,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const Spacer(), Text(value, style: Theme.of(context).textTheme.titleLarge)]),
          ),
        ),
      );
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.snapshot, required this.onCommand});
  final EngineSnapshot snapshot;
  final ValueChanged<String> onCommand;

  String _time(Duration value) {
    final total = value.inSeconds;
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_time(snapshot.position)),
            const SizedBox(width: 18),
            IconButton(onPressed: () => onCommand('previousFrame'), icon: const Icon(Icons.skip_previous)),
            IconButton(onPressed: () => onCommand('playReverse'), icon: const Icon(Icons.fast_rewind)),
            IconButton(onPressed: () => onCommand('playPause'), icon: Icon(snapshot.isPlaying ? Icons.pause_circle : Icons.play_circle), iconSize: 30),
            IconButton(onPressed: () => onCommand('stop'), icon: const Icon(Icons.stop_circle_outlined)),
            IconButton(onPressed: () => onCommand('nextFrame'), icon: const Icon(Icons.skip_next)),
            IconButton(onPressed: () => onCommand('loop'), icon: const Icon(Icons.repeat)),
            const SizedBox(width: 18),
            Text(_time(snapshot.duration)),
          ],
        ),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 88, child: Center(child: Text('TIMELINE'))),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 20,
                    itemBuilder: (context, index) => SizedBox(width: 80, child: Text('${index * 5}s', style: const TextStyle(fontSize: 10))),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: _TrackRow(label: 'V1', icon: Icons.videocam_outlined)),
          const Expanded(child: _TrackRow(label: 'V2', icon: Icons.videocam_outlined)),
          const Expanded(child: _TrackRow(label: 'A1', icon: Icons.audiotrack_outlined)),
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
          SizedBox(width: 88, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 15), const SizedBox(width: 6), Text(label)])),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(4)),
              child: const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Engine-owned track state', style: TextStyle(fontSize: 11, color: Colors.white38)))),
            ),
          ),
        ],
      );
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.workspace,
    required this.features,
    required this.sliderValues,
    required this.toggleValues,
    required this.choiceValues,
    required this.onAction,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
  });

  final EngineWorkspace workspace;
  final List<EngineUiFeature> features;
  final Map<String, double> sliderValues;
  final Map<String, bool> toggleValues;
  final Map<String, String> choiceValues;
  final Future<void> Function(String, String, [Object?]) onAction;
  final void Function(String, String, double) onSlider;
  final void Function(String, String, bool) onToggle;
  final void Function(String, String, String) onChoice;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('${workspace.label} Inspector', style: Theme.of(context).textTheme.titleSmall),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (final feature in features)
                  ExpansionTile(
                    initiallyExpanded: features.length <= 4,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                    title: Text(feature.title, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(feature.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                    children: [
                      for (final control in feature.controls)
                        _ControlView(
                          featureId: feature.id,
                          control: control,
                          sliderValue: sliderValues['${feature.id}.${control.id}'],
                          toggleValue: toggleValues['${feature.id}.${control.id}'],
                          choiceValue: choiceValues['${feature.id}.${control.id}'],
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

class _ControlView extends StatelessWidget {
  const _ControlView({
    required this.featureId,
    required this.control,
    required this.sliderValue,
    required this.toggleValue,
    required this.choiceValue,
    required this.onAction,
    required this.onSlider,
    required this.onToggle,
    required this.onChoice,
  });

  final String featureId;
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
          padding: const EdgeInsets.fromLTRB(8, 3, 8, 7),
          child: OutlinedButton(onPressed: () => onAction(featureId, control.id), child: Text(control.label)),
        );
      case EngineControlType.slider:
        final value = (sliderValue ?? control.initial).clamp(control.min, control.max);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Expanded(child: Text(control.label, style: const TextStyle(fontSize: 11))), Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10))]),
              Slider(value: value, min: control.min, max: control.max, onChanged: (next) => onSlider(featureId, control.id, next)),
            ],
          ),
        );
      case EngineControlType.toggle:
        return SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(control.label, style: const TextStyle(fontSize: 11)),
          value: toggleValue ?? false,
          onChanged: (next) => onToggle(featureId, control.id, next),
        );
      case EngineControlType.choice:
        final options = control.choices;
        if (options.isEmpty) return const SizedBox.shrink();
        final selected = options.contains(choiceValue) ? choiceValue! : options.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 8, 8),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isDense: true,
            decoration: InputDecoration(labelText: control.label, border: const OutlineInputBorder()),
            items: [for (final option in options) DropdownMenuItem(value: option, child: Text(option))],
            onChanged: (next) {
              if (next != null) onChoice(featureId, control.id, next);
            },
          ),
        );
      case EngineControlType.vector:
      case EngineControlType.text:
        return const SizedBox.shrink();
    }
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.snapshot, required this.knownFeatures, required this.runtimeCapabilities});
  final EngineSnapshot snapshot;
  final int knownFeatures;
  final List<EngineCapability> runtimeCapabilities;

  @override
  Widget build(BuildContext context) {
    final supported = runtimeCapabilities.where((item) => item.supported).length;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(snapshot.connected ? Icons.circle : Icons.circle_outlined, size: 9),
          const SizedBox(width: 6),
          Text(snapshot.connected ? 'DigitorEngine online' : 'Digitor UI · native host offline', style: const TextStyle(fontSize: 10)),
          const Spacer(),
          Text('Known UI: $knownFeatures  ·  Runtime: $supported/${runtimeCapabilities.length}', style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
