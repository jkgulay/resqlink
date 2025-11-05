import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/map_service.dart';
import 'location_preview_modal.dart';

class LocationMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? senderName;
  final bool isEmergency;

  const LocationMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.senderName,
    this.isEmergency = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEmergency ? ResQLinkTheme.primaryRed : Colors.blue,
          width: 2,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(latitude, longitude),
              initialZoom: 15.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              // CRITICAL FIX: Use PhilippinesMapService for offline map support
              // This allows maps to load even when offline if tiles are cached
              PhilippinesMapService.instance.getTileLayer(
                useOffline: !PhilippinesMapService.instance.isOnline,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(latitude, longitude),
                    width: 40,
                    height: 40,
                    child: Icon(
                      isEmergency ? Icons.warning : Icons.location_on,
                      color: isEmergency
                          ? ResQLinkTheme.primaryRed
                          : Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Overlay with coordinates info
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black.withValues(alpha: 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (senderName != null)
                    Text(
                      senderName!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          // "Open in Maps" button
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openInMaps(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Open',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openInMaps(BuildContext context) {
    // Open inline modal with the full map preview instead of navigating
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocationPreviewModal(
        latitude: latitude,
        longitude: longitude,
        senderName: senderName,
        isEmergency: isEmergency,
      ),
    );
  }
}
