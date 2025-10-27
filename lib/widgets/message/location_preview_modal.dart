import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/map_service.dart';

class LocationPreviewModal extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? senderName;
  final bool isEmergency;

  const LocationPreviewModal({
    super.key,
    required this.latitude,
    required this.longitude,
    this.senderName,
    this.isEmergency = false,
  });

  @override
  Widget build(BuildContext context) {
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
                initialCenter: LatLng(latitude, longitude),
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
                      point: LatLng(latitude, longitude),
                      width: 48,
                      height: 48,
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
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }
}
