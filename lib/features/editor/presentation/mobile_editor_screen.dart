import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine/engine_feature_catalog.dart';
import '../../../core/engine/engine_gateway.dart';

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
      if (!mounted) return;
      if (value.type == 'unsupportedAction' ||
          value.type == 'engineError' ||
          value.type == 'previewError') {
        final message = value.payload['error']?.toString() ??
            'Engine API not exposed for ${value.payload['action']}';
        setState(() => error = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }));
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _supported(String id) {
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
    final textureId = snapshot.state['previewTextureId'] as int?;
    final previewWidth = snapshot.state['previewWidth'] as int? ?? 0;
    final previewHeight = snapshot.state['previewHeight'] as int? ?? 0;
    final showTimeline = workspace == EngineWorkspace.edit ||
        workspace == EngineWorkspace.playback;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 52,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 8),
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
                    message: snapshot.connected
                        ? 'Engine connected'
                        : 'Engine disconnected',
                    child: Icon(
                      snapshot.connected ? Icons.check_circle : Icons.link_off,
                      size: 20,
                      color: snapshot.connected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
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
            if (progress != null && progress!.fraction < 1)
              LinearProgressIndicator(value: progress!.fraction),
            if (error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
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
              ),
            SizedBox(
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
                    child: Container(
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
            ),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: workspace == EngineWorkspace.export
                        ? Center(
                            child: FilledButton.icon(
                              onPressed: _supported('export.production')
                                  ? () => _dispatch('export.production', 'start')
                                  : null,
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Start production export'),
                            ),
                          )
                        : ColoredBox(
                            color: const Color(0xFF080808),
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
                                                  size: 44,
                                                  color: Colors.white24),
                                              SizedBox(height: 7),
                                              Text(
                                                'Import media to start preview',
                                                style: TextStyle(
                                                    color: Colors.white38),
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
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 46,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton(
                          onPressed: () => _dispatch(
                              'playback.transport', 'previousFrame'),
                          icon: const Icon(Icons.skip_previous),
                        ),
                        IconButton.filledTonal(
                          onPressed: () =>
                              _dispatch('playback.transport', 'playPause'),
                          icon: const Icon(Icons.play_arrow),
                        ),
                        IconButton(
                          onPressed: () =>
                              _dispatch('playback.transport', 'nextFrame'),
                          icon: const Icon(Icons.skip_next),
                        ),
                      ],
                    ),
                  ),
                  if (showTimeline) ...<Widget>[
                    const Divider(height: 1),
                    SizedBox(
                      height: 72,
                      child: Card(
                        margin: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(
                            snapshot.state['mediaPath']?.toString() ??
                                'No media on timeline',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 1),
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(7, 5, 7, 24),
                      children: <Widget>[
                        for (final feature in features)
                          _featureCard(context, feature),
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

  Widget _featureCard(BuildContext context, EngineUiFeature feature) {
    final supported = _supported(feature.id);
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
                  supported ? Icons.check_circle_outline : Icons.info_outline,
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
            if (engineManagedZeroCopy)
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text('Engine managed')),
                ),
              )
            else
              for (final control in feature.controls)
                _control(feature, control, supported),
          ],
        ),
      ),
    );
  }

  Widget _control(
      EngineUiFeature feature, EngineUiControl control, bool enabled) {
    final key = '${feature.id}.${control.id}';
    switch (control.type) {
      case EngineControlType.action:
        return Padding(
          padding: const EdgeInsets.only(top: 7),
          child: OutlinedButton(
            onPressed: enabled ? () => _dispatch(feature.id, control.id) : null,
            child: Text(control.label),
          ),
        );
      case EngineControlType.slider:
        final value = (sliders[key] ?? control.initial)
            .clamp(control.min, control.max)
            .toDouble();
        return Column(
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
          padding: const EdgeInsets.only(top: 7),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: control.label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final choice in control.choices)
                DropdownMenuItem<String>(value: choice, child: Text(choice)),
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
