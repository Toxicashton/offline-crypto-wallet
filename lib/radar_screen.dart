import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'services/local_db.dart';
import 'package:permission_handler/permission_handler.dart';

class RadarScreen extends StatefulWidget {
  final String?
  transactionPayload; // If null, we are receiving. If string, we are sending.
  final String shortAddress;

  const RadarScreen({
    super.key,
    this.transactionPayload,
    required this.shortAddress,
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final Strategy strategy =
      Strategy.P2P_CLUSTER; // Best for connecting smartphones
  // This is the secret handshake. Both phones MUST match this exactly!
  final String _serviceId = "com.oactf.offline_wallet";

  bool _isScanning = false;
  Map<String, String> _discoveredDevices = {}; // Maps endpointId to deviceName

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  // 1. Android 12+ requires strict runtime permissions for Bluetooth
  // 1. Android 12+ requires strict runtime permissions for Bluetooth
  Future<void> _requestPermissions() async {
    // Request all required hardware permissions at once
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    // Automatically start the correct radar mode!
    if (widget.transactionPayload == null) {
      _startAdvertising(); // I want to RECEIVE
    } else {
      _startDiscovery(); // I want to SEND
    }
  }

  // ==========================================
  // RECEIVER LOGIC (Broadcast my presence)
  // ==========================================
  void _startAdvertising() async {
    setState(() => _isScanning = true);
    try {
      bool a = await Nearby().startAdvertising(
        widget.shortAddress,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Connected to sender! Waiting for payload..."),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        onDisconnected: (id) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Disconnected.")));
        },
      );
    } catch (e) {
      print("Advertising Error: $e");
    }
  }

  // ==========================================
  // SENDER LOGIC (Scan for receivers)
  // ==========================================
  void _startDiscovery() async {
    setState(() => _isScanning = true);
    try {
      bool a = await Nearby().startDiscovery(
        widget.shortAddress,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          // We found a receiver! Add them to the list UI.
          setState(() {
            _discoveredDevices[id] = name;
          });
        },
        onEndpointLost: (id) {
          setState(() {
            _discoveredDevices.remove(id);
          });
        },
      );
    } catch (e) {
      print("Discovery Error: $e");
    }
  }

  // ==========================================
  // CONNECTION & TRANSFER LOGIC
  // ==========================================

  // When the sender taps a device, initiate the connection
  void _requestConnection(String endpointId) {
    Nearby().requestConnection(
      widget.shortAddress,
      endpointId,
      onConnectionInitiated: _onConnectionInit,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED && widget.transactionPayload != null) {
          // Send the encrypted JSON over the Bluetooth bridge!
          Nearby().sendBytesPayload(
            id,
            Uint8List.fromList(utf8.encode(widget.transactionPayload!)),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Payload Beamed Successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Go back to wallet
        }
      },
      onDisconnected: (id) {},
    );
  }

  // Both devices must accept the connection bridge
  void _onConnectionInit(String endpointId, ConnectionInfo info) {
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) async {
        if (payload.type == PayloadType.BYTES &&
            widget.transactionPayload == null) {
          // I am the receiver and I just caught the payload!
          String jsonStr = utf8.decode(payload.bytes!);
          await _lockPayloadInVault(jsonStr);
        }
      },
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
    );
  }

  // Same logic as our QR Scanner! Lock it in SQLite.
  Future<void> _lockPayloadInVault(String data) async {
    try {
      final Map<String, dynamic> payload = json.decode(data);
      if (payload.containsKey('from') &&
          payload.containsKey('to') &&
          payload.containsKey('amount')) {
        String offlineTxnId =
            "OFF_BEAM_${DateTime.now().millisecondsSinceEpoch}";
        await LocalDatabase.saveOfflineTransaction(
          transactionId: offlineTxnId,
          amount: (payload['amount'] as num).toDouble(),
          sender: payload['from'],
          receiver: payload['to'],
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Success! Offline payment locked in vault."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error catching payload."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isReceiving = widget.transactionPayload == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isReceiving ? "Receiving Mode" : "Select Device to Beam"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isReceiving ? Icons.radar : Icons.wifi_tethering,
              size: 100,
              color: Colors.blueAccent.withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            Text(
              isReceiving
                  ? "Broadcasting your presence..."
                  : "Scanning for nearby wallets...",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
            const SizedBox(height: 40),

            // Only the Sender needs to see the list of discovered devices
            if (!isReceiving) ...[
              const Text(
                "Discovered Devices:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    String endpointId = _discoveredDevices.keys.elementAt(
                      index,
                    );
                    String deviceName = _discoveredDevices[endpointId]!;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.phone_android,
                          color: Colors.blueAccent,
                        ),
                        title: Text(deviceName),
                        subtitle: const Text("Tap to beam OFC offline"),
                        trailing: const Icon(Icons.send, color: Colors.green),
                        onTap: () => _requestConnection(endpointId),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
