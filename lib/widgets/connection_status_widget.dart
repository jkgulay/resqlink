import 'dart:async';
import 'package:flutter/material.dart';
import '../services/p2p_service.dart';
import '../utils/resqlink_theme.dart';

class ConnectionStatusWidget extends StatefulWidget {
  final P2PConnectionService p2pService;
  final bool showDetails;

  const ConnectionStatusWidget({
    super.key,
    required this.p2pService,
    this.showDetails = false,
  });

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _statusUpdateTimer;
  
  // Connection state
  bool _isConnected = false;
  String _connectionType = 'none';
  String _role = 'none';
  int _deviceCount = 0;
  int _signalStrength = -100;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupStatusMonitoring();
    _updateConnectionStatus();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  void _setupStatusMonitoring() {
    // Listen to P2P service changes
    widget.p2pService.addListener(_updateConnectionStatus);
    
    // Periodic status updates
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted) {
        _updateConnectionStatus();
      }
    });
  }

  void _updateConnectionStatus() {
    if (!mounted) return;

    try {
      final connectionInfo = widget.p2pService.getConnectionInfo();
      final newIsConnected = widget.p2pService.isConnected;
      final newConnectionType = _determineConnectionType();
      final newRole = connectionInfo['role'] as String? ?? 'none';
      final newDeviceCount = connectionInfo['connectedDevices'] as int? ?? 0;
      final newSignalStrength = _getCurrentSignalStrength();

      setState(() {
        _isConnected = newIsConnected;
        _connectionType = newConnectionType;
        _role = newRole;
        _deviceCount = newDeviceCount;
        _signalStrength = newSignalStrength;
      });

      // Control pulse animation based on connection status
      if (_isConnected && widget.p2pService.emergencyMode) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    } catch (e) {
      debugPrint("❌ Error updating connection status: $e");
    }
  }

  String _determineConnectionType() {
    if (!widget.p2pService.isConnected) return 'none';
    
    // Fix: Check if hotspot properties exist before accessing
    try {
      if (widget.p2pService.hotspotFallbackEnabled) {
        // Check if we have a connected hotspot SSID through the connection info
        final connectionInfo = widget.p2pService.getConnectionInfo();
        final hotspotSSID = connectionInfo['connectedHotspotSSID'] as String?;
        if (hotspotSSID != null) {
          return 'hotspot';
        }
      }
      
      if (widget.p2pService.currentRole != P2PRole.none) {
        return 'wifi_direct';
      }
    } catch (e) {
      debugPrint("❌ Error determining connection type: $e");
    }
    
    return 'p2p';
  }

  int _getCurrentSignalStrength() {
    // Get signal strength from discovered devices or connected devices
    try {
      if (_isConnected && _deviceCount > 0) {
        // Try to get signal from connected devices
        final devices = widget.p2pService.discoveredDevices.values;
        if (devices.isNotEmpty) {
          final signalLevels = devices
              .map((d) => d['signalLevel'] as int? ?? -100)
              .where((s) => s > -100);
          
          if (signalLevels.isNotEmpty) {
            return signalLevels.reduce((a, b) => a > b ? a : b); // Best signal
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error getting signal strength: $e");
    }
    
    return _isConnected ? -60 : -100; // Default values
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusUpdateTimer?.cancel();
    widget.p2pService.removeListener(_updateConnectionStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.p2pService.emergencyMode && _isConnected 
              ? _pulseAnimation.value 
              : 1.0,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.showDetails ? 12 : 8, 
              vertical: widget.showDetails ? 8 : 6,
            ),
            decoration: BoxDecoration(
              color: _getConnectionColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(widget.showDetails ? 12 : 20),
              border: Border.all(
                color: _getConnectionColor(),
                width: 1.5,
              ),
              boxShadow: widget.p2pService.emergencyMode && _isConnected
                  ? [
                      BoxShadow(
                        color: _getConnectionColor().withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: widget.showDetails ? _buildDetailedView() : _buildCompactView(),
          ),
        );
      },
    );
  }

  Widget _buildCompactView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: Icon(
            _getConnectionIcon(),
            key: ValueKey('$_connectionType-$_isConnected'),
            color: _getConnectionColor(),
            size: 16,
          ),
        ),
        SizedBox(width: 6),
        Text(
          _getStatusText(),
          style: TextStyle(
            color: _getConnectionColor(),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        if (_isConnected && _connectionType == 'hotspot')
          _buildSignalStrengthCompact(),
      ],
    );
  }

  Widget _buildDetailedView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection icon with animation
        AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: Icon(
            _getConnectionIcon(),
            key: ValueKey('$_connectionType-$_isConnected'),
            color: _getConnectionColor(),
            size: 18,
          ),
        ),
        SizedBox(width: 8),
        
        // Connection details
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _getConnectionDisplayName(),
                  style: TextStyle(
                    color: _getConnectionColor(),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (_isConnected) ...[
                  SizedBox(width: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _getConnectionColor(),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _role.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (widget.p2pService.emergencyMode) ...[
                  SizedBox(width: 4),
                  Icon(
                    Icons.emergency,
                    size: 12,
                    color: Colors.red,
                  ),
                ],
              ],
            ),
            Text(
              _getDetailedStatusText(),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10,
              ),
            ),
          ],
        ),
        
        // Signal strength indicator for specific connection types
        if (_connectionType == 'hotspot' && _isConnected) ...[
          SizedBox(width: 8),
          _buildSignalStrengthIndicator(),
        ],
      ],
    );
  }

  Widget _buildSignalStrengthCompact() {
    return Container(
      margin: EdgeInsets.only(left: 4),
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            width: 2,
            height: 3.0 + (index * 1.5),
            margin: EdgeInsets.only(right: 1),
            decoration: BoxDecoration(
              color: index < _getSignalBars() ? _getConnectionColor() : Colors.grey[300],
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSignalStrengthIndicator() {
    final strength = _getSignalBars(); // 1-4 bars
    
    return Row(
      children: List.generate(4, (index) {
        return Container(
          width: 3,
          height: 4.0 + (index * 2),
          margin: EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: index < strength ? _getSignalColor() : Colors.grey[300],
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  int _getSignalBars() {
    if (_signalStrength >= -50) return 4; // Excellent
    if (_signalStrength >= -60) return 3; // Very Good
    if (_signalStrength >= -70) return 2; // Good
    if (_signalStrength >= -80) return 1; // Fair
    return 0; // Poor
  }

  Color _getSignalColor() {
    final bars = _getSignalBars();
    if (bars >= 3) return Colors.green;
    if (bars >= 2) return Colors.orange;
    return Colors.red;
  }

  IconData _getConnectionIcon() {
    if (!_isConnected) {
      return widget.p2pService.isDiscovering ? Icons.search : Icons.portable_wifi_off;
    }
    
    switch (_connectionType) {
      case 'hotspot':
        return Icons.wifi_tethering;
      case 'wifi_direct':
        return Icons.wifi; // Fix: Use Icons.wifi instead of Icons.wifi_direct
      case 'p2p':
        return Icons.device_hub;
      default:
        return Icons.portable_wifi_off;
    }
  }

  String _getConnectionDisplayName() {
    switch (_connectionType) {
      case 'hotspot':
        return 'Hotspot Mode';
      case 'wifi_direct':
        return 'WiFi Direct';
      case 'p2p':
        return 'P2P Network';
      case 'none':
      default:
        return widget.p2pService.isDiscovering ? 'Discovering...' : 'Disconnected';
    }
  }

  String _getStatusText() {
    if (widget.p2pService.isDiscovering && !_isConnected) {
      return 'Scanning';
    }
    if (_isConnected) {
      return widget.showDetails ? 'Connected' : _getConnectionDisplayName();
    }
    return 'Offline';
  }

  String _getDetailedStatusText() {
    if (!_isConnected) {
      if (widget.p2pService.isDiscovering) {
        return 'Scanning for devices...';
      }
      return 'No devices connected';
    }
    
    return '$_deviceCount device${_deviceCount != 1 ? 's' : ''} connected';
  }

  Color _getConnectionColor() {
    if (widget.p2pService.emergencyMode && _isConnected) {
      return Colors.red; // Emergency mode
    }
    
    if (!_isConnected) {
      return widget.p2pService.isDiscovering ? Colors.blue : Colors.grey;
    }
    
    switch (_connectionType) {
      case 'hotspot':
        return Colors.orange;
      case 'wifi_direct':
        return ResQLinkTheme.safeGreen;
      case 'p2p':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}