import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // REPLACE THIS with your actual IPv4 address from Step 2!
  // Keep the :3000 at the end.
  static const String _baseUrl = 'http://127.0.0.1:3000/api';

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
      // This is where our Offline SQLite logic will take over later.
      return false;
    }
  }

  // ==========================================
  // NEW: Fetch Balance and History
  // ==========================================
  static Future<Map<String, dynamic>?> getWalletData(String userId) async {
    // Notice how we reuse the _baseUrl from the top here!
    final url = Uri.parse('$_baseUrl/wallet/$userId');

    try {
      print('--> Fetching wallet data for $userId...');
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('*** Server error: ${response.body}');
        return null;
      }
    } catch (e) {
      print('*** Connection failed: $e');
      return null;
    }
  }
}
