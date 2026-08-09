import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Uri?> cacheNotificationCover(String bookId, Uint8List bytes) async {
  if (bytes.isEmpty || bookId.isEmpty) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/stories_cover_$bookId.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return Uri.file(file.path);
}
