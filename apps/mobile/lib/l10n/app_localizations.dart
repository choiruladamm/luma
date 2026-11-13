import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// No description provided for @interfaceLanguage.
  ///
  /// In id, this message translates to:
  /// **'Bahasa antarmuka'**
  String get interfaceLanguage;

  /// No description provided for @interfaceLanguageNote.
  ///
  /// In id, this message translates to:
  /// **'Bahasa ini cuma buat tampilan. Terjemahan dan jawaban AI tetap Bahasa Indonesia.'**
  String get interfaceLanguageNote;

  /// No description provided for @languageSaveFailed.
  ///
  /// In id, this message translates to:
  /// **'Bahasanya gagal disimpen. Coba lagi, ya.'**
  String get languageSaveFailed;

  /// Interface copy in ui/core/widgets/book_row.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi diimport {p0}'**
  String bookImporting(Object p0);

  /// Interface copy in ui/core/widgets/book_row.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi diproses'**
  String get bookProcessing;

  /// Interface copy in ui/core/widgets/book_row.dart
  ///
  /// In id, this message translates to:
  /// **'Baru'**
  String get bookNew;

  /// Interface copy in ui/core/widgets/book_row.dart
  ///
  /// In id, this message translates to:
  /// **'Kelar!'**
  String get bookFinished;

  /// Interface copy in ui/core/widgets/book_row.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} bab'**
  String bookChapters(int p0);

  /// Interface copy in ui/core/widgets/ai_status.dart
  ///
  /// In id, this message translates to:
  /// **'Salin'**
  String get aiCopy;

  /// Interface copy in ui/core/widgets/ai_status.dart
  ///
  /// In id, this message translates to:
  /// **'{p0}, belum bisa: {p1}'**
  String aiUnavailable(Object p0, Object p1);

  /// Interface copy in ui/core/widgets/book_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Tutup menu'**
  String get bookCloseMenu;

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'Hasil cari'**
  String get searchSearchResults;

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'Hasil sebelumnya'**
  String get searchPreviousResult;

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke daftar hasil'**
  String get searchBackToResults;

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} dari {p1}'**
  String searchOf(Object p0, Object p1);

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} dari {p1} · {p2}'**
  String searchOf2(Object p0, Object p1, Object p2);

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'Hasil berikutnya'**
  String get searchNextResult;

  /// Interface copy in ui/core/widgets/search_navigator.dart
  ///
  /// In id, this message translates to:
  /// **'Keluar dari cari'**
  String get searchExitSearch;

  /// Interface copy in ui/core/widgets/search_field.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus isian'**
  String get searchClearField;

  /// Interface copy in ui/core/widgets/dialog.dart
  ///
  /// In id, this message translates to:
  /// **'Batal'**
  String get dialogCancel;

  /// Interface copy in ui/core/widgets/sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tutup'**
  String get sheetClose;

  /// Interface copy in ui/core/widgets/search_result.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi dibaca'**
  String get searchCurrentlyReading;

  /// Interface copy in ui/core/widgets/search_result.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} hasil'**
  String searchResults(int p0);

  /// Interface copy in ui/core/widgets/field.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus {p0}'**
  String fieldClear(Object p0);

  /// Interface copy in ui/core/widgets/field.dart
  ///
  /// In id, this message translates to:
  /// **'Liat key'**
  String get fieldShowKey;

  /// Interface copy in ui/core/widgets/field.dart
  ///
  /// In id, this message translates to:
  /// **'Sembunyiin key'**
  String get fieldHideKey;

  /// Interface copy in ui/core/widgets/nav_bar.dart
  ///
  /// In id, this message translates to:
  /// **'Navigasi utama'**
  String get navMainNavigation;

  /// Interface copy in ui/core/widgets/nav_bar.dart
  ///
  /// In id, this message translates to:
  /// **'{p0}, {p1} unduhan jalan'**
  String navActiveDownloads(Object p0, Object p1);

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cari kata di buku ini'**
  String get bookSearchThisBook;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Gak ketemu “{p0}” di buku ini'**
  String bookNoMatchesForInThisBook(Object p0);

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cek ejaannya, atau coba kata lain.'**
  String get bookCheckTheSpellingOrTryAnother;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Pencariannya lagi macet'**
  String get bookSearchIsStuck;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tutup terus buka lagi ya.'**
  String get bookCloseItAndTryAgain;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Terakhir dicari'**
  String get bookRecentSearches;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus'**
  String get bookClear;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Kebanyakan, coba kata yang lebih spesifik'**
  String get bookTooManyResultsTryAMore;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nyiapin pencarian…'**
  String get bookPreparingSearch;

  /// Interface copy in ui/features/reader/views/book_search_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cuma sekali buat buku ini. Abis ini nyarinya langsung kilat.'**
  String get bookJustOnceForThisBookSearches;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Obrolan belum bisa dibuka. Coba buka ulang bukunya.'**
  String get readerCouldnTOpenTheChatTry;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke posisi tadi?'**
  String get readerBackToYourPreviousPosition;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik'**
  String get readerGoBack;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sumber ini udah gak tersedia.'**
  String get readerThisSourceIsNoLongerAvailable;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngintip · belum ada progres baca'**
  String get readerPreviewingNoReadingProgressYet;

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngintip · progres masih {p0} · Paragraf {p1}'**
  String readerPreviewingSavedPositionParagraph(Object p0, Object p1);

  /// Interface copy in ui/features/reader/views/reader_view.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, bukunya gagal kebuka'**
  String get readerCouldnTOpenTheBook;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Udah disalin, tinggal paste'**
  String get meaningCopiedReadyToPaste;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'timeout · 30 detik'**
  String get meaningTimeoutSeconds;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'offline / gak nyambung'**
  String get meaningOfflineDisconnected;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'HTTP {p0} · key ditolak'**
  String meaningHttpKeyRejected(Object p0);

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'HTTP 402 · saldo abis'**
  String get meaningHttpNoCredit;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'jawaban AI gak valid'**
  String get meaningInvalidAiResponse;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artinya udah lengkap'**
  String get meaningTranslationAndMeaningComplete;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artinya, lagi ditulis'**
  String get meaningWritingTranslationAndMeaning;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bentar, lagi mikir...'**
  String get meaningHangOnThinking;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artinya gini nih'**
  String get meaningHereSWhatItMeans;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Batalin'**
  String get meaningCancel;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Terjemahan'**
  String get meaningTranslation;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Maksud penulisnya tuh...'**
  String get meaningWhatTheAuthorMeans;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Disalin'**
  String get meaningCopied;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tanyain ini'**
  String get meaningAskAboutThis;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi mikir'**
  String get meaningThinking;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nulis'**
  String get meaningWriting;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut'**
  String get meaningNext;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Agak lama nih...'**
  String get meaningTakingALittleLonger;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'AI-nya masih mikir. Tungguin bentar lagi, atau coba ulang.'**
  String get meaningTheAiIsStillThinkingGive;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Coba lagi'**
  String get meaningTryAgain;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, kepotong di tengah'**
  String get meaningCutOffHalfway;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksinya putus pas lagi nulis. Yang udah masuk tetep di sini.'**
  String get meaningTheConnectionDroppedWhileWritingWhat;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal ngambil artinya'**
  String get meaningCouldnTGetTheMeaning;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal nih'**
  String get meaningSomethingWentWrong;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Kayaknya koneksi lagi ngadat, atau AI-nya lagi sibuk. Tinggal coba lagi aja.'**
  String get meaningTheConnectionMightBeDownOr;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nanti aja'**
  String get meaningMaybeLater;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Isi API key dulu yuk'**
  String get meaningAddYourApiKeyFirst;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artinya dibikin AI lewat OpenRouter. Tempel API key lo sekali aja di Pengaturan, abis itu tinggal tap-tap paragraf.'**
  String get meaningTranslationsAndMeaningsUseAiThrough;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Belum punya? Bikin dulu di '**
  String get meaningDonTHaveOneCreateIt;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Buka Pengaturan'**
  String get meaningOpenSettings;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Buka bedahan'**
  String get meaningOpenBreakdown;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Masih bingung? Bedahin'**
  String get meaningStillPuzzledBreakItDown;

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Udah pernah dibedah · {p0}'**
  String meaningPreviouslyBrokenDown(Object p0);

  /// Interface copy in ui/features/reader/views/meaning_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Per bagian, plus tokoh & istilah'**
  String get meaningSectionBySectionPlusPeopleTerms;

  /// Interface copy in ui/features/reader/views/chapter_text.dart
  ///
  /// In id, this message translates to:
  /// **'Sumber hilang'**
  String get chapterSourceMissing;

  /// Interface copy in ui/features/reader/views/chapter_text.dart
  ///
  /// In id, this message translates to:
  /// **'Grup paragraf yang lagi dibuka'**
  String get chapterCurrentlyOpenParagraphGroup;

  /// Interface copy in ui/features/reader/views/chapter_text.dart
  ///
  /// In id, this message translates to:
  /// **'Pemisah adegan'**
  String get chapterSceneBreak;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Menu baca'**
  String get readerReadingMenu;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke rak'**
  String get readerBackToShelf;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Daftar isi'**
  String get readerContents;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Aksi lain'**
  String get readerMoreActions;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Ngobrolin buku'**
  String get readerBookChat;

  /// Interface copy in ui/features/reader/views/reader_capsule.dart
  ///
  /// In id, this message translates to:
  /// **'Progres buku'**
  String get readerBookProgress;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bukunya '**
  String get bookBook;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'kelar!'**
  String get bookFinished2;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} udah lo libas sampe kalimat terakhir. Keren sih.'**
  String bookYouReadRightToTheLast(Object p0);

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'waktu baca'**
  String get bookReadingTime;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'paragraf diartiin'**
  String get bookParagraphsTranslated;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke rak, cari buku lain'**
  String get bookBackToShelfFindAnotherBook;

  /// Interface copy in ui/features/reader/views/book_end_view.dart
  ///
  /// In id, this message translates to:
  /// **'Baca ulang dari awal'**
  String get bookReadAgainFromTheStart;

  /// Interface copy in ui/features/reader/views/chapter_heading.dart
  ///
  /// In id, this message translates to:
  /// **'Bab {p0} dari {p1} · ±{p2} mnt'**
  String chapterChapterOfMin(Object p0, Object p1, Object p2);

  /// Interface copy in ui/features/reader/views/toc_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} · {p1} bab · {p2}% kebaca'**
  String tocChaptersRead(Object p0, int p1, Object p2);

  /// Interface copy in ui/features/reader/views/toc_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi dibaca · ±{p0} mnt'**
  String tocCurrentlyReadingMin(Object p0);

  /// Interface copy in ui/features/reader/views/toc_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'±{p0} mnt'**
  String tocMin(Object p0);

  /// Interface copy in ui/features/reader/views/reader_overlay.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} kelar'**
  String readerFinished(Object p0);

  /// Interface copy in ui/features/reader/views/reader_overlay.dart
  ///
  /// In id, this message translates to:
  /// **'±{p0} mnt lagi'**
  String readerMinLeft(Object p0);

  /// Interface copy in ui/features/reader/views/reader_overlays.dart
  ///
  /// In id, this message translates to:
  /// **'Ngobrol soal bukunya'**
  String get readerChatAboutTheBook;

  /// Interface copy in ui/features/reader/views/reader_overlays.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke ngobrol'**
  String get readerBackToChat;

  /// Interface copy in ui/features/reader/views/reader_overlays.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut baca'**
  String get readerKeepReading;

  /// Interface copy in ui/features/reader/views/read_mark.dart
  ///
  /// In id, this message translates to:
  /// **'Terakhir lo baca di sini'**
  String get readYouLastReadHere;

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Bab selesai'**
  String get chapterChapterFinished;

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} paragraf diterjemahin'**
  String chapterParagraphsTranslated(int p0);

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Itu tadi bab terakhir!'**
  String get chapterThatWasTheLastChapter;

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut ke {p0}?'**
  String chapterContinueTo(Object p0);

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Bukunya kelar, tinggal satu tap lagi'**
  String get chapterOneMoreTapToFinishThe;

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut, gas'**
  String get chapterLetSKeepGoing;

  /// Interface copy in ui/features/reader/views/chapter_end.dart
  ///
  /// In id, this message translates to:
  /// **'Udahan dulu, balik ke rak'**
  String get chapterStopHereBackToShelf;

  /// Interface copy in ui/features/reader/views/reader_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Cari kata'**
  String get readerSearchWords;

  /// Interface copy in ui/features/reader/views/reader_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Lihat hasil “{p0}”'**
  String readerViewResultsFor(Object p0);

  /// Interface copy in ui/features/reader/views/reader_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Atur tampilan'**
  String get readerReadingAppearance;

  /// Interface copy in ui/features/reader/views/reader_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Ukuran, font, tema'**
  String get readerSizeFontTheme;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Atur bacaan lo'**
  String get aaMakeItYours;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ukuran huruf'**
  String get aaTextSize;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Font'**
  String get aaFont;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Jelas'**
  String get aaClear;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Kayak buku'**
  String get aaBookLike;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bawaan sistem'**
  String get aaSystemDefault;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Jarak baris'**
  String get aaLineSpacing;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Rapat'**
  String get aaTight;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Pas'**
  String get aaBalanced;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lega'**
  String get aaRoomy;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Margin'**
  String get aaMargins;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Sempit'**
  String get aaNarrow;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tema'**
  String get aaTheme;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Terang'**
  String get aaLight;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Gelap'**
  String get aaDark;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ikut sistem'**
  String get aaSystem;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tampilan layar'**
  String get aaScreenDisplay;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Sembunyiin jam & baterai'**
  String get aaHideClockBattery;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Status bar ngumpet bareng menu pas lagi baca'**
  String get aaHideTheStatusBarWithThe;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tampilin garis progres'**
  String get aaShowProgressLine;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Garis tipis di bawah layar pas menu ngumpet'**
  String get aaAThinLineAtTheBottom;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Kecilin huruf'**
  String get aaSmallerText;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Gedein huruf'**
  String get aaLargerText;

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Font {p0}'**
  String aaFont2(Object p0);

  /// Interface copy in ui/features/reader/views/aa_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Tema {p0}'**
  String aaTheme2(Object p0);

  /// Interface copy in ui/features/settings/views/backup_listener.dart
  ///
  /// In id, this message translates to:
  /// **'Backup kelar, aman!'**
  String get backupBackupCompleteAllSafe;

  /// Interface copy in ui/features/settings/views/backup_listener.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, backup gagal'**
  String get backupBackupFailed;

  /// Interface copy in ui/features/settings/views/backup_listener.dart
  ///
  /// In id, this message translates to:
  /// **'Coba lagi bentar ya'**
  String get backupTryAgainInAMoment;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sip, data lo udah balik!'**
  String get settingsYourDataIsBack;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} buku · {p1} terjemahan'**
  String settingsBooksTranslations(int p0, int p1);

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'API key gak ikut backup, isi ulang dulu biar bisa nerjemahin.'**
  String get settingsApiKeysArenTIncludedIn;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Isi key'**
  String get settingsAddKey;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus cache terjemahan?'**
  String get settingsDeleteTranslationCache;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Semua terjemahan yang udah kesimpen bakal ilang. Paragraf yang dibuka lagi manggil AI ulang dan motong saldo lagi. Obrolan buku lo tetap kesimpen.'**
  String get settingsAllSavedTranslationsWillBeDeleted;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Katalognya udah yang terbaru'**
  String get settingsYourCatalogIsAlreadyUpTo;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik'**
  String get settingsBack;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get settingsSettings;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'API key OpenRouter'**
  String get settingsOpenrouterApiKey;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Model AI'**
  String get settingsAiModel;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Biayanya kepotong dari saldo akun OpenRouter lo.'**
  String get settingsChargesComeFromYourOpenrouterAccount;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Backup & pulihin'**
  String get settingsBackupRestore;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Katalog buku'**
  String get settingsBookCatalog;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Daftar ±62.000 buku Project Gutenberg buat nyari judul tanpa internet. Diperbarui mingguan.'**
  String get settingsAroundProjectGutenbergBooksToSearch;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Penyimpanan'**
  String get settingsStorage;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Disimpen aman di perangkat (Keychain / Keystore), gak dikirim ke mana-mana selain OpenRouter.'**
  String get settingsStoredSecurelyOnYourDeviceKeychain;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Itu bukan API key OpenRouter. Key-nya mulai dari sk-or-... dan gak disimpen.'**
  String get settingsThatSNotAnOpenrouterApi;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Key-nya ditolak OpenRouter, jadi gak disimpen. Cek lagi ya.'**
  String get settingsOpenrouterRejectedTheKeySoIt;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bentar, lagi ngecek...'**
  String get settingsHangOnChecking;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Key-nya jalan'**
  String get settingsYourKeyWorks;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Key-nya ditolak OpenRouter'**
  String get settingsOpenrouterRejectedYourKey;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Disimpen aman di perangkat'**
  String get settingsStoredSecurelyOnYourDevice;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Isinya buku, progres baca, terjemahan, sama pengaturan. '**
  String get settingsIncludesBooksReadingProgressTranslationsAnd;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'API key gak ikut'**
  String get settingsApiKeysArenTIncluded;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **', jadi abis pulihin isi ulang ya. Simpen file-nya di iCloud Drive biar gak ikut kehapus pas install ulang.'**
  String get settingsSoAddYoursAgainAfterRestoring;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Barusan'**
  String get settingsJustNow;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Status backup'**
  String get settingsBackupStatus;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Backup terakhir'**
  String get settingsLastBackup;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Belum pernah backup'**
  String get settingsNoBackupsYet;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Data lo cuma ada di HP ini doang'**
  String get settingsYourDataIsOnlyOnThis;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Backup sekarang'**
  String get settingsBackUpNow;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Pulihin dari backup'**
  String get settingsRestoreFromBackup;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Default · paling akurat'**
  String get settingsDefaultMostAccurate;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Cache terjemahan'**
  String get settingsTranslationCache;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} paragraf · {p1}'**
  String settingsParagraphs(int p0, Object p1);

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus cache'**
  String get settingsClearCache;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Belum diunduh · 5,6 MB'**
  String get settingsNotDownloadedMb;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Diperbarui {p0} · '**
  String settingsUpdated(Object p0);

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0}{p1} buku'**
  String settingsBooks(Object p0, int p1);

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ngecek versi terbaru…'**
  String get settingsCheckingForUpdates;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ngunduh…'**
  String get settingsDownloading;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ngunduh {p0}%'**
  String settingsDownloading2(Object p0);

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyusun katalog…'**
  String get settingsPreparingCatalog;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal, katalog lama tetep dipakai'**
  String get settingsFailedKeepingThePreviousCatalog;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Unduh'**
  String get settingsDownload;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Perbarui'**
  String get settingsUpdate;

  /// Interface copy in ui/features/settings/views/settings_view.dart
  ///
  /// In id, this message translates to:
  /// **'Katalog Gutenberg'**
  String get settingsGutenbergCatalog;

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} buku + progres bacanya'**
  String backupBooksReadingProgress(int p0);

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} terjemahan'**
  String backupTranslations(int p0);

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Pengaturan baca & model AI'**
  String get backupReadingSettingsAiModel;

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi backup'**
  String get backupBackingUp;

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngebungkus backup...'**
  String get backupPackingYourBackup;

  /// Interface copy in ui/features/settings/views/backup_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Abis ini muncul menu share. Simpen ke Files / Drive terus taruh di tempat aman biar gak ilang.'**
  String get backupTheShareMenuOpensNextSave;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Pulihin dari backup ini?'**
  String get restoreRestoreThisBackup;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ganti & pulihin'**
  String get restoreReplaceRestore;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'API key lo gak kesentuh.'**
  String get restoreYourApiKeyWonTBe;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Dibikin {p0} · Luma {p1}'**
  String restoreCreatedLuma(Object p0, Object p1);

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'buku di rak'**
  String get restoreBooksOnShelf;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'terjemahan'**
  String get restoreTranslations;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Semua data di HP ini bakal diganti'**
  String get restoreAllDataOnThisPhoneWill;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Buku, progres, sama terjemahan yang ada sekarang ({p0} buku) diganti total sama isi backup. Yang sekarang gak bisa dibalikin.'**
  String restoreYourCurrentBooksProgressAndTranslations(int p0);

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Iya, gua ngerti. Ganti aja semuanya.'**
  String get restoreYesIUnderstandReplaceEverything;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi mulihin'**
  String get restoreRestoring;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi mulihin data lo...'**
  String get restoreRestoringYourData;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Cek file backup'**
  String get restoreCheckBackupFile;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Balikin {p0} buku'**
  String restoreRestoreBooks(int p0);

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Balikin progres & terjemahan'**
  String get restoreRestoreProgressTranslations;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Jangan tutup Luma dulu ya, bentar doang kok.'**
  String get restoreKeepLumaOpenThisWonT;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ini bukan backup Luma'**
  String get restoreThisIsnTALumaBackup;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'File backup Luma itu yang namanya luma-backup-…zip, hasil dari tombol \"Backup sekarang\". Coba cari lagi di file manager ya.'**
  String get restoreLumaBackupFilesAreNamedLuma;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Backup-nya dari Luma yang lebih baru'**
  String get restoreThisBackupIsFromANewer;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'File ini dibikin pake Luma {p0}, sedangkan yang keinstall masih {p1}. Install Luma versi terbaru dulu, baru pulihin.'**
  String restoreThisFileWasCreatedWithLuma(Object p0, Object p1);

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'File backup-nya rusak'**
  String get restoreTheBackupFileIsDamaged;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Isinya gak kebaca, mungkin kepotong pas disimpen. Coba file backup yang lain.'**
  String get restoreCouldnTReadTheFileIt;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal mulihin'**
  String get restoreCouldnTRestore;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ada yang error pas ganti data, semuanya udah dibalikin kayak semula.'**
  String get restoreSomethingWentWrongWhileReplacingData;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal mulihin'**
  String get restoreRestoreFailed;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Pilih file lain'**
  String get restoreChooseAnotherFile;

  /// Interface copy in ui/features/settings/views/restore_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Tenang, data yang sekarang gak diapa-apain.'**
  String get restoreYourCurrentDataHasnTBeen;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi import'**
  String get importImporting;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngebongkar EPUB...'**
  String get importUnpackingEpub;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Baca judul & penulis'**
  String get importReadTitleAuthor;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ambil cover'**
  String get importGetCover;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Mecah per bab & paragraf'**
  String get importSplitIntoChaptersParagraphs;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'ditambah {p0}'**
  String importAdded(Object p0);

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Eh, buku ini udah ada di rak'**
  String get importThisBookIsAlreadyOnYour;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lo pernah import buku yang sama. Mau lanjutin yang lama aja?'**
  String get importYouVeImportedTheSameBook;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Buka yang udah ada'**
  String get importOpenExistingBook;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ganti file-nya'**
  String get importReplaceFile;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ganti file = progres & terjemahan lama tetep aman.'**
  String get importReplacingTheFileKeepsYourProgress;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'File-nya rusak nih'**
  String get importThisFileIsDamaged;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'EPUB-nya gak bisa dibuka, kayaknya korup atau kedownload setengah. Coba download ulang, terus import lagi.'**
  String get importCouldnTOpenThisEpubIt;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} · file rusak'**
  String importDamagedFile(Object p0);

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Ini bukan EPUB'**
  String get importThisIsnTAnEpub;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'App ini cuma bisa baca .epub. Kalau bukunya MOBI, convert dulu ke EPUB (misal pake Calibre), baru import lagi.'**
  String get importThisImporterReadsEpubFilesConvert;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Bukunya dikunci DRM'**
  String get importThisBookIsDrmLocked;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'EPUB ini dikunci sama tokonya, jadi cuma bisa dibaca di app toko itu. Pake file EPUB yang bebas DRM ya.'**
  String get importThisEpubIsLockedToIts;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Judul buku gak boleh kosong'**
  String get importBookTitleCanTBeEmpty;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Harus angka'**
  String get importMustBeANumber;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Masukin'**
  String get importImport;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Masuk ke buku mana?'**
  String get importWhichBookIsThisFor;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Judul buku'**
  String get importBookTitle;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Judul bab'**
  String get importChapterTitle;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Judul bab (opsional)'**
  String get importChapterTitleOptional;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nomor bab'**
  String get importChapterNumber;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bab terakhir di buku ini: {p0}'**
  String importLastChapterInThisBook(Object p0);

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ditebak dari judul di file. Boleh diubah.'**
  String get importGuessedFromTheFileTitleYou;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Buku baru'**
  String get importNewBook;

  /// Interface copy in ui/features/import_book/views/import_markdown_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bikin buku dari file ini'**
  String get importCreateABookFromThisFile;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Cari buku'**
  String get discoverDiscover;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Judul atau nama penulis'**
  String get discoverTitleOrAuthorName;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus kata cari'**
  String get discoverClearSearch;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyiapin katalog buku… {p0}%'**
  String discoverPreparingBookCatalog(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyiapin katalog buku…'**
  String get discoverPreparingBookCatalog2;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Katalog lagi gak bisa dihubungin'**
  String get discoverCanTReachTheCatalog;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bukan salah lo kok. Coba lagi bentar lagi ya.'**
  String get discoverItSNotYourFaultGive;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sekali aja, abis itu nyari jalan tanpa internet.'**
  String get discoverJustOnceThenSearchWorksOffline;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lo lagi offline'**
  String get discoverYouReOffline;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyari tetep jalan. Tapi daftar rame, detail buku, sama unduhan butuh internet. Buku di rak tetap bisa lo baca kok.'**
  String get discoverSearchStillWorksPopularBooksDetails;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Buka rak'**
  String get discoverOpenShelf;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'LAGI RAME'**
  String get discoverPopularNow;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Katalognya lagi lemot nih'**
  String get discoverTheCatalogIsTakingAWhile;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Udah 5 detik lebih. Tungguin bentar, atau coba lagi.'**
  String get discoverItSBeenOverSecondsGive;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'COBA CARI'**
  String get discoverTrySearching;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'#1 lagi rame, {p0}'**
  String discoverPopular(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'#1 lagi rame'**
  String get discoverPopular2;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gak nemu “{p0}”'**
  String discoverNoMatchesFor(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Pencarian cuma nyocokin judul sama nama penulis. Cek ejaannya, atau coba kata yang lebih pendek.'**
  String get discoverSearchMatchesTitlesAndAuthorNames;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'HASIL BUAT “{p0}”'**
  String discoverResultsFor(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} hasil · urut paling cocok'**
  String discoverResultsBestMatchFirst(int p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal ngambil. Coba lagi'**
  String get discoverCouldnTLoadTryAgain;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ngambil {p0} lagi…'**
  String discoverLoadingMore(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Paling cocok, {p0}'**
  String discoverBestMatch(Object p0);

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Paling cocok'**
  String get discoverBestMatch2;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Udah di rak'**
  String get discoverOnYourShelf;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Antri'**
  String get discoverQueued;

  /// Interface copy in ui/features/discover/views/discover_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi diunduh · {p0}%'**
  String discoverDownloading(Object p0);

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Ngunduh {p0} buku · {p1}%'**
  String downloadDownloadingBooks(int p0, Object p1);

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Status unduhan, {p0}'**
  String downloadDownloadStatus(Object p0);

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Unduhan'**
  String get downloadDownloads;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Jalan terus walau lo pindah layar'**
  String get downloadKeepsGoingWhileYouBrowse;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Gak ada yang lagi diunduh.'**
  String get downloadNoActiveDownloads;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Unduhan {p0} dibatalin'**
  String downloadCanceledDownloadOf(Object p0);

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Antri, abis {p0}'**
  String downloadQueuedAfter(Object p0);

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus dari antrian'**
  String get downloadRemoveFromQueue;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Nyusun buku…'**
  String get downloadPreparingBook;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Udah masuk rak'**
  String get downloadAddedToShelf;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Udah ada di rak'**
  String get downloadAlreadyOnShelf;

  /// Interface copy in ui/features/discover/views/download_chip.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal, koneksinya putus'**
  String get downloadFailedConnectionLost;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Masuk Gutenberg'**
  String get bookAddedToGutenberg;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ukuran'**
  String get bookSize;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Inggris'**
  String get bookEnglish;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bahasa'**
  String get bookLanguage;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sinopsis'**
  String get bookSynopsis;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Belum ada sinopsis buat buku ini. Langsung buka bab 1 aja.'**
  String get bookNoSynopsisForThisBookYet;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Baca selengkapnya'**
  String get bookReadMore;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tentang'**
  String get bookAbout;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Masuk daftar'**
  String get bookListedIn;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Penulis'**
  String get bookAuthor;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Info file'**
  String get bookFileInfo;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Format'**
  String get bookFormat;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hak cipta'**
  String get bookCopyright;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Public domain di AS'**
  String get bookPublicDomainInTheUs;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'ID katalog'**
  String get bookCatalogId;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Detail buku'**
  String get bookBookDetails;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} buku lain di katalog'**
  String bookOtherBooksInTheCatalog(int p0);

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Cari buku lain {p0}'**
  String bookFindMoreBooksBy(Object p0);

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal ngunduh, koneksinya putus.'**
  String get bookDownloadFailedConnectionLost;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Baca sekarang'**
  String get bookReadNow;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut baca · {p0}%'**
  String bookContinueReading(Object p0);

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Udah ada di rak lo, gak perlu diunduh lagi'**
  String get bookAlreadyOnYourShelfNoNeed;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Antri…'**
  String get bookQueued;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi diunduh…'**
  String get bookDownloading;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Boleh ditinggal, nanti gua kabarin pas udah masuk rak.'**
  String get bookFeelFreeToBrowseILl;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ambil buku'**
  String get bookGetBook;

  /// Interface copy in ui/features/discover/views/book_detail_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gratis, langsung masuk Rak buku lo'**
  String get bookFreeStraightToYourShelf;

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} udah masuk rak'**
  String downloadAddedToShelf2(Object p0);

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} udah ada di rak'**
  String downloadIsAlreadyOnYourShelf(Object p0);

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal ngunduh {p0}'**
  String downloadCouldnTDownload(Object p0);

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'Tap buat mulai baca'**
  String get downloadTapToStartReading;

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'Buka'**
  String get downloadOpen;

  /// Interface copy in ui/features/discover/views/download_toasts.dart
  ///
  /// In id, this message translates to:
  /// **'Baca'**
  String get downloadRead;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Buku ini'**
  String get chatThisBook;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'buku ini'**
  String get chatThisBook2;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Riwayatnya gak kebuka.'**
  String get chatCouldnTOpenHistory;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Obrolan lo aman kok. Coba muat ulang bentar lagi.'**
  String get chatYourChatsAreSafeTryReloading;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Muat ulang'**
  String get chatReload;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Belum ada obrolan.'**
  String get chatNoChatsYet;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Obrolan yang lo mulai bakal muncul di sini, dipisah per sesi.'**
  String get chatYourChatsWillAppearHereOrganized;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Kembali ke obrolan'**
  String get chatBackToChat;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Riwayat obrolan'**
  String get chatChatHistory;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Obrolan baru'**
  String get chatNewChat;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Diperbarui {p0}'**
  String chatUpdated(Object p0);

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi dibuka'**
  String get chatOpenNow;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Arsip'**
  String get chatArchived;

  /// Interface copy in ui/features/chat/views/chat_sessions_view.dart
  ///
  /// In id, this message translates to:
  /// **'Menu {p0}'**
  String chatMenuFor(Object p0);

  /// Interface copy in ui/features/chat/views/chat_source_visit_view.dart
  ///
  /// In id, this message translates to:
  /// **'Posisi baca pindah ke kutipan ini.'**
  String get chatReadingPositionMovedToThisQuote;

  /// Interface copy in ui/features/chat/views/chat_source_visit_view.dart
  ///
  /// In id, this message translates to:
  /// **'Posisi baca belum dipindah. Coba lagi.'**
  String get chatReadingPositionHasnTMovedTry;

  /// Interface copy in ui/features/chat/views/chat_source_visit_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sumber ini udah gak tersedia. Posisi baca lo tetap aman.'**
  String get chatThisSourceIsNoLongerAvailable;

  /// Interface copy in ui/features/chat/views/chat_composer.dart
  ///
  /// In id, this message translates to:
  /// **'Tanyain isi buku ini…'**
  String get chatAskAboutThisBook;

  /// Interface copy in ui/features/chat/views/chat_composer.dart
  ///
  /// In id, this message translates to:
  /// **'Hentikan jawaban'**
  String get chatStopResponse;

  /// Interface copy in ui/features/chat/views/chat_composer.dart
  ///
  /// In id, this message translates to:
  /// **'Kirim pertanyaan'**
  String get chatSendQuestion;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Ubah judul'**
  String get chatRename;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Gak bisa buat obrolan arsip'**
  String get chatUnavailableForArchivedChats;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus obrolan'**
  String get chatDeleteChat;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus obrolan ini?'**
  String get chatDeleteThisChat;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'“{p0}” bakal dihapus permanen. Bukunya, progres baca, dan obrolan lain gak ikut kehapus.'**
  String chatWillBePermanentlyDeletedYourBook(Object p0);

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Judul belum tersimpan. Coba lagi.'**
  String get chatCouldnTSaveTheTitleTry;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Simpan'**
  String get chatSave;

  /// Interface copy in ui/features/chat/views/chat_session_menu.dart
  ///
  /// In id, this message translates to:
  /// **'Judul obrolan'**
  String get chatChatTitle;

  /// Interface copy in ui/features/chat/views/chat_context_card.dart
  ///
  /// In id, this message translates to:
  /// **'Fitur ini masih dalam pengembangan. Jawaban AI bisa keliru, jadi cek sumbernya lewat angka sitasi.'**
  String get chatThisFeatureIsStillInDevelopment;

  /// Interface copy in ui/features/chat/views/chat_context_card.dart
  ///
  /// In id, this message translates to:
  /// **'bagian {p0}'**
  String chatParagraph(Object p0);

  /// Interface copy in ui/features/chat/views/chat_context_card.dart
  ///
  /// In id, this message translates to:
  /// **'Baca di buku'**
  String get chatReadInBook;

  /// Interface copy in ui/features/chat/views/chat_context_card.dart
  ///
  /// In id, this message translates to:
  /// **'Ciutkan konteks'**
  String get chatCollapseContext;

  /// Interface copy in ui/features/chat/views/chat_context_card.dart
  ///
  /// In id, this message translates to:
  /// **'Perluas konteks'**
  String get chatExpandContext;

  /// Interface copy in ui/features/chat/views/chat_history.dart
  ///
  /// In id, this message translates to:
  /// **'CATATAN SEMENTARA'**
  String get chatDraftNotes;

  /// Interface copy in ui/features/chat/views/chat_history.dart
  ///
  /// In id, this message translates to:
  /// **'{p0}, paragraf {p1}'**
  String chatParagraph2(Object p0, Object p1);

  /// Interface copy in ui/features/chat/views/chat_history.dart
  ///
  /// In id, this message translates to:
  /// **'Ke terbaru'**
  String get chatJumpToLatest;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik baca'**
  String get chatBackToReading;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Arsip · cuma bisa dibaca'**
  String get chatArchivedReadOnly;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Riwayat ini gak bisa dilanjutkan.'**
  String get chatThisHistoryCanTBeContinued;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tanya soal buku ini…'**
  String get chatAskAboutThisBook2;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tanya soal kutipan ini…'**
  String get chatAskAboutThisQuote;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan'**
  String get chatContinue;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Mau ngobrolin apa soal bukunya?'**
  String get chatWhatWouldYouLikeToDiscuss;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Buku ini gak tersedia.'**
  String get chatThisBookIsUnavailable;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Mau tanya apa soal kutipan ini?'**
  String get chatWhatWouldYouLikeToAsk;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tulis pertanyaan lo di bawah. Kutipan sama terjemahannya ikut kebaca sebagai konteks.'**
  String get chatWriteYourQuestionBelowTheQuote;

  /// Interface copy in ui/features/chat/views/chat_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tanya apa aja soal {p0}. Jawabannya selalu ada sitasi ke bagian bukunya.'**
  String chatAskAnythingAboutAnswersIncludeCitations(Object p0);

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} · {p1}'**
  String chat(Object p0, Object p1);

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bukunya udah berubah'**
  String get chatTheBookHasChanged;

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Buka di buku'**
  String get chatOpenInBook;

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngecek lokasi kutipan…'**
  String get chatCheckingQuoteLocation;

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cek teks aslinya tanpa mengubah posisi baca lo.'**
  String get chatCheckTheOriginalTextWithoutChanging;

  /// Interface copy in ui/features/chat/views/chat_source_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Sumber ini udah gak tersedia atau jawabannya belum lolos pengecekan. Kutipan lama tetap bisa lo baca.'**
  String get chatThisSourceIsNoLongerAvailable2;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Bentar, lagi siapin obrolan…'**
  String get chatHangOnPreparingTheChat;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nyari sumber di buku…'**
  String get chatLookingForSourcesInTheBook;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Bentar, lagi mikir…'**
  String get chatHangOnThinking;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nulis…'**
  String get chatWriting;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Agak lama nih, masih diproses…'**
  String get chatTakingAWhileStillWorking;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Jawaban selesai'**
  String get chatResponseComplete;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Jawabannya keputus.'**
  String get chatTheResponseWasCutOff;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Dihentiin.'**
  String get chatStopped;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Obrolan sempat terputus'**
  String get chatTheChatWasInterrupted;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke Terjemahin'**
  String get chatBackToTranslation;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Kembali'**
  String get chatBack;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'API key belum diisi. Isi dulu di Pengaturan, lalu kirim lagi.'**
  String get chatNoApiKeyYetAddIt;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksi lagi putus. Cek internet lo, lalu coba lagi.'**
  String get chatConnectionLostCheckYourInternetAnd;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Kelamaan nunggu jawaban. Lo bisa coba lagi.'**
  String get chatTheResponseTookTooLongYou;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Jawabannya belum lolos pengecekan. Coba lagi, yuk.'**
  String get chatTheResponseHasnTPassedValidation;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'API key ditolak. Periksa key lo di Pengaturan.'**
  String get chatApiKeyRejectedCheckYourKey;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Saldo OpenRouter habis. Cek akun lo, lalu coba lagi.'**
  String get chatYourOpenrouterCreditHasRunOut;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi kena batas request. Tunggu sebentar, lalu coba lagi.'**
  String get chatRateLimitReachedWaitAMoment;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Layanan AI lagi bermasalah. Coba lagi nanti.'**
  String get chatTheAiServiceIsHavingTrouble;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Hari ini'**
  String get chatToday;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Kemarin'**
  String get chatYesterday;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'7 hari terakhir'**
  String get chatLastDays;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lebih lama'**
  String get chatOlder;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi meriksa isi buku…'**
  String get chatCheckingTheBook;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi baca {p0}…'**
  String chatReading(Object p0);

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} {p1}/{p2} potongan'**
  String chatChunks(Object p0, Object p1, Object p2);

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nyiapin buku… {p0}/{p1} potongan'**
  String chatPreparingTheBookChunks(Object p0, Object p1);

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nyusun rencana'**
  String get chatPlanning;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ambil catatan tersimpan'**
  String get chatLoadingSavedNotes;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi nulis jawaban'**
  String get chatWritingTheResponse;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi {p0}{p1}'**
  String chatWorking(Object p0, Object p1);

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Draf ini belum lolos pengecekan jawaban.'**
  String get chatThisDraftHasnTPassedResponse;

  /// Interface copy in ui/features/chat/views/chat_copy.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi benerin format jawaban… ({p0}/{p1})'**
  String chatFixingTheResponseFormat(Object p0, Object p1);

  /// Interface copy in ui/features/chat/views/chat_answer_blocks.dart
  ///
  /// In id, this message translates to:
  /// **'Tafsiran'**
  String get chatInterpretation;

  /// Interface copy in ui/features/chat/views/chat_answer_blocks.dart
  ///
  /// In id, this message translates to:
  /// **'Di luar buku'**
  String get chatOutsideTheBook;

  /// Interface copy in ui/features/chat/views/chat_steps_row.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} langkah selesai'**
  String chatStepsCompleted(int p0);

  /// Interface copy in ui/features/chat/views/chat_steps_row.dart
  ///
  /// In id, this message translates to:
  /// **'Langkah {p0}'**
  String chatSteps(Object p0);

  /// Interface copy in ui/features/chat/views/chat_steps_row.dart
  ///
  /// In id, this message translates to:
  /// **'lihat {p0} lagi'**
  String chatShowMore(Object p0);

  /// Interface copy in ui/features/chat/views/chat_steps_row.dart
  ///
  /// In id, this message translates to:
  /// **'Jawab sekarang'**
  String get chatAnswerNow;

  /// Interface copy in ui/features/chat/views/chat_steps_row.dart
  ///
  /// In id, this message translates to:
  /// **'Pakai {p0} catatan yang udah masuk, sisa buku gak dibaca.'**
  String chatUseTheNotesReceivedSoFar(int p0);

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} · grup berikutnya'**
  String peekNextGroup(Object p0);

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nyambung ke · awal {p0}'**
  String peekConnectsToStartOf(Object p0);

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artiin'**
  String get peekTranslate;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Coba artiin lagi'**
  String get peekTryTranslatingAgain;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Bedahin ini juga'**
  String get peekBreakThisDownToo;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Yang udah masuk tetep di sini, tapi gak disimpen.'**
  String get peekWhatCameThroughIsStillHere;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Artiin butuh API key OpenRouter.'**
  String get peekTranslationNeedsAnOpenrouterApiKey;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'API key-nya ditolak'**
  String get peekApiKeyRejected;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'OpenRouter gak nerima key lo. Cek lagi di Pengaturan.'**
  String get peekOpenrouterRejectedYourKeyCheckIt;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Saldo OpenRouter abis'**
  String get peekOpenrouterCreditRanOut;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Isi saldo dulu di openrouter.ai, abis itu coba lagi.'**
  String get peekTopUpAtOpenrouterAiThen;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal ngartiin'**
  String get peekCouldnTTranslate;

  /// Interface copy in ui/features/breakdown/views/peek_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksi lagi ngadat. Teks aslinya tetep bisa dibaca.'**
  String get peekTheConnectionIsHavingTroubleYou;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Kutipannya belum bisa dibawa. Coba buka ulang bukunya.'**
  String get breakdownCouldnTBringTheQuoteOver;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bedahan udah lengkap, {p0}'**
  String breakdownBreakdownComplete(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Istilah'**
  String get breakdownTerms;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Praktek'**
  String get breakdownPractice;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bedahin'**
  String get breakdownBreakdown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Kepotong di tengah'**
  String get breakdownCutOffHalfway;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngebedah...'**
  String get breakdownBreakingItDown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Udah dibedah nih'**
  String get breakdownHereSTheBreakdown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} bagian masuk'**
  String breakdownSectionsReceived(int p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngebedah, tunggu ya'**
  String get breakdownBreakingItDownHangOn;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bedahin, {p0} {p1}'**
  String breakdownBreakdown2(Object p0, Object p1);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'udah lengkap'**
  String get breakdownComplete;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Batalin, balik ke Artinya'**
  String get breakdownCancelBackToTranslation;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Balik ke Artinya'**
  String get breakdownBackToTranslation;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Artinya udah kesimpen, tapi Bedahin butuh AI lewat OpenRouter. API key lo udah gak ada di Pengaturan, tempel lagi sekali aja.'**
  String get breakdownYourTranslationIsSavedButBreakdown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'1 gagasan'**
  String get breakdownIdea;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} bagian'**
  String breakdownSections(int p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal ngebedah'**
  String get breakdownCouldnTBreakItDown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi offline nih'**
  String get breakdownYouReOffline;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bedahin butuh internet. Nyalain dulu, abis itu coba lagi. Bedahan yang udah kesimpen tetep bisa dibuka.'**
  String get breakdownBreakdownNeedsInternetConnectAndTry;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'OpenRouter gak nerima key lo. Cek lagi di Pengaturan, siapa tau kepotong pas ditempel.'**
  String get breakdownOpenrouterRejectedYourKeyCheckIt;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} · key ditolak'**
  String breakdownKeyRejected(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Isi saldo dulu di openrouter.ai, abis itu balik ke sini dan coba lagi.'**
  String get breakdownTopUpAtOpenrouterAiThen;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'402 · saldo abis'**
  String get breakdownNoCredit;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Jawabannya berantakan'**
  String get breakdownTheResponseFormatIsInvalid;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'AI-nya ngasih jawaban yang gak bisa dibaca Luma. Coba sekali lagi, biasanya beres.'**
  String get breakdownTheAiReturnedSomethingLumaCan;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'format gak valid'**
  String get breakdownInvalidFormat;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bagian {p0}'**
  String breakdownSection(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Teks terjemahan'**
  String get breakdownTranslatedText;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Teks terjemahan, {p0} bagian'**
  String breakdownTranslatedTextSections(int p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lipet teks terjemahan'**
  String get breakdownCollapseTranslatedText;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Teks yang dibedah'**
  String get breakdownTextBeingExplained;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bagian {p0} dari {p1}, {p2}'**
  String breakdownSectionOf(Object p0, Object p1, Object p2);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'MAKSUDNYA'**
  String get breakdownMeaning;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'LOGIKANYA'**
  String get breakdownLogic;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **' · bagian {p0}'**
  String breakdownSection2(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'NYAMBUNG KE'**
  String get breakdownConnectsTo;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Praktekinnya gini'**
  String get breakdownPuttingItIntoPractice;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjutan'**
  String get breakdownContinuation;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjutan {p0}'**
  String breakdownContinuationOf(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bab {p0}'**
  String breakdownChapter(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyambung ke {p0}, {p1}'**
  String breakdownConnectsTo2(Object p0, Object p1);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nyambung ke {p0}, {p1}. Ketuk dua kali buat ngintip.'**
  String breakdownConnectsToDoubleTapToPreview(Object p0, Object p1);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'AI-nya lagi rame. Tungguin bentar, atau coba minta ulang.'**
  String get breakdownTheAiIsBusyGiveIt;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksinya putus pas lagi ngebedah.'**
  String get breakdownTheConnectionDroppedDuringTheBreakdown;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksinya putus pas lagi ngebedah. Bagian 1 tetep di sini.'**
  String get breakdownTheConnectionDroppedDuringTheBreakdown2;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Koneksinya putus pas lagi ngebedah. Bagian 1–{p0} tetep di sini.'**
  String breakdownTheConnectionDroppedDuringTheBreakdown3(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Coba lagi dari awal'**
  String get breakdownTryAgainFromTheStart;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sorot \"{p0}\" di teks'**
  String breakdownHighlightInTheText(Object p0);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Buka teks terjemahan'**
  String get breakdownOpenTranslatedText;

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lompat ke bagian {p0} dari {p1}'**
  String breakdownJumpToSectionOf(Object p0, Object p1);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Lompat ke {p0}'**
  String breakdownJumpTo(Object p0);

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Sip, judul & penulisnya udah diganti'**
  String get bookTitleAuthorUpdated;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal nyimpen'**
  String get bookCouldnTSave;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ubah judul & penulis'**
  String get bookEditTitleAuthor;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Preview cover'**
  String get bookCoverPreview;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cover asli EPUB'**
  String get bookOriginalEpubCover;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cover default'**
  String get bookDefaultCover;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Judul'**
  String get bookTitle;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Penulis (opsional)'**
  String get bookAuthorOptional;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nama penulis'**
  String get bookAuthorName;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cover asli tetep disimpen, bisa dinyalain lagi kapan aja.'**
  String get bookYourOriginalCoverIsSavedYou;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Cover ini bawaan file EPUB, jadi gak ikut berubah pas judulnya lo ganti.'**
  String get bookThisCoverComesFromTheEpub;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Pakai cover default'**
  String get bookUseDefaultCover;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Balikin ke aslinya'**
  String get bookRestoreOriginals;

  /// Interface copy in ui/features/bookshelf/views/book_edit_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Dari EPUB: {p0} · {p1}'**
  String bookFromEpub(Object p0, Object p1);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Sip, udah masuk rak!'**
  String get bookshelfAddedToYourShelf;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bab {p0} udah ada'**
  String bookshelfChapterAlreadyExists(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Kalau diganti, terjemahan yang udah kesimpen di bab {p0} yang lama ikut kehapus.'**
  String bookshelfReplacingChapterWillAlsoDeleteIts(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ganti'**
  String get bookshelfReplace;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} masuk rak ✨'**
  String bookshelfAddedToShelf(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bab {p0} masuk ke {p1} ✨'**
  String bookshelfChapterAddedTo(Object p0, Object p1);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Info buku'**
  String get bookshelfBookInfo;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus dari rak'**
  String get bookshelfRemoveFromShelf;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Progres {p0}%'**
  String bookshelfProgress(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} paragraf yang udah diartiin'**
  String bookshelfTranslatedParagraphs(int p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **' sama '**
  String get bookshelfAnd;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Hapus \"{p0}\" dari rak?'**
  String bookshelfRemoveFromYourShelf(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0}File aslinya tetep aman kok.'**
  String bookshelfYourOriginalFileStaysSafe(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Gak jadi'**
  String get bookshelfNeverMind;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, gagal ngehapus bukunya'**
  String get bookshelfCouldnTDeleteTheBook;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Urutin pake'**
  String get bookshelfSortBy;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Yah, rak-nya gagal kebuka'**
  String get bookshelfCouldnTOpenYourShelf;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Udah mentok. {p0} buku di rak lo.'**
  String bookshelfThatSEverythingBooksOnYour(int p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Semua buku'**
  String get bookshelfAllBooks;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Urutan rak: {p0}'**
  String bookshelfShelfOrder(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tampilan grid'**
  String get bookshelfGridView;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tampilan list'**
  String get bookshelfListView;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'KALIMAT PEMBUKA PALING TERKENAL'**
  String get bookshelfAFamousOpeningLine;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ambil {p0}'**
  String bookshelfGet(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ambil'**
  String get bookshelfGet2;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Rak lo masih '**
  String get bookshelfYourShelfIsStill;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'kosong'**
  String get bookshelfEmpty;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ambil buku di atas, atau cari yang lain. Gratis semua.'**
  String get bookshelfGetTheBookAboveOrFind;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Cari buku gratis'**
  String get bookshelfFindFreeBooks;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'atau import EPUB / PDF / Markdown dari Files'**
  String get bookshelfOrImportEpubMarkdownFromFiles;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nanti tap paragraf yang bikin pusing'**
  String get bookshelfTapAParagraphWhenYouGet;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Bingung sama satu kalimat? Bedahin'**
  String get bookshelfPuzzledByASentenceBreakIt;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Dari sheet Artinya, tap Bedahin: kalimatnya dipecah bagian per bagian, dijelasin satu-satu.'**
  String get bookshelfFromTheTranslationSheetTapBreakdown;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Ngobrolin bukunya kapan aja'**
  String get bookshelfChatAboutTheBookAnytime;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'Nanya soal tokoh, alur, atau kenapa gitu: jawabannya ngutip halaman bukunya langsung.'**
  String get bookshelfAskAboutCharactersThePlotOr;

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} lagi diunduh'**
  String bookshelfDownloading(Object p0);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'SAMBIL NUNGGU · {p0} DARI {p1}'**
  String bookshelfWhileYouWaitOf(Object p0, Object p1);

  /// Interface copy in ui/features/bookshelf/views/bookshelf_view.dart
  ///
  /// In id, this message translates to:
  /// **'ARTINYA GINI NIH'**
  String get bookshelfHereSWhatItMeans;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Belum pernah backup nih'**
  String get backupNoBackupsYet;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Data lo cuma ada di HP ini doang. Amanin dulu yuk.'**
  String get backupYourDataIsOnlyOnThis;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Udah 6 hari belum backup nih'**
  String get backupItSBeenDaysSinceYour;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Besok jatah install ulang. Amanin data lo dulu yuk.'**
  String get backupYourReinstallIsDueTomorrowBack;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Udah {p0} hari belum backup nih'**
  String backupItSBeenDaysSinceYour2(int p0);

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Amanin data lo dulu yuk, sebelum keburu install ulang.'**
  String get backupBackUpYourDataBeforeYour;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Pengingat backup'**
  String get backupBackupReminder;

  /// Interface copy in ui/features/bookshelf/views/backup_reminder.dart
  ///
  /// In id, this message translates to:
  /// **'Tutup pengingat'**
  String get backupDismissReminder;

  /// Interface copy in ui/features/bookshelf/views/shelf_header.dart
  ///
  /// In id, this message translates to:
  /// **'Rak buku lo'**
  String get shelfYourBookshelf;

  /// Interface copy in ui/features/bookshelf/views/shelf_header.dart
  ///
  /// In id, this message translates to:
  /// **'Import EPUB'**
  String get shelfImportEpub;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi di'**
  String get bookReadingPosition;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Terakhir dibuka'**
  String get bookLastOpened;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ditambah'**
  String get bookAdded;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Paragraf diartiin'**
  String get bookParagraphsTranslated2;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Ukuran file'**
  String get bookFileSize;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Nama file'**
  String get bookFileName;

  /// Interface copy in ui/features/bookshelf/views/book_info_sheet.dart
  ///
  /// In id, this message translates to:
  /// **'Penulis gak ketemu'**
  String get bookAuthorNotFound;

  /// Interface copy in ui/features/bookshelf/views/continue_card.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut baca {p0}, {p1}'**
  String continueContinueReading(Object p0, Object p1);

  /// Interface copy in ui/features/bookshelf/views/continue_card.dart
  ///
  /// In id, this message translates to:
  /// **'Lanjut baca yuk →'**
  String get continueLetSKeepReading;

  /// Interface copy in ui/features/bookshelf/views/continue_card.dart
  ///
  /// In id, this message translates to:
  /// **'Bab {p0} dari {p1}'**
  String continueChapterOf(Object p0, Object p1);

  /// Interface copy in ui/features/breakdown/views/breakdown_view.dart
  ///
  /// In id, this message translates to:
  /// **'Tokoh & istilah'**
  String get breakdownPeopleTerms;

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'hari ini'**
  String get relativeToday;

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'kemarin'**
  String get relativeYesterday;

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'{count} hari lalu'**
  String relativeDays(int count);

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'{count} minggu lalu'**
  String relativeWeeks(int count);

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'{count} bulan lalu'**
  String relativeMonths(int count);

  /// Calendar-relative time
  ///
  /// In id, this message translates to:
  /// **'{count} tahun lalu'**
  String relativeYears(int count);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Belum mulai'**
  String get notStarted;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Kelar dibaca'**
  String get finishedReading;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Bab {current} dari {total}'**
  String chapterPosition(int current, int total);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Terakhir dibuka'**
  String get sortLastOpened;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Judul (A–Z)'**
  String get sortTitle;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Baru ditambah'**
  String get sortAdded;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Bab {range}'**
  String chapterList(String range);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'bab {range}'**
  String chapterListLower(String range);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Belum ada bab'**
  String get noChapters;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'{count} bab'**
  String chapterCount(int count);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'{range} udah dibaca'**
  String chaptersRead(String range);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'lagi baca bab {number}'**
  String chapterReading(int number);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'tanpa penulis'**
  String get unknownAuthor;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'{details} ikut kehapus. '**
  String deletedProgress(String details);

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Buku ini sudah dihapus.'**
  String get bookDeleted;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Isi buku berubah. Mulai obrolan baru untuk lanjut.'**
  String get bookChanged;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Riwayat sesi ini rusak. Lo bisa hapus sesi ini.'**
  String get chatHistoryDamaged;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Obrolan belum bisa dibuka. Coba buka lagi.'**
  String get chatUnavailable;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Pertanyaan kosong atau terlalu panjang.'**
  String get questionInvalid;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Progres penelusuran sudah tidak cocok. Kirim pertanyaan baru buat mulai ulang.'**
  String get checkpointInvalid;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Unduhan buku'**
  String get notificationChannelName;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'Kabar pas buku yang diunduh udah masuk rak'**
  String get notificationChannelDescription;

  /// UI label rendered from application state
  ///
  /// In id, this message translates to:
  /// **'bagian {number}'**
  String sourceParagraph(int number);

  /// No description provided for @navShelf.
  ///
  /// In id, this message translates to:
  /// **'Rak'**
  String get navShelf;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Filenya kosong nih'**
  String get markdownThisFileIsEmpty;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Gak ada teks bacaan di dalamnya, jadi belum ada yang bisa dimasukin. Cek lagi file-nya, atau pilih file bab yang lain.'**
  String get markdownThereSNoReadingText;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'{p0} · 0 kata'**
  String markdownPWords(Object p0);

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Nomor babnya gak kebaca'**
  String get markdownCouldnTReadTheChapter;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Di bagian atas file ada tulisan nomor bab, tapi bukan angka. Ganti jadi angka, terus coba lagi. Atau pilih file lain.'**
  String get markdownTheChapterNumberAtThe;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'{p0} · nomor bab: “{p1}”'**
  String markdownPChapterNumberP(Object p0, Object p1);

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Nama bukunya gak valid'**
  String get markdownInvalidBookName;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Nama buku di bagian atas file cuma boleh huruf kecil, angka, sama strip. Ganti jadi kayak '**
  String get markdownTheBookNameAtThe;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'{p0} · nama buku: “{p1}”'**
  String markdownPBookNameP(Object p0, Object p1);

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **', atau hapus baris itu biar Luma yang nebak.'**
  String get markdownOrRemoveThatLineAnd;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Filenya gak kebaca'**
  String get markdownCouldnTReadThisFile;

  /// Markdown import error
  ///
  /// In id, this message translates to:
  /// **'Luma gak bisa baca isi file ini. Coba pilih file lain, atau simpan ulang filenya dulu.'**
  String get markdownLumaCanTReadThis;

  /// No description provided for @navSettings.
  ///
  /// In id, this message translates to:
  /// **'Atur'**
  String get navSettings;

  /// No description provided for @editTitleEmpty.
  ///
  /// In id, this message translates to:
  /// **'Judul gak boleh kosong'**
  String get editTitleEmpty;

  /// No description provided for @backToConversation.
  ///
  /// In id, this message translates to:
  /// **'Balik ke obrolan'**
  String get backToConversation;

  /// Reading duration on book completion
  ///
  /// In id, this message translates to:
  /// **'{minutes} mnt'**
  String readingDurationMinutes(int minutes);

  /// Reading duration on book completion
  ///
  /// In id, this message translates to:
  /// **'{hours} jam {minutes} mnt'**
  String readingDurationHours(int hours, int minutes);

  /// No description provided for @chatPartialNote.
  ///
  /// In id, this message translates to:
  /// **'Sebagian pertanyaan belum punya bukti yang cukup di sumber ini.'**
  String get chatPartialNote;

  /// No description provided for @chatNoEvidenceNote.
  ///
  /// In id, this message translates to:
  /// **'Belum ada sumber yang cukup untuk menjawab itu. Coba tunjukkan kutipan atau perjelas pertanyaannya.'**
  String get chatNoEvidenceNote;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Lagi ngebongkar PDF...'**
  String get importUnpackingPdf;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'PDF-nya dikunci password'**
  String get importPdfPasswordTitle;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Luma belum bisa buka PDF yang pake password. Buka kuncinya dulu di app lain, simpen salinannya, terus import lagi.'**
  String get importPdfPasswordBody;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'PDF ini hampir gak ada teksnya'**
  String get importPdfScanTitle;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Kebanyakan halamannya gak punya teks yang bisa dibaca, bisa jadi hasil scan. Buat PDF scan, pakai jalur foto atau Docling buat convert ke Markdown, terus import file .md-nya.'**
  String get importPdfScanBody;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'PDF-nya gak bisa dibuka'**
  String get importPdfDamagedTitle;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Kayaknya rusak atau kedownload setengah. Coba download ulang, terus import lagi.'**
  String get importPdfDamagedBody;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Gak ada teks yang bisa dibaca'**
  String get importPdfEmptyTitle;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'PDF-nya kebuka, tapi gak nemu teks buat dijadiin bab. Kalau isinya gambar doang, pakai jalur foto atau Docling.'**
  String get importPdfEmptyBody;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'File-nya gak kebaca'**
  String get importPdfIoTitle;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'Gagal baca atau nyalin file-nya. Cek ruang penyimpanan, terus coba lagi.'**
  String get importPdfIoBody;

  /// Interface copy in ui/features/import_book/views/import_sheets.dart
  ///
  /// In id, this message translates to:
  /// **'{p0} halaman tanpa teks dilewati'**
  String importPdfSkippedPages(int p0);

  /// No description provided for @authLoginTitle.
  ///
  /// In id, this message translates to:
  /// **'Rak lo, ikut\nke mana aja.'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Satu akun buat semua bacaan lo'**
  String get authLoginSubtitle;

  /// No description provided for @authChapterOne.
  ///
  /// In id, this message translates to:
  /// **'BAB I'**
  String get authChapterOne;

  /// No description provided for @authChapterTwo.
  ///
  /// In id, this message translates to:
  /// **'BAB II'**
  String get authChapterTwo;

  /// No description provided for @authChapterThree.
  ///
  /// In id, this message translates to:
  /// **'BAB III'**
  String get authChapterThree;

  /// No description provided for @authBenefitQuota.
  ///
  /// In id, this message translates to:
  /// **'Kuota AI gratis'**
  String get authBenefitQuota;

  /// No description provided for @authBenefitQuotaNote.
  ///
  /// In id, this message translates to:
  /// **'Artinya, Bedahin, sama Ngobrol'**
  String get authBenefitQuotaNote;

  /// No description provided for @authBenefitBackup.
  ///
  /// In id, this message translates to:
  /// **'Backup ke cloud'**
  String get authBenefitBackup;

  /// No description provided for @authBenefitBackupNote.
  ///
  /// In id, this message translates to:
  /// **'Rak sama catatan lo aman'**
  String get authBenefitBackupNote;

  /// No description provided for @authBenefitSync.
  ///
  /// In id, this message translates to:
  /// **'Sync antar HP'**
  String get authBenefitSync;

  /// No description provided for @authBenefitSyncNote.
  ///
  /// In id, this message translates to:
  /// **'Lanjut di iPhone atau Android'**
  String get authBenefitSyncNote;

  /// No description provided for @authSignInGoogle.
  ///
  /// In id, this message translates to:
  /// **'Masuk pakai Google'**
  String get authSignInGoogle;

  /// No description provided for @authConnectingGoogle.
  ///
  /// In id, this message translates to:
  /// **'Nyambung ke Google…'**
  String get authConnectingGoogle;

  /// No description provided for @authGoogleWillAsk.
  ///
  /// In id, this message translates to:
  /// **'Abis ini Google nanya lo mau pakai akun yang mana.'**
  String get authGoogleWillAsk;

  /// No description provided for @authPrivacyNote.
  ///
  /// In id, this message translates to:
  /// **'Dengan masuk, lo setuju sama {policy} Luma.'**
  String authPrivacyNote(String policy);

  /// No description provided for @authPrivacyPolicy.
  ///
  /// In id, this message translates to:
  /// **'Kebijakan privasi'**
  String get authPrivacyPolicy;

  /// No description provided for @authNetworkTitle.
  ///
  /// In id, this message translates to:
  /// **'Gak bisa nyambung'**
  String get authNetworkTitle;

  /// No description provided for @authNetworkBody.
  ///
  /// In id, this message translates to:
  /// **'Cek internet lo, terus coba lagi.'**
  String get authNetworkBody;

  /// No description provided for @authTryAgain.
  ///
  /// In id, this message translates to:
  /// **'Coba lagi'**
  String get authTryAgain;

  /// No description provided for @authRejectedTitle.
  ///
  /// In id, this message translates to:
  /// **'Login-nya ditolak'**
  String get authRejectedTitle;

  /// No description provided for @authRejectedBody.
  ///
  /// In id, this message translates to:
  /// **'Akun Google ini gak bisa dipakai buat masuk. Coba pakai akun lain.'**
  String get authRejectedBody;

  /// No description provided for @authUseAnotherAccount.
  ///
  /// In id, this message translates to:
  /// **'Pakai akun lain'**
  String get authUseAnotherAccount;

  /// No description provided for @authDevBadge.
  ///
  /// In id, this message translates to:
  /// **'Build developer'**
  String get authDevBadge;

  /// No description provided for @authDevLabel.
  ///
  /// In id, this message translates to:
  /// **'Build dev'**
  String get authDevLabel;

  /// No description provided for @authDevTitle.
  ///
  /// In id, this message translates to:
  /// **'Isi yang kosong.'**
  String get authDevTitle;

  /// No description provided for @authDevEmailLead.
  ///
  /// In id, this message translates to:
  /// **'Email gua'**
  String get authDevEmailLead;

  /// No description provided for @authDevPasswordLead.
  ///
  /// In id, this message translates to:
  /// **'dan kata sandinya'**
  String get authDevPasswordLead;

  /// No description provided for @authDevNote.
  ///
  /// In id, this message translates to:
  /// **'Cuma ada di build developer. Versi rilis cuma pakai Google.'**
  String get authDevNote;

  /// No description provided for @authEmailLabel.
  ///
  /// In id, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In id, this message translates to:
  /// **'Kata sandi'**
  String get authPasswordLabel;

  /// No description provided for @authSignUp.
  ///
  /// In id, this message translates to:
  /// **'Daftar'**
  String get authSignUp;

  /// No description provided for @authSignIn.
  ///
  /// In id, this message translates to:
  /// **'Masuk'**
  String get authSignIn;

  /// No description provided for @authInvalidCredentialsTitle.
  ///
  /// In id, this message translates to:
  /// **'Email atau kata sandinya salah'**
  String get authInvalidCredentialsTitle;

  /// No description provided for @authInvalidCredentialsBody.
  ///
  /// In id, this message translates to:
  /// **'Cek lagi, terus coba masuk lagi.'**
  String get authInvalidCredentialsBody;

  /// No description provided for @authUserExistsTitle.
  ///
  /// In id, this message translates to:
  /// **'Email ini udah terdaftar'**
  String get authUserExistsTitle;

  /// No description provided for @authUserExistsBody.
  ///
  /// In id, this message translates to:
  /// **'Pakai Masuk aja, bukan Daftar.'**
  String get authUserExistsBody;

  /// No description provided for @authPasswordShortTitle.
  ///
  /// In id, this message translates to:
  /// **'Kata sandinya kependekan'**
  String get authPasswordShortTitle;

  /// No description provided for @authPasswordShortBody.
  ///
  /// In id, this message translates to:
  /// **'Minimal 8 karakter.'**
  String get authPasswordShortBody;

  /// No description provided for @authSignedInAs.
  ///
  /// In id, this message translates to:
  /// **'Masuk sebagai'**
  String get authSignedInAs;

  /// No description provided for @authChange.
  ///
  /// In id, this message translates to:
  /// **'Ganti'**
  String get authChange;

  /// No description provided for @authInviteIntro.
  ///
  /// In id, this message translates to:
  /// **'Luma lagi beta, jadi akun baru butuh undangan.'**
  String get authInviteIntro;

  /// No description provided for @authInviteLead.
  ///
  /// In id, this message translates to:
  /// **'Kode undangan gua:'**
  String get authInviteLead;

  /// No description provided for @authInviteHint.
  ///
  /// In id, this message translates to:
  /// **'Huruf besar/kecil gak ngaruh. Strip boleh dilewatin.'**
  String get authInviteHint;

  /// No description provided for @authContinue.
  ///
  /// In id, this message translates to:
  /// **'Lanjut'**
  String get authContinue;

  /// No description provided for @authNoteLabel.
  ///
  /// In id, this message translates to:
  /// **'CATATAN'**
  String get authNoteLabel;

  /// No description provided for @authInviteUsedTitle.
  ///
  /// In id, this message translates to:
  /// **'Kode ini udah dipakai'**
  String get authInviteUsedTitle;

  /// No description provided for @authInviteUsedBody.
  ///
  /// In id, this message translates to:
  /// **'Satu kode buat satu akun. Minta kode baru ke yang ngundang lo.'**
  String get authInviteUsedBody;

  /// No description provided for @authInviteInvalidTitle.
  ///
  /// In id, this message translates to:
  /// **'Kodenya salah'**
  String get authInviteInvalidTitle;

  /// No description provided for @authInviteInvalidBody.
  ///
  /// In id, this message translates to:
  /// **'Cek lagi hurufnya, atau minta kode baru ke yang ngundang lo.'**
  String get authInviteInvalidBody;

  /// No description provided for @settingsAccount.
  ///
  /// In id, this message translates to:
  /// **'Akun'**
  String get settingsAccount;

  /// No description provided for @authExLibris.
  ///
  /// In id, this message translates to:
  /// **'EX LIBRIS'**
  String get authExLibris;

  /// No description provided for @authViaGoogle.
  ///
  /// In id, this message translates to:
  /// **'Masuk lewat Google'**
  String get authViaGoogle;

  /// No description provided for @authViaEmail.
  ///
  /// In id, this message translates to:
  /// **'Masuk lewat email'**
  String get authViaEmail;

  /// No description provided for @authSignOut.
  ///
  /// In id, this message translates to:
  /// **'Keluar'**
  String get authSignOut;

  /// No description provided for @authDeleteAccount.
  ///
  /// In id, this message translates to:
  /// **'Hapus akun'**
  String get authDeleteAccount;

  /// No description provided for @authSignOutTitle.
  ///
  /// In id, this message translates to:
  /// **'Keluar dari akun?'**
  String get authSignOutTitle;

  /// No description provided for @authSignOutBody.
  ///
  /// In id, this message translates to:
  /// **'Buku, progres, sama catatan di HP ini tetap ada. Lo balik ke layar Masuk; backup + sync berhenti dulu.'**
  String get authSignOutBody;

  /// No description provided for @authSwitchTitle.
  ///
  /// In id, this message translates to:
  /// **'Ganti ke akun lain?'**
  String get authSwitchTitle;

  /// No description provided for @authSwitchOwner.
  ///
  /// In id, this message translates to:
  /// **'Isi HP ini punya'**
  String get authSwitchOwner;

  /// No description provided for @authSwitchNew.
  ///
  /// In id, this message translates to:
  /// **'Mau masuk pakai'**
  String get authSwitchNew;

  /// No description provided for @authSwitchBodyLead.
  ///
  /// In id, this message translates to:
  /// **'Biar gak kecampur,'**
  String get authSwitchBodyLead;

  /// No description provided for @authSwitchBodyBold.
  ///
  /// In id, this message translates to:
  /// **'isi HP ini dihapus dulu'**
  String get authSwitchBodyBold;

  /// No description provided for @authSwitchBodyTail.
  ///
  /// In id, this message translates to:
  /// **': buku, progres, catatan. Data akun lama tetap aman di cloud.'**
  String get authSwitchBodyTail;

  /// No description provided for @authSwitchConfirm.
  ///
  /// In id, this message translates to:
  /// **'Hapus isi HP & lanjut'**
  String get authSwitchConfirm;

  /// No description provided for @authSwitchKeep.
  ///
  /// In id, this message translates to:
  /// **'Pakai akun lama aja'**
  String get authSwitchKeep;

  /// No description provided for @authDeleteTitle.
  ///
  /// In id, this message translates to:
  /// **'Hapus akun selamanya?'**
  String get authDeleteTitle;

  /// No description provided for @authDeleteBody.
  ///
  /// In id, this message translates to:
  /// **'Centang semua biar yakin lo ngerti apa yang ilang. Ini gak bisa dibalikin.'**
  String get authDeleteBody;

  /// No description provided for @authDeleteCheckAccount.
  ///
  /// In id, this message translates to:
  /// **'Akun {email} kehapus'**
  String authDeleteCheckAccount(String email);

  /// No description provided for @authDeleteCheckBackup.
  ///
  /// In id, this message translates to:
  /// **'Semua backup di cloud ilang'**
  String get authDeleteCheckBackup;

  /// No description provided for @authDeleteCheckSync.
  ///
  /// In id, this message translates to:
  /// **'Data sync di semua HP lo ilang'**
  String get authDeleteCheckSync;

  /// No description provided for @authDeleteNote.
  ///
  /// In id, this message translates to:
  /// **'Buku di HP ini gak ikut kehapus, tapi gak kebackup lagi.'**
  String get authDeleteNote;

  /// No description provided for @authDeleteConfirm.
  ///
  /// In id, this message translates to:
  /// **'Hapus akun selamanya'**
  String get authDeleteConfirm;

  /// No description provided for @authSessionExpiredTitle.
  ///
  /// In id, this message translates to:
  /// **'Sesi lo habis'**
  String get authSessionExpiredTitle;

  /// No description provided for @authSessionExpiredBody.
  ///
  /// In id, this message translates to:
  /// **'Baca tetap jalan; backup & sync nunggu dulu.'**
  String get authSessionExpiredBody;

  /// No description provided for @authSignInAgain.
  ///
  /// In id, this message translates to:
  /// **'Login lagi'**
  String get authSignInAgain;

  /// No description provided for @authCloseBanner.
  ///
  /// In id, this message translates to:
  /// **'Tutup'**
  String get authCloseBanner;

  /// No description provided for @authToastSignedIn.
  ///
  /// In id, this message translates to:
  /// **'Udah masuk. Halo, {name}!'**
  String authToastSignedIn(String name);

  /// No description provided for @authToastSignedOut.
  ///
  /// In id, this message translates to:
  /// **'Udah keluar. Buku di HP ini tetap ada.'**
  String get authToastSignedOut;

  /// No description provided for @authToastDeleted.
  ///
  /// In id, this message translates to:
  /// **'Akun lo udah dihapus.'**
  String get authToastDeleted;

  /// No description provided for @authToastDeleteFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal hapus akun. Gak ada internet.'**
  String get authToastDeleteFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
