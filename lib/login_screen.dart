import 'package:flutter/material.dart';
import 'package:elliptic/elliptic.dart';
import 'services/wallet_service.dart';
import 'main.dart';

class LoginScreen extends StatefulWidget {
  final bool fromLogout;
  const LoginScreen({super.key, this.fromLogout = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final WalletService _walletService = WalletService();
  bool _isLoading = false;

  // View states: 0 = Home Menu, 1 = Show New Words, 2 = Type Words to Restore
  int _viewState = 0;
  String _generatedMnemonic = "";
  final TextEditingController _restoreController = TextEditingController();

  @override
  void initState() {
    super.initState();
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

  void _navigateToWallet(PrivateKey key) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WalletScreen(privateKey: key)),
      );
    }
  }

  // --- FLOW 1: CREATE NEW WALLET ---
  void _startCreateAccount() {
    setState(() {
      _generatedMnemonic = _walletService
          .generateMnemonic(); // Generate the 12 words!
      _viewState = 1; // Switch UI to View 1
    });
  }

  void _confirmAndSaveNewWallet() async {
    setState(() => _isLoading = true);
    try {
      // Crush the 12 words into the Private Key
      PrivateKey newKey = _walletService.getPrivateKeyFromMnemonic(
        _generatedMnemonic,
      );
      await _walletService.saveWallet(newKey);
      _navigateToWallet(newKey);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // --- FLOW 2: RESTORE EXISTING WALLET ---
  void _startRestoreAccount() {
    setState(() {
      _viewState = 2; // Switch UI to View 2
    });
  }

  void _submitRestoreAccount() async {
    String inputWords = _restoreController.text.trim().toLowerCase();

    // Quick validation check
    if (inputWords.split(' ').length != 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please enter exactly 12 words separated by spaces.",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Attempt to generate the key from the typed words
      PrivateKey restoredKey = _walletService.getPrivateKeyFromMnemonic(
        inputWords,
      );
      await _walletService.saveWallet(restoredKey);
      _navigateToWallet(restoredKey);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Invalid seed phrase. Check your spelling.",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _viewState != 0
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () =>
                    setState(() => _viewState = 0), // Go back to Home Menu
              ),
              backgroundColor: Colors.white,
              elevation: 0,
            )
          : null,
      body: Padding(padding: const EdgeInsets.all(30.0), child: _buildBody()),
    );
  }

  // A helper function to swap out the screen content based on what they clicked
  Widget _buildBody() {
    if (_viewState == 1) {
      // --- VIEW 1: SHOW THE NEW 12 WORDS ---
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Secret Recovery Phrase",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          const Text(
            "Write down these 12 words on a piece of paper. Do not share them with anyone. If you lose them, your money is gone forever.",
            style: TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _generatedMnemonic,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _confirmAndSaveNewWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text(
              "I WROTE IT DOWN",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    } else if (_viewState == 2) {
      // --- VIEW 2: TYPE WORDS TO RESTORE ---
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Restore Wallet",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          const Text(
            "Enter your 12-word secret recovery phrase separated by spaces.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _restoreController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "e.g. apple zebra bridge...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _submitRestoreAccount,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text(
              "RESTORE WALLET",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      // --- VIEW 0: MAIN HOME MENU ---
      return Column(
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
            onPressed: _startCreateAccount,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text(
              "CREATE NEW WALLET",
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: _startRestoreAccount,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text("LOGIN (RESTORE WITH 12 WORDS)"),
          ),
        ],
      );
    }
  }
}
