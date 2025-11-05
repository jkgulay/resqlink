import 'package:flutter/material.dart';
import '../../pages/gps_page.dart';

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
    // Show empty state only when no location AND not loading
    if (location == null && !isLoading) {
      return _buildEmptyState();
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

  Widget _buildEmptyState() {
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF0B192C),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationContent(BuildContext context, bool isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with loading indicator if needed
        _buildLocationHeader(isNarrow),
        SizedBox(height: 24),

        // Location details - show loading or actual data
        isLoading
            ? _buildLoadingDetails(isNarrow)
            : _buildLocationDetails(isNarrow),
        SizedBox(height: 24),

        // Action buttons - disable during loading
        _buildActionButtons(context, isNarrow),
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
              color: isLoading
                  ? Colors.grey.withValues(alpha: 0.15)
                  : (location?.type == LocationType.emergency ||
                        location?.type == LocationType.sos)
                  ? Colors.red.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLoading
                    ? Colors.grey
                    : (location?.type == LocationType.emergency ||
                          location?.type == LocationType.sos)
                    ? Colors.red
                    : Colors.blue,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isLoading
                              ? Colors.grey
                              : (location?.type == LocationType.emergency ||
                                    location?.type == LocationType.sos)
                              ? Colors.red
                              : Colors.blue)
                          .withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: isLoading
                ? SizedBox(
                    width: isNarrow ? 26 : 30,
                    height: isNarrow ? 26 : 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  )
                : Icon(
                    location?.type == LocationType.emergency ||
                            location?.type == LocationType.sos
                        ? Icons.emergency_share
                        : Icons.location_on,
                    color:
                        location?.type == LocationType.emergency ||
                            location?.type == LocationType.sos
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
                  isLoading ? 'Refreshing Location...' : 'Last Known Location',
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
                        color: isLoading
                            ? Colors.orange
                            : (location?.type == LocationType.emergency ||
                                  location?.type == LocationType.sos)
                            ? Colors.red
                            : Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (isLoading
                                        ? Colors.orange
                                        : (location?.type ==
                                                  LocationType.emergency ||
                                              location?.type ==
                                                  LocationType.sos)
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
                        isLoading
                            ? 'Updating location data...'
                            : (location?.type == LocationType.emergency ||
                                  location?.type == LocationType.sos)
                            ? 'Emergency Location Active'
                            : 'Location Available',
                        style: TextStyle(
                          color: isLoading
                              ? Colors.orange
                              : (location?.type == LocationType.emergency ||
                                    location?.type == LocationType.sos)
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
        ],
      ),
    );
  }

  Widget _buildLoadingDetails(bool isNarrow) {
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
          _buildLoadingRow(Icons.my_location, "Latitude", isNarrow),
          SizedBox(height: 16),
          _buildLoadingRow(Icons.my_location, "Longitude", isNarrow),
          SizedBox(height: 16),
          _buildLoadingRow(Icons.schedule, "Timestamp", isNarrow),
        ],
      ),
    );
  }

  Widget _buildLoadingRow(IconData icon, String label, bool isNarrow) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: isNarrow ? 16 : 18, color: Colors.grey),
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
              Container(
                height: isNarrow ? 14 : 15,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationDetails(bool isNarrow) {
    if (location == null) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 105, 107, 109).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            'No location data available',
            style: TextStyle(color: Colors.grey, fontSize: isNarrow ? 14 : 16),
          ),
        ),
      );
    }

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

  Widget _buildActionButtons(BuildContext context, bool isNarrow) {
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
              icon: isLoading
                  ? SizedBox(
                      width: isNarrow ? 16 : 18,
                      height: isNarrow ? 16 : 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.refresh, size: isNarrow ? 16 : 18),
              label: Text(
                isLoading ? 'Refreshing...' : 'Refresh',
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
              onPressed: isLoading ? null : onRefresh, // Disable when loading
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
                colors: isLoading || location == null
                    ? [Colors.grey, Colors.grey.shade600]
                    : [Color(0xFFFF6500), Color(0xFFFF8533)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isLoading || location == null
                              ? Colors.grey
                              : Color(0xFFFF6500))
                          .withValues(alpha: 0.4),
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
              onPressed: (isLoading || location == null)
                  ? null
                  : () async {
                      try {
                        // Show loading indicator
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => AlertDialog(
                            content: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(width: 16),
                                Text('Sharing location...'),
                              ],
                            ),
                          ),
                        );

                        // Execute share function
                        onShare();

                        // Close loading dialog
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }

                        // Show success feedback
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Location shared successfully!',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Coordinates copied to clipboard',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 4),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              action: SnackBarAction(
                                label: 'VIEW GPS',
                                textColor: Colors.white,
                                onPressed: () {
                                  // Navigate to GPS page
                                  Navigator.of(context).pushNamed('/gps');
                                },
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        // Close loading dialog if still open
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }

                        // Show error feedback
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.error, color: Colors.white),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Failed to share location',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          e.toString(),
                                          style: TextStyle(fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 5),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              action: SnackBarAction(
                                label: 'RETRY',
                                textColor: Colors.white,
                                onPressed: () {
                                  // Retry share
                                },
                              ),
                            ),
                          );
                        }
                      }
                    },
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
