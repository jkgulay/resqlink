import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for recording voice messages and encoding them to Base64
/// for transmission through WiFi Direct
///
/// Platform Support: Android only (WiFi Direct limitation)
class VoiceRecorderService {
  static final VoiceRecorderService _instance =
      VoiceRecorderService._internal();
  factory VoiceRecorderService() => _instance;
  VoiceRecorderService._internal();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  /// Initialize the recorder
  Future<void> _initializeRecorder() async {
    if (_isInitialized) return;

    try {
      await _recorder.openRecorder();
      _isInitialized = true;
      debugPrint('🎤 FlutterSoundRecorder initialized');
    } catch (e) {
      debugPrint('❌ Error initializing recorder: $e');
    }
  }

  /// Check if microphone permission is granted
  Future<bool> checkMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      debugPrint('🎤 Microphone permission status: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('❌ Error checking microphone permission: $e');
      return false;
    }
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      debugPrint('🎤 Microphone permission requested: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('❌ Error requesting microphone permission: $e');
      return false;
    }
  }

  /// Start recording audio
  Future<bool> startRecording() async {
    try {
      // Initialize if not already done
      await _initializeRecorder();

      // Check permission first
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        final granted = await requestMicrophonePermission();
        if (!granted) {
          debugPrint('❌ Microphone permission denied');
          return false;
        }
      }

      // Check if already recording
      if (_isRecording) {
        debugPrint('⚠️ Already recording');
        return false;
      }

      // Create temporary file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/voice_$timestamp.aac';

      debugPrint('🎤 Starting recording to: $_currentRecordingPath');

      // Start recording with optimized settings for WiFi Direct
      await _recorder.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacMP4, // AAC for better compression
        sampleRate: 16000, // 16kHz sufficient for voice
        bitRate: 32000, // 32kbps for smaller file size
        numChannels: 1, // Mono for voice
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      debugPrint('✅ Recording started');
      return true;
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return false;
    }
  }

  /// Stop recording and return Base64 encoded audio with metadata
  Future<Map<String, dynamic>?> stopRecording() async {
    try {
      if (!_isRecording) {
        debugPrint('⚠️ Not currently recording');
        return null;
      }

      debugPrint('🎤 Stopping recording...');
      final path = await _recorder.stopRecorder();

      if (path == null || path.isEmpty) {
        debugPrint('❌ Recording path is null or empty');
        _isRecording = false;
        return null;
      }

      _isRecording = false;
      final recordingDuration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0;

      debugPrint('✅ Recording stopped. Duration: ${recordingDuration}s');
      debugPrint('   File path: $path');

      // Read the audio file
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('❌ Recording file does not exist');
        return null;
      }

      final fileSize = await file.length();
      debugPrint(
        '📊 Recording file size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
      );

      // Encode to Base64
      debugPrint('🔄 Encoding audio to Base64...');
      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);

      debugPrint('✅ Audio encoded. Base64 length: ${base64Audio.length} chars');
      debugPrint(
        '   Estimated transmission size: ${(base64Audio.length / 1024).toStringAsFixed(2)} KB',
      );

      // Clean up the temporary file
      try {
        await file.delete();
        debugPrint('🧹 Temporary recording file deleted');
      } catch (e) {
        debugPrint('⚠️ Failed to delete temporary file: $e');
      }

      return {
        'audioData': base64Audio,
        'duration': recordingDuration,
        'format': 'aac',
        'sampleRate': 16000,
        'bitRate': 32000,
        'channels': 1,
        'fileSize': fileSize,
      };
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        debugPrint('🎤 Cancelling recording...');
        await _recorder.stopRecorder();

        // Delete the temporary file
        if (_currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            await file.delete();
            debugPrint('🧹 Cancelled recording file deleted');
          }
        }
      }

      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      debugPrint('✅ Recording cancelled');
    } catch (e) {
      debugPrint('❌ Error cancelling recording: $e');
      _isRecording = false;
    }
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get recording duration in seconds
  int get recordingDuration {
    if (_recordingStartTime == null) return 0;
    return DateTime.now().difference(_recordingStartTime!).inSeconds;
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      if (_isRecording) {
        await cancelRecording();
      }
      if (_isInitialized) {
        await _recorder.closeRecorder();
        _isInitialized = false;
      }
      debugPrint('🧹 VoiceRecorderService disposed');
    } catch (e) {
      debugPrint('❌ Error disposing VoiceRecorderService: $e');
    }
  }
}
