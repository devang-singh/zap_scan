import 'package:flutter/material.dart';
import 'package:zap_scan/zap_scan.dart';

void main() => runApp(const MaterialApp(home: ZapScanExample()));

class ZapScanExample extends StatefulWidget {
  const ZapScanExample({super.key});

  @override
  State<ZapScanExample> createState() => _ZapScanExampleState();
}

class _ZapScanExampleState extends State<ZapScanExample> {
  late UniversalScannerController _controller;
  String _status = "Select an action below";
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    // 1. Initialize the controller with callbacks
    _controller = UniversalScannerController(
      onResultScanned: (result) {
        setState(() {
          _isScanning = false;
          if (result is ZapCardResult) {
            _status = "Credit Card: ${result.cardNumber}\nExpiry: ${result.expiryDate ?? 'N/A'}\nCVV: ${result.cvv ?? 'N/A'}";
          } else if (result is FlightTicketResult) {
            _status = "Boarding Pass: ${result.passengerName}\nFlight: ${result.flightNumber}\nPNR: ${result.pnr}";
          } else if (result is BarcodeResult) {
            _status = "Barcode (${result.format}): ${result.payload}";
          }
        });
      },
    );
  }

  Future<void> _readNfc() async {
    setState(() => _status = "Hold card near the back of the device...");
    try {
      final card = await EmvNfcService.scanCard();
      if (card != null) {
        setState(() => _status = "NFC Found Card!\nNumber: ${card.cardNumber}\nExpiry: ${card.expiryDate}");
      }
    } catch (e) {
      setState(() => _status = "NFC Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zap Scan Example')),
      body: Column(
        children: [
          // THE SCANNER WIDGET
          if (_isScanning)
            Expanded(
              child: Stack(
                children: [
                  ZapScanWidget(controller: _controller),
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: () => setState(() => _isScanning = false),
                        child: const Text("Cancel"),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),

          // BUTTONS
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _status = "Scanning...";
                      _isScanning = true;
                    });
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Scan Card"),
                ),
                ElevatedButton.icon(
                  onPressed: _readNfc,
                  icon: const Icon(Icons.nfc),
                  label: const Text("Read NFC"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
