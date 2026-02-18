import 'dart:convert';
import 'package:elliptic/elliptic.dart';
import 'package:crypto/crypto.dart';
import 'package:ecdsa/ecdsa.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <--- NEW IMPORT

class WalletService {
  // Use the secp256k1 curve (Standard for Bitcoin/Ethereum)
  final _curve = getSecp256k1();

  // --- NEW: SAVE WALLET TO PHONE MEMORY ---
  Future<void> saveWallet(PrivateKey privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    // We save the Private Key as a HEX string
    await prefs.setString('private_key', privateKey.toHex());
  }

  // --- NEW: LOAD WALLET FROM PHONE MEMORY ---
  Future<PrivateKey?> loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    String? keyHex = prefs.getString('private_key');

    if (keyHex == null) return null; // No account found

    // Convert the Hex string back to a Private Key object
    return PrivateKey.fromHex(_curve, keyHex);
  }

  // --- NEW: LOGOUT (DELETE WALLET) ---
  Future<void> deleteWallet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('private_key');
  }

  // 1. Generate a new "Account" (Private/Public Key Pair)
  PrivateKey generateWallet() {
    var privateKey = _curve.generatePrivateKey();
    return privateKey;
  }

  // 2. Create the Transaction Data Packet
  Map<String, dynamic> createTransactionPacket({
    required String senderId,
    required String receiverId,
    required double amount,
    required PrivateKey privateKey,
  }) {
    // A. Create the payload
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final Map<String, dynamic> transactionData = {
      'from': senderId,
      'to': receiverId,
      'amount': amount,
      'timestamp': timestamp,
    };

    // B. Convert to string to sign it
    String payloadString = json.encode(transactionData);

    // C. Sign the payload
    String signatureString = _signData(payloadString, privateKey);

    // D. Return the final packet
    return {...transactionData, 'signature': signatureString};
  }

  // Helper: Sign string data
  String _signData(String data, PrivateKey privateKey) {
    // Hash the data first (SHA-256)
    var bytes = utf8.encode(data);
    var digest = sha256.convert(bytes);

    // FIX: Using the imported 'signature' function from ecdsa.dart
    var sig = signature(privateKey, digest.bytes);

    return sig.toASN1Hex();
  }
}
