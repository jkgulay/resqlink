import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus { pending, sent, delivered, failed, synced }
enum MessageType { text, emergency, location, sos, system, file }

class MessageModel {
  final int? id;
  final String endpointId;
  final String fromUser;
  final String message;
  final bool isMe;
  final bool isEmergency;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final bool synced;
  final bool syncedToFirebase;
  final String? messageId;
  final String type;
  final MessageStatus status;
  final List<String>? routePath;
  final int? ttl;
  final String? connectionType;
  final Map<String, dynamic>? deviceInfo;
  final String? targetDeviceId;
  final MessageType messageType;
  final String? chatSessionId;

  MessageModel({
    this.id,
    required this.endpointId,
    required this.fromUser,
    required this.message,
    required this.isMe,
    required this.isEmergency,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.synced = false,
    this.syncedToFirebase = false,
    this.messageId,
    String? type,
    this.status = MessageStatus.pending,
    this.routePath,
    this.ttl,
    this.connectionType,
    this.deviceInfo,
    this.targetDeviceId,
    MessageType? messageType,
    this.chatSessionId,
  }) : type = type ?? (isEmergency ? 'emergency' : 'message'),
       messageType = messageType ?? (isEmergency ? MessageType.emergency : MessageType.text);

  // DateTime getter for convenience
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  // Check if message has location
  bool get hasLocation => latitude != null && longitude != null;

  // Get message priority (for sorting/display)
  int get priority {
    if (type == 'sos') return 3;
    if (type == 'emergency' || isEmergency) return 2;
    if (type == 'location') return 1;
    return 0;
  }

  // copyWith method for immutability
  MessageModel copyWith({
    int? id,
    String? endpointId,
    String? fromUser,
    String? message,
    bool? isMe,
    bool? isEmergency,
    int? timestamp,
    double? latitude,
    double? longitude,
    bool? synced,
    bool? syncedToFirebase,
    String? messageId,
    String? type,
    MessageStatus? status,
    List<String>? routePath,
    int? ttl,
    String? connectionType,
    Map<String, dynamic>? deviceInfo,
    String? targetDeviceId,
    MessageType? messageType,
    String? chatSessionId,
  }) {
    return MessageModel(
      id: id ?? this.id,
      endpointId: endpointId ?? this.endpointId,
      fromUser: fromUser ?? this.fromUser,
      message: message ?? this.message,
      isMe: isMe ?? this.isMe,
      isEmergency: isEmergency ?? this.isEmergency,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      synced: synced ?? this.synced,
      syncedToFirebase: syncedToFirebase ?? this.syncedToFirebase,
      messageId: messageId ?? this.messageId,
      type: type ?? this.type,
      status: status ?? this.status,
      routePath: routePath ?? this.routePath,
      ttl: ttl ?? this.ttl,
      connectionType: connectionType ?? this.connectionType,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      messageType: messageType ?? this.messageType,
      chatSessionId: chatSessionId ?? this.chatSessionId,
    );
  }

  // Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'endpoint_id': endpointId,
      'from_user': fromUser,
      'message': message,
      'is_me': isMe ? 1 : 0,
      'is_emergency': isEmergency ? 1 : 0,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'synced': synced ? 1 : 0,
      'synced_to_firebase': syncedToFirebase ? 1 : 0,
      'message_id': messageId,
      'type': type,
      'status': status.index,
      'route_path': routePath?.join(','),
      'ttl': ttl,
      'connection_type': connectionType,
      'device_info': deviceInfo != null ? jsonEncode(deviceInfo!) : null,
      'target_device_id': targetDeviceId,
      'message_type': messageType.index,
      'chat_session_id': chatSessionId,
    };
  }

  // Create from database Map
  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      endpointId: map['endpoint_id'] ?? '',
      fromUser: map['from_user'] ?? '',
      message: map['message'] ?? '',
      isMe: map['is_me'] == 1,
      isEmergency: map['is_emergency'] == 1,
      timestamp: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      synced: map['synced'] == 1,
      syncedToFirebase: map['synced_to_firebase'] == 1,
      messageId: map['message_id'],
      type: map['type'] ?? 'message',
      status: map['status'] != null
          ? MessageStatus.values[map['status']]
          : MessageStatus.pending,
      routePath: map['route_path'] != null
          ? (map['route_path'] as String).split(',')
          : null,
      ttl: map['ttl'],
      connectionType: map['connection_type'],
      deviceInfo: map['device_info'] != null
          ? jsonDecode(map['device_info'])
          : null,
      targetDeviceId: map['target_device_id'],
      messageType: map['message_type'] != null
          ? MessageType.values[map['message_type']]
          : MessageType.text,
      chatSessionId: map['chat_session_id'],
    );
  }

  // Create from enhanced database Map
  factory MessageModel.fromDatabase(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      endpointId: map['endpointId'] ?? '',
      fromUser: map['fromUser'] ?? '',
      message: map['message'] ?? '',
      isMe: map['isMe'] == 1,
      isEmergency: map['isEmergency'] == 1,
      timestamp: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      synced: map['synced'] == 1,
      syncedToFirebase: map['syncedToFirebase'] == 1,
      messageId: map['messageId'],
      type: map['type'] ?? 'message',
      status: map['status'] is String
          ? MessageStatus.values.firstWhere(
              (e) => e.name == map['status'],
              orElse: () => MessageStatus.pending,
            )
          : MessageStatus.pending,
      routePath: map['routePath'] != null
          ? List<String>.from(jsonDecode(map['routePath']))
          : null,
      ttl: map['ttl'],
      connectionType: map['connectionType'],
      deviceInfo: map['deviceInfo'] != null
          ? jsonDecode(map['deviceInfo'])
          : null,
      targetDeviceId: map['targetDeviceId'],
      messageType: map['messageType'] is String
          ? MessageType.values.firstWhere(
              (e) => e.name == map['messageType'],
              orElse: () => MessageType.text,
            )
          : MessageType.text,
      chatSessionId: map['chatSessionId'],
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebaseJson() {
    return {
      'endpointId': endpointId,
      'fromUser': fromUser,
      'message': message,
      'isEmergency': isEmergency,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'messageId': messageId ?? '${endpointId}_$timestamp',
      'status': status.name,
      'routePath': routePath,
      'ttl': ttl,
      'connectionType': connectionType,
      'deviceInfo': deviceInfo,
    };
  }

  // Convert to Firebase document
  Map<String, dynamic> toFirebase() {
    return {
      'endpointId': endpointId,
      'fromUser': fromUser,
      'message': message,
      'isEmergency': isEmergency,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'messageId': messageId ?? '${endpointId}_$timestamp',
      'status': status.name,
      'routePath': routePath,
      'ttl': ttl,
      'connectionType': connectionType,
      'deviceInfo': deviceInfo,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  String toString() {
    return 'MessageModel(id: $id, endpointId: $endpointId, fromUser: $fromUser, '
        'message: $message, isMe: $isMe, isEmergency: $isEmergency, '
        'timestamp: $timestamp, latitude: $latitude, longitude: $longitude, '
        'synced: $synced, syncedToFirebase: $syncedToFirebase, '
        'messageId: $messageId, type: $type, status: $status, '
        'routePath: $routePath, ttl: $ttl, connectionType: $connectionType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel &&
        other.messageId == messageId &&
        other.endpointId == endpointId &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return messageId.hashCode ^ endpointId.hashCode ^ timestamp.hashCode;
  }

  // Network transmission methods
  Map<String, dynamic> toNetworkJson() {
    return {
      'messageId': messageId ?? '${endpointId}_$timestamp',
      'endpointId': endpointId,
      'fromUser': fromUser,
      'message': message,
      'isMe': isMe,
      'isEmergency': isEmergency,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'messageType': messageType.name,
      'status': status.name,
      'routePath': routePath,
      'ttl': ttl,
      'targetDeviceId': targetDeviceId,
      'connectionType': connectionType,
      'deviceInfo': deviceInfo,
    };
  }

  factory MessageModel.fromNetworkJson(Map<String, dynamic> json) {
    return MessageModel(
      messageId: json['messageId'],
      endpointId: json['endpointId'] ?? '',
      fromUser: json['fromUser'] ?? '',
      message: json['message'] ?? '',
      isMe: json['isMe'] ?? false,
      isEmergency: json['isEmergency'] ?? false,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      type: json['type'] ?? 'message',
      messageType: json['messageType'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == json['messageType'],
              orElse: () => MessageType.text,
            )
          : MessageType.text,
      status: json['status'] != null
          ? MessageStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => MessageStatus.pending,
            )
          : MessageStatus.pending,
      routePath: json['routePath'] != null
          ? List<String>.from(json['routePath'])
          : null,
      ttl: json['ttl'],
      targetDeviceId: json['targetDeviceId'],
      connectionType: json['connectionType'],
      deviceInfo: json['deviceInfo'],
    );
  }

  // Generate unique message ID
  static String generateMessageId(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode;
    return 'msg_${timestamp}_${deviceId.hashCode}_$random';
  }

  // Create a broadcast message (no specific target)
  static MessageModel createBroadcastMessage({
    required String fromUser,
    required String message,
    required String deviceId,
    MessageType type = MessageType.text,
    bool isEmergency = false,
    double? latitude,
    double? longitude,
  }) {
    return MessageModel(
      messageId: generateMessageId(deviceId),
      endpointId: 'broadcast',
      fromUser: fromUser,
      message: message,
      isMe: true,
      isEmergency: isEmergency,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: latitude,
      longitude: longitude,
      messageType: type,
      type: type.name,
      ttl: 5,
      routePath: [deviceId],
    );
  }

  // Create a direct message to specific device
  static MessageModel createDirectMessage({
    required String fromUser,
    required String message,
    required String deviceId,
    required String targetDeviceId,
    MessageType type = MessageType.text,
    bool isEmergency = false,
    double? latitude,
    double? longitude,
  }) {
    return MessageModel(
      messageId: generateMessageId(deviceId),
      endpointId: targetDeviceId,
      targetDeviceId: targetDeviceId,
      fromUser: fromUser,
      message: message,
      isMe: true,
      isEmergency: isEmergency,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: latitude,
      longitude: longitude,
      messageType: type,
      type: type.name,
      ttl: 5,
      routePath: [deviceId],
    );
  }
}

/// Represents a pending message for P2P communication
class PendingMessage {
  final String messageId;
  final String targetDeviceId;
  final String message;
  final DateTime timestamp;
  final MessageType type;
  final int retryCount;
  final Map<String, dynamic>? metadata;

  PendingMessage({
    required this.messageId,
    required this.targetDeviceId,
    required this.message,
    required this.timestamp,
    required this.type,
    this.retryCount = 0,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'targetDeviceId': targetDeviceId,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.name,
      'retryCount': retryCount,
      'metadata': metadata,
    };
  }

  factory PendingMessage.fromJson(Map<String, dynamic> json) {
    return PendingMessage(
      messageId: json['messageId'],
      targetDeviceId: json['targetDeviceId'],
      message: json['message'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      retryCount: json['retryCount'] ?? 0,
      metadata: json['metadata'],
    );
  }

  PendingMessage copyWith({
    String? messageId,
    String? targetDeviceId,
    String? message,
    DateTime? timestamp,
    MessageType? type,
    int? retryCount,
    Map<String, dynamic>? metadata,
  }) {
    return PendingMessage(
      messageId: messageId ?? this.messageId,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      retryCount: retryCount ?? this.retryCount,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Represents a P2P message for database operations
class P2PMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final MessageType type;
  final DateTime timestamp;
  final bool isEmergency;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic>? metadata;

  P2PMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isEmergency = false,
    this.latitude,
    this.longitude,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isEmergency': isEmergency,
      'latitude': latitude,
      'longitude': longitude,
      'metadata': metadata,
    };
  }

  factory P2PMessage.fromJson(Map<String, dynamic> json) {
    return P2PMessage(
      id: json['id'],
      senderId: json['senderId'],
      senderName: json['senderName'],
      message: json['message'],
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      isEmergency: json['isEmergency'] ?? false,
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      metadata: json['metadata'],
    );
  }
}