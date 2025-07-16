class MessageModel {
  final int? id;
  final String endpointId;
  final String fromUser;
  final String message;
  final bool isMe;
  final bool isEmergency;
  final int timestamp;
  final double latitude;
  final double longitude;

  MessageModel({
    this.id,
    required this.endpointId,
    required this.fromUser,
    required this.message,
    required this.isMe,
    required this.isEmergency,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });

  // Add a proper type getter if needed
  String get type => isEmergency ? 'emergency' : 'normal';

  // Add a DateTime getter for convenience
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  // Add copyWith method for immutability
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'endpoint_id': endpointId,
      'from_user': fromUser,
      'message': message,
      'is_me': isMe ? 1 : 0,
      'is_emergency': isEmergency ? 1 : 0,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  static MessageModel fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      endpointId: map['endpoint_id'],
      fromUser: map['from_user'],
      message: map['message'],
      isMe: map['is_me'] == 1,
      isEmergency: map['is_emergency'] == 1,
      timestamp: map['timestamp'],
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
    );
  }

  @override
  String toString() {
    return 'MessageModel(id: $id, endpointId: $endpointId, fromUser: $fromUser, message: $message, isMe: $isMe, isEmergency: $isEmergency, timestamp: $timestamp, latitude: $latitude, longitude: $longitude)';
  }
}
