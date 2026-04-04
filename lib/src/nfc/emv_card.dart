/// Represents a payment card read via NFC (EMV).
class EmvCard {
  /// The Primary Account Number (PAN) of the card.
  final String cardNumber;
  
  /// The expiry date in YYMM format.
  final String expiryDate;

  /// Returns the month component (MM) of the [expiryDate].
  String get month => expiryDate.substring(0, 2);

  /// Default constructor for [EmvCard].
  const EmvCard({
    required this.cardNumber,
    required this.expiryDate,
  });

  @override
  String toString() {
    return 'ZapCard(cardNumber: $cardNumber, expiryDate: $expiryDate)';
  }
}
