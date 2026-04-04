class EmvCard {
  final String cardNumber;
  final String expiryDate; // Format: YYMM

  String get month => expiryDate.substring(0, 2);

  const EmvCard({
    required this.cardNumber,
    required this.expiryDate,
  });

  @override
  String toString() {
    return 'EmvCard(cardNumber: $cardNumber, expiryDate: $expiryDate)';
  }
}
