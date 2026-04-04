abstract class ScanResult {
  final String? rawText;
  const ScanResult({this.rawText});
}

class ZapCardResult extends ScanResult {
  final String cardNumber;
  final String? expiryDate;
  final String? cvv;

  const ZapCardResult({
    required this.cardNumber,
    this.expiryDate,
    this.cvv,
    super.rawText,
  });

  @override
  String toString() {
    return 'ZapCardResult(cardNumber: $cardNumber, expiryDate: $expiryDate, cvv: $cvv, rawText: $rawText)';
  }
}

class BarcodeResult extends ScanResult {
  final String payload;
  final String format;

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

class FlightTicketResult extends BarcodeResult {
  final String pnr;
  final String? passengerName;
  final String? flightNumber;
  final String? origin;
  final String? originTerminal;
  final String? destination;
  final String? destinationTerminal;
  final String? seat;
  final String? sequence;
  
  final String? departureTime;
  final String? boardingTime;
  final String? zone;
  final String? cabinBaggage;
  final String? checkInBaggage;
  final String? addOns;

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
