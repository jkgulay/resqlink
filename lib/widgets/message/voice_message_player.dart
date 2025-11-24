import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:resqlink/utils/offline_fonts.dart';
import 'package:path_provider/path_provider.dart';

/// Widget for playing voice messages received through WiFi Direct
class VoiceMessagePlayer extends StatefulWidget {
  final String base64Audio;
  final int durationSeconds;
  final bool isMe;
  final String? format;

  const VoiceMessagePlayer({
    super.key,
    required this.base64Audio,
    required this.durationSeconds,
    required this.isMe,
    this.format = 'aac',
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _tempAudioPath;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
    _prepareTempAudioFile();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  Future<void> _prepareTempAudioFile() async {
    try {
      setState(() => _isLoading = true);

      // Decode Base64 to bytes
      final bytes = base64Decode(widget.base64Audio);

      // Create temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _tempAudioPath = '${tempDir.path}/voice_play_$timestamp.${widget.format}';

      final file = File(_tempAudioPath!);
      await file.writeAsBytes(bytes);

      debugPrint('🎵 Prepared voice message for playback: $_tempAudioPath');
      debugPrint('   Size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ Error preparing audio file: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_tempAudioPath == null) {
        debugPrint('⚠️ Audio file not ready');
        return;
      }

      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(DeviceFileSource(_tempAudioPath!));
      }
    } catch (e) {
      debugPrint('❌ Error toggling playback: $e');
    }
  }

  Future<void> _cleanupTempFile() async {
    try {
      if (_tempAudioPath != null) {
        final file = File(_tempAudioPath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('🧹 Cleaned up temporary voice file');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to cleanup temp file: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 400;
    final progress = _totalDuration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    return Container(
      constraints: BoxConstraints(maxWidth: isNarrow ? 240 : 280),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isMe
              ? [
                  Color(0xFFFF6500).withValues(alpha: 0.2),
                  Color(0xFFFF8533).withValues(alpha: 0.15),
                ]
              : [
                  Color(0xFF1E3E62).withValues(alpha: 0.3),
                  Color(0xFF0B192C).withValues(alpha: 0.4),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isMe
              ? Color(0xFFFF6500).withValues(alpha: 0.3)
              : Color(0xFF4A9EFF).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _isLoading ? null : _togglePlayback,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isMe ? Color(0xFFFF6500) : Color(0xFF4A9EFF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (widget.isMe ? Color(0xFFFF6500) : Color(0xFF4A9EFF))
                        .withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: _isLoading
                  ? Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
          SizedBox(width: 10),
          // Waveform/Progress indicator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Voice message',
                      style: OfflineFonts.inter(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                // Progress bar
                Stack(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: widget.isMe
                              ? Color(0xFFFF6500)
                              : Color(0xFF4A9EFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                // Duration
                Text(
                  _isPlaying
                      ? '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}'
                      : _formatDuration(
                          Duration(seconds: widget.durationSeconds),
                        ),
                  style: OfflineFonts.jetBrainsMono(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
