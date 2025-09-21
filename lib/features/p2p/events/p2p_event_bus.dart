import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../models/message_model.dart';

/// Events for P2P communication
abstract class P2PEvent {
  final DateTime timestamp;
  P2PEvent() : timestamp = DateTime.now();
}

/// Device connection events
class DeviceConnectionEvent extends P2PEvent {
  final String deviceId;
  final String deviceName;
  final String connectionType;
  final Map<String, dynamic>? deviceInfo;

  DeviceConnectionEvent({
    required this.deviceId,
    required this.deviceName,
    required this.connectionType,
    this.deviceInfo,
  });

  @override
  String toString() => 'DeviceConnectionEvent(deviceId: $deviceId, name: $deviceName, type: $connectionType)';
}

/// Device disconnection events
class DeviceDisconnectionEvent extends P2PEvent {
  final String deviceId;
  final String? reason;

  DeviceDisconnectionEvent({
    required this.deviceId,
    this.reason,
  });

  @override
  String toString() => 'DeviceDisconnectionEvent(deviceId: $deviceId, reason: $reason)';
}

/// Message received events
class MessageReceivedEvent extends P2PEvent {
  final MessageModel message;
  final String fromDeviceId;

  MessageReceivedEvent({
    required this.message,
    required this.fromDeviceId,
  });

  @override
  String toString() => 'MessageReceivedEvent(from: $fromDeviceId, type: ${message.messageType})';
}

/// Message send status events
class MessageSendStatusEvent extends P2PEvent {
  final String messageId;
  final MessageStatus status;
  final String? error;

  MessageSendStatusEvent({
    required this.messageId,
    required this.status,
    this.error,
  });

  @override
  String toString() => 'MessageSendStatusEvent(messageId: $messageId, status: $status)';
}

/// Device discovery events
class DeviceDiscoveryEvent extends P2PEvent {
  final String deviceId;
  final String deviceName;
  final Map<String, dynamic> deviceInfo;
  final bool isAvailable;

  DeviceDiscoveryEvent({
    required this.deviceId,
    required this.deviceName,
    required this.deviceInfo,
    required this.isAvailable,
  });

  @override
  String toString() => 'DeviceDiscoveryEvent(deviceId: $deviceId, available: $isAvailable)';
}

/// Connection status change events
class ConnectionStatusEvent extends P2PEvent {
  final bool isConnected;
  final String? connectionType;
  final List<String> connectedDevices;

  ConnectionStatusEvent({
    required this.isConnected,
    this.connectionType,
    required this.connectedDevices,
  });

  @override
  String toString() => 'ConnectionStatusEvent(connected: $isConnected, devices: ${connectedDevices.length})';
}

/// Error events
class P2PErrorEvent extends P2PEvent {
  final String error;
  final String operation;
  final Map<String, dynamic>? context;

  P2PErrorEvent({
    required this.error,
    required this.operation,
    this.context,
  });

  @override
  String toString() => 'P2PErrorEvent(operation: $operation, error: $error)';
}

/// Event bus for P2P communication
class P2PEventBus {
  static final P2PEventBus _instance = P2PEventBus._internal();
  factory P2PEventBus() => _instance;
  P2PEventBus._internal();

  // Event stream controllers
  final _deviceConnectedController = StreamController<DeviceConnectionEvent>.broadcast();
  final _deviceDisconnectedController = StreamController<DeviceDisconnectionEvent>.broadcast();
  final _messageReceivedController = StreamController<MessageReceivedEvent>.broadcast();
  final _messageSendStatusController = StreamController<MessageSendStatusEvent>.broadcast();
  final _deviceDiscoveryController = StreamController<DeviceDiscoveryEvent>.broadcast();
  final _connectionStatusController = StreamController<ConnectionStatusEvent>.broadcast();
  final _errorController = StreamController<P2PErrorEvent>.broadcast();
  final _allEventsController = StreamController<P2PEvent>.broadcast();

  // Event streams
  Stream<DeviceConnectionEvent> get onDeviceConnected => _deviceConnectedController.stream;
  Stream<DeviceDisconnectionEvent> get onDeviceDisconnected => _deviceDisconnectedController.stream;
  Stream<MessageReceivedEvent> get onMessageReceived => _messageReceivedController.stream;
  Stream<MessageSendStatusEvent> get onMessageSendStatus => _messageSendStatusController.stream;
  Stream<DeviceDiscoveryEvent> get onDeviceDiscovery => _deviceDiscoveryController.stream;
  Stream<ConnectionStatusEvent> get onConnectionStatus => _connectionStatusController.stream;
  Stream<P2PErrorEvent> get onError => _errorController.stream;
  Stream<P2PEvent> get onAllEvents => _allEventsController.stream;

  // Event emission methods
  void emitDeviceConnected({
    required String deviceId,
    required String deviceName,
    required String connectionType,
    Map<String, dynamic>? deviceInfo,
  }) {
    final event = DeviceConnectionEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      connectionType: connectionType,
      deviceInfo: deviceInfo,
    );

    _deviceConnectedController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitDeviceDisconnected({
    required String deviceId,
    String? reason,
  }) {
    final event = DeviceDisconnectionEvent(
      deviceId: deviceId,
      reason: reason,
    );

    _deviceDisconnectedController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitMessageReceived({
    required MessageModel message,
    required String fromDeviceId,
  }) {
    final event = MessageReceivedEvent(
      message: message,
      fromDeviceId: fromDeviceId,
    );

    _messageReceivedController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitMessageSendStatus({
    required String messageId,
    required MessageStatus status,
    String? error,
  }) {
    final event = MessageSendStatusEvent(
      messageId: messageId,
      status: status,
      error: error,
    );

    _messageSendStatusController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitDeviceDiscovery({
    required String deviceId,
    required String deviceName,
    required Map<String, dynamic> deviceInfo,
    required bool isAvailable,
  }) {
    final event = DeviceDiscoveryEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceInfo: deviceInfo,
      isAvailable: isAvailable,
    );

    _deviceDiscoveryController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitConnectionStatus({
    required bool isConnected,
    String? connectionType,
    required List<String> connectedDevices,
  }) {
    final event = ConnectionStatusEvent(
      isConnected: isConnected,
      connectionType: connectionType,
      connectedDevices: connectedDevices,
    );

    _connectionStatusController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Event: $event');
  }

  void emitError({
    required String error,
    required String operation,
    Map<String, dynamic>? context,
  }) {
    final event = P2PErrorEvent(
      error: error,
      operation: operation,
      context: context,
    );

    _errorController.add(event);
    _allEventsController.add(event);
    debugPrint('📡 Error Event: $event');
  }

  // Subscription helper methods
  StreamSubscription<DeviceConnectionEvent> onDeviceConnectedListen(
    void Function(DeviceConnectionEvent) onData
  ) {
    return onDeviceConnected.listen(onData);
  }

  StreamSubscription<DeviceDisconnectionEvent> onDeviceDisconnectedListen(
    void Function(DeviceDisconnectionEvent) onData
  ) {
    return onDeviceDisconnected.listen(onData);
  }

  StreamSubscription<MessageReceivedEvent> onMessageReceivedListen(
    void Function(MessageReceivedEvent) onData
  ) {
    return onMessageReceived.listen(onData);
  }

  StreamSubscription<MessageSendStatusEvent> onMessageSendStatusListen(
    void Function(MessageSendStatusEvent) onData
  ) {
    return onMessageSendStatus.listen(onData);
  }

  StreamSubscription<DeviceDiscoveryEvent> onDeviceDiscoveryListen(
    void Function(DeviceDiscoveryEvent) onData
  ) {
    return onDeviceDiscovery.listen(onData);
  }

  StreamSubscription<ConnectionStatusEvent> onConnectionStatusListen(
    void Function(ConnectionStatusEvent) onData
  ) {
    return onConnectionStatus.listen(onData);
  }

  StreamSubscription<P2PErrorEvent> onErrorListen(
    void Function(P2PErrorEvent) onData
  ) {
    return onError.listen(onData);
  }

  // Filtered event streams
  Stream<MessageReceivedEvent> getMessagesForDevice(String deviceId) {
    return onMessageReceived.where((event) => event.fromDeviceId == deviceId);
  }

  Stream<DeviceConnectionEvent> getConnectionsForDevice(String deviceId) {
    return onDeviceConnected.where((event) => event.deviceId == deviceId);
  }

  Stream<P2PErrorEvent> getErrorsForOperation(String operation) {
    return onError.where((event) => event.operation == operation);
  }

  // Event history (last N events)
  final List<P2PEvent> _eventHistory = [];

  List<P2PEvent> getEventHistory({int? limit}) {
    if (limit == null) return List.from(_eventHistory);
    final startIndex = (_eventHistory.length - limit).clamp(0, _eventHistory.length);
    return _eventHistory.sublist(startIndex);
  }

  List<T> getEventHistoryOfType<T extends P2PEvent>({int? limit}) {
    final filteredEvents = _eventHistory.whereType<T>().toList();
    if (limit == null) return filteredEvents;
    final startIndex = (filteredEvents.length - limit).clamp(0, filteredEvents.length);
    return filteredEvents.sublist(startIndex);
  }

  // Statistics
  Map<String, int> getEventStats() {
    final stats = <String, int>{};
    for (final event in _eventHistory) {
      final type = event.runtimeType.toString();
      stats[type] = (stats[type] ?? 0) + 1;
    }
    return stats;
  }

  // Cleanup
  void dispose() {
    _deviceConnectedController.close();
    _deviceDisconnectedController.close();
    _messageReceivedController.close();
    _messageSendStatusController.close();
    _deviceDiscoveryController.close();
    _connectionStatusController.close();
    _errorController.close();
    _allEventsController.close();
    _eventHistory.clear();
    debugPrint('📡 P2P Event Bus disposed');
  }

  // Debug helpers
  void logEventStats() {
    final stats = getEventStats();
    debugPrint('📊 P2P Event Stats: $stats');
  }

  void clearHistory() {
    _eventHistory.clear();
    debugPrint('🧹 P2P Event history cleared');
  }
}