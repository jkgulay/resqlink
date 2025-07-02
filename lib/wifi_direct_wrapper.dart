import 'dart:typed_data'; // Add this import
import 'package:nearby_connections/nearby_connections.dart';

class NearbyWrapper {
  static const Strategy strategy = Strategy.P2P_CLUSTER;
  static const String serviceId = "com.example.resqlink.emergency";

  final Nearby _nearby = Nearby();

  Future<bool> startDiscovery({
    required void Function(String, String, String) onEndpointFound,
    required void Function(String) onEndpointLost,
  }) async {
    return _nearby.startDiscovery(
      serviceId,
      strategy,
      onEndpointFound:
          (String endpointId, String endpointName, String serviceId) {
            onEndpointFound(endpointId, endpointName, serviceId);
          },
      onEndpointLost: onEndpointLost as dynamic, 
    );
  }

  Future<bool> startAdvertising(
    String userName, {
    required void Function(String, ConnectionInfo) onConnectionInitiated,
    required void Function(String, Status) onConnectionResult,
    required void Function(String) onDisconnected,
  }) async {
    return _nearby.startAdvertising(
      userName,
      strategy,
      onConnectionInitiated: onConnectionInitiated,
      onConnectionResult: onConnectionResult,
      onDisconnected: onDisconnected,
      serviceId: serviceId,
    );
  }

  Future<bool> requestConnection(
    String userName,
    String endpointId, {
    required void Function(String, ConnectionInfo) onConnectionInitiated,
    required void Function(String, Status) onConnectionResult,
    required void Function(String) onDisconnected,
  }) async {
    return _nearby.requestConnection(
      userName,
      endpointId,
      onConnectionInitiated: onConnectionInitiated,
      onConnectionResult: onConnectionResult,
      onDisconnected: onDisconnected,
    );
  }

  Future<void> acceptConnection(
    String endpointId, {
    required void Function(String, Payload) onPayloadReceived,
  }) async {
    _nearby.acceptConnection(endpointId, onPayLoadRecieved: onPayloadReceived);
  }

  // Fixed: Convert List<int> to Uint8List
  Future<void> sendBytesPayload(String endpointId, List<int> bytes) async {
    await _nearby.sendBytesPayload(endpointId, Uint8List.fromList(bytes));
  }

  Future<void> stopAdvertising() async {
    await _nearby.stopAdvertising();
  }

  Future<void> stopDiscovery() async {
    await _nearby.stopDiscovery();
  }

  Future<void> stopAllEndpoints() async {
    await _nearby.stopAllEndpoints();
  }
}
