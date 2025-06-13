import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart';

class GpsPage extends StatefulWidget {
  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage> {
  final List<LatLng> savedLocations = [];

  void _saveLocation(TapPosition tapPosition, LatLng latLng) {
    setState(() {
      savedLocations.add(latLng);
    });
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('GPS Offline Map')),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(37.4219983, -122.084),
          zoom: 13.0,
          onLongPress: _saveLocation,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: [
              for (final point in savedLocations)
                Marker(
                  width: 80,
                  height: 80,
                  point: point,
                  rotate: false,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
