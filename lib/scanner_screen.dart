import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'services/local_db.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing)
      return; // Prevent scanning the same code 100 times a second

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null) {
        setState(() => _isProcessing = true);
        await _processScannedData(rawValue);
        break;
      }
    }
  }

  Future<void> _processScannedData(String data) async {
    try {
      // 1. Parse the JSON payload from the QR Code
      final Map<String, dynamic> payload = json.decode(data);

      // 2. Verify it's actually our Offline Crypto payload
      if (payload.containsKey('from') &&
          payload.containsKey('to') &&
          payload.containsKey('amount')) {
        String sender = payload['from'];
        String receiver = payload['to'];
        double amount = (payload['amount'] as num).toDouble();

        // Generate a unique ID for this offline transaction
        String offlineTxnId = "OFF_QR_${DateTime.now().millisecondsSinceEpoch}";

        // 3. Save it directly to the SQLite vault!
        await LocalDatabase.saveOfflineTransaction(
          transactionId: offlineTxnId,
          amount: amount,
          sender: sender,
          receiver: receiver,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Success! Offline payment locked in vault."),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Go back to the wallet screen
        }
      } else {
        throw Exception("Invalid QR Format");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error: Not a valid offline crypto payment."),
            backgroundColor: Colors.red,
          ),
        );
        // Let them try scanning again after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Offline Payment"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // A nice targeting reticle for the UI
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Text(
              "Center the QR code in the box",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
