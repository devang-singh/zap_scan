/// Zap Scan — scan payment cards, barcodes, and boarding passes via OCR (camera) or NFC.
///
/// ## Usage
///
/// Use [UniversalScannerController] with [CardScannerWidget] (to be renamed to ZapScanWidget)
/// and handle the result via [UniversalScannerController.onResultScanned].
///
/// ```dart
/// import 'package:zap_scan/zap_scan.dart';
///
/// // ... implementation details ...
/// ```
///
/// For headless use, call [EmvNfcService.scanCard] or [CardScannerOCR.findCardSlots] directly.
library zap_scan;

export 'src/nfc/emv_card.dart';
export 'src/nfc/emv_nfc_service.dart';
export 'src/ocr/universal_scanner_controller.dart';
export 'src/ocr/zap_scan_ocr.dart';
export 'src/ocr/zap_scan_plugin.dart';
export 'src/ocr/zap_scan_widget.dart';
export 'src/ocr/scan_result.dart';
export 'src/ocr/boarding_pass_ocr.dart';
