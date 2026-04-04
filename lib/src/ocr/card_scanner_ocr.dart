/// OCR-to-card-number logic
///
/// 3 different card layouts:
///   Horizontal  – "4029 8600 0354 8548"            (all digits on same line)
///   Grid (2×2)  – "b529 b000 / 0000 L079"          (2 lines × 8 digits)
///   Vertical    – "4029 / 8L00 / 0354 / 8548"      (4 lines × 4 digits, gaps allowed)
class CardScannerOCR {
  // Raw OCR gives incorrect characters while trying to find correct set of numbers.
  // Following are some examples picked from real samples:
  static const _fixed = <String, String>{
    'b': '6',
    'l': '1',
    'I': '1',
    'i': '1',
    'O': '0',
    'o': '0',
    'D': '0',
    'S': '5',
    'Y': '4',
    'y': '4',
    'G': '6',
    'Z': '2',
    'a': '8',
  };

  static const _ambiguous = <String, List<String>>{
    'L': ['6'],
    'B': ['8', '6'],
  };

  /// Returns a valid sequence of 14- to 16-digit possibility-sets, or null if nothing found.
  static List<Set<String>>? findCardSlots(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Horizontal
    // XXXX XXXX XXXX XXXX
    // XXXX XXXXXX XXXX
    // XXXX XXXXXX XXXXX
    for (final line in lines) {
      final result = _matchPattern(line);
      if (result != null) return result;
    }

    // Grid (2 × 2)
    // Two rows each containing 7–9 digit slots.
    for (var i = 0; i < lines.length - 1; i++) {
      final s1 = _toSlots(lines[i]);
      final s2 = _toSlots(lines[i + 1]);
      if (s1.length >= 7 &&
          s1.length <= 9 &&
          s2.length >= 7 &&
          s2.length <= 9) {
        final result = _searchByLength([...s1, ...s2]);
        if (result != null) return result;
      }
    }

    // Vertical
    // Treat each line as a potential 4-digit chunk. To handle internal spaces
    // (e.g., "315 6|") and drop punctuation (e.g., "|2700|"), we strip all
    // non-alphanumeric characters first before checking density.
    final quads = <List<List<String>>>[];

    for (final line in lines) {
      final clean = line.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (clean.isEmpty) continue;

      final slots = _toSlots(clean);
      if (clean.length > slots.length + 1) continue;

      if (slots.length == 4) {
        quads.add(slots);
      } else if (slots.length == 5) {
        final firstIsOne = slots.first.contains('1');
        final lastIsOne = slots.last.contains('1');
        if (lastIsOne && !firstIsOne) {
          quads.add(slots.sublist(
              0, 4)); // strip trailing bar, e.g. "12341" -> "1234"
        } else if (firstIsOne && !lastIsOne) {
          quads.add(
              slots.sublist(1)); // strip leading bar, e.g. "11234" -> "1234"
        }
      } else if (slots.length == 6) {
        if (slots.first.contains('1') && slots.last.contains('1')) {
          quads.add(
              slots.sublist(1, 5)); // strip both bars, e.g. "112341" -> "1234"
        }
      }
    }
    if (quads.length >= 4) {
      final result = _searchVertical(quads);
      if (result != null) return result;
    }

    return null;
  }

  /// Convert a text line into a list of "slots". Each slot is the list of
  /// possible digit characters for that position.
  static List<List<String>> _toSlots(String line) {
    final slots = <List<String>>[];
    for (final ch in line.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        // '0'–'9': unambiguous digit
        slots.add([ch]);
      } else if (_ambiguous.containsKey(ch)) {
        slots.add(List<String>.from(_ambiguous[ch]!));
      } else if (_fixed.containsKey(ch)) {
        slots.add([_fixed[ch]!]);
      }
      // Anything else is noise — skip (J, punctuation, spaces, etc.)
    }
    return slots;
  }

  static List<Set<String>>? _searchByLength(List<List<String>> slots) {
    for (final len in [16, 15, 14]) {
      if (slots.length < len) continue;
      final result = slots.sublist(0, len).map((s) => s.toSet()).toList();
      if (_isValidPrefix(result)) return result;
    }
    return null;
  }

  static List<Set<String>>? _searchVertical(List<List<List<String>>> quads) {
    final n = quads.length;
    for (var a = 0; a < n - 3; a++) {
      for (var b = a + 1; b < n - 2; b++) {
        for (var c = b + 1; c < n - 1; c++) {
          for (var d = c + 1; d < n; d++) {
            final combined = [
              ...quads[a],
              ...quads[b],
              ...quads[c],
              ...quads[d]
            ];
            final result = combined.map((s) => s.toSet()).toList();
            if (_isValidPrefix(result)) return result;
          }
        }
      }
    }
    return null;
  }

  /// Network-length validation. A 15-digit card claiming to be Visa
  /// (starting with 4) is actually just a 16-digit card that OCR dropped a digit from.
  static bool _isValidPrefix(List<Set<String>> slots) {
    if (slots.length < 14 || slots.length > 16) return false;

    final firstOpt = slots[0];
    final secondOpt = slots[1];

    if (slots.length == 15) {
      // Amex: 34, 37
      if (!firstOpt.contains('3')) return false;
      if (!secondOpt.contains('4') && !secondOpt.contains('7')) return false;
      return true;
    }

    if (slots.length == 14) {
      // Diners Club: 30, 36, 38, 39
      if (!firstOpt.contains('3')) return false;
      if (!secondOpt.any((c) => ['0', '6', '8', '9'].contains(c))) return false;
      return true;
    }

    if (slots.length == 16) {
      // Visa (4), MC (5, 2), RuPay/Discover (6, 8), JCB (35)
      return firstOpt.any((c) => ['2', '3', '4', '5', '6', '8'].contains(c));
    }

    return false;
  }

  // All characters that could be a digit after substitution.
  // Must stay in sync with _fixed and _ambiguous keys.
  static const _dl = r'[0-9bBLlIiOoDSGZa]';

  /// Match known card number spacing patterns explicitly.
  /// Anchoring to spaces prevents digit-like chars in surrounding text
  /// (e.g. I/S from "VISA") from shifting the extraction window.
  static List<Set<String>>? _matchPattern(String line) {
    const d = _dl;
    // 4-4-4-4  (16 digits: Visa / MC / RuPay …)
    var m = RegExp('($d{4})\\s+($d{4})\\s+($d{4})\\s+($d{4})').firstMatch(line);
    if (m != null) {
      final resRaw = '${m[1]}${m[2]}${m[3]}${m[4]}';
      final res =
          resRaw.split('').map((ch) => _toSlots(ch).first.toSet()).toList();
      if (_isValidPrefix(res)) return res;
    }
    // 4-6-5    (15 digits: Amex)
    m = RegExp('($d{4})\\s+($d{6})\\s+($d{5})').firstMatch(line);
    if (m != null) {
      final resRaw = '${m[1]}${m[2]}${m[3]}';
      final res =
          resRaw.split('').map((ch) => _toSlots(ch).first.toSet()).toList();
      if (_isValidPrefix(res)) return res;
    }
    // 4-6-4    (14 digits: Diners Club)
    m = RegExp('($d{4})\\s+($d{6})\\s+($d{4})').firstMatch(line);
    if (m != null) {
      final resRaw = '${m[1]}${m[2]}${m[3]}';
      final res =
          resRaw.split('').map((ch) => _toSlots(ch).first.toSet()).toList();
      if (_isValidPrefix(res)) return res;
    }
    return null;
  }

  /// Attempts to find an expiration date in the raw text.
  /// Looks for patterns like MM/YY, MM\YY, MM|YY, MM-YY, MM/YYYY, etc.
  /// Also handles common OCR mistakes like `l` or `1` or `7` instead of `/` (e.g., 04126 -> 04/26).
  static String? findExpiryDate(String rawText) {
    // We clean the text to just numbers and likely separators.
    final cleanText = rawText.replaceAll(RegExp(r'[^0-9a-zA-Z\n/\\\-\|\s]'), '');
    final lines = cleanText.split('\n');

    // M: 01-12
    // Sep: / \ - |  (allow space around it, or 'l', '1', '7' as common mistakes)
    // Y: 20-40 (for YY) or 2020-2040 (for YYYY)
    
    // Pattern looking for 01-12 followed by a separator and 2 or 4 digits.
    // It captures month in group 1, year in group 2.
    // Separator could be non-alphanumeric, or a space, or common misreads like 'L', 'l', '1', '7', 'I', 'i'
    final expRegex = RegExp(r'\b(0[1-9]|1[0-2])\s*([/\-\|\\lLIi17]|\s)\s*([0-9]{2,4})\b');

    for (final line in lines) {
      final matches = expRegex.allMatches(line);
      for (final match in matches) {
        final monthStr = match.group(1);
        final yearStr = match.group(3);

        if (monthStr != null && yearStr != null) {
          int? year = int.tryParse(yearStr);
          if (year != null) {
            // Validate year constraints
            if (yearStr.length == 2 && year >= 24 && year <= 49) { // 2024 to 2049
              return '$monthStr/$yearStr';
            } else if (yearStr.length == 4 && year >= 2024 && year <= 2049) {
              return '$monthStr/${yearStr.substring(2)}'; // Normalize to MM/YY
            }
          }
        }
      }
    }

    // Fallback: Extremely compact date like 1226 (MMYY) surrounded by spaces or boundaries
    // We only accept it if month is 01-12 and year is 24-49
    final compactRegex = RegExp(r'\b(0[1-9]|1[0-2])([2-4][0-9])\b');
    for (final line in lines) {
      final matches = compactRegex.allMatches(line);
      for (final match in matches) {
        final monthStr = match.group(1);
        final yearStr = match.group(2);
        if (monthStr != null && yearStr != null) {
          int? year = int.tryParse(yearStr);
          if (year != null && year >= 24 && year <= 49) {
            return '$monthStr/$yearStr';
          }
        }
      }
    }

    return null;
  }

  /// Attempts to find a CVV (3 or 4 digits). 
  /// Excludes chunks that are identical to segments of the known card number.
  static String? findCvv(String rawText, String? knownCardNumber) {
    final lines = rawText.split('\n');

    final cvvRegex = RegExp(r'\b([0-9]{3,4})\b');

    for (final line in lines) {
      // Sometimes CVV is prefixed with CVV, CVC, CID, etc.
      final matches = cvvRegex.allMatches(line);
      for (final match in matches) {
        final candidate = match.group(1);
        if (candidate != null) {
          // Rule out if it's part of the known card number (e.g. the first 4 digits of Visa, or Amex)
          // Or if it's the exact same as an expiry date's year (e.g., "2026")
          if (knownCardNumber != null && knownCardNumber.contains(candidate)) {
            continue;
          }

          // Rule out sizes > 4 (already handled by regex \b)
          // Look for keywords nearby in the same line? 
          // Usually just blindly returning a 3-4 digit string that passes rules is "best effort".
          // We can prioritize it if we see "CVV" or "CVC".
          final upperLine = line.toUpperCase();
          if (upperLine.contains('CVV') || upperLine.contains('CVC') || upperLine.contains('CID')) {
            return candidate; // High confidence
          }

          // If no keyword, but it's a 3 or 4 digit standalone, we might return it if we are desperate.
          // Because AMEX cards have 4 digits on the front as CID.
          // Let's just return the first valid 3-4 digit block that's untouched.
          // To reduce false positives, we might only accept 4 digits if AMEX, 3 digits otherwise?
          // Since it's best effort, we will just return it.
          if (candidate.length == 3 || candidate.length == 4) {
             // Exclude obvious years like 2024, 2025
             if (candidate.length == 4) {
                final cInt = int.tryParse(candidate);
                if (cInt != null && cInt >= 2000 && cInt <= 2050) {
                   continue; // likely a year
                }
             }
             return candidate;
          }
        }
      }
    }
    return null;
  }
}
