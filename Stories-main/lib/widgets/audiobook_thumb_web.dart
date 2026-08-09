import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

Widget audiobookThumb(String url, {double width = 60, double height = 60}) {
  final isRemote =
      url.startsWith('http://') || url.startsWith('https://');
  if (!isRemote || url.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: Colors.white12,
      child: const Icon(Icons.menu_book_rounded, color: Colors.white54),
    );
  }
  return CachedNetworkImage(
    imageUrl: url,
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorWidget: (c, u, e) => Container(
      width: width,
      height: height,
      color: Colors.white12,
      child: const Icon(Icons.menu_book_rounded, color: Colors.white54),
    ),
  );
}
