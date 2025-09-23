import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/p2p/p2p_main_service.dart';
import '../../services/p2p/p2p_base_service.dart';
import '../../utils/resqlink_theme.dart';
import 'chat_search_delegate.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isChatView;
  final String? selectedDeviceName;
  final String? selectedEndpointId;
  final P2PMainService p2pService;
  final VoidCallback? onBackPressed;
  final Function(String) onMenuAction;
  final VoidCallback? onReconnect;

  const ChatAppBar({
    super.key,
    required this.isChatView,
    this.selectedDeviceName,
    this.selectedEndpointId,
    required this.p2pService,
    this.onBackPressed,
    required this.onMenuAction,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 2,
      shadowColor: Colors.black26,
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: isChatView
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: onBackPressed,
            )
          : null,
      title: _buildTitle(),
      actions: _buildActions(context),
    );
  }

  Widget _buildTitle() {
    if (isChatView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedDeviceName ?? 'Unknown Device',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            maxLines: 1,
          ),
          GestureDetector(
            onTap: () {
              if (!p2pService.connectedDevices.containsKey(selectedEndpointId) && 
                  selectedEndpointId != null && onReconnect != null) {
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
                    color: p2pService.connectedDevices.containsKey(selectedEndpointId)
                        ? ResQLinkTheme.safeGreen
                        : ResQLinkTheme.warningYellow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  p2pService.connectedDevices.containsKey(selectedEndpointId)
                      ? 'Connected'
                      : 'Disconnected - Tap to reconnect',
                  style: TextStyle(
                    fontSize: 12,
                    color: p2pService.connectedDevices.containsKey(selectedEndpointId)
                        ? ResQLinkTheme.safeGreen
                        : ResQLinkTheme.warningYellow,
                    decoration: !p2pService.connectedDevices.containsKey(selectedEndpointId)
                        ? TextDecoration.underline
                        : null,
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
        Text('Messages', style: TextStyle(color: Colors.white)),
        Text(
          p2pService.isConnected
              ? '${p2pService.connectedDevices.length} connected'
              : 'No connection',
          style: TextStyle(
            fontSize: 12,
            color: p2pService.isConnected
                ? ResQLinkTheme.safeGreen
                : ResQLinkTheme.warningYellow,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];

    // Add search button for chat view
    if (isChatView) {
      actions.add(
        IconButton(
          icon: Icon(Icons.search, color: Colors.white),
          onPressed: () async {
            final result = await showSearch(
              context: context,
              delegate: ChatSearchDelegate(sessionId: selectedEndpointId),
            );
            if (result != null) {
              // Handle search result if needed
              debugPrint('Search result: ${result.message}');
            }
          },
        ),
      );
    }

    if (isChatView && selectedEndpointId != null &&
        !p2pService.connectedDevices.containsKey(selectedEndpointId)) {
      actions.add(
        Container(
          margin: EdgeInsets.only(right: 8),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.primaryRed,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size(0, 32),
            ),
            icon: Icon(Icons.refresh, size: 16, color: Colors.white),
            label: Text('Reconnect',
              style: TextStyle(fontSize: 12, color: Colors.white)),
            onPressed: onReconnect,
          ),
        ),
      );
    }

    actions.add(
      Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: p2pService.isConnected
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.warningYellow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              p2pService.isConnected ? Icons.wifi : Icons.wifi_off,
              size: 14,
              color: Colors.white,
            ),
            SizedBox(width: 4),
            Text(
              p2pService.currentRole == P2PRole.host
                  ? 'HOST'
                  : p2pService.currentRole == P2PRole.client
                  ? 'CLIENT'
                  : 'OFF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );

    actions.add(
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.white),
        onSelected: onMenuAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'scan',
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Scan for Devices', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'create_group',
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Create Group', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          if (isChatView) ...[
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat', style: TextStyle(color: Colors.red)),
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
}