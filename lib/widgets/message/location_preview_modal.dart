import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/map_service.dart';
import 'shared_location_markers.dart';

class LocationPreviewModal extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? senderName;
  final bool isEmergency;
  final double? userLatitude;
  final double? userLongitude;
  final double? distanceMeters;

  const LocationPreviewModal({
    super.key,
    required this.latitude,
    required this.longitude,
    this.senderName,
    this.isEmergency = false,
    this.userLatitude,
    this.userLongitude,
    this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    final hasUserLocation = userLatitude != null && userLongitude != null;
    final LatLng senderLatLng = LatLng(latitude, longitude);
    final LatLng? userLatLng = hasUserLocation
        ? LatLng(userLatitude!, userLongitude!)
        : null;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    senderName ?? 'Shared Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          Container(
            height: 420,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEmergency ? ResQLinkTheme.primaryRed : Colors.blue,
                width: 2,
              ),
              color: Colors.black,
            ),
            clipBehavior: Clip.hardEdge,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: senderLatLng,
                initialZoom: 16.0,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                // Use the same cached tiles as the GPS page for offline capability
                PhilippinesMapService.instance.getTileLayer(
                  zoom: 16,
                  useOffline: !PhilippinesMapService.instance.isOnline,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: senderLatLng,
                      width: 90,
                      height: 90,
                      child: SenderLocationMarker(
                        isEmergency: isEmergency,
                        label: senderName,
                      ),
                    ),
                    if (userLatLng != null)
                      Marker(
                        point: userLatLng,
                        width: 80,
                        height: 80,
                        child: const UserLocationMarker(),
                      ),
                  ],
                ),
                if (userLatLng != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [senderLatLng, userLatLng],
                        color: Colors.white.withValues(alpha: 0.7),
                        strokeWidth: 3.5,
                        borderColor: Colors.black54,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (userLatLng != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _LegendDot(
                        color: isEmergency
                            ? ResQLinkTheme.primaryRed
                            : Colors.deepPurple,
                        label: 'Sender',
                      ),
                      const SizedBox(width: 12),
                      const _LegendDot(color: Colors.blueAccent, label: 'You'),
                    ],
                  ),
                  Text(
                    _formatDistance(distanceMeters),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 12),
        ],
      ),
    );
  }

  static String _formatDistance(double? meters) {
    if (meters == null) return '--';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km apart';
    }
    return '${meters.toStringAsFixed(0)} m apart';
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
