/// Scapia Card Reader — scan payment card details via OCR (camera) or NFC.
///
/// ## Usage
///
/// Push [CardScannerScreen] and handle the result via [CardScannerScreen.onCardScanned]:
///
/// ```dart
/// import 'package:scapia_card_reader/card_reader.dart';
///
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => CardScannerScreen(
///       onCardScanned: (cardNumber, expiry) {
///         // cardNumber: '4111111111111111'
///         // expiry:     'YYMM' (NFC only) or null (OCR)
///       },
///     ),
///   ),
/// );
/// ```
///
/// For headless use, call [EmvNfcService.scanCard] or [CardScannerOCR.findCardSlots] directly.
library card_reader;

export 'src/nfc/emv_card.dart';
export 'src/nfc/emv_nfc_service.dart';
export 'src/ocr/universal_scanner_controller.dart';
export 'src/ocr/card_scanner_ocr.dart';
export 'src/ocr/card_reader_plugin.dart';
export 'src/ocr/card_scanner_widget.dart';
export 'src/ocr/scan_result.dart';
export 'src/ocr/boarding_pass_ocr.dart';
