import 'package:flutter/material.dart';
import '../../services/p2p_service.dart';

class EmergencyActionsCard extends StatelessWidget {
  final P2PConnectionService p2pService;
  final Function(EmergencyTemplate) onEmergencyMessage;

  const EmergencyActionsCard({
    super.key,
    required this.p2pService,
    required this.onEmergencyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.quick_contacts_mail, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Quick Emergency Messages',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEmergencyButton(
                  'SOS',
                  Colors.red,
                  Icons.sos,
                  () => onEmergencyMessage(EmergencyTemplate.sos),
                ),
                _buildEmergencyButton(
                  'Trapped',
                  Colors.orange,
                  Icons.warning,
                  () => onEmergencyMessage(EmergencyTemplate.trapped),
                ),
                _buildEmergencyButton(
                  'Medical',
                  Colors.blue,
                  Icons.medical_services,
                  () => onEmergencyMessage(EmergencyTemplate.medical),
                ),
                _buildEmergencyButton(
                  'Safe',
                  Colors.green,
                  Icons.check_circle,
                  () => onEmergencyMessage(EmergencyTemplate.safe),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyButton(
    String label,
    Color color,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      onPressed: onPressed,
    );
  }
}