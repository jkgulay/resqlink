import 'package:flutter/material.dart';
import '../../utils/resqlink_theme.dart';

class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({
    super.key,
    this.message = 'Loading messages...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: ResQLinkTheme.primaryRed),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}