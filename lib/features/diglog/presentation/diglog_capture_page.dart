import 'package:digitor/features/diglog/data/diglog_native.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DigLogCapturePage extends StatefulWidget {
  const DigLogCapturePage({super.key});

  @override
  State<DigLogCapturePage> createState() => _DigLogCapturePageState();
}

class _DigLogCapturePageState extends State<DigLogCapturePage> {
  static const DigLogNative _native = DigLogNative();

  DigLogCapabilities? _capabilities;
  bool _loading = true;
  bool _opening = false;
  String? _lastClip;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
      final result = await _native.getCapabilities();
      if (mounted) setState(() => _capabilities = result);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _capabilities = DigLogCapabilities(
            available: false,
            reason: error.message ?? 'Capability detection failed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCamera() async {
    if (_opening || _capabilities?.available != true) return;
    setState(() => _opening = true);
    try {
      final path = await _native.openCapture();
      if (path != null && mounted) {
        setState(() => _lastClip = path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DigLog clip saved')),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'DigLog capture failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openLastClip() async {
    final path = _lastClip;
    if (path == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          media: MediaItem(
            id: path,
            path: path,
            isVideo: true,
            duration: Duration.zero,
            createdAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _capabilities?.available == true;
    return Scaffold(
      appBar: AppBar(title: const Text('DigLog')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.videocam_rounded, size: 76),
                const SizedBox(height: 24),
                Text(
                  _loading
                      ? 'Checking camera…'
                      : available
                          ? 'DigLog Ready'
                          : 'Not Available',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  _loading
                      ? 'Finding the highest usable capture path.'
                      : available
                          ? 'The app will automatically use the highest supported DigLog capture path.'
                          : (_capabilities?.reason ?? 'This device cannot record DigLog footage.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: available && !_opening ? _openCamera : null,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fiber_manual_record_rounded),
                  label: const Text('Open DigLog'),
                ),
                if (_lastClip != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openLastClip,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit Last Clip'),
                  ),
                ],
                if (!_loading && !available) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: _check, child: const Text('Check Again')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
