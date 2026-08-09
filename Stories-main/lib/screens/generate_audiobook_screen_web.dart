import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// EPUB → TTS generation uses `dart:io` and is not available on web.
class GenerateAudiobookScreen extends StatelessWidget {
  const GenerateAudiobookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Generate audiobook'),
        backgroundColor: Colors.transparent,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Generating audiobooks from EPUB files is only supported on desktop and mobile builds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
