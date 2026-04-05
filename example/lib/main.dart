import 'package:flutter/material.dart';
import 'package:zap_scan/zap_scan.dart';
import 'package:image_picker/image_picker.dart';

/// Entry point for the Zap Scan example application.
void main() => runApp(const MaterialApp(home: ZapScanExample()));

/// A simple example application demonstrating the use of [ZapScanWidget]
/// and [EmvNfcService] for scanning payment cards and barcodes.
class ZapScanExample extends StatefulWidget {
  /// Default constructor for [ZapScanExample].
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
            _status = "💳 Credit Card\nNumber: ${result.cardNumber}\nExpiry: ${result.expiryDate ?? 'N/A'}\nCVV: ${result.cvv ?? 'N/A'}";
          } else if (result is FlightTicketResult) {
            _status = "✈️ Boarding Pass\n"
                "Name: ${result.passengerName ?? 'N/A'}\n"
                "Flight: ${result.flightNumber ?? 'N/A'}\n"
                "PNR: ${result.pnr}\n"
                "Seat: ${result.seat ?? 'N/A'} | Seq: ${result.sequence ?? 'N/A'}\n"
                "Route: ${result.origin}${result.originTerminal ?? ''} -> ${result.destination}${result.destinationTerminal ?? ''}\n"
                "Boarding: ${result.boardingTime ?? 'N/A'}\n"
                "Departure: ${result.departureTime ?? 'N/A'}\n"
                "Baggage: ${result.cabinBaggage ?? 'None'} / ${result.checkInBaggage ?? 'None'}\n"
                "Add-ons: ${result.addOns ?? 'None'}";
          } else if (result is BarcodeResult) {
            _status = "📊 Barcode (${result.format})\nPayload: ${result.payload}";
          }
        });
      },
    )..showDebugOverlay = true;
  }

  Future<void> _readNfc() async {
    setState(() => _status = "Hold card near the back of the device...");
    try {
      final card = await EmvNfcService.scanCard();
      if (card != null) {
        setState(() => _status = "🔓 NFC Found Card!\nNumber: ${card.cardNumber}\nExpiry: ${card.expiryDate}");
      }
    } catch (e) {
      setState(() => _status = "❌ NFC Error: $e");
    }
  }

  Future<void> _pickAndScan() async {
    await _controller.stopCamera(); // Kill the cam
    setState(() => _isScanning = false); // Update UI
    await Future.delayed(const Duration(milliseconds: 300));
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);

    if (image == null) return;

    setState(() {
      _status = "Processing image...";
      _isScanning = false;
    });

    await _controller.stopCamera();

    try {
      final result = await _controller.scanFromImage(image);

      if (result is ScanErrorResult) {
        setState(() => _status = "Scan Error [${result.code}]: ${result.message}");
      } else if (result is ZapCardResult) {
        setState(() => _status = "💳 Credit Card\n"
            "Number: ${result.cardNumber}\n"
            "Guessed: ${result.guessedCardNumber ?? 'N/A'}\n"
            "Expiry: ${result.expiryDate ?? 'N/A'}\n"
            "CVV: ${result.cvv ?? 'N/A'}\n"
            "Raw: ${result.rawText}\n");
      } else if (result is FlightTicketResult) {
        setState(() => _status = "✈️ Boarding Pass\n"
            "Name: ${result.passengerName ?? 'N/A'}\n"
            "Flight: ${result.flightNumber ?? 'N/A'}\n"
            "PNR: ${result.pnr}\n"
            "Route: ${result.origin} -> ${result.destination}");
      } else if (result is BarcodeResult) {
        setState(() => _status = "📊 Barcode (${result.format})\nPayload: ${result.payload}");
      } else {
        setState(() => _status = "No recognizable data found in image.");
      }
    } catch (e) {
      setState(() => _status = "Unexpected Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zap Scan Example'),
        elevation: 2,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_controller.showDebugOverlay ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () {
              setState(() {
                _controller.showDebugOverlay = !_controller.showDebugOverlay;
              });
            },
            tooltip: "Toggle OCR Debug Overlay",
          ),
        ],
      ),
      body: Column(
        children: [
          // THE SCANNER WIDGET
          if (_isScanning)
            Expanded(
              child: Stack(
                children: [
                  ZapScanWidget(controller: _controller),
                  // SHOW REAL-TIME GUESSED CARD
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      if (_controller.guessedCard == null) return const SizedBox.shrink();
                      return Positioned(
                        top: 40,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Detecting: ${_controller.guessedCard}",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: () => setState(() => _isScanning = false),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ),

          // BUTTONS
          Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _status = "Scanning...";
                      _isScanning = true;
                    });
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Live Cam"),
                ),
                ElevatedButton.icon(
                  onPressed: _pickAndScan,
                  icon: const Icon(Icons.image),
                  label: const Text("Upload File"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
                ElevatedButton.icon(
                  onPressed: _readNfc,
                  icon: const Icon(Icons.nfc),
                  label: const Text("Read NFC"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
