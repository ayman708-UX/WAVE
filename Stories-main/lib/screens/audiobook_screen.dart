import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/audiobook_service.dart';
import '../api/android_auto_browse.dart';
import '../api/audiobook_player_service.dart';
import '../api/music_player_service.dart';
import '../api/settings_service.dart';
import '../services/playtorrio_cloud_sync_service.dart';
import '../utils/app_theme.dart';
import '../widgets/audiobook_thumb.dart';
import '../widgets/literary_character_avatar.dart';
import '../platform_flags.dart';
import 'audiobook_player_screen.dart';
import 'audiobook_downloads_screen.dart';
import 'generate_audiobook_screen.dart';
import '../widgets/tv_interactive.dart';
import '../widgets/app_update_prompt.dart';
import '../widgets/background_policy_prompt.dart';
import '../services/app_update_service.dart';
import 'audiobook_magnet_screen.dart';
import 'settings_screen.dart';

enum _AudiobookShelf { browse, liked, bookmarks }

class AudiobookScreen extends StatefulWidget {
  const AudiobookScreen({super.key, this.initWarning});

  /// Shown once when background audio / torrent init partially failed.
  final String? initWarning;

  @override
  State<AudiobookScreen> createState() => _AudiobookScreenState();
}

class _AudiobookScreenState extends State<AudiobookScreen> with WidgetsBindingObserver {
  final AudiobookService _service = AudiobookService();
  final AudiobookPlayerService _playerService = AudiobookPlayerService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Audiobook> _books = [];
  List<Audiobook> _likedBooks = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  int _currentOffset = 0;
  final int _limit = 12;
  bool _isSearching = false;
  _AudiobookShelf _shelf = _AudiobookShelf.browse;
  List<Map<String, dynamic>> _bookmarks = [];
  Set<String> _bookmarkIds = {};
  VoidCallback? _audiobookPrefsListener;
  VoidCallback? _avatarListener;
  int _avatarIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audiobookPrefsListener = () {
      if (!mounted) return;
      _reloadCloudBackedShelves();
    };
    SettingsService.audiobookPrefsChangeNotifier
        .addListener(_audiobookPrefsListener!);
    _avatarListener = () {
      if (!mounted) return;
      _loadUserAvatar();
    };
    SettingsService.userAvatarChangeNotifier.addListener(_avatarListener!);
    _loadBooks();
    _loadUserAvatar();
    _reloadCloudBackedShelves();
    final warning = widget.initWarning;
    if (warning != null && warning.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning)),
        );
      });
    }
    if (platformIsAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOfferAppUpdate());
        unawaited(showUnrestrictedDataReminder(context));
      });
    }
  }

  Future<void> _maybeOfferAppUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptKey = 'stories_update_prompt_remote_build';
      final lastPromptRemoteBuild = prefs.getInt(promptKey) ?? 0;

      final offer = await AppUpdateService.instance.checkForUpdate();
      if (!mounted || offer == null) return;

      if (offer.remoteBuild <= lastPromptRemoteBuild) return;

      await prefs.setInt(promptKey, offer.remoteBuild);
      if (!mounted) return;
      await showAppUpdateDialog(context, offer);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_audiobookPrefsListener != null) {
      SettingsService.audiobookPrefsChangeNotifier
          .removeListener(_audiobookPrefsListener!);
    }
    if (_avatarListener != null) {
      SettingsService.userAvatarChangeNotifier.removeListener(_avatarListener!);
    }
    _searchController.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pullCloudAudiobookPrefs();
    }
  }

  Future<void> _loadUserAvatar() async {
    final avatar = await SettingsService().getUserAvatarIndex();
    if (mounted) setState(() => _avatarIndex = avatar);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    if (!mounted) return;
    await Future.wait([
      _reloadCloudBackedShelves(),
      _loadUserAvatar(),
    ]);
  }

  Future<void> _pullCloudAudiobookPrefs() async {
    try {
      await PlaytorrioCloudSyncService.instance.pullUserSettings();
    } catch (_) {}
    if (mounted) await _reloadCloudBackedShelves();
  }

  Future<void> _reloadCloudBackedShelves() async {
    await Future.wait([
      _loadHistory(),
      _loadLikedBooks(),
      _loadBookmarkIds(),
      _loadBookmarks(),
    ]);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final history = await _playerService.getHistory();
    if (mounted) {
      setState(() => _history = history);
    }
    unawaited(AndroidAutoBrowse.warmCache());
  }

  Future<void> _loadLikedBooks() async {
    final liked = await _playerService.getLikedBooks();
    if (mounted) {
      setState(() => _likedBooks = liked);
    }
  }

  Future<void> _loadBookmarkIds() async {
    final ids = await _playerService.getBookmarkedAudioBookIds();
    if (mounted) setState(() => _bookmarkIds = ids);
  }

  Future<void> _loadBookmarks() async {
    final list = await _playerService.getBookmarks();
    if (mounted) setState(() => _bookmarks = list);
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoading = true;
      _shelf = _AudiobookShelf.browse;
    });
    final books = await _service.getAudiobooks(offset: _currentOffset, limit: _limit);
    if (!mounted) return;
    setState(() {
      _books = books;
      _isLoading = false;
      _isSearching = false;
    });
  }

  Future<void> _onSearch(String query) async {
    if (query.isEmpty) {
      _currentOffset = 0;
      _loadBooks();
      return;
    }
    setState(() {
      _isLoading = true;
      _isSearching = true;
      _shelf = _AudiobookShelf.browse;
    });
    final results = await _service.searchAudiobooks(query);
    setState(() {
      _books = results;
      _isLoading = false;
    });
  }

  void _toggleLikedShelf() {
    setState(() {
      if (_shelf == _AudiobookShelf.liked) {
        _shelf = _AudiobookShelf.browse;
      } else {
        _shelf = _AudiobookShelf.liked;
        _isSearching = false;
      }
    });
    if (_shelf == _AudiobookShelf.liked) _loadLikedBooks();
  }

  void _toggleBookmarkShelf() {
    setState(() {
      if (_shelf == _AudiobookShelf.bookmarks) {
        _shelf = _AudiobookShelf.browse;
      } else {
        _shelf = _AudiobookShelf.bookmarks;
        _isSearching = false;
      }
    });
    if (_shelf == _AudiobookShelf.bookmarks) _loadBookmarks();
  }

  void _nextPage() {
    setState(() {
      _currentOffset += _limit;
    });
    _loadBooks();
  }

  void _prevPage() {
    if (_currentOffset >= _limit) {
      setState(() {
        _currentOffset -= _limit;
      });
      _loadBooks();
    }
  }

  void _resumeAudiobook(Map<String, dynamic> progress) async {
    final entry = progress;
    final rawBook = entry['book'];
    if (rawBook is! Map) return;
    final book =
        Audiobook.fromJson(Map<String, dynamic>.from(rawBook as Map));

    final ciRaw = entry['chapterIndex'];
    var chapterIndex = ciRaw is int
        ? ciRaw
        : (ciRaw is num ? ciRaw.toInt() : int.tryParse('$ciRaw') ?? 0);

    final pmRaw = entry['positionMs'];
    var positionMs = pmRaw is int
        ? pmRaw
        : (pmRaw is num ? pmRaw.toInt() : int.tryParse('$pmRaw') ?? 0);

    final isPlaceholder = entry['placeholderBookmark'] == true;

    // Grid "title only" bookmarks merge Continue Listening when present.
    if (isPlaceholder) {
      final hist = await _playerService.getHistory();
      for (final h in hist) {
        final b = h['book'];
        if (b is! Map) continue;
        if ('${b['audioBookId']}' != book.audioBookId) continue;
        final hciRaw = h['chapterIndex'];
        final hpmRaw = h['positionMs'];
        chapterIndex = hciRaw is int
            ? hciRaw
            : (hciRaw is num ? hciRaw.toInt() : int.tryParse('$hciRaw') ?? 0);
        positionMs = hpmRaw is int
            ? hpmRaw
            : (hpmRaw is num ? hpmRaw.toInt() : int.tryParse('$hpmRaw') ?? 0);
        break;
      }
    }

    final hasSavedPlace = chapterIndex > 0 || positionMs > 0;

    _openAudiobook(
      book,
      initialChapter: chapterIndex,
      initialPosition: hasSavedPlace
          ? Duration(milliseconds: positionMs)
          : null,
    );
  }

  String _formatPlaybackOffset(int positionMs) {
    final totalSeconds = (positionMs / 1000).floor();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _bookmarkResumeLabel(Map<String, dynamic> entry) {
    final isPlaceholder = entry['placeholderBookmark'] == true;
    final ciRaw = entry['chapterIndex'];
    final chapterIndex = ciRaw is int
        ? ciRaw
        : (ciRaw is num ? ciRaw.toInt() : int.tryParse('$ciRaw') ?? 0);
    final pmRaw = entry['positionMs'];
    final positionMs = pmRaw is int
        ? pmRaw
        : (pmRaw is num ? pmRaw.toInt() : int.tryParse('$pmRaw') ?? 0);

    if (isPlaceholder && chapterIndex == 0 && positionMs == 0) {
      return 'Tap to open';
    }
    final chapterLabel = 'Chapter ${chapterIndex + 1}';
    if (positionMs > 0) {
      return '$chapterLabel · ${_formatPlaybackOffset(positionMs)}';
    }
    return chapterLabel;
  }

  void _removeFromHistory(String audioBookId) async {
    await _playerService.removeFromHistory(audioBookId);
    _loadHistory();
  }

  void _openAudiobook(Audiobook book, {int initialChapter = 0, Duration? initialPosition}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
    );

    final prepared = await _service.prepareAudiobookPlayback(
      book,
      warmChapterIndex: initialChapter,
    );
    final playbackBook = prepared.book;
    final chapters = prepared.chapters;

    if (mounted) {
      Navigator.pop(context); 
      final musicService = MusicPlayerService();
      if (chapters.isNotEmpty) {
        if (platformIsWindows || MediaQuery.of(context).size.width > 900) {
          musicService.isFullScreenVisible.value = true;
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 850),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AudiobookPlayerScreen(
                    audiobook: playbackBook,
                    chapters: chapters,
                    initialChapterIndex: initialChapter,
                    initialPosition: initialPosition,
                  ),
                ),
              ),
            ),
          ).then((_) {
            musicService.isFullScreenVisible.value = false;
            _loadHistory();
            _loadBookmarkIds();
            if (_shelf == _AudiobookShelf.bookmarks) _loadBookmarks();
          });
        } else {
          musicService.isFullScreenVisible.value = true;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AudiobookPlayerScreen(
                audiobook: playbackBook,
                chapters: chapters,
                initialChapterIndex: initialChapter,
                initialPosition: initialPosition,
              ),
            ),
          ).then((_) {
            musicService.isFullScreenVisible.value = false;
            _loadHistory();
            _loadBookmarkIds();
            if (_shelf == _AudiobookShelf.bookmarks) _loadBookmarks();
          }); 
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load audio tracks. Book might be restricted.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _pullCloudAudiobookPrefs();
                  await _loadBooks();
                },
                color: AppTheme.primaryColor,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      if (!_isSearching && _history.isNotEmpty) _buildHistoryCarousel(),
                      _buildBody(),
                    ],
                  ),
                ),
              ),
            ),
            if (!_isSearching && _shelf == _AudiobookShelf.browse) _buildPagination(),
          ],
        ),
      ),
      ),
    );
  }

  void _goHome() {
    setState(() {
      _shelf = _AudiobookShelf.browse;
      _isSearching = false;
      _searchController.clear();
      if (_currentOffset != 0) {
        _currentOffset = 0;
        _loadBooks();
      }
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: _goHome,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: AppTheme.title(),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _openSettings,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: LiteraryCharacterAvatar(
                    index: _avatarIndex,
                    size: 34,
                    selected: false,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: AppTheme.textSecondary, size: 22),
                tooltip: 'Settings & account',
                onPressed: _openSettings,
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome_outlined,
                    color: AppTheme.textSecondary, size: 22),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GenerateAudiobookScreen()),
                  ).then((_) => _loadHistory());
                },
                tooltip: 'Generate your own audiobook',
              ),
              if (!platformIsWeb)
                IconButton(
                  icon: const Icon(Icons.link_rounded,
                      color: AppTheme.textSecondary, size: 22),
                  tooltip: 'Add audiobook from magnet link',
                  onPressed: () async {
                    final book = await Navigator.push<Audiobook>(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const AudiobookMagnetScreen()),
                    );
                    if (book != null && mounted) {
                      setState(() {
                        _books.removeWhere((b) => b.audioBookId == book.audioBookId);
                        _books.insert(0, book);
                      });
                      _openAudiobook(book);
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.download_rounded,
                    color: AppTheme.textSecondary, size: 24),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AudiobookDownloadsScreen()),
                  );
                },
                tooltip: 'Downloads',
              ),
              IconButton(
                icon: Icon(
                  _shelf == _AudiobookShelf.liked
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _shelf == _AudiobookShelf.liked
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                  size: 24,
                ),
                onPressed: _toggleLikedShelf,
                tooltip: 'Liked audiobooks',
              ),
              IconButton(
                icon: Icon(
                  _shelf == _AudiobookShelf.bookmarks
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: _shelf == _AudiobookShelf.bookmarks
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                  size: 24,
                ),
                onPressed: _toggleBookmarkShelf,
                tooltip: 'Bookmarked (syncs with account)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: TextField(
        controller: _searchController,
        onSubmitted: _onSearch,
        style: AppTheme.body.copyWith(fontSize: 15),
        decoration: const InputDecoration(
          hintText: 'Search stories, authors, series…',
          prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 22),
        ),
      ),
    );
  }

  Widget _buildHistoryCarousel() {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final pageController = PageController(viewportFraction: isDesktop ? 0.45 : 0.9);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CONTINUE LISTENING', style: AppTheme.sectionTitle),
              if (isDesktop && _history.length > 1)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: () {
                        pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      color: AppTheme.textSecondary,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: () {
                        pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: pageController,
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final progress = _history[index];
              final book = Audiobook.fromJson(progress['book']);
              final title = book.title;
              final chapterIdx = progress['chapterIndex'] + 1;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Stack(
                  children: [
                    FocusableControl(
                      onTap: () => _resumeAudiobook(progress),
                      borderRadius: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: audiobookThumb(book.thumbUrl),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text('Chapter $chapterIdx', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_circle_fill, color: AppTheme.primaryColor, size: 40),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 4,
                      child: TvGestureTap(
                        onTap: () => _removeFromHistory(book.audioBookId),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookmarkGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1200) {
      crossAxisCount = 6;
    } else if (screenWidth > 900) {
      crossAxisCount = 4;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 150),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.68,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final entry = _bookmarks[index];
        final rawBook = entry['book'];
        if (rawBook is! Map) return const SizedBox.shrink();
        final book = Audiobook.fromJson(Map<String, dynamic>.from(rawBook));
        return _buildBookCard(book, bookmarkResume: entry);
      },
    );
  }

  Widget _buildBody() {
    if (_shelf == _AudiobookShelf.bookmarks) {
      if (_bookmarks.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Center(
            child: Text(
              'No bookmarks yet\nOpen a title and tap the bookmark icon while listening to save your place (syncs when logged in).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.35),
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              'Tap a title to resume at your saved place',
              style: AppTheme.body.copyWith(
                color: AppTheme.primaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildBookmarkGrid(),
        ],
      );
    }

    final displayBooks =
        _shelf == _AudiobookShelf.liked ? _likedBooks : _books;

    if (_isLoading && _shelf == _AudiobookShelf.browse) {
      return const Padding(
          padding: EdgeInsets.only(top: 100),
          child: Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primaryColor)));
    }
    if (displayBooks.isEmpty) {
      final msg = _shelf == _AudiobookShelf.liked
          ? 'No liked audiobooks'
          : 'No audiobooks found';
      return Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Center(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white54))));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1200) {
      crossAxisCount = 6;
    } else if (screenWidth > 900) {
      crossAxisCount = 4;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: displayBooks.length,
      itemBuilder: (context, index) {
        final book = displayBooks[index];
        return _buildBookCard(book);
      },
    );
  }

  Widget _buildBookCard(Audiobook book, {Map<String, dynamic>? bookmarkResume}) {
    final isLiked = _likedBooks.any((b) => b.audioBookId == book.audioBookId);
    final resumeLabel =
        bookmarkResume != null ? _bookmarkResumeLabel(bookmarkResume!) : null;

    return FocusableControl(
      onTap: bookmarkResume != null
          ? () => _resumeAudiobook(bookmarkResume!)
          : () => _openAudiobook(book),
      borderRadius: 16,
      child: Container(
        decoration: AppTheme.cardDecoration(radius: 14),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      book.thumbUrl.startsWith('http://') ||
                              book.thumbUrl.startsWith('https://')
                          ? CachedNetworkImage(
                              imageUrl: book.thumbUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) =>
                                  Container(color: Colors.white10),
                              errorWidget: (context, url, error) =>
                                  CachedNetworkImage(
                                imageUrl: book.coverImage,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (c, u, e) => const Center(
                                    child: Icon(Icons.book,
                                        color: Colors.white24)),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: audiobookThumb(book.thumbUrl,
                                  width: 480, height: 720),
                            ),
                      if (bookmarkResume != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF1A1208),
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (resumeLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          resumeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: bookmarkResume == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TvGestureTap(
                          onTap: () async {
                            await _playerService.toggleBookmarkGrid(book);
                            await _loadBookmarkIds();
                            if (_shelf == _AudiobookShelf.bookmarks) {
                              await _loadBookmarks();
                            }
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _bookmarkIds.contains(book.audioBookId)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: _bookmarkIds.contains(book.audioBookId)
                                  ? Colors.amberAccent
                                  : Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TvGestureTap(
                          onTap: () async {
                            await _playerService.toggleLikeBook(book);
                            _loadLikedBooks();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color:
                                  isLiked ? Colors.redAccent : Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await _playerService.removeBookmark(book.audioBookId);
                        await _reloadCloudBackedShelves();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bookmark removed'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white70, size: 18),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination() {
    if (_shelf != _AudiobookShelf.browse) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: _currentOffset > 0 ? _prevPage : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bgCard,
              foregroundColor: AppTheme.textPrimary,
            ),
            child: const Text('Previous'),
          ),
          Text('Page ${(_currentOffset / _limit).floor() + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: const Color(0xFF1A1208),
            ),
            child: const Text('Next Page'),
          ),
        ],
      ),
    );
  }

}
