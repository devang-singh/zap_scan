# zap_scan

Flutter Plugin for reading card details via **OCR** (Native Vision) or **NFC**.

### Architecture Overview
This library leverages a custom **Headless Native Engine** architecture to minimize app size and maximize scanning performance without overriding your Flutter UI elements:
- **Android**: Uses Play Services Unbundled ML Kit (0 MB footprint in your APK since it calls OS-level modules).
- **iOS**: Uses the built-in Apple `Vision` Framework (no external dependencies).
- **Dart**: Manages camera streams and applies battle-tested regex to piece together vertically stacked or embossed horizontal cards based on text layout.
## Installation

```yaml
dependencies:
  scapia_card_reader:
    git:
      url: https://github.com/scapia/zap_scan.git
```

### Android permissions

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.NFC" />
```

### iOS permissions

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to scan your card number.</string>
```

> NFC EMV card reading capabilities depend on OS support.

---

## Usage

### 1. Camera OCR

The package provides a `CardScannerController` to handle the OCR logic, and a `CardScannerWidget` to render the camera preview. You can place this widget anywhere in your app and draw your own UI (buttons, text) over it.

```dart
import 'package:flutter/material.dart';
import 'package:zap_scan/zap_scan.dart';

class MyCardScanner extends StatefulWidget {
  @override
  State<MyCardScanner> createState() => _MyCardScannerState();
}

class _MyCardScannerState extends State<MyCardScanner> {
  late final CardScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CardScannerController(
      scanExpiryDate: true,  // Optional: Extrapolate expiry date (Best effort)
      scanCvv: true,         // Optional: Extrapolate CVV (Best effort)
      onCardDetailsScanned: (CardDetails details) {
        print("Card: ${details.cardNumber}");
        print("Expiry: ${details.expiryDate}");
        print("CVV: ${details.cvv}");
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Card"),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          )
        ],
      ),
      body: CardScannerWidget(
        controller: _controller,
      ),
    );
  }
}
```

### 2. NFC Only (Headless)

NFC scanning is fully headless. You can trigger it from any button tap and build your own "Ready to scan" dialog on Android. On iOS, the system automatically shows the scanning bottom sheet.

```dart
import 'package:zap_scan/zap_scan.dart';

Future<void> startNfc() async {
  try {
    // Show your own UI asking the user to tap the card
    final EmvCard? card = await EmvNfcService.scanCard();
    if (card != null) {
      print("NFC Card: ${card.cardNumber}, Expiry: ${card.expiryDate}");
    }
  } catch (e) {
    print("NFC Error: $e");
  }
}
```

### 3. Headless OCR parser (No camera UI)

```dart
final slots = CardScannerOCR.findCardSlots(rawOcrText);
// slots is a List<Set<String>>? — each position holds the possible digits.
```

---

## Public API

| Symbol | Description |
|--------|-------------|
| `CardScannerController` | Manages camera lifecycle, torch, and OCR frame consensus |
| `CardScannerWidget` | Renders the camera preview bound to the controller |
| `EmvNfcService` | Headless NFC EMV reader service |
| `EmvCard` | Result model `{cardNumber, expiryDate}` |
| `EmvTlvParser` | EMV TLV parsing utilities for internal or advanced usage |
| `CardScannerOCR` | Pure OCR parser — no Flutter/camera dependencies |
