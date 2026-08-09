import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Stub music player used only for lock-screen handler wiring and desktop dialog state.
class MusicPlayerService {
  static final MusicPlayerService _instance = MusicPlayerService._internal();
  factory MusicPlayerService() => _instance;
  MusicPlayerService._internal();

  final Player player = Player();
  final ValueNotifier<bool> isFullScreenVisible = ValueNotifier<bool>(false);

  void setHandler(dynamic handler) {}

  Future<void> play() async {}

  Future<void> pause() async {}

  Future<void> next() async {}

  Future<void> previous() async {}
}
