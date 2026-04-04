import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Strategies for enhancing camera images before OCR processing.
enum EnhancementStrategy {
  /// No enhancement — standard fast-path conversion.
  none,

  /// Sobel edge detection — highlights gradient edges.
  /// Critical for embossed numbers which create physical shadows.
  sobelEdge,

  /// Local contrast amplification via integral-image unsharp mask.
  /// Amplifies subtle luminance differences (e.g. 2-3 value gap).
  localContrast,

  /// Global histogram equalization — stretches the full luminance range.
  histogramEqualization,

  /// Otsu's binary threshold — adaptive black/white conversion.
  binaryThreshold,

  /// Block-based adaptive threshold — handles uneven lighting.
  /// Approximates CLAHE for local contrast enhancement.
  adaptiveThreshold,

  /// Inverted luminance — swaps light and dark.
  /// Helps when text is lighter than background.
  inversion,

  /// Grayscale + aggressive linear contrast stretch.
  /// Maps [min_lum, max_lum] → [0, 255]. The winning strategy
  /// for silver-on-silver cards confirmed by manual testing.
  grayscaleHiContrast,

  /// 3x3 high-pass filter to enhance digit edges.
  sharpen,
}

/// A service that applies various computer vision filters to [CameraImage] frames
/// to improve OCR accuracy for difficult cards (metallic, embossed, low-contrast).
class ImageProcessing {
  // ── Configuration ──────────────────────────────────────────────────

  /// Consecutive frames each strategy runs for, giving the controller's
  /// consensus mechanism enough identical-strategy frames to converge.
  /// Needs to be >= _requiredConsensus (3) with margin for OCR misses.
  static const int _framesPerStrategy = 8;

  /// Fraction of sampled pixels above [_glarePixelValue] that triggers
  /// glare detection.  0.15 = 15%.
  static const double _glareFraction = 0.15;

  /// Luminance value above which a pixel is considered "blown out".
  static const int _glarePixelValue = 240;

  /// Block size (pixels) for adaptive thresholding.
  static const int _adaptiveBlockSize = 16;

  /// Constant subtracted from the block mean in adaptive thresholding.
  static const int _adaptiveC = 8;

  /// Sample stride for glare detection — check every Nth pixel.
  static const int _glareSampleStride = 16;

  /// Radius for the local contrast integral-image box blur.
  static const int _localContrastRadius = 8;

  /// Amplification factor for local contrast enhancement.
  /// For embossed cards, a 2-value luminance gap × 16 = 32 — visible to MLKit.
  static const int _localContrastStrength = 16;

  // ── State ──────────────────────────────────────────────────────────

  int _frameCount = 0;

  /// The enhancement strategy currently being applied.
  EnhancementStrategy _currentStrategy = EnhancementStrategy.none;
  
  /// Returns the current [EnhancementStrategy] being used.
  EnhancementStrategy get currentStrategy => _currentStrategy;

  /// Whether excessive glare was detected on the most recent frame.
  /// The host UI can read this to prompt the user to tilt the card.
  bool glareDetected = false;

  // ── Strategy rotation ──────────────────────────────────────────────

  /// The rotation is heavily biased toward [grayscaleHiContrast] since
  /// that's the only strategy confirmed to work on embossed metallic cards.
  /// It alternates with [none] (for normal detection) and occasional
  /// other strategies as fallbacks.
  static const _rotation = <EnhancementStrategy>[
    EnhancementStrategy.none,
    EnhancementStrategy.grayscaleHiContrast,
    EnhancementStrategy.none,
    EnhancementStrategy.sharpen,
    EnhancementStrategy.none,
    EnhancementStrategy.grayscaleHiContrast,
    EnhancementStrategy.none,
    EnhancementStrategy.sobelEdge,
    EnhancementStrategy.none,
    EnhancementStrategy.grayscaleHiContrast,
    EnhancementStrategy.none,
    EnhancementStrategy.localContrast,
  ];

  /// Default constructor for [ImageProcessing].
  ImageProcessing();

  // ── Public API ─────────────────────────────────────────────────────

  /// Converts a [CameraImage] to an [InputImage] using the standard (no
  /// enhancement) path without modifying any internal state. Used for retry
  /// passes with an alternative rotation (e.g. card held upside down).
  InputImage? convertStandard(CameraImage image, int rotationDeg) => _standardConversion(image, rotationDeg);

  /// Resets the internal frame counter (e.g. when the scanner is reset).
  void reset() {
    _frameCount = 0;
    glareDetected = false;
  }

  /// Converts a [CameraImage] to an [InputImage] for MLKit, optionally
  /// applying image enhancements.
  ///
  /// When [enableEnhancement] is `false` this is equivalent to zero copying, 
  /// zero overhead conversion.
  Future<InputImage?> process(
    CameraImage image,
    int rotationDeg, {
    required bool enableEnhancement,
    Rect? roi,
  }) async {
    if (!enableEnhancement) {
      glareDetected = false;
      _currentStrategy = EnhancementStrategy.none;
      return _standardConversion(image, rotationDeg);
    }

    final strategyIndex = (_frameCount ~/ _framesPerStrategy) % _rotation.length;
    final strategy = _rotation[strategyIndex];
    _currentStrategy = strategy;
    _frameCount++;

    if (strategy == EnhancementStrategy.none) {
      glareDetected = false;
      return _standardConversion(image, rotationDeg);
    }

    return _enhancedConversion(image, rotationDeg, strategy, roi: roi);
  }

  // ── Conversion paths ───────────────────────────────────────────────

  /// Fast path — no byte copying, no processing.
  InputImage? _standardConversion(CameraImage image, int rotationDeg) {
    if (image.planes.length != 1) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(rotationDeg);
    if (rotation == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Slow path — copies bytes, applies the selected strategy, then
  /// returns the modified buffer as an [InputImage].
  Future<InputImage?> _enhancedConversion(
    CameraImage image,
    int rotationDeg,
    EnhancementStrategy strategy, {
    Rect? roi,
  }) async {
    if (image.planes.length != 1) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(rotationDeg);
    if (rotation == null) return null;

    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final pixelCount = width * height;
    final isNv21 = Platform.isAndroid;

    // Work on a copy so we don't mutate the camera's buffer.
    final bytes = Uint8List.fromList(plane.bytes);

    // Glare check on unmodified bytes.
    if (_detectGlare(bytes, pixelCount, isNv21)) {
      glareDetected = true;
      return null; // Skip this frame entirely.
    }
    glareDetected = false;

    // Apply the selected strategy.
    switch (strategy) {
      case EnhancementStrategy.grayscaleHiContrast:
        _applyGrayscaleHiContrast(bytes, width, height, isNv21, roi: roi);
        break;
      case EnhancementStrategy.sharpen:
        _applySharpening(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.sobelEdge:
        _applySobelEdge(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.localContrast:
        _applyLocalContrast(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.histogramEqualization:
        _applyHistogramEqualization(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.binaryThreshold:
        _applyOtsuThreshold(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.adaptiveThreshold:
        _applyAdaptiveThreshold(bytes, width, height, isNv21);
        break;
      case EnhancementStrategy.inversion:
        _applyInversion(bytes, pixelCount, isNv21);
        break;
      case EnhancementStrategy.none:
        break;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
  // ── Grayscale + High Contrast ─────────────────────────────────────

  /// Percentile-based contrast stretch: finds the 2nd and 98th percentile
  /// luminance values and linearly maps that range to [0, 255].
  ///
  /// If [roi] is provided, the percentile range is calculated *only* from
  /// the card region, ensuring the 0-255 range is dedicated to the card
  /// surface, ignoring background table or hands.
  void _applyGrayscaleHiContrast(Uint8List bytes, int width, int height, bool isNv21, {Rect? roi}) {
    final pixelCount = width * height;

    // Build histogram.
    // If we have an ROI, we use ROI pixels for stats, but apply to full image.
    final histogram = _buildHistogram(bytes, width, height, isNv21, roi: roi);

    // If ROI is used, the cumulative pixel count for percentiles is smaller.
    final effectivePixelCount = roi != null ? (roi.width * roi.height).toInt() : pixelCount;

    // Find 2nd and 98th percentile luminance values.
    final pLowTarget = (effectivePixelCount * 0.02).round();
    final pHighTarget = (effectivePixelCount * 0.98).round();

    int cumulative = 0;
    int pLow = 0;
    int pHigh = 255;
    bool foundLow = false;

    for (int i = 0; i < 256; i++) {
      cumulative += histogram[i];
      if (!foundLow && cumulative >= pLowTarget) {
        pLow = i;
        foundLow = true;
      }
      if (cumulative >= pHighTarget) {
        pHigh = i;
        break;
      }
    }

    final range = pHigh - pLow;
    if (range <= 0) return; // Uniform — nothing to stretch.

    // Build LUT: map [pLow..pHigh] → [0..255], clamp outliers.
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      lut[i] = ((i - pLow) * 255 ~/ range).clamp(0, 255);
    }

    // Apply globally.
    _applyLut(bytes, pixelCount, isNv21, lut);
  }

  /// 3x3 Sharpening kernel (high-pass filter).
  /// [ 0, -1,  0;
  ///  -1,  5, -1;
  ///   0, -1,  0 ]
  void _applySharpening(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;
    final lum = _extractLuminance(bytes, width, height, isNv21);
    final output = Uint8List(pixelCount);

    // Copy border pixels.
    _copyBorder(lum, output, width, height);

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final sum = 5 * lum[i] - lum[(y - 1) * width + x] - lum[(y + 1) * width + x] - lum[y * width + (x - 1)] - lum[y * width + (x + 1)];

        output[i] = sum.clamp(0, 255);
      }
    }

    // Write back.
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        bytes[i] = output[i];
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        final v = output[i];
        bytes[o] = v;
        bytes[o + 1] = v;
        bytes[o + 2] = v;
      }
    }
  }

  void _copyBorder(Uint8List src, Uint8List dst, int width, int height) {
    for (int x = 0; x < width; x++) {
      dst[x] = src[x];
      dst[(height - 1) * width + x] = src[(height - 1) * width + x];
    }
    for (int y = 0; y < height; y++) {
      dst[y * width] = src[y * width];
      dst[y * width + width - 1] = src[y * width + width - 1];
    }
  }

  // ── Glare Detection ────────────────────────────────────────────────

  /// Samples every [_glareSampleStride]th pixel and checks if more than
  /// [_glareFraction] are over-exposed.
  bool _detectGlare(Uint8List bytes, int pixelCount, bool isNv21) {
    int overexposed = 0;
    int sampled = 0;

    if (isNv21) {
      for (int i = 0; i < pixelCount; i += _glareSampleStride) {
        if (bytes[i] > _glarePixelValue) overexposed++;
        sampled++;
      }
    } else {
      // BGRA8888: compute luminance from RGB.
      for (int i = 0; i < pixelCount; i += _glareSampleStride) {
        final o = i * 4;
        final gray = _luminance(bytes[o + 2], bytes[o + 1], bytes[o]);
        if (gray > _glarePixelValue) overexposed++;
        sampled++;
      }
    }

    return sampled > 0 && overexposed / sampled > _glareFraction;
  }

  // ── Edge-Based Strategies (key for embossed cards) ─────────────────

  /// Sobel combo: 3×3 box-blur → Sobel → normalize → invert.
  ///
  /// Pre-blur removes metallic surface noise. Sobel detects gradient edges
  /// from embossing shadows. Normalization stretches even a max gradient of
  /// 3 to 255. Inversion produces dark-on-white output (what MLKit expects).
  void _applySobelEdge(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;

    // Step 1: Extract luminance.
    final lum = _extractLuminance(bytes, width, height, isNv21);

    // Step 2: Box-blur 3×3 to suppress metallic texture noise.
    final blurred = Uint8List(pixelCount);
    // Copy border pixels as-is.
    for (int i = 0; i < width; i++) {
      blurred[i] = lum[i];
      blurred[(height - 1) * width + i] = lum[(height - 1) * width + i];
    }
    for (int y = 0; y < height; y++) {
      blurred[y * width] = lum[y * width];
      blurred[y * width + width - 1] = lum[y * width + width - 1];
    }
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int sum = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            sum += lum[(y + dy) * width + (x + dx)];
          }
        }
        blurred[y * width + x] = sum ~/ 9;
      }
    }

    // Step 3: Sobel on blurred image, store magnitudes in a temp buffer.
    final edges = Uint8List(pixelCount); // defaults to 0
    int maxMag = 1; // track max for normalization (avoid div-by-zero).

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final i00 = (y - 1) * width + (x - 1);
        final i01 = (y - 1) * width + x;
        final i02 = (y - 1) * width + (x + 1);
        final i10 = y * width + (x - 1);
        final i12 = y * width + (x + 1);
        final i20 = (y + 1) * width + (x - 1);
        final i21 = (y + 1) * width + x;
        final i22 = (y + 1) * width + (x + 1);

        final gx = -blurred[i00] + blurred[i02] - 2 * blurred[i10] + 2 * blurred[i12] - blurred[i20] + blurred[i22];

        final gy = -blurred[i00] - 2 * blurred[i01] - blurred[i02] + blurred[i20] + 2 * blurred[i21] + blurred[i22];

        int mag = gx.abs() + gy.abs();
        if (mag > maxMag) maxMag = mag;
        edges[y * width + x] = mag.clamp(0, 255);
      }
    }

    // Step 4: Normalize + Invert.
    // Normalization stretches [0..maxMag] → [0..255].
    // Inversion makes edges dark on white background (MLKit-friendly).
    for (int i = 0; i < pixelCount; i++) {
      final normalized = edges[i] * 255 ~/ maxMag;
      final inverted = 255 - normalized.clamp(0, 255);
      if (isNv21) {
        bytes[i] = inverted;
      } else {
        final o = i * 4;
        bytes[o] = inverted;
        bytes[o + 1] = inverted;
        bytes[o + 2] = inverted;
      }
    }
  }

  /// Extracts luminance values from raw camera bytes into a new [Uint8List].
  Uint8List _extractLuminance(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;
    final lum = Uint8List(pixelCount);
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        lum[i] = bytes[i];
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        lum[i] = _luminance(bytes[o + 2], bytes[o + 1], bytes[o]);
      }
    }
    return lum;
  }

  /// Local contrast amplification using an integral image (summed area table)
  /// for O(1) per-pixel box-mean computation.
  ///
  /// For each pixel: `enhanced = 128 + (original − localMean) × strength`
  ///
  /// A 2-3 luminance difference from embossing gets amplified to 32-48,
  /// making it clearly visible to MLKit.
  void _applyLocalContrast(Uint8List bytes, int width, int height, bool isNv21) {
    // Extract luminance.
    final lum = _extractLuminance(bytes, width, height, isNv21);

    // Build integral image for O(1) box-mean lookups.
    // integral[(y+1) * stride + (x+1)] = sum of lum[0..y][0..x]
    final stride = width + 1;
    final integral = Int32List(stride * (height + 1));
    for (int y = 1; y <= height; y++) {
      int rowSum = 0;
      for (int x = 1; x <= width; x++) {
        rowSum += lum[(y - 1) * width + (x - 1)];
        integral[y * stride + x] = integral[(y - 1) * stride + x] + rowSum;
      }
    }

    // For each pixel, compute local mean and amplify the difference.
    const r = _localContrastRadius;
    const s = _localContrastStrength;

    for (int y = 0; y < height; y++) {
      final y0 = (y - r).clamp(0, height);
      final y1 = (y + r + 1).clamp(0, height);
      for (int x = 0; x < width; x++) {
        final x0 = (x - r).clamp(0, width);
        final x1 = (x + r + 1).clamp(0, width);

        final sum = integral[y1 * stride + x1] - integral[y0 * stride + x1] - integral[y1 * stride + x0] + integral[y0 * stride + x0];
        final area = (y1 - y0) * (x1 - x0);
        final mean = sum ~/ area;

        final original = lum[y * width + x];
        int enhanced = 128 + (original - mean) * s;
        enhanced = enhanced.clamp(0, 255);

        final idx = y * width + x;
        if (isNv21) {
          bytes[idx] = enhanced;
        } else {
          final o = idx * 4;
          bytes[o] = enhanced;
          bytes[o + 1] = enhanced;
          bytes[o + 2] = enhanced;
        }
      }
    }
  }

  // ── Luminance-Based Strategies ──────────────────────────────────────

  /// Global histogram equalization — stretches luminance to use full 0-255 range.
  void _applyHistogramEqualization(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;
    final histogram = _buildHistogram(bytes, width, height, isNv21);

    // Compute CDF.
    final cdf = List<int>.filled(256, 0);
    cdf[0] = histogram[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + histogram[i];
    }

    // Find first non-zero CDF value.
    int cdfMin = 0;
    for (int i = 0; i < 256; i++) {
      if (cdf[i] > 0) {
        cdfMin = cdf[i];
        break;
      }
    }

    // Build lookup table.
    final lut = Uint8List(256);
    final denominator = pixelCount - cdfMin;
    if (denominator > 0) {
      for (int i = 0; i < 256; i++) {
        lut[i] = ((cdf[i] - cdfMin) * 255 ~/ denominator).clamp(0, 255);
      }
    }

    // Apply LUT.
    _applyLut(bytes, pixelCount, isNv21, lut);
  }

  /// Binary threshold using Otsu's method for automatic threshold selection.
  void _applyOtsuThreshold(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;
    final histogram = _buildHistogram(bytes, width, height, isNv21);

    // Otsu's method: find the threshold that maximises inter-class variance.
    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }

    double sumBack = 0;
    int countBack = 0;
    double maxVariance = 0;
    int bestThreshold = 128;

    for (int i = 0; i < 256; i++) {
      countBack += histogram[i];
      if (countBack == 0) continue;

      int countFore = pixelCount - countBack;
      if (countFore == 0) break;

      sumBack += i * histogram[i];
      final meanBack = sumBack / countBack;
      final meanFore = (sumAll - sumBack) / countFore;
      final varianceBetween = countBack.toDouble() * countFore.toDouble() * (meanBack - meanFore) * (meanBack - meanFore);

      if (varianceBetween > maxVariance) {
        maxVariance = varianceBetween;
        bestThreshold = i;
      }
    }

    // Apply binary threshold with computed value.
    _applyBinaryThreshold(bytes, pixelCount, isNv21, bestThreshold);
  }

  /// Block-based adaptive threshold — approximates CLAHE for local contrast.
  void _applyAdaptiveThreshold(Uint8List bytes, int width, int height, bool isNv21) {
    final pixelCount = width * height;

    // Extract luminance into a working array.
    final lum = Uint8List(pixelCount);
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        lum[i] = bytes[i];
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        lum[i] = _luminance(bytes[o + 2], bytes[o + 1], bytes[o]);
      }
    }

    // Process each block.
    for (int by = 0; by < height; by += _adaptiveBlockSize) {
      for (int bx = 0; bx < width; bx += _adaptiveBlockSize) {
        final bh = (by + _adaptiveBlockSize < height) ? _adaptiveBlockSize : height - by;
        final bw = (bx + _adaptiveBlockSize < width) ? _adaptiveBlockSize : width - bx;

        // Compute block mean.
        int sum = 0;
        for (int y = by; y < by + bh; y++) {
          for (int x = bx; x < bx + bw; x++) {
            sum += lum[y * width + x];
          }
        }
        final threshold = sum ~/ (bh * bw) - _adaptiveC;

        // Apply threshold to this block.
        for (int y = by; y < by + bh; y++) {
          for (int x = bx; x < bx + bw; x++) {
            final idx = y * width + x;
            final val = lum[idx] > threshold ? 255 : 0;
            if (isNv21) {
              bytes[idx] = val;
            } else {
              final o = idx * 4;
              bytes[o] = val;
              bytes[o + 1] = val;
              bytes[o + 2] = val;
            }
          }
        }
      }
    }
  }

  /// Simple luminance inversion.
  void _applyInversion(Uint8List bytes, int pixelCount, bool isNv21) {
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        bytes[i] = 255 - bytes[i];
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        bytes[o] = 255 - bytes[o];
        bytes[o + 1] = 255 - bytes[o + 1];
        bytes[o + 2] = 255 - bytes[o + 2];
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Builds a 256-bin luminance histogram from the raw bytes.
  /// If [roi] is provided, only pixels within the ROI are sampled.
  List<int> _buildHistogram(Uint8List bytes, int width, int height, bool isNv21, {Rect? roi}) {
    final histogram = List<int>.filled(256, 0);

    if (roi != null) {
      final left = roi.left.toInt().clamp(0, width - 1);
      final top = roi.top.toInt().clamp(0, height - 1);
      final right = roi.right.toInt().clamp(0, width - 1);
      final bottom = roi.bottom.toInt().clamp(0, height - 1);

      for (int y = top; y <= bottom; y++) {
        for (int x = left; x <= right; x++) {
          final idx = y * width + x;
          if (isNv21) {
            histogram[bytes[idx]]++;
          } else {
            final o = idx * 4;
            histogram[_luminance(bytes[o + 2], bytes[o + 1], bytes[o])]++;
          }
        }
      }
    } else {
      final pixelCount = width * height;
      if (isNv21) {
        for (int i = 0; i < pixelCount; i++) {
          histogram[bytes[i]]++;
        }
      } else {
        for (int i = 0; i < pixelCount; i++) {
          final o = i * 4;
          histogram[_luminance(bytes[o + 2], bytes[o + 1], bytes[o])]++;
        }
      }
    }
    return histogram;
  }

  /// Applies a 256-entry lookup table to every pixel.
  void _applyLut(Uint8List bytes, int pixelCount, bool isNv21, Uint8List lut) {
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        bytes[i] = lut[bytes[i]];
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        final gray = _luminance(bytes[o + 2], bytes[o + 1], bytes[o]);
        final eq = lut[gray];
        bytes[o] = eq;
        bytes[o + 1] = eq;
        bytes[o + 2] = eq;
      }
    }
  }

  /// Applies a fixed binary threshold to every pixel.
  void _applyBinaryThreshold(Uint8List bytes, int pixelCount, bool isNv21, int threshold) {
    if (isNv21) {
      for (int i = 0; i < pixelCount; i++) {
        bytes[i] = bytes[i] > threshold ? 255 : 0;
      }
    } else {
      for (int i = 0; i < pixelCount; i++) {
        final o = i * 4;
        final gray = _luminance(bytes[o + 2], bytes[o + 1], bytes[o]);
        final val = gray > threshold ? 255 : 0;
        bytes[o] = val;
        bytes[o + 1] = val;
        bytes[o + 2] = val;
      }
    }
  }

  /// Standard BT.601 luminance from RGB.
  static int _luminance(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
}
