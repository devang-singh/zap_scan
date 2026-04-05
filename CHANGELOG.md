## 1.1.1

*   **WASM Compatibility**: Removed all direct `dart:io` usage and replaced them with `defaultTargetPlatform` to support the new Dart WASM compiler on the Web.
*   **Official SPM Support**: Added a `Package.swift` manifest and restructured the native code into a shared `apple` directory to provide first-class Swift Package Manager support for both iOS and macOS.
*   **Up-to-Date Dependencies**: Bumped `camera` to `^0.12.0` and `google_mlkit_commons` to `^0.11.2` as recommended by pub.dev.
*   **Improved Native macOS Support**: The Apple plugin now uses a shared codebase for iOS and macOS, enabling native OCR on macOS via the Vision framework when used directly.

## 1.1.0

*   **Full Multi-platform Support**: Officially declared support for all 6 platforms (Android, iOS, Web, Windows, macOS, Linux).
*   **Unified Image Pipeline**: Refactored `scanFromImage` to use `XFile` instead of `File`, enabling cross-platform image processing.
*   **Custom OCR Delegates**: Introduced `ocrDelegate` and `barcodeDelegate` in `UniversalScannerController` to allow non-mobile platforms to plug in their own recognition engines.
*   **100% Documentation Coverage**: Added comprehensive DartDoc comments to all public classes, methods, and properties.
*   **Dependency Modernization**: Bumped `camera` to `^0.11.0` and `nfc_manager` to `^4.1.1`.
*   **iOS SPM Support**: Updated `podspec` for Swift Package Manager compatibility and included the required Privacy Manifest.
*   **Linting**: Enabled `public_member_api_docs` to ensure continued documentation quality.

## 1.0.3

*   Lowered Android `minSdkVersion` from 30 to 21.

## 1.0.2

*   Fixed broken repository and homepage links on pub.dev.

## 1.0.1

*   Renamed package internal identifiers.
*   Updated metadata with issue tracker and topics.

## 1.0.0

*   Initial release of `zap_scan`.
*   OCR for credit cards (supports horizontal, grid, and vertical layouts).
*   IATA Boarding Pass parsing from Barcodes and OCR text.
*   EMV NFC contactless card reading (Visa, Mastercard, Amex, RuPay).
*   Support for image enhancement strategies to handle embossed/metallic cards.
