import 'package:flutter/material.dart';
import 'package:elliptic/elliptic.dart';
import 'services/wallet_service.dart';
import 'main.dart'; 

class LoginScreen extends StatefulWidget {
  // New: Accept a flag to know if we should check for auto-login
  final bool fromLogout;

  const LoginScreen({super.key, this.fromLogout = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final WalletService _walletService = WalletService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // FIX: Only check for existing user if we did NOT come from Logout
    if (!widget.fromLogout) {
      _checkExistingUser();
    }
  }

  void _checkExistingUser() async {
    setState(() => _isLoading = true);
    PrivateKey? savedKey = await _walletService.loadWallet();
    if (savedKey != null) {
      _navigateToWallet(savedKey);
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _createAccount() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800)); 
    PrivateKey newKey = _walletService.generateWallet();
    await _walletService.saveWallet(newKey);
    _navigateToWallet(newKey);
  }

  void _navigateToWallet(PrivateKey key) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WalletScreen(privateKey: key)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text(
              "Offline Crypto",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 60),

            ElevatedButton(
              onPressed: _createAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text("CREATE NEW WALLET", style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 15),
            
            // "Login" button manually triggers the check
            OutlinedButton(
              onPressed: _checkExistingUser, 
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text("LOGIN (RESTORE)"),
            ),
          ],
        ),
      ),
    );
  }
}