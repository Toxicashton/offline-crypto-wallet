import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:elliptic/elliptic.dart';
import 'package:hex/hex.dart';
import 'services/wallet_service.dart';
import 'login_screen.dart'; // <--- Import the new screen
import 'package:flutter/services.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(), // <--- Start at Login, not Wallet
    ),
  );
}

class WalletScreen extends StatefulWidget {
  // Now we accept the key from the Login Page
  final PrivateKey privateKey;

  const WalletScreen({super.key, required this.privateKey});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService();
  late String _myPublicKey;
  String _transactionJson = "";

  @override
  void initState() {
    super.initState();
    // Use the key passed from Login Page
    _myPublicKey = widget.privateKey.publicKey.toHex().substring(0, 15) + "...";
  }

  void _sendMoney() {
    var packet = _walletService.createTransactionPacket(
      senderId: widget.privateKey.publicKey.toHex(),
      receiverId: "User_B_Gateway_Address",
      amount: 50.0,
      privateKey: widget.privateKey,
    );

    setState(() {
      _transactionJson = json.encode(packet);
    });
  }

  // 1. Copy the FULL key to the clipboard
  void _copyAddressToClipboard() {
    String fullKey = widget.privateKey.publicKey.toHex();
    Clipboard.setData(ClipboardData(text: fullKey));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Full Wallet Address Copied!"),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  // 2. Show a Popup with the QR Code of YOUR Address
  void _showAddressQR() {
    String fullKey = widget.privateKey.publicKey.toHex();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("My Wallet Address"),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: fullKey, // This generates a QR of YOUR address
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Wallet"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // 1. Clear the navigation stack so they can't go back
              // 2. Force the app to go to the LoginScreen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(fromLogout: true),
                ),

                // This removes all previous routes
              );
            },
          ),
        ],
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- START OF UPDATED CARD ---
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "MY PUBLIC ID (WALLET ADDRESS)",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Row with: Key Text | Copy Button | QR Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The Truncated Text (Clickable)
                        InkWell(
                          onTap: _copyAddressToClipboard,
                          child: Text(
                            _myPublicKey, // Shows "049833..."
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.blueAccent,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        // Copy Icon
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            size: 20,
                            color: Colors.grey,
                          ),
                          tooltip: "Copy Full Address",
                          onPressed: _copyAddressToClipboard,
                        ),

                        // QR Icon (Show Full Key)
                        IconButton(
                          icon: const Icon(
                            Icons.qr_code,
                            size: 20,
                            color: Colors.grey,
                          ),
                          tooltip: "Show Address QR",
                          onPressed: _showAddressQR,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // --- END OF UPDATED CARD ---
            const SizedBox(height: 20),
            const TextField(
              decoration: InputDecoration(
                labelText: "Receiver ID",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const TextField(
              decoration: InputDecoration(
                labelText: "Amount",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _sendMoney,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text("SIGN & GENERATE OFFLINE QR"),
            ),
            const SizedBox(height: 30),
            if (_transactionJson.isNotEmpty) ...[
              Center(
                child: QrImageView(
                  data: _transactionJson,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.grey[200],
                child: Text(
                  _transactionJson,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
