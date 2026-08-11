import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DebridFile {
  final String filename;
  final int filesize;
  final String downloadUrl;

  DebridFile({
    required this.filename,
    required this.filesize,
    required this.downloadUrl,
  });
}

class DebridAudiobookMatcher {
  static const _audioExts = {
    '.mp3', '.m4b', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav', '.wma',
  };

  /// Helper to pick the matching audiobook file from a list of torrent file maps.
  static T? pickAudiobookFile<T>(
    List<T> files, {
    int? fileIndex,
    String? filename,
    required String Function(T) name,
    required int Function(T) size,
  }) {
    if (files.isEmpty) return null;

    // Filter to audio files first if present
    final audioFiles = files.where((f) {
      final n = name(f).toLowerCase();
      return _audioExts.any((ext) => n.endsWith(ext));
    }).toList();

    final candidates = audioFiles.isNotEmpty ? audioFiles : files;

    // 1. Exact or substring match by chapter title / filename
    if (filename != null && filename.isNotEmpty) {
      final cleanName = filename.toLowerCase().trim();
      final nameMatch = candidates.where((f) {
        final fName = name(f).toLowerCase();
        return fName.contains(cleanName) || cleanName.contains(fName.split('/').last);
      }).toList();
      if (nameMatch.isNotEmpty) {
        nameMatch.sort((a, b) => size(b).compareTo(size(a)));
        return nameMatch.first;
      }
    }

    // 2. Match by file index
    if (fileIndex != null && fileIndex >= 0 && fileIndex < candidates.length) {
      return candidates[fileIndex];
    }
    if (fileIndex != null && fileIndex >= 0 && fileIndex < files.length) {
      return files[fileIndex];
    }

    // 3. Fallback: largest file
    candidates.sort((a, b) => size(b).compareTo(size(a)));
    return candidates.first;
  }
}

class DebridApi {
  static final DebridApi _instance = DebridApi._internal();
  factory DebridApi() => _instance;
  DebridApi._internal();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> _safeRead(String key) async {
    try {
      return (await _prefs).getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await (await _prefs).setString(key, value);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {}
  }

  // --- Active Selected Debrid Service ---
  static const String _debridServiceKey = 'debrid_service';

  Future<String?> getDebridService() async {
    return await _safeRead(_debridServiceKey);
  }

  Future<void> saveDebridService(String service) async {
    await _safeWrite(_debridServiceKey, service.trim());
  }

  /// Returns the active debrid service strictly based on the dropdown selection.
  /// If 'None' or empty is selected, Debrid is OFF and returns null.
  /// If a provider is selected but has no saved API key, throws an Exception.
  Future<String?> getActiveDebridService() async {
    final selected = await getDebridService();
    if (selected == null || selected == 'None' || selected.isEmpty) {
      return null; // Debrid is OFF!
    }

    final hasKey = await hasKeyForService(selected);
    if (!hasKey) {
      throw Exception('Selected Debrid provider ($selected) has no API key saved. Please enter and save your API key in Settings.');
    }

    return selected;
  }

  Future<bool> hasKeyForService(String service) async {
    switch (service) {
      case 'Real-Debrid':
        return (await getRDAccessToken())?.isNotEmpty == true;
      case 'TorBox':
        return (await getTorBoxKey())?.isNotEmpty == true;
      case 'AllDebrid':
        return (await getAllDebridKey())?.isNotEmpty == true;
      case 'Premiumize':
        return (await getPremiumizeKey())?.isNotEmpty == true;
      case 'Debrid-Link':
        return (await getDebridLinkKey())?.isNotEmpty == true;
      default:
        return false;
    }
  }

  // --- Real-Debrid ---
  static const String _rdTokenKey = 'rd_access_token';

  Future<void> saveRDApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await logoutRD();
      return;
    }
    await _safeWrite(_rdTokenKey, trimmed);
  }

  Future<String?> getRDAccessToken() async {
    return await _safeRead(_rdTokenKey);
  }

  Future<Map<String, dynamic>?> verifyRDApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/user'),
        headers: {'Authorization': 'Bearer $trimmed'},
      );
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> logoutRD() async {
    for (final key in [
      _rdTokenKey,
      'rd_refresh_token',
      'rd_token_expiry',
      'rd_client_id',
      'rd_client_secret',
    ]) {
      await _safeDelete(key);
    }
  }

  Future<List<DebridFile>> resolveRealDebrid(
    String magnet, {
    int? fileIndex,
    String? filename,
  }) async {
    final token = await getRDAccessToken();
    if (token == null || token.isEmpty) throw Exception("Real-Debrid not logged in");

    final headers = {'Authorization': 'Bearer $token'};

    // 1. Add the magnet
    final addRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/addMagnet'),
      headers: headers,
      body: {'magnet': magnet},
    );
    if (addRes.statusCode != 201) {
      throw Exception("Failed to add magnet to RD: ${addRes.body}");
    }
    final torrentId = json.decode(addRes.body)['id'] as String;

    // 2. Poll info for file list
    Map<String, dynamic>? info;
    List<dynamic>? rdFiles;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      info = json.decode(infoRes.body) as Map<String, dynamic>;
      final status = info['status'] as String?;
      if (status == 'magnet_error' || status == 'error' || status == 'dead' || status == 'virus') {
        throw Exception("RD rejected magnet (status: $status)");
      }
      rdFiles = (info['files'] as List?) ?? const [];
      if (rdFiles.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 2));
      attempts++;
    }
    if (rdFiles == null || rdFiles.isEmpty) {
      throw Exception("RD never returned a file list");
    }

    // 3. Pick matching file
    final picked = DebridAudiobookMatcher.pickAudiobookFile<dynamic>(
      rdFiles,
      fileIndex: fileIndex,
      filename: filename,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['bytes'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) {
      throw Exception("No suitable file found in torrent");
    }
    final pickedId = picked['id'].toString();
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedSize = (picked['bytes'] as num?)?.toInt() ?? 0;
    debugPrint('[RD] picked file id=$pickedId path=$pickedPath');

    final selRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
      headers: headers,
      body: {'files': pickedId},
    );
    if (selRes.statusCode != 204 && selRes.statusCode != 202) {
      debugPrint('[RD] single-file select failed (${selRes.statusCode}), falling back to all');
      await http.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
        headers: headers,
        body: {'files': 'all'},
      );
    }

    // 4. Poll until downloaded
    attempts = 0;
    while (attempts < 40) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      info = json.decode(infoRes.body) as Map<String, dynamic>;
      final status = info['status'] as String?;
      if (status == 'downloaded') break;
      if (status == 'error' || status == 'dead' || status == 'virus') {
        throw Exception("RD download failed (status: $status)");
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }
    if (info!['status'] != 'downloaded') {
      throw Exception("RD download timed out");
    }

    // 5. Unrestrict link
    final links = (info['links'] as List?) ?? const [];
    if (links.isEmpty) throw Exception("RD returned no links");
    String? targetLink;
    if (links.length == 1) {
      targetLink = links.first as String;
    } else {
      final selectedFiles = (info['files'] as List)
          .where((f) => (f['selected'] as int?) == 1)
          .toList();
      final idx = selectedFiles.indexWhere((f) => f['id'].toString() == pickedId);
      if (idx >= 0 && idx < links.length) {
        targetLink = links[idx] as String;
      } else {
        targetLink = links.first as String;
      }
    }

    final unRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/unrestrict/link'),
      headers: headers,
      body: {'link': targetLink},
    );
    if (unRes.statusCode != 200) {
      throw Exception("RD unrestrict failed: ${unRes.body}");
    }
    final data = json.decode(unRes.body) as Map<String, dynamic>;
    return [
      DebridFile(
        filename: (data['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (data['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: data['download'] as String,
      ),
    ];
  }

  // --- TorBox ---
  Future<void> saveTorBoxKey(String key) async {
    await _safeWrite('torbox_api_key', key.trim());
  }

  Future<String?> getTorBoxKey() async {
    return await _safeRead('torbox_api_key');
  }

  Future<List<DebridFile>> resolveTorBox(
    String magnet, {
    int? fileIndex,
    String? filename,
  }) async {
    final apiKey = await getTorBoxKey();
    if (apiKey == null || apiKey.isEmpty) throw Exception("TorBox API Key not set");

    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Create Torrent
    final createRes = await http.post(
      Uri.parse('https://api.torbox.app/v1/api/torrents/createtorrent'),
      headers: headers,
      body: {'magnet': magnet},
    );

    final createData = json.decode(createRes.body);
    if (createData['success'] == false) throw Exception("TorBox failed: ${createData['detail']}");

    final torrentId = createData['data']['torrent_id'];

    // 2. Poll status
    Map<String, dynamic>? info;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.torbox.app/v1/api/torrents/mylist?id=$torrentId&bypass_cache=true'),
        headers: headers,
      );
      final mylist = json.decode(infoRes.body)['data'];
      info = mylist;
      if (info!['download_finished'] == true || info['download_state'] == 'cached') break;
      if (info['download_state'] == 'error') throw Exception("TorBox Download failed");

      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    final List rawFiles = (info!['files'] as List?) ?? const [];
    if (rawFiles.isEmpty) throw Exception("TorBox returned no files");

    // 3. Pick file
    final picked = DebridAudiobookMatcher.pickAudiobookFile<dynamic>(
      rawFiles,
      fileIndex: fileIndex,
      filename: filename,
      name: (f) => (f['name'] as String?) ?? '',
      size: (f) => (f['size'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) throw Exception("No suitable file found in torrent");

    final permalink =
        'https://api.torbox.app/v1/api/torrents/requestdl?token=$apiKey'
        '&torrent_id=$torrentId&file_id=${picked['id']}&redirect=true';
    return [
      DebridFile(
        filename: (picked['name'] as String?) ?? 'audio',
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: permalink,
      ),
    ];
  }

  // --- AllDebrid ---
  Future<void> saveAllDebridKey(String key) async {
    await _safeWrite('alldebrid_api_key', key.trim());
  }

  Future<String?> getAllDebridKey() async {
    return await _safeRead('alldebrid_api_key');
  }

  void _flattenAdFiles(
    List<dynamic> nodes,
    String prefix,
    List<Map<String, dynamic>> out,
  ) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final name = (node['n'] as String?) ?? '';
      final children = node['e'];
      if (children is List) {
        _flattenAdFiles(
          children,
          prefix.isEmpty ? name : '$prefix/$name',
          out,
        );
      } else {
        out.add({
          'path': prefix.isEmpty ? name : '$prefix/$name',
          'size': (node['s'] as num?)?.toInt() ?? 0,
          'link': (node['l'] as String?) ?? '',
        });
      }
    }
  }

  Map<String, dynamic> _adDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['status'] == 'error') {
      final err = body['error'] as Map<String, dynamic>?;
      throw Exception(
        'AllDebrid: ${err?['code']} - ${err?['message'] ?? res.body}',
      );
    }
    return (body['data'] as Map).cast<String, dynamic>();
  }

  Future<List<DebridFile>> resolveAllDebrid(
    String magnet, {
    int? fileIndex,
    String? filename,
  }) async {
    final apiKey = await getAllDebridKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('AllDebrid API key not set');
    }
    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Upload magnet
    final upRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/upload'),
      headers: headers,
      body: {'magnets[]': magnet},
    );
    final upData = _adDecode(upRes);
    final magnets = (upData['magnets'] as List?) ?? const [];
    if (magnets.isEmpty || magnets.first is! Map) {
      throw Exception('AllDebrid: empty magnet upload response');
    }
    final m = (magnets.first as Map).cast<String, dynamic>();
    if (m['error'] != null) {
      final e = (m['error'] as Map).cast<String, dynamic>();
      throw Exception('AllDebrid: ${e['code']} - ${e['message']}');
    }
    final magnetId = m['id'];
    if (magnetId == null) throw Exception('AllDebrid: no magnet id returned');

    // 2. Poll status
    int attempts = 0;
    while (attempts < 40) {
      final stRes = await http.post(
        Uri.parse('https://api.alldebrid.com/v4.1/magnet/status'),
        headers: headers,
        body: {'id': magnetId.toString()},
      );
      final stData = _adDecode(stRes);
      final mags = stData['magnets'];
      Map<String, dynamic>? magObj;
      if (mags is List && mags.isNotEmpty && mags.first is Map) {
        magObj = (mags.first as Map).cast<String, dynamic>();
      } else if (mags is Map) {
        magObj = mags.cast<String, dynamic>();
      }
      final code = (magObj?['statusCode'] as num?)?.toInt() ?? -1;
      if (code == 4) break;
      if (code >= 5) {
        throw Exception(
          'AllDebrid magnet failed: ${magObj?['status']} (code $code)',
        );
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    // 3. Get files
    final filesRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/files'),
      headers: headers,
      body: {'id[]': magnetId.toString()},
    );
    final filesData = _adDecode(filesRes);
    final filesMagnets = (filesData['magnets'] as List?) ?? const [];
    if (filesMagnets.isEmpty || filesMagnets.first is! Map) {
      throw Exception('AllDebrid: empty files response');
    }
    final filesObj = (filesMagnets.first as Map).cast<String, dynamic>();
    if (filesObj['error'] != null) {
      final e = (filesObj['error'] as Map).cast<String, dynamic>();
      throw Exception('AllDebrid files: ${e['code']} - ${e['message']}');
    }
    final tree = (filesObj['files'] as List?) ?? const [];
    final flat = <Map<String, dynamic>>[];
    _flattenAdFiles(tree, '', flat);
    if (flat.isEmpty) {
      throw Exception('AllDebrid: no files in magnet');
    }

    // 4. Pick file
    final picked = DebridAudiobookMatcher.pickAudiobookFile<Map<String, dynamic>>(
      flat,
      fileIndex: fileIndex,
      filename: filename,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['size'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) {
      throw Exception('AllDebrid: no suitable file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    final pickedSize = (picked['size'] as num?)?.toInt() ?? 0;
    if (pickedLink.isEmpty) {
      throw Exception('AllDebrid: picked file has no unlock link');
    }

    // 5. Unlock link
    final unRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/link/unlock'),
      headers: headers,
      body: {'link': pickedLink},
    );
    final unData = _adDecode(unRes);
    final dlLink = unData['link'] as String?;
    if (dlLink == null || dlLink.isEmpty) {
      if (unData['delayed'] != null) {
        throw Exception('AllDebrid returned a delayed link');
      }
      throw Exception('AllDebrid unlock returned no link');
    }
    return [
      DebridFile(
        filename: (unData['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (unData['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: dlLink,
      ),
    ];
  }

  // --- Premiumize ---
  Future<void> savePremiumizeKey(String key) async {
    await _safeWrite('premiumize_api_key', key.trim());
  }

  Future<String?> getPremiumizeKey() async {
    return await _safeRead('premiumize_api_key');
  }

  Future<void> _walkPremiumizeFolder(
    String apiKey,
    String folderId,
    String prefix,
    List<Map<String, dynamic>> out,
  ) async {
    final res = await http.post(
      Uri.parse('https://www.premiumize.me/api/folder/list'),
      body: {'apikey': apiKey, 'id': folderId},
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') {
      throw Exception('Premiumize folder/list: ${body['message']}');
    }
    final content = (body['content'] as List?) ?? const [];
    for (final raw in content) {
      if (raw is! Map) continue;
      final node = raw.cast<String, dynamic>();
      final name = (node['name'] as String?) ?? '';
      final path = prefix.isEmpty ? name : '$prefix/$name';
      if (node['type'] == 'folder' && node['id'] is String) {
        await _walkPremiumizeFolder(apiKey, node['id'] as String, path, out);
      } else {
        out.add({
          'path': path,
          'size': (node['size'] as num?)?.toInt() ?? 0,
          'link': (node['link'] as String?) ?? '',
        });
      }
    }
  }

  Future<List<DebridFile>> resolvePremiumize(
    String magnet, {
    int? fileIndex,
    String? filename,
  }) async {
    final apiKey = await getPremiumizeKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Premiumize API key not set');
    }

    List<Map<String, dynamic>> files = [];

    // Direct download (cached)
    try {
      final dlRes = await http.post(
        Uri.parse('https://www.premiumize.me/api/transfer/directdl'),
        body: {'apikey': apiKey, 'src': magnet},
      );
      final dlBody = json.decode(dlRes.body) as Map<String, dynamic>;
      if (dlBody['status'] == 'success') {
        final content = (dlBody['content'] as List?) ?? const [];
        for (final raw in content) {
          if (raw is! Map) continue;
          final node = raw.cast<String, dynamic>();
          files.add({
            'path': (node['path'] as String?) ?? (node['name'] as String?) ?? '',
            'size': (node['size'] as num?)?.toInt() ?? 0,
            'link': (node['stream_link'] as String?)?.isNotEmpty == true
                ? node['stream_link'] as String
                : (node['link'] as String?) ?? '',
          });
        }
      }
    } catch (e) {
      debugPrint('[Premiumize] directdl error: $e');
    }

    if (files.isEmpty) {
      final createRes = await http.post(
        Uri.parse('https://www.premiumize.me/api/transfer/create'),
        body: {'apikey': apiKey, 'src': magnet},
      );
      final createBody = json.decode(createRes.body) as Map<String, dynamic>;
      if (createBody['status'] != 'success') {
        throw Exception('Premiumize create: ${createBody['message']}');
      }
      final transferId = createBody['id'] as String?;
      if (transferId == null) {
        throw Exception('Premiumize: no transfer id returned');
      }

      String? folderId;
      int attempts = 0;
      while (attempts < 40) {
        await Future.delayed(const Duration(seconds: 3));
        final listRes = await http.post(
          Uri.parse('https://www.premiumize.me/api/transfer/list'),
          body: {'apikey': apiKey},
        );
        final listBody = json.decode(listRes.body) as Map<String, dynamic>;
        if (listBody['status'] != 'success') {
          throw Exception('Premiumize list: ${listBody['message']}');
        }
        final transfers = (listBody['transfers'] as List?) ?? const [];
        Map<String, dynamic>? mine;
        for (final raw in transfers) {
          if (raw is Map && raw['id'] == transferId) {
            mine = raw.cast<String, dynamic>();
            break;
          }
        }
        if (mine == null) {
          throw Exception('Premiumize: transfer disappeared');
        }
        final status = mine['status'] as String?;
        if (status == 'finished' || status == 'seeding') {
          folderId = mine['folder_id'] as String?;
          break;
        }
        if (status == 'error' || status == 'deleted' || status == 'banned') {
          throw Exception('Premiumize transfer failed: $status (${mine['message']})');
        }
        attempts++;
      }
      if (folderId == null) {
        throw Exception('Premiumize: transfer did not finish in time');
      }

      await _walkPremiumizeFolder(apiKey, folderId, '', files);
    }

    if (files.isEmpty) {
      throw Exception('Premiumize: no files in torrent');
    }

    final picked = DebridAudiobookMatcher.pickAudiobookFile<Map<String, dynamic>>(
      files,
      fileIndex: fileIndex,
      filename: filename,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['size'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) {
      throw Exception('Premiumize: no file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    if (pickedLink.isEmpty) {
      throw Exception('Premiumize: picked file has no download link');
    }

    return [
      DebridFile(
        filename: pickedPath.split('/').last,
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: pickedLink,
      ),
    ];
  }

  // --- Debrid-Link ---
  Future<void> saveDebridLinkKey(String key) async {
    await _safeWrite('debridlink_api_key', key.trim());
  }

  Future<String?> getDebridLinkKey() async {
    return await _safeRead('debridlink_api_key');
  }

  Map<String, dynamic> _dlDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw Exception('Debrid-Link: ${body['error'] ?? res.body}');
    }
    return body;
  }

  List<Map<String, dynamic>> _dlExtractFiles(dynamic torrentValue) {
    final out = <Map<String, dynamic>>[];
    if (torrentValue is! Map) return out;
    final files = torrentValue['files'];
    if (files is! List) return out;
    for (final raw in files) {
      if (raw is! Map) continue;
      out.add({
        'path': (raw['name'] as String?) ?? '',
        'size': (raw['size'] as num?)?.toInt() ?? 0,
        'link': (raw['downloadUrl'] as String?) ?? '',
        'percent': (raw['downloadPercent'] as num?)?.toDouble() ?? 0.0,
      });
    }
    return out;
  }

  Future<List<DebridFile>> resolveDebridLink(
    String magnet, {
    int? fileIndex,
    String? filename,
  }) async {
    final apiKey = await getDebridLinkKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Debrid-Link API key not set');
    }
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    final addRes = await http.post(
      Uri.parse('https://debrid-link.com/api/v2/seedbox/add'),
      headers: headers,
      body: json.encode({'url': magnet, 'async': true}),
    );
    final addBody = _dlDecode(addRes);
    final torrent = addBody['value'];
    if (torrent is! Map || torrent['id'] == null) {
      throw Exception('Debrid-Link: no torrent id returned');
    }
    final torrentId = torrent['id'] as String;

    var files = _dlExtractFiles(torrent);
    bool ready = files.isNotEmpty &&
        files.every((f) => (f['link'] as String).isNotEmpty);

    int attempts = 0;
    while (!ready && attempts < 40) {
      await Future.delayed(const Duration(seconds: 3));
      final stRes = await http.get(
        Uri.parse('https://debrid-link.com/api/v2/seedbox/list?ids=$torrentId'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      final stBody = _dlDecode(stRes);
      final list = stBody['value'];
      if (list is List && list.isNotEmpty) {
        files = _dlExtractFiles(list.first);
        ready = files.isNotEmpty &&
            files.every((f) => (f['link'] as String).isNotEmpty);
      }
      attempts++;
    }
    if (files.isEmpty) {
      throw Exception('Debrid-Link: no files in torrent');
    }
    if (!ready) {
      throw Exception('Debrid-Link: torrent not ready after 120s');
    }

    final picked = DebridAudiobookMatcher.pickAudiobookFile<Map<String, dynamic>>(
      files,
      fileIndex: fileIndex,
      filename: filename,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['size'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) {
      throw Exception('Debrid-Link: no file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    if (pickedLink.isEmpty) {
      throw Exception('Debrid-Link: picked file has no download link');
    }

    return [
      DebridFile(
        filename: pickedPath.split('/').last,
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: pickedLink,
      ),
    ];
  }

  // --- Dispatcher ---
  Future<List<DebridFile>> resolveByService(
    String service,
    String magnet, {
    int? fileIndex,
    String? filename,
  }) {
    switch (service) {
      case 'Real-Debrid':
        return resolveRealDebrid(magnet, fileIndex: fileIndex, filename: filename);
      case 'TorBox':
        return resolveTorBox(magnet, fileIndex: fileIndex, filename: filename);
      case 'AllDebrid':
        return resolveAllDebrid(magnet, fileIndex: fileIndex, filename: filename);
      case 'Premiumize':
        return resolvePremiumize(magnet, fileIndex: fileIndex, filename: filename);
      case 'Debrid-Link':
        return resolveDebridLink(magnet, fileIndex: fileIndex, filename: filename);
      default:
        throw Exception('Unknown debrid service: $service');
    }
  }
}
