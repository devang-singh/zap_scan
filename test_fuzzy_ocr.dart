import 'package:flutter/widgets.dart';
import 'package:zap_scan/src/ocr/zap_scan_ocr.dart';

void main() {
  final samples = [
    "000 1e3 5578 90L0",
    "H000 1R 56789040",
    "M000 R3 5518 9DL0",
    "N000 A23 5678 9010",
    "H000 123 SK78 9010",
    "4000 LR3 55189010",
    "H000 123W 56789010",
    "M000 12Y 56789010",
  ];

  debugPrint("Testing Lenient OCR Extraction...");
  for (final s in samples) {
    final slots = ZapScanOCR.findCardSlots(s);
    if (slots != null) {
      final res = slots.map((s) => s.first).join();
      debugPrint("Source: '$s' -> Extracted: '$res' (Length: ${res.length})");
    } else {
      debugPrint("Source: '$s' -> FAILED");
    }
  }
}
