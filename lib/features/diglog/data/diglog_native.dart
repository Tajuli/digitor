import 'package:flutter/services.dart';

class DigLogCapabilities {
  const DigLogCapabilities({
    required this.available,
    required this.reason,
  });

  final bool available;
  final String reason;

  factory DigLogCapabilities.fromMap(Map<Object?, Object?> map) {
    return DigLogCapabilities(
      available: map['available'] == true,
      reason: (map['reason'] as String?) ?? 'DigLog is not available.',
    );
  }
}

class DigLogNative {
  const DigLogNative();

  static const MethodChannel _channel = MethodChannel('digitor/diglog');

  Future<DigLogCapabilities> getCapabilities() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return DigLogCapabilities.fromMap(result ?? const {});
  }

  Future<String?> openCapture() {
    return _channel.invokeMethod<String>('openCapture');
  }
}
