import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({super.key, this.message = 'Loading messages...'});

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 400;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B192C).withValues(alpha: 0.5),
            Color(0xFF1E3E62).withValues(alpha: 0.3),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spinner container with gradient background
            Container(
              padding: EdgeInsets.all(isNarrow ? 20 : 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1E3E62).withValues(alpha: 0.4),
                    Color(0xFF0B192C).withValues(alpha: 0.6),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Color(0xFFFF6500).withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFF6500).withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: SizedBox(
                width: isNarrow ? 36 : 40,
                height: isNarrow ? 36 : 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6500)),
                ),
              ),
            ),

            SizedBox(height: isNarrow ? 20 : 24),

            // Loading text
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: isNarrow ? 16 : 18,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),

            SizedBox(height: 8),

            // Subtitle
            Text(
              'Please wait',
              style: GoogleFonts.poppins(
                fontSize: isNarrow ? 12 : 13,
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
