import 'dart:async';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;
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

  bool _showDebugOverlay = false;
  bool _isDebugStreamPaused = false;

  /// Whether to show a live debug overlay with raw OCR detections.
  bool get showDebugOverlay => _showDebugOverlay;
  set showDebugOverlay(bool value) {
    _showDebugOverlay = value;
    notifyListeners();
  }

  /// Whether to pause the live debug stream for manual inspection.
  bool get isDebugStreamPaused => _isDebugStreamPaused;
  set isDebugStreamPaused(bool value) {
    _isDebugStreamPaused = value;
    notifyListeners();
  }

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

  /// The most accurate guessed card number so far.
  String? get guessedCard => _guessedCard;

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
  static const int _historyLimit = 15; // Track last 15 valid frames

  // Buffer tracking the most recent candidate strings from valid frames
  final List<String> _candidateHistory = [];
  int _totalValidFrames = 0;
  String? _guessedCard;

  final Map<String, int> _expiryVotes = {};
  final Map<String, int> _cvvVotes = {};

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
    reset();
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
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.android ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
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
    if (_isBusy) return null;
    _isBusy = true;

    try {
      // Consolidate all successful OCR results into a candidate list for absorption consensus
      final candidateMatches = <String>[];
      String? bestRawText;
      String? bestExpiry;
      String? bestCvv;

      // 1. Pass 1: Try as-is (using Native Path for best OS-level EXIF support)
      var nativeResult = await _scanSinglePass(imageFile: imageFile);
      if (nativeResult != null && nativeResult is ZapCardResult) {
        bestRawText = nativeResult.rawText;
        if (nativeResult.expiryDate != null) bestExpiry = nativeResult.expiryDate;
        if (nativeResult.cvv != null) bestCvv = nativeResult.cvv;
        candidateMatches.add(nativeResult.cardNumber);
      } else if (nativeResult != null && nativeResult is BarcodeResult) {
        // Boarding passes / Barcodes are deterministically accurate, return immediately
        return nativeResult;
      } else if (nativeResult != null && nativeResult is ScanErrorResult) {
        // If a platform error occurs natively, we can still fall back to image bytes processing below
      }

      // 2. Pass 2: Try 180° Rotation (using Native Path if possible, or Manual Bytes)
      // Since native recognizeText(imagePath) doesn't support rotation arg easily for files,
      // we'll move to the Byte Path for subsequent passes.
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;

      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return nativeResult;
      final rawBytes = data.buffer.asUint8List();

      // Convert to NV21 (Luma + padded Chroma) for all subsequent byte-level passes
      final ySize = width * height;
      final uvSize = ySize ~/ 2;
      final nv21 = Uint8List(ySize + uvSize);

      // 1. Fill Y-Plane
      for (int i = 0; i < ySize; i++) {
        final o = i * 4;
        nv21[i] = ImageProcessing.luminance(rawBytes[o], rawBytes[o + 1], rawBytes[o + 2]);
      }

      // 2. Fill UV-Plane with neutral 128 (grayscale chrominance)
      // Required by ML Kit because NV21 is strictly monitored by image parsers.
      nv21.fillRange(ySize, ySize + uvSize, 128);

      // Prepare generic luminance passes

      // Static gallery images rarely need heavy edge detection.
      // Limit to none + grayscale for max speed (4 seconds -> ~1.5 sec)
      for (final strategy in [
        EnhancementStrategy.none,
        EnhancementStrategy.grayscaleHiContrast,
      ]) {
        // Prepare base luminance for this strategy
        // Prepare base luminance for this strategy
        final processLum = Uint8List.view(nv21.buffer, 0, ySize); // Modify only Y plane
        final workNv21 = Uint8List.fromList(nv21);

        if (strategy != EnhancementStrategy.none) {
          final workLum = Uint8List.view(workNv21.buffer, 0, ySize);
          _enhancerService.processLuminance(workLum, width, height, strategy);
        }

        // Try 0° and 180° for each enhancement
        for (final rot in [0, 180]) {
          final res = await _scanSinglePass(bytes: workNv21, width: width, height: height, rotation: rot);
          if (res != null && res is ZapCardResult) {
            final numStr = res.cardNumber;
            bestRawText = res.rawText;
            if (res.expiryDate != null) bestExpiry = res.expiryDate;
            if (res.cvv != null) bestCvv = res.cvv;

            candidateMatches.add(numStr);

            // EARLY ABORT: If we mathematically validated the Luhn check
            // natively right here, exit the entire enhancement loop instantly!
            // No need to run 4 more passes and wait 2 seconds.
            if (ZapScanOCR.luhnCheck(numStr)) {
              return res;
            }
          }
        }
      }

      // 3. Consensus Winner: Find the highest scored absorbed candidate
      if (candidateMatches.isNotEmpty) {
        final stableDigits = _performSubsequenceConsensus(candidateMatches);
        if (stableDigits != null && stableDigits.length >= 13) {
          return ZapCardResult(
            cardNumber: stableDigits,
            expiryDate: bestExpiry,
            cvv: bestCvv,
            rawText: bestRawText ?? "",
          );
        }
      }

      return nativeResult is ScanErrorResult ? nativeResult : null;
    } catch (e) {
      if (e is services.PlatformException) {
        return ScanErrorResult(
          code: e.code,
          message: e.message ?? "Unknown native error",
          rawText: e.details?.toString(),
        );
      }
      return ScanErrorResult(
        code: "unexpected_error",
        message: e.toString(),
      );
    } finally {
      _isBusy = false;
    }
  }

  /// Internal helper to perform a single OCR/Barcode pass for a specific image configuration.
  Future<ScanResult?> _scanSinglePass({
    XFile? imageFile,
    Uint8List? bytes,
    int? width,
    int? height,
    int rotation = 0,
  }) async {
    Object? lastError;

    try {
      // 1. Try Barcodes
      if (scanBarcodes) {
        try {
          List<Map<String, dynamic>>? barcodeResults;
          if (imageFile != null) {
            if (barcodeDelegate != null) {
              barcodeResults = await barcodeDelegate!(imageFile);
            } else {
              barcodeResults = await ZapScanPlugin.recognizeBarcode(imagePath: imageFile.path);
            }
          } else {
            barcodeResults = await ZapScanPlugin.recognizeBarcode(
              bytes: bytes!,
              width: width!,
              height: height!,
              rotation: rotation,
              format: 17, // 17 = NV21 format
            );
          }

          if (barcodeResults != null && barcodeResults.isNotEmpty) {
            final payload = barcodeResults.first['rawValue'] as String?;
            final format = barcodeResults.first['format'] as String? ?? "UNKNOWN";
            if (payload != null) {
              String? rawText;
              if (scanCards) {
                try {
                  if (imageFile != null) {
                    rawText = ocrDelegate != null ? await ocrDelegate!(imageFile) : await ZapScanPlugin.recognizeText(imagePath: imageFile.path);
                  } else {
                    rawText = await ZapScanPlugin.recognizeText(bytes: bytes!, width: width!, height: height!, rotation: rotation, format: 17);
                  }
                } catch (_) {}
              }
              if (payload.startsWith("M1") && payload.length > 20) {
                final bpResult = BoardingPassOCR.parseBoardingPass(payload, format, rawText);
                if (bpResult != null) return bpResult;
              }
              return BarcodeResult(payload: payload, format: format, rawText: rawText);
            }
          }
        } catch (e) {
          lastError = e;
        }
      }

      // 2. Try Cards/OCR Text
      if (scanCards) {
        String? text;
        if (imageFile != null) {
          text = ocrDelegate != null ? await ocrDelegate!(imageFile) : await ZapScanPlugin.recognizeText(imagePath: imageFile.path);
        } else {
          text = await ZapScanPlugin.recognizeText(bytes: bytes!, width: width!, height: height!, rotation: rotation, format: 17);
        }

        if (text != null && text.isNotEmpty) {
          var cardCandidate = ZapScanOCR.extractCardNumberFromUpload(text);
          if (cardCandidate != null) {
            String? expiry;
            String? cvv;
            if (scanExpiryDate) expiry = ZapScanOCR.findExpiryDate(text);
            if (scanCvv) cvv = ZapScanOCR.findCvv(text, cardCandidate);
            return ZapCardResult(
              cardNumber: cardCandidate,
              expiryDate: expiry,
              cvv: cvv,
              rawText: text,
            );
          }
        }
      }

      if (lastError != null && lastError is services.PlatformException) {
        final pe = lastError;
        return ScanErrorResult(
          code: pe.code,
          message: pe.message ?? "Unknown native error",
          rawText: pe.details?.toString(),
        );
      }
      return null;
    } catch (e) {
      if (e is services.PlatformException) rethrow; // Handled in scanFromImage
      return null;
    }
  }

  /// Resets the controller's internal state and consensus tracking.
  void reset() {
    _probableCard = null;
    _guessedCard = null;
    _finalConfirmedResult = null;
    _probableExpiry = null;
    _probableCvv = null;
    _totalValidFrames = 0;
    _candidateHistory.clear();
    _expiryVotes.clear();
    _cvvVotes.clear();
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
        try {
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
        } catch (_) {
          // Barcode engine failed (e.g. iOS simulator inference context).
          // Fall through to text/card OCR.
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

        var cardCandidate = ZapScanOCR.extractCardNumber(filteredText);

        // Retry with 180° rotation in case the card is held upside down.
        if (cardCandidate == null) {
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
                final extractCand = ZapScanOCR.extractCardNumber(candidate);
                if (extractCand != null) {
                  cardCandidate = extractCand;
                  filteredText = candidate;
                  dump.add('=== retried at 180° ===');
                  dump.add(candidate);
                  break;
                }
              }
            }
          }
        }

        // Only update debug stream if not paused
        if (!isDebugStreamPaused) {
          _rawText = filteredText;
          onRawDataScanned?.call(filteredText);
          _rawLines = dump;
        }

        if (_finalConfirmedResult == null) {
          String? expiry;
          String? cvv;
          if (cardCandidate != null) {
            if (scanExpiryDate) expiry = ZapScanOCR.findExpiryDate(filteredText);
            if (scanCvv) cvv = ZapScanOCR.findCvv(filteredText, cardCandidate);

            _updateCardFrequency(cardCandidate, expiry, cvv);
          } else {
            // Optional: slowly decay frequency if no card found to handle card swap
            _decayFrequencies();
          }
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

  void _updateCardFrequency(String? newCardNumber, String? newExpiry, String? newCvv) {
    if (newCardNumber == null || newCardNumber.isEmpty) return;

    if (newExpiry != null) _expiryVotes[newExpiry] = (_expiryVotes[newExpiry] ?? 0) + 1;
    if (newCvv != null) _cvvVotes[newCvv] = (_cvvVotes[newCvv] ?? 0) + 1;

    // Align slots to 16 digits (right-aligned for now, as most cards are 16 or 15/14)
    final offset = 16 - newCardNumber.length;
    if (offset < 0) return; // Should not happen with current OCR logic

    if (_totalValidFrames >= _historyLimit) {
      // Decay old data by removing the oldest entries instead of mathematically decaying
      _candidateHistory.removeRange(0, _candidateHistory.length - (_historyLimit - 1));
      _totalValidFrames = _candidateHistory.length;
    }

    _totalValidFrames++;
    _candidateHistory.add(newCardNumber);

    _updateProbableCard();

    // Check if we have enough consensus to finalize
    // For finalization, we still want a "perfect" set of digits that pass Luhn
    if (_totalValidFrames >= _requiredConsensus && _probableCard != null) {
      // Only finalize if the probable card has enough stable digits
      // In fuzzy mode, we might finalize even if Luhn fails if we want "most accurate"
      // but for the primary result, let's stick to Luhn or high stability.

      _finalConfirmedResult = ZapCardResult(
        cardNumber: _probableCard!,
        guessedCardNumber: _guessedCard,
        expiryDate: _probableExpiry,
        cvv: _probableCvv,
        rawText: _rawText,
      );

      onResultScanned?.call(_finalConfirmedResult!);
    }
  }

  void _decayFrequencies() {
    // If we haven't seen a card for a bit, reset buffer
    if (_totalValidFrames > 0) {
      _totalValidFrames = 0;
      _candidateHistory.clear();
      _probableCard = null;
      _guessedCard = null;
    }
  }

  bool _isSubsequence(String sub, String full) {
    if (sub.length >= full.length) return false;
    int i = 0;
    for (int j = 0; j < full.length && i < sub.length; j++) {
      if (sub[i] == full[j]) {
        i++;
      }
    }
    return i == sub.length;
  }

  /// Calculates the best candidate via Subsequence Absorption Consensus
  static String? _performSubsequenceConsensus(List<String> candidates) {
    if (candidates.isEmpty) return null;

    final scores = <String, int>{};
    for (final cand in candidates) {
      scores[cand] = (scores[cand] ?? 0) + 1;
    }

    final absorbedScores = Map<String, int>.from(scores);

    for (final a in scores.keys) {
      for (final b in scores.keys) {
        if (a == b) continue;
        if (b.length > a.length) {
          // We do a simple subsequence check. We want to be lenient enough:
          // A missing digit OCR hallucination shouldn't destroy the score.
          // If A is a perfect subsequence of B computationally:
          int i = 0;
          for (int j = 0; j < b.length && i < a.length; j++) {
            if (a[i] == b[j]) {
              i++;
            }
          }
          if (i == a.length) {
            // B absorbs A's score completely!
            absorbedScores[b] = (absorbedScores[b] ?? 0) + (scores[a] ?? 0);
          }
        }
      }
    }

    // Find candidate with max absorbed score
    var bestCand = absorbedScores.keys.first;
    var maxScore = -1;
    for (final entry in absorbedScores.entries) {
      if (entry.value > maxScore || (entry.value == maxScore && entry.key.length > bestCand.length)) {
        maxScore = entry.value;
        bestCand = entry.key;
      }
    }

    return bestCand;
  }

  void _updateProbableCard() {
    _guessedCard = _candidateHistory.isNotEmpty ? _candidateHistory.last : null;

    final stableBest = _performSubsequenceConsensus(_candidateHistory);

    // If perfectly aligned string gets enough votes (or absorbed votes), we deem it probable
    // In strict mode we'd require at least 50% hit rate:
    if (stableBest != null) {
      // Recalculate score subset for stability confirmation
      int confirmScore = 0;
      for (final cand in _candidateHistory) {
        if (cand == stableBest || _isSubsequence(cand, stableBest)) {
          confirmScore++;
        }
      }
      if (confirmScore >= (_totalValidFrames / 2).ceil() && confirmScore >= 2) {
        _probableCard = stableBest;
      } else {
        _probableCard = null;
      }
    } else {
      _probableCard = null;
    }

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

    final services.DeviceOrientation orientation = controller.value.deviceOrientation;
    int deviceDeg = 0;
    switch (orientation) {
      case services.DeviceOrientation.portraitUp:
        deviceDeg = 0;
        break;
      case services.DeviceOrientation.landscapeLeft:
        deviceDeg = 90;
        break;
      case services.DeviceOrientation.portraitDown:
        deviceDeg = 180;
        break;
      case services.DeviceOrientation.landscapeRight:
        deviceDeg = 270;
        break;
    }

    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    if (defaultTargetPlatform == TargetPlatform.iOS) return sensorOrientation;

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
