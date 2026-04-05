/// A utility class containing the core logic for extracting card details from OCR text.
class ZapScanOCR {
  // Definite digit-like characters (high confidence)
  static const _definiteDigits = <String, String>{
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
    'K': '6',
    'Z': '2',
    'a': '8',
  };

  // Speculative digit-like characters (noisy: embossed or low-contrast)
  static const _speculativeDigits = <String, String>{
    'H': '4',
    'W': '4',
    'M': '4',
    'N': '4',
    'A': '4',
    'R': '2',
    'e': '2',
    'E': '8',
    'T': '7',
    'U': '0',
  };

  static const _ambiguous = <String, List<String>>{
    'L': ['6'],
    'B': ['8', '6'],
  };

  /// Builds a regex pattern of all possible digit-like characters for the current mapping level.
  static String _getDigitRegex(bool includeSpeculative) {
    final chars = StringBuffer('0-9');
    chars.write(_definiteDigits.keys.join());
    chars.write(_ambiguous.keys.join());
    if (includeSpeculative) {
      chars.write(_speculativeDigits.keys.join());
    }
    return '[$chars]';
  }

  /// Parses the [rawText] to find a valid 13- to 16-digit credit card number sequence.
  static List<Set<String>>? findCardSlots(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Pass 1: Strict Matching (Definite mappings only)
    var result = _findInPass(lines, includeSpeculative: false);
    if (result != null) return result;

    // Pass 2: Speculative Matching (Include noisy mappings as fallback)
    return _findInPass(lines, includeSpeculative: true);
  }

  /// Helper to perform a full scanning pass over all layouts with a given mapping level.
  static List<Set<String>>? _findInPass(List<String> lines, {required bool includeSpeculative}) {
    final candidates = <List<_Slot>>[];

    // 1. Horizontal
    for (final line in lines) {
      final res = _matchPattern(line, includeSpeculative);
      if (res != null) candidates.add(res);

      final len = _matchLenient(line, includeSpeculative);
      if (len != null) candidates.add(len);
    }

    // 2. Grid (2 × 2)
    for (var i = 0; i < lines.length - 1; i++) {
      final s1 = _toSlots(lines[i], includeSpeculative: includeSpeculative);
      final s2 = _toSlots(lines[i + 1], includeSpeculative: includeSpeculative);
      // Grid cards often have 8 digits per line (4-4), but OCR might drop characters.
      // We allow 7-9 per line to be flexible.
      if (s1.length >= 7 && s1.length <= 9 && s2.length >= 7 && s2.length <= 9) {
        final res = _searchByLength([...s1, ...s2]);
        if (res != null) candidates.add(res);
      }
    }

    // 3. Vertical
    final quads = <List<_Slot>>[];
    for (final line in lines) {
      final slots = _toSlots(line, includeSpeculative: includeSpeculative);
      if (slots.length >= 4 && slots.length <= 6) {
        // Vertical blocks (often 4 digits)
        quads.add(slots.sublist(0, 4));
      }
    }
    if (quads.length >= 4) {
      final res = _searchVertical(quads);
      if (res != null) candidates.add(res);
    }

    if (candidates.isEmpty) return null;

    // Selection Algorithm:
    // Confidence Score = (Count of Real Digits 0-9) - (Count of Mapped Letters)
    int getScore(List<_Slot> cand) {
      return cand.fold(0, (sum, s) => sum + (s.isOriginalDigit ? 1 : -1));
    }

    List<_Slot>? bestCand;
    int bestScore = -999;
    bool bestPassesLuhn = false;

    for (final cand in candidates) {
      final num = cand.map((s) => s.digits.first).join();
      final score = getScore(cand);
      final luhn = checkLuhn(num);

      // Priority 1: Luhn-valid AND higher score
      // Priority 2: Higher score (probabilistic fallback)
      if (luhn && !bestPassesLuhn) {
        // First Luhn valid one we find, set it as best
        bestPassesLuhn = true;
        bestScore = score;
        bestCand = cand;
      } else if (luhn == bestPassesLuhn) {
        // Both pass Luhn or both fail Luhn, pick highest score
        if (score > bestScore) {
          bestScore = score;
          bestCand = cand;
        }
      }
    }

    return bestCand?.map((s) => s.digits.toSet()).toList();
  }

  /// Convert a text line into a list of slots.
  static List<_Slot> _toSlots(String line, {required bool includeSpeculative}) {
    final slots = <_Slot>[];
    for (final ch in line.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        slots.add(_Slot([ch], true));
      } else if (_ambiguous.containsKey(ch)) {
        slots.add(_Slot(List<String>.from(_ambiguous[ch]!), false));
      } else if (_definiteDigits.containsKey(ch)) {
        slots.add(_Slot([_definiteDigits[ch]!], false));
      } else if (includeSpeculative && _speculativeDigits.containsKey(ch)) {
        slots.add(_Slot([_speculativeDigits[ch]!], false));
      }
    }
    return slots;
  }

  static List<_Slot>? _searchByLength(List<_Slot> slots) {
    // Grid healing: allow 13-16 digits if it looks like a card
    for (final len in [16, 15, 14, 13]) {
      if (slots.length < len) continue;
      final sub = slots.sublist(0, len);
      if (_isValidPrefix(sub.map((s) => s.toSet()).toList())) return sub;
    }
    return null;
  }

  static List<_Slot>? _searchVertical(List<List<_Slot>> quads) {
    final n = quads.length;
    for (var a = 0; a < n - 3; a++) {
      for (var b = a + 1; b < n - 2; b++) {
        for (var c = b + 1; c < n - 1; c++) {
          for (var d = c + 1; d < n; d++) {
            final combined = [...quads[a], ...quads[b], ...quads[c], ...quads[d]];
            if (_isValidPrefix(combined.map((s) => s.toSet()).toList())) return combined;
          }
        }
      }
    }
    return null;
  }

  /// Network-centric validation.
  static bool _isValidPrefix(List<Set<String>> slots) {
    if (slots.length < 13 || slots.length > 16) return false;
    final first = slots[0];
    final second = slots[1];

    // Visa (4)
    if (first.contains('4')) return true;
    // MC (5, 2)
    if (first.contains('5') || first.contains('2')) return true;
    // Amex (34, 37) / Diners (30, 36, 38, 39)
    if (first.contains('3')) {
      if (slots.length == 15) return second.contains('4') || second.contains('7');
      if (slots.length == 14) return second.any((c) => ['0', '6', '8', '9'].contains(c));
      return true; // Probabilistic
    }
    // Discover/RuPay (6, 8)
    if (first.contains('6') || first.contains('8')) return true;

    return false;
  }

  /// Standard Luhn algorithm.
  static bool checkLuhn(String number) {
    if (number.length < 13) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = number.length - 1; i >= 0; i--) {
      int? n = int.tryParse(number[i]);
      if (n == null) return false;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
  }

  static List<_Slot>? _matchPattern(String line, bool includeSpeculative) {
    final d = _getDigitRegex(includeSpeculative);
    // Patterns with spaces
    final patterns = [
      RegExp('($d{4})\\s+($d{4})\\s+($d{4})\\s+($d{4})'), // 4-4-4-4
      RegExp('($d{4})\\s+($d{6})\\s+($d{5})'), // 4-6-5
      RegExp('($d{4})\\s+($d{6})\\s+($d{4})'), // 4-6-4
    ];

    for (final p in patterns) {
      final m = p.firstMatch(line);
      if (m != null) {
        final raw = List.generate(m.groupCount, (i) => m.group(i + 1)!).join();
        final res = _toSlots(raw, includeSpeculative: includeSpeculative);
        if (_isValidPrefix(res.map((s) => s.toSet()).toList())) return res;
      }
    }
    return null;
  }

  static List<_Slot>? _matchLenient(String line, bool includeSpeculative) {
    final slots = _toSlots(line, includeSpeculative: includeSpeculative);
    for (final len in [16, 15, 14, 13]) {
      if (slots.length < len) continue;
      for (var i = 0; i <= slots.length - len; i++) {
        final sub = slots.sublist(i, i + len);
        if (_isValidPrefix(sub.map((s) => s.toSet()).toList())) return sub;
      }
    }
    return null;
  }

  /// Find expiration date.
  static String? findExpiryDate(String rawText) {
    final expRegex = RegExp(r'\b(0[1-9]|1[0-2])\s*([/\-\|\\lLIi17]|\s)\s*([0-9]{2,4})\b');
    final lines = rawText.split('\n');
    for (final line in lines) {
      final matches = expRegex.allMatches(line);
      for (final match in matches) {
        final monthStr = match.group(1);
        final yearStr = match.group(3);
        if (monthStr != null && yearStr != null) {
          int? year = int.tryParse(yearStr);
          if (year != null) {
            if (yearStr.length == 2 && year >= 24 && year <= 49) return '$monthStr/$yearStr';
            if (yearStr.length == 4 && year >= 2024 && year <= 2049) return '$monthStr/${yearStr.substring(2)}';
          }
        }
      }
    }
    return null;
  }

  /// Find CVV.
  static String? findCvv(String rawText, String? knownCardNumber) {
    final cvvRegex = RegExp(r'\b([0-9]{3,4})\b');
    final lines = rawText.split('\n');
    for (final line in lines) {
      final matches = cvvRegex.allMatches(line);
      for (final match in matches) {
        final candidate = match.group(1);
        if (candidate != null) {
          if (knownCardNumber != null && knownCardNumber.contains(candidate)) continue;
          final cInt = int.tryParse(candidate);
          if (candidate.length == 4 && cInt != null && cInt >= 2000 && cInt <= 2050) continue;
          return candidate;
        }
      }
    }
    return null;
  }
}

class _Slot {
  final List<String> digits;
  final bool isOriginalDigit;
  _Slot(this.digits, this.isOriginalDigit);
  Set<String> toSet() => digits.toSet();
}
