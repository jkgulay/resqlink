import 'package:flutter/material.dart';
import 'connection_quality_monitor.dart';

/// Device priority score
class DevicePriority {
  final String deviceId;
  final double score;
  final int rank;
  final DevicePriorityFactors factors;

  DevicePriority({
    required this.deviceId,
    required this.score,
    required this.rank,
    required this.factors,
  });

  @override
  String toString() => 'Priority(rank: $rank, score: ${score.toStringAsFixed(2)})';
}

/// Factors contributing to device priority
class DevicePriorityFactors {
  final bool isEmergency;
  final int signalStrength;
  final double? rtt;
  final double? packetLoss;
  final ConnectionQualityLevel? connectionQuality;
  final DateTime lastSeen;
  final bool isPreviouslyConnected;
  final int messageCount;

  DevicePriorityFactors({
    required this.isEmergency,
    required this.signalStrength,
    this.rtt,
    this.packetLoss,
    this.connectionQuality,
    required this.lastSeen,
    required this.isPreviouslyConnected,
    required this.messageCount,
  });

  Map<String, dynamic> toJson() => {
        'isEmergency': isEmergency,
        'signalStrength': signalStrength,
        'rtt': rtt,
        'packetLoss': packetLoss,
        'connectionQuality': connectionQuality?.name,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'isPreviouslyConnected': isPreviouslyConnected,
        'messageCount': messageCount,
      };
}

/// Manages device prioritization for connection decisions
class DevicePrioritization {
  // Scoring weights (total should be 100)
  static const double emergencyWeight = 40.0;
  static const double signalWeight = 20.0;
  static const double qualityWeight = 20.0;
  static const double recencyWeight = 10.0;
  static const double historyWeight = 10.0;

  /// Calculate priority score for a device
  double calculatePriorityScore(DevicePriorityFactors factors) {
    double score = 0.0;

    // Emergency devices get highest priority (0-40 points)
    if (factors.isEmergency) {
      score += emergencyWeight;
    }

    // Signal strength (0-20 points)
    // Convert dBm (-100 to 0) to 0-20 scale
    final signalScore = ((factors.signalStrength + 100) / 100) * signalWeight;
    score += signalScore.clamp(0, signalWeight);

    // Connection quality (0-20 points)
    if (factors.connectionQuality != null) {
      final qualityScore = _getQualityScore(factors.connectionQuality!);
      score += qualityScore * qualityWeight;
    } else if (factors.rtt != null && factors.packetLoss != null) {
      // Calculate quality from RTT and packet loss if quality level not available
      final rttScore = _getRttScore(factors.rtt!);
      final lossScore = _getPacketLossScore(factors.packetLoss!);
      score += ((rttScore + lossScore) / 2) * qualityWeight;
    }

    // Recency (0-10 points)
    final recencyScore = _getRecencyScore(factors.lastSeen);
    score += recencyScore * recencyWeight;

    // History/familiarity (0-10 points)
    final historyScore = _getHistoryScore(
      factors.isPreviouslyConnected,
      factors.messageCount,
    );
    score += historyScore * historyWeight;

    return score.clamp(0, 100);
  }

  /// Get quality score from connection quality level (0-1)
  double _getQualityScore(ConnectionQualityLevel level) {
    switch (level) {
      case ConnectionQualityLevel.excellent:
        return 1.0;
      case ConnectionQualityLevel.good:
        return 0.8;
      case ConnectionQualityLevel.fair:
        return 0.6;
      case ConnectionQualityLevel.poor:
        return 0.3;
      case ConnectionQualityLevel.critical:
        return 0.1;
    }
  }

  /// Get RTT score (0-1, lower RTT is better)
  double _getRttScore(double rtt) {
    if (rtt < 50) return 1.0;
    if (rtt < 100) return 0.9;
    if (rtt < 150) return 0.8;
    if (rtt < 200) return 0.6;
    if (rtt < 300) return 0.4;
    if (rtt < 500) return 0.2;
    return 0.1;
  }

  /// Get packet loss score (0-1, lower loss is better)
  double _getPacketLossScore(double packetLoss) {
    if (packetLoss == 0) return 1.0;
    if (packetLoss < 5) return 0.8;
    if (packetLoss < 10) return 0.6;
    if (packetLoss < 20) return 0.4;
    if (packetLoss < 30) return 0.2;
    return 0.1;
  }

  /// Get recency score (0-1, more recent is better)
  double _getRecencyScore(DateTime lastSeen) {
    final age = DateTime.now().difference(lastSeen);

    if (age.inSeconds < 10) return 1.0;
    if (age.inSeconds < 30) return 0.9;
    if (age.inMinutes < 1) return 0.8;
    if (age.inMinutes < 5) return 0.6;
    if (age.inMinutes < 15) return 0.4;
    if (age.inMinutes < 30) return 0.2;
    return 0.1;
  }

  /// Get history score (0-1, based on previous interactions)
  double _getHistoryScore(bool isPreviouslyConnected, int messageCount) {
    double score = 0.0;

    // Previously connected devices get bonus
    if (isPreviouslyConnected) {
      score += 0.5;
    }

    // More message history means more established connection
    if (messageCount > 100) {
      score += 0.5;
    } else if (messageCount > 50) {
      score += 0.4;
    } else if (messageCount > 20) {
      score += 0.3;
    } else if (messageCount > 5) {
      score += 0.2;
    } else if (messageCount > 0) {
      score += 0.1;
    }

    return score.clamp(0, 1);
  }

  /// Prioritize a list of devices
  List<DevicePriority> prioritizeDevices(
    Map<String, DevicePriorityFactors> devices,
  ) {
    if (devices.isEmpty) return [];

    debugPrint('🎯 Prioritizing ${devices.length} devices...');

    // Calculate scores for all devices
    final scored = devices.entries.map((entry) {
      final score = calculatePriorityScore(entry.value);
      return {
        'deviceId': entry.key,
        'score': score,
        'factors': entry.value,
      };
    }).toList();

    // Sort by score (highest first)
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // Create priority list with ranks
    final priorities = scored.asMap().entries.map((entry) {
      return DevicePriority(
        deviceId: entry.value['deviceId'] as String,
        score: entry.value['score'] as double,
        rank: entry.key + 1,
        factors: entry.value['factors'] as DevicePriorityFactors,
      );
    }).toList();

    // Log priorities
    for (final priority in priorities.take(5)) {
      debugPrint(
        '  ${priority.rank}. ${priority.deviceId}: ${priority.score.toStringAsFixed(1)} '
        '${priority.factors.isEmergency ? "🚨" : ""}',
      );
    }

    return priorities;
  }

  /// Get highest priority device
  String? getHighestPriorityDevice(
    Map<String, DevicePriorityFactors> devices,
  ) {
    final priorities = prioritizeDevices(devices);
    return priorities.isNotEmpty ? priorities.first.deviceId : null;
  }

  /// Get top N priority devices
  List<String> getTopPriorityDevices(
    Map<String, DevicePriorityFactors> devices,
    int count,
  ) {
    final priorities = prioritizeDevices(devices);
    return priorities.take(count).map((p) => p.deviceId).toList();
  }

  /// Filter devices by minimum priority score
  List<String> filterByMinimumPriority(
    Map<String, DevicePriorityFactors> devices,
    double minScore,
  ) {
    final priorities = prioritizeDevices(devices);
    return priorities
        .where((p) => p.score >= minScore)
        .map((p) => p.deviceId)
        .toList();
  }

  /// Get emergency devices (sorted by priority)
  List<String> getEmergencyDevices(
    Map<String, DevicePriorityFactors> devices,
  ) {
    final emergencyDevices = Map<String, DevicePriorityFactors>.fromEntries(
      devices.entries.where((e) => e.value.isEmergency),
    );

    return prioritizeDevices(emergencyDevices).map((p) => p.deviceId).toList();
  }

  /// Compare two devices and return which should be prioritized
  String compareDevices(
    String deviceId1,
    DevicePriorityFactors factors1,
    String deviceId2,
    DevicePriorityFactors factors2,
  ) {
    final score1 = calculatePriorityScore(factors1);
    final score2 = calculatePriorityScore(factors2);

    debugPrint(
      '⚖️ Comparing devices: $deviceId1 (${score1.toStringAsFixed(1)}) vs '
      '$deviceId2 (${score2.toStringAsFixed(1)})',
    );

    return score1 >= score2 ? deviceId1 : deviceId2;
  }

  /// Get prioritization explanation for a device
  String explainPriority(DevicePriorityFactors factors) {
    final score = calculatePriorityScore(factors);
    final breakdown = <String>[];

    if (factors.isEmergency) {
      breakdown.add('🚨 Emergency (+${emergencyWeight.toInt()}pts)');
    }

    final signalScore =
        ((factors.signalStrength + 100) / 100 * signalWeight).round();
    breakdown.add('📶 Signal: ${factors.signalStrength}dBm (+${signalScore}pts)');

    if (factors.connectionQuality != null) {
      final qualityScore =
          (_getQualityScore(factors.connectionQuality!) * qualityWeight).round();
      breakdown.add(
        '✨ Quality: ${factors.connectionQuality!.name} (+${qualityScore}pts)',
      );
    }

    if (factors.rtt != null) {
      breakdown.add('⚡ RTT: ${factors.rtt!.toStringAsFixed(0)}ms');
    }

    final age = DateTime.now().difference(factors.lastSeen);
    breakdown.add('🕐 Last seen: ${_formatDuration(age)} ago');

    if (factors.isPreviouslyConnected) {
      breakdown.add('🔗 Previously connected');
    }

    if (factors.messageCount > 0) {
      breakdown.add('💬 ${factors.messageCount} messages');
    }

    return 'Score: ${score.toStringAsFixed(1)}/100\n${breakdown.join("\n")}';
  }

  /// Format duration in human-readable form
  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inHours}h';
    }
  }
}
