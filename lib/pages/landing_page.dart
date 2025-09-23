import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';
import '../services/auth_service.dart';
import '../widgets/auth/emergency_auth_dialog.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  void _showEmergencyAuthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const EmergencyAuthDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = ResponsiveUtils.isLandscape(context);
            final isDesktop = ResponsiveUtils.isDesktop(context);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Container(
                    width: double.infinity,
                    padding: ResponsiveUtils.getResponsivePadding(context),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0B192C), Color(0xFF1E3E62)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: isLandscape && !isDesktop
                        ? _buildLandscapeLayout(context)
                        : _buildPortraitLayout(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildNetworkStatusIndicator(),
        _buildImageSection(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),
        _buildTitleSection(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),
        _buildFeatureHighlight(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 30)),
        _buildEnterButton(context),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNetworkStatusIndicator(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),
              _buildImageSection(context),
            ],
          ),
        ),
        SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 40)),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleSection(context),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),
              _buildFeatureHighlight(context),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 30),
              ),
              _buildEnterButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkStatusIndicator() {
    return FutureBuilder<bool>(
      future: AuthService.isOnline(),
      builder: (context, snapshot) {
        final online = snapshot.data ?? false;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: online
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: online ? Colors.green : Colors.orange,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                online ? Icons.wifi : Icons.wifi_off,
                color: online ? Colors.green : Colors.orange,
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                online ? 'Online' : 'Offline Ready',
                style: TextStyle(
                  color: online ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageSection(BuildContext context) {
    return SizedBox(
      height: ResponsiveUtils.getImageHeight(context),
      child: Image.asset('assets/1.png', fit: BoxFit.contain),
    );
  }

  Widget _buildTitleSection(BuildContext context) {
    return Column(
      crossAxisAlignment:
          ResponsiveUtils.isLandscape(context) &&
              !ResponsiveUtils.isDesktop(context)
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'ResQLink',
          textAlign:
              ResponsiveUtils.isLandscape(context) &&
                  !ResponsiveUtils.isDesktop(context)
              ? TextAlign.left
              : TextAlign.center,
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 28),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 10)),
        Text(
          'Offline Emergency Chat & Location Sharing',
          textAlign:
              ResponsiveUtils.isLandscape(context) &&
                  !ResponsiveUtils.isDesktop(context)
              ? TextAlign.left
              : TextAlign.center,
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureHighlight(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(
        ResponsiveUtils.getResponsiveSpacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Row(
        mainAxisAlignment:
            ResponsiveUtils.isLandscape(context) &&
                !ResponsiveUtils.isDesktop(context)
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Icon(
            Icons.offline_bolt,
            color: Colors.green,
            size: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
          SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
          Flexible(
            child: Text(
              'Ready for Emergency',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterButton(BuildContext context) {
    final buttonWidth = ResponsiveUtils.isDesktop(context)
        ? 300.0
        : ResponsiveUtils.isTablet(context)
        ? 250.0
        : MediaQuery.of(context).size.width * 0.8;

    return SizedBox(
      width: buttonWidth,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6500),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.getResponsiveSpacing(context, 24),
            vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(
          Icons.emergency,
          size: ResponsiveUtils.getResponsiveFontSize(context, 20),
        ),
        label: Text(
          'Start Emergency Chat',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () => _showEmergencyAuthDialog(context),
      ),
    );
  }
}