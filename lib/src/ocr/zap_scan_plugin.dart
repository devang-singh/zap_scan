import 'package:flutter/services.dart';

/// The native bridge class for the `zap_scan` plugin.
/// 
/// This class provides static methods to communicate with the native 
/// (Android/iOS) OCR and Barcode recognition engines.
class ZapScanPlugin {
  static const MethodChannel _channel = MethodChannel('zap_scan');

  /// Recognizes and extracts text from an image.
  /// 
  /// The image can be provided as a [Uint8List] of image bytes or as an [imagePath].
  /// On mobile, this uses Google ML Kit's Text Recognition.
  /// 
  /// Returns the raw recognized text string, or `null` if recognition fails.
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

  /// Recognizes and extracts barcodes/QR codes from an image.
  /// 
  /// The image can be provided as a [Uint8List] of image bytes or as an [imagePath].
  /// On mobile, this uses Google ML Kit's Barcode Scanning.
  /// 
  /// Returns a list of maps containing the barcode raw value and format details.
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
