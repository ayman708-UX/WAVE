import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class AudiobookDownloadsScreen extends StatelessWidget {
  const AudiobookDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(title: const Text('Downloads')),
      body: const Center(
        child: Text(
          'Offline audiobook downloads are not available in the web build.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
