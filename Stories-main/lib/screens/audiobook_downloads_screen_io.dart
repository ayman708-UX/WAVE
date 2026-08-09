import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/audiobook_download_service.dart';
import '../api/audiobook_service.dart';
import '../api/music_player_service.dart';
import '../utils/app_theme.dart';
import 'audiobook_player_screen.dart';
import '../widgets/tv_interactive.dart';

class AudiobookDownloadsScreen extends StatefulWidget {
  const AudiobookDownloadsScreen({super.key});

  @override
  State<AudiobookDownloadsScreen> createState() =>
      _AudiobookDownloadsScreenState();
}

class _AudiobookDownloadsScreenState extends State<AudiobookDownloadsScreen> {
  final _downloadService = AudiobookDownloadService();
  List<DownloadedAudiobook> _downloadedBooks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
    _downloadService.activeDownloads.addListener(_onDownloadsChanged);
    _downloadService.downloadedChapterKeys.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    _downloadService.activeDownloads.removeListener(_onDownloadsChanged);
    _downloadService.downloadedChapterKeys.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    _refreshDownloads();
  }

  Future<void> _refreshDownloads() async {
    final books = await _downloadService.getDownloadedBooks();
    if (mounted) {
      setState(() {
        _downloadedBooks = books;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    final books = await _downloadService.getDownloadedBooks();
    if (mounted) {
      setState(() {
        _downloadedBooks = books;
        _isLoading = false;
      });
    }
  }

  void _playDownloaded(DownloadedAudiobook downloaded) {
    // Convert downloaded chapters to AudiobookChapter with local file:// URLs
    final chapters = downloaded.chapters
        .where((c) => c.sizeBytes > 0)
        .map((c) => AudiobookChapter(
              title: c.title,
              url: c.filePath,
            ))
        .toList();

    if (chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No downloaded chapters available')),
      );
      return;
    }

    final musicService = MusicPlayerService();

    if (Platform.isWindows || MediaQuery.of(context).size.width > 900) {
      musicService.isFullScreenVisible.value = true;
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 850),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AudiobookPlayerScreen(
                audiobook: downloaded.book,
                chapters: chapters,
              ),
            ),
          ),
        ),
      ).then((_) {
        musicService.isFullScreenVisible.value = false;
      });
    } else {
      musicService.isFullScreenVisible.value = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AudiobookPlayerScreen(
            audiobook: downloaded.book,
            chapters: chapters,
          ),
        ),
      ).then((_) {
        musicService.isFullScreenVisible.value = false;
      });
    }
  }

  void _deleteDownload(DownloadedAudiobook book) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B2E),
        title: const Text('Delete Download', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${book.book.title}" and all its chapters?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _downloadService.deleteBook(book.book.audioBookId);
      _loadDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            // Active downloads
            ValueListenableBuilder<Map<String, AudiobookDownloadProgress>>(
              valueListenable: _downloadService.activeDownloads,
              builder: (context, downloads, _) {
                final active = downloads.values
                    .where((d) => d.status == 'downloading')
                    .toList();
                if (active.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        'DOWNLOADING',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ...active.map((d) => _buildActiveDownloadTile(d)),
                  ],
                );
              },
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primaryColor))
                  : _downloadedBooks.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded,
                                  color: Colors.white24, size: 64),
                              SizedBox(height: 16),
                              Text('No downloads yet',
                                  style: TextStyle(color: Colors.white54)),
                              SizedBox(height: 8),
                              Text(
                                'Download audiobooks from the player\nto listen offline',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDownloads,
                          color: AppTheme.primaryColor,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: _downloadedBooks.length,
                            itemBuilder: (context, index) =>
                                _buildDownloadedBookTile(
                                    _downloadedBooks[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'Downloads',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins'),
          ),
          const Spacer(),
          Text(
            '${_downloadedBooks.length} book${_downloadedBooks.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDownloadTile(AudiobookDownloadProgress progress) {
    final book = progress.book;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: book.thumbUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorWidget: (c, u, e) => CachedNetworkImage(
                imageUrl: book.coverImage,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (c, u, e) => Container(
                  width: 48,
                  height: 48,
                  color: Colors.white10,
                  child: const Icon(Icons.book, color: Colors.white24, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${progress.completedChapters} / ${progress.totalChapters} items',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 4,
                    color: AppTheme.primaryColor,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () =>
                _downloadService.cancelDownload(progress.audioBookId),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedBookTile(DownloadedAudiobook book) {
    final coverFile = File(book.coverPath);
    final hasCover = coverFile.existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TvInkWell(
        onTap: () => _playDownloaded(book),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasCover
                    ? Image.file(coverFile,
                        width: 72, height: 72, fit: BoxFit.cover)
                    : Container(
                        width: 72,
                        height: 72,
                        color: Colors.white10,
                        child: const Icon(Icons.book,
                            color: Colors.white24, size: 32),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${book.chapters.length} chapters  •  ${_downloadService.formatBytes(book.totalSizeBytes)}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSource(book.book.source),
                      style: const TextStyle(
                          color: AppTheme.primaryColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_fill,
                      color: AppTheme.primaryColor, size: 36),
                  const SizedBox(height: 8),
                  TvGestureTap(
                    onTap: () => _deleteDownload(book),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white38, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSource(String? source) {
    switch (source) {
      case 'tokybook':
        return 'Tokybook';
      case 'audiozaic':
        return 'Audiozaic';
      case 'goldenaudiobook':
        return 'GoldenAudiobook';
      case 'appaudiobooks':
        return 'AppAudiobooks';
      case 'magnet':
        return 'Magnet';
      case 'audiobookbay':
        return 'Audiobook Bay';
      case 'ezaudiobookforsoul':
        return 'EzAudiobookForSoul';
      default:
        return source ?? 'Unknown';
    }
  }
}
