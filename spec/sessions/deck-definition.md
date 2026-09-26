# Deck definition

The card-deck screen shared by the three decks: أذكار الصباح, أذكار المساء and رقية القرين
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
| `ruqyah` | `content/ruqyah.v1.json` → `segments` (15 segments, 33 readings) | Pack order, never reordered | Own session |

A **card's number** is its 1-based position in content order, in Arabic-Indic digits. Long-order never changes
it. **Positions** («٢ من ٢٦») are 1-based positions in the deck as currently ordered.

The screen has three tabs in this order: الصباح, المساء, أخرى. The first two open their adhkar deck. أخرى opens a
list of sections (رقية القرين, أذكار النوم, أذكار بعد الصلاة, أذكار الاستيقاظ, أوقات الصلاة, القبلة); رقية القرين
and أوقات الصلاة open, and the others are listed as «قريبًا». A deck row shows the deck's summary copy, and «✓»
once today is complete; the أوقات الصلاة row shows the next prayer and its time, or «حدّد موقعك لعرض المواقيت». While a section is open, the header title is replaced by a back button with the section's
title, and tapping أخرى again also returns to the list. The list has no summary and the reset button is disabled.
The أخرى tab never shows «✓»; completion is shown per row. Each deck keeps its current card while another is shown.

### Adhkar item fields

The card reads these item fields:

- `id`, `kind` (`quran` | `dhikr` | `review`), `text`, `prefix?`, `details[]`
- `count?`, `countLabel?`, `targetOptions?`, `defaultTarget?`, `noteIndex?`
- `reviewTitle?`, `reviewCopy?` (review items)

Presentation:

- `prefix` is centred above the text.
- `quran` items use KFGQPC Uthman Taha Naskh for the prefix and text. Other items use the platform's Arabic
  Naskh/system face.
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

## 2. Counters

### Adhkar (`targetForState`, `countForState`)

- **Target.**
  - If the item has `targetOptions` (and `defaultTarget`), the target is the stored target when it equals one of
    the options, otherwise `defaultTarget`.
  - Otherwise the target is `count`, or 1 when `count` is absent or 0.
  - Chosen targets are stored per (date, period, item). A new day starts at the default target.
- **Count.** The stored count, `floor`ed. It is 0 when not finite or negative. It is then clamped to
  `min(count, target)`. Storage keeps raw values.
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
- **Progress.** The sum of counts, out of the sum of `repeat` (33).

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
  - Ruqyah: the first incomplete segment, or 0 when all are complete.
- **Back** («السابق», and a swipe back) is enabled when `index > 0`.
- **Forward** («التالي», and a swipe forward) is enabled when `index < count − 1`, and additionally:
  - Adhkar: the current item is complete, or is a review item, or the period is manually complete (the lock).
  - Ruqyah: no other condition; never locked.
- **Position.** Shown as «N من M». Spoken as «الذكر N من M» for adhkar and «المقطع N من M» for ruqyah, and
  announced after every navigation.
- **Hint below the controls.** `deck.hint.adhkar` or `deck.hint.ruqyah`.

## 5. Tap to count

The whole card is the tap target. The reset button, the target picker and the source link sit above it and
receive their own taps.

A tap does nothing when:

- the card is complete (the tap target is disabled), or
- it lands within 450 ms of the end of a horizontal swipe, or
- the local date changed since the last check. The rollover runs first and the tap is ignored.

Otherwise:

1. `count += 1`, and the new count is saved.
2. If the card just reached its target, play the completion haptic: 45 ms, only when `haptics` is true.
3. **Adhkar:** run `syncCompletionState(period)`. If it returns `newlyCompleted`, open the completion dialog and
   do not auto-advance. Otherwise, if the card just completed, auto-advance.
4. **Ruqyah:**
   - If every segment is now complete, record today as complete (once; the first completion time is kept) and
     open the completion dialog. This also happens when today was already recorded.
   - Otherwise, if the segment just completed, auto-advance.
5. Announce the card's counter label (§9).

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

**Card reset.** Enabled when `count > 0`. It sets `count = 0` and then runs `syncCompletionState` (adhkar) or saves
the segment (ruqyah).

- Adhkar asks first only when `target >= 50`:
  - Title: `card.reset.confirm.adhkar.title` («إعادة عداد الذكر N؟»).
  - Message: `…message` («سيعود العداد من X إلى الصفر.»).
  - Confirm button: «إعادة».
- Ruqyah always asks: `card.reset.confirm.ruqyah.*`.

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

The tab (adhkar) or the أخرى row (ruqyah) shows «✓» and is spoken «<section>، مكتملة اليوم».

### Ruqyah

- The day is complete once every segment is complete. It is recorded in `ruqyah_days` once.
- The dialog shows `completion.ruqyah.title` and `completion.ruqyah.message`, with the buttons
  `completion.ruqyah.close` and `completion.ruqyah.restart`. «بدء رقية جديدة» is a day reset (§8); today stays
  recorded.
- Its أخرى row shows «✓» once today is recorded.

## 8. Scoped reset

The header button «↻ إعادة», spoken «خيارات الإعادة», opens a picker for the pillar on screen. Both adhkar periods
reset together; ruqyah resets alone. The button first runs the day rollover.

It is enabled when:

- **Adhkar** (`hasResettableState`): any non-review count > 0 in either period, or any manual completion, or any
  earlier completed day.
- **Ruqyah:** today's readings > 0, or any recorded day.

| Choice | Adhkar | Ruqyah | Asks first |
| --- | --- | --- | --- |
| «تقدم اليوم» | Today's counts, `completedAt` and manual flags cleared; chosen targets kept. | Today's counts set to 0; today's record kept. | No |
| «هذا الأسبوع» | Day reset, plus every adhkar record dated in the last 7 local dates (today included) deleted. | Day reset, plus recorded days in the last 7 local dates (today included) deleted. | Yes |
| «كل شيء» | Day reset, plus every adhkar record deleted. | Day reset, plus every recorded day deleted. | Yes |

After any reset, every deck of the pillar goes back to card 1.

The confirmations use `reset.confirm.week.*` and `reset.confirm.everything.*`, with the recorded-day count `N` from
`dayCountLabel`:

- `dayCountLabel(N)` is: 1 → «يوم واحد», 2 → «يومين», 3–10 → «N أيام», 11 and more → «N يومًا».
- Adhkar counts earlier days with a completion. Ruqyah counts recorded days, today included.

The storage for all of this is in `spec/schema.md`.

## 9. Summary, day rollover, accessibility

**Summary above the deck** (`updateSessionProgress`):

- Adhkar:
  - «N من M ذكرًا» (M = non-review items; the suffix is «ذكرًا متاحًا» when the morning has a review item).
  - «اكتملت <section> اليوم» when complete by counters.
  - «اكتملت <section> خارج التطبيق» when manually complete.
  - The progress bar is full when the period is complete.
- Ruqyah:
  - «N من ٣٣ تكرارًا».
  - A second line: «رقية اليوم لم تكتمل بعد.», or «تمت رقية اليوم في h:mm.» once today is recorded.

**Day rollover.** Runs at local midnight, on returning to the foreground, on a clock or time-zone change, and
before each tap, card reset (including a confirmed one) and target change. When that check finds a new date, the
tap, reset or target change is dropped: it belonged to the previous day's card.

- A new local date loads that date's rows, and each deck opens on its first unread card.
- Nothing is deleted. The previous day is already history.

**Labels to speak.** These are the PWAs' live-region strings; announce them after the change.

- Adhkar counter (`progressLabel`):
  - Counted items: «ذكر N، تم تكراره X من أصل Y مرات», with «، اكتمل» added when complete.
  - Other items: «ذكر N، لم يُعلَّم كمقروء», or «ذكر N، تمت قراءته» once read.
- Adhkar tap target:
  - Counted items: «زيادة عداد الذكر N. <label>».
  - Other items: «تحديد كمقروء، الذكر N. <label>», or «اكتمل، الذكر N. <label>» once read.
- Ruqyah counter (`segmentLabel`): «المقطع N: <surah> <range>. <status>». The status is «لم تُقرأ بعد» or «تمت
  القراءة» when repeat is 1, and «تم X من Y» otherwise.
- Ruqyah tap target: «تسجيل قراءة المقطع N. <label>», or «اكتمل. <label>» once complete.
- Reset buttons: «إعادة عداد الذكر N» / «إعادة عداد المقطع N».
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

These keys seed `content/ui-copy.json`, which does not exist yet (NATIVE_APP_PLAN.md §4.1). The strings are the
PWAs' wording, verbatim. `{n}`, `{x}`, `{y}` are Arabic-Indic numbers.

| Key | Text |
| --- | --- |
| `deck.tab.morning` / `deck.tab.evening` / `deck.tab.ruqyah` | الصباح / المساء / رقية |
| `deck.section.morning` / `deck.section.evening` / `deck.section.ruqyah` | أذكار الصباح / أذكار المساء / رقية القرين |
| `deck.previous` / `deck.next` | السابق / التالي |
| `deck.position` | {n} من {m} |
| `deck.hint.adhkar` | اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال. |
| `deck.hint.ruqyah` | اضغط على البطاقة بعد كل قراءة؛ واسحب للتنقل بين المقاطع. |
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
| `summary.ruqyah.progress` / `.pending` / `.done` | {x} من {y} تكرارًا / رقية اليوم لم تكتمل بعد. / تمت رقية اليوم في {time}. |
| `completion.adhkar.title` / `.message` / `.time` | اكتملت {section} بحمد الله / تم حفظ إكمال اليوم محليًا على هذا الجهاز. / وقت الإكمال: {time} |
| `completion.adhkar.done` / `.switch` | تم / الانتقال إلى {otherSection} |
| `completion.ruqyah.title` / `.message` | تمت الرقية بحمد الله / اكتملت جميع المقاطع بتكراراتها. |
| `completion.ruqyah.close` / `.restart` | إغلاق / بدء رقية جديدة |
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
| `haptics.setting` / `.note` | الاهتزاز عند إكمال الذكر / اهتزاز لمدة ٤٥ مللي ثانية عند إكمال الذكر. |
| `tab.completeSuffix` | ، مكتملة اليوم |
| `header.reset.label` / `header.settings.label` | خيارات الإعادة / فتح الإعدادات |
