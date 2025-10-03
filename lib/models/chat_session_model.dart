import 'dart:convert';

enum ConnectionType { wifiDirect, hotspot, unknown }

enum ChatSessionStatus { active, inactive, archived }

class ChatSession {
  final String id;
  final String deviceId;
  final String deviceName;
  final String? deviceAddress;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final DateTime? lastConnectionAt;
  final int messageCount;
  final int unreadCount;
  final List<ConnectionType> connectionHistory;
  final ChatSessionStatus status;
  final Map<String, dynamic>? metadata;

  ChatSession({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    this.deviceAddress,
    required this.createdAt,
    required this.lastMessageAt,
    this.lastConnectionAt,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.connectionHistory = const [],
    this.status = ChatSessionStatus.active,
    this.metadata,
  });

  static String generateSessionId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'chat_${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Generate session ID using display names instead of device IDs
  static String generateSessionIdFromNames(String userName1, String userName2) {
    final sortedNames = [userName1.toLowerCase().trim(), userName2.toLowerCase().trim()]..sort();
    return 'chat_${sortedNames[0]}_${sortedNames[1]}';
  }

  /// Generate session ID for a peer using current user's name
  static String generateSessionIdForPeer(String currentUserName, String peerUserName) {
    return generateSessionIdFromNames(currentUserName, peerUserName);
  }

  bool get isOnline =>
      lastConnectionAt != null &&
      DateTime.now().difference(lastConnectionAt!).inMinutes < 5;

  ConnectionType? get lastConnectionType =>
      connectionHistory.isNotEmpty ? connectionHistory.last : null;

  String get displayName => deviceName.isNotEmpty ? deviceName : deviceId;

  String get lastSeenText {
    if (isOnline) return 'Online';
    if (lastConnectionAt == null) return 'Never connected';

    final difference = DateTime.now().difference(lastConnectionAt!);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'device_name': deviceName,
      'device_address': deviceAddress,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_message_at': lastMessageAt.millisecondsSinceEpoch,
      'last_connection_at': lastConnectionAt?.millisecondsSinceEpoch,
      'message_count': messageCount,
      'unread_count': unreadCount,
      'connection_history': jsonEncode(
        connectionHistory.map((e) => e.index).toList(),
      ),
      'status': status.index,
      'metadata': metadata != null ? jsonEncode(metadata!) : null,
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'] ?? '',
      deviceId: map['device_id'] ?? '',
      deviceName: map['device_name'] ?? '',
      deviceAddress: map['device_address'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] ?? 0),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
        map['last_message_at'] ?? 0,
      ),
      lastConnectionAt: map['last_connection_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_connection_at'])
          : null,
      messageCount: map['message_count'] ?? 0,
      unreadCount: map['unread_count'] ?? 0,
      connectionHistory: map['connection_history'] != null
          ? (jsonDecode(map['connection_history']) as List)
                .map((index) => ConnectionType.values[index])
                .toList()
          : [],
      status: map['status'] != null
          ? ChatSessionStatus.values[map['status']]
          : ChatSessionStatus.active,
      metadata: map['metadata'] != null ? jsonDecode(map['metadata']) : null,
    );
  }

  ChatSession copyWith({
    String? id,
    String? deviceId,
    String? deviceName,
    String? deviceAddress,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    DateTime? lastConnectionAt,
    int? messageCount,
    int? unreadCount,
    List<ConnectionType>? connectionHistory,
    ChatSessionStatus? status,
    Map<String, dynamic>? metadata,
  }) {
    return ChatSession(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastConnectionAt: lastConnectionAt ?? this.lastConnectionAt,
      messageCount: messageCount ?? this.messageCount,
      unreadCount: unreadCount ?? this.unreadCount,
      connectionHistory: connectionHistory ?? this.connectionHistory,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'ChatSession(id: $id, deviceId: $deviceId, deviceName: $deviceName, '
        'messageCount: $messageCount, unreadCount: $unreadCount, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatSession && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class ChatSessionSummary {
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final ConnectionType? connectionType;

  ChatSessionSummary({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.connectionType,
  });

  String get timeDisplay {
    if (lastMessageTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(lastMessageTime!);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d';

    return '${lastMessageTime!.day}/${lastMessageTime!.month}';
  }

  String get connectionStatusText {
    if (isOnline) {
      return connectionType != null ? connectionType!.displayName : 'Connected';
    }
    return 'Offline';
  }
}

extension ConnectionTypeExtension on ConnectionType {
  String get displayName {
    switch (this) {
      case ConnectionType.wifiDirect:
        return 'WiFi Direct';
      case ConnectionType.hotspot:
        return 'Hotspot';
      case ConnectionType.unknown:
        return 'Unknown';
    }
  }

  String get iconName {
    switch (this) {
      case ConnectionType.wifiDirect:
        return 'wifi_direct';
      case ConnectionType.hotspot:
        return 'wifi_tethering';
      case ConnectionType.unknown:
        return 'device_unknown';
    }
  }
}
