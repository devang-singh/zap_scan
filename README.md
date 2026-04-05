# Zap Scan ⚡

[![Pub Version](https://img.shields.io/pub/v/zap_scan?color=blue)](https://pub.dev/packages/zap_scan)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](https://opensource.org/licenses/MIT)

**Zap Scan** is a package for Flutter that extracts data from cards, barcodes, and boarding passes. It leverages native, on-device OCR and EMV NFC to provide a "bulletproof" scanning experience.

## Features

- 🃏 **Card Scanning**: Robust OCR for 14- to 16-digit payment cards. Handles horizontal, grid (2×2), and vertical layouts.
- 🌫️ **Image Enhancement**: Specialized strategies (Sobel, Otsu, CLAHE) to handle glare, low light, and metallic/embossed cards.
- 🛫 **Boarding Pass Parsing**: Full IATA BCBP support to extract PNR, Seat, Flight Number, and more.
- 💳 **EMV NFC**: Contactless card reading (PAN & Expiry) for Visa, Mastercard, Amex, RuPay, and Diners.
- 📊 **Stability Consensus**: Built-in "consensus mechanism" that requires multiple identical frames before confirming a result, preventing "fluttery" OCR misreads.

## Installation

Add `zap_scan` to your `pubspec.yaml`:

```yaml
dependencies:
  zap_scan: ^1.0.0
```

## Setup

### Android
Set `minSdkVersion` to **21** in `android/app/build.gradle`.

### iOS
Set your iOS Deployment Target to **16.0**.

> [!NOTE]
> Review the [PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md) for a complete list of required permissions and configurations.

## Usage

### Camera-based Scanning (OCR & Barcodes)

The `ZapScanWidget` provides the camera preview, while the `UniversalScannerController` manages the detection logic.

```dart
import 'package:zap_scan/zap_scan.dart';

// 1. Initialize the controller
final controller = UniversalScannerController(
  onResultScanned: (result) {
    if (result is ZapCardResult) {
      print('Card Number: ${result.cardNumber}');
    } else if (result is FlightTicketResult) {
       print('Flight: ${result.flightNumber} via ${result.pnr}');
    }
  },
);

// 2. Add the widget to your build
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: ZapScanWidget(
      controller: controller,
      loader: CircularProgressIndicator(),
    ),
  );
}
```

### NFC Card Reading

NFC is handled via the static `EmvNfcService`.

```dart
import 'package:zap_scan/zap_scan.dart';

try {
  final card = await EmvNfcService.scanCard();
  if (card != null) {
    print('NFC Card: ${card.cardNumber}');
  }
} catch (e) {
  print('NFC Error: $e');
}
```

## Advanced Logic: Embossed & Metallic Cards

Zap Scan is unique for its **Strategy Rotation**. If a card isn't detected within a few frames, the engine automatically cycles through image enhancement filters (e.g., inverting colors, sharpening edges, or local contrast amplification). This is particularly effective for "silver-on-silver" embossed cards that traditional OCR often fails to pick up.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
