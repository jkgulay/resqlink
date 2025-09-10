class LocationModel {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? userId;
  final LocationType type;
  final String? message;
  final bool synced;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final int? batteryLevel;
  final EmergencyLevel? emergencyLevel;
  final String? source;

  LocationModel({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.userId,
    required this.type,
    this.message,
    required this.synced,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.batteryLevel,
    this.emergencyLevel,
    this.source = 'gps',
  });


  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      id: map['id'],
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      userId: map['userId'] as String?,
      type: _parseLocationType(map['type']),
      message: map['message'] as String?,
      synced: (map['synced'] ?? 0) == 1,
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      batteryLevel: map['batteryLevel'] as int?,
      emergencyLevel: _parseEmergencyLevel(map['emergencyLevel']),
      source: map['source'] as String? ?? 'gps',
    );
  }
  static LocationType _parseLocationType(dynamic type) {
    if (type == null) return LocationType.normal;

    if (type is String) {
      try {
        return LocationType.values.firstWhere(
          (e) => e.toString() == type,
          orElse: () => LocationType.normal,
        );
      } catch (e) {
        return LocationType.normal;
      }
    }

    if (type is int && type >= 0 && type < LocationType.values.length) {
      return LocationType.values[type];
    }

    return LocationType.normal;
  }

  static EmergencyLevel? _parseEmergencyLevel(dynamic level) {
    if (level == null) return null;

    if (level is int && level >= 0 && level < EmergencyLevel.values.length) {
      return EmergencyLevel.values[level];
    }

    return null;
  }

  
Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'userId': userId,
      'type': type.toString(),
      'message': message,
      'synced': synced ? 1 : 0,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'batteryLevel': batteryLevel,
      'emergencyLevel': emergencyLevel?.index,
      'source': source,
    };
  }

  LocationModel copyWith({
    int? id,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? userId,
    LocationType? type,
    String? message,
    bool? synced,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
  }) {
    return LocationModel(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      message: message ?? this.message,
      synced: synced ?? this.synced,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
    );
  }
}

enum LocationType { 
  normal, 
  emergency, 
  sos, 
  safezone, 
  hazard, 
  evacuationPoint, 
  medicalAid, 
  supplies 
}

enum EmergencyLevel { 
  safe, 
  caution, 
  warning, 
  danger, 
  critical 
}