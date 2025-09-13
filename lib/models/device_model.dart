import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceModel {
  final String id;
  final String deviceId;
  final String userName;
  final String? ssid;
  final String? psk;
  final bool isHost;
  final bool isOnline;
  final DateTime lastSeen;
  final DateTime createdAt;
  final Map<String, dynamic>? deviceInfo;
  final GeoPoint? lastLocation;
  final int messageCount;
  final List<String>? capabilities;

  // Add these new properties for P2P compatibility
  final String? deviceAddress;
  final bool isConnected;
  final String? discoveryMethod;

  DeviceModel({
    required this.id,
    required this.deviceId,
    required this.userName,
    this.ssid,
    this.psk,
    required this.isHost,
    required this.isOnline,
    required this.lastSeen,
    required this.createdAt,
    this.deviceInfo,
    this.lastLocation,
    this.messageCount = 0,
    this.capabilities,
    this.deviceAddress, // Add this
    this.isConnected = false, // Add this
    this.discoveryMethod, // Add this
  });

  /// Create from Firestore document
  factory DeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeviceModel(
      id: doc.id,
      deviceId: data['deviceId'] ?? '',
      userName: data['userName'] ?? '',
      ssid: data['ssid'],
      psk: data['psk'],
      isHost: data['isHost'] ?? false,
      isOnline: data['isOnline'] ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deviceInfo: data['deviceInfo'],
      lastLocation: data['lastLocation'],
      messageCount: data['messageCount'] ?? 0,
      capabilities: data['capabilities'] != null
          ? List<String>.from(data['capabilities'])
          : null,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'deviceId': deviceId,
      'userName': userName,
      'ssid': ssid,
      'psk': psk,
      'isHost': isHost,
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': createdAt,
      'deviceInfo': deviceInfo,
      'lastLocation': lastLocation,
      'messageCount': messageCount,
      'capabilities': capabilities,
    };
  }

  /// Create from JSON (for local storage)
  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      userName: json['userName'] ?? '',
      ssid: json['ssid'],
      psk: json['psk'],
      isHost: json['isHost'] ?? false,
      isOnline: json['isOnline'] ?? false,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] ?? 0),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] ?? 0),
      deviceInfo: json['deviceInfo'],
      lastLocation: json['lastLocation'] != null
          ? GeoPoint(
              json['lastLocation']['latitude'],
              json['lastLocation']['longitude'],
            )
          : null,
      messageCount: json['messageCount'] ?? 0,
      capabilities: json['capabilities'] != null
          ? List<String>.from(json['capabilities'])
          : null,
    );
  }

  /// Convert to JSON (for local storage)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'userName': userName,
      'ssid': ssid,
      'psk': psk,
      'isHost': isHost,
      'isOnline': isOnline,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'deviceInfo': deviceInfo,
      'lastLocation': lastLocation != null
          ? {
              'latitude': lastLocation!.latitude,
              'longitude': lastLocation!.longitude,
            }
          : null,
      'messageCount': messageCount,
      'capabilities': capabilities,
    };
  }

  DeviceModel copyWith({
    String? id,
    String? deviceId,
    String? userName,
    String? ssid,
    String? psk,
    bool? isHost,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? createdAt,
    Map<String, dynamic>? deviceInfo,
    GeoPoint? lastLocation,
    int? messageCount,
    List<String>? capabilities,
    String? deviceAddress, 
    bool? isConnected, 
    String? discoveryMethod, 
  }) {
    return DeviceModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      userName: userName ?? this.userName,
      ssid: ssid ?? this.ssid,
      psk: psk ?? this.psk,
      isHost: isHost ?? this.isHost,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      lastLocation: lastLocation ?? this.lastLocation,
      messageCount: messageCount ?? this.messageCount,
      capabilities: capabilities ?? this.capabilities,
      deviceAddress: deviceAddress ?? this.deviceAddress, 
      isConnected: isConnected ?? this.isConnected, 
      discoveryMethod: discoveryMethod ?? this.discoveryMethod, 
    );
  }

  @override
  String toString() {
    return 'DeviceModel(id: $id, deviceId: $deviceId, userName: $userName, isHost: $isHost, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceModel && other.deviceId == deviceId;
  }

  @override
  int get hashCode => deviceId.hashCode;
}

/// Represents a device's network status
class DeviceNetworkStatus {
  final String deviceId;
  final bool isConnected;
  final int signalStrength;
  final String? ipAddress;
  final DateTime lastPing;

  DeviceNetworkStatus({
    required this.deviceId,
    required this.isConnected,
    required this.signalStrength,
    this.ipAddress,
    required this.lastPing,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'isConnected': isConnected,
      'signalStrength': signalStrength,
      'ipAddress': ipAddress,
      'lastPing': lastPing.millisecondsSinceEpoch,
    };
  }

  factory DeviceNetworkStatus.fromJson(Map<String, dynamic> json) {
    return DeviceNetworkStatus(
      deviceId: json['deviceId'],
      isConnected: json['isConnected'],
      signalStrength: json['signalStrength'],
      ipAddress: json['ipAddress'],
      lastPing: DateTime.fromMillisecondsSinceEpoch(json['lastPing']),
    );
  }
}

/// Represents device capabilities
class DeviceCapabilities {
  static const String bluetooth = 'bluetooth';
  static const String wifi = 'wifi';
  static const String wifiDirect = 'wifi_direct';
  static const String ble = 'ble';
  static const String location = 'location';
  static const String storage = 'storage';
  static const String camera = 'camera';
  static const String microphone = 'microphone';

  static List<String> getAllCapabilities() {
    return [
      bluetooth,
      wifi,
      wifiDirect,
      ble,
      location,
      storage,
      camera,
      microphone,
    ];
  }
}

/// Device role in the P2P network
enum DeviceRole { none, host, client, relay }

/// Extension methods for DeviceRole
extension DeviceRoleExtension on DeviceRole {
  String get displayName {
    switch (this) {
      case DeviceRole.none:
        return 'Not Connected';
      case DeviceRole.host:
        return 'Group Host';
      case DeviceRole.client:
        return 'Connected';
      case DeviceRole.relay:
        return 'Relay Node';
    }
  }

  bool get canCreateGroup =>
      this == DeviceRole.none || this == DeviceRole.client;
  bool get canRelay => this == DeviceRole.host || this == DeviceRole.relay;
}

/// Device credentials for P2P connections
class DeviceCredentials {
  final String deviceId;
  final String? ssid;
  final String? psk;
  final bool isHost;
  final DateTime lastSeen;

  DeviceCredentials({
    required this.deviceId,
    this.ssid,
    this.psk,
    required this.isHost,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'ssid': ssid,
      'psk': psk,
      'isHost': isHost,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
    };
  }

  factory DeviceCredentials.fromJson(Map<String, dynamic> json) {
    return DeviceCredentials(
      deviceId: json['deviceId'],
      ssid: json['ssid'],
      psk: json['psk'],
      isHost: json['isHost'] ?? false,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] ?? 0),
    );
  }
}
