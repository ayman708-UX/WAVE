/// Android Auto media ID helpers (no app dependencies).
abstract final class AndroidAutoIds {
  static const continueParentId = 'stories_continue';
  static const nowPlayingParentId = 'stories_now_playing';
  static const resumePrefix = 'stories_resume_';
  static const chapterPrefix = 'stories_chapter_';

  static String resume(String audioBookId) => '$resumePrefix$audioBookId';

  static String chapter(String audioBookId, int index) =>
      '$chapterPrefix${audioBookId}_$index';
}
