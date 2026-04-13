import 'package:zap_scan/src/ocr/zap_scan_ocr.dart';

void main() {
  final samples = [
    "3610 102077 3663", // Valid Diners (Luhn: 50 % 10 = 0)
    "8110841018181888", // Invalid Garbage (Luhn: 68 % 10 != 0)
    "Nepal and Bhutan. 3610 102077 3663 Phone: 1800 202 6161", // Mixed
    "b529 bO00\nD000 I079", // Scapia Grid (6529 6000 0000 1079)
    "MPi IN KA O P300476 1224", // False-Luhn Noise from Scapia Bottom Info
    "b529 bO00\nD000 I079\nMPi IN KA O P300476 1224", // Competitive Case (Card vs Noise)
  ];

  print("Testing Layout-Based OCR Extraction...");
  for (final s in samples) {
    final res = ZapScanOCR.extractCardNumber(s);
    if (res != null) {
      print("Source: '$s'\n -> Extracted: '$res' (Length: ${res.length})");
    } else {
      print("Source: '$s' -> FAILED");
    }
  }
}
