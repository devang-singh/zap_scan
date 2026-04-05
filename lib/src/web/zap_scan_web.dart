import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The Web implementation of the `zap_scan` plugin.
class ZapScanWeb {
  /// Registers the Web implementation with the [Registrar].
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'zap_scan',
      const StandardMethodCodec(),
      registrar,
    );

    final instance = ZapScanWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  /// Handles method calls from Dart.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getPlatformVersion':
        return 'Web';
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'zap_scan for web doesn\'t implement \'${call.method}\'',
        );
    }
  }
}
