import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/message_model.dart';
import '../../services/audio/voice_recorder_service.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String, MessageType) onSendMessage;
  final VoidCallback onSendLocation;
  final Function(String) onTyping;
  final bool enabled;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onSendLocation,
    required this.onTyping,
    required this.enabled,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final VoiceRecorderService _voiceRecorder = VoiceRecorderService();
  bool _isRecording = false;
  int _recordingSeconds = 0;

  @override
  void dispose() {
    _voiceRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceRecording() async {
    if (!widget.enabled) return;

    if (_isRecording) {
      // Stop recording and send
      setState(() => _isRecording = false);

      final result = await _voiceRecorder.stopRecording();
      if (result != null) {
        // Encode voice data as JSON string in message
        final voiceData = {
          'audioData': result['audioData'],
          'duration': result['duration'],
          'format': result['format'] ?? 'm4a',
        };
        final voiceMessage = voiceData.toString();

        debugPrint('🎤 Sending voice message (${result['duration']}s)');
        widget.onSendMessage(voiceMessage, MessageType.voice);
      }
    } else {
      // Start recording
      final started = await _voiceRecorder.startRecording();
      if (started) {
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });

        // Update recording duration every second
        _updateRecordingDuration();
      }
    }
  }

  Future<void> _cancelRecording() async {
    await _voiceRecorder.cancelRecording();
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
  }

  void _updateRecordingDuration() {
    if (!_isRecording) return;

    Future.delayed(Duration(seconds: 1), () {
      if (mounted && _isRecording) {
        setState(() {
          _recordingSeconds = _voiceRecorder.recordingDuration;
        });
        _updateRecordingDuration();
      }
    });
  }

  String _formatRecordingTime() {
    final minutes = _recordingSeconds ~/ 60;
    final seconds = _recordingSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 400;

    // Recording mode UI
    if (_isRecording) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 12 : 16,
          vertical: isNarrow ? 12 : 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.95),
              Color(0xFF1E3E62).withValues(alpha: 0.95),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            top: BorderSide(
              color: Color(0xFFFF6500).withValues(alpha: 0.5),
              width: 2,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // Cancel button
              IconButton(
                icon: Icon(Icons.close, color: Colors.red),
                onPressed: _cancelRecording,
                tooltip: 'Cancel',
              ),
              // Recording indicator
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      color: Colors.red,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Recording ${_formatRecordingTime()}',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Send button
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A9EFF), Color(0xFF6BB8FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF4A9EFF).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _toggleVoiceRecording,
                  tooltip: 'Send voice message',
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal input mode UI
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 16,
        vertical: isNarrow ? 12 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B192C).withValues(alpha: 0.95),
            Color(0xFF1E3E62).withValues(alpha: 0.95),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: Color(0xFFFF6500).withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Location button
            Container(
              margin: EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: widget.enabled
                    ? Color(0xFF4A9EFF).withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.enabled
                      ? Color(0xFF4A9EFF).withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.my_location,
                  color: widget.enabled ? Color(0xFF4A9EFF) : Colors.grey,
                  size: isNarrow ? 20 : 22,
                ),
                onPressed: widget.enabled ? widget.onSendLocation : null,
                tooltip: 'Share GPS Location',
                constraints: BoxConstraints(
                  minWidth: isNarrow ? 40 : 44,
                  minHeight: isNarrow ? 40 : 44,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
            SizedBox(width: 8),
            // Text input
            Expanded(
              child: Container(
                constraints: BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Color(0xFF1E3E62).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: widget.enabled
                        ? Color(0xFFFF6500).withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  onChanged: widget.enabled ? widget.onTyping : null,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    hintText: widget.enabled
                        ? 'Type a message...'
                        : 'Device offline',
                    hintStyle: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: isNarrow ? 14 : 15,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: isNarrow ? 14 : 15,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            SizedBox(width: 8),
            // Microphone button (changes to send when typing)
            Container(
              margin: EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                gradient:
                    widget.enabled && widget.controller.text.trim().isEmpty
                    ? LinearGradient(
                        colors: [Color(0xFF4A9EFF), Color(0xFF6BB8FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : (widget.enabled
                          ? LinearGradient(
                              colors: [Color(0xFFFF6500), Color(0xFFFF8533)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null),
                color: widget.enabled
                    ? null
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                boxShadow: widget.enabled
                    ? [
                        BoxShadow(
                          color:
                              (widget.controller.text.trim().isEmpty
                                      ? Color(0xFF4A9EFF)
                                      : Color(0xFFFF6500))
                                  .withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: IconButton(
                icon: Icon(
                  widget.controller.text.trim().isEmpty
                      ? Icons.mic
                      : Icons.send_rounded,
                  color: Colors.white,
                  size: isNarrow ? 20 : 22,
                ),
                onPressed: widget.enabled
                    ? () {
                        final text = widget.controller.text.trim();
                        if (text.isNotEmpty) {
                          widget.onSendMessage(text, MessageType.text);
                          widget.controller.clear();
                        } else {
                          _toggleVoiceRecording();
                        }
                      }
                    : null,
                tooltip: widget.controller.text.trim().isEmpty
                    ? 'Record voice message'
                    : 'Send message',
                constraints: BoxConstraints(
                  minWidth: isNarrow ? 40 : 44,
                  minHeight: isNarrow ? 40 : 44,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
