import 'dart:convert';
import 'package:elliptic/elliptic.dart';
import 'package:crypto/crypto.dart';
import 'package:ecdsa/ecdsa.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bip39/bip39.dart' as bip39; // <--- NEW BIP-39 IMPORT!

class WalletService {
  // Use the secp256k1 curve (Standard for Bitcoin/Ethereum)
  final _curve = getSecp256k1();

  // ==========================================
  // --- NEW: 12-WORD SEED PHRASE LOGIC ---
  // ==========================================

  // 1. Generate a brand new 12-word phrase
  String generateMnemonic() {
    return bip39.generateMnemonic(); // e.g., "apple zebra bridge..."
  }

  // 2. Convert the 12 words into a secure Private Key
  PrivateKey getPrivateKeyFromMnemonic(String mnemonic) {
    // Check if the words are valid dictionary words
    if (!bip39.validateMnemonic(mnemonic)) {
      throw Exception("Invalid 12-word phrase");
    }

    // Convert words to a cryptographic seed hex (128 characters long)
    String seedHex = bip39.mnemonicToSeedHex(mnemonic);

    // We take the first 64 characters (32 bytes) to form our secp256k1 private key
    String privateKeyHex = seedHex.substring(0, 64);

    return PrivateKey.fromHex(_curve, privateKeyHex);
  }

  // ==========================================
  // --- EXISTING PHONE MEMORY LOGIC ---
  // ==========================================

  Future<void> saveWallet(PrivateKey privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('private_key', privateKey.toHex());
  }

  Future<PrivateKey?> loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    String? keyHex = prefs.getString('private_key');

    if (keyHex == null) return null;
    return PrivateKey.fromHex(_curve, keyHex);
  }

  Future<void> deleteWallet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('private_key');
  }

  // ==========================================
  // --- EXISTING TRANSACTION LOGIC ---
  // ==========================================

  Map<String, dynamic> createTransactionPacket({
    required String senderId,
    required String receiverId,
    required double amount,
    required PrivateKey privateKey,
  }) {
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final Map<String, dynamic> transactionData = {
      'from': senderId,
      'to': receiverId,
      'amount': amount,
      'timestamp': timestamp,
    };

    String payloadString = json.encode(transactionData);
    String signatureString = _signData(payloadString, privateKey);

    return {...transactionData, 'signature': signatureString};
  }

  String _signData(String data, PrivateKey privateKey) {
    var bytes = utf8.encode(data);
    var digest = sha256.convert(bytes);
    var sig = signature(privateKey, digest.bytes);
    return sig.toASN1Hex();
  }
}
