// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get interfaceLanguage => 'Interface language';

  @override
  String get interfaceLanguageNote =>
      'This changes the interface language. Translations and AI responses stay in Indonesian.';

  @override
  String get languageSaveFailed => 'Couldn’t save the language. Try again.';

  @override
  String bookImporting(Object p0) {
    return 'Importing $p0';
  }

  @override
  String get bookProcessing => 'Processing';

  @override
  String get bookNew => 'New';

  @override
  String get bookFinished => 'Finished!';

  @override
  String bookChapters(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 chapters',
      one: '1 chapter',
    );
    String _temp1 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$_temp0',
      one: '1 chapter',
    );
    return '$_temp1';
  }

  @override
  String get aiCopy => 'Copy';

  @override
  String aiUnavailable(Object p0, Object p1) {
    return '$p0, unavailable: $p1';
  }

  @override
  String get bookCloseMenu => 'Close menu';

  @override
  String get searchSearchResults => 'Search results';

  @override
  String get searchPreviousResult => 'Previous result';

  @override
  String get searchBackToResults => 'Back to results';

  @override
  String searchOf(Object p0, Object p1) {
    return '$p0 of $p1';
  }

  @override
  String searchOf2(Object p0, Object p1, Object p2) {
    return '$p0 of $p1 · $p2';
  }

  @override
  String get searchNextResult => 'Next result';

  @override
  String get searchExitSearch => 'Exit search';

  @override
  String get searchClearField => 'Clear field';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get sheetClose => 'Close';

  @override
  String get searchCurrentlyReading => 'Currently reading';

  @override
  String searchResults(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String fieldClear(Object p0) {
    return 'Clear $p0';
  }

  @override
  String get fieldShowKey => 'Show key';

  @override
  String get fieldHideKey => 'Hide key';

  @override
  String get navMainNavigation => 'Main navigation';

  @override
  String navActiveDownloads(Object p0, Object p1) {
    return '$p0, $p1 active downloads';
  }

  @override
  String get bookSearchThisBook => 'Search this book';

  @override
  String bookNoMatchesForInThisBook(Object p0) {
    return 'No matches for “$p0” in this book';
  }

  @override
  String get bookCheckTheSpellingOrTryAnother =>
      'Check the spelling or try another word.';

  @override
  String get bookSearchIsStuck => 'Search is stuck';

  @override
  String get bookCloseItAndTryAgain => 'Close it and try again.';

  @override
  String get bookRecentSearches => 'Recent searches';

  @override
  String get bookClear => 'Clear';

  @override
  String get bookTooManyResultsTryAMore =>
      'Too many results. Try a more specific word';

  @override
  String get bookPreparingSearch => 'Preparing search…';

  @override
  String get bookJustOnceForThisBookSearches =>
      'Just once for this book. Searches will be instant after this.';

  @override
  String get readerCouldnTOpenTheChatTry =>
      'Couldn’t open the chat. Try reopening the book.';

  @override
  String get readerBackToYourPreviousPosition =>
      'Back to your previous position?';

  @override
  String get readerGoBack => 'Go back';

  @override
  String get readerThisSourceIsNoLongerAvailable =>
      'This source is no longer available.';

  @override
  String get readerPreviewingNoReadingProgressYet =>
      'Previewing · no reading progress yet';

  @override
  String readerPreviewingSavedPositionParagraph(Object p0, Object p1) {
    return 'Previewing · saved position: $p0 · Paragraph $p1';
  }

  @override
  String get readerCouldnTOpenTheBook => 'Couldn’t open the book';

  @override
  String get meaningCopiedReadyToPaste => 'Copied, ready to paste';

  @override
  String get meaningTimeoutSeconds => 'timeout · 30 seconds';

  @override
  String get meaningOfflineDisconnected => 'offline / disconnected';

  @override
  String meaningHttpKeyRejected(Object p0) {
    return 'HTTP $p0 · key rejected';
  }

  @override
  String get meaningHttpNoCredit => 'HTTP 402 · no credit';

  @override
  String get meaningInvalidAiResponse => 'invalid AI response';

  @override
  String get meaningTranslationAndMeaningComplete =>
      'Translation and meaning complete';

  @override
  String get meaningWritingTranslationAndMeaning =>
      'Writing translation and meaning';

  @override
  String get meaningHangOnThinking => 'Hang on, thinking...';

  @override
  String get meaningHereSWhatItMeans => 'Here’s what it means';

  @override
  String get meaningCancel => 'Cancel';

  @override
  String get meaningTranslation => 'Translation';

  @override
  String get meaningWhatTheAuthorMeans => 'What the author means...';

  @override
  String get meaningCopied => 'Copied';

  @override
  String get meaningAskAboutThis => 'Ask about this';

  @override
  String get meaningThinking => 'Thinking';

  @override
  String get meaningWriting => 'Writing';

  @override
  String get meaningNext => 'Next';

  @override
  String get meaningTakingALittleLonger => 'Taking a little longer...';

  @override
  String get meaningTheAiIsStillThinkingGive =>
      'The AI is still thinking. Give it a moment or try again.';

  @override
  String get meaningTryAgain => 'Try again';

  @override
  String get meaningCutOffHalfway => 'Cut off halfway';

  @override
  String get meaningTheConnectionDroppedWhileWritingWhat =>
      'The connection dropped while writing. What came through is still here.';

  @override
  String get meaningCouldnTGetTheMeaning => 'Couldn’t get the meaning';

  @override
  String get meaningSomethingWentWrong => 'Something went wrong';

  @override
  String get meaningTheConnectionMightBeDownOr =>
      'The connection might be down or the AI busy. Give it another try.';

  @override
  String get meaningMaybeLater => 'Maybe later';

  @override
  String get meaningAddYourApiKeyFirst => 'Add your API key first';

  @override
  String get meaningTranslationsAndMeaningsUseAiThrough =>
      'Translations and meanings use AI through OpenRouter. Paste your API key in Settings once, then just tap paragraphs.';

  @override
  String get meaningDonTHaveOneCreateIt => 'Don’t have one? Create it at ';

  @override
  String get meaningOpenSettings => 'Open Settings';

  @override
  String get meaningOpenBreakdown => 'Open breakdown';

  @override
  String get meaningStillPuzzledBreakItDown => 'Still puzzled? Break it down';

  @override
  String meaningPreviouslyBrokenDown(Object p0) {
    return 'Previously broken down · $p0';
  }

  @override
  String get meaningSectionBySectionPlusPeopleTerms =>
      'Section by section, plus people & terms';

  @override
  String get chapterSourceMissing => 'Source missing';

  @override
  String get chapterCurrentlyOpenParagraphGroup =>
      'Currently open paragraph group';

  @override
  String get chapterSceneBreak => 'Scene break';

  @override
  String get readerReadingMenu => 'Reading menu';

  @override
  String get readerBackToShelf => 'Back to shelf';

  @override
  String get readerContents => 'Contents';

  @override
  String get readerMoreActions => 'More actions';

  @override
  String get readerBookChat => 'Book chat';

  @override
  String get readerBookProgress => 'Book progress';

  @override
  String get bookBook => 'Book ';

  @override
  String get bookFinished2 => 'finished!';

  @override
  String bookYouReadRightToTheLast(Object p0) {
    return 'You read $p0 right to the last sentence. Nicely done.';
  }

  @override
  String get bookReadingTime => 'reading time';

  @override
  String get bookParagraphsTranslated => 'paragraphs translated';

  @override
  String get bookBackToShelfFindAnotherBook =>
      'Back to shelf, find another book';

  @override
  String get bookReadAgainFromTheStart => 'Read again from the start';

  @override
  String chapterChapterOfMin(Object p0, Object p1, Object p2) {
    return 'Chapter $p0 of $p1 · ~$p2 min';
  }

  @override
  String tocChaptersRead(Object p0, int p1, Object p2) {
    String _temp0 = intl.Intl.pluralLogic(
      p1,
      locale: localeName,
      other: '$p1 chapters',
      one: '1 chapter',
    );
    return '$p0 · $_temp0 · $p2% read';
  }

  @override
  String tocCurrentlyReadingMin(Object p0) {
    return 'Currently reading · ~$p0 min';
  }

  @override
  String tocMin(Object p0) {
    return '~$p0 min';
  }

  @override
  String readerFinished(Object p0) {
    return '$p0 finished';
  }

  @override
  String readerMinLeft(Object p0) {
    return '~$p0 min left';
  }

  @override
  String get readerChatAboutTheBook => 'Chat about the book';

  @override
  String get readerBackToChat => 'Back to chat';

  @override
  String get readerKeepReading => 'Keep reading';

  @override
  String get readYouLastReadHere => 'You last read here';

  @override
  String get chapterChapterFinished => 'Chapter finished';

  @override
  String chapterParagraphsTranslated(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 paragraphs',
      one: '1 paragraph',
    );
    return '$_temp0 translated';
  }

  @override
  String get chapterThatWasTheLastChapter => 'That was the last chapter!';

  @override
  String chapterContinueTo(Object p0) {
    return 'Continue to $p0?';
  }

  @override
  String get chapterOneMoreTapToFinishThe => 'One more tap to finish the book';

  @override
  String get chapterLetSKeepGoing => 'Let’s keep going';

  @override
  String get chapterStopHereBackToShelf => 'Stop here, back to shelf';

  @override
  String get readerSearchWords => 'Search words';

  @override
  String readerViewResultsFor(Object p0) {
    return 'View results for “$p0”';
  }

  @override
  String get readerReadingAppearance => 'Reading appearance';

  @override
  String get readerSizeFontTheme => 'Size, font, theme';

  @override
  String get aaMakeItYours => 'Make it yours';

  @override
  String get aaTextSize => 'Text size';

  @override
  String get aaFont => 'Font';

  @override
  String get aaClear => 'Clear';

  @override
  String get aaBookLike => 'Book-like';

  @override
  String get aaSystemDefault => 'System default';

  @override
  String get aaLineSpacing => 'Line spacing';

  @override
  String get aaTight => 'Tight';

  @override
  String get aaBalanced => 'Balanced';

  @override
  String get aaRoomy => 'Roomy';

  @override
  String get aaMargins => 'Margins';

  @override
  String get aaNarrow => 'Narrow';

  @override
  String get aaTheme => 'Theme';

  @override
  String get aaLight => 'Light';

  @override
  String get aaDark => 'Dark';

  @override
  String get aaSystem => 'System';

  @override
  String get aaScreenDisplay => 'Screen display';

  @override
  String get aaHideClockBattery => 'Hide clock & battery';

  @override
  String get aaHideTheStatusBarWithThe =>
      'Hide the status bar with the reading menu';

  @override
  String get aaShowProgressLine => 'Show progress line';

  @override
  String get aaAThinLineAtTheBottom =>
      'A thin line at the bottom when the menu is hidden';

  @override
  String get aaSmallerText => 'Smaller text';

  @override
  String get aaLargerText => 'Larger text';

  @override
  String aaFont2(Object p0) {
    return 'Font $p0';
  }

  @override
  String aaTheme2(Object p0) {
    return 'Theme $p0';
  }

  @override
  String get backupBackupCompleteAllSafe => 'Backup complete, all safe!';

  @override
  String get backupBackupFailed => 'Backup failed';

  @override
  String get backupTryAgainInAMoment => 'Try again in a moment';

  @override
  String get settingsYourDataIsBack => 'Your data is back!';

  @override
  String settingsBooksTranslations(int p0, int p1) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);
    final intl.NumberFormat p1NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p1String = p1NumberFormat.format(p1);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String books',
      one: '$p0String book',
    );
    String _temp1 = intl.Intl.pluralLogic(
      p1,
      locale: localeName,
      other: '$p1String translations',
      one: '$p1String translation',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get settingsApiKeysArenTIncludedIn =>
      'API keys aren’t included in backups. Add yours again to translate.';

  @override
  String get settingsAddKey => 'Add key';

  @override
  String get settingsDeleteTranslationCache => 'Delete translation cache?';

  @override
  String get settingsAllSavedTranslationsWillBeDeleted =>
      'All saved translations will be deleted. Opening those paragraphs again will request AI and use credit again. Your book chats will stay.';

  @override
  String get settingsYourCatalogIsAlreadyUpTo =>
      'Your catalog is already up to date';

  @override
  String get settingsBack => 'Back';

  @override
  String get settingsSettings => 'Settings';

  @override
  String get settingsOpenrouterApiKey => 'OpenRouter API key';

  @override
  String get settingsAiModel => 'AI model';

  @override
  String get settingsChargesComeFromYourOpenrouterAccount =>
      'Charges come from your OpenRouter account credit.';

  @override
  String get settingsBackupRestore => 'Backup & restore';

  @override
  String get settingsBookCatalog => 'Book catalog';

  @override
  String get settingsAroundProjectGutenbergBooksToSearch =>
      'Around 62,000 Project Gutenberg books to search offline. Updated weekly.';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsStoredSecurelyOnYourDeviceKeychain =>
      'Stored securely on your device (Keychain / Keystore). Sent only to OpenRouter.';

  @override
  String get settingsThatSNotAnOpenrouterApi =>
      'That’s not an OpenRouter API key. Keys start with sk-or-... It hasn’t been saved.';

  @override
  String get settingsOpenrouterRejectedTheKeySoIt =>
      'OpenRouter rejected the key, so it wasn’t saved. Check it and try again.';

  @override
  String get settingsHangOnChecking => 'Hang on, checking...';

  @override
  String get settingsYourKeyWorks => 'Your key works';

  @override
  String get settingsOpenrouterRejectedYourKey =>
      'OpenRouter rejected your key';

  @override
  String get settingsStoredSecurelyOnYourDevice =>
      'Stored securely on your device';

  @override
  String get settingsIncludesBooksReadingProgressTranslationsAnd =>
      'Includes books, reading progress, translations, and settings. ';

  @override
  String get settingsApiKeysArenTIncluded => 'API keys aren’t included';

  @override
  String get settingsSoAddYoursAgainAfterRestoring =>
      ', so add yours again after restoring. Keep the file in iCloud Drive so it survives a reinstall.';

  @override
  String get settingsJustNow => 'Just now';

  @override
  String get settingsBackupStatus => 'Backup status';

  @override
  String get settingsLastBackup => 'Last backup';

  @override
  String get settingsNoBackupsYet => 'No backups yet';

  @override
  String get settingsYourDataIsOnlyOnThis => 'Your data is only on this phone';

  @override
  String get settingsBackUpNow => 'Back up now';

  @override
  String get settingsRestoreFromBackup => 'Restore from backup';

  @override
  String get settingsDefaultMostAccurate => 'Default · most accurate';

  @override
  String get settingsTranslationCache => 'Translation cache';

  @override
  String settingsParagraphs(int p0, Object p1) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String paragraphs',
      one: '$p0String paragraph',
    );
    return '$_temp0 · $p1';
  }

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsNotDownloadedMb => 'Not downloaded · 5.6 MB';

  @override
  String settingsUpdated(Object p0) {
    return 'Updated $p0 · ';
  }

  @override
  String settingsBooks(Object p0, int p1) {
    final intl.NumberFormat p1NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p1String = p1NumberFormat.format(p1);

    String _temp0 = intl.Intl.pluralLogic(
      p1,
      locale: localeName,
      other: '$p1String books',
      one: '$p1String book',
    );
    return '$p0$_temp0';
  }

  @override
  String get settingsCheckingForUpdates => 'Checking for updates…';

  @override
  String get settingsDownloading => 'Downloading…';

  @override
  String settingsDownloading2(Object p0) {
    return 'Downloading $p0%';
  }

  @override
  String get settingsPreparingCatalog => 'Preparing catalog…';

  @override
  String get settingsFailedKeepingThePreviousCatalog =>
      'Failed; keeping the previous catalog';

  @override
  String get settingsDownload => 'Download';

  @override
  String get settingsUpdate => 'Update';

  @override
  String get settingsGutenbergCatalog => 'Gutenberg catalog';

  @override
  String backupBooksReadingProgress(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String books',
      one: '$p0String book',
    );
    return '$_temp0 + reading progress';
  }

  @override
  String backupTranslations(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String translations',
      one: '$p0String translation',
    );
    return '$_temp0';
  }

  @override
  String get backupReadingSettingsAiModel => 'Reading settings & AI model';

  @override
  String get backupBackingUp => 'Backing up';

  @override
  String get backupPackingYourBackup => 'Packing your backup...';

  @override
  String get backupTheShareMenuOpensNextSave =>
      'The share menu opens next. Save to Files / Drive and keep it somewhere safe.';

  @override
  String get restoreRestoreThisBackup => 'Restore this backup?';

  @override
  String get restoreReplaceRestore => 'Replace & restore';

  @override
  String get restoreYourApiKeyWonTBe => 'Your API key won’t be changed.';

  @override
  String restoreCreatedLuma(Object p0, Object p1) {
    return 'Created $p0 · Luma $p1';
  }

  @override
  String get restoreBooksOnShelf => 'books on shelf';

  @override
  String get restoreTranslations => 'translations';

  @override
  String get restoreAllDataOnThisPhoneWill =>
      'All data on this phone will be replaced';

  @override
  String restoreYourCurrentBooksProgressAndTranslations(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String books',
      one: '$p0String book',
    );
    return 'Your current books, progress, and translations ($_temp0) will be replaced with the backup. Your current data can’t be recovered.';
  }

  @override
  String get restoreYesIUnderstandReplaceEverything =>
      'Yes, I understand. Replace everything.';

  @override
  String get restoreRestoring => 'Restoring';

  @override
  String get restoreRestoringYourData => 'Restoring your data...';

  @override
  String get restoreCheckBackupFile => 'Check backup file';

  @override
  String restoreRestoreBooks(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0String books',
      one: '$p0String book',
    );
    return 'Restore $_temp0';
  }

  @override
  String get restoreRestoreProgressTranslations =>
      'Restore progress & translations';

  @override
  String get restoreKeepLumaOpenThisWonT =>
      'Keep Luma open. This won’t take long.';

  @override
  String get restoreThisIsnTALumaBackup => 'This isn’t a Luma backup';

  @override
  String get restoreLumaBackupFilesAreNamedLuma =>
      'Luma backup files are named luma-backup-…zip and come from “Back up now”. Try looking in your file manager.';

  @override
  String get restoreThisBackupIsFromANewer =>
      'This backup is from a newer Luma';

  @override
  String restoreThisFileWasCreatedWithLuma(Object p0, Object p1) {
    return 'This file was created with Luma $p0, but you have $p1. Install the latest Luma, then restore.';
  }

  @override
  String get restoreTheBackupFileIsDamaged => 'The backup file is damaged';

  @override
  String get restoreCouldnTReadTheFileIt =>
      'Couldn’t read the file. It may not have saved completely. Try another backup.';

  @override
  String get restoreCouldnTRestore => 'Couldn’t restore';

  @override
  String get restoreSomethingWentWrongWhileReplacingData =>
      'Something went wrong while replacing data. Everything has been put back as it was.';

  @override
  String get restoreRestoreFailed => 'Restore failed';

  @override
  String get restoreChooseAnotherFile => 'Choose another file';

  @override
  String get restoreYourCurrentDataHasnTBeen =>
      'Your current data hasn’t been touched.';

  @override
  String get importImporting => 'Importing';

  @override
  String get importUnpackingEpub => 'Unpacking EPUB...';

  @override
  String get importReadTitleAuthor => 'Read title & author';

  @override
  String get importGetCover => 'Get cover';

  @override
  String get importSplitIntoChaptersParagraphs =>
      'Split into chapters & paragraphs';

  @override
  String importAdded(Object p0) {
    return 'added $p0';
  }

  @override
  String get importThisBookIsAlreadyOnYour =>
      'This book is already on your shelf';

  @override
  String get importYouVeImportedTheSameBook =>
      'You’ve imported the same book before. Want to continue the existing one?';

  @override
  String get importOpenExistingBook => 'Open existing book';

  @override
  String get importReplaceFile => 'Replace file';

  @override
  String get importReplacingTheFileKeepsYourProgress =>
      'Replacing the file keeps your progress & translations safe.';

  @override
  String get importThisFileIsDamaged => 'This file is damaged';

  @override
  String get importCouldnTOpenThisEpubIt =>
      'Couldn’t open this EPUB. It may be corrupt or only partly downloaded. Download it again, then import.';

  @override
  String importDamagedFile(Object p0) {
    return '$p0 · damaged file';
  }

  @override
  String get importThisIsnTAnEpub => 'This isn’t an EPUB';

  @override
  String get importThisImporterReadsEpubFilesConvert =>
      'This importer reads .epub files. Convert MOBI to EPUB first (for example with Calibre), then import.';

  @override
  String get importThisBookIsDrmLocked => 'This book is DRM-locked';

  @override
  String get importThisEpubIsLockedToIts =>
      'This EPUB is locked to its store’s app. Use a DRM-free EPUB file.';

  @override
  String get importBookTitleCanTBeEmpty => 'Book title can’t be empty';

  @override
  String get importMustBeANumber => 'Must be a number';

  @override
  String get importImport => 'Import';

  @override
  String get importWhichBookIsThisFor => 'Which book is this for?';

  @override
  String get importBookTitle => 'Book title';

  @override
  String get importChapterTitle => 'Chapter title';

  @override
  String get importChapterTitleOptional => 'Chapter title (optional)';

  @override
  String get importChapterNumber => 'Chapter number';

  @override
  String importLastChapterInThisBook(Object p0) {
    return 'Last chapter in this book: $p0';
  }

  @override
  String get importGuessedFromTheFileTitleYou =>
      'Guessed from the file title. You can change it.';

  @override
  String get importNewBook => 'New book';

  @override
  String get importCreateABookFromThisFile => 'Create a book from this file';

  @override
  String get discoverDiscover => 'Discover';

  @override
  String get discoverTitleOrAuthorName => 'Title or author name';

  @override
  String get discoverClearSearch => 'Clear search';

  @override
  String discoverPreparingBookCatalog(Object p0) {
    return 'Preparing book catalog… $p0%';
  }

  @override
  String get discoverPreparingBookCatalog2 => 'Preparing book catalog…';

  @override
  String get discoverCanTReachTheCatalog => 'Can’t reach the catalog';

  @override
  String get discoverItSNotYourFaultGive =>
      'It’s not your fault. Give it another try in a moment.';

  @override
  String get discoverJustOnceThenSearchWorksOffline =>
      'Just once, then search works offline.';

  @override
  String get discoverYouReOffline => 'You’re offline';

  @override
  String get discoverSearchStillWorksPopularBooksDetails =>
      'Search still works. Popular books, details, and downloads need internet. Books on your shelf are still ready to read.';

  @override
  String get discoverOpenShelf => 'Open shelf';

  @override
  String get discoverPopularNow => 'POPULAR NOW';

  @override
  String get discoverTheCatalogIsTakingAWhile =>
      'The catalog is taking a while';

  @override
  String get discoverItSBeenOverSecondsGive =>
      'It’s been over 5 seconds. Give it a moment or try again.';

  @override
  String get discoverTrySearching => 'TRY SEARCHING';

  @override
  String discoverPopular(Object p0) {
    return '#1 popular, $p0';
  }

  @override
  String get discoverPopular2 => '#1 popular';

  @override
  String discoverNoMatchesFor(Object p0) {
    return 'No matches for “$p0”';
  }

  @override
  String get discoverSearchMatchesTitlesAndAuthorNames =>
      'Search matches titles and author names. Check the spelling or try a shorter word.';

  @override
  String discoverResultsFor(Object p0) {
    return 'RESULTS FOR “$p0”';
  }

  @override
  String discoverResultsBestMatchFirst(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 results',
      one: '1 result',
    );
    return '$_temp0 · best match first';
  }

  @override
  String get discoverCouldnTLoadTryAgain => 'Couldn’t load. Try again';

  @override
  String discoverLoadingMore(Object p0) {
    return 'Loading $p0 more…';
  }

  @override
  String discoverBestMatch(Object p0) {
    return 'Best match, $p0';
  }

  @override
  String get discoverBestMatch2 => 'Best match';

  @override
  String get discoverOnYourShelf => 'On your shelf';

  @override
  String get discoverQueued => 'Queued';

  @override
  String discoverDownloading(Object p0) {
    return 'Downloading · $p0%';
  }

  @override
  String downloadDownloadingBooks(int p0, Object p1) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 books',
      one: '1 book',
    );
    return 'Downloading $_temp0 · $p1%';
  }

  @override
  String downloadDownloadStatus(Object p0) {
    return 'Download status, $p0';
  }

  @override
  String get downloadDownloads => 'Downloads';

  @override
  String get downloadKeepsGoingWhileYouBrowse => 'Keeps going while you browse';

  @override
  String get downloadNoActiveDownloads => 'No active downloads.';

  @override
  String downloadCanceledDownloadOf(Object p0) {
    return 'Canceled download of $p0';
  }

  @override
  String downloadQueuedAfter(Object p0) {
    return 'Queued after $p0';
  }

  @override
  String get downloadRemoveFromQueue => 'Remove from queue';

  @override
  String get downloadPreparingBook => 'Preparing book…';

  @override
  String get downloadAddedToShelf => 'Added to shelf';

  @override
  String get downloadAlreadyOnShelf => 'Already on shelf';

  @override
  String get downloadFailedConnectionLost => 'Failed, connection lost';

  @override
  String get bookAddedToGutenberg => 'Added to Gutenberg';

  @override
  String get bookSize => 'Size';

  @override
  String get bookEnglish => 'English';

  @override
  String get bookLanguage => 'Language';

  @override
  String get bookSynopsis => 'Synopsis';

  @override
  String get bookNoSynopsisForThisBookYet =>
      'No synopsis for this book yet. Jump straight into chapter 1.';

  @override
  String get bookReadMore => 'Read more';

  @override
  String get bookAbout => 'About';

  @override
  String get bookListedIn => 'Listed in';

  @override
  String get bookAuthor => 'Author';

  @override
  String get bookFileInfo => 'File info';

  @override
  String get bookFormat => 'Format';

  @override
  String get bookCopyright => 'Copyright';

  @override
  String get bookPublicDomainInTheUs => 'Public domain in the US';

  @override
  String get bookCatalogId => 'Catalog ID';

  @override
  String get bookBookDetails => 'Book details';

  @override
  String bookOtherBooksInTheCatalog(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 other books',
      one: '1 other book',
    );
    return '$_temp0 in the catalog';
  }

  @override
  String bookFindMoreBooksBy(Object p0) {
    return 'Find more books by $p0';
  }

  @override
  String get bookDownloadFailedConnectionLost =>
      'Download failed, connection lost.';

  @override
  String get bookReadNow => 'Read now';

  @override
  String bookContinueReading(Object p0) {
    return 'Continue reading · $p0%';
  }

  @override
  String get bookAlreadyOnYourShelfNoNeed =>
      'Already on your shelf. No need to download again';

  @override
  String get bookQueued => 'Queued…';

  @override
  String get bookDownloading => 'Downloading…';

  @override
  String get bookFeelFreeToBrowseILl =>
      'Feel free to browse. I’ll let you know when it’s on your shelf.';

  @override
  String get bookGetBook => 'Get book';

  @override
  String get bookFreeStraightToYourShelf => 'Free, straight to your shelf';

  @override
  String downloadAddedToShelf2(Object p0) {
    return '$p0 added to shelf';
  }

  @override
  String downloadIsAlreadyOnYourShelf(Object p0) {
    return '$p0 is already on your shelf';
  }

  @override
  String downloadCouldnTDownload(Object p0) {
    return 'Couldn’t download $p0';
  }

  @override
  String get downloadTapToStartReading => 'Tap to start reading';

  @override
  String get downloadOpen => 'Open';

  @override
  String get downloadRead => 'Read';

  @override
  String get chatThisBook => 'This book';

  @override
  String get chatThisBook2 => 'this book';

  @override
  String get chatCouldnTOpenHistory => 'Couldn’t open history.';

  @override
  String get chatYourChatsAreSafeTryReloading =>
      'Your chats are safe. Try reloading in a moment.';

  @override
  String get chatReload => 'Reload';

  @override
  String get chatNoChatsYet => 'No chats yet.';

  @override
  String get chatYourChatsWillAppearHereOrganized =>
      'Your chats will appear here, organized into sessions.';

  @override
  String get chatBackToChat => 'Back to chat';

  @override
  String get chatChatHistory => 'Chat history';

  @override
  String get chatNewChat => 'New chat';

  @override
  String chatUpdated(Object p0) {
    return 'Updated $p0';
  }

  @override
  String get chatOpenNow => 'Open now';

  @override
  String get chatArchived => 'Archived';

  @override
  String chatMenuFor(Object p0) {
    return 'Menu for $p0';
  }

  @override
  String get chatReadingPositionMovedToThisQuote =>
      'Reading position moved to this quote.';

  @override
  String get chatReadingPositionHasnTMovedTry =>
      'Reading position hasn’t moved. Try again.';

  @override
  String get chatThisSourceIsNoLongerAvailable =>
      'This source is no longer available. Your reading position is safe.';

  @override
  String get chatAskAboutThisBook => 'Ask about this book…';

  @override
  String get chatStopResponse => 'Stop response';

  @override
  String get chatSendQuestion => 'Send question';

  @override
  String get chatRename => 'Rename';

  @override
  String get chatUnavailableForArchivedChats =>
      'Unavailable for archived chats';

  @override
  String get chatDeleteChat => 'Delete chat';

  @override
  String get chatDeleteThisChat => 'Delete this chat?';

  @override
  String chatWillBePermanentlyDeletedYourBook(Object p0) {
    return '“$p0” will be permanently deleted. Your book, progress, and other chats won’t be affected.';
  }

  @override
  String get chatCouldnTSaveTheTitleTry =>
      'Couldn’t save the title. Try again.';

  @override
  String get chatSave => 'Save';

  @override
  String get chatChatTitle => 'Chat title';

  @override
  String get chatThisFeatureIsStillInDevelopment =>
      'This feature is still in development. AI can get things wrong. Check sources using the citation numbers.';

  @override
  String chatParagraph(Object p0) {
    return 'paragraph $p0';
  }

  @override
  String get chatReadInBook => 'Read in book';

  @override
  String get chatCollapseContext => 'Collapse context';

  @override
  String get chatExpandContext => 'Expand context';

  @override
  String get chatDraftNotes => 'DRAFT NOTES';

  @override
  String chatParagraph2(Object p0, Object p1) {
    return '$p0, paragraph $p1';
  }

  @override
  String get chatJumpToLatest => 'Jump to latest';

  @override
  String get chatBackToReading => 'Back to reading';

  @override
  String get chatArchivedReadOnly => 'Archived · read only';

  @override
  String get chatThisHistoryCanTBeContinued =>
      'This history can’t be continued.';

  @override
  String get chatAskAboutThisBook2 => 'Ask about this book…';

  @override
  String get chatAskAboutThisQuote => 'Ask about this quote…';

  @override
  String get chatContinue => 'Continue';

  @override
  String get chatWhatWouldYouLikeToDiscuss =>
      'What would you like to discuss about the book?';

  @override
  String get chatThisBookIsUnavailable => 'This book is unavailable.';

  @override
  String get chatWhatWouldYouLikeToAsk =>
      'What would you like to ask about this quote?';

  @override
  String get chatWriteYourQuestionBelowTheQuote =>
      'Write your question below. The quote and its translation are included as context.';

  @override
  String chatAskAnythingAboutAnswersIncludeCitations(Object p0) {
    return 'Ask anything about $p0. Answers include citations to the book.';
  }

  @override
  String chat(Object p0, Object p1) {
    return '$p0 · $p1';
  }

  @override
  String get chatTheBookHasChanged => 'The book has changed';

  @override
  String get chatOpenInBook => 'Open in book';

  @override
  String get chatCheckingQuoteLocation => 'Checking quote location…';

  @override
  String get chatCheckTheOriginalTextWithoutChanging =>
      'Check the original text without changing your reading position.';

  @override
  String get chatThisSourceIsNoLongerAvailable2 =>
      'This source is no longer available or the answer hasn’t passed validation. You can still read the old quote.';

  @override
  String get chatHangOnPreparingTheChat => 'Hang on, preparing the chat…';

  @override
  String get chatLookingForSourcesInTheBook =>
      'Looking for sources in the book…';

  @override
  String get chatHangOnThinking => 'Hang on, thinking…';

  @override
  String get chatWriting => 'Writing…';

  @override
  String get chatTakingAWhileStillWorking => 'Taking a while, still working…';

  @override
  String get chatResponseComplete => 'Response complete';

  @override
  String get chatTheResponseWasCutOff => 'The response was cut off.';

  @override
  String get chatStopped => 'Stopped.';

  @override
  String get chatTheChatWasInterrupted => 'The chat was interrupted';

  @override
  String get chatBackToTranslation => 'Back to translation';

  @override
  String get chatBack => 'Back';

  @override
  String get chatNoApiKeyYetAddIt =>
      'No API key yet. Add it in Settings, then send again.';

  @override
  String get chatConnectionLostCheckYourInternetAnd =>
      'Connection lost. Check your internet and try again.';

  @override
  String get chatTheResponseTookTooLongYou =>
      'The response took too long. You can try again.';

  @override
  String get chatTheResponseHasnTPassedValidation =>
      'The response hasn’t passed validation. Try again.';

  @override
  String get chatApiKeyRejectedCheckYourKey =>
      'API key rejected. Check your key in Settings.';

  @override
  String get chatYourOpenrouterCreditHasRunOut =>
      'Your OpenRouter credit has run out. Check your account and try again.';

  @override
  String get chatRateLimitReachedWaitAMoment =>
      'Rate limit reached. Wait a moment and try again.';

  @override
  String get chatTheAiServiceIsHavingTrouble =>
      'The AI service is having trouble. Try again later.';

  @override
  String get chatToday => 'Today';

  @override
  String get chatYesterday => 'Yesterday';

  @override
  String get chatLastDays => 'Last 7 days';

  @override
  String get chatOlder => 'Older';

  @override
  String get chatCheckingTheBook => 'Checking the book…';

  @override
  String chatReading(Object p0) {
    return 'Reading $p0…';
  }

  @override
  String chatChunks(Object p0, Object p1, Object p2) {
    return '$p0 $p1/$p2 chunks';
  }

  @override
  String chatPreparingTheBookChunks(Object p0, Object p1) {
    return 'Preparing the book… $p0/$p1 chunks';
  }

  @override
  String get chatPlanning => 'Planning';

  @override
  String get chatLoadingSavedNotes => 'Loading saved notes';

  @override
  String get chatWritingTheResponse => 'Writing the response';

  @override
  String chatWorking(Object p0, Object p1) {
    return 'Working: $p0$p1';
  }

  @override
  String get chatThisDraftHasnTPassedResponse =>
      'This draft hasn’t passed response validation.';

  @override
  String chatFixingTheResponseFormat(Object p0, Object p1) {
    return 'Fixing the response format… ($p0/$p1)';
  }

  @override
  String get chatInterpretation => 'Interpretation';

  @override
  String get chatOutsideTheBook => 'Outside the book';

  @override
  String chatStepsCompleted(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 steps',
      one: '1 step',
    );
    return '$_temp0 completed';
  }

  @override
  String chatSteps(Object p0) {
    return 'Steps $p0';
  }

  @override
  String chatShowMore(Object p0) {
    return 'show $p0 more';
  }

  @override
  String get chatAnswerNow => 'Answer now';

  @override
  String chatUseTheNotesReceivedSoFar(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 notes',
      one: '1 note',
    );
    return 'Use the $_temp0 received so far without reading the rest of the book.';
  }

  @override
  String peekNextGroup(Object p0) {
    return '$p0 · next group';
  }

  @override
  String peekConnectsToStartOf(Object p0) {
    return 'Connects to · start of $p0';
  }

  @override
  String get peekTranslate => 'Translate';

  @override
  String get peekTryTranslatingAgain => 'Try translating again';

  @override
  String get peekBreakThisDownToo => 'Break this down too';

  @override
  String get peekWhatCameThroughIsStillHere =>
      'What came through is still here, but hasn’t been saved.';

  @override
  String get peekTranslationNeedsAnOpenrouterApiKey =>
      'Translation needs an OpenRouter API key.';

  @override
  String get peekApiKeyRejected => 'API key rejected';

  @override
  String get peekOpenrouterRejectedYourKeyCheckIt =>
      'OpenRouter rejected your key. Check it in Settings.';

  @override
  String get peekOpenrouterCreditRanOut => 'OpenRouter credit ran out';

  @override
  String get peekTopUpAtOpenrouterAiThen =>
      'Top up at openrouter.ai, then try again.';

  @override
  String get peekCouldnTTranslate => 'Couldn’t translate';

  @override
  String get peekTheConnectionIsHavingTroubleYou =>
      'The connection is having trouble. You can still read the original.';

  @override
  String get breakdownCouldnTBringTheQuoteOver =>
      'Couldn’t bring the quote over. Try reopening the book.';

  @override
  String breakdownBreakdownComplete(Object p0) {
    return 'Breakdown complete, $p0';
  }

  @override
  String get breakdownTerms => 'Terms';

  @override
  String get breakdownPractice => 'Practice';

  @override
  String get breakdownBreakdown => 'Breakdown';

  @override
  String get breakdownCutOffHalfway => 'Cut off halfway';

  @override
  String get breakdownBreakingItDown => 'Breaking it down...';

  @override
  String get breakdownHereSTheBreakdown => 'Here’s the breakdown';

  @override
  String breakdownSectionsReceived(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 sections',
      one: '1 section',
    );
    return '$_temp0 received';
  }

  @override
  String get breakdownBreakingItDownHangOn => 'Breaking it down, hang on';

  @override
  String breakdownBreakdown2(Object p0, Object p1) {
    return 'Breakdown, $p0 $p1';
  }

  @override
  String get breakdownComplete => 'complete';

  @override
  String get breakdownCancelBackToTranslation => 'Cancel, back to translation';

  @override
  String get breakdownBackToTranslation => 'Back to translation';

  @override
  String get breakdownYourTranslationIsSavedButBreakdown =>
      'Your translation is saved, but Breakdown needs AI through OpenRouter. Your API key is missing from Settings. Paste it in again.';

  @override
  String get breakdownIdea => '1 idea';

  @override
  String breakdownSections(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 sections',
      one: '1 section',
    );
    return '$_temp0';
  }

  @override
  String get breakdownCouldnTBreakItDown => 'Couldn’t break it down';

  @override
  String get breakdownYouReOffline => 'You’re offline';

  @override
  String get breakdownBreakdownNeedsInternetConnectAndTry =>
      'Breakdown needs internet. Connect and try again. Saved breakdowns are still available.';

  @override
  String get breakdownOpenrouterRejectedYourKeyCheckIt =>
      'OpenRouter rejected your key. Check it in Settings; it may have been cut off when pasted.';

  @override
  String breakdownKeyRejected(Object p0) {
    return '$p0 · key rejected';
  }

  @override
  String get breakdownTopUpAtOpenrouterAiThen =>
      'Top up at openrouter.ai, then come back and try again.';

  @override
  String get breakdownNoCredit => '402 · no credit';

  @override
  String get breakdownTheResponseFormatIsInvalid =>
      'The response format is invalid';

  @override
  String get breakdownTheAiReturnedSomethingLumaCan =>
      'The AI returned something Luma can’t read. Try once more; that usually helps.';

  @override
  String get breakdownInvalidFormat => 'invalid format';

  @override
  String breakdownSection(Object p0) {
    return 'Section $p0';
  }

  @override
  String get breakdownTranslatedText => 'Translated text';

  @override
  String breakdownTranslatedTextSections(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 sections',
      one: '1 section',
    );
    return 'Translated text, $_temp0';
  }

  @override
  String get breakdownCollapseTranslatedText => 'Collapse translated text';

  @override
  String get breakdownTextBeingExplained => 'Text being explained';

  @override
  String breakdownSectionOf(Object p0, Object p1, Object p2) {
    return 'Section $p0 of $p1, $p2';
  }

  @override
  String get breakdownMeaning => 'MEANING';

  @override
  String get breakdownLogic => 'LOGIC';

  @override
  String breakdownSection2(Object p0) {
    return ' · section $p0';
  }

  @override
  String get breakdownConnectsTo => 'CONNECTS TO';

  @override
  String get breakdownPuttingItIntoPractice => 'Putting it into practice';

  @override
  String get breakdownContinuation => 'Continuation';

  @override
  String breakdownContinuationOf(Object p0) {
    return 'Continuation of $p0';
  }

  @override
  String breakdownChapter(Object p0) {
    return 'Chapter $p0';
  }

  @override
  String breakdownConnectsTo2(Object p0, Object p1) {
    return 'Connects to $p0, $p1';
  }

  @override
  String breakdownConnectsToDoubleTapToPreview(Object p0, Object p1) {
    return 'Connects to $p0, $p1. Double-tap to preview.';
  }

  @override
  String get breakdownTheAiIsBusyGiveIt =>
      'The AI is busy. Give it a moment or try again.';

  @override
  String get breakdownTheConnectionDroppedDuringTheBreakdown =>
      'The connection dropped during the breakdown.';

  @override
  String get breakdownTheConnectionDroppedDuringTheBreakdown2 =>
      'The connection dropped during the breakdown. Section 1 is still here.';

  @override
  String breakdownTheConnectionDroppedDuringTheBreakdown3(Object p0) {
    return 'The connection dropped during the breakdown. Sections 1–$p0 are still here.';
  }

  @override
  String get breakdownTryAgainFromTheStart => 'Try again from the start';

  @override
  String breakdownHighlightInTheText(Object p0) {
    return 'Highlight “$p0” in the text';
  }

  @override
  String get breakdownOpenTranslatedText => 'Open translated text';

  @override
  String breakdownJumpToSectionOf(Object p0, Object p1) {
    return 'Jump to section $p0 of $p1';
  }

  @override
  String breakdownJumpTo(Object p0) {
    return 'Jump to $p0';
  }

  @override
  String get bookTitleAuthorUpdated => 'Title & author updated';

  @override
  String get bookCouldnTSave => 'Couldn’t save';

  @override
  String get bookEditTitleAuthor => 'Edit title & author';

  @override
  String get bookCoverPreview => 'Cover preview';

  @override
  String get bookOriginalEpubCover => 'Original EPUB cover';

  @override
  String get bookDefaultCover => 'Default cover';

  @override
  String get bookTitle => 'Title';

  @override
  String get bookAuthorOptional => 'Author (optional)';

  @override
  String get bookAuthorName => 'Author name';

  @override
  String get bookYourOriginalCoverIsSavedYou =>
      'Your original cover is saved. You can switch back anytime.';

  @override
  String get bookThisCoverComesFromTheEpub =>
      'This cover comes from the EPUB, so editing the title won’t change it.';

  @override
  String get bookUseDefaultCover => 'Use default cover';

  @override
  String get bookRestoreOriginals => 'Restore originals';

  @override
  String bookFromEpub(Object p0, Object p1) {
    return 'From EPUB: $p0 · $p1';
  }

  @override
  String get bookshelfAddedToYourShelf => 'Added to your shelf!';

  @override
  String bookshelfChapterAlreadyExists(Object p0) {
    return 'Chapter $p0 already exists';
  }

  @override
  String bookshelfReplacingChapterWillAlsoDeleteIts(Object p0) {
    return 'Replacing chapter $p0 will also delete its saved translations.';
  }

  @override
  String get bookshelfReplace => 'Replace';

  @override
  String bookshelfAddedToShelf(Object p0) {
    return '$p0 added to shelf ✨';
  }

  @override
  String bookshelfChapterAddedTo(Object p0, Object p1) {
    return 'Chapter $p0 added to $p1 ✨';
  }

  @override
  String get bookshelfBookInfo => 'Book info';

  @override
  String get bookshelfRemoveFromShelf => 'Remove from shelf';

  @override
  String bookshelfProgress(Object p0) {
    return 'Progress $p0%';
  }

  @override
  String bookshelfTranslatedParagraphs(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 translated paragraphs',
      one: '1 translated paragraph',
    );
    return '$_temp0';
  }

  @override
  String get bookshelfAnd => ' and ';

  @override
  String bookshelfRemoveFromYourShelf(Object p0) {
    return 'Remove “$p0” from your shelf?';
  }

  @override
  String bookshelfYourOriginalFileStaysSafe(Object p0) {
    return '${p0}Your original file stays safe.';
  }

  @override
  String get bookshelfNeverMind => 'Never mind';

  @override
  String get bookshelfCouldnTDeleteTheBook => 'Couldn’t delete the book';

  @override
  String get bookshelfSortBy => 'Sort by';

  @override
  String get bookshelfCouldnTOpenYourShelf => 'Couldn’t open your shelf';

  @override
  String bookshelfThatSEverythingBooksOnYour(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 books',
      one: '1 book',
    );
    return 'That’s everything. $_temp0 on your shelf.';
  }

  @override
  String get bookshelfAllBooks => 'All books';

  @override
  String bookshelfShelfOrder(Object p0) {
    return 'Shelf order: $p0';
  }

  @override
  String get bookshelfGridView => 'Grid view';

  @override
  String get bookshelfListView => 'List view';

  @override
  String get bookshelfAFamousOpeningLine => 'A FAMOUS OPENING LINE';

  @override
  String bookshelfGet(Object p0) {
    return 'Get $p0';
  }

  @override
  String get bookshelfGet2 => 'Get';

  @override
  String get bookshelfYourShelfIsStill => 'Your shelf is still ';

  @override
  String get bookshelfEmpty => 'empty';

  @override
  String get bookshelfGetTheBookAboveOrFind =>
      'Get the book above or find another. They’re all free.';

  @override
  String get bookshelfFindFreeBooks => 'Find free books';

  @override
  String get bookshelfOrImportEpubMarkdownFromFiles =>
      'or import EPUB / PDF / Markdown from Files';

  @override
  String get bookshelfTapAParagraphWhenYouGet =>
      'Tap a paragraph when you get stuck';

  @override
  String get bookshelfPuzzledByASentenceBreakIt =>
      'Puzzled by a sentence? Break it down';

  @override
  String get bookshelfFromTheTranslationSheetTapBreakdown =>
      'From the translation sheet, tap Breakdown to explore the sentence section by section.';

  @override
  String get bookshelfChatAboutTheBookAnytime => 'Chat about the book anytime';

  @override
  String get bookshelfAskAboutCharactersThePlotOr =>
      'Ask about characters, the plot, or why something happened. Answers cite the book directly.';

  @override
  String bookshelfDownloading(Object p0) {
    return 'Downloading $p0';
  }

  @override
  String bookshelfWhileYouWaitOf(Object p0, Object p1) {
    return 'WHILE YOU WAIT · $p0 OF $p1';
  }

  @override
  String get bookshelfHereSWhatItMeans => 'HERE’S WHAT IT MEANS';

  @override
  String get backupNoBackupsYet => 'No backups yet';

  @override
  String get backupYourDataIsOnlyOnThis =>
      'Your data is only on this phone. Let’s keep it safe.';

  @override
  String get backupItSBeenDaysSinceYour =>
      'It’s been 6 days since your last backup';

  @override
  String get backupYourReinstallIsDueTomorrowBack =>
      'Your reinstall is due tomorrow. Back up your data first.';

  @override
  String backupItSBeenDaysSinceYour2(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 days',
      one: '1 day',
    );
    return 'It’s been $_temp0 since your last backup';
  }

  @override
  String get backupBackUpYourDataBeforeYour =>
      'Back up your data before your next reinstall.';

  @override
  String get backupBackupReminder => 'Backup reminder';

  @override
  String get backupDismissReminder => 'Dismiss reminder';

  @override
  String get shelfYourBookshelf => 'Your bookshelf';

  @override
  String get shelfImportEpub => 'Import EPUB';

  @override
  String get bookReadingPosition => 'Reading position';

  @override
  String get bookLastOpened => 'Last opened';

  @override
  String get bookAdded => 'Added';

  @override
  String get bookParagraphsTranslated2 => 'Paragraphs translated';

  @override
  String get bookFileSize => 'File size';

  @override
  String get bookFileName => 'File name';

  @override
  String get bookAuthorNotFound => 'Author not found';

  @override
  String continueContinueReading(Object p0, Object p1) {
    return 'Continue reading $p0, $p1';
  }

  @override
  String get continueLetSKeepReading => 'Let’s keep reading →';

  @override
  String continueChapterOf(Object p0, Object p1) {
    return 'Chapter $p0 of $p1';
  }

  @override
  String get breakdownPeopleTerms => 'People & terms';

  @override
  String get relativeToday => 'today';

  @override
  String get relativeYesterday => 'yesterday';

  @override
  String relativeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String relativeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }

  @override
  String relativeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '1 month ago',
    );
    return '$_temp0';
  }

  @override
  String relativeYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String get notStarted => 'Not started';

  @override
  String get finishedReading => 'Finished reading';

  @override
  String chapterPosition(int current, int total) {
    return 'Chapter $current of $total';
  }

  @override
  String get sortLastOpened => 'Last opened';

  @override
  String get sortTitle => 'Title (A–Z)';

  @override
  String get sortAdded => 'Recently added';

  @override
  String chapterList(String range) {
    return 'Chapters $range';
  }

  @override
  String chapterListLower(String range) {
    return 'chapters $range';
  }

  @override
  String get noChapters => 'No chapters yet';

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return '$_temp0';
  }

  @override
  String chaptersRead(String range) {
    return '$range read';
  }

  @override
  String chapterReading(int number) {
    return 'reading chapter $number';
  }

  @override
  String get unknownAuthor => 'unknown author';

  @override
  String deletedProgress(String details) {
    return '$details will also be deleted. ';
  }

  @override
  String get bookDeleted => 'This book has been deleted.';

  @override
  String get bookChanged =>
      'Book content changed. Start a new chat to continue.';

  @override
  String get chatHistoryDamaged =>
      'This session’s history is damaged. You can delete this session.';

  @override
  String get chatUnavailable => 'Couldn’t open the chat. Try again.';

  @override
  String get questionInvalid => 'The question is empty or too long.';

  @override
  String get checkpointInvalid =>
      'Exploration progress no longer matches. Send a new question to start again.';

  @override
  String get notificationChannelName => 'Book downloads';

  @override
  String get notificationChannelDescription =>
      'Updates when downloaded books reach your shelf';

  @override
  String sourceParagraph(int number) {
    return 'paragraph $number';
  }

  @override
  String get navShelf => 'Shelf';

  @override
  String get markdownThisFileIsEmpty => 'This file is empty';

  @override
  String get markdownThereSNoReadingText =>
      'There’s no reading text to import. Check the file or choose another chapter file.';

  @override
  String markdownPWords(Object p0) {
    return '$p0 · 0 words';
  }

  @override
  String get markdownCouldnTReadTheChapter =>
      'Couldn’t read the chapter number';

  @override
  String get markdownTheChapterNumberAtThe =>
      'The chapter number at the top of the file isn’t a number. Change it to a number and try again, or choose another file.';

  @override
  String markdownPChapterNumberP(Object p0, Object p1) {
    return '$p0 · chapter number: “$p1”';
  }

  @override
  String get markdownInvalidBookName => 'Invalid book name';

  @override
  String get markdownTheBookNameAtThe =>
      'The book name at the top can only contain lowercase letters, numbers, and hyphens. Try something like ';

  @override
  String markdownPBookNameP(Object p0, Object p1) {
    return '$p0 · book name: “$p1”';
  }

  @override
  String get markdownOrRemoveThatLineAnd =>
      ', or remove that line and let Luma work it out.';

  @override
  String get markdownCouldnTReadThisFile => 'Couldn’t read this file';

  @override
  String get markdownLumaCanTReadThis =>
      'Luma can’t read this file. Choose another file or save it again first.';

  @override
  String get navSettings => 'Settings';

  @override
  String get editTitleEmpty => 'Title can’t be empty';

  @override
  String get backToConversation => 'Back to chat';

  @override
  String readingDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String readingDurationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get chatPartialNote =>
      'There isn’t enough evidence in these sources for part of your question.';

  @override
  String get chatNoEvidenceNote =>
      'There isn’t enough source material to answer that yet. Try selecting a quote or making your question more specific.';

  @override
  String get importUnpackingPdf => 'Unpacking PDF...';

  @override
  String get importPdfPasswordTitle => 'This PDF is password-protected';

  @override
  String get importPdfPasswordBody =>
      'Luma can’t open password-protected PDFs yet. Remove the password in another app, save a copy, then import again.';

  @override
  String get importPdfScanTitle => 'This PDF has almost no text';

  @override
  String get importPdfScanBody =>
      'Most pages have no readable text, so it may be a scan. For scanned PDFs, use the photo route or Docling to convert it to Markdown, then import the .md file.';

  @override
  String get importPdfDamagedTitle => 'Couldn’t open this PDF';

  @override
  String get importPdfDamagedBody =>
      'It may be corrupt or only partly downloaded. Download it again, then import.';

  @override
  String get importPdfEmptyTitle => 'No readable text found';

  @override
  String get importPdfEmptyBody =>
      'The PDF opened, but there’s no text to turn into chapters. If it’s only images, use the photo route or Docling.';

  @override
  String get importPdfIoTitle => 'Couldn’t read this file';

  @override
  String get importPdfIoBody =>
      'Reading or copying the file failed. Check your storage space, then try again.';

  @override
  String importPdfSkippedPages(int p0) {
    String _temp0 = intl.Intl.pluralLogic(
      p0,
      locale: localeName,
      other: '$p0 pages without text skipped',
      one: '1 page without text skipped',
    );
    return '$_temp0';
  }

  @override
  String get authLoginTitle => 'Your shelf,\nwherever you go.';

  @override
  String get authLoginSubtitle => 'One account for all your reading';

  @override
  String get authChapterOne => 'CHAPTER I';

  @override
  String get authChapterTwo => 'CHAPTER II';

  @override
  String get authChapterThree => 'CHAPTER III';

  @override
  String get authBenefitQuota => 'Free AI quota';

  @override
  String get authBenefitQuotaNote => 'Meaning, Breakdown, and Chat';

  @override
  String get authBenefitBackup => 'Cloud backup';

  @override
  String get authBenefitBackupNote => 'Your shelf and notes stay safe';

  @override
  String get authBenefitSync => 'Sync across phones';

  @override
  String get authBenefitSyncNote => 'Pick up on iPhone or Android';

  @override
  String get authSignInGoogle => 'Sign in with Google';

  @override
  String get authConnectingGoogle => 'Connecting to Google…';

  @override
  String get authGoogleWillAsk => 'Next, Google will ask which account to use.';

  @override
  String authPrivacyNote(String policy) {
    return 'By signing in, you agree to Luma\'s $policy.';
  }

  @override
  String get authPrivacyPolicy => 'Privacy policy';

  @override
  String get authNetworkTitle => 'Can\'t connect';

  @override
  String get authNetworkBody => 'Check your internet, then try again.';

  @override
  String get authTryAgain => 'Try again';

  @override
  String get authRejectedTitle => 'Sign-in was rejected';

  @override
  String get authRejectedBody =>
      'This Google account can\'t be used to sign in. Try another account.';

  @override
  String get authUseAnotherAccount => 'Use another account';

  @override
  String get authDevBadge => 'Developer build';

  @override
  String get authDevLabel => 'Dev build';

  @override
  String get authDevTitle => 'Fill in the blanks.';

  @override
  String get authDevEmailLead => 'My email is';

  @override
  String get authDevPasswordLead => 'and my password is';

  @override
  String get authDevNote =>
      'Developer builds only. Release builds use Google only.';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authInvalidCredentialsTitle => 'Wrong email or password';

  @override
  String get authInvalidCredentialsBody => 'Check them, then sign in again.';

  @override
  String get authUserExistsTitle => 'This email is already registered';

  @override
  String get authUserExistsBody => 'Use Sign in instead of Sign up.';

  @override
  String get authPasswordShortTitle => 'Password is too short';

  @override
  String get authPasswordShortBody => 'Use at least 8 characters.';

  @override
  String get authSignedInAs => 'Signing in as';

  @override
  String get authChange => 'Change';

  @override
  String get authInviteIntro =>
      'Luma is in beta, so new accounts need an invite.';

  @override
  String get authInviteLead => 'My invite code:';

  @override
  String get authInviteHint => 'Case doesn\'t matter. The dash is optional.';

  @override
  String get authContinue => 'Continue';

  @override
  String get authNoteLabel => 'NOTE';

  @override
  String get authInviteUsedTitle => 'This code has been used';

  @override
  String get authInviteUsedBody =>
      'One code per account. Ask whoever invited you for a new one.';

  @override
  String get authInviteInvalidTitle => 'That code is wrong';

  @override
  String get authInviteInvalidBody =>
      'Check the letters again, or ask whoever invited you for a new code.';

  @override
  String get settingsAccount => 'Account';

  @override
  String get authExLibris => 'EX LIBRIS';

  @override
  String get authViaGoogle => 'Signed in with Google';

  @override
  String get authViaEmail => 'Signed in with email';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authDeleteAccount => 'Delete account';

  @override
  String get authSignOutTitle => 'Sign out?';

  @override
  String get authSignOutBody =>
      'Books, progress, and notes on this phone stay. You\'ll go back to sign-in; backup and sync pause.';

  @override
  String get authSwitchTitle => 'Switch to another account?';

  @override
  String get authSwitchOwner => 'This phone\'s data belongs to';

  @override
  String get authSwitchNew => 'Signing in with';

  @override
  String get authSwitchBodyLead => 'To keep things separate,';

  @override
  String get authSwitchBodyBold => 'this phone is cleared first';

  @override
  String get authSwitchBodyTail =>
      ': books, progress, notes. The old account\'s data stays safe in the cloud.';

  @override
  String get authSwitchConfirm => 'Clear phone & continue';

  @override
  String get authSwitchKeep => 'Keep the old account';

  @override
  String get authDeleteTitle => 'Delete account forever?';

  @override
  String get authDeleteBody =>
      'Tick everything so you know what\'s lost. This can\'t be undone.';

  @override
  String authDeleteCheckAccount(String email) {
    return 'Account $email is deleted';
  }

  @override
  String get authDeleteCheckBackup => 'All cloud backups are gone';

  @override
  String get authDeleteCheckSync => 'Sync data on all your phones is gone';

  @override
  String get authDeleteNote =>
      'Books on this phone stay, but won\'t be backed up anymore.';

  @override
  String get authDeleteConfirm => 'Delete account forever';

  @override
  String get authSessionExpiredTitle => 'Your session expired';

  @override
  String get authSessionExpiredBody =>
      'Reading still works; backup & sync wait.';

  @override
  String get authSignInAgain => 'Sign in again';

  @override
  String get authCloseBanner => 'Close';

  @override
  String authToastSignedIn(String name) {
    return 'Signed in. Hi, $name!';
  }

  @override
  String get authToastSignedOut => 'Signed out. Books on this phone stay.';

  @override
  String get authToastDeleted => 'Your account is deleted.';

  @override
  String get authToastDeleteFailed =>
      'Couldn\'t delete the account. No internet.';

  @override
  String get quotaToday => 'AI quota today';

  @override
  String quotaResetAt(String time) {
    return 'Resets $time';
  }

  @override
  String quotaResetAtIn(String time, String countdown) {
    return 'Resets $time · $countdown';
  }

  @override
  String quotaCountdown(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String quotaTapsLeft(int count) {
    return '≈ $count taps left';
  }

  @override
  String get quotaLow => 'Almost out';

  @override
  String get quotaUsedUp => 'Today\'s free quota is used up.';

  @override
  String get quotaLoading => 'Loading…';

  @override
  String get quotaLoadFailed => 'Couldn\'t check the remaining quota.';

  @override
  String get quotaSource => 'AI source';

  @override
  String get quotaOwnKey => 'Own key';

  @override
  String get quotaOwnKeyNote =>
      'Charged to your OpenRouter balance. Free quota isn\'t used.';

  @override
  String get quotaFree => 'Free AI quota';

  @override
  String get quotaRevoked => 'Revoked';

  @override
  String get quotaBlocked => 'Blocked';

  @override
  String get quotaRevokedNote => 'AI still works with your own key.';

  @override
  String get quotaExhaustedTitle => 'Today\'s free quota is used up';

  @override
  String quotaExhaustedBody(String time, int hours, int minutes) {
    return 'Resets at $time (in ${hours}h ${minutes}m). To keep going now, use your own OpenRouter key.';
  }

  @override
  String get quotaResetIn => 'Resets in';

  @override
  String get quotaHoursUnit => 'h';

  @override
  String get quotaMinutesUnit => 'm';

  @override
  String quotaTapsOf(int count) {
    return '0 of ≈ $count taps left';
  }

  @override
  String quotaTapsOfShort(int count) {
    return '0 of ≈ $count taps';
  }

  @override
  String quotaPeekBody(String time) {
    return 'The original text is still readable. Translate again after the $time reset, or use your own key.';
  }

  @override
  String get quotaUseOwnKey => 'Use my own key';

  @override
  String get quotaOk => 'OK';

  @override
  String quotaChatClosed(String time) {
    return 'Out of quota, back at $time';
  }

  @override
  String get quotaBannedPill => 'Free quota blocked';

  @override
  String get quotaBannedTitle => 'Your free AI access was revoked';

  @override
  String get quotaBannedBody =>
      'This account can\'t use Luma\'s free quota anymore. Meaning, Breakdown, and Chat still work with your own OpenRouter key.';

  @override
  String get aiSection => 'AI';

  @override
  String get aiSourceFree => 'Free quota';

  @override
  String get aiSourceOwn => 'Own key';

  @override
  String get aiOwnKeyCost =>
      'Charged to your OpenRouter balance. Luma\'s free quota isn\'t used while this key is active.';

  @override
  String get aiKeyRejected401 => 'Key rejected (401)';

  @override
  String get aiKeyRejectedBox =>
      'OpenRouter rejected this key. Check it at openrouter.ai/keys and paste it again. AI stops until the key works, or switch back to the free quota.';

  @override
  String get aiCheckedJustNow => 'Checked just now';

  @override
  String get aiDefaultTag => 'default';

  @override
  String get aiBackToFree => 'Back to free quota';

  @override
  String get aiBackToFreeTitle => 'Back to the free quota?';

  @override
  String aiBackToFreeBody(String model) {
    return 'Your OpenRouter key is removed from this phone. The model goes back to $model, one of the 3 free models.';
  }

  @override
  String get aiBackToFreeConfirm => 'Back to free';

  @override
  String get aiPickModel => 'Choose a model';

  @override
  String get aiFreeModelsNote =>
      'The free quota only works with these 3 models.';

  @override
  String get aiDefaultCheapest => 'Default · cheapest';

  @override
  String get aiMoreModelsTitle => 'Want another model?';

  @override
  String get aiMoreModelsBody =>
      'Use your own OpenRouter key to unlock hundreds of models. Charged to your balance.';

  @override
  String aiSearchModels(int count) {
    return 'Search $count models';
  }

  @override
  String get aiFilterAll => 'All';

  @override
  String get aiFilterCheap => 'Budget';

  @override
  String get aiFilterLong => 'Long context';

  @override
  String get aiModelsLoadFailed =>
      'Couldn\'t load the model list. Check your internet, then try again.';

  @override
  String get aiNoModelMatch => 'No matching models.';
}
