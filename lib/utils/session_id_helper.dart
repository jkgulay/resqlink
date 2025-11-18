class SessionIdHelper {
  static final RegExp _nonAlphanumeric = RegExp(r'[^A-Za-z0-9]');
  static final RegExp _underscores = RegExp(r'_+');

  /// Normalize any device identifier (UUID, MAC, display handle) into a
  /// filesystem-safe token we can embed inside chat session IDs.
  static String sanitizeDeviceId(String? deviceId) {
    if (deviceId == null) {
      return '';
    }

    final trimmed = deviceId.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final replaced = trimmed.replaceAll(_nonAlphanumeric, '_');
    return replaced.replaceAll(_underscores, '_').trim();
  }

  /// Canonical chat session ID builder (`chat_<sanitizedId>`), used across the app.
  static String buildSessionId(String deviceId) {
    final sanitized = sanitizeDeviceId(deviceId);
    if (sanitized.isEmpty) {
      return '';
    }
    return 'chat_$sanitized';
  }

  /// Legacy session IDs that might still exist in the database for the same device.
  /// Used when migrating historical data to the canonical format.
  static List<String> legacySessionIds(String deviceId) {
    final trimmed = deviceId.trim();
    final ids = <String>{
      buildSessionId(deviceId),
      if (trimmed.isNotEmpty) 'chat_$trimmed',
      if (trimmed.isNotEmpty) 'chat_${trimmed.replaceAll(':', '_')}',
    };

    ids.removeWhere((element) => element.isEmpty);
    return ids.toList();
  }
}
