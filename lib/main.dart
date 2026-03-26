import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:elliptic/elliptic.dart';
import 'package:hex/hex.dart';
import 'package:flutter/services.dart';

// --- OUR CUSTOM SERVICES ---
import 'services/wallet_service.dart';
import 'services/api_service.dart';
import 'services/local_db.dart';
import 'login_screen.dart';

// --- OUR OFFLINE SCREENS ---
import 'scanner_screen.dart';
import 'radar_screen.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: LoginScreen()),
  );
}

class WalletScreen extends StatefulWidget {
  final PrivateKey privateKey;
  const WalletScreen({super.key, required this.privateKey});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService();
  final TextEditingController _receiverController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  late String _fullPublicKey;
  late String _shortPublicKey;

  bool _isSending = false;
  bool _isSyncing = false;

  double _balance = 0.0;
  // NEW: Keep track of money sent offline during this session
  double _pendingDeductions = 0.0;

  List<dynamic> _history = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _fullPublicKey = widget.privateKey.publicKey.toHex();
    _shortPublicKey = _fullPublicKey.substring(0, 16);
    _fetchDashboardData();
  }

  @override
  void dispose() {
    _receiverController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoadingData = true);
    final data = await ApiService.getWalletData(_shortPublicKey);
    if (data != null && mounted) {
      setState(() {
        _balance = (data['balance'] as num).toDouble();
        _history = data['history'] ?? [];
        // Reset pending deductions when we get fresh true data from the blockchain
        _pendingDeductions = 0.0;
      });
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  // ==========================================
  // ONLINE LOGIC
  // ==========================================
  void _submitToBlockchain() async {
    if (_receiverController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Receiver ID and Amount")),
      );
      return;
    }

    double parsedAmount = double.tryParse(_amountController.text) ?? 0.0;

    // NEW: Prevent sending if they don't have enough (including pending offline sends)
    if (parsedAmount > (_balance - _pendingDeductions)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Insufficient funds!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    String uniqueTxnId = "TXN_${DateTime.now().millisecondsSinceEpoch}";

    bool success = await ApiService.submitTransaction(
      transactionId: uniqueTxnId,
      amount: parsedAmount,
      sender: _shortPublicKey,
      receiver: _receiverController.text,
    );

    setState(() => _isSending = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Success! Payment secured."),
          backgroundColor: Colors.green,
        ),
      );
      _amountController.clear();
      _receiverController.clear();
      _fetchDashboardData();
    } else {
      await LocalDatabase.saveOfflineTransaction(
        transactionId: uniqueTxnId,
        amount: parsedAmount,
        sender: _shortPublicKey,
        receiver: _receiverController.text,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Offline Mode: Saved to vault."),
          backgroundColor: Colors.orange,
        ),
      );

      // Update pending balance locally since it failed to hit the internet
      setState(() {
        _pendingDeductions += parsedAmount;
      });
    }
  }

  Future<void> _syncOfflineVault() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final pendingTxns = await LocalDatabase.getPendingTransactions();
    if (pendingTxns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vault is empty. Everything is synced!"),
          backgroundColor: Colors.blueAccent,
        ),
      );
      setState(() => _isSyncing = false);
      return;
    }

    int successCount = 0;
    for (var txn in pendingTxns) {
      bool success = await ApiService.submitTransaction(
        transactionId: txn['id'],
        amount: txn['amount'],
        sender: txn['sender'],
        receiver: txn['receiver'],
      );
      if (success) {
        await LocalDatabase.deleteTransaction(txn['id']);
        successCount++;
      }
    }

    setState(() => _isSyncing = false);
    _fetchDashboardData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Synced $successCount out of ${pendingTxns.length} offline transactions!",
        ),
        backgroundColor: successCount == pendingTxns.length
            ? Colors.green
            : Colors.orange,
      ),
    );
  }

  // ==========================================
  // SMART OFFLINE LOGIC
  // ==========================================
  void _handleSmartQR() {
    if (_amountController.text.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ScannerScreen()),
      );
    } else {
      double parsedAmount = double.tryParse(_amountController.text) ?? 0.0;

      // Check for sufficient funds!
      if (parsedAmount > (_balance - _pendingDeductions)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Insufficient funds!"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      var packet = _walletService.createTransactionPacket(
        senderId: _shortPublicKey,
        receiverId: _receiverController.text.isNotEmpty
            ? _receiverController.text
            : "Unknown_Receiver",
        amount: parsedAmount,
        privateKey: widget.privateKey,
      );

      // Deduct locally and show QR
      setState(() {
        _pendingDeductions += parsedAmount;
      });
      _amountController.clear(); // Clear so they don't double send easily
      _showQrDialog(json.encode(packet));
    }
  }

  void _handleSmartRadar() {
    if (_amountController.text.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RadarScreen(shortAddress: _shortPublicKey),
        ),
      );
    } else {
      double parsedAmount = double.tryParse(_amountController.text) ?? 0.0;

      // Check for sufficient funds!
      if (parsedAmount > (_balance - _pendingDeductions)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Insufficient funds!"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      var packet = _walletService.createTransactionPacket(
        senderId: _shortPublicKey,
        receiverId: _receiverController.text.isNotEmpty
            ? _receiverController.text
            : "Unknown_Receiver",
        amount: parsedAmount,
        privateKey: widget.privateKey,
      );

      // Deduct locally and open Radar
      setState(() {
        _pendingDeductions += parsedAmount;
      });
      _amountController.clear(); // Clear input

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RadarScreen(
            transactionPayload: json.encode(packet),
            shortAddress: _shortPublicKey,
          ),
        ),
      );
    }
  }

  void _showQrDialog(String qrData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Scan to Receive OFC",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220.0,
            ),
          ),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "CLOSE",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyAddressToClipboard() {
    Clipboard.setData(ClipboardData(text: _shortPublicKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Address Copied!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildActionIcon(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.blueAccent.withOpacity(0.1),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: Colors.blueAccent, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate what the user actually has available right now
    double availableBalance = _balance - _pendingDeductions;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "My Wallet",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const LoginScreen(fromLogout: true),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- 1. THE BALANCE CARD ---
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      "AVAILABLE BALANCE",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _isLoadingData
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "${availableBalance.toStringAsFixed(2)} OFC",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                    // NEW: Show pending deductions if there are any!
                    if (_pendingDeductions > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Pending offline sync: -${_pendingDeductions.toStringAsFixed(2)} OFC",
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- 2. WALLET ADDRESS BAR ---
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.qr_code, color: Colors.blueAccent),
                  title: const Text(
                    "My Address",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  subtitle: Text(
                    "${_shortPublicKey}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: _copyAddressToClipboard,
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // --- 3. SEND MONEY SECTION ---
              TextField(
                controller: _receiverController,
                decoration: InputDecoration(
                  labelText: "Receiver ID",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Amount (OFC)",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              ElevatedButton(
                onPressed: _isSending ? null : _submitToBlockchain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "SUBMIT TO BLOCKCHAIN",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 30),

              // --- 4. THE SMART OFFLINE TOOLS ROW ---
              const Text(
                "Offline Tools",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionIcon(
                    Icons.qr_code_scanner,
                    "Smart QR",
                    _handleSmartQR,
                  ),
                  _buildActionIcon(
                    Icons.radar,
                    "Smart Radar",
                    _handleSmartRadar,
                  ),
                  _buildActionIcon(
                    Icons.cloud_upload,
                    "Sync Vault",
                    _syncOfflineVault,
                    isLoading: _isSyncing,
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // --- 5. RECENT TRANSACTIONS ---
              const Text(
                "Recent Transactions",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _isLoadingData
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _history.isEmpty
                  ? const Center(
                      child: Text(
                        "No transactions yet.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final txn = _history[index];
                        bool isSent = txn['type'] == 'SENT';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSent
                                  ? Colors.red[100]
                                  : Colors.green[100],
                              child: Icon(
                                isSent
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: isSent ? Colors.red : Colors.green,
                              ),
                            ),
                            title: Text(
                              txn['id'].toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              txn['date'].toString().substring(0, 10),
                            ),
                            trailing: Text(
                              "${isSent ? '-' : '+'}${txn['amount']} OFC",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isSent ? Colors.red : Colors.green,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
