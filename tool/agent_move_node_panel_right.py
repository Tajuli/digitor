from pathlib import Path

path = Path('lib/features/editor/presentation/editor_screen.dart')
text = path.read_text()

old_width = """    final wideColorWheels = inspectorFeature?.id == 'color.primaryWheels' ||
        inspectorFeature?.id == 'color.logWheels';
    final inspectorWidth = wideColorWheels ? 620.0 : 350.0;
"""
new_width = """    final wideColorWheels = inspectorFeature?.id == 'color.primaryWheels' ||
        inspectorFeature?.id == 'color.logWheels';
    final nodeWorkspace = workspace == EngineWorkspace.nodes;
    final inspectorWidth = nodeWorkspace ? 430.0 : (wideColorWheels ? 620.0 : 350.0);
"""
assert old_width in text
text = text.replace(old_width, new_width, 1)

old_inspector = """                    child: ListView(
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
"""
new_inspector = """                    child: nodeWorkspace
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
"""
assert old_inspector in text
text = text.replace(old_inspector, new_inspector, 1)

old_nodes = """    if (workspace == EngineWorkspace.nodes) {
      return Container(
        color: const Color(0xFF0D0D0D),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            const Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _Node('Input', Icons.input),
                  Icon(Icons.arrow_forward, color: Colors.white24),
                  _Node('Grade', Icons.tune),
                  Icon(Icons.arrow_forward, color: Colors.white24),
                  _Node('Output', Icons.output),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => dispatch('nodes.graph', 'addSerial'),
                  child: const Text('+ Serial'),
                ),
                FilledButton.tonal(
                  onPressed: () => dispatch('nodes.graph', 'addParallel'),
                  child: const Text('+ Parallel'),
                ),
              ],
            ),
          ],
        ),
      );
    }

"""
assert old_nodes in text
text = text.replace(old_nodes, '', 1)

anchor = "class _Node extends StatelessWidget {\n"
panel = r'''class _NodeGraphPanel extends StatelessWidget {
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

'''
assert anchor in text
text = text.replace(anchor, panel + anchor, 1)
path.write_text(text)
