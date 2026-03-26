import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // REPLACE THIS with your actual IPv4 address or ngrok URL if testing wirelessly!
  //static const String _baseUrl = 'http://127.0.0.1:3000/api';
  static const String _baseUrl ='https://demetria-uninsidious-laboriously.ngrok-free.dev/api';

  static Future<bool> submitTransaction({
    required String transactionId,
    required double amount,
    required String sender,
    required String receiver,
  }) async {
    final url = Uri.parse('$_baseUrl/submitPayment');

    try {
      print('--> Sending payment to Gateway API...');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transactionId': transactionId,
              'amount': amount,
              'sender': sender,
              'receiver': receiver,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('*** Success: ${response.body}');
        return true;
      } else {
        print('*** Failed to submit: ${response.body}');
        return false;
      }
    } catch (e) {
      print('*** Connection Error: $e');
      // If this fails, it means the phone has no internet!
      return false;
    }
  }

  // ==========================================
  // UPDATED: Fetch Balance with OFFLINE MEMORY
  // ==========================================
  static Future<Map<String, dynamic>?> getWalletData(String userId) async {
    final url = Uri.parse('$_baseUrl/wallet/$userId');

    // 1. Prepare to access the phone's local memory
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'offline_wallet_data_$userId';

    try {
      print('--> Fetching wallet data for $userId from Blockchain...');
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        // 2. SUCCESS! We are online. Save this fresh data to memory immediately!
        await prefs.setString(cacheKey, response.body);

        return jsonDecode(response.body);
      } else {
        print('*** Server error: ${response.body}');
        // Fall through to offline load
      }
    } catch (e) {
      print('*** Connection failed (Cable unplugged or Airplane Mode): $e');
      print('--> Loading last known balance from Offline Memory...');
    }

    // 3. OFFLINE FALLBACK: If we reach here, the network failed.
    // Let's check if we have a saved balance in memory!
    final String? savedData = prefs.getString(cacheKey);

    if (savedData != null) {
      print('--> Successfully loaded offline data!');
      return jsonDecode(savedData);
    } else {
      print('--> No offline data found. Returning 0 balance.');
      // 4. Only return 0 if they have literally NEVER connected to the server before
      return {'balance': 0.0, 'history': []};
    }
  }

  // ==========================================
  // NEW: OFFLINE TRANSACTION QUEUE (For QR Codes)
  // ==========================================
  static const String _offlineTxKey = 'offline_tx_queue';

  /// Call this when Phone B scans Phone A's QR Code while offline
  static Future<void> saveOfflineTransaction(
    Map<String, dynamic> txData,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Get existing queue of pending transactions
    final String? queueStr = prefs.getString(_offlineTxKey);
    List<dynamic> queue = [];
    if (queueStr != null) {
      queue = jsonDecode(queueStr);
    }

    // Add the newly scanned transaction
    queue.add(txData);

    // Save it safely back into the phone's memory
    await prefs.setString(_offlineTxKey, jsonEncode(queue));
    print('--> Offline transaction securely saved to local memory queue!');
  }

  /// Call this when the phone reconnects to Wi-Fi/Internet
  static Future<void> syncOfflineTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueStr = prefs.getString(_offlineTxKey);

    if (queueStr == null) return; // Nothing to sync

    List<dynamic> queue = jsonDecode(queueStr);
    if (queue.isEmpty) return;

    print(
      '--> Found ${queue.length} offline transactions. Syncing to Blockchain...',
    );

    List<dynamic> remainingQueue = [];

    // Loop through all saved offline transactions and try to upload them
    for (var tx in queue) {
      bool success = await submitTransaction(
        transactionId: tx['transactionId'],
        amount: (tx['amount'] as num).toDouble(),
        sender: tx['sender'],
        receiver: tx['receiver'],
      );

      if (!success) {
        // If the upload failed (e.g., internet dropped again), keep it in the queue
        remainingQueue.add(tx);
      }
    }

    // Update the queue (if everything succeeded, this will empty the queue!)
    await prefs.setString(_offlineTxKey, jsonEncode(remainingQueue));
    if (remainingQueue.isEmpty) {
      print(
        '--> All offline transactions synced successfully! Queue is clear.',
      );
    }
  }
}
