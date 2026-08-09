import 'package:flutter/material.dart';
import 'audiobook_thumb_io.dart' if (dart.library.html) 'audiobook_thumb_web.dart'
    as impl;

/// Cover thumbnail for audiobook list tiles — remote URLs or local file paths (non‑web).
Widget audiobookThumb(String url, {double width = 60, double height = 60}) {
  return impl.audiobookThumb(url, width: width, height: height);
}
