import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus { pending, sent, delivered, failed, synced }

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
  }) : type = type ?? (isEmergency ? 'emergency' : 'message');

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
}