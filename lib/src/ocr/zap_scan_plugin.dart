import 'package:flutter/services.dart';

class ZapScanPlugin {
  static const MethodChannel _channel = MethodChannel('zap_scan');

  static Future<String?> recognizeText({
    Uint8List? bytes,
    int? width,
    int? height,
    int? rotation,
    int? format,
    String? imagePath,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>('recognizeText', {
        if (bytes != null) 'bytes': bytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (rotation != null) 'rotation': rotation,
        if (format != null) 'format': format,
        if (imagePath != null) 'imagePath': imagePath,
      });
      return text;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> recognizeBarcode({
    Uint8List? bytes,
    int? width,
    int? height,
    int? rotation,
    int? format,
    String? imagePath,
  }) async {
    try {
      final barcodes = await _channel.invokeListMethod<Map<dynamic, dynamic>>('recognizeBarcode', {
        if (bytes != null) 'bytes': bytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (rotation != null) 'rotation': rotation,
        if (format != null) 'format': format,
        if (imagePath != null) 'imagePath': imagePath,
      });
      if (barcodes == null) return null;
      return barcodes.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return null;
    }
  }
}
