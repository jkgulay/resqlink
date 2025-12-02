import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_state_service.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/map_service.dart';
import 'location_preview_modal.dart';
import 'shared_location_markers.dart';

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
    final currentLocation = LocationStateService().currentLocation;
    final LatLng? myLatLng = currentLocation != null
        ? LatLng(currentLocation.latitude, currentLocation.longitude)
        : null;
    final LatLng senderLatLng = LatLng(latitude, longitude);
    final Distance distanceCalculator = const Distance();
    final double? distanceMeters = myLatLng != null
        ? distanceCalculator.as(LengthUnit.Meter, senderLatLng, myLatLng)
        : null;

    final markers = <Marker>[
      Marker(
        point: senderLatLng,
        width: 90,
        height: 90,
        child: SenderLocationMarker(
          isEmergency: isEmergency,
          label: senderName,
        ),
      ),
      if (myLatLng != null)
        Marker(
          point: myLatLng,
          width: 80,
          height: 80,
          child: const UserLocationMarker(),
        ),
    ];

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
              initialCenter: senderLatLng,
              initialZoom: 15.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              PhilippinesMapService.instance.getTileLayer(
                useOffline: !PhilippinesMapService.instance.isOnline,
              ),
              MarkerLayer(markers: markers),
              if (myLatLng != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [senderLatLng, myLatLng],
                      color: Colors.white.withValues(alpha: 0.6),
                      strokeWidth: 3,
                      borderColor: Colors.black.withValues(alpha: 0.3),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (myLatLng != null) ...[
                  _LegendPill(
                    distanceText: _formatDistance(distanceMeters),
                    senderColor: isEmergency
                        ? ResQLinkTheme.primaryRed
                        : Colors.deepPurple,
                    userColor: Colors.blueAccent,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
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
                  if (myLatLng != null) ...[
                    SizedBox(height: 2),
                    Text(
                      'You: ${myLatLng.latitude.toStringAsFixed(6)}, ${myLatLng.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                    if (distanceMeters != null)
                      Text(
                        'Distance apart: ${_formatDistance(distanceMeters)}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openInMaps(
                  context,
                  myLatLng?.latitude,
                  myLatLng?.longitude,
                  distanceMeters,
                ),
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

  void _openInMaps(
    BuildContext context,
    double? myLatitude,
    double? myLongitude,
    double? distanceMeters,
  ) {
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
        userLatitude: myLatitude,
        userLongitude: myLongitude,
        distanceMeters: distanceMeters,
      ),
    );
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '--';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }
}

class _LegendPill extends StatelessWidget {
  final String distanceText;
  final Color senderColor;
  final Color userColor;

  const _LegendPill({
    required this.distanceText,
    required this.senderColor,
    required this.userColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: senderColor, label: 'Sender'),
          SizedBox(width: 8),
          _LegendDot(color: userColor, label: 'You'),
          SizedBox(width: 8),
          Text(
            distanceText,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
