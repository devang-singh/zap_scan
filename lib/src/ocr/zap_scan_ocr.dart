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

  /// Extracts the card number robustly using layout-based chunk inference.
  static String? extractCardNumber(String rawText, {bool enableLuhn = false}) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Valid characters for a chunk
    final validChars = <String>{
      ...List.generate(10, (i) => i.toString()),
      ..._definiteDigits.keys,
      ..._speculativeDigits.keys,
      ..._ambiguous.keys,
      '|'
    };

    final rawChunks = <String>[];

    for (var line in lines) {
      // Extract possible chunks from the line
      // Split by spaces, or by 2 spaces?
      // Grid chunks often have lots of spaces.
      // We will look for sequences of valid characters.

      // Also try to heal spaced digits (e.g. "315 6|") but NOT break separate chunks "0541 8548"
      // If a line has exactly one space between valid blocks, it might be a single chunk spaced out,
      // but usually chunks are space-separated.

      final words = line.split(RegExp(r'\s+'));
      for (var word in words) {
        // clean word by removing leading/trailing characters NOT in validChars
        var cleanWord = word;
        while (cleanWord.isNotEmpty && !validChars.contains(cleanWord[0])) {
          cleanWord = cleanWord.substring(1);
        }
        while (cleanWord.isNotEmpty && !validChars.contains(cleanWord[cleanWord.length - 1])) {
          cleanWord = cleanWord.substring(0, cleanWord.length - 1);
        }

        // We consider chunks down to length 1. OCR sometimes spaces out a chunk e.g. "315 6|" -> "315" and "6|"
        if (cleanWord.length >= 1 && cleanWord.length <= 19) {
          // Ensure it's not a generic word mapped randomly.
          // A real chunk should be mostly digits or mapped chars.
          int origDigits = cleanWord.split('').where((c) => validChars.contains(c) && !['|', '[', ']', '{', '}'].contains(c)).length;

          // It needs at least 1 true digit, or it could be noise like "by" that maps exclusively to digits
          if (origDigits >= 1 || cleanWord.length > 13) {
            rawChunks.add(cleanWord);
          }
        }
      }
    }

    // Border Cleanup (Vertical Artifacts)
    final cleanedChunks = <String>[];
    final edgeArtifacts = {'|', '1', 'l', 'I', 'i'};
    final verticalEdgeEncodings = {'T', 'J', 't', 'j', '[', ']', '{', '}'};

    // Check if there are strong indicators of an enclosed vertical layout
    bool enclosedLayout = rawChunks.any((c) => c.contains('|') || c.contains('[') || c.contains(']'));

    for (var chunk in rawChunks) {
      var c = chunk;

      // Aggressive edge artifact stripping for enclosed layout matrices
      if (enclosedLayout) {
        while (c.isNotEmpty && (verticalEdgeEncodings.contains(c[0]) || c[0] == '|')) {
          c = c.substring(1);
        }
        while (c.isNotEmpty && (verticalEdgeEncodings.contains(c[c.length - 1]) || c[c.length - 1] == '|')) {
          c = c.substring(0, c.length - 1);
        }
      }

      // Standard length 5/6 chunk edge smoothing
      if (c.length == 5) {
        if (edgeArtifacts.contains(c[c.length - 1])) {
          c = c.substring(0, 4);
        } else if (edgeArtifacts.contains(c[0])) {
          c = c.substring(1);
        }
      } else if (c.length == 6) {
        if (edgeArtifacts.contains(c[0]) && edgeArtifacts.contains(c[c.length - 1])) {
          c = c.substring(1, 5);
        }
      }

      if (c.isNotEmpty) {
        cleanedChunks.add(c);
      }
    }

    // Map cleaned chunks into their equivalent numeric representations securely
    // Map cleaned chunks into their equivalent numeric representations securely
    final mappedChunks = <String>[];
    for (var chunk in cleanedChunks) {
      var mappedStr = '';
      int trueDigits = 0;
      bool hasUnmappable = false;

      for (int i = 0; i < chunk.length; i++) {
        var char = chunk[i];
        if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
          mappedStr += char;
          trueDigits++;
        } else if (_definiteDigits.containsKey(char)) {
          mappedStr += _definiteDigits[char]!;
        } else if (_ambiguous.containsKey(char)) {
          mappedStr += _ambiguous[char]!.first; // Camera uses greedy mapping for speed
        } else if (_speculativeDigits.containsKey(char)) {
          mappedStr += _speculativeDigits[char]!;
        } else {
          hasUnmappable = true; 
        }
      }
      
      // English Word Eraser: If the chunk contains ANY unmapped letter, it's just normal text.
      if (hasUnmappable) continue;
      
      // Coincidence Eraser: If it contains NO actual numbers and is tiny (e.g. 'by' -> '64'), drop it.
      if (trueDigits == 0 && mappedStr.length < 4) continue;

      if (mappedStr.isNotEmpty) {
          mappedChunks.add(mappedStr);
      }
    }

    final candidates = <String, int>{};

    void addCandidate(String str, List<int> chunkSizes) {
      if (str.length < 13 || str.length > 16) return;

      int score = 0;
      if (_isValidBIN(str)) score += 50;

      bool isPerfectLayout = false;
      if (chunkSizes.length == 4 && chunkSizes[0] == 4 && chunkSizes[1] == 4 && chunkSizes[2] == 4 && chunkSizes[3] == 4) {
        isPerfectLayout = true;
        score += 2000;
      } else if (chunkSizes.length == 3 && chunkSizes[0] == 4 && chunkSizes[1] == 6 && chunkSizes[2] == 5) {
        isPerfectLayout = true;
        score += 2000;
      }

      if (luhnCheck(str)) {
        score += enableLuhn ? 1000 : 100;
      }

      if (str.length == 16) score += 30; // Standard Visa/MC/Disc length
      if (str.length == 15 && (str.startsWith('34') || str.startsWith('37'))) score += 30; // Amex length

      if (!isPerfectLayout) {
        if (chunkSizes.length == 4 && str.length == 16) score += 40;
        if (chunkSizes.length == 3 && str.length == 15) score += 40;
      }

      candidates[str] = (candidates[str] ?? 0) + score;
    }

    // 1. Build candidates strictly from continuous contiguous chunk boundaries.
    for (int startIdx = 0; startIdx < mappedChunks.length; startIdx++) {
      var continuousStr = "";
      var currentSizes = <int>[];
      for (int endIdx = startIdx; endIdx < mappedChunks.length; endIdx++) {
        continuousStr += mappedChunks[endIdx];
        currentSizes.add(mappedChunks[endIdx].length);
        addCandidate(continuousStr, List.from(currentSizes));
        if (continuousStr.length > 16) break; // Overshoot bail
      }
    }

    // 2. Fallback search (fused strings)
    for (var chunk in mappedChunks) {
      if (chunk.length >= 13) {
        for (final len in [16, 15, 14, 13]) {
          if (chunk.length < len) continue;
          for (var i = 0; i <= chunk.length - len; i++) {
            final sub = chunk.substring(i, i + len);
            addCandidate(sub, [sub.length]);
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    var validCandidates = candidates.entries.where((e) {
      if (enableLuhn) return luhnCheck(e.key);
      return true;
    }).toList();

    if (validCandidates.isEmpty) return null;

    validCandidates.sort((a, b) => b.value.compareTo(a.value));
    return validCandidates.first.key;
  }

  /// Extracts the card number exhaustively via deep Cartesian combinations.
  /// Strictly used for static gallery/image uploads where frame consensus is unavailable.
  static String? extractCardNumberFromUpload(String rawText, {bool enableLuhn = false}) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final validChars = <String>{
      ...List.generate(10, (i) => i.toString()),
      ..._definiteDigits.keys,
      ..._speculativeDigits.keys,
      ..._ambiguous.keys,
      '|',
      '[',
      ']',
      '{',
      '}'
    };

    final rawChunks = <String>[];
    for (var line in lines) {
      final words = line.split(RegExp(r'\s+'));
      for (var word in words) {
        var cleanWord = word;
        while (cleanWord.isNotEmpty && !validChars.contains(cleanWord[0])) {
          cleanWord = cleanWord.substring(1);
        }
        while (cleanWord.isNotEmpty && !validChars.contains(cleanWord[cleanWord.length - 1])) {
          cleanWord = cleanWord.substring(0, cleanWord.length - 1);
        }

        if (cleanWord.length >= 1 && cleanWord.length <= 19) {
          int origDigits = cleanWord.split('').where((c) => validChars.contains(c) && !['|', '[', ']', '{', '}'].contains(c)).length;
          if (origDigits >= 1 || cleanWord.length > 13) {
            rawChunks.add(cleanWord);
          }
        }
      }
    }

    final cleanedChunks = <String>[];
    final edgeArtifacts = {'|', '1', 'l', 'I', 'i'};
    final verticalEdgeEncodings = {'T', 'J', 't', 'j', '[', ']', '{', '}'};

    bool enclosedLayout = rawChunks.any((c) => c.contains('|') || c.contains('[') || c.contains(']'));

    for (var chunk in rawChunks) {
      var c = chunk;
      if (enclosedLayout) {
        while (c.isNotEmpty && (verticalEdgeEncodings.contains(c[0]) || c[0] == '|')) {
          c = c.substring(1);
        }
        while (c.isNotEmpty && (verticalEdgeEncodings.contains(c[c.length - 1]) || c[c.length - 1] == '|')) {
          c = c.substring(0, c.length - 1);
        }
      }
      if (c.length == 5) {
        if (edgeArtifacts.contains(c[c.length - 1])) {
          c = c.substring(0, 4);
        } else if (edgeArtifacts.contains(c[0])) {
          c = c.substring(1);
        }
      } else if (c.length == 6) {
        if (edgeArtifacts.contains(c[0]) && edgeArtifacts.contains(c[c.length - 1])) {
          c = c.substring(1, 5);
        }
      }
      if (c.isNotEmpty) cleanedChunks.add(c);
    }

    // MAP CHUNKS VIA CARTESIAN DESTRUCTOR
    List<List<String>> mappedPermutations = [];

    for (var chunk in cleanedChunks) {
      List<String> currentPerms = [''];
      int trueDigits = 0;
      bool hasUnmappable = false;

      for (int i = 0; i < chunk.length; i++) {
        var char = chunk[i];
        List<String> nextPerms = [];
        List<String> possibleValues = [];

        if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
          possibleValues.add(char);
          trueDigits++;
        } else if (_definiteDigits.containsKey(char)) {
          possibleValues.add(_definiteDigits[char]!);
        } else if (_ambiguous.containsKey(char)) {
          possibleValues.addAll(_ambiguous[char]!); // Fork dimensions for B, L, etc.
        } else if (_speculativeDigits.containsKey(char)) {
          possibleValues.add(_speculativeDigits[char]!);
        } else {
          hasUnmappable = true;
        }

        for (var perm in currentPerms) {
          for (var val in possibleValues) {
            nextPerms.add(perm + val);
          }
        }
        currentPerms = nextPerms; // Permutate forward!
      }
      
      if (hasUnmappable) continue;
      if (trueDigits == 0 && chunk.length < 4) continue;
      
      // Only retain chunks that actually produced digits
      final finals = currentPerms.where((p) => p.isNotEmpty).toList();
      if (finals.isNotEmpty) mappedPermutations.add(finals);
    }

    final candidates = <String, int>{};

    void evalCandidate(String str, List<int> chunkSizes) {
      if (str.length < 13 || str.length > 16) return;
      if (!_isValidBIN(str) && !enableLuhn) return; // Strict gating for single frames

      int score = 0;
      if (_isValidBIN(str)) score += 50;

      bool isPerfectLayout = false;
      if (chunkSizes.length == 4 && chunkSizes[0] == 4 && chunkSizes[1] == 4 && chunkSizes[2] == 4 && chunkSizes[3] == 4) {
        isPerfectLayout = true;
        score += 2000; // Found standard layout! Massive points.
      } else if (chunkSizes.length == 3 && chunkSizes[0] == 4 && chunkSizes[1] == 6 && chunkSizes[2] == 5) {
        isPerfectLayout = true;
        score += 2000;
      }

      if (luhnCheck(str)) {
        score += enableLuhn ? 1000 : 1500; // Luhn is incredibly dominant on single frames
      }

      if (str.length == 16) score += 30;
      if (str.length == 15 && (str.startsWith('34') || str.startsWith('37'))) score += 30;

      if (!isPerfectLayout) {
        if (chunkSizes.length == 4 && str.length == 16) score += 40;
        if (chunkSizes.length == 3 && str.length == 15) score += 40;
      }
      candidates[str] = (candidates[str] ?? 0) + score;
    }

    for (int startIdx = 0; startIdx < mappedPermutations.length; startIdx++) {
      // A record of strings mapped to their physical chunk layouts.
      // E.g [ ("4025", [4]) ]
      List<MapEntry<String, List<int>>> structuralCombos = [MapEntry("", [])];

      for (int endIdx = startIdx; endIdx < mappedPermutations.length; endIdx++) {
        List<MapEntry<String, List<int>>> nextCombos = [];
        final segmentOptions = mappedPermutations[endIdx];

        for (var existing in structuralCombos) {
          // Protect against explosion (cards are never 20 digits long)
          if (existing.key.length > 16) continue;

          for (var opt in segmentOptions) {
            final newList = List<int>.from(existing.value)..add(opt.length);
            nextCombos.add(MapEntry(existing.key + opt, newList));
          }
        }
        structuralCombos = nextCombos;

        for (var seq in structuralCombos) {
          evalCandidate(seq.key, seq.value);
        }
      }
    }

    // Fallback isolated chunk scanner (identical to camera flow)
    for (var options in mappedPermutations) {
      for (var chunk in options) {
        if (chunk.length >= 13) {
          for (final len in [16, 15, 14, 13]) {
            if (chunk.length < len) continue;
            for (var i = 0; i <= chunk.length - len; i++) {
              final sub = chunk.substring(i, i + len);
              evalCandidate(sub, [sub.length]);
            }
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    var validCandidates = candidates.entries.where((e) {
      if (enableLuhn) return luhnCheck(e.key);
      return true;
    }).toList();

    if (validCandidates.isEmpty) return null;

    validCandidates.sort((a, b) => b.value.compareTo(a.value));
    return validCandidates.first.key;
  }

  static bool _isValidBIN(String str) {
    if (str.isEmpty) return false;
    final first = str[0];
    if (first == '4') return true; // Visa
    if (first == '5' || first == '2') return true; // MC
    if (first == '3') return true; // Amex/Diners
    if (first == '6' || first == '8') return true; // Discover/RuPay
    return false;
  }

  static bool luhnCheck(String str) {
    if (str.length < 13) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = str.length - 1; i >= 0; i--) {
      int n = int.parse(str[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n = (n % 10) + 1;
      }
      sum += n;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
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
