import 'package:flutter/material.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 240, child: _MediaPanel()),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        const Expanded(child: _Viewport()),
                        const Divider(height: 1),
                        SizedBox(
                          height: 220,
                          child: _TimelinePanel(),
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
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text('Digitor', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPanel extends StatelessWidget {
  const _MediaPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: null,
            icon: const Icon(Icons.add),
            label: const Text('Import media'),
          ),
          const SizedBox(height: 16),
          Text('Media', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          const Expanded(
            child: Center(
              child: Text(
                'Media bin will be supplied by DigitorEngine',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Viewport extends StatelessWidget {
  const _Viewport();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.all(16),
      color: Colors.black,
      child: const Text('DigitorEngine preview surface'),
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Timeline UI — authoritative state comes from DigitorEngine'),
    );
  }
}
