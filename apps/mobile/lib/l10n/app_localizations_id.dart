// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get interfaceLanguage => 'Bahasa antarmuka';

  @override
  String get interfaceLanguageNote =>
      'Bahasa ini cuma buat tampilan. Terjemahan dan jawaban AI tetap Bahasa Indonesia.';

  @override
  String get languageSaveFailed => 'Bahasanya gagal disimpen. Coba lagi, ya.';

  @override
  String bookImporting(Object p0) {
    return 'Lagi diimport $p0';
  }

  @override
  String get bookProcessing => 'Lagi diproses';

  @override
  String get bookNew => 'Baru';

  @override
  String get bookFinished => 'Kelar!';

  @override
  String bookChapters(int p0) {
    return '$p0 bab';
  }

  @override
  String get aiCopy => 'Salin';

  @override
  String aiUnavailable(Object p0, Object p1) {
    return '$p0, belum bisa: $p1';
  }

  @override
  String get bookCloseMenu => 'Tutup menu';

  @override
  String get searchSearchResults => 'Hasil cari';

  @override
  String get searchPreviousResult => 'Hasil sebelumnya';

  @override
  String get searchBackToResults => 'Balik ke daftar hasil';

  @override
  String searchOf(Object p0, Object p1) {
    return '$p0 dari $p1';
  }

  @override
  String searchOf2(Object p0, Object p1, Object p2) {
    return '$p0 dari $p1 · $p2';
  }

  @override
  String get searchNextResult => 'Hasil berikutnya';

  @override
  String get searchExitSearch => 'Keluar dari cari';

  @override
  String get searchClearField => 'Hapus isian';

  @override
  String get dialogCancel => 'Batal';

  @override
  String get sheetClose => 'Tutup';

  @override
  String get searchCurrentlyReading => 'Lagi dibaca';

  @override
  String searchResults(int p0) {
    return '$p0 hasil';
  }

  @override
  String fieldClear(Object p0) {
    return 'Hapus $p0';
  }

  @override
  String get fieldShowKey => 'Liat key';

  @override
  String get fieldHideKey => 'Sembunyiin key';

  @override
  String get navMainNavigation => 'Navigasi utama';

  @override
  String navActiveDownloads(Object p0, Object p1) {
    return '$p0, $p1 unduhan jalan';
  }

  @override
  String get bookSearchThisBook => 'Cari kata di buku ini';

  @override
  String bookNoMatchesForInThisBook(Object p0) {
    return 'Gak ketemu “$p0” di buku ini';
  }

  @override
  String get bookCheckTheSpellingOrTryAnother =>
      'Cek ejaannya, atau coba kata lain.';

  @override
  String get bookSearchIsStuck => 'Pencariannya lagi macet';

  @override
  String get bookCloseItAndTryAgain => 'Tutup terus buka lagi ya.';

  @override
  String get bookRecentSearches => 'Terakhir dicari';

  @override
  String get bookClear => 'Hapus';

  @override
  String get bookTooManyResultsTryAMore =>
      'Kebanyakan, coba kata yang lebih spesifik';

  @override
  String get bookPreparingSearch => 'Nyiapin pencarian…';

  @override
  String get bookJustOnceForThisBookSearches =>
      'Cuma sekali buat buku ini. Abis ini nyarinya langsung kilat.';

  @override
  String get readerCouldnTOpenTheChatTry =>
      'Obrolan belum bisa dibuka. Coba buka ulang bukunya.';

  @override
  String get readerBackToYourPreviousPosition => 'Balik ke posisi tadi?';

  @override
  String get readerGoBack => 'Balik';

  @override
  String get readerThisSourceIsNoLongerAvailable =>
      'Sumber ini udah gak tersedia.';

  @override
  String get readerPreviewingNoReadingProgressYet =>
      'Lagi ngintip · belum ada progres baca';

  @override
  String readerPreviewingSavedPositionParagraph(Object p0, Object p1) {
    return 'Lagi ngintip · progres masih $p0 · Paragraf $p1';
  }

  @override
  String get readerCouldnTOpenTheBook => 'Yah, bukunya gagal kebuka';

  @override
  String get meaningCopiedReadyToPaste => 'Udah disalin, tinggal paste';

  @override
  String get meaningTimeoutSeconds => 'timeout · 30 detik';

  @override
  String get meaningOfflineDisconnected => 'offline / gak nyambung';

  @override
  String meaningHttpKeyRejected(Object p0) {
    return 'HTTP $p0 · key ditolak';
  }

  @override
  String get meaningHttpNoCredit => 'HTTP 402 · saldo abis';

  @override
  String get meaningInvalidAiResponse => 'jawaban AI gak valid';

  @override
  String get meaningTranslationAndMeaningComplete => 'Artinya udah lengkap';

  @override
  String get meaningWritingTranslationAndMeaning => 'Artinya, lagi ditulis';

  @override
  String get meaningHangOnThinking => 'Bentar, lagi mikir...';

  @override
  String get meaningHereSWhatItMeans => 'Artinya gini nih';

  @override
  String get meaningCancel => 'Batalin';

  @override
  String get meaningTranslation => 'Terjemahan';

  @override
  String get meaningWhatTheAuthorMeans => 'Maksud penulisnya tuh...';

  @override
  String get meaningCopied => 'Disalin';

  @override
  String get meaningAskAboutThis => 'Tanyain ini';

  @override
  String get meaningThinking => 'Lagi mikir';

  @override
  String get meaningWriting => 'Lagi nulis';

  @override
  String get meaningNext => 'Lanjut';

  @override
  String get meaningTakingALittleLonger => 'Agak lama nih...';

  @override
  String get meaningTheAiIsStillThinkingGive =>
      'AI-nya masih mikir. Tungguin bentar lagi, atau coba ulang.';

  @override
  String get meaningTryAgain => 'Coba lagi';

  @override
  String get meaningCutOffHalfway => 'Yah, kepotong di tengah';

  @override
  String get meaningTheConnectionDroppedWhileWritingWhat =>
      'Koneksinya putus pas lagi nulis. Yang udah masuk tetep di sini.';

  @override
  String get meaningCouldnTGetTheMeaning => 'Gagal ngambil artinya';

  @override
  String get meaningSomethingWentWrong => 'Yah, gagal nih';

  @override
  String get meaningTheConnectionMightBeDownOr =>
      'Kayaknya koneksi lagi ngadat, atau AI-nya lagi sibuk. Tinggal coba lagi aja.';

  @override
  String get meaningMaybeLater => 'Nanti aja';

  @override
  String get meaningAddYourApiKeyFirst => 'Isi API key dulu yuk';

  @override
  String get meaningTranslationsAndMeaningsUseAiThrough =>
      'Artinya dibikin AI lewat OpenRouter. Tempel API key lo sekali aja di Pengaturan, abis itu tinggal tap-tap paragraf.';

  @override
  String get meaningDonTHaveOneCreateIt => 'Belum punya? Bikin dulu di ';

  @override
  String get meaningOpenSettings => 'Buka Pengaturan';

  @override
  String get meaningOpenBreakdown => 'Buka bedahan';

  @override
  String get meaningStillPuzzledBreakItDown => 'Masih bingung? Bedahin';

  @override
  String meaningPreviouslyBrokenDown(Object p0) {
    return 'Udah pernah dibedah · $p0';
  }

  @override
  String get meaningSectionBySectionPlusPeopleTerms =>
      'Per bagian, plus tokoh & istilah';

  @override
  String get chapterSourceMissing => 'Sumber hilang';

  @override
  String get chapterCurrentlyOpenParagraphGroup =>
      'Grup paragraf yang lagi dibuka';

  @override
  String get chapterSceneBreak => 'Pemisah adegan';

  @override
  String get readerReadingMenu => 'Menu baca';

  @override
  String get readerBackToShelf => 'Balik ke rak';

  @override
  String get readerContents => 'Daftar isi';

  @override
  String get readerMoreActions => 'Aksi lain';

  @override
  String get readerBookChat => 'Ngobrolin buku';

  @override
  String get readerBookProgress => 'Progres buku';

  @override
  String get bookBook => 'Bukunya ';

  @override
  String get bookFinished2 => 'kelar!';

  @override
  String bookYouReadRightToTheLast(Object p0) {
    return '$p0 udah lo libas sampe kalimat terakhir. Keren sih.';
  }

  @override
  String get bookReadingTime => 'waktu baca';

  @override
  String get bookParagraphsTranslated => 'paragraf diartiin';

  @override
  String get bookBackToShelfFindAnotherBook => 'Balik ke rak, cari buku lain';

  @override
  String get bookReadAgainFromTheStart => 'Baca ulang dari awal';

  @override
  String chapterChapterOfMin(Object p0, Object p1, Object p2) {
    return 'Bab $p0 dari $p1 · ±$p2 mnt';
  }

  @override
  String tocChaptersRead(Object p0, int p1, Object p2) {
    return '$p0 · $p1 bab · $p2% kebaca';
  }

  @override
  String tocCurrentlyReadingMin(Object p0) {
    return 'Lagi dibaca · ±$p0 mnt';
  }

  @override
  String tocMin(Object p0) {
    return '±$p0 mnt';
  }

  @override
  String readerFinished(Object p0) {
    return '$p0 kelar';
  }

  @override
  String readerMinLeft(Object p0) {
    return '±$p0 mnt lagi';
  }

  @override
  String get readerChatAboutTheBook => 'Ngobrol soal bukunya';

  @override
  String get readerBackToChat => 'Balik ke ngobrol';

  @override
  String get readerKeepReading => 'Lanjut baca';

  @override
  String get readYouLastReadHere => 'Terakhir lo baca di sini';

  @override
  String get chapterChapterFinished => 'Bab selesai';

  @override
  String chapterParagraphsTranslated(int p0) {
    return '$p0 paragraf diterjemahin';
  }

  @override
  String get chapterThatWasTheLastChapter => 'Itu tadi bab terakhir!';

  @override
  String chapterContinueTo(Object p0) {
    return 'Lanjut ke $p0?';
  }

  @override
  String get chapterOneMoreTapToFinishThe =>
      'Bukunya kelar, tinggal satu tap lagi';

  @override
  String get chapterLetSKeepGoing => 'Lanjut, gas';

  @override
  String get chapterStopHereBackToShelf => 'Udahan dulu, balik ke rak';

  @override
  String get readerSearchWords => 'Cari kata';

  @override
  String readerViewResultsFor(Object p0) {
    return 'Lihat hasil “$p0”';
  }

  @override
  String get readerReadingAppearance => 'Atur tampilan';

  @override
  String get readerSizeFontTheme => 'Ukuran, font, tema';

  @override
  String get aaMakeItYours => 'Atur bacaan lo';

  @override
  String get aaTextSize => 'Ukuran huruf';

  @override
  String get aaFont => 'Font';

  @override
  String get aaClear => 'Jelas';

  @override
  String get aaBookLike => 'Kayak buku';

  @override
  String get aaSystemDefault => 'Bawaan sistem';

  @override
  String get aaLineSpacing => 'Jarak baris';

  @override
  String get aaTight => 'Rapat';

  @override
  String get aaBalanced => 'Pas';

  @override
  String get aaRoomy => 'Lega';

  @override
  String get aaMargins => 'Margin';

  @override
  String get aaNarrow => 'Sempit';

  @override
  String get aaTheme => 'Tema';

  @override
  String get aaLight => 'Terang';

  @override
  String get aaDark => 'Gelap';

  @override
  String get aaSystem => 'Ikut sistem';

  @override
  String get aaScreenDisplay => 'Tampilan layar';

  @override
  String get aaHideClockBattery => 'Sembunyiin jam & baterai';

  @override
  String get aaHideTheStatusBarWithThe =>
      'Status bar ngumpet bareng menu pas lagi baca';

  @override
  String get aaShowProgressLine => 'Tampilin garis progres';

  @override
  String get aaAThinLineAtTheBottom =>
      'Garis tipis di bawah layar pas menu ngumpet';

  @override
  String get aaSmallerText => 'Kecilin huruf';

  @override
  String get aaLargerText => 'Gedein huruf';

  @override
  String aaFont2(Object p0) {
    return 'Font $p0';
  }

  @override
  String aaTheme2(Object p0) {
    return 'Tema $p0';
  }

  @override
  String get backupBackupCompleteAllSafe => 'Backup kelar, aman!';

  @override
  String get backupBackupFailed => 'Yah, backup gagal';

  @override
  String get backupTryAgainInAMoment => 'Coba lagi bentar ya';

  @override
  String get settingsYourDataIsBack => 'Sip, data lo udah balik!';

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

    return '$p0String buku · $p1String terjemahan';
  }

  @override
  String get settingsApiKeysArenTIncludedIn =>
      'API key gak ikut backup, isi ulang dulu biar bisa nerjemahin.';

  @override
  String get settingsAddKey => 'Isi key';

  @override
  String get settingsDeleteTranslationCache => 'Hapus cache terjemahan?';

  @override
  String get settingsAllSavedTranslationsWillBeDeleted =>
      'Semua terjemahan yang udah kesimpen bakal ilang. Paragraf yang dibuka lagi manggil AI ulang dan motong saldo lagi. Obrolan buku lo tetap kesimpen.';

  @override
  String get settingsYourCatalogIsAlreadyUpTo => 'Katalognya udah yang terbaru';

  @override
  String get settingsBack => 'Balik';

  @override
  String get settingsSettings => 'Pengaturan';

  @override
  String get settingsOpenrouterApiKey => 'API key OpenRouter';

  @override
  String get settingsAiModel => 'Model AI';

  @override
  String get settingsChargesComeFromYourOpenrouterAccount =>
      'Biayanya kepotong dari saldo akun OpenRouter lo.';

  @override
  String get settingsBackupRestore => 'Backup & pulihin';

  @override
  String get settingsBookCatalog => 'Katalog buku';

  @override
  String get settingsAroundProjectGutenbergBooksToSearch =>
      'Daftar ±62.000 buku Project Gutenberg buat nyari judul tanpa internet. Diperbarui mingguan.';

  @override
  String get settingsStorage => 'Penyimpanan';

  @override
  String get settingsStoredSecurelyOnYourDeviceKeychain =>
      'Disimpen aman di perangkat (Keychain / Keystore), gak dikirim ke mana-mana selain OpenRouter.';

  @override
  String get settingsThatSNotAnOpenrouterApi =>
      'Itu bukan API key OpenRouter. Key-nya mulai dari sk-or-... dan gak disimpen.';

  @override
  String get settingsOpenrouterRejectedTheKeySoIt =>
      'Key-nya ditolak OpenRouter, jadi gak disimpen. Cek lagi ya.';

  @override
  String get settingsHangOnChecking => 'Bentar, lagi ngecek...';

  @override
  String get settingsYourKeyWorks => 'Key-nya jalan';

  @override
  String get settingsOpenrouterRejectedYourKey => 'Key-nya ditolak OpenRouter';

  @override
  String get settingsStoredSecurelyOnYourDevice => 'Disimpen aman di perangkat';

  @override
  String get settingsIncludesBooksReadingProgressTranslationsAnd =>
      'Isinya buku, progres baca, terjemahan, sama pengaturan. ';

  @override
  String get settingsApiKeysArenTIncluded => 'API key gak ikut';

  @override
  String get settingsSoAddYoursAgainAfterRestoring =>
      ', jadi abis pulihin isi ulang ya. Simpen file-nya di iCloud Drive biar gak ikut kehapus pas install ulang.';

  @override
  String get settingsJustNow => 'Barusan';

  @override
  String get settingsBackupStatus => 'Status backup';

  @override
  String get settingsLastBackup => 'Backup terakhir';

  @override
  String get settingsNoBackupsYet => 'Belum pernah backup';

  @override
  String get settingsYourDataIsOnlyOnThis => 'Data lo cuma ada di HP ini doang';

  @override
  String get settingsBackUpNow => 'Backup sekarang';

  @override
  String get settingsRestoreFromBackup => 'Pulihin dari backup';

  @override
  String get settingsDefaultMostAccurate => 'Default · paling akurat';

  @override
  String get settingsTranslationCache => 'Cache terjemahan';

  @override
  String settingsParagraphs(int p0, Object p1) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    return '$p0String paragraf · $p1';
  }

  @override
  String get settingsClearCache => 'Hapus cache';

  @override
  String get settingsNotDownloadedMb => 'Belum diunduh · 5,6 MB';

  @override
  String settingsUpdated(Object p0) {
    return 'Diperbarui $p0 · ';
  }

  @override
  String settingsBooks(Object p0, int p1) {
    final intl.NumberFormat p1NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p1String = p1NumberFormat.format(p1);

    return '$p0$p1String buku';
  }

  @override
  String get settingsCheckingForUpdates => 'Ngecek versi terbaru…';

  @override
  String get settingsDownloading => 'Ngunduh…';

  @override
  String settingsDownloading2(Object p0) {
    return 'Ngunduh $p0%';
  }

  @override
  String get settingsPreparingCatalog => 'Nyusun katalog…';

  @override
  String get settingsFailedKeepingThePreviousCatalog =>
      'Gagal, katalog lama tetep dipakai';

  @override
  String get settingsDownload => 'Unduh';

  @override
  String get settingsUpdate => 'Perbarui';

  @override
  String get settingsGutenbergCatalog => 'Katalog Gutenberg';

  @override
  String backupBooksReadingProgress(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    return '$p0String buku + progres bacanya';
  }

  @override
  String backupTranslations(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    return '$p0String terjemahan';
  }

  @override
  String get backupReadingSettingsAiModel => 'Pengaturan baca & model AI';

  @override
  String get backupBackingUp => 'Lagi backup';

  @override
  String get backupPackingYourBackup => 'Lagi ngebungkus backup...';

  @override
  String get backupTheShareMenuOpensNextSave =>
      'Abis ini muncul menu share. Simpen ke Files / Drive terus taruh di tempat aman biar gak ilang.';

  @override
  String get restoreRestoreThisBackup => 'Pulihin dari backup ini?';

  @override
  String get restoreReplaceRestore => 'Ganti & pulihin';

  @override
  String get restoreYourApiKeyWonTBe => 'API key lo gak kesentuh.';

  @override
  String restoreCreatedLuma(Object p0, Object p1) {
    return 'Dibikin $p0 · Luma $p1';
  }

  @override
  String get restoreBooksOnShelf => 'buku di rak';

  @override
  String get restoreTranslations => 'terjemahan';

  @override
  String get restoreAllDataOnThisPhoneWill =>
      'Semua data di HP ini bakal diganti';

  @override
  String restoreYourCurrentBooksProgressAndTranslations(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    return 'Buku, progres, sama terjemahan yang ada sekarang ($p0String buku) diganti total sama isi backup. Yang sekarang gak bisa dibalikin.';
  }

  @override
  String get restoreYesIUnderstandReplaceEverything =>
      'Iya, gua ngerti. Ganti aja semuanya.';

  @override
  String get restoreRestoring => 'Lagi mulihin';

  @override
  String get restoreRestoringYourData => 'Lagi mulihin data lo...';

  @override
  String get restoreCheckBackupFile => 'Cek file backup';

  @override
  String restoreRestoreBooks(int p0) {
    final intl.NumberFormat p0NumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String p0String = p0NumberFormat.format(p0);

    return 'Balikin $p0String buku';
  }

  @override
  String get restoreRestoreProgressTranslations =>
      'Balikin progres & terjemahan';

  @override
  String get restoreKeepLumaOpenThisWonT =>
      'Jangan tutup Luma dulu ya, bentar doang kok.';

  @override
  String get restoreThisIsnTALumaBackup => 'Ini bukan backup Luma';

  @override
  String get restoreLumaBackupFilesAreNamedLuma =>
      'File backup Luma itu yang namanya luma-backup-…zip, hasil dari tombol \"Backup sekarang\". Coba cari lagi di file manager ya.';

  @override
  String get restoreThisBackupIsFromANewer =>
      'Backup-nya dari Luma yang lebih baru';

  @override
  String restoreThisFileWasCreatedWithLuma(Object p0, Object p1) {
    return 'File ini dibikin pake Luma $p0, sedangkan yang keinstall masih $p1. Install Luma versi terbaru dulu, baru pulihin.';
  }

  @override
  String get restoreTheBackupFileIsDamaged => 'File backup-nya rusak';

  @override
  String get restoreCouldnTReadTheFileIt =>
      'Isinya gak kebaca, mungkin kepotong pas disimpen. Coba file backup yang lain.';

  @override
  String get restoreCouldnTRestore => 'Yah, gagal mulihin';

  @override
  String get restoreSomethingWentWrongWhileReplacingData =>
      'Ada yang error pas ganti data, semuanya udah dibalikin kayak semula.';

  @override
  String get restoreRestoreFailed => 'Gagal mulihin';

  @override
  String get restoreChooseAnotherFile => 'Pilih file lain';

  @override
  String get restoreYourCurrentDataHasnTBeen =>
      'Tenang, data yang sekarang gak diapa-apain.';

  @override
  String get importImporting => 'Lagi import';

  @override
  String get importUnpackingEpub => 'Lagi ngebongkar EPUB...';

  @override
  String get importReadTitleAuthor => 'Baca judul & penulis';

  @override
  String get importGetCover => 'Ambil cover';

  @override
  String get importSplitIntoChaptersParagraphs => 'Mecah per bab & paragraf';

  @override
  String importAdded(Object p0) {
    return 'ditambah $p0';
  }

  @override
  String get importThisBookIsAlreadyOnYour => 'Eh, buku ini udah ada di rak';

  @override
  String get importYouVeImportedTheSameBook =>
      'Lo pernah import buku yang sama. Mau lanjutin yang lama aja?';

  @override
  String get importOpenExistingBook => 'Buka yang udah ada';

  @override
  String get importReplaceFile => 'Ganti file-nya';

  @override
  String get importReplacingTheFileKeepsYourProgress =>
      'Ganti file = progres & terjemahan lama tetep aman.';

  @override
  String get importThisFileIsDamaged => 'File-nya rusak nih';

  @override
  String get importCouldnTOpenThisEpubIt =>
      'EPUB-nya gak bisa dibuka, kayaknya korup atau kedownload setengah. Coba download ulang, terus import lagi.';

  @override
  String importDamagedFile(Object p0) {
    return '$p0 · file rusak';
  }

  @override
  String get importThisIsnTAnEpub => 'Ini bukan EPUB';

  @override
  String get importThisImporterReadsEpubFilesConvert =>
      'App ini cuma bisa baca .epub. Kalau bukunya MOBI, convert dulu ke EPUB (misal pake Calibre), baru import lagi.';

  @override
  String get importThisBookIsDrmLocked => 'Bukunya dikunci DRM';

  @override
  String get importThisEpubIsLockedToIts =>
      'EPUB ini dikunci sama tokonya, jadi cuma bisa dibaca di app toko itu. Pake file EPUB yang bebas DRM ya.';

  @override
  String get importBookTitleCanTBeEmpty => 'Judul buku gak boleh kosong';

  @override
  String get importMustBeANumber => 'Harus angka';

  @override
  String get importImport => 'Masukin';

  @override
  String get importWhichBookIsThisFor => 'Masuk ke buku mana?';

  @override
  String get importBookTitle => 'Judul buku';

  @override
  String get importChapterTitle => 'Judul bab';

  @override
  String get importChapterTitleOptional => 'Judul bab (opsional)';

  @override
  String get importChapterNumber => 'Nomor bab';

  @override
  String importLastChapterInThisBook(Object p0) {
    return 'Bab terakhir di buku ini: $p0';
  }

  @override
  String get importGuessedFromTheFileTitleYou =>
      'Ditebak dari judul di file. Boleh diubah.';

  @override
  String get importNewBook => 'Buku baru';

  @override
  String get importCreateABookFromThisFile => 'Bikin buku dari file ini';

  @override
  String get discoverDiscover => 'Cari buku';

  @override
  String get discoverTitleOrAuthorName => 'Judul atau nama penulis';

  @override
  String get discoverClearSearch => 'Hapus kata cari';

  @override
  String discoverPreparingBookCatalog(Object p0) {
    return 'Nyiapin katalog buku… $p0%';
  }

  @override
  String get discoverPreparingBookCatalog2 => 'Nyiapin katalog buku…';

  @override
  String get discoverCanTReachTheCatalog => 'Katalog lagi gak bisa dihubungin';

  @override
  String get discoverItSNotYourFaultGive =>
      'Bukan salah lo kok. Coba lagi bentar lagi ya.';

  @override
  String get discoverJustOnceThenSearchWorksOffline =>
      'Sekali aja, abis itu nyari jalan tanpa internet.';

  @override
  String get discoverYouReOffline => 'Lo lagi offline';

  @override
  String get discoverSearchStillWorksPopularBooksDetails =>
      'Nyari tetep jalan. Tapi daftar rame, detail buku, sama unduhan butuh internet. Buku di rak tetap bisa lo baca kok.';

  @override
  String get discoverOpenShelf => 'Buka rak';

  @override
  String get discoverPopularNow => 'LAGI RAME';

  @override
  String get discoverTheCatalogIsTakingAWhile => 'Katalognya lagi lemot nih';

  @override
  String get discoverItSBeenOverSecondsGive =>
      'Udah 5 detik lebih. Tungguin bentar, atau coba lagi.';

  @override
  String get discoverTrySearching => 'COBA CARI';

  @override
  String discoverPopular(Object p0) {
    return '#1 lagi rame, $p0';
  }

  @override
  String get discoverPopular2 => '#1 lagi rame';

  @override
  String discoverNoMatchesFor(Object p0) {
    return 'Gak nemu “$p0”';
  }

  @override
  String get discoverSearchMatchesTitlesAndAuthorNames =>
      'Pencarian cuma nyocokin judul sama nama penulis. Cek ejaannya, atau coba kata yang lebih pendek.';

  @override
  String discoverResultsFor(Object p0) {
    return 'HASIL BUAT “$p0”';
  }

  @override
  String discoverResultsBestMatchFirst(int p0) {
    return '$p0 hasil · urut paling cocok';
  }

  @override
  String get discoverCouldnTLoadTryAgain => 'Gagal ngambil. Coba lagi';

  @override
  String discoverLoadingMore(Object p0) {
    return 'Ngambil $p0 lagi…';
  }

  @override
  String discoverBestMatch(Object p0) {
    return 'Paling cocok, $p0';
  }

  @override
  String get discoverBestMatch2 => 'Paling cocok';

  @override
  String get discoverOnYourShelf => 'Udah di rak';

  @override
  String get discoverQueued => 'Antri';

  @override
  String discoverDownloading(Object p0) {
    return 'Lagi diunduh · $p0%';
  }

  @override
  String downloadDownloadingBooks(int p0, Object p1) {
    return 'Ngunduh $p0 buku · $p1%';
  }

  @override
  String downloadDownloadStatus(Object p0) {
    return 'Status unduhan, $p0';
  }

  @override
  String get downloadDownloads => 'Unduhan';

  @override
  String get downloadKeepsGoingWhileYouBrowse =>
      'Jalan terus walau lo pindah layar';

  @override
  String get downloadNoActiveDownloads => 'Gak ada yang lagi diunduh.';

  @override
  String downloadCanceledDownloadOf(Object p0) {
    return 'Unduhan $p0 dibatalin';
  }

  @override
  String downloadQueuedAfter(Object p0) {
    return 'Antri, abis $p0';
  }

  @override
  String get downloadRemoveFromQueue => 'Hapus dari antrian';

  @override
  String get downloadPreparingBook => 'Nyusun buku…';

  @override
  String get downloadAddedToShelf => 'Udah masuk rak';

  @override
  String get downloadAlreadyOnShelf => 'Udah ada di rak';

  @override
  String get downloadFailedConnectionLost => 'Gagal, koneksinya putus';

  @override
  String get bookAddedToGutenberg => 'Masuk Gutenberg';

  @override
  String get bookSize => 'Ukuran';

  @override
  String get bookEnglish => 'Inggris';

  @override
  String get bookLanguage => 'Bahasa';

  @override
  String get bookSynopsis => 'Sinopsis';

  @override
  String get bookNoSynopsisForThisBookYet =>
      'Belum ada sinopsis buat buku ini. Langsung buka bab 1 aja.';

  @override
  String get bookReadMore => 'Baca selengkapnya';

  @override
  String get bookAbout => 'Tentang';

  @override
  String get bookListedIn => 'Masuk daftar';

  @override
  String get bookAuthor => 'Penulis';

  @override
  String get bookFileInfo => 'Info file';

  @override
  String get bookFormat => 'Format';

  @override
  String get bookCopyright => 'Hak cipta';

  @override
  String get bookPublicDomainInTheUs => 'Public domain di AS';

  @override
  String get bookCatalogId => 'ID katalog';

  @override
  String get bookBookDetails => 'Detail buku';

  @override
  String bookOtherBooksInTheCatalog(int p0) {
    return '$p0 buku lain di katalog';
  }

  @override
  String bookFindMoreBooksBy(Object p0) {
    return 'Cari buku lain $p0';
  }

  @override
  String get bookDownloadFailedConnectionLost =>
      'Gagal ngunduh, koneksinya putus.';

  @override
  String get bookReadNow => 'Baca sekarang';

  @override
  String bookContinueReading(Object p0) {
    return 'Lanjut baca · $p0%';
  }

  @override
  String get bookAlreadyOnYourShelfNoNeed =>
      'Udah ada di rak lo, gak perlu diunduh lagi';

  @override
  String get bookQueued => 'Antri…';

  @override
  String get bookDownloading => 'Lagi diunduh…';

  @override
  String get bookFeelFreeToBrowseILl =>
      'Boleh ditinggal, nanti gua kabarin pas udah masuk rak.';

  @override
  String get bookGetBook => 'Ambil buku';

  @override
  String get bookFreeStraightToYourShelf =>
      'Gratis, langsung masuk Rak buku lo';

  @override
  String downloadAddedToShelf2(Object p0) {
    return '$p0 udah masuk rak';
  }

  @override
  String downloadIsAlreadyOnYourShelf(Object p0) {
    return '$p0 udah ada di rak';
  }

  @override
  String downloadCouldnTDownload(Object p0) {
    return 'Gagal ngunduh $p0';
  }

  @override
  String get downloadTapToStartReading => 'Tap buat mulai baca';

  @override
  String get downloadOpen => 'Buka';

  @override
  String get downloadRead => 'Baca';

  @override
  String get chatThisBook => 'Buku ini';

  @override
  String get chatThisBook2 => 'buku ini';

  @override
  String get chatCouldnTOpenHistory => 'Riwayatnya gak kebuka.';

  @override
  String get chatYourChatsAreSafeTryReloading =>
      'Obrolan lo aman kok. Coba muat ulang bentar lagi.';

  @override
  String get chatReload => 'Muat ulang';

  @override
  String get chatNoChatsYet => 'Belum ada obrolan.';

  @override
  String get chatYourChatsWillAppearHereOrganized =>
      'Obrolan yang lo mulai bakal muncul di sini, dipisah per sesi.';

  @override
  String get chatBackToChat => 'Kembali ke obrolan';

  @override
  String get chatChatHistory => 'Riwayat obrolan';

  @override
  String get chatNewChat => 'Obrolan baru';

  @override
  String chatUpdated(Object p0) {
    return 'Diperbarui $p0';
  }

  @override
  String get chatOpenNow => 'Lagi dibuka';

  @override
  String get chatArchived => 'Arsip';

  @override
  String chatMenuFor(Object p0) {
    return 'Menu $p0';
  }

  @override
  String get chatReadingPositionMovedToThisQuote =>
      'Posisi baca pindah ke kutipan ini.';

  @override
  String get chatReadingPositionHasnTMovedTry =>
      'Posisi baca belum dipindah. Coba lagi.';

  @override
  String get chatThisSourceIsNoLongerAvailable =>
      'Sumber ini udah gak tersedia. Posisi baca lo tetap aman.';

  @override
  String get chatAskAboutThisBook => 'Tanyain isi buku ini…';

  @override
  String get chatStopResponse => 'Hentikan jawaban';

  @override
  String get chatSendQuestion => 'Kirim pertanyaan';

  @override
  String get chatRename => 'Ubah judul';

  @override
  String get chatUnavailableForArchivedChats => 'Gak bisa buat obrolan arsip';

  @override
  String get chatDeleteChat => 'Hapus obrolan';

  @override
  String get chatDeleteThisChat => 'Hapus obrolan ini?';

  @override
  String chatWillBePermanentlyDeletedYourBook(Object p0) {
    return '“$p0” bakal dihapus permanen. Bukunya, progres baca, dan obrolan lain gak ikut kehapus.';
  }

  @override
  String get chatCouldnTSaveTheTitleTry => 'Judul belum tersimpan. Coba lagi.';

  @override
  String get chatSave => 'Simpan';

  @override
  String get chatChatTitle => 'Judul obrolan';

  @override
  String get chatThisFeatureIsStillInDevelopment =>
      'Fitur ini masih dalam pengembangan. Jawaban AI bisa keliru, jadi cek sumbernya lewat angka sitasi.';

  @override
  String chatParagraph(Object p0) {
    return 'bagian $p0';
  }

  @override
  String get chatReadInBook => 'Baca di buku';

  @override
  String get chatCollapseContext => 'Ciutkan konteks';

  @override
  String get chatExpandContext => 'Perluas konteks';

  @override
  String get chatDraftNotes => 'CATATAN SEMENTARA';

  @override
  String chatParagraph2(Object p0, Object p1) {
    return '$p0, paragraf $p1';
  }

  @override
  String get chatJumpToLatest => 'Ke terbaru';

  @override
  String get chatBackToReading => 'Balik baca';

  @override
  String get chatArchivedReadOnly => 'Arsip · cuma bisa dibaca';

  @override
  String get chatThisHistoryCanTBeContinued =>
      'Riwayat ini gak bisa dilanjutkan.';

  @override
  String get chatAskAboutThisBook2 => 'Tanya soal buku ini…';

  @override
  String get chatAskAboutThisQuote => 'Tanya soal kutipan ini…';

  @override
  String get chatContinue => 'Lanjutkan';

  @override
  String get chatWhatWouldYouLikeToDiscuss => 'Mau ngobrolin apa soal bukunya?';

  @override
  String get chatThisBookIsUnavailable => 'Buku ini gak tersedia.';

  @override
  String get chatWhatWouldYouLikeToAsk => 'Mau tanya apa soal kutipan ini?';

  @override
  String get chatWriteYourQuestionBelowTheQuote =>
      'Tulis pertanyaan lo di bawah. Kutipan sama terjemahannya ikut kebaca sebagai konteks.';

  @override
  String chatAskAnythingAboutAnswersIncludeCitations(Object p0) {
    return 'Tanya apa aja soal $p0. Jawabannya selalu ada sitasi ke bagian bukunya.';
  }

  @override
  String chat(Object p0, Object p1) {
    return '$p0 · $p1';
  }

  @override
  String get chatTheBookHasChanged => 'Bukunya udah berubah';

  @override
  String get chatOpenInBook => 'Buka di buku';

  @override
  String get chatCheckingQuoteLocation => 'Lagi ngecek lokasi kutipan…';

  @override
  String get chatCheckTheOriginalTextWithoutChanging =>
      'Cek teks aslinya tanpa mengubah posisi baca lo.';

  @override
  String get chatThisSourceIsNoLongerAvailable2 =>
      'Sumber ini udah gak tersedia atau jawabannya belum lolos pengecekan. Kutipan lama tetap bisa lo baca.';

  @override
  String get chatHangOnPreparingTheChat => 'Bentar, lagi siapin obrolan…';

  @override
  String get chatLookingForSourcesInTheBook => 'Lagi nyari sumber di buku…';

  @override
  String get chatHangOnThinking => 'Bentar, lagi mikir…';

  @override
  String get chatWriting => 'Lagi nulis…';

  @override
  String get chatTakingAWhileStillWorking => 'Agak lama nih, masih diproses…';

  @override
  String get chatResponseComplete => 'Jawaban selesai';

  @override
  String get chatTheResponseWasCutOff => 'Jawabannya keputus.';

  @override
  String get chatStopped => 'Dihentiin.';

  @override
  String get chatTheChatWasInterrupted => 'Obrolan sempat terputus';

  @override
  String get chatBackToTranslation => 'Balik ke Terjemahin';

  @override
  String get chatBack => 'Kembali';

  @override
  String get chatNoApiKeyYetAddIt =>
      'API key belum diisi. Isi dulu di Pengaturan, lalu kirim lagi.';

  @override
  String get chatConnectionLostCheckYourInternetAnd =>
      'Koneksi lagi putus. Cek internet lo, lalu coba lagi.';

  @override
  String get chatTheResponseTookTooLongYou =>
      'Kelamaan nunggu jawaban. Lo bisa coba lagi.';

  @override
  String get chatTheResponseHasnTPassedValidation =>
      'Jawabannya belum lolos pengecekan. Coba lagi, yuk.';

  @override
  String get chatApiKeyRejectedCheckYourKey =>
      'API key ditolak. Periksa key lo di Pengaturan.';

  @override
  String get chatYourOpenrouterCreditHasRunOut =>
      'Saldo OpenRouter habis. Cek akun lo, lalu coba lagi.';

  @override
  String get chatRateLimitReachedWaitAMoment =>
      'Lagi kena batas request. Tunggu sebentar, lalu coba lagi.';

  @override
  String get chatTheAiServiceIsHavingTrouble =>
      'Layanan AI lagi bermasalah. Coba lagi nanti.';

  @override
  String get chatToday => 'Hari ini';

  @override
  String get chatYesterday => 'Kemarin';

  @override
  String get chatLastDays => '7 hari terakhir';

  @override
  String get chatOlder => 'Lebih lama';

  @override
  String get chatCheckingTheBook => 'Lagi meriksa isi buku…';

  @override
  String chatReading(Object p0) {
    return 'Lagi baca $p0…';
  }

  @override
  String chatChunks(Object p0, Object p1, Object p2) {
    return '$p0 $p1/$p2 potongan';
  }

  @override
  String chatPreparingTheBookChunks(Object p0, Object p1) {
    return 'Lagi nyiapin buku… $p0/$p1 potongan';
  }

  @override
  String get chatPlanning => 'Lagi nyusun rencana';

  @override
  String get chatLoadingSavedNotes => 'Lagi ambil catatan tersimpan';

  @override
  String get chatWritingTheResponse => 'Lagi nulis jawaban';

  @override
  String chatWorking(Object p0, Object p1) {
    return 'Lagi $p0$p1';
  }

  @override
  String get chatThisDraftHasnTPassedResponse =>
      'Draf ini belum lolos pengecekan jawaban.';

  @override
  String chatFixingTheResponseFormat(Object p0, Object p1) {
    return 'Lagi benerin format jawaban… ($p0/$p1)';
  }

  @override
  String get chatInterpretation => 'Tafsiran';

  @override
  String get chatOutsideTheBook => 'Di luar buku';

  @override
  String chatStepsCompleted(int p0) {
    return '$p0 langkah selesai';
  }

  @override
  String chatSteps(Object p0) {
    return 'Langkah $p0';
  }

  @override
  String chatShowMore(Object p0) {
    return 'lihat $p0 lagi';
  }

  @override
  String get chatAnswerNow => 'Jawab sekarang';

  @override
  String chatUseTheNotesReceivedSoFar(int p0) {
    return 'Pakai $p0 catatan yang udah masuk, sisa buku gak dibaca.';
  }

  @override
  String peekNextGroup(Object p0) {
    return '$p0 · grup berikutnya';
  }

  @override
  String peekConnectsToStartOf(Object p0) {
    return 'Nyambung ke · awal $p0';
  }

  @override
  String get peekTranslate => 'Artiin';

  @override
  String get peekTryTranslatingAgain => 'Coba artiin lagi';

  @override
  String get peekBreakThisDownToo => 'Bedahin ini juga';

  @override
  String get peekWhatCameThroughIsStillHere =>
      'Yang udah masuk tetep di sini, tapi gak disimpen.';

  @override
  String get peekTranslationNeedsAnOpenrouterApiKey =>
      'Artiin butuh API key OpenRouter.';

  @override
  String get peekApiKeyRejected => 'API key-nya ditolak';

  @override
  String get peekOpenrouterRejectedYourKeyCheckIt =>
      'OpenRouter gak nerima key lo. Cek lagi di Pengaturan.';

  @override
  String get peekOpenrouterCreditRanOut => 'Saldo OpenRouter abis';

  @override
  String get peekTopUpAtOpenrouterAiThen =>
      'Isi saldo dulu di openrouter.ai, abis itu coba lagi.';

  @override
  String get peekCouldnTTranslate => 'Yah, gagal ngartiin';

  @override
  String get peekTheConnectionIsHavingTroubleYou =>
      'Koneksi lagi ngadat. Teks aslinya tetep bisa dibaca.';

  @override
  String get breakdownCouldnTBringTheQuoteOver =>
      'Kutipannya belum bisa dibawa. Coba buka ulang bukunya.';

  @override
  String breakdownBreakdownComplete(Object p0) {
    return 'Bedahan udah lengkap, $p0';
  }

  @override
  String get breakdownTerms => 'Istilah';

  @override
  String get breakdownPractice => 'Praktek';

  @override
  String get breakdownBreakdown => 'Bedahin';

  @override
  String get breakdownCutOffHalfway => 'Kepotong di tengah';

  @override
  String get breakdownBreakingItDown => 'Lagi ngebedah...';

  @override
  String get breakdownHereSTheBreakdown => 'Udah dibedah nih';

  @override
  String breakdownSectionsReceived(int p0) {
    return '$p0 bagian masuk';
  }

  @override
  String get breakdownBreakingItDownHangOn => 'Lagi ngebedah, tunggu ya';

  @override
  String breakdownBreakdown2(Object p0, Object p1) {
    return 'Bedahin, $p0 $p1';
  }

  @override
  String get breakdownComplete => 'udah lengkap';

  @override
  String get breakdownCancelBackToTranslation => 'Batalin, balik ke Artinya';

  @override
  String get breakdownBackToTranslation => 'Balik ke Artinya';

  @override
  String get breakdownYourTranslationIsSavedButBreakdown =>
      'Artinya udah kesimpen, tapi Bedahin butuh AI lewat OpenRouter. API key lo udah gak ada di Pengaturan, tempel lagi sekali aja.';

  @override
  String get breakdownIdea => '1 gagasan';

  @override
  String breakdownSections(int p0) {
    return '$p0 bagian';
  }

  @override
  String get breakdownCouldnTBreakItDown => 'Yah, gagal ngebedah';

  @override
  String get breakdownYouReOffline => 'Lagi offline nih';

  @override
  String get breakdownBreakdownNeedsInternetConnectAndTry =>
      'Bedahin butuh internet. Nyalain dulu, abis itu coba lagi. Bedahan yang udah kesimpen tetep bisa dibuka.';

  @override
  String get breakdownOpenrouterRejectedYourKeyCheckIt =>
      'OpenRouter gak nerima key lo. Cek lagi di Pengaturan, siapa tau kepotong pas ditempel.';

  @override
  String breakdownKeyRejected(Object p0) {
    return '$p0 · key ditolak';
  }

  @override
  String get breakdownTopUpAtOpenrouterAiThen =>
      'Isi saldo dulu di openrouter.ai, abis itu balik ke sini dan coba lagi.';

  @override
  String get breakdownNoCredit => '402 · saldo abis';

  @override
  String get breakdownTheResponseFormatIsInvalid => 'Jawabannya berantakan';

  @override
  String get breakdownTheAiReturnedSomethingLumaCan =>
      'AI-nya ngasih jawaban yang gak bisa dibaca Luma. Coba sekali lagi, biasanya beres.';

  @override
  String get breakdownInvalidFormat => 'format gak valid';

  @override
  String breakdownSection(Object p0) {
    return 'Bagian $p0';
  }

  @override
  String get breakdownTranslatedText => 'Teks terjemahan';

  @override
  String breakdownTranslatedTextSections(int p0) {
    return 'Teks terjemahan, $p0 bagian';
  }

  @override
  String get breakdownCollapseTranslatedText => 'Lipet teks terjemahan';

  @override
  String get breakdownTextBeingExplained => 'Teks yang dibedah';

  @override
  String breakdownSectionOf(Object p0, Object p1, Object p2) {
    return 'Bagian $p0 dari $p1, $p2';
  }

  @override
  String get breakdownMeaning => 'MAKSUDNYA';

  @override
  String get breakdownLogic => 'LOGIKANYA';

  @override
  String breakdownSection2(Object p0) {
    return ' · bagian $p0';
  }

  @override
  String get breakdownConnectsTo => 'NYAMBUNG KE';

  @override
  String get breakdownPuttingItIntoPractice => 'Praktekinnya gini';

  @override
  String get breakdownContinuation => 'Lanjutan';

  @override
  String breakdownContinuationOf(Object p0) {
    return 'Lanjutan $p0';
  }

  @override
  String breakdownChapter(Object p0) {
    return 'Bab $p0';
  }

  @override
  String breakdownConnectsTo2(Object p0, Object p1) {
    return 'Nyambung ke $p0, $p1';
  }

  @override
  String breakdownConnectsToDoubleTapToPreview(Object p0, Object p1) {
    return 'Nyambung ke $p0, $p1. Ketuk dua kali buat ngintip.';
  }

  @override
  String get breakdownTheAiIsBusyGiveIt =>
      'AI-nya lagi rame. Tungguin bentar, atau coba minta ulang.';

  @override
  String get breakdownTheConnectionDroppedDuringTheBreakdown =>
      'Koneksinya putus pas lagi ngebedah.';

  @override
  String get breakdownTheConnectionDroppedDuringTheBreakdown2 =>
      'Koneksinya putus pas lagi ngebedah. Bagian 1 tetep di sini.';

  @override
  String breakdownTheConnectionDroppedDuringTheBreakdown3(Object p0) {
    return 'Koneksinya putus pas lagi ngebedah. Bagian 1–$p0 tetep di sini.';
  }

  @override
  String get breakdownTryAgainFromTheStart => 'Coba lagi dari awal';

  @override
  String breakdownHighlightInTheText(Object p0) {
    return 'Sorot \"$p0\" di teks';
  }

  @override
  String get breakdownOpenTranslatedText => 'Buka teks terjemahan';

  @override
  String breakdownJumpToSectionOf(Object p0, Object p1) {
    return 'Lompat ke bagian $p0 dari $p1';
  }

  @override
  String breakdownJumpTo(Object p0) {
    return 'Lompat ke $p0';
  }

  @override
  String get bookTitleAuthorUpdated => 'Sip, judul & penulisnya udah diganti';

  @override
  String get bookCouldnTSave => 'Yah, gagal nyimpen';

  @override
  String get bookEditTitleAuthor => 'Ubah judul & penulis';

  @override
  String get bookCoverPreview => 'Preview cover';

  @override
  String get bookOriginalEpubCover => 'Cover asli EPUB';

  @override
  String get bookDefaultCover => 'Cover default';

  @override
  String get bookTitle => 'Judul';

  @override
  String get bookAuthorOptional => 'Penulis (opsional)';

  @override
  String get bookAuthorName => 'Nama penulis';

  @override
  String get bookYourOriginalCoverIsSavedYou =>
      'Cover asli tetep disimpen, bisa dinyalain lagi kapan aja.';

  @override
  String get bookThisCoverComesFromTheEpub =>
      'Cover ini bawaan file EPUB, jadi gak ikut berubah pas judulnya lo ganti.';

  @override
  String get bookUseDefaultCover => 'Pakai cover default';

  @override
  String get bookRestoreOriginals => 'Balikin ke aslinya';

  @override
  String bookFromEpub(Object p0, Object p1) {
    return 'Dari EPUB: $p0 · $p1';
  }

  @override
  String get bookshelfAddedToYourShelf => 'Sip, udah masuk rak!';

  @override
  String bookshelfChapterAlreadyExists(Object p0) {
    return 'Bab $p0 udah ada';
  }

  @override
  String bookshelfReplacingChapterWillAlsoDeleteIts(Object p0) {
    return 'Kalau diganti, terjemahan yang udah kesimpen di bab $p0 yang lama ikut kehapus.';
  }

  @override
  String get bookshelfReplace => 'Ganti';

  @override
  String bookshelfAddedToShelf(Object p0) {
    return '$p0 masuk rak ✨';
  }

  @override
  String bookshelfChapterAddedTo(Object p0, Object p1) {
    return 'Bab $p0 masuk ke $p1 ✨';
  }

  @override
  String get bookshelfBookInfo => 'Info buku';

  @override
  String get bookshelfRemoveFromShelf => 'Hapus dari rak';

  @override
  String bookshelfProgress(Object p0) {
    return 'Progres $p0%';
  }

  @override
  String bookshelfTranslatedParagraphs(int p0) {
    return '$p0 paragraf yang udah diartiin';
  }

  @override
  String get bookshelfAnd => ' sama ';

  @override
  String bookshelfRemoveFromYourShelf(Object p0) {
    return 'Hapus \"$p0\" dari rak?';
  }

  @override
  String bookshelfYourOriginalFileStaysSafe(Object p0) {
    return '${p0}File aslinya tetep aman kok.';
  }

  @override
  String get bookshelfNeverMind => 'Gak jadi';

  @override
  String get bookshelfCouldnTDeleteTheBook => 'Yah, gagal ngehapus bukunya';

  @override
  String get bookshelfSortBy => 'Urutin pake';

  @override
  String get bookshelfCouldnTOpenYourShelf => 'Yah, rak-nya gagal kebuka';

  @override
  String bookshelfThatSEverythingBooksOnYour(int p0) {
    return 'Udah mentok. $p0 buku di rak lo.';
  }

  @override
  String get bookshelfAllBooks => 'Semua buku';

  @override
  String bookshelfShelfOrder(Object p0) {
    return 'Urutan rak: $p0';
  }

  @override
  String get bookshelfGridView => 'Tampilan grid';

  @override
  String get bookshelfListView => 'Tampilan list';

  @override
  String get bookshelfAFamousOpeningLine => 'KALIMAT PEMBUKA PALING TERKENAL';

  @override
  String bookshelfGet(Object p0) {
    return 'Ambil $p0';
  }

  @override
  String get bookshelfGet2 => 'Ambil';

  @override
  String get bookshelfYourShelfIsStill => 'Rak lo masih ';

  @override
  String get bookshelfEmpty => 'kosong';

  @override
  String get bookshelfGetTheBookAboveOrFind =>
      'Ambil buku di atas, atau cari yang lain. Gratis semua.';

  @override
  String get bookshelfFindFreeBooks => 'Cari buku gratis';

  @override
  String get bookshelfOrImportEpubMarkdownFromFiles =>
      'atau import EPUB / PDF / Markdown dari Files';

  @override
  String get bookshelfTapAParagraphWhenYouGet =>
      'Nanti tap paragraf yang bikin pusing';

  @override
  String get bookshelfPuzzledByASentenceBreakIt =>
      'Bingung sama satu kalimat? Bedahin';

  @override
  String get bookshelfFromTheTranslationSheetTapBreakdown =>
      'Dari sheet Artinya, tap Bedahin: kalimatnya dipecah bagian per bagian, dijelasin satu-satu.';

  @override
  String get bookshelfChatAboutTheBookAnytime => 'Ngobrolin bukunya kapan aja';

  @override
  String get bookshelfAskAboutCharactersThePlotOr =>
      'Nanya soal tokoh, alur, atau kenapa gitu: jawabannya ngutip halaman bukunya langsung.';

  @override
  String bookshelfDownloading(Object p0) {
    return '$p0 lagi diunduh';
  }

  @override
  String bookshelfWhileYouWaitOf(Object p0, Object p1) {
    return 'SAMBIL NUNGGU · $p0 DARI $p1';
  }

  @override
  String get bookshelfHereSWhatItMeans => 'ARTINYA GINI NIH';

  @override
  String get backupNoBackupsYet => 'Belum pernah backup nih';

  @override
  String get backupYourDataIsOnlyOnThis =>
      'Data lo cuma ada di HP ini doang. Amanin dulu yuk.';

  @override
  String get backupItSBeenDaysSinceYour => 'Udah 6 hari belum backup nih';

  @override
  String get backupYourReinstallIsDueTomorrowBack =>
      'Besok jatah install ulang. Amanin data lo dulu yuk.';

  @override
  String backupItSBeenDaysSinceYour2(int p0) {
    return 'Udah $p0 hari belum backup nih';
  }

  @override
  String get backupBackUpYourDataBeforeYour =>
      'Amanin data lo dulu yuk, sebelum keburu install ulang.';

  @override
  String get backupBackupReminder => 'Pengingat backup';

  @override
  String get backupDismissReminder => 'Tutup pengingat';

  @override
  String get shelfYourBookshelf => 'Rak buku lo';

  @override
  String get shelfImportEpub => 'Import EPUB';

  @override
  String get bookReadingPosition => 'Lagi di';

  @override
  String get bookLastOpened => 'Terakhir dibuka';

  @override
  String get bookAdded => 'Ditambah';

  @override
  String get bookParagraphsTranslated2 => 'Paragraf diartiin';

  @override
  String get bookFileSize => 'Ukuran file';

  @override
  String get bookFileName => 'Nama file';

  @override
  String get bookAuthorNotFound => 'Penulis gak ketemu';

  @override
  String continueContinueReading(Object p0, Object p1) {
    return 'Lanjut baca $p0, $p1';
  }

  @override
  String get continueLetSKeepReading => 'Lanjut baca yuk →';

  @override
  String continueChapterOf(Object p0, Object p1) {
    return 'Bab $p0 dari $p1';
  }

  @override
  String get breakdownPeopleTerms => 'Tokoh & istilah';

  @override
  String get relativeToday => 'hari ini';

  @override
  String get relativeYesterday => 'kemarin';

  @override
  String relativeDays(int count) {
    return '$count hari lalu';
  }

  @override
  String relativeWeeks(int count) {
    return '$count minggu lalu';
  }

  @override
  String relativeMonths(int count) {
    return '$count bulan lalu';
  }

  @override
  String relativeYears(int count) {
    return '$count tahun lalu';
  }

  @override
  String get notStarted => 'Belum mulai';

  @override
  String get finishedReading => 'Kelar dibaca';

  @override
  String chapterPosition(int current, int total) {
    return 'Bab $current dari $total';
  }

  @override
  String get sortLastOpened => 'Terakhir dibuka';

  @override
  String get sortTitle => 'Judul (A–Z)';

  @override
  String get sortAdded => 'Baru ditambah';

  @override
  String chapterList(String range) {
    return 'Bab $range';
  }

  @override
  String chapterListLower(String range) {
    return 'bab $range';
  }

  @override
  String get noChapters => 'Belum ada bab';

  @override
  String chapterCount(int count) {
    return '$count bab';
  }

  @override
  String chaptersRead(String range) {
    return '$range udah dibaca';
  }

  @override
  String chapterReading(int number) {
    return 'lagi baca bab $number';
  }

  @override
  String get unknownAuthor => 'tanpa penulis';

  @override
  String deletedProgress(String details) {
    return '$details ikut kehapus. ';
  }

  @override
  String get bookDeleted => 'Buku ini sudah dihapus.';

  @override
  String get bookChanged =>
      'Isi buku berubah. Mulai obrolan baru untuk lanjut.';

  @override
  String get chatHistoryDamaged =>
      'Riwayat sesi ini rusak. Lo bisa hapus sesi ini.';

  @override
  String get chatUnavailable => 'Obrolan belum bisa dibuka. Coba buka lagi.';

  @override
  String get questionInvalid => 'Pertanyaan kosong atau terlalu panjang.';

  @override
  String get checkpointInvalid =>
      'Progres penelusuran sudah tidak cocok. Kirim pertanyaan baru buat mulai ulang.';

  @override
  String get notificationChannelName => 'Unduhan buku';

  @override
  String get notificationChannelDescription =>
      'Kabar pas buku yang diunduh udah masuk rak';

  @override
  String sourceParagraph(int number) {
    return 'bagian $number';
  }

  @override
  String get navShelf => 'Rak';

  @override
  String get markdownThisFileIsEmpty => 'Filenya kosong nih';

  @override
  String get markdownThereSNoReadingText =>
      'Gak ada teks bacaan di dalamnya, jadi belum ada yang bisa dimasukin. Cek lagi file-nya, atau pilih file bab yang lain.';

  @override
  String markdownPWords(Object p0) {
    return '$p0 · 0 kata';
  }

  @override
  String get markdownCouldnTReadTheChapter => 'Nomor babnya gak kebaca';

  @override
  String get markdownTheChapterNumberAtThe =>
      'Di bagian atas file ada tulisan nomor bab, tapi bukan angka. Ganti jadi angka, terus coba lagi. Atau pilih file lain.';

  @override
  String markdownPChapterNumberP(Object p0, Object p1) {
    return '$p0 · nomor bab: “$p1”';
  }

  @override
  String get markdownInvalidBookName => 'Nama bukunya gak valid';

  @override
  String get markdownTheBookNameAtThe =>
      'Nama buku di bagian atas file cuma boleh huruf kecil, angka, sama strip. Ganti jadi kayak ';

  @override
  String markdownPBookNameP(Object p0, Object p1) {
    return '$p0 · nama buku: “$p1”';
  }

  @override
  String get markdownOrRemoveThatLineAnd =>
      ', atau hapus baris itu biar Luma yang nebak.';

  @override
  String get markdownCouldnTReadThisFile => 'Filenya gak kebaca';

  @override
  String get markdownLumaCanTReadThis =>
      'Luma gak bisa baca isi file ini. Coba pilih file lain, atau simpan ulang filenya dulu.';

  @override
  String get navSettings => 'Atur';

  @override
  String get editTitleEmpty => 'Judul gak boleh kosong';

  @override
  String get backToConversation => 'Balik ke obrolan';

  @override
  String readingDurationMinutes(int minutes) {
    return '$minutes mnt';
  }

  @override
  String readingDurationHours(int hours, int minutes) {
    return '$hours jam $minutes mnt';
  }

  @override
  String get chatPartialNote =>
      'Sebagian pertanyaan belum punya bukti yang cukup di sumber ini.';

  @override
  String get chatNoEvidenceNote =>
      'Belum ada sumber yang cukup untuk menjawab itu. Coba tunjukkan kutipan atau perjelas pertanyaannya.';

  @override
  String get importUnpackingPdf => 'Lagi ngebongkar PDF...';

  @override
  String get importPdfPasswordTitle => 'PDF-nya dikunci password';

  @override
  String get importPdfPasswordBody =>
      'Luma belum bisa buka PDF yang pake password. Buka kuncinya dulu di app lain, simpen salinannya, terus import lagi.';

  @override
  String get importPdfScanTitle => 'PDF ini hampir gak ada teksnya';

  @override
  String get importPdfScanBody =>
      'Kebanyakan halamannya gak punya teks yang bisa dibaca, bisa jadi hasil scan. Buat PDF scan, pakai jalur foto atau Docling buat convert ke Markdown, terus import file .md-nya.';

  @override
  String get importPdfDamagedTitle => 'PDF-nya gak bisa dibuka';

  @override
  String get importPdfDamagedBody =>
      'Kayaknya rusak atau kedownload setengah. Coba download ulang, terus import lagi.';

  @override
  String get importPdfEmptyTitle => 'Gak ada teks yang bisa dibaca';

  @override
  String get importPdfEmptyBody =>
      'PDF-nya kebuka, tapi gak nemu teks buat dijadiin bab. Kalau isinya gambar doang, pakai jalur foto atau Docling.';

  @override
  String get importPdfIoTitle => 'File-nya gak kebaca';

  @override
  String get importPdfIoBody =>
      'Gagal baca atau nyalin file-nya. Cek ruang penyimpanan, terus coba lagi.';

  @override
  String importPdfSkippedPages(int p0) {
    return '$p0 halaman tanpa teks dilewati';
  }

  @override
  String get authLoginTitle => 'Rak lo, ikut\nke mana aja.';

  @override
  String get authLoginSubtitle => 'Satu akun buat semua bacaan lo';

  @override
  String get authChapterOne => 'BAB I';

  @override
  String get authChapterTwo => 'BAB II';

  @override
  String get authChapterThree => 'BAB III';

  @override
  String get authBenefitQuota => 'Kuota AI gratis';

  @override
  String get authBenefitQuotaNote => 'Artinya, Bedahin, sama Ngobrol';

  @override
  String get authBenefitBackup => 'Backup ke cloud';

  @override
  String get authBenefitBackupNote => 'Rak sama catatan lo aman';

  @override
  String get authBenefitSync => 'Sync antar HP';

  @override
  String get authBenefitSyncNote => 'Lanjut di iPhone atau Android';

  @override
  String get authSignInGoogle => 'Masuk pakai Google';

  @override
  String get authConnectingGoogle => 'Nyambung ke Google…';

  @override
  String get authGoogleWillAsk =>
      'Abis ini Google nanya lo mau pakai akun yang mana.';

  @override
  String authPrivacyNote(String policy) {
    return 'Dengan masuk, lo setuju sama $policy Luma.';
  }

  @override
  String get authPrivacyPolicy => 'Kebijakan privasi';

  @override
  String get authNetworkTitle => 'Gak bisa nyambung';

  @override
  String get authNetworkBody => 'Cek internet lo, terus coba lagi.';

  @override
  String get authTryAgain => 'Coba lagi';

  @override
  String get authRejectedTitle => 'Login-nya ditolak';

  @override
  String get authRejectedBody =>
      'Akun Google ini gak bisa dipakai buat masuk. Coba pakai akun lain.';

  @override
  String get authUseAnotherAccount => 'Pakai akun lain';

  @override
  String get authDevBadge => 'Build developer';

  @override
  String get authDevLabel => 'Build dev';

  @override
  String get authDevTitle => 'Isi yang kosong.';

  @override
  String get authDevEmailLead => 'Email gua';

  @override
  String get authDevPasswordLead => 'dan kata sandinya';

  @override
  String get authDevNote =>
      'Cuma ada di build developer. Versi rilis cuma pakai Google.';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Kata sandi';

  @override
  String get authSignUp => 'Daftar';

  @override
  String get authSignIn => 'Masuk';

  @override
  String get authInvalidCredentialsTitle => 'Email atau kata sandinya salah';

  @override
  String get authInvalidCredentialsBody => 'Cek lagi, terus coba masuk lagi.';

  @override
  String get authUserExistsTitle => 'Email ini udah terdaftar';

  @override
  String get authUserExistsBody => 'Pakai Masuk aja, bukan Daftar.';

  @override
  String get authPasswordShortTitle => 'Kata sandinya kependekan';

  @override
  String get authPasswordShortBody => 'Minimal 8 karakter.';

  @override
  String get authSignedInAs => 'Masuk sebagai';

  @override
  String get authChange => 'Ganti';

  @override
  String get authInviteIntro =>
      'Luma lagi beta, jadi akun baru butuh undangan.';

  @override
  String get authInviteLead => 'Kode undangan gua:';

  @override
  String get authInviteHint =>
      'Huruf besar/kecil gak ngaruh. Strip boleh dilewatin.';

  @override
  String get authContinue => 'Lanjut';

  @override
  String get authNoteLabel => 'CATATAN';

  @override
  String get authInviteUsedTitle => 'Kode ini udah dipakai';

  @override
  String get authInviteUsedBody =>
      'Satu kode buat satu akun. Minta kode baru ke yang ngundang lo.';

  @override
  String get authInviteInvalidTitle => 'Kodenya salah';

  @override
  String get authInviteInvalidBody =>
      'Cek lagi hurufnya, atau minta kode baru ke yang ngundang lo.';

  @override
  String get settingsAccount => 'Akun';

  @override
  String get authExLibris => 'EX LIBRIS';

  @override
  String get authViaGoogle => 'Masuk lewat Google';

  @override
  String get authViaEmail => 'Masuk lewat email';

  @override
  String get authSignOut => 'Keluar';

  @override
  String get authDeleteAccount => 'Hapus akun';

  @override
  String get authSignOutTitle => 'Keluar dari akun?';

  @override
  String get authSignOutBody =>
      'Buku, progres, sama catatan di HP ini tetap ada. Lo balik ke layar Masuk; backup + sync berhenti dulu.';

  @override
  String get authSwitchTitle => 'Ganti ke akun lain?';

  @override
  String get authSwitchOwner => 'Isi HP ini punya';

  @override
  String get authSwitchNew => 'Mau masuk pakai';

  @override
  String get authSwitchBodyLead => 'Biar gak kecampur,';

  @override
  String get authSwitchBodyBold => 'isi HP ini dihapus dulu';

  @override
  String get authSwitchBodyTail =>
      ': buku, progres, catatan. Data akun lama tetap aman di cloud.';

  @override
  String get authSwitchConfirm => 'Hapus isi HP & lanjut';

  @override
  String get authSwitchKeep => 'Pakai akun lama aja';

  @override
  String get authDeleteTitle => 'Hapus akun selamanya?';

  @override
  String get authDeleteBody =>
      'Centang semua biar yakin lo ngerti apa yang ilang. Ini gak bisa dibalikin.';

  @override
  String authDeleteCheckAccount(String email) {
    return 'Akun $email kehapus';
  }

  @override
  String get authDeleteCheckBackup => 'Semua backup di cloud ilang';

  @override
  String get authDeleteCheckSync => 'Data sync di semua HP lo ilang';

  @override
  String get authDeleteNote =>
      'Buku di HP ini gak ikut kehapus, tapi gak kebackup lagi.';

  @override
  String get authDeleteConfirm => 'Hapus akun selamanya';

  @override
  String get authSessionExpiredTitle => 'Sesi lo habis';

  @override
  String get authSessionExpiredBody =>
      'Baca tetap jalan; backup & sync nunggu dulu.';

  @override
  String get authSignInAgain => 'Login lagi';

  @override
  String get authCloseBanner => 'Tutup';

  @override
  String authToastSignedIn(String name) {
    return 'Udah masuk. Halo, $name!';
  }

  @override
  String get authToastSignedOut => 'Udah keluar. Buku di HP ini tetap ada.';

  @override
  String get authToastDeleted => 'Akun lo udah dihapus.';

  @override
  String get authToastDeleteFailed => 'Gagal hapus akun. Gak ada internet.';

  @override
  String get quotaToday => 'Kuota AI hari ini';

  @override
  String quotaResetAt(String time) {
    return 'Reset $time';
  }

  @override
  String quotaResetAtIn(String time, String countdown) {
    return 'Reset $time · $countdown';
  }

  @override
  String quotaCountdown(int hours, int minutes) {
    return '${hours}j ${minutes}m';
  }

  @override
  String quotaTapsLeft(int count) {
    return '± $count tap lagi';
  }

  @override
  String get quotaLow => 'Hampir abis';

  @override
  String get quotaUsedUp => 'Kuota gratis hari ini udah kepakai semua.';

  @override
  String get quotaLoading => 'Lagi dimuat…';

  @override
  String get quotaLoadFailed => 'Gak bisa ngecek sisa kuota.';

  @override
  String get quotaSource => 'Sumber AI';

  @override
  String get quotaOwnKey => 'Key sendiri';

  @override
  String get quotaOwnKeyNote =>
      'Biaya dari saldo OpenRouter lo. Kuota gratis gak kepotong.';

  @override
  String get quotaFree => 'Kuota AI gratis';

  @override
  String get quotaRevoked => 'Dicabut';

  @override
  String get quotaBlocked => 'Diblokir';

  @override
  String get quotaRevokedNote => 'AI masih bisa dipakai pakai key sendiri.';

  @override
  String get quotaExhaustedTitle => 'Kuota gratis hari ini abis';

  @override
  String quotaExhaustedBody(String time, int hours, int minutes) {
    return 'Reset jam $time ($hours jam $minutes menit lagi). Biar bisa lanjut sekarang, pakai key OpenRouter sendiri.';
  }

  @override
  String get quotaResetIn => 'Reset dalam';

  @override
  String get quotaHoursUnit => 'j';

  @override
  String get quotaMinutesUnit => 'm';

  @override
  String quotaTapsOf(int count) {
    return '0 dari ± $count tap tersisa';
  }

  @override
  String quotaTapsOfShort(int count) {
    return '0 dari ± $count tap';
  }

  @override
  String quotaPeekBody(String time) {
    return 'Teks aslinya tetap bisa dibaca. Artiin lagi abis reset jam $time, atau pakai key sendiri.';
  }

  @override
  String get quotaUseOwnKey => 'Pakai key sendiri';

  @override
  String get quotaOk => 'Oke';

  @override
  String quotaChatClosed(String time) {
    return 'Kuota abis, buka lagi jam $time';
  }

  @override
  String get quotaBannedPill => 'Kuota gratis diblokir';

  @override
  String get quotaBannedTitle => 'Akses AI gratis lo dicabut';

  @override
  String get quotaBannedBody =>
      'Akun ini gak bisa pakai kuota gratis Luma lagi. Artinya, Bedahin, sama Ngobrol tetap bisa jalan pakai key OpenRouter lo sendiri.';

  @override
  String get aiSection => 'AI';

  @override
  String get aiSourceFree => 'Kuota gratis';

  @override
  String get aiSourceOwn => 'Key sendiri';

  @override
  String get aiOwnKeyCost =>
      'Biayanya kepotong dari saldo akun OpenRouter lo. Kuota gratis Luma gak dipakai selama key ini aktif.';

  @override
  String get aiKeyRejected401 => 'Key-nya ditolak (401)';

  @override
  String get aiKeyRejectedBox =>
      'OpenRouter nolak key ini. Cek lagi di openrouter.ai/keys, terus tempel ulang. AI berhenti dulu sampai key-nya bener, atau balik ke kuota gratis.';

  @override
  String get aiCheckedJustNow => 'Dicek barusan';

  @override
  String get aiDefaultTag => 'default';

  @override
  String get aiBackToFree => 'Balik ke kuota gratis';

  @override
  String get aiBackToFreeTitle => 'Balik ke kuota gratis?';

  @override
  String aiBackToFreeBody(String model) {
    return 'Key OpenRouter lo dihapus dari HP ini. Model balik ke $model, salah satu dari 3 model gratis.';
  }

  @override
  String get aiBackToFreeConfirm => 'Balik ke gratis';

  @override
  String get aiPickModel => 'Pilih model';

  @override
  String get aiFreeModelsNote => 'Kuota gratis cuma bisa pakai 3 model ini.';

  @override
  String get aiDefaultCheapest => 'Default · paling hemat';

  @override
  String get aiMoreModelsTitle => 'Mau model lain?';

  @override
  String get aiMoreModelsBody =>
      'Pakai key OpenRouter sendiri, 300-an model kebuka. Biayanya dari saldo lo.';

  @override
  String aiSearchModels(int count) {
    return 'Cari dari $count model';
  }

  @override
  String get aiFilterAll => 'Semua';

  @override
  String get aiFilterCheap => 'Hemat';

  @override
  String get aiFilterLong => 'Konteks panjang';

  @override
  String get aiModelsLoadFailed =>
      'Daftar model gak kebaca. Cek internet lo, terus coba lagi.';

  @override
  String get aiNoModelMatch => 'Gak ada model yang cocok.';
}
