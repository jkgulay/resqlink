import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InstructionsCard extends StatelessWidget {
  const InstructionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.9),
              Color(0xFF1E3A5F).withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;
              return _buildInstructionsContent(isNarrow);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionsContent(bool isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInstructionsHeader(isNarrow),
        SizedBox(height: 24),
        _buildInstructionsList(isNarrow),
      ],
    );
  }

  Widget _buildInstructionsHeader(bool isNarrow) {
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
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.lightbulb,
              color: Colors.orange,
              size: isNarrow ? 26 : 30,
            ),
          ),
          SizedBox(width: isNarrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How It Works',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: isNarrow ? 18 : 20,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'ResQLink Emergency Network',
                  style: GoogleFonts.poppins(
                    color: Colors.orange,
                    fontSize: isNarrow ? 13 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsList(bool isNarrow) {
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
          _buildInstructionItem(
            '1',
            'Emergency Mode automatically discovers and connects to nearby devices using WiFi Direct',
            Icons.wifi_tethering,
            Colors.blue,
            isNarrow,
          ),
          SizedBox(height: 20),
          _buildInstructionItem(
            '2',
            'Messages relay through multiple devices to reach everyone',
            Icons.hub,
            Colors.green,
            isNarrow,
          ),
          SizedBox(height: 20),
          _buildInstructionItem(
            '3',
            'No internet required - pure peer-to-peer communication',
            Icons.cloud_off,
            Colors.purple,
            isNarrow,
          ),
          SizedBox(height: 20),
          _buildInstructionItem(
            '4',
            'Location sharing helps rescuers find you in emergencies',
            Icons.my_location,
            Colors.red,
            isNarrow,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(
    String number,
    String text,
    IconData icon,
    Color color,
    bool isNarrow,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isNarrow ? 40 : 44,
          height: isNarrow ? 40 : 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: isNarrow ? 18 : 20, color: color),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: isNarrow ? 16 : 18,
                  height: isNarrow ? 16 : 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isNarrow ? 10 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(
                fontSize: isNarrow ? 13 : 14,
                color: Color.fromARGB(255, 200, 200, 200),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
