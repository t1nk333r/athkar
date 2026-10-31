# Deck definition

The card-deck screen shared by the four decks: أذكار الصباح, أذكار المساء, رقية القرين and سور
(NATIVE_APP_PLAN.md §3.2, §9.2). It describes behaviour, not code. A platform builds one deck component driven by
this document. iOS builds `DeckView` + `DeckModel` in `ios/Athkar/Deck/`. Android builds a Compose `DeckScreen`.
The rules below follow the two PWAs: `index.html` in this repository, and `index.html` in `ruqyah-al-qareen`. PWA
function names are given in backticks.

Session rules that already have fixtures (`spec/sessions/fixtures/`) are the contract: `targetForState`,
`countForState`, `periodCountersComplete`, `syncCompletionState`, `setManualCompletion`, `buildDeck`,
`firstIncompleteIndex`, `rollStateToDate`, and the scoped resets. Storage is described in `spec/schema.md`
("Session state bridge", "Ruqyah counters and reset").

## 1. Decks

| Deck | Items | Order | Session |
| --- | --- | --- | --- |
| `morning` | `content/adhkar.v1.json` → `periods.morning` (26 items) | Content order, or long-order (§3) | Shared adhkar session (both periods) |
| `evening` | `content/adhkar.v1.json` → `periods.evening` (24 items) | Content order, or long-order (§3) | Shared adhkar session |
| `ruqyah` | `content/ruqyah.v1.json` → `segments` (15 segments, 33 readings) in five sections, one per sura | Pack order, never reordered | Own session |
| `suwar` | `content/suwar.v1.json` → `suwar` (5 suras, 86 pages) in five sections, one per sura | Pack order, never reordered | Own session |

A **card's number** is its 1-based position in content order, in Arabic-Indic digits; a ruqyah segment's or a
«سور» page's is its position in its sura. Long-order never changes it. **Positions** («٢ من ٢٦») are 1-based
positions in the deck as currently ordered, the shown sura for ruqyah and «سور».

**Ruqyah sections.** The ruqyah deck has one section per sura, as the ruqyah PWA's `RUQYAH_SUWAR` groups the pack:
the segments whose IDs share a prefix (`qaf`, `jinn`, `takwir`, `kafirun`, `nas`), consecutive in the pack. Chips
above the summary pick the sura shown (`.sura-picker`, spoken «اختيار السورة»). Each chip shows the sura's name
without «سورة », and «✓» once its segments are all complete today; it is spoken «<surah>», or «<surah>، مكتملة
اليوم», and the shown sura's chip is selected. Each chip starts from its text's width and the chips share the rest of
the row (`flex: 1 1 auto`), so «الكافرون ✓» is not cut where «ق» needs little. The cards, position, lock, summary row
and sura dialog are the shown sura's; the today line, the أخرى row and its «✓» are the whole day's. The deck opens on
ق (the PWA opens there unless a sura deep link names another; the native app has no deep links). Each sura keeps the
card it showed last until the day changes or the ruqyah is reset.

**«سور» sections.** The «سور» deck is the athkar PWA's «سور» tab: one section per sura of `content/suwar.v1.json`, in
pack order (الكهف, يس, الصافات, الواقعة, الملك). Its chips work as the ruqyah chips do, with «✓» once every page of
the sura is read today, but take equal shares of the row (`flex: 1 1 0`), as the athkar PWA's do. The cards,
position, lock, summary row and sura dialog are the shown sura's; the أخرى row and its «✓» are the whole day's. The
shown sura is stored (`suwar_selected_sura`, the PWA's `athkar-suwar-v1.selected`), so the deck reopens on it. It
starts on الكهف, and a stored sura the pack no longer has reads as the first (`normalizeSuwarState`). Each sura keeps
the page it showed last until the day changes or «سور» is reset (`suwarIndices`).

The screen has three tabs in this order: الصباح, المساء, أخرى. The first two open their adhkar deck. أخرى opens a list
of sections (رقية القرين, سور, مسبحة, أذكار النوم, أذكار بعد الصلاة, أذكار الاستيقاظ, أوقات الصلاة, القبلة). The app
opens رقية القرين, سور, مسبحة, أوقات الصلاة and القبلة, and lists the others as «قريبًا». A deck row shows the deck's
summary copy and «✓» once today is complete. «مسبحة» is a counter, not a deck ([`tasbih.md`](tasbih.md)); its row
shows today's total, «اليوم: N». The أوقات الصلاة row shows the next prayer and its time, or «حدّد موقعك لعرض
المواقيت». When a section is open, the header replaces its title with a back button labeled with the section's title,
and the tabs are hidden; the back button returns to the list, where they show again. The list has no summary, and its
reset button is disabled. The أخرى tab never shows «✓»; each row shows completion. Each deck keeps its current card
while another deck is open. The رقية القرين row shows the whole day's «N من ٣٣ تكرارًا», and the سور row the suras
complete today, «N من ٥ سور» (native: the PWA's tab has no such line); its «✓» needs all five.

### Adhkar item fields

The card reads these item fields:

- `id`, `kind` (`quran` | `dhikr` | `review`), `text`, `prefix?`, `details[]`
- `count?`, `countLabel?`, `targetOptions?`, `defaultTarget?`, `noteIndex?`
- `reviewTitle?`, `reviewCopy?` (review items)

Presentation:

- `prefix` is centred above the text.
- `quran` items (all in the Uthmani edition) use KFGQPC HAFS for the prefix and text, converted to the King Fahd
  Complex's encoding (`MushafEncoding.kfgqpc`, `kfgqpcEncoding` in the PWA); their ﴿n﴾ numbers stay in KFGQPC Uthman
  Taha Naskh. Other items use the platform's Arabic Naskh/system face.
- The card shows `details[0..<noteIndex]`, or every detail when `noteIndex` is absent or out of range.
- When `noteIndex < details.count`, a «المصدر والتفاصيل» link opens a sheet with all the details. The detail at
  `noteIndex` is styled as a note.
- `review` items are never counted and cannot be tapped. Their card (`.needs-review`: dashed warning border on a
  warning tint) shows only the number with the badge «بحاجة إلى مراجعة», then `reviewTitle` (or `text` when
  absent) in the dhikr text style, then `reviewCopy` in the warning colour (1 rem, bold, line height 1.8). There
  is no requirement row, counter, reset or tap target, and the body is not fitted; it scrolls if it must.

### Ruqyah segment fields

The card reads these segment fields: `id`, `surah`, `range`, `repeat`, `basmala`, `ayahs[{number, text}]`.

Layout:

- The card head shows `surah` at the start and `range` at the end.
- The body is centred.
- When `basmala` is true, the body starts with «بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ» at 0.92× the text size, in
  the accent colour. The pack does not contain this text; the PWA prints it.
- Then the ayahs, joined by spaces. Each ayah is followed by «﴿n﴾» (Arabic-Indic n) at 0.78× the text size, in the
  accent colour.

### «سور» page fields

The card reads the pack's `basmala`, the sura's `surah`, and these page fields: `id`, `range`, `ayahs[{number,
text}]`.

Layout (`suraPageMarkup`, a `.dhikr-card.quran.sura-page`):

- No head; the body is centred.
- A sura's first page starts with the pack's `basmala` (`.dhikr-prefix`) at the quran prefix size, line height 1.7,
  in the strong accent colour. Later pages have none.
- Then the ayahs, joined by spaces, each followed by «﴿n﴾» (Arabic-Indic n) in KFGQPC Uthman Taha in the strong
  accent colour. The text is set as adhkar `quran` items are: KFGQPC HAFS in the King Fahd Complex's encoding.
- The footer shows `range` and the counter, in the adhkar card's style with a compact footer.

## 2. Counters

### Adhkar (`targetForState`, `countForState`)

- **Target.**
  - If the item has `targetOptions` (and `defaultTarget`), the target is the stored target when it equals one of
    the options, otherwise `defaultTarget`.
  - Otherwise the target is `count`, or 1 when `count` is absent or 0.
  - Chosen targets are stored per (date, period, item). A new day starts at the default target.
- **Count.** Apply `floor` to the stored count. Use 0 when the result is not finite or is negative, then clamp it
  to `min(count, target)`. Storage keeps the raw values.
- **Complete item.** `count >= target`, or the item is a review item.
- **Display.** Numeric when `count > 0` (the item field) or `targetOptions` is present (`isExplicitlyCounted`):
  «count/target», left to right, with «✓» when complete. Otherwise the phrase «اضغط بعد القراءة», which becomes
  «تمت القراءة» once complete.
- **Requirement line.** `countLabel`, or «مرة واحدة».
- **Target picker** (only for items with `targetOptions`). Labelled «الهدف». Options 1, 10 and 100, shown in
  Arabic-Indic digits.

### Ruqyah

- **Count.** The stored count, clamped to `0…repeat` (`normalizeCounts`).
- **Complete segment.** `count >= repeat`.
- **Display.** When `repeat == 1`: «اضغط بعد القراءة», which becomes «تمت». Otherwise «count/repeat».
- **Requirement line.** «مرة واحدة» (repeat 1), «مرتان» (repeat 2), «N مرات» (otherwise).
- **Progress.** The sum of counts, out of the sum of `repeat`: the shown sura's in the summary row, the whole
  day's (33) in the today line and the أخرى row.
- **Complete sura.** Every segment of the sura is complete (`suraIsComplete`).

### «سور»

- **Count.** 1 once the page is read today, otherwise 0: a page is read once (`markPageRead`).
- **Display.** «اضغط بعد القراءة», which becomes «تمت القراءة» with «✓». The requirement line is the page's `range`.
- **Progress.** Pages read out of the shown sura's pages in the summary row; suras complete out of five in the أخرى
  row.
- **Complete sura.** Every page of the sura is read today (`suraIsComplete`).

## 3. Long-order (adhkar only)

The setting is `long_order` (`last` | `original`; default `original`).

- **Long items.** A non-review item whose *current* target is at least 10 (`longDhikrThreshold`).
- **Deck order with `last`** (`buildDeck`). Take every item except the last, in content order. Put the non-long
  ones first, then the long ones, then the last item. A deck with fewer than 3 items is never reordered. The last
  item always stays last, even when it is long.
  - Shipped morning result: m01…m19, m22, m23, m26, then m20, m21, m24, then m25.
- **Rebuild the order** only at these moments. A deck is not re-sorted on every tap.
  1. When long-order is toggled. The current card of the active adhkar period stays in view at its new position,
     or the deck moves to its first unread card if that item is gone. The other period moves to its first unread
     card. The active period is the adhkar period shown last, even when the أخرى tab is open.
  2. When a target changes while long-order is on. Focus stays on the changed item.
  3. On day rollover.
- **One-time question.** It is asked 0.7 s after the first launch, while `long_order_prompt_answered` is false. If
  another dialog is open, it waits and tries again every 1.5 s. It cannot be dismissed without answering.
  - Title: `longOrder.prompt.title`.
  - Buttons: `longOrder.prompt.keep` (sets `original`) and `longOrder.prompt.accept` (sets `last`).
  - Either answer sets `long_order_prompt_answered = true`.

## 4. Opening card, navigation, lock

- **Opening card.**
  - Adhkar: `firstIncompleteIndex`. That is the first non-review item below its target. If there is none, it is
    the last index; for an empty deck it is 0. Manual completion does not change it.
  - Ruqyah: the shown sura's last card since the deck opened, otherwise its first incomplete segment, or 0 when
    the sura is complete (`renderSuraDeck`). A day rollover forgets the last cards and keeps the shown sura. A
    reset reopens ق on its first segment (`showDayCleared`).
  - «سور»: the shown sura's last page since the deck opened, otherwise its first unread page, or its last page when
    every page is read (`renderSuraPages`). A day rollover and a reset forget the last pages and keep the shown
    sura.
- **Back** («السابق», and a swipe back) is enabled when `index > 0`.
- **Forward** («التالي», and a swipe forward) is enabled when `index < count − 1`, and additionally:
  - Adhkar: the current item is complete, or is a review item, or the period is manually complete (the lock).
  - Ruqyah: the current segment's repeats are complete (`updateDeckNavigation`, as in the adhkar PWA's «سور» tab).
    The lock holds within the shown sura; the chips switch suras at any time.
  - «سور»: the current page is read. The lock holds within the shown sura.
- **Position.** Shown as «N من M». Spoken as «الذكر N من M» for adhkar, «المقطع N من M» for ruqyah and «الصفحة N
  من M» for «سور», where M counts the shown sura's segments or pages, and announced after every navigation. The
  card list is spoken «<cards>، <position>»: «بطاقات <section>» for adhkar, «مقاطع <surah>» for ruqyah, «صفحات
  <surah>» for «سور».
- **Native quick index.** The position is a button at least 44 pt tall. It opens an RTL sheet titled
  «فهرس الورد» for adhkar, «فهرس الرقية» for ruqyah or «فهرس السورة» for «سور», with «إغلاق» and every card in
  current deck order.
  Each row shows its original number, existing opening text or surah/range, counter status and current-row marker.
  Review rows show their warning and no counter. Quran text uses the same rendering as the card.
  - Earlier and current rows are selectable. A later row is selectable only when every intervening forward
    step satisfies the existing lock. Keep unavailable rows visible and disabled. Manual completion unlocks
    adhkar. A ruqyah segment or «سور» page opens once every one before it in its sura is read.
  - Opening the index cancels pending auto-advance. Closing it does not reschedule advance. Selection never
    changes counts, targets or completion. Dismiss first, resolve the selected card ID against the current deck,
    recheck day rollover and reachability, then navigate and announce. If rollover changed the deck or the chosen
    row is no longer reachable, keep the current card and announce its position. Selecting the current row only
    dismisses.
  - Keep `deck.position` and its spoken label. Row labels use `card.progressLabel`, never encoded Quran text;
    their accessibility value gives the deck position, which can differ from the original number in long-order.
    Wrap rows at large text sizes and preserve Reduce Motion, RTL, palette and reading fonts.
- **Hint below the controls.** `deck.hint.adhkar` (adhkar and «سور», as the PWA's «سور» tab keeps it) or
  `deck.hint.ruqyah`.

## 5. Tap to count

The whole card is the tap target. The reset button, the target picker and the source link sit above it and receive
their own taps.

A tap does nothing when:

- the card is complete (the tap target is disabled), or
- it lands within 450 ms of the end of a horizontal swipe, or
- the local date changed since the last check. The rollover runs first and the tap is ignored.

Otherwise:

1. `count += 1`, and the new count is saved.
2. Play the completion haptic, 45 ms, only when `haptics` is true:
   - Adhkar: when the card just reached a target greater than one. Single-count cards stay quiet.
   - Ruqyah: when the segment just completed, whatever its `repeat` (`if (completesSegment) triggerHaptic`).
   - «سور»: every page marked read (`markPageRead`).
   - Intermediate taps stay quiet.
3. **Adhkar:** run `syncCompletionState(period)`. If it returns `newlyCompleted`, open the completion dialog and
   do not auto-advance. Otherwise, if the card just completed, auto-advance.
4. **Ruqyah** (`applyOp`, `showReading`):
   - If the segment just completed its sura, record the sura complete today (once; the first time is kept), in
     the same transaction as the count.
   - If every segment is now complete, also record today as complete (once; the first completion time is kept) and
     open the day's completion dialog. This also happens when today was already recorded.
   - Otherwise, if the sura just completed, open its completion dialog (§7).
   - Otherwise, if the segment just completed, auto-advance.
   - The PWA opens the day's dialog only when this reading records the day. When today was already recorded (a
     new reading after «بدء رقية جديدة», or after a restart), it opens the sura dialog instead, whose
     «الانتقال إلى …» then finds no incomplete sura and fails. The native app opens the day's dialog whenever
     every segment is complete.
5. **«سور»** (`markPageRead`): record the page read today. If it completes the sura, record the sura complete
   today (once; the first time is kept) in the same transaction, and open its dialog (§7). Otherwise auto-advance.
6. Announce the card's counter label (§9).

**Auto-advance** (`scheduleAdvance`). After 320 ms (20 ms with Reduce Motion), move to `index + 1`, but only if:

- the card was not the last, and
- the deck is still on that index, and
- the card is still complete.

Any navigation cancels a pending advance.

**Target change** (adhkar only). There is no haptic.

1. `wasComplete = count >= target`.
2. Store the new target, then set `count = min(count, newTarget)`, where `count` is already clamped to the new
   target.
3. Run `syncCompletionState`.
4. If newly completed, open the dialog. Else, if long-order is on, rebuild the order (§3). Else, if the item went
   from incomplete to complete, auto-advance.

**Card reset.** Enabled when `count > 0`. It sets `count = 0` and then runs `syncCompletionState` (adhkar), or
saves the segment and clears its sura's completion today (ruqyah), or marks the page unread and clears its sura's
completion today («سور», `resetSuraPage`), in one transaction.

- Adhkar asks first only when `target >= 50`:
  - Title: `card.reset.confirm.adhkar.title` («إعادة عداد الذكر N؟»).
  - Message: `…message` («سيعود العداد من X إلى الصفر.»).
  - Confirm button: «إعادة».
- Ruqyah always asks: `card.reset.confirm.ruqyah.*`.
- «سور» never asks.

## 6. Swipe (`beginCardSwipe` … `finishCardSwipe`)

Measure the drag in screen coordinates, not layout-mirrored ones. A **rightward** finger movement (dx > 0) means
**forward**, in both PWAs and on native.

**Axis lock.** After 8 pt of movement:

- If `|dy| >= |dx|`, the gesture is vertical. Ignore it; it may scroll the card.
- Otherwise it is horizontal. Taps are suppressed until 450 ms after it ends.

**While dragging horizontally:**

- The card moves by `dx` if navigation in that direction is allowed (§4), otherwise by `dx × 0.2` (rubber band).
- Opacity is `1 − min(|offset| / cardWidth × 0.18, 0.18)`.

**On release:**

- `distance = |dx|`
- `threshold = max(32, min(52, cardWidth × 0.1))`
- `velocity` in pt/ms: the recent velocity when its sign matches `dx`, taking `max(|recent|, average)`. Otherwise
  the average (`|dx| / duration`, with the duration measured from touch-down, not from the axis lock).
- `flick = distance >= 18 && velocity >= 0.35`
- `horizontal = distance > |dy| × 0.75`

Navigate one card only if `horizontal && (distance >= threshold || flick)` and the direction is allowed.
Otherwise the card settles back over 120 ms, using cubic-bezier(0.2, 0.8, 0.2, 1). With Reduce Motion it snaps
back at once.

**Card transition.** The entering card fades in from opacity 0 and scale 0.988, over 150 ms with cubic-bezier(0.2,
0.8, 0.2, 1):

- going forward, it starts 16 pt to the physical left;
- going back, it starts 16 pt to the physical right.

With Reduce Motion there is no transition.

## 7. Completion

### Adhkar (`syncCompletionState`, `setManualCompletion`)

A period is complete when it is complete by counters (`periodCountersComplete`: every non-review item is at its
target) or manually complete.

After a counter or target change:

- Counter completion clears the manual flag.
- A complete period gets `completedAt = now`, unless it already has one.
- An incomplete period loses `completedAt`.
- `newlyCompleted` means complete by counters, with no manual flag and no earlier `completedAt`.

Manual completion is a per-period toggle in Settings. The toggle:

- is on while the period is complete;
- is disabled while the period is complete by counters;
- when turned on, keeps an existing `completedAt` or sets it to now;
- when turned off, clears `completedAt`;
- never opens the dialog, and unlocks forward navigation.

The completion dialog shows:

- Title: `completion.adhkar.title`.
- Message: `completion.adhkar.message`.
- The completion time, «وقت الإكمال: h:mm», localised ar-EG.
- Buttons: `completion.adhkar.done`, and `completion.adhkar.switch`, which opens the other period.

The tab (adhkar) or the أخرى row (ruqyah, «سور») shows «✓» and is spoken «<section>، مكتملة اليوم».

### Ruqyah

- A sura is complete once its segments are all complete. It is recorded in `ruqyah_sura_days` once a day, and its
  segment's card reset clears the record.
- The sura dialog (`openSuraCompletionDialog`) shows `completion.ruqyah.sura.title`,
  `completion.ruqyah.sura.message` and the sura's completion time, «وقت الإكمال: h:mm», with the buttons
  `completion.ruqyah.sura.done` and `completion.ruqyah.sura.switch`. The switch opens the next sura in pack order
  that is still incomplete today, wrapping round. A sura complete by its counters with no record of its own shows
  the day's record time, or no time without one (`backfillSuwarCompletions`); nothing is written.
- The day is complete once every segment is complete. It is recorded in `ruqyah_days` once.
- The day dialog shows `completion.ruqyah.title`, `completion.ruqyah.message` and today's completion time, with
  the buttons `completion.ruqyah.close` and `completion.ruqyah.restart`. «بدء رقية جديدة» is a day reset (§8);
  today stays recorded.
- Its أخرى row shows «✓» once today is recorded.

### «سور»

- A sura is complete once every page is read today. It is recorded in `suwar_sura_days` once a day, at the time its
  last page was read; a page reset clears the record (`completedAt`).
- The sura dialog (`openSuraCompletionDialog`) shows `completion.suwar.title`, `completion.suwar.message` and the
  sura's completion time, «وقت الإكمال: h:mm», with the one button `completion.suwar.done`: the PWA hides the
  switch (`completionSwitch.hidden`).
- Its أخرى row shows «✓» once all five suras are complete today.

## 8. Scoped reset

The header button «↻ إعادة», spoken «خيارات الإعادة», opens a picker for the pillar on screen. Both adhkar periods
reset together; ruqyah, «سور» and «مسبحة» each reset alone (the PWA's header reset clears every store at once). The
button first runs the day rollover. «مسبحة» resets as [`tasbih.md`](tasbih.md) §6 describes: unlike the decks, its
«تقدم اليوم» asks first while a phrase is counted today.

It is enabled when:

- **Adhkar** (`hasResettableState`): any non-review count > 0 in either period, or any manual completion, or any
  earlier completed day.
- **Ruqyah:** today's readings > 0, or any recorded day: a completed day, or an earlier day with a completed sura.
- **«سور»** (`suwarHasResettableState`): any page read today, any sura complete today, or an earlier day with a
  completed sura.

| Choice | Adhkar | Ruqyah | «سور» | Asks first |
| --- | --- | --- | --- | --- |
| «تقدم اليوم» | Today's counts, `completedAt` and manual flags cleared; chosen targets kept. | Today's counts set to 0 and today's sura completions deleted; today's record kept. | Today's page reads and sura completions deleted (`resetSuwarProgress`). | No |
| «هذا الأسبوع» | Day reset, plus every adhkar record dated in the last 7 local dates (today included) deleted. | Day reset, plus recorded days and sura completions in the last 7 local dates (today included) deleted. | Day reset, plus the page reads and sura completions in the last 7 local dates (today included) deleted (`deleteSuwarHistory`). | Yes |
| «كل شيء» | Day reset, plus every adhkar record deleted. | Day reset, plus every recorded day and sura completion deleted. | Day reset, plus every page read and sura completion deleted. | Yes |

After any reset, every deck of the pillar goes back to card 1; the ruqyah deck reopens ق, and «سور» keeps the shown
sura.

The confirmations use `reset.confirm.week.*` and `reset.confirm.everything.*`, with the recorded-day count `N` from
`dayCountLabel`:

- `dayCountLabel(N)` is: 1 → «يوم واحد», 2 → «يومين», 3–10 → «N أيام», 11 and more → «N يومًا».
- Adhkar counts earlier days with a completion. Ruqyah counts completed days, today included, together with
  earlier days with a completed sura (`historyDates`). «سور» counts earlier days with a completed sura
  (`suwarState.history`).

The storage for all of this is in `spec/schema.md`.

## 9. Summary, day rollover, accessibility

**Summary above the deck** (`updateSessionProgress`):

- Adhkar:
  - «N من M ذكرًا» (M = non-review items; the suffix is «ذكرًا متاحًا» when the morning has a review item).
  - «اكتملت <section> اليوم» when complete by counters.
  - «اكتملت <section> خارج التطبيق» when manually complete.
  - The progress bar is full when the period is complete.
- Ruqyah:
  - The chips (§1), then the shown sura: «N من M تكرارًا», or «اكتملت <surah> اليوم» once it is complete. The
    progress bar is spoken «<surah>: N من M تكرارًا».
  - A second line for the whole day (`updateTodayStatus`): «رقية اليوم: N من ٣٣ تكرارًا», or «تمت رقية اليوم في
    h:mm» once today is recorded, in the completed colour.
- «سور» (`updateSuraProgress`): the chips (§1), then the shown sura: «N من M صفحة», or «اكتملت <surah> اليوم» once
  it is complete. The progress bar is spoken «<surah>: N من M صفحة مقروءة».

**Day rollover.** It runs at local midnight, when the app returns to the foreground, when the clock or time zone
changes, and before each tap, card reset (including a confirmed one), and target change. When the check finds a
new date, ignore the tap, reset, or target change because it belongs to the previous day's card.

- When the local date changes, load its rows and open each deck on its first unread card. The ruqyah and «سور»
  decks keep the shown sura.
- Nothing is deleted. The previous day is already history.

**Labels to speak.** These are the PWAs' live-region strings; announce them after the change.

- Adhkar counter (`progressLabel`):
  - Counted items: «ذكر N، تم تكراره X من أصل Y مرات», with «، اكتمل» added when complete.
  - Other items: «ذكر N، لم يُعلَّم كمقروء», or «ذكر N، تمت قراءته» once read.
- Adhkar tap target:
  - Counted items: «زيادة عداد الذكر N. <label>».
  - Other items: «تحديد كمقروء، الذكر N. <label>», or «اكتمل، الذكر N. <label>» once read.
- Ruqyah counter (`segmentLabel`): «المقطع N: <surah> <range>. <status>», N within the sura. The status is
  «لم تُقرأ بعد» or «تمت القراءة» when repeat is 1, and «تم X من Y» otherwise.
- Ruqyah tap target: «تسجيل قراءة المقطع N. <label>», or «اكتمل. <label>» once complete.
- «سور» counter (`updateSuraPage`): «الصفحة N من <surah>، <range>، لم تُعلَّم كمقروءة», or «…، تمت قراءتها» once
  read, N within the sura.
- «سور» tap target: «تحديد كمقروءة، <label>», or «اكتملت، <label>» once read.
- Reset buttons: «إعادة عداد الذكر N» / «إعادة عداد المقطع N» / «إعادة الصفحة N».
- Target picker: «اختيار عدد تكرار الذكر N».
- Reading order within a card: text, then counter controls, then the tap target.

## 10. Reading sizes and fit

Sizes use CSS `clamp(min rem, vw, max rem)`, with 1 rem = 16 pt and 1 vw = 1% of the window width. They are
multiplied by the platform's text-scale factor, so Dynamic Type or font scale still applies (factor 1 at the
default size).

| Text | small | medium | large |
| --- | --- | --- | --- |
| dhikr text | 1.08, 4.7, 1.5 | 1.24, 5.35, 1.72 | 1.4, 6, 1.95 |
| detail | 0.9, 3.7, 1.12 | 1, 4.1, 1.27 | 1.08, 4.5, 1.4 |
| quran prefix | 1.05, 4.45, 1.4 | 1.2, 5, 1.58 | 1.35, 5.75, 1.82 |
| quran text | 1.15, 5, 1.62 | 1.3, 5.6, 1.82 | 1.45, 6.4, 2.12 |
| ruqyah text | 1.1, 4.7, 1.55 | 1.26, 5.4, 1.78 | 1.42, 6.2, 2.05 |

Line heights (multiples of the font size), by the `line_spacing` setting:

| Text | compact | comfortable | wide |
| --- | --- | --- | --- |
| dhikr | 1.7 | 1.95 | 2.16 |
| detail | 1.62 | 1.85 | 2.05 |
| quran | 1.82 | 2.05 | 2.3 |
| ruqyah | 1.82 | 2.05 | 2.32 |

**Fitting.** Show the first step whose content fits the card body's height. Scroll only when no step fits.

- Adhkar `quran` cards: never shrink; they scroll if needed.
- Other adhkar cards step down twice (`fitCardContent`). A step never makes text larger than the chosen size.
  - Dense: text `min(size, clamp(1.12, 4.9, 1.54))`, line height 1.76; detail `clamp(0.94, 3.85, 1.1)`, line
    height 1.62.
  - Tight: text `clamp(1.08, 4.7, 1.48)`, line height 1.65; detail `clamp(0.9, 3.7, 1.04)`, line height 1.5.
- Ruqyah (`fitCardText`): (scale, line-height reduction) steps (1, 0), (0.94, 0.12), (0.88, 0.24), (0.82, 0.34),
  (0.76, 0.44), (0.70, 0.54).
  - Native adds (0.66, 0.54) and (0.62, 0.54): iOS sets these pages about one step taller than Chromium, and
    without them some pages scroll at wide spacing and large text on a 375 pt screen.
  - A platform that cannot set a line height below the font's natural height adds (0.58, 0.54) and (0.54, 0.54)
    as well. iOS before 26 does this.
- Acceptance: all 15 ruqyah pages fit without scrolling at the three text sizes, with comfortable and with wide
  line spacing, on a 375 × 667 pt screen (iOS `AutoFitUITests`).
- «سور» (`fitSuraPage`, `data-fit` 0…6): (scale, line-height factor) steps (1, 1), (0.94, 0.97), (0.88, 0.94),
  (0.82, 0.91), (0.76, 0.88), (0.70, 0.85), (0.64, 0.82). The text is the quran text size × scale, with line height
  `max(1.6, quran × factor)`; the basmala is the quran prefix size × scale, line height 1.7. A page that does not fit
  at the last step scrolls, as in the PWA.

**Overflow hint** (native addition; the PWAs show nothing because iOS Safari hides scroll bars). A card that
scrolls flashes its scroll indicator when it appears. While more than 1 pt of its content lies below the visible
area, it also shows:

- a fade over the bottom edge, 36 pt, from transparent to the card's background colour;
- a small capsule «المزيد» with a down chevron, `deck.more`. Tapping it scrolls to the end, animated unless
  Reduce Motion is on. It is spoken with the hint «يعرض بقية البطاقة».

Both disappear once the end of the content is in view, fading over 0.2 s (no animation with Reduce Motion), and
come back if the reader scrolls up again. A card that fits never shows them. The iOS test
`DeckRegressionUITests.testOverflowingCardShowsMoreUntilScrolledToTheEnd` covers this.

## 11. Arabic copy keys

These keys seed `content/ui-copy.json`, which does not exist yet (NATIVE_APP_PLAN.md §4.1). The existing keys follow the
PWAs' wording; index keys and the repeated-counter haptic note include the native contract. `{n}`, `{x}`, `{y}` are Arabic-Indic numbers.

| Key | Text |
| --- | --- |
| `deck.tab.morning` / `deck.tab.evening` / `deck.tab.ruqyah` | الصباح / المساء / رقية |
| `deck.section.morning` / `deck.section.evening` / `deck.section.ruqyah` | أذكار الصباح / أذكار المساء / رقية القرين |
| `deck.section.suwar` | سور |
| `deck.previous` / `deck.next` | السابق / التالي |
| `deck.position` | {n} من {m} |
| `deck.index.adhkar.title` / `.hint` | فهرس الورد / يعرض فهرس الورد للانتقال إلى ذكر |
| `deck.index.ruqyah.title` / `.hint` | فهرس الرقية / يعرض فهرس الرقية للانتقال إلى مقطع |
| `deck.index.suwar.title` / `.hint` | فهرس السورة / يعرض فهرس السورة للانتقال إلى صفحة |
| `deck.index.row.hint` | ينتقل إلى هذه البطاقة |
| `deck.index.lock` | يُتاح بعد إكمال {noun} {n} |
| `deck.hint.adhkar` | اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال. |
| `deck.hint.ruqyah` | اضغط على البطاقة بعد كل قراءة؛ واسحب للتنقل بين المقاطع. |
| `deck.sections.ruqyah` / `deck.cards.ruqyah` | اختيار السورة / مقاطع {surah} |
| `deck.cards.suwar` | صفحات {surah} |
| `card.single.pending` / `card.single.done` / `card.ruqyah.single.done` | اضغط بعد القراءة / تمت القراءة / تمت |
| `card.requirement.once` / `card.requirement.twice` / `card.requirement.times` | مرة واحدة / مرتان / {n} مرات |
| `card.target` | الهدف |
| `card.reset` | إعادة |
| `card.source` / `card.source.title` | المصدر والتفاصيل / المصدر والتفاصيل — الذكر {n} |
| `card.review` | بحاجة إلى مراجعة |
| `card.reset.confirm.adhkar.title` / `.message` | إعادة عداد الذكر {n}؟ / سيعود العداد من {x} إلى الصفر. |
| `card.reset.confirm.ruqyah.title` / `.message` | إعادة العداد؟ / سيعود عداد {surah} {range} إلى الصفر. |
| `deck.more` / `deck.more.hint` | المزيد / يعرض بقية البطاقة |
| `summary.adhkar.progress` / `.done` / `.manual` | {x} من {y} ذكرًا / اكتملت {section} اليوم / اكتملت {section} خارج التطبيق |
| `summary.ruqyah.progress` / `.done` / `.label` | {x} من {y} تكرارًا / اكتملت {surah} اليوم / {surah}: {x} من {y} تكرارًا |
| `summary.ruqyah.today.pending` / `.done` | رقية اليوم: {x} من {y} تكرارًا / تمت رقية اليوم في {time} |
| `summary.ruqyah.list.label` | تقدم رقية اليوم: {x} من {y} تكرارًا |
| `summary.suwar.progress` / `.done` / `.label` | {x} من {y} صفحة / اكتملت {surah} اليوم / {surah}: {x} من {y} صفحة مقروءة |
| `summary.suwar.list` / `.label` | {x} من {y} سور / سور اليوم: {x} من {y} سور مكتملة |
| `completion.adhkar.title` / `.message` / `.time` | اكتملت {section} بحمد الله / تم حفظ إكمال اليوم محليًا على هذا الجهاز. / وقت الإكمال: {time} |
| `completion.adhkar.done` / `.switch` | تم / الانتقال إلى {otherSection} |
| `completion.ruqyah.title` / `.message` | تمت الرقية بحمد الله / اكتملت جميع المقاطع بتكراراتها. |
| `completion.ruqyah.close` / `.restart` | إغلاق / بدء رقية جديدة |
| `completion.ruqyah.sura.title` / `.message` | اكتملت قراءة {surah} بحمد الله / تم حفظ إكمال اليوم محليًا على هذا الجهاز. |
| `completion.ruqyah.sura.done` / `.switch` | تم / الانتقال إلى {nextSurah} |
| `completion.suwar.title` / `.message` / `.done` | اكتملت قراءة {surah} بحمد الله / تم حفظ إكمال اليوم محليًا على هذا الجهاز. / تم |
| `reset.title` / `reset.copy` | ما الذي تريد إعادته؟ / اختر نطاق الإعادة. لا يُرسل شيء خارج هذا الجهاز. |
| `reset.day` / `.detail` | تقدم اليوم / إعادة عدادات اليوم فقط مع بقاء السجل كما هو. |
| `reset.week` / `.detail` | هذا الأسبوع / إعادة عدادات اليوم وحذف سجل آخر سبعة أيام. |
| `reset.everything` / `.detail` | كل شيء / إعادة العدادات وحذف السجل كاملًا. |
| `reset.confirm.week.title` / `.message` | حذف سجل هذا الأسبوع؟ / ستُعاد عدادات اليوم، وسيُحذف {سجل N من آخر أسبوع \| سجل آخر سبعة أيام}. لا يمكن التراجع. |
| `reset.confirm.everything.title` / `.message` | حذف كل شيء؟ / ستُعاد العدادات وسيُحذف السجل كاملًا{ (N)}. لا يمكن التراجع. |
| `reset.confirm` / `common.cancel` | إعادة / إلغاء |
| `reset.done.day` / `.week` / `.everything` | أُعيدت عدادات اليوم / حُذف سجل آخر سبعة أيام / حُذف السجل كاملًا |
| `longOrder.prompt.title` | تأجيل الأذكار الطويلة؟ |
| `longOrder.prompt.message` | بعض الأذكار تُكرَّر عشر مرات فأكثر، مثل التهليل والتسبيح والاستغفار. هل تفضّل قراءتها في آخر الورد قبل الذكر الأخير؟ يمكنك تغيير ذلك لاحقًا من الإعدادات. |
| `longOrder.prompt.keep` / `.accept` | لا، أبقِ الترتيب / نعم، أخّرها |
| `longOrder.setting` / `.note` | تأخير الأذكار الطويلة / الأذكار التي تُكرَّر ١٠ مرات فأكثر تُقرأ في آخر الورد قبل الذكر الأخير، دون تغيير أرقامها ولا عدّاداتها. |
| `longOrder.done.on` / `.off` | ستُقرأ الأذكار الطويلة قبل الذكر الأخير / عاد ترتيب الأذكار كما هو |
| `manual.title` / `manual.note` | إكمال الورد يدويًا / فعّله إذا أكملت الورد خارج التطبيق. سيُسجل كمكتمل ويوقف تذكيره اليوم، ثم يُعاد تلقائيًا غدًا. لا تتغير العدادات، ويمكنك تصفح بطاقات الورد بحرية. |
| `manual.status.counters` / `.manual` / `.none` | اكتملت داخل التطبيق / اكتملت خارج التطبيق / لم تُسجل كمكتملة |
| `manual.done.on` / `.off` / `.locked` | سُجلت {section} مكتملة خارج التطبيق / أُلغي الإكمال اليدوي لـ{section} / {section} مكتملة داخل التطبيق |
| `haptics.setting` / `.note` | الاهتزاز عند إكمال العداد / اهتزاز لمدة ٤٥ مللي ثانية عند إكمال عداد يتطلب التكرار أكثر من مرة، وعند اكتمال تكرار كل مقطع من الرقية، وعند قراءة كل صفحة من السور، وعند بلوغ هدف المسبحة وكل دورة بعده. |
| `tab.completeSuffix` | ، مكتملة اليوم |
| `header.reset.label` / `header.settings.label` | خيارات الإعادة / فتح الإعدادات |
