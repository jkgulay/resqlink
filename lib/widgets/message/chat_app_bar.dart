import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/p2p/p2p_main_service.dart';
import '../../utils/resqlink_theme.dart';
import '../../features/database/repositories/chat_repository.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isChatView;
  final String? selectedDeviceName;
  final String? selectedEndpointId;
  final P2PMainService p2pService;
  final VoidCallback? onBackPressed;
  final Function(String) onMenuAction;
  final VoidCallback? onReconnect;
  final bool? isConnected;
  final bool? isMeshReachable;
  final int? meshHopCount;

  const ChatAppBar({
    super.key,
    required this.isChatView,
    this.selectedDeviceName,
    this.selectedEndpointId,
    required this.p2pService,
    this.onBackPressed,
    required this.onMenuAction,
    this.onReconnect,
    this.isConnected,
    this.isMeshReachable,
    this.meshHopCount,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;

    return AppBar(
      elevation: 8,
      shadowColor: Colors.black45,
      backgroundColor: Colors.transparent,
      toolbarHeight: isNarrow ? 56.0 : 64.0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.95),
          border: Border(
            bottom: BorderSide(
              color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: isChatView
          ? Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBackPressed,
                padding: EdgeInsets.zero,
              ),
            )
          : null,
      title: _buildTitle(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildTitle(BuildContext context) {
    if (isChatView) {
      // Use passed connectivity state if available, otherwise fall back to checking connectedDevices
      final directConnection =
          isConnected ??
          p2pService.connectedDevices.containsKey(selectedEndpointId);
      final meshReachable = isMeshReachable ?? false;
      final hopCount = meshHopCount ?? 0;
      final hasMeshRelay = !directConnection && meshReachable;

      // Determine status text and color
      final String statusText;
      final Color statusColor;

      if (directConnection) {
        statusText = 'Direct link';
        statusColor = ResQLinkTheme.safeGreen;
      } else if (hasMeshRelay) {
        statusText =
            'Relay via mesh ($hopCount ${hopCount == 1 ? 'hop' : 'hops'})';
        statusColor = Colors.orange; // Yellow/orange for mesh relay
      } else {
        statusText = 'Offline';
        statusColor = Colors.grey;
      }

      final displayNameFuture = _getDisplayName();

      return Row(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: directConnection
                  ? LinearGradient(
                      colors: [
                        ResQLinkTheme.safeGreen,
                        ResQLinkTheme.safeGreen.withValues(alpha: 0.7),
                      ],
                    )
                  : hasMeshRelay
                  ? LinearGradient(
                      colors: [
                        Colors.orange,
                        Colors.orange.withValues(alpha: 0.7),
                      ],
                    )
                  : LinearGradient(
                      colors: [Colors.grey.shade700, Colors.grey.shade800],
                    ),
              boxShadow: [
                BoxShadow(
                  color: directConnection
                      ? ResQLinkTheme.safeGreen.withValues(alpha: 0.4)
                      : hasMeshRelay
                      ? Colors.orange.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.transparent,
              child: FutureBuilder<String>(
                future: displayNameFuture,
                builder: (context, snapshot) {
                  final resolvedName =
                      snapshot.data ?? selectedDeviceName ?? 'Device';
                  final initial = resolvedName.isNotEmpty
                      ? resolvedName[0].toUpperCase()
                      : 'D';
                  return Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FutureBuilder<String>(
                  future: displayNameFuture,
                  builder: (context, snapshot) {
                    return ResponsiveTextWidget(
                      snapshot.data ?? selectedDeviceName ?? 'Unknown Device',
                      styleBuilder: (context) =>
                          ResponsiveText.bodyLarge(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                SizedBox(height: 2),
                GestureDetector(
                  onTap: () {
                    if (!directConnection &&
                        selectedEndpointId != null &&
                        onReconnect != null) {
                      onReconnect!();
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: (directConnection || hasMeshRelay)
                              ? [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.6),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: ResponsiveTextWidget(
                          statusText,
                          styleBuilder: (context) =>
                              ResponsiveText.caption(context).copyWith(
                                color: (directConnection || hasMeshRelay)
                                    ? statusColor
                                    : Colors.white60,
                                fontSize: 10,
                                fontFamily: 'Poppins',
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveTextWidget(
          'Messages',
          styleBuilder: (context) => ResponsiveText.heading3(context).copyWith(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        ResponsiveTextWidget(
          p2pService.isConnected
              ? '${p2pService.connectedDevices.length} connected'
              : 'No connection',
          styleBuilder: (context) => ResponsiveText.caption(context).copyWith(
            color: p2pService.isConnected
                ? ResQLinkTheme.safeGreen
                : Colors.white60,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];

    actions.add(
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.white),
        color: ResQLinkTheme.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        onSelected: onMenuAction,
        itemBuilder: (context) => [
          if (isChatView) ...[
            PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Clear Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return actions;
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);

  Future<String> _getDisplayName() async {
    final deviceId = selectedEndpointId;
    if (deviceId == null || deviceId.isEmpty) {
      return selectedDeviceName ?? 'Unknown Device';
    }

    // Prioritize name from a live connection
    if (p2pService.connectedDevices.containsKey(deviceId)) {
      final deviceName = p2pService.connectedDevices[deviceId]!.userName;
      if (deviceName.isNotEmpty) {
        return deviceName;
      }
    }

    try {
      final session = await ChatRepository.getSessionByDeviceId(deviceId);
      if (session != null && session.deviceName.isNotEmpty) {
        return session.deviceName;
      }
    } catch (e) {
      // Fallback handled below
    }

    return selectedDeviceName ?? 'Unknown Device';
  }
}
