import 'package:flutter/material.dart';
import '../../utils/resqlink_theme.dart';

/// Reusable "my location" marker that mirrors the GPS page styling.
class UserLocationMarker extends StatelessWidget {
  final bool isSosMode;

  const UserLocationMarker({super.key, this.isSosMode = false});

  @override
  Widget build(BuildContext context) {
    final Color baseColor = isSosMode
        ? ResQLinkTheme.primaryRed
        : Colors.blueAccent;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseColor.withValues(alpha: 0.25),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseColor,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isSosMode ? Icons.emergency : Icons.my_location,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marker used for the sender/peer locations shared inside chat messages.
class SenderLocationMarker extends StatelessWidget {
  final bool isEmergency;
  final String? label;

  const SenderLocationMarker({super.key, this.isEmergency = false, this.label});

  @override
  Widget build(BuildContext context) {
    final Color baseColor = isEmergency
        ? ResQLinkTheme.primaryRed
        : Colors.deepPurple;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: 0.2),
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  isEmergency ? Icons.warning_amber_rounded : Icons.place,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
        if (label != null && label!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              label!.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
