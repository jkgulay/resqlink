import 'package:flutter/material.dart';
import '../gps_page.dart';

class LocationStatusCard extends StatelessWidget {
  final LocationModel? location;
  final bool isLoading;
  final int unsyncedCount;
  final VoidCallback onRefresh;
  final VoidCallback onShare;

  const LocationStatusCard({
    super.key,
    required this.location,
    required this.isLoading,
    required this.unsyncedCount,
    required this.onRefresh,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (location == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.location_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No location data available',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: Icon(Icons.refresh),
                label: Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.08),
              Color(0xFF1E3A5F).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;
              return _buildLocationContent(context, isNarrow);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLocationContent(BuildContext context, bool isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildLocationHeader(isNarrow),
        SizedBox(height: 24),
        
        // Location details
        _buildLocationDetails(isNarrow),
        SizedBox(height: 24),
        
        // Action buttons
        _buildActionButtons(isNarrow),
      ],
    );
  }

  Widget _buildLocationHeader(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Color(0xFF1E3A5F).withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isNarrow ? 14 : 16),
            decoration: BoxDecoration(
              color: (location!.type == LocationType.emergency ||
                      location!.type == LocationType.sos)
                  ? Colors.red.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (location!.type == LocationType.emergency ||
                        location!.type == LocationType.sos)
                    ? Colors.red
                    : Colors.blue,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: ((location!.type == LocationType.emergency ||
                              location!.type == LocationType.sos)
                          ? Colors.red
                          : Colors.blue)
                      .withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              location!.type == LocationType.emergency ||
                      location!.type == LocationType.sos
                  ? Icons.emergency_share
                  : Icons.location_on,
              color: location!.type == LocationType.emergency ||
                      location!.type == LocationType.sos
                  ? Colors.red
                  : Colors.blue,
              size: isNarrow ? 26 : 30,
            ),
          ),
          SizedBox(width: isNarrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Known Location',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isNarrow ? 18 : 20,
                    color: Color.fromARGB(255, 252, 254, 255),
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: (location!.type == LocationType.emergency ||
                                location!.type == LocationType.sos)
                            ? Colors.red
                            : Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: ((location!.type == LocationType.emergency ||
                                        location!.type == LocationType.sos)
                                    ? Colors.red
                                    : Colors.green)
                                .withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (location!.type == LocationType.emergency ||
                                location!.type == LocationType.sos)
                            ? 'Emergency Location Active'
                            : 'Location Available',
                        style: TextStyle(
                          color: (location!.type == LocationType.emergency ||
                                  location!.type == LocationType.sos)
                              ? Colors.red
                              : Colors.green,
                          fontSize: isNarrow ? 13 : 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (unsyncedCount > 0)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 10 : 12,
                vertical: isNarrow ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$unsyncedCount unsynced',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: isNarrow ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationDetails(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 105, 107, 109).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(0xFF1E3A5F).withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0B192C).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLocationRow(
            Icons.my_location,
            "Latitude",
            location!.latitude.toStringAsFixed(6),
            isNarrow,
          ),
          SizedBox(height: 16),
          _buildLocationRow(
            Icons.my_location,
            "Longitude",
            location!.longitude.toStringAsFixed(6),
            isNarrow,
          ),
          SizedBox(height: 16),
          _buildLocationRow(
            Icons.schedule,
            "Timestamp",
            _formatDateTime(location!.timestamp),
            isNarrow,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
    IconData icon,
    String label,
    String value,
    bool isNarrow,
  ) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: isNarrow ? 16 : 18, color: Colors.blue),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isNarrow ? 12 : 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: Color.fromARGB(255, 252, 254, 255),
                  fontSize: isNarrow ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isNarrow) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF0B192C).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              icon: Icon(Icons.refresh, size: isNarrow ? 16 : 18),
              label: Text(
                'Refresh',
                style: TextStyle(
                  fontSize: isNarrow ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onRefresh,
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [Color(0xFFFF6500), Color(0xFFFF8533)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFFFF6500).withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              icon: Icon(Icons.share, size: isNarrow ? 16 : 18),
              label: Text(
                'Share',
                style: TextStyle(
                  fontSize: isNarrow ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onShare,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return dateTime.toString().substring(0, 19);
    }
  }
}