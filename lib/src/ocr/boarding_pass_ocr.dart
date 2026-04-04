import 'scan_result.dart';

/// A utility class for parsing IATA Barcoded Boarding Passes (BCBP).
/// 
/// This class handles the extraction of mandatory fields from the M1-strip 
/// barcode payload and cross-references them with raw OCR text to extract 
/// optional fields like boarding time, terminal, and baggage allowance.
class BoardingPassOCR {
  /// Parses an IATA BCBP barcode string (M1 format) and cross-references 
  /// with the [rawText] to extract detailed flight information.
  /// 
  /// The [payload] must be a valid IATA BCBP string (usually starting with 'M1').
  /// The [format] is the barcode format (e.g., 'PDF417' or 'QR_CODE').
  /// 
  /// Returns a [FlightTicketResult] if parsing is successful, or `null` otherwise.
  static FlightTicketResult? parseBoardingPass(String payload, String format, String? rawText) {
    if (!payload.startsWith('M') || payload.length < 58) {
      return null;
    }

    final String nameRaw = payload.substring(2, 22).trim();
    final String pnrRaw = payload.substring(23, 30).trim();
    final String fromRaw = payload.substring(30, 33).trim();
    final String toRaw = payload.substring(33, 36).trim();
    final String carrierRaw = payload.substring(36, 39).trim();
    final String flightRaw = payload.substring(39, 44).trim();
    final String seatRaw = payload.substring(48, 52).trim();
    final String seqRaw = payload.substring(52, 57).trim();

    final flightNumber = "$carrierRaw$flightRaw".replaceAll(RegExp(r'\s+'), '');

    String? departureTime;
    String? boardingTime;
    String? zone;
    String? cabinBaggage;
    String? checkInBaggage;
    String? addOns;
    String? originTerminal;
    String? destinationTerminal;

    if (rawText != null && rawText.isNotEmpty) {
      // 1. Text Pre-processing (Handle common OCR typos for numbers)
      // Replace common typos in potential time blocks like 13:!8 or 17:|5
      String processedText = rawText.replaceAll(RegExp(r'(?<=\d)[:.][!|l]'), ':1');
      processedText = processedText.replaceAll(RegExp(r'(?<=\d)[\s]*[!|l](?=\d)'), '1');

      final lines = processedText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      // 2. Extract Times via Keyword Proximity (Boarding/Departure)
      final timeRegex = RegExp(r'\b([0-1]?[0-9]|2[0-3])[:.]([0-5][0-9])\b|\b([0-1]?[0-9][:.][0-5][0-9]\s*(AM|PM))\b', caseSensitive: false);

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].toLowerCase();

        // Hunting for Boarding Time
        if (boardingTime == null && (line.contains('boarding') || line.contains('brdg'))) {
           // Look for time in current line or next 2 lines
           for (int j = i; j <= i + 2 && j < lines.length; j++) {
              final match = timeRegex.firstMatch(lines[j]);
              if (match != null) {
                boardingTime = match.group(0)?.replaceAll('.', ':');
                break;
              }
           }
        }

        // Hunting for Departure Time
        if (departureTime == null && (line.contains('departure') || line.contains('dep time') || line.contains('schd dep'))) {
           for (int j = i; j <= i + 2 && j < lines.length; j++) {
              final match = timeRegex.firstMatch(lines[j]);
              if (match != null) {
                departureTime = match.group(0)?.replaceAll('.', ':');
                break;
              }
           }
        }
      }

      // Fallback: If keywords failed, use visual order (First = Boarding, Second = Departure)
      if (boardingTime == null || departureTime == null) {
        final allTimeMatches = timeRegex.allMatches(processedText).toList();
        if (boardingTime == null && allTimeMatches.isNotEmpty) {
           boardingTime = allTimeMatches[0].group(0)?.replaceAll('.', ':');
        }
        if (departureTime == null && allTimeMatches.length > 1) {
           departureTime = allTimeMatches[1].group(0)?.replaceAll('.', ':');
        }
      }

      // 3. Extract Terminals (Visual order: 1st is origin, 2nd is destination)
      final terminalRegex = RegExp(r'\b(T[\s-]?[0-9]|Terminal[\s-]?[0-9])\b', caseSensitive: false);
      final terminalMatches = terminalRegex.allMatches(processedText).toList();
      if (terminalMatches.isNotEmpty) {
        originTerminal = terminalMatches[0].group(0);
        if (terminalMatches.length > 1) {
          destinationTerminal = terminalMatches[1].group(0);
        }
      }

      // 4. Contextual Line Scraping for other fields
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].toLowerCase();

        // Zone
        if (zone == null && (line.contains('zone') || line.contains('group') || line.contains('grp'))) {
           final zonMatch = RegExp(r'\b(zone|group|grp)[\s:]*([0-9A-Z])\b', caseSensitive: false).firstMatch(lines[i]);
           if (zonMatch != null) {
             zone = zonMatch.group(0);
           }
        }

        // Add Ons
        if (addOns == null && (line.contains('add ons') || line.contains('add-ons'))) {
          if (i + 1 < lines.length) {
            addOns = lines[i + 1];
          }
        }

        // Cabin Baggage
        if (cabinBaggage == null && (line.contains('cabin baggage') || line.contains('hand baggage'))) {
          // Look for weight in same line or next line
          final weightRegex = RegExp(r'([0-9]+\s*(kg|kgs|lbs|pc|pcs))', caseSensitive: false);
          final matchInLine = weightRegex.firstMatch(lines[i]);
          if (matchInLine != null) {
            cabinBaggage = matchInLine.group(0);
          } else if (i + 1 < lines.length) {
            final matchInNext = weightRegex.firstMatch(lines[i + 1]);
            if (matchInNext != null) {
              cabinBaggage = lines[i + 1].trim();
            }
          }
        }

        // Check-in Baggage
        if (checkInBaggage == null && (line.contains('check-in bag') || line.contains('checked bag') || line.contains('checkin bag'))) {
          final weightRegex = RegExp(r'([0-9]+\s*(kg|kgs|lbs|pc|pcs))', caseSensitive: false);
          final matchInLine = weightRegex.firstMatch(lines[i]);
          if (matchInLine != null) {
            checkInBaggage = matchInLine.group(0);
          } else if (i + 1 < lines.length) {
            final matchInNext = weightRegex.firstMatch(lines[i + 1]);
            if (matchInNext != null) {
              checkInBaggage = lines[i + 1].trim();
            }
          }
        }
      }
    }

    return FlightTicketResult(
      payload: payload,
      format: format,
      pnr: pnrRaw,
      passengerName: nameRaw,
      flightNumber: flightNumber,
      origin: fromRaw,
      originTerminal: originTerminal,
      destination: toRaw,
      destinationTerminal: destinationTerminal,
      seat: seatRaw,
      sequence: seqRaw,
      departureTime: departureTime,
      boardingTime: boardingTime,
      zone: zone,
      cabinBaggage: cabinBaggage,
      checkInBaggage: checkInBaggage,
      addOns: addOns,
      rawText: rawText,
    );
  }
}
