import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'zap_scan_ocr.dart';
import 'image_processing.dart';
import 'zap_scan_plugin.dart';
import 'scan_result.dart';
import 'boarding_pass_ocr.dart';

/// A delegate that provides OCR and Barcode recognition capabilities
/// for non-mobile platforms.
typedef ScanOcrDelegate = Future<String?> Function(XFile file);

/// A delegate that provides Barcode recognition capabilities
/// for non-mobile platforms.
typedef ScanBarcodeDelegate = Future<List<Map<String, dynamic>>?> Function(XFile file);

/// The central controller for managing the scanning lifecycle, camera streams,
/// and consensus-based OCR/Barcode extraction.
/// 
/// This class handles:
/// * Camera initialization and streaming.
/// * Real-time image enhancement.
/// * Stable consensus for card number extraction.
/// * IATA Boarding Pass parsing.
/// * Static image scanning (via file upload).
class UniversalScannerController extends ChangeNotifier {
  CameraController? _cameraController;

  static List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;

  final ImageProcessing _enhancerService = ImageProcessing();

  /// Enables or disables real-time image enhancement (Sobel/Otsu filters).
  /// This is particularly useful for embossed or low-contrast cards.
  bool enableImageEnhancement = false;

  /// Whether to attempt scanning payment cards.
  bool scanCards = true;

  /// Whether to attempt scanning barcodes/QR codes (including Boarding Passes).
  bool scanBarcodes = true;

  /// Whether to attempt extracting the card's expiry date (MM/YY).
  bool scanExpiryDate = false;

  /// Whether to attempt extracting the card's 3- or 4-digit CVV.
  bool scanCvv = false;

  /// Custom OCR engine for non-mobile platforms (Web/Desktop). 
  /// If null, the native ML Kit plugin is used.
  ScanOcrDelegate? ocrDelegate;

  /// Custom Barcode engine for non-mobile platforms (Web/Desktop).
  /// If null, the native ML Kit plugin is used.
  ScanBarcodeDelegate? barcodeDelegate;

  /// Returns true if the image stabilizer detects significant glare.
  bool get glareDetected => _enhancerService.glareDetected;

  bool _isBusy = false;
  bool _isDisposed = false;
  bool _isPaused = false;

  /// Returns true if the camera stream is currently paused.
  bool get isPaused => _isPaused;

  bool _torchOn = false;
  
  /// Returns true if the camera flash/torch is currently enabled.
  bool get torchOn => _torchOn;

  String? _probableCard;
  
  /// The current most probable card number being tracked.
  String? get probableCard => _probableCard;

  ScanResult? _finalConfirmedResult;
  
  /// The final confirmed result once consensus is reached.
  ScanResult? get finalConfirmedResult => _finalConfirmedResult;

  String? _probableExpiry;
  
  /// The current most probable expiry date (MM/YY).
  String? get probableExpiry => _probableExpiry;

  String? _probableCvv;
  
  /// The current most probable CVV.
  String? get probableCvv => _probableCvv;

  /// Returns true if a final result has been confirmed and scanning has stopped.
  bool get isConfirmed => _finalConfirmedResult != null;

  List<String> _rawLines = [];
  
  /// Debugging lines from the OCR engine (strategy notes + raw text).
  List<String> get rawLines => _rawLines;

  /// The underlying [CameraController] used for live scanning.
  CameraController? get cameraController => _cameraController;

  /// Callback triggered when a final [ScanResult] is confirmed.
  final void Function(ScanResult result)? onResultScanned;
  
  /// Callback triggered for every frame with the raw OCR text.
  final void Function(String rawText)? onRawDataScanned;
  
  /// Callback triggered when the camera is initialized and ready.
  final void Function()? onCameraReady;
  
  /// Callback triggered when an error occurs during scanning.
  final void Function(Object error)? onError;

  String _rawText = "";
  
  /// The raw text from the most recent OCR frame.
  String get rawText => _rawText;

  static const int _requiredConsensus = 3;
  List<Set<String>>? _consensusSlots;
  final Map<String, int> _expiryVotes = {};
  final Map<String, int> _cvvVotes = {};
  int _consensusFrames = 0;

  int _barcodeConsensusFrames = 0;
  String? _lastBarcodePayload;

  /// Creates a new [UniversalScannerController] with optional configuration.
  UniversalScannerController({
    this.onResultScanned,
    this.onRawDataScanned,
    this.onCameraReady,
    this.onError,
    this.ocrDelegate,
    this.barcodeDelegate,
    this.scanCards = true,
    this.scanBarcodes = true,
    this.scanExpiryDate = false,
    this.scanCvv = false,
  });

  /// Initializes and starts the back camera. 
  /// Automatically picks the back camera if available.
  Future<void> startCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      for (var i = 0; i < _cameras.length; i++) {
        if (_cameras[i].lensDirection == CameraLensDirection.back) {
          _cameraIndex = i;
          break;
        }
      }
      if (_cameraIndex != -1) {
        final camera = _cameras[_cameraIndex];
        _cameraController = CameraController(
          camera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
        );

        await _cameraController!.initialize();
        if (_isDisposed) return;

        _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.startImageStream(_processCameraImage);
        onCameraReady?.call();
        notifyListeners();
      }
    } catch (e) {
      onError?.call(e);
    }
  }

  /// Pauses the live camera image stream.
  Future<void> pauseCamera() async {
    if (_cameraController == null || _isPaused) return;
    _isPaused = true;
    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
    notifyListeners();
  }

  /// Resumes the live camera image stream.
  Future<void> resumeCamera() async {
    if (_cameraController == null || !_isPaused) return;
    _isPaused = false;
    await _cameraController!.startImageStream(_processCameraImage);
    notifyListeners();
  }

  /// Stops and disposes of the camera controller.
  Future<void> stopCamera() async {
    _isPaused = false;
    final c = _cameraController;
    _cameraController = null;
    if (c == null) return;
    if (c.value.isInitialized && c.value.isStreamingImages) {
      await c.stopImageStream();
    }
    await c.dispose();
    notifyListeners();
  }

  /// Toggles the flash/torch on the current camera.
  Future<void> toggleTorch() => setTorchEnabled(!_torchOn);

  /// Directly sets the camera's torch status.
  Future<void> setTorchEnabled(bool enabled) async {
    if (_cameraController == null) return;
    _torchOn = enabled;
    await _cameraController!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
    notifyListeners();
  }

  /// Runs the universal parsing logic on a static image instead of the camera live feed.
  /// 
  /// This method is cross-platform and uses [ocrDelegate]/[barcodeDelegate] if on Web/Desktop.
  Future<ScanResult?> scanFromImage(XFile imageFile) async {
    // 1. Try Barcodes first
    if (scanBarcodes) {
      List<Map<String, dynamic>>? barcodeResults;
      if (barcodeDelegate != null) {
        barcodeResults = await barcodeDelegate!(imageFile);
      } else {
         barcodeResults = await ZapScanPlugin.recognizeBarcode(imagePath: imageFile.path);
      }
      
      if (barcodeResults != null && barcodeResults.isNotEmpty) {
        final payload = barcodeResults.first['rawValue'] as String?;
        final format = barcodeResults.first['format'] as String? ?? "UNKNOWN";
        if (payload != null) {
          String? rawText;
          if (scanCards) {
            if (ocrDelegate != null) {
              rawText = await ocrDelegate!(imageFile);
            } else {
              rawText = await ZapScanPlugin.recognizeText(imagePath: imageFile.path);
            }
          }
          if (payload.startsWith("M1") && payload.length > 20) {
            final bpResult = BoardingPassOCR.parseBoardingPass(payload, format, rawText);
            if (bpResult != null) return bpResult;
          }
          return BarcodeResult(payload: payload, format: format, rawText: rawText);
        }
      }
    }

    // 2. Try Cards/OCR Text
    if (scanCards) {
      String? text;
      if (ocrDelegate != null) {
        text = await ocrDelegate!(imageFile);
      } else {
        text = await ZapScanPlugin.recognizeText(imagePath: imageFile.path);
      }
      
      if (text == null) return null;
      var cardSlots = ZapScanOCR.findCardSlots(text);
      if (cardSlots == null) {
        final reversed = text.split('\n').reversed.join('\n');
        cardSlots = ZapScanOCR.findCardSlots(reversed);
      }
      if (cardSlots != null) {
        final tempCardNum = cardSlots.map((s) => s.first).join();
        String? expiry;
        String? cvv;
        if (scanExpiryDate) expiry = ZapScanOCR.findExpiryDate(text);
        if (scanCvv) cvv = ZapScanOCR.findCvv(text, tempCardNum);
        return ZapCardResult(
          cardNumber: tempCardNum,
          expiryDate: expiry,
          cvv: cvv,
          rawText: text,
        );
      }
    }
    return null;
  }

  /// Resets the controller's internal state and consensus tracking.
  void reset() {
    _probableCard = null;
    _finalConfirmedResult = null;
    _probableExpiry = null;
    _probableCvv = null;
    _consensusSlots = null;
    _expiryVotes.clear();
    _cvvVotes.clear();
    _consensusFrames = 0;
    _barcodeConsensusFrames = 0;
    _lastBarcodePayload = null;
    _rawLines = [];
    _enhancerService.reset();
    notifyListeners();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _finalConfirmedResult != null) return;
    _isBusy = true;

    try {
      final rotDeg = _getRotationDeg();

      final inputImage = await _enhancerService.process(
        image,
        rotDeg,
        enableEnhancement: enableImageEnhancement,
      );
      if (inputImage == null || inputImage.bytes == null) return;

      // 1. BARCODE SCANNING
      if (scanBarcodes) {
        final barcodeResults = await ZapScanPlugin.recognizeBarcode(
          bytes: inputImage.bytes!,
          width: inputImage.metadata!.size.width.toInt(),
          height: inputImage.metadata!.size.height.toInt(),
          rotation: inputImage.metadata!.rotation.rawValue,
          format: inputImage.metadata!.format.rawValue,
        );

        if (barcodeResults != null && barcodeResults.isNotEmpty) {
          final payload = barcodeResults.first['rawValue'] as String?;
          final format = barcodeResults.first['format'] as String?;
          if (payload != null) {
            _intersectBarcodeConsensus(payload, format ?? "UNKNOWN");
            if (_finalConfirmedResult != null) return; // Exit if confirmed
          } else {
            _resetBarcodeConsensus();
          }
        } else {
          _resetBarcodeConsensus();
        }
      }

      // 2. TEXT/CARD OCR SCANNING
      if (scanCards) {
        final textResult = await ZapScanPlugin.recognizeText(
          bytes: inputImage.bytes!,
          width: inputImage.metadata!.size.width.toInt(),
          height: inputImage.metadata!.size.height.toInt(),
          rotation: inputImage.metadata!.rotation.rawValue,
          format: inputImage.metadata!.format.rawValue,
        );

        if (textResult == null) return;
        var filteredText = textResult;

        final dump = <String>[];
        if (enableImageEnhancement) {
          dump.add('=== strategy: ${_enhancerService.currentStrategy.name}'
              '${_enhancerService.glareDetected ? " [GLARE]" : ""} ===');
        }
        dump.add('=== text ===');
        dump.add(filteredText.isEmpty ? '(empty)' : filteredText);

        var cardSlots = ZapScanOCR.findCardSlots(filteredText);

        // Retry with 180° rotation in case the card is held upside down.
        if (cardSlots == null) {
          final rotDeg180 = (rotDeg + 180) % 360;
          final inputImage180 = _enhancerService.convertStandard(image, rotDeg180);
          if (inputImage180 != null && inputImage180.bytes != null) {
            final textResult180 = await ZapScanPlugin.recognizeText(
              bytes: inputImage180.bytes!,
              width: inputImage180.metadata!.size.width.toInt(),
              height: inputImage180.metadata!.size.height.toInt(),
              rotation: inputImage180.metadata!.rotation.rawValue,
              format: inputImage180.metadata!.format.rawValue,
            );
            if (textResult180 != null) {
              final flippedText = textResult180;
              final flippedLines = flippedText.split('\n');
              final candidates = [
                flippedLines.reversed.join('\n'),
                flippedText,
              ];
              for (final candidate in candidates) {
                final slots = ZapScanOCR.findCardSlots(candidate);
                if (slots != null) {
                  cardSlots = slots;
                  filteredText = candidate;
                  dump.add('=== retried at 180° ===');
                  dump.add(candidate);
                  break;
                }
              }
            }
          }
        }

        _rawText = filteredText;
        onRawDataScanned?.call(filteredText);
        _rawLines = dump;

        if (_finalConfirmedResult == null) {
          String? expiry;
          String? cvv;
          if (cardSlots != null) {
            final tempCardNum = cardSlots.map((s) => s.first).join();
            if (scanExpiryDate) expiry = ZapScanOCR.findExpiryDate(filteredText);
            if (scanCvv) cvv = ZapScanOCR.findCvv(filteredText, tempCardNum);
          }
          _intersectCardConsensus(cardSlots, expiry, cvv);
        }
      }

      notifyListeners();
    } finally {
      _isBusy = false;
    }
  }

  void _resetBarcodeConsensus() {
    _lastBarcodePayload = null;
    _barcodeConsensusFrames = 0;
  }

  void _intersectBarcodeConsensus(String payload, String format) {
    if (_lastBarcodePayload == payload) {
      _barcodeConsensusFrames++;
    } else {
      _lastBarcodePayload = payload;
      _barcodeConsensusFrames = 1;
    }

    // Barcodes only need 2 frames to confirm stability
    if (_barcodeConsensusFrames >= 2) {
      // Identify IATA BCBP (Boarding Passes usually start with M1)
      if (payload.startsWith("M1") && payload.length > 20) {
        final bpResult = BoardingPassOCR.parseBoardingPass(payload, format, _rawText);
        if (bpResult != null) {
          _finalConfirmedResult = bpResult;
        } else {
          _finalConfirmedResult = BarcodeResult(
            payload: payload,
            format: format,
            rawText: _rawText,
          );
        }
      } else {
        _finalConfirmedResult = BarcodeResult(
          payload: payload,
          format: format,
          rawText: _rawText,
        );
      }
      onResultScanned?.call(_finalConfirmedResult!);
    }
  }

  void _intersectCardConsensus(List<Set<String>>? newSlots, String? newExpiry, String? newCvv) {
    if (newSlots == null) return;

    if (newExpiry != null) _expiryVotes[newExpiry] = (_expiryVotes[newExpiry] ?? 0) + 1;
    if (newCvv != null) _cvvVotes[newCvv] = (_cvvVotes[newCvv] ?? 0) + 1;

    if (_consensusSlots == null || _consensusSlots!.length != newSlots.length) {
      _consensusSlots = newSlots.map((s) => Set<String>.from(s)).toList();
      _consensusFrames = 1;
      _updateProbableCard();
      return;
    }

    bool stillValid = true;
    final nextConsensus = <Set<String>>[];

    for (int i = 0; i < newSlots.length; i++) {
      final intersection = _consensusSlots![i].intersection(newSlots[i]);
      if (intersection.isNotEmpty) {
        nextConsensus.add(intersection);
      } else {
        stillValid = false;
        break;
      }
    }

    if (stillValid) {
      _consensusSlots = nextConsensus;
      _consensusFrames++;
      _updateProbableCard();

      if (_consensusFrames >= _requiredConsensus) {
        final confirmedCardStr = _probableCard!;

        _finalConfirmedResult = ZapCardResult(
          cardNumber: confirmedCardStr,
          expiryDate: _probableExpiry,
          cvv: _probableCvv,
          rawText: _rawText,
        );

        onResultScanned?.call(_finalConfirmedResult!);
      }
    } else {
      _consensusSlots = newSlots.map((s) => Set<String>.from(s)).toList();
      _consensusFrames = 1;
      _updateProbableCard();
    }
  }

  void _updateProbableCard() {
    if (_consensusSlots == null) return;
    _probableCard = _consensusSlots!.map((s) => s.first).join();

    if (_expiryVotes.isNotEmpty) {
      _probableExpiry = _expiryVotes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }
    if (_cvvVotes.isNotEmpty) {
      _probableCvv = _cvvVotes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }
  }

  int _getRotationDeg() {
    final controller = _cameraController;
    if (controller == null) return 0;

    final DeviceOrientation orientation = controller.value.deviceOrientation;
    int deviceDeg = 0;
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        deviceDeg = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceDeg = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceDeg = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceDeg = 270;
        break;
    }

    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) return sensorOrientation;

    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDeg) % 360;
    }
    return (sensorOrientation - deviceDeg + 360) % 360;
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopCamera();
    super.dispose();
  }
}
