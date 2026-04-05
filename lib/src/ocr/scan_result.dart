/// Base class for all scan results.
abstract class ScanResult {
  /// The raw text recognized by the OCR or Barcode engine.
  final String? rawText;

  /// Default constructor for [ScanResult].
  const ScanResult({this.rawText});
}

/// Represents the data extracted from a payment card.
class ZapCardResult extends ScanResult {
  /// The 14- to 16-digit card number.
  final String cardNumber;

  /// The most accurate guessed card number, even if it fails validation or has noisy characters.
  final String? guessedCardNumber;

  /// The expiry date in MM/YY format, if found.
  final String? expiryDate;

  /// The 3- or 4-digit security code (CVV/CVC/CID), if found.
  final String? cvv;

  /// Default constructor for [ZapCardResult].
  const ZapCardResult({
    required this.cardNumber,
    this.guessedCardNumber,
    this.expiryDate,
    this.cvv,
    super.rawText,
  });

  @override
  String toString() {
    return 'ZapCardResult(cardNumber: $cardNumber, guessedCardNumber: $guessedCardNumber, expiryDate: $expiryDate, cvv: $cvv, rawText: $rawText)';
  }
}

/// Represents the data extracted from a generic barcode or QR code.
class BarcodeResult extends ScanResult {
  /// The decoded string content of the barcode.
  final String payload;

  /// The format of the barcode (e.g., QR_CODE, CODE_128).
  final String format;

  /// Default constructor for [BarcodeResult].
  const BarcodeResult({
    required this.payload,
    required this.format,
    super.rawText,
  });

  @override
  String toString() {
    return 'BarcodeResult(payload: $payload, format: $format, rawText: $rawText)';
  }
}

/// Represents the detailed data extracted from an IATA BCBP boarding pass.
class FlightTicketResult extends BarcodeResult {
  /// The 6-character Passenger Name Record (PNR) or locator.
  final String pnr;

  /// The passenger's name as it appears in the barcode.
  final String? passengerName;

  /// The flight number (e.g., AI101).
  final String? flightNumber;

  /// The IATA airport code for the origin (e.g., JFK).
  final String? origin;

  /// The terminal code for the origin.
  final String? originTerminal;

  /// The IATA airport code for the destination (e.g., LHR).
  final String? destination;

  /// The terminal code for the destination.
  final String? destinationTerminal;

  /// The assigned seat (e.g., 12A).
  final String? seat;

  /// The check-in sequence number.
  final String? sequence;

  /// The scheduled departure time.
  final String? departureTime;

  /// The estimated boarding time.
  final String? boardingTime;

  /// The assigned boarding zone.
  final String? zone;

  /// The cabin baggage allowance or status.
  final String? cabinBaggage;

  /// The checked baggage allowance or status.
  final String? checkInBaggage;

  /// Additional services or notes included in the barcode.
  final String? addOns;

  /// Default constructor for [FlightTicketResult].
  const FlightTicketResult({
    required super.payload,
    required super.format,
    required this.pnr,
    this.passengerName,
    this.flightNumber,
    this.origin,
    this.originTerminal,
    this.destination,
    this.destinationTerminal,
    this.seat,
    this.sequence,
    this.departureTime,
    this.boardingTime,
    this.zone,
    this.cabinBaggage,
    this.checkInBaggage,
    this.addOns,
    super.rawText,
  });

  @override
  String toString() {
    return 'FlightTicketResult(pnr: $pnr, pass: $passengerName, flight: $flightNumber, from: $origin $originTerminal, to: $destination $destinationTerminal, seat: $seat, seq: $sequence, dep: $departureTime, board: $boardingTime, zone: $zone, cabinBag: $cabinBaggage, checkBag: $checkInBaggage, addOns: $addOns, rawText: $rawText)';
  }
}

/// Represents an error occurred during the scanning process.
class ScanErrorResult extends ScanResult {
  /// The error code (e.g., 'image_error', 'ocr_error').
  final String code;

  /// The descriptive error message.
  final String message;

  /// Default constructor for [ScanErrorResult].
  const ScanErrorResult({
    required this.code,
    required this.message,
    super.rawText,
  });

  @override
  String toString() {
    return 'ScanErrorResult(code: $code, message: $message, rawText: $rawText)';
  }
}
