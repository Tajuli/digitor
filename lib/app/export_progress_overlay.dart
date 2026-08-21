import 'package:flutter/material.dart';

import '../core/engine/engine_gateway.dart';

class ExportProgressOverlay extends StatelessWidget {
  const ExportProgressOverlay({
    super.key,
    required this.engine,
    required this.child,
  });

  final EngineGateway engine;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          child,
          StreamBuilder<EngineProgress>(
            stream: engine.progress,
            builder: (context, snapshot) {
              final progress = snapshot.data;
              final exporting = progress?.operation == 'export' &&
                  progress!.fraction >= 0 &&
                  progress.fraction < 1;
              if (!exporting) return const SizedBox.shrink();

              final fraction = progress.fraction.clamp(0.0, 1.0).toDouble();
              final percent = (fraction * 100).round();
              return SafeArea(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      constraints: const BoxConstraints(maxWidth: 430),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                      decoration: BoxDecoration(
                        color: const Color(0xF21A1A20),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Exporting video',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '$percent%',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            minHeight: 5,
                            value: fraction,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
}
