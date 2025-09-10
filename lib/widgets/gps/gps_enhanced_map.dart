import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../gps_page.dart';
import '../../services/map_service.dart';
import '../../utils/resqlink_theme.dart';

// Define the CriticalLocation class
class CriticalLocation {
  final LatLng location;
  final String name;
  final CriticalInfrastructureType type;
  final Color color;
  final IconData icon;
  final String description;

  const CriticalLocation({
    required this.location,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    this.description = '',
  });
}

// Define the infrastructure types
enum CriticalInfrastructureType {
  hospital,
  fireStation,
  policeStation,
  evacuation,
  shelter,
  communications,
  powerPlant,
  waterTreatment,
}

class GpsEnhancedMap extends StatefulWidget {
  final MapController? mapController;
  final Function(LatLng)? onMapTap;
  final Function(LatLng)? onMapLongPress;
  final Function(LocationModel)? onLocationTap;
  final bool showCurrentLocation;
  final bool showSavedLocations;
  final bool showTrackingPath;
  final bool showEmergencyZones;
  final bool showCriticalInfrastructure;

  const GpsEnhancedMap({
    super.key,
    this.mapController,
    this.onMapTap,
    this.onMapLongPress,
    this.onLocationTap,
    this.showCurrentLocation = true,
    this.showSavedLocations = true,
    this.showTrackingPath = true,
    this.showEmergencyZones = false,
    this.showCriticalInfrastructure = false,
  });

  @override
  State<GpsEnhancedMap> createState() => _GpsEnhancedMapState();
}

class _GpsEnhancedMapState extends State<GpsEnhancedMap>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Critical infrastructure data for Philippines
  static const List<CriticalLocation> _criticalInfrastructure = [
    // Hospitals
    CriticalLocation(
      location: LatLng(14.5547, 121.0244),
      name: 'Philippine General Hospital',
      type: CriticalInfrastructureType.hospital,
      color: Colors.red,
      icon: Icons.local_hospital,
      description: 'Major public hospital',
    ),
    CriticalLocation(
      location: LatLng(14.5648, 121.0198),
      name: 'St. Luke\'s Medical Center',
      type: CriticalInfrastructureType.hospital,
      color: Colors.red,
      icon: Icons.local_hospital,
      description: 'Private hospital',
    ),
    
    // Fire Stations
    CriticalLocation(
      location: LatLng(14.5995, 120.9842),
      name: 'Manila Central Fire Station',
      type: CriticalInfrastructureType.fireStation,
      color: Colors.orange,
      icon: Icons.local_fire_department,
      description: 'Central fire station',
    ),
    
    // Police Stations
    CriticalLocation(
      location: LatLng(14.5906, 120.9823),
      name: 'Manila Police District',
      type: CriticalInfrastructureType.policeStation,
      color: Colors.blue,
      icon: Icons.local_police,
      description: 'Main police station',
    ),
    
    // Evacuation Centers
    CriticalLocation(
      location: LatLng(14.6042, 121.0017),
      name: 'Rizal Memorial Sports Complex',
      type: CriticalInfrastructureType.evacuation,
      color: Colors.green,
      icon: Icons.location_city,
      description: 'Evacuation center',
    ),
    
    // Shelters
    CriticalLocation(
      location: LatLng(14.5764, 121.0851),
      name: 'Marikina Sports Center',
      type: CriticalInfrastructureType.shelter,
      color: Colors.purple,
      icon: Icons.home,
      description: 'Emergency shelter',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        return FlutterMap(
          mapController: widget.mapController,
          options: MapOptions(
            initialCenter: controller.currentLocation ?? const LatLng(14.5995, 120.9842),
            initialZoom: controller.currentLocation != null ? 15.0 : 13.0,
            maxZoom: 18.0,
            minZoom: 5.0,
            onTap: (tapPosition, point) => widget.onMapTap?.call(point),
            onLongPress: (tapPosition, point) => widget.onMapLongPress?.call(point),
          ),
          children: [
            _buildTileLayer(controller),
            if (widget.showTrackingPath && controller.savedLocations.length > 1)
              _buildTrackingPath(controller),
            if (widget.showEmergencyZones)
              _buildEmergencyZones(),
            if (widget.showCriticalInfrastructure)
              _buildCriticalInfrastructure(),
            _buildLocationMarkers(controller),
          ],
        );
      },
    );
  }

  Widget _buildTileLayer(GpsController controller) {
    try {
      // Get current zoom level safely
      int currentZoom = 13;
      if (widget.mapController != null) {
        try {
          currentZoom = widget.mapController!.camera.zoom.round();
        } catch (e) {
          // If camera is not ready, use default zoom
          currentZoom = 13;
        }
      }

      // Get tile layer from map service
      return PhilippinesMapService.instance.getTileLayer(
        zoom: currentZoom,
        useOffline: !controller.isConnected,
      );
    } catch (e) {
      debugPrint('❌ Error getting tile layer: $e');
      // Fallback to OpenStreetMap
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.resqlink.app',
        maxZoom: 19,
      );
    }
  }

  Widget _buildTrackingPath(GpsController controller) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: controller.savedLocations
              .take(50)
              .map((loc) => LatLng(loc.latitude, loc.longitude))
              .toList(),
          strokeWidth: 3.0,
          color: ResQLinkTheme.emergencyOrange.withValues(alpha: 0.7),
          pattern: StrokePattern.dashed(segments: [6.0, 4.0]),
        ),
      ],
    );
  }

  Widget _buildEmergencyZones() {
    // Define emergency zones for Philippines
    final List<LatLng> zone1 = [
      const LatLng(14.58, 120.97),
      const LatLng(14.62, 120.97),
      const LatLng(14.62, 121.01),
      const LatLng(14.58, 121.01),
    ];

    return PolygonLayer(
      polygons: [
        Polygon(
          points: zone1,
          color: Colors.red.withValues(alpha: 0.3),
          borderColor: Colors.red,
          borderStrokeWidth: 2.0,
          label: 'High Risk Zone',
          labelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCriticalInfrastructure() {
    return MarkerLayer(
      markers: _criticalInfrastructure.map((infrastructure) {
        return Marker(
          width: 40,
          height: 40,
          point: infrastructure.location,
          child: GestureDetector(
            onTap: () => _showInfrastructureDetails(infrastructure),
            child: Container(
              decoration: BoxDecoration(
                color: infrastructure.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: infrastructure.color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                infrastructure.icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLocationMarkers(GpsController controller) {
    final List<Marker> markers = [];

    // Add current location marker
    if (widget.showCurrentLocation && controller.currentLocation != null) {
      markers.add(
        Marker(
          width: 80,
          height: 80,
          point: controller.currentLocation!,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: controller.sosMode
                            ? ResQLinkTheme.primaryRed.withValues(alpha: 0.3)
                            : Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: controller.sosMode
                      ? ResQLinkTheme.primaryRed
                      : Colors.blue,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: (controller.sosMode
                              ? ResQLinkTheme.primaryRed
                              : Colors.blue)
                          .withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  controller.sosMode ? Icons.emergency : Icons.my_location,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Add saved location markers
    if (widget.showSavedLocations) {
      markers.addAll(
        controller.savedLocations.take(50).map((location) {
          return Marker(
            width: 60,
            height: 60,
            point: LatLng(location.latitude, location.longitude),
            child: GestureDetector(
              onTap: () => widget.onLocationTap?.call(location),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: location.getMarkerColor(),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: location.getMarkerColor().withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  location.getMarkerIcon(),
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          );
        }),
      );
    }

    return MarkerLayer(markers: markers);
  }

  void _showInfrastructureDetails(CriticalLocation infrastructure) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Row(
          children: [
            Icon(infrastructure.icon, color: infrastructure.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                infrastructure.name,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type: ${infrastructure.type.name}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${infrastructure.location.latitude.toStringAsFixed(4)}, ${infrastructure.location.longitude.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white70),
            ),
            if (infrastructure.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                infrastructure.description,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.mapController?.move(infrastructure.location, 16.0);
            },
            child: const Text('Navigate'),
          ),
        ],
      ),
    );
  }
}