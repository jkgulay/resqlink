import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/settings_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('📱 Initializing NotificationService...');

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final initialized = await _notifications.initialize(initSettings);
    debugPrint('📱 Notification plugin initialized: $initialized');

    // Request permissions for Android 13+ (POST_NOTIFICATIONS)
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      debugPrint('📱 Requesting Android notification permissions...');
      final granted = await androidImplementation
          .requestNotificationsPermission();
      debugPrint('📱 Android notification permission granted: $granted');

      // Check if we can show exact alarms
      final canSchedule = await androidImplementation
          .canScheduleExactNotifications();
      debugPrint('📱 Can schedule exact notifications: $canSchedule');
    }

    // Request permissions for iOS
    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    if (iosImplementation != null) {
      debugPrint('📱 Requesting iOS notification permissions...');
      final granted = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('📱 iOS notification permission granted: $granted');
    }

    _initialized = true;
    debugPrint('✅ NotificationService initialized and permissions requested');
  }

  /// Show emergency notification (SOS, trapped, medical, etc.)
  static Future<void> showEmergencyNotification({
    required String title,
    required String body,
    String? sender,
  }) async {
    debugPrint('🚨 showEmergencyNotification called:');
    debugPrint('   Title: $title');
    debugPrint('   Body: $body');
    debugPrint('   Sender: $sender');

    final settings = SettingsService.instance;
    debugPrint(
      '   Emergency notifications enabled: ${settings.emergencyNotifications}',
    );
    debugPrint('   Sound enabled: ${settings.soundNotifications}');
    debugPrint('   Vibration enabled: ${settings.vibrationNotifications}');
    debugPrint('   Silent mode: ${settings.silentMode}');

    // Check if emergency notifications are enabled
    if (!settings.emergencyNotifications) {
      debugPrint('🔕 Emergency notifications disabled in settings');
      return;
    }

    // Play sound if enabled
    if (settings.soundNotifications && !settings.silentMode) {
      try {
        debugPrint('🔊 Playing emergency sound...');
        await _player.stop(); // Stop any previous sounds
        await _player.setSource(AssetSource('sounds/emergency_alert.mp3'));
        await _player.setVolume(1.0);
        await _player.resume();
        debugPrint('✅ Emergency sound played');
      } catch (e) {
        debugPrint('❌ Error playing emergency sound: $e');
      }
    }

    // Vibrate if enabled
    if (settings.vibrationNotifications && !settings.silentMode) {
      try {
        debugPrint('📳 Vibrating...');
        final hasVibrator = await Vibration.hasVibrator();
        debugPrint('   Has vibrator: $hasVibrator');
        if (hasVibrator == true) {
          await Vibration.vibrate(
            pattern: [0, 500, 200, 500, 200, 1000],
            intensities: [0, 255, 0, 255, 0, 255],
          );
          debugPrint('✅ Vibration executed');
        }
      } catch (e) {
        debugPrint('❌ Error vibrating: $e');
      }
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        'emergency_channel',
        'Emergency Alerts',
        channelDescription: 'Emergency notifications from nearby users',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false, // Handled manually above
        enableVibration: false, // Handled manually above
        styleInformation: BigTextStyleInformation(body),
        color: ResQLinkTheme.primaryRed,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false, // Handled manually above
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );
      debugPrint('📢 Showing notification with ID: $notificationId');

      await _notifications.show(notificationId, title, body, details);

      debugPrint('✅ Emergency notification shown successfully');
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
    }
  }

  /// Show regular message notification
  static Future<void> showMessageNotification({
    required String title,
    required String body,
    String? sender,
  }) async {
    debugPrint('💬 showMessageNotification called:');
    debugPrint('   Title: $title');
    debugPrint('   Body: $body');
    debugPrint('   Sender: $sender');

    final settings = SettingsService.instance;
    debugPrint('   Sound enabled: ${settings.soundNotifications}');
    debugPrint('   Vibration enabled: ${settings.vibrationNotifications}');
    debugPrint('   Silent mode: ${settings.silentMode}');

    // Check if in silent mode
    if (settings.silentMode) {
      debugPrint('🔕 Silent mode enabled, notification suppressed');
      return;
    }

    // Play sound if enabled
    if (settings.soundNotifications) {
      try {
        debugPrint('🔊 Playing message sound...');
        await _player.stop(); // Stop any previous sounds
        await _player.setSource(AssetSource('sounds/message_received.mp3'));
        await _player.setVolume(1.0);
        await _player.resume();
        debugPrint('✅ Message sound played');
      } catch (e) {
        debugPrint('❌ Error playing message sound: $e');
      }
    }

    // Vibrate if enabled
    if (settings.vibrationNotifications) {
      try {
        debugPrint('📳 Vibrating...');
        final hasVibrator = await Vibration.hasVibrator();
        debugPrint('   Has vibrator: $hasVibrator');
        if (hasVibrator == true) {
          await Vibration.vibrate(duration: 200);
          debugPrint('✅ Vibration executed');
        }
      } catch (e) {
        debugPrint('❌ Error vibrating: $e');
      }
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        'messages_channel',
        'Messages',
        channelDescription: 'New message notifications',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false, // Handled manually above
        enableVibration: false, // Handled manually above
        styleInformation: BigTextStyleInformation(body),
        color: ResQLinkTheme.primaryBlue,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false, // Handled manually above
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );
      debugPrint('📢 Showing notification with ID: $notificationId');

      await _notifications.show(notificationId, title, body, details);

      debugPrint('✅ Message notification shown successfully');
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
    }
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
