import 'package:flutter/material.dart';

/// Photorealistic book-character portraits for profile pictures.
class LiteraryAvatarInfo {
  const LiteraryAvatarInfo(this.label, this.subtitle, this.assetPath);

  final String label;
  final String subtitle;
  final String assetPath;
}

const List<LiteraryAvatarInfo> kLiteraryAvatars = [
  LiteraryAvatarInfo('Storyteller', 'Open golden book', 'assets/avatars/01_storyteller.png'),
  LiteraryAvatarInfo('Wizard', 'Spellbook & wand', 'assets/avatars/02_wizard.png'),
  LiteraryAvatarInfo('Detective', 'Mystery journal', 'assets/avatars/03_detective.png'),
  LiteraryAvatarInfo('Princess', 'Fairy tale folio', 'assets/avatars/04_princess.png'),
  LiteraryAvatarInfo('Pirate', 'Captain\'s log', 'assets/avatars/05_pirate.png'),
  LiteraryAvatarInfo('Scholar', 'Ancient tome', 'assets/avatars/06_scholar.png'),
  LiteraryAvatarInfo('Knight', 'Hero\'s chronicle', 'assets/avatars/07_knight.png'),
  LiteraryAvatarInfo('Dragon', 'Fantasy grimoire', 'assets/avatars/08_dragon.png'),
  LiteraryAvatarInfo('Voyager', 'Star atlas', 'assets/avatars/09_voyager.png'),
  LiteraryAvatarInfo('Romantic', 'Poetry volume', 'assets/avatars/10_romantic.png'),
  LiteraryAvatarInfo('Gothic', 'Dark novel', 'assets/avatars/11_gothic.png'),
  LiteraryAvatarInfo('Dreamer', 'Picture books', 'assets/avatars/12_dreamer.png'),
];

int clampLiteraryAvatarIndex(int index) =>
    index % kLiteraryAvatars.length;

/// Circular profile avatar with bundled book/character art.
class LiteraryCharacterAvatar extends StatelessWidget {
  const LiteraryCharacterAvatar({
    super.key,
    required this.index,
    this.size = 56,
    this.selected = false,
  });

  final int index;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final i = clampLiteraryAvatarIndex(index);
    final info = kLiteraryAvatars[i];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: const Color(0xFFE8B86D), width: 3)
            : Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFFE8B86D).withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Image.asset(
          info.assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: const Color(0xFF1A1A22),
            child: Icon(Icons.menu_book_rounded, size: size * 0.5, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}
