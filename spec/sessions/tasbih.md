# «مسبحة»

This document describes the athkar PWA's counter (`#tasbih`, `athkar-tasbih-v1`), opened from أخرى. The counter is
not a deck. It has no cards and no summary bar, and [`deck-definition.md`](deck-definition.md) applies only where
this document says so. iOS builds `TasbihView` and `TasbihModel` in `ios/Athkar/Tasbih/`. PWA function names are
given in backticks; the copy is the PWA's, verbatim. Storage is in [`../schema.md`](../schema.md) (`tasbih_counts`,
the three `tasbih_*` settings, and "Tasbih counts and reset").

The text rules are ported exactly in `TasbihText`: `tasbihMatchKey`, `cleanTasbihPhrase`, `findTasbihPhrase`,
`tasbihIdentity`, `parseTasbihTarget` and `tasbihStatusText`. Strings are read as UTF-16 code units, as JavaScript
reads them, and whitespace is JavaScript's `\s`. [`fixtures/tasbih-text.json`](fixtures/tasbih-text.json) records
what the PWA returns, and `TasbihTextTests` checks the native port against it.

## 1. Screen

- The أخرى row «مسبحة» (`other.tasbih`) shows today's total, «اليوم: N».
- Two chips sit above the card:
  - The phrase (`tasbih.phrase`), spoken «اختيار الذكر، الحالي: <short>», opens «اختيار الذكر» (§3).
  - The target (`tasbih.target`) shows «الهدف: T» or «بلا هدف», is spoken «تغيير الهدف، الحالي: T» or «…: بلا هدف»,
    and opens «الهدف» (§4).
- The card shows the phrase with its tashkeel, a ring with the count, and the status line (`tasbih.status`). A tap
  anywhere on it counts. The whole card is one button (`tasbih.surface`), spoken «أضف واحدًا» with the value
  `tasbihSrSummary`, «<short>، N من T» or «<short>، N، بلا هدف». The hint under the controls reads «اضغط في أي مكان
  من البطاقة للعدّ».
- The controls are «تراجع» (`tasbih.undo`, spoken «تراجع عن العدّة الأخيرة»), the total «اليوم: N» (`tasbih.total`,
  spoken «مجموع المسبحة اليوم: N») and «↻ إعادة» (`tasbih.reset`, spoken «إعادة عدّ <short> إلى الصفر»). «تراجع» and
  «إعادة» are disabled at zero.
- `<short>` is the phrase without tashkeel (`tasbihPhrase`).

## 2. Counting

- **Add** (`addTasbihCount`) counts one more for the phrase on screen. At 99,999 (`tasbihMaxCount`) nothing is
  counted, and «بلغت الحد الأقصى للعدّ» is announced once, until the count is below the cap again or another phrase
  is shown.
- **Target T.** Counting continues past T in laps. Every multiple of T plays the haptic (when the haptics setting
  is on), briefly enlarges the count, and is announced at once: «بلغت الهدف: T، <short>» at T, «اكتملت الدورة K» at
  K × T. Any other count is announced once taps pause for a second: «N من T», or «N» without a target.
- **Ring.** The fraction of the current lap, ((N − 1) mod T + 1) / T, so a whole lap is a full ring. The tap after a
  full lap sets the ring at once; it never sweeps back. With Reduce Motion the ring never animates. Without a target
  the ring stays empty.
- **Status** (`tasbihStatusText`) is «الهدف T» at zero, «N من T» below T, «بلغت الهدف ✓» at T, «الدورة K: R من T»
  within lap K, «اكتملت الدورة K ✓» at its end; «بلا هدف» without a target.
- **Undo** (`undoTasbihCount`) counts one less and announces «تراجع، العدد N»; it does nothing at zero.
- **«إعادة»** (`requestTasbihReset`) always asks: «إعادة عدّ <short>؟» / «سيعود عدّ هذا الذكر اليوم من N إلى الصفر،
  ويُنقص من مجموع اليوم.», with «إعادة» and «إلغاء». Once confirmed, today's count of the phrase is zero and «أُعيد
  عدّ <short> إلى الصفر» is announced; other phrases keep their counts.
- **The day's order.** A phrase's first count of the day puts it last (`firstUse`). A count back at zero removes the
  phrase from the day, so its next count puts it last again.

## 3. Phrases («اختيار الذكر»)

- «أذكار مقترحة»: the eight presets (`tasbihPresets`), in this order and with these stored IDs: `subhan`, `hamd`,
  `takbir`, `tahlil`, `istighfar`, `subhan-bihamdih`, `hawqala`, `salawat` (`tasbih.preset.<id>`).
- «عباراتك»: the saved phrases, newest first, each with «×» (`tasbih.custom.<n>`, `tasbih.custom.<n>.delete`,
  spoken «حذف العبارة: <phrase>»).
- A row shows today's count when it is not zero and is spoken «<short>، اليوم N»; the phrase counted is selected.
- «عبارة جديدة»: «اكتب الذكر» (`tasbih.custom.input`, at most 60 UTF-16 code units), «إضافة»
  (`tasbih.custom.add`, disabled until the cleaned text is not empty) and «تُحفظ العبارة على هذا الجهاز لتختارها
  لاحقًا.». With eight saved, «يمكن حفظ ٨ عبارات. احذف واحدة لإضافة غيرها.» (`tasbih.custom.limit`) replaces it,
  and the typed text is cleared, as `addTasbihPhrase` clears it at the limit.
- **Choosing** (`selectTasbihPhrase`) stores the phrase and announces «الذكر: <short>، العدد N». Choosing or adding
  closes the sheet; deleting keeps it open.
- **Adding** (`addTasbihPhrase`) saves the cleaned spelling (`cleanTasbihPhrase`). A phrase that names a preset or a
  saved phrase (`findTasbihPhrase`) chooses it instead. A new one is saved first and chosen, and «أُضيفت العبارة:
  <phrase>» is announced.
- **Deleting** (`deleteTasbihPhrase`) removes the phrase from the list only. Its counts, today and before, stay in
  the totals and come back if it is saved again. When it was the phrase counted, «سبحان الله» becomes the phrase
  counted. «حُذفت العبارة: <phrase>» is announced.

## 4. Target («الهدف»)

«يتواصل العدّ بعد بلوغ الهدف.», then «بلا هدف» (`tasbih.target.none`), ٣٣, ١٠٠ (`tasbih.target.33`, `.100`) and
«عدد آخر» (`tasbih.target.custom`), which takes a number from 1 to 9999 in Arabic-Indic, Persian or Latin digits
(`parseTasbihTarget`, at most five characters, `tasbih.target.input` and «حفظ» `tasbih.target.save`). For any other
input, the app shows and announces «أدخل عددًا من ١ إلى ٩٩٩٩.» (`tasbih.target.error`). «إلغاء»
(`tasbih.target.cancel`) closes it. A new target never changes a count and plays no haptic; «الهدف: T» or
«بلا هدف» is announced.

## 5. Day

- The counter rolls over with the decks (deck-definition §9). The new day shows that day's counts, and the phrase,
  target and saved phrases stay.
- A tap after midnight first rolls the day over, then counts on the new day, as the PWA's `ensureCurrentDay` runs
  before `addTasbihCount`. The decks ignore that tap instead, because it belongs to the previous day's card; the
  counter has no card. A new day that cannot be read is not shown, and the tap is not counted. The counter keeps its
  day until a later rollover reads the new one.

## 6. Scoped reset

The header's «⋯» menu item «إعادة» resets «مسبحة» alone, as each deck resets alone (deck-definition §8). It is
enabled when a phrase is counted today or an earlier day has a count (`tasbihHasResettableState`).

| Choice | «مسبحة» | Asks first |
| --- | --- | --- |
| «تقدم اليوم» | No phrase is counted today (`resetTasbihProgress`). | While a phrase is counted today |
| «هذا الأسبوع» | The day reset, plus the counts dated in the last 7 local dates (`deleteTasbihHistory`). | Yes |
| «كل شيء» | The day reset, plus every count. | Yes |

Today's counts cannot be rebuilt, so «تقدم اليوم» asks while a phrase is counted today (`resetDayButton`):
«إعادة تقدم اليوم؟» / «ستُعاد عدادات المسبحة اليوم (N)، مع بقاء السجل كما هو. لا يمكن التراجع.», where N is the
day's total. With nothing counted today, it resets at once. The week and everything confirmations count the earlier
days with a count (`tasbihState.history`). The phrase counted, the target and the saved phrases are preferences, and
no reset changes them.

## 7. Native differences

- **Storage.** Each date keeps its own rows, and nothing is trimmed (`schema.md`); there are no reset epochs and no
  transfer. Backup envelope v1 does not carry `athkar-tasbih-v1` (NATIVE_APP_PLAN.md §10.4), so nothing is imported.
- **Clock moved back.** The PWA sums the counts of a later stored date, and of later history days, into today
  (`rollTasbihStateToDate`). The native counter shows each date's own rows.
- **Spellings.** The PWA merges the keys of one phrase (`tasbihIdentity`) each time it loads
  (`canonicalTasbihDays`). Native stores only the spelling it saved. When a phrase is added, the counts an earlier
  spelling kept move to the new spelling on every date. They are summed up to 99,999, and the earlier first use is
  kept. A date never holds two keys for one phrase.
- **Keys** compare as UTF-16 code units, as JavaScript compares them. Swift's `==` would also equate two spellings
  whose tashkeel is only ordered differently, which the PWA keeps apart.
- **The 60-unit cut.** Where it would split a surrogate pair, the PWA keeps the pair's first half alone; native
  drops it, so no saved phrase holds a lone surrogate.
- **The header reset** resets «مسبحة» alone; the PWA's clears every store at once. Its «تقدم اليوم» question
  therefore names the counter alone. The PWA asks «ستُعاد عدادات اليوم، ومنها المسبحة (N)، …».
- **VoiceOver focus** follows the PWA's. «اختيار الذكر» opens on the phrase counted (`openTasbihPhraseSheet`) and
  «الهدف» on the pressed option (`openTasbihTargetDialog`). After a delete, focus moves to the saved phrase now in
  that place, or the one before it, or «اكتب الذكر» once none is left (`deleteTasbihPhrase`).

## 8. Tests

- Linux: `TasbihTextTests` (the fixture), `TasbihModelTests`, `TasbihPersistenceTests` (real SQLite failures),
  `DayRolloverTests`; in AthkarCore, `StorageRepositoryTests`, `StorageMigrationTests` and `StorageSchemaTests`.
- Mac only: `TasbihUITests`. `tools/ios-mac-run.sh` selects it when the files it checks change.
