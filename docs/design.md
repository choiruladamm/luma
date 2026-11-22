---
type: reference
purpose: UI rules and behavior for the mobile app (Stabilo); values live in tokens and layout in the boards.
sections: [Sources of truth, Principles, Color, Typography, Layout and shape, Motion, Accessibility, Shared components, Reader interaction, Bedahin, Pengaturan, Ngobrolin buku (book chat), Copy]
---

# Design: Stabilo

The rules and behavior behind Luma's UI. Read this before building or changing a screen.

## Sources of truth

| What | Where | Owns |
|---|---|---|
| Visuals per screen and component | Stabilo boards in Claude Design: https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F (light + dark for every screen) | Layout, composition, spacing as drawn |
| Book chat screens | [design/references/ngobrolin-buku.html](../design/references/ngobrolin-buku.html), flows in `design/luma.pen` | Chat, history, citation, and "Tanyain ini" screens |
| Values | `apps/mobile/lib/ui/core/theme/`: `stabilo_tokens.dart` (`Space`, `Radii`, `Layout`, `Motion`, `Elevation`), `stabilo_theme.dart` (`StabiloColors` via `context.stabilo`, `StabiloType`) | Every color, size, radius, duration, curve, shadow |
| Copy | `apps/mobile/lib/l10n/app_id.arb` (template) and `app_en.arb` | Every user-facing string ([i18n.md](i18n.md)) |
| Rules and behavior | This doc | Principles, roles, states, thresholds, accessibility |

On conflict: tokens win for values, this doc wins for behavior, the board wins for layout. A new value becomes a token first; this doc names tokens, never hex or raw numbers.

## Principles

1. **Text first, UI later.** The reading page is clean; UI appears only when needed (sheets, capsules, a thin progress line).
2. **Yellow = what matters right now.** One yellow (`accent`) button per screen. `highlight` marks only the text the reader is focused on (see [Color](#color)).
3. **Night stays calm.** Dark mode uses warm black, not pure black, and is drawn per board, not inverted.
4. **Nothing jumps.** Chrome (capsules, headers, buttons) overlays content, so showing or hiding it never moves text.
5. **Reading settings follow the reader everywhere.** Any surface that shows book or AI text uses the reader's Aa settings.

## Color

Roles are fields on `StabiloColors` (`context.stabilo`), one light and one dark set. Values: `stabilo_theme.dart`.

- `canvas` page background · `sheet` sheets, cards, capsules · `muted` quiet buttons and tiles · `ink` / `ink2` / `ink3` text by emphasis.
- `accent` + `onAccent`: the primary action and the active tab only.
- `pink` / `pinkSoft` + `onPink`: status that needs attention (cut-off answer, "check this" dot) and destructive buttons.
- `highlight` + `onHighlight`: the text in focus:
  - the open group in the reader (block, `Radii.md`);
  - the active section or tapped term in Bedahin's text panel;
  - Cari kata hits ([book-search.md](book-search.md)): in the search sheet a rounded box (`Radii.xs`); on the reading page a plain `TextSpan` background, the open hit full strength with an underline (`Layout.outline`), other visible hits at 50% alpha;
  - the quote on the shelf's continue-reading card.

  Nothing else uses `highlight`.
- `mark`: the margin line on groups that already have a translation.
- `progressLine` / `progressLineTrack`: the reader's bottom progress line.
- Outlines (`Layout.outline`) only go on objects you can grab or press.

## Typography

| Font | Used for |
|---|---|
| Bricolage Grotesque (`StabiloType`) | UI: titles, labels, buttons, chips, toasts |
| Atkinson Hyperlegible | Reading text, default ("Jelas") |
| Literata | Reading option "Kayak buku" (line height +0.05) |
| System (SF on iOS, Roboto on Android) | Reading option "Bawaan sistem" |

- Fonts ship as assets; never fetched at runtime.
- Reading text everywhere comes from `ReaderTypography` (font, size, line height, margin from Aa; dark mode adds +0.05 line height). It applies to the reader, the Artinya sheet's translation and meaning, Bedahin's text panel, chat answers, chat context cards, and citation sheets.
- UI text (titles, chips, buttons, toasts, error messages, chat bubbles, composer) stays at UI sizes regardless of Aa.

## Layout and shape

- Spacing from `Space`, screen margin `Layout.margin`, radii by role from `Radii` (`xs` inline highlight, `md` cover and group block, `lg` cards, `xl` sheet corners, `full` pills and icon buttons).
- Touch targets are at least `Layout.touch`, even when the visible control is smaller.
- **Edge-to-edge bottom.** Scroll areas aren't wrapped in `SafeArea(bottom: true)`; their bottom padding is the safe-area inset inside the scroll, so content runs under the home indicator and the last item can still scroll above it. Buttons and pinned elements stay inside the safe area.
- Shadows from `Elevation`. In dark mode, capsules drop the pressed shadow and keep the soft one.

## Motion

- Every duration and curve is a `Motion` token, named by what it animates (`Motion.capsule`, `Motion.sheetOpen`, `Motion.edgeFade`, …).
- **Reduce Motion** (iOS setting) applies to every screen:
  - no sliding or finger-following chrome; show/hide uses `Motion.reducedFade` (app sheets still slide, only shorter);
  - streamed text appears per whole section;
  - no fading tail, static dots, no shimmer on placeholders;
  - jumps and folds don't animate.

## Accessibility

- VoiceOver gets a label for every icon-only button, announces when a streamed answer is complete, and never reads a section while it's still being written.
- Chrome that hides on scroll stays visible while VoiceOver is on.
- Color is never the only signal: status also has text or an icon.
- Long-press on a book (card or row) gives a medium haptic.

## Shared components

Shared widgets live in `ui/core/widgets/`; reuse them before building new ones.

### Sheets (`showAppSheet`, `SheetFrame`)

- Standard sheet frame: grabber, title, scrolling body, optional action buttons. Detail pages under Settings use `SettingsPage` instead (back button, title, scrolling body with space for the tab bar).
- Close: Flutter's standard drag-to-dismiss, or tap above the sheet. The Artinya sheet has its own drag handling (see [Artinya sheet](#artinya-sheet)).

### Edge fade (`EdgeFadeScroll`)

Scroll edges that meet pinned elements fade with a mask (`ShaderMask` + `BlendMode.dstIn`), never a background-colored gradient, so it works in both themes. Board "EdgeFade · tepi area scroll".

- The top fade appears only after scrolling; the bottom fade only above action buttons or the bottom capsule, and only while more content is below. Fades show and hide with `Motion.edgeFade`.
- The bottom screen and sheet edges never fade (edge-to-edge).

| Where | Top fade | Bottom fade |
|---|---|---|
| Sheet without actions (Aa, table of contents) | below the title | none |
| Sheet with actions | below the title | above the buttons |
| Artinya sheet | below the header (below the grabber when the header hides) | above the buttons while they're visible |
| Full screens (Rak, Pengaturan) | below the pinned header | none |
| Reader, capsules visible | from the top capsule | to the bottom capsule, then a weak fade to the screen edge |
| Reader, immersive | none | none |

In the reader, the mask strength follows `ReaderChrome.hidden` (the capsule controller), so text never flickers when the capsules move.

### Reader capsules (`ReaderCapsule`)

Board "Baca imersif · ReaderCapsule" (+ screens 03, 03b, 03c). The reading page shows only text and the progress line; menus live in two floating capsules that overlay the text.

- **Top capsule**: back · book title + chapter title ("Bab N" only when the book has no chapter titles) · table of contents · ⋯. The ⋯ popover holds Cari kata and Atur tampilan; in search mode ⋯ gets a yellow dot. The button whose sheet is open turns yellow.
- **Bottom capsule**: info only: percentage, progress track (`Layout.readerProgressTrack`), and "±N mnt lagi" or "<chapter> kelar".
- **Chapter opener**: one layout for every title length: centered, tilted yellow stroke (`Layout.chapterStroke*`), title in the reading font, meta "Bab 4 dari 102 · ±14 mnt", spacing `Layout.chapterOpener*`.
- **Table of contents**: no number column; each row shows "±N mnt" on the right; the current chapter has a yellow background and "Lagi dibaca".
- **Progress line**: full width just above the bottom safe area (`progressLine` on `progressLineTrack`), per book; 100% on the book-end screen.

### Artinya sheet

Boards "Spek · Artinya ngumpet pas scroll" and "Artinya streaming · perilaku". Data and phases: [architecture.md](architecture.md), [llm.md](llm.md).

- **Shape**: fixed height `Layout.artinyaHeight` in every state (`DraggableScrollableSheet`). Header (title + X), grabber, and the Salin / Lanjut buttons are layers above a full-height scrolling body (padding `Layout.artinyaHeader` / `Layout.artinyaActions`), so hiding them never moves text.
- **Text follows Aa** (`ReaderTypography`); the sheet's base padding is the minimum margin, so "Sempit" looks like "Pas".
- **Streaming states**:
  - *waiting*: header "Bentar, lagi mikir...", placeholders per paragraph + meaning; not scrollable yet; swiping the body doesn't close.
  - *writing translation*, then *writing meaning*: paragraphs arrive in order, the rest stay placeholders.
  - *done*: header "Artinya gini nih", Salin enabled.
  - *slow*: a card above the content (Batal / Coba lagi) that disappears when tokens arrive.
  - *cut*: received text stays, placeholders go, pink banner + Coba lagi (restarts).
  - Cached groups appear complete at once, with no pacing.
- **Pacing**: characters per frame via `Pacer` (`domain/pacing.dart`): a steady baseline that speeds up adaptively when text backs up. No cursor, blink, or yellow in the text; the last 4 words of the section being written fade in steps (80 · 60 · 42 · 26%) and turn solid over `Motion.tailFade` when done.
- **No auto-scroll**: the body stays at the start of the translation while the rest is written below; only the finger scrolls. During streaming the header scrolls with the content and the buttons stay put.
- **Placeholders follow Aa**: lines = ⌈chars × average glyph width ÷ column width⌉, chars = source paragraph length × 1.05 (meaning: 130), glyph width measured with `TextPainter` for the active font and size.
- **Buttons**: while processing, Salin is disabled and carries the status (pulsing dots + "Lagi mikir" / "Lagi nulis"), then crossfades to "Salin" (`Motion.statusSwap`). Lanjut is disabled while waiting, slow, or writing. X cancels the request ("Batalin" in VoiceOver).
- **Hide on scroll** (finger scrolls only, after streaming): the header follows the content 1:1 and is gone after `Layout.artinyaHeader`; scrolling up by the `ScrollRun` show threshold brings it back, following the finger, snapping on release. The buttons slide out after the `ScrollRun` hide threshold (`Motion.capsule`) and return on scroll up or at the bottom. They never hide when everything fits, in waiting / error / no-key states, or with VoiceOver on.
- **Close**: swipe down on the grabber at any offset (fling past `Layout.sheetDismissFling` or drag below `Layout.sheetDismissRatio`), swipe down on the body at offset 0, or tap above the sheet.
- One widget renders every phase, so completing never jumps the layout or resets the scroll position.
- **Salin** copies the whole group's translation (one paragraph per block); the button becomes "Disalin" + toast "Udah disalin, tinggal paste".
- **VoiceOver**: the sheet is labeled "Artinya, lagi ditulis"; completion is announced "Artinya udah lengkap".
- **Bedahin entry**: last item of the body, after the meaning, for every group: "Masih bingung? Bedahin" or "Buka bedahan · Udah pernah dibedah · N bagian". Hidden while the meaning is being written or cut; fades in once the section count is loaded, so the copy never swaps in front of the reader.

### Book metadata sheet

Boards 33–38 (entry row on Info buku, board 21). Stacked on Info buku: X (Batal) · title · check (Simpan, primary; disabled = muted). A live cover preview follows the fields; Judul + Penulis (optional); "Pakai cover default" only when the EPUB has a cover; "Balikin ke aslinya" refills the fields (saved only on Simpan) and leaves the cover toggle alone. Empty title: error + Simpan disabled. Info buku shows "Penulis gak ketemu" (italic) for an empty author, and breaks long unspaced titles per character.

## Reader interaction

Thresholds marked `ScrollRun` come from `ui/core/scroll_run.dart` and are shared by the capsules, the Artinya sheet, and Bedahin; they count per direction and reset when the direction changes. Only finger scrolls count; programmatic scrolls and restore jumps never move chrome.

| Trigger | Result |
|---|---|
| Scroll down past the `ScrollRun` hide threshold | Both capsules slide out (`Motion.capsule`); while dragging they follow the finger 1:1, then snap |
| Scroll up past the `ScrollRun` show threshold, or fling up | Capsules come back |
| First 80 pt of a chapter, last paragraph visible, chapter change | Capsules show |
| Tap a paragraph (its whole column-width box) | Opens the Artinya sheet for its group |
| Tap empty space (margins, gaps, below the last text, headings, scene breaks) | Toggles the capsules. The margin tap area is at least 24 pt: with "Sempit" margins, the column's outer 8 pt count as empty space |
| Tap outside an open sheet | Closes the sheet (never toggles capsules) |
| Open a sheet from a capsule (table of contents, ⋯ → Aa) | Top capsule stays above the scrim; its button turns yellow; tapping it again closes the sheet. The barrier is transparent and the reader draws the scrim below the capsule |
| Artinya sheet opens | Capsules hide; the page scrolls with the sheet so the group's bottom sits `Layout.followGap` above the sheet, re-aligning whenever the sheet height changes (a taller group starts at safe area + `Layout.followGap`). The group is one `highlight` block; the scrim is cut out around it |
| Lanjut in the Artinya sheet | Moves to the next group in the chapter (disabled on the last) and scrolls it into place. Closing afterwards keeps the page at the last group and saves the position; closing after a single group returns to where the page was |
| Group already translated | `mark` line in the left margin (`ReadMark`); opens from cache |
| Chapter-end card visible | Both capsules show; bottom capsule reads "<chapter> kelar" |
| Book end | Its own screen without capsules, progress line full, default cover style, status bar back |
| Open a book with a saved position (Lanjut baca) | Capsules show for `Motion.capsuleIntro` then hide (cancelled if the reader scrolls first); the saved group flashes once (`Motion.flash`, `flash` color). Reduce Motion: a left line for `Motion.flashReduced` instead |
| Capsules hide with "Sembunyiin jam & baterai" on (default) | Status bar hides with them; leaving the reader brings it back |

### Aa sheet ("Atur bacaan lo")

Board 07, opened from ⋯ → Atur tampilan. Every choice applies and saves immediately; the scrim is light so the text behind acts as a preview. The line at the top of the screen stays put when size, font, spacing, or margin change.

- Size: 7 steps 16 · 17 · 18 · **18.5** · 20 · 22 · 24.
- Font: **Jelas** / Kayak buku / Bawaan sistem.
- Line height: Rapat 1.5 / **Pas 1.65** / Lega 1.85.
- Margin: Sempit 16 / **Pas 24** / Lega 32.
- Theme: Terang / Gelap / **Ikut sistem** (the app's `themeMode`).
- Toggles (both on by default): "Sembunyiin jam & baterai", "Tampilin garis progres".
- Stored per device, not per book ([data-model.md](data-model.md)).

## Bedahin

Boards "Terpilih · Bedahin · Opsi C · layar bedah" + "Spek · Bedahin · state". Its own screen (`BreakdownView`); data from `breakdownStreamProvider` ([architecture.md](architecture.md), [llm.md](llm.md)). All Artinya streaming rules apply: `Pacer`, fading tail, shimmering placeholders, status in the Salin button, Reduce Motion, VoiceOver.

- **Header**: back (VoiceOver "Batalin, balik ke Artinya" while processing) + status ("Lagi ngebedah..." / "Udah dibedah nih" / "Kepotong di tengah" / "Bedahin" on error) + "book · chapter · N bagian" ("1 gagasan"; "N bagian masuk" when cut).
- **Text panel** (the translation, follows Aa) exists in every state:
  - Section numbers precede the first sentence of each section, only with ≥ 2 sections; while writing, a number appears together with its explanation.
  - Multi-paragraph groups get `¶n` in a left gutter; a section spanning paragraphs gets a `¶2–3` tag.
  - **Folded by default** in every state to one line "Teks terjemahan · n bagian" (no count while processing or on error), since the reader just read it in Artinya. Tap the line to open (`Motion.fold`); tap the panel (outside a number) or its bottom chevron strip to fold.
  - Nothing folds or opens automatically, except tapping a term, which opens it. The fold state isn't remembered between screens.
  - Pinned under the header, height = text, at most `Layout.breakdownPanel` of the screen, scrolling inside beyond that. With 1 section (done), it scrolls with the page instead and shows the source sentence under the translation.
- **Explanation**: per section a number + title (≥ 2 sections), MAKSUDNYA, LOGIKANYA; then Tokoh & istilah, Nyambung ke (cards with a chevron when the target exists, plain text otherwise), Praktekinnya gini. Empty blocks don't render.
- **Sync** (≥ 2 sections):
  - The active block is the one whose top passed the read line (`Layout.breakdownReadLine`, hysteresis `Layout.breakdownSwitch`, `activeBlock` in `domain/breakdown_sync.dart`); at the bottom, the last block.
  - The active section's sentences are highlighted in the panel, which scrolls to its number. Highlighting runs from section 1 while writing.
  - Tapping a number or chip jumps the explanation there (locked until the next finger scroll). Chips `1…n / Istilah / Praktek` appear only with ≥ 3 sections and scroll sideways with a right fade.
  - Tapping a term highlights its exact words and opens the panel; terms without an exact match aren't tappable.
- **Buttons**:
  - Salin / status + "Balik baca" (yellow).
  - Cut: Salin disabled, "Balik baca" muted, yellow moves to "Coba lagi dari awal".
  - Error: "Balik baca" + "Coba lagi"; key rejected or missing shows "Buka Pengaturan", and returning from Settings retries.
  - Buttons hide on scroll (`ScrollRun`) except while processing, on error, or with VoiceOver. The header never hides.
- **States**:
  - *waiting*: placeholders, count guessed from sentences ÷ 6, not scrollable.
  - *slow*: card above the placeholders, secondary Batal / Coba lagi; Batal returns to Artinya.
  - *cut*: complete sections only, closing blocks dropped, pink banner.
  - *error*: copy per error type.
  - *cached*: complete, from the top.
- **Peek** (board "Bedahin · Nyambung ke · intip"):
  - Tapping a Nyambung ke card opens a sheet sized to content (max 70%) with the header ("NYAMBUNG KE · AWAL XVII" / "LANJUTAN V · GRUP BERIKUTNYA"), why it connects, and a muted card: the translation over italic source text if translated, otherwise the source at Aa size.
  - Buttons are all secondary: "Artiin" + "Bedahin ini juga", or only the latter when translated. "Artiin" streams the target group without pacing.
  - Failed or cut: a pink row under the card + "Coba artiin lagi"; key rejected, balance empty, or no key adds a "Buka Pengaturan" link.
  - "Bedahin ini juga" on an untranslated group translates it first, then continues.
- **Layered navigation**: "Bedahin ini juga" pushes the target's Bedahin on top. Back or edge swipe goes back one layer, keeping the layer's scroll position. "Balik baca" from any layer returns to the reading page.
- **Salin**: plain text "book · chapter (dibedah di Luma)", per section number + title + Maksudnya + Logikanya, then Tokoh & istilah and Praktekinnya gini; no translation, no Nyambung ke.
- **Reduce Motion**: push is a fade. **VoiceOver**: the explanation is read before the panel; each section is a heading "Bagian i dari n, title"; completion is announced "Bedahan udah lengkap, N bagian".

## Pengaturan

Board "Pengaturan · 01–11" (page `atur`).

- The hub fits one screen without scrolling and isn't covered by the tab bar: account card + AI quota ring, AI model card ("Ganti model" opens the picker, "Atur AI" goes to the AI page), then 5 tiles Backup · Katalog · Cache · Tampilan · Statistik (name + one status + "›"; a pink dot when something needs checking, e.g. never backed up). Statistik isn't on the board; it reuses the tile and the detail-page cards.
- Detail pages: Akun, AI, Backup & pulihin, Katalog buku, Statistik baca. Cache and Tampilan are sheets.
- Statistik baca: Kebiasaan (this week's reading time from Monday, the streak, last week's time), Kalender baca (the last `StatsRepository.calendarWeeks` weeks, one square per day in four accent steps relative to the busiest day), Paling sering baca (busiest hour and weekday), Lagi dibaca and Udah tamat (up to 5 books each: position, own speed in characters per minute, and time left at the speed of the last `StatsRepository.recentDays` days; finish date), Bantuan AI (successful Artinya calls per 1,000 characters read, one bar per week over `StatsRepository.trendWeeks`; lower means smoother reading), Bab paling susah (chapters with at least `StatsRepository.hardestMinGroups` groups, by the share of groups translated, with reopen counts; a tap opens the reader at that chapter), Biaya AI (shown once an AI call is logged: cost and requests per month over `StatsRepository.costMonths`, per feature, and for the costliest books; a cost no call reported is "Gak tercatat", never zero), and Sejauh ini (all-time reading time, finished books); an empty card before any reading. The Statistik tile shows this week's reading time.
- Tampilan = theme (same setting as Aa) + display language; the language never changes translations or AI answers.
- Sparing palette: yellow only on the primary button and the active tab, pink for status and delete.

## Ngobrolin buku (book chat)

Screens: [design/references/ngobrolin-buku.html](../design/references/ngobrolin-buku.html). Data, lifecycle, and answer protocol: [architecture.md](architecture.md), [llm.md](llm.md).

- The reader entry resumes the last session; "Tanyain ini" opens the session already started from that quote, or starts a new draft with the quote (removable). A draft isn't in history until its first send. A session from an old book revision is a read-only archive with a "new chat" action.
- **Aa**: chat answers, context cards, quotes, and citation context use `ReaderTypography.style` with `ReaderTypography.paragraphGap` between paragraphs. The citation sheet uses the Aa margin (`ReaderPrefs.marginWidth`). The chat screen's side margin is always 16 (= Sempit) whatever the Aa margin; font, size, and line height still follow Aa. Header and composer use UI margins.
- Composer: 1–5 lines. Renaming requires a title (max 120 Unicode code points). Entry targets stay `Layout.touch` while the dock shrinks.

## Copy

- Indonesian is casual Gen Z: "Rak buku lo", "Lanjut baca yuk", "Artinya gini nih", "Maksud penulisnya tuh...", "Bentar, lagi mikir...", "Yah, gagal nih". English is casual and natural.
- Errors say what happened and what to do next, with a short technical code in small text where useful (`timeout · 30 detik`, `HTTP 402 · saldo abis`).
- Strings live in the ARB files, never in widgets ([i18n.md](i18n.md)).
