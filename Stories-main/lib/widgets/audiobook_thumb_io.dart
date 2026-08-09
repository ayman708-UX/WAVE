import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

Widget audiobookThumb(String url, {double width = 60, double height = 60}) {
  final isRemote =
      url.startsWith('http://') || url.startsWith('https://');
  if (isRemote) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorWidget: (c, u, e) => _fallback(width, height),
    );
  }
  if (url.isEmpty) return _fallback(width, height);
  final f = File(url);
  if (f.existsSync()) {
    return Image.file(
      f,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(width, height),
    );
  }
  return _fallback(width, height);
}

Widget _fallback(double width, double height) => Container(
      width: width,
      height: height,
      color: Colors.white12,
      child: const Icon(Icons.menu_book_rounded, color: Colors.white54),
    );
