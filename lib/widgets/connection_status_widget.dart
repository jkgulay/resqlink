import 'dart:async';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectionStatusWidget extends StatefulWidget {
  const ConnectionStatusWidget({super.key});

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  late Stream<List<ConnectivityResult>> _connectivityStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();

    _connectivityStream = Connectivity().onConnectivityChanged;
    _connectivitySubscription = _connectivityStream.listen((
      List<ConnectivityResult> results,
    ) {
      if (mounted) {
        setState(() {
          isConnected = results.any(
            (result) => result != ConnectivityResult.none,
          );
        });
      }
    });
  }

  Future<void> _checkConnection() async {
    final List<ConnectivityResult> connectivityResult = await Connectivity()
        .checkConnectivity();
    if (mounted) {
      setState(() {
        isConnected = connectivityResult.any(
          (result) => result != ConnectivityResult.none,
        );
      });
    }
  }

    @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withAlpha(26)
            : Colors.red.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            size: 16,
            color: isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              color: isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
