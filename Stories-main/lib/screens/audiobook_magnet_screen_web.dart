import 'package:flutter/material.dart';

/// Web stub — torrent magnets are not available in the browser build.
class AudiobookMagnetScreen extends StatelessWidget {
  const AudiobookMagnetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Magnet audiobook'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Adding audiobooks from magnet links requires the Android, iOS, or desktop app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
