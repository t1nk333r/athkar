# «مسبحة»

The athkar PWA's counter (`#tasbih`, `athkar-tasbih-v1`), opened from أخرى. It is not a deck: it has no cards and
no summary bar, and [`deck-definition.md`](deck-definition.md) applies only where this document says so. iOS builds
`TasbihView` and `TasbihModel` in `ios/Athkar/Tasbih/`. PWA function names are given in backticks; the copy is the
PWA's, verbatim. Storage is in [`../schema.md`](../schema.md) (`tasbih_counts`, the three `tasbih_*` settings, and
"Tasbih counts and reset").

The text rules are ported exactly in `TasbihText`: `tasbihMatchKey`, `cleanTasbihPhrase`, `findTasbihPhrase`,
`tasbihIdentity`, `parseTasbihTarget` and `tasbihStatusText`. Strings are read as UTF-16 code units, as JavaScript
reads them, and whitespace is JavaScript's `\s`. [`fixtures/tasbih-text.json`](fixtures/tasbih-text.json) records
what the PWA returns, and `TasbihTextTests` holds the native port to it.

## 1. Screen

- The أخرى row «مسبحة» (`other.tasbih`) shows today's total, «اليوم: N».
- Two chips above the card:
  - The phrase (`tasbih.phrase`), spoken «اختيار الذكر، الحالي: <short>», opens «اختيار الذكر» (§3).
  - The target (`tasbih.target`), «الهدف: T» or «بلا هدف», spoken «تغيير الهدف، الحالي: T» or «…: بلا هدف», opens
    «الهدف» (§4).
- The card shows the phrase with its tashkeel, a ring with the count, and the status line (`tasbih.status`). A tap
  anywhere on it counts: the whole card is one button (`tasbih.surface`), spoken «أضف واحدًا» with the value
  `tasbihSrSummary`, «<short>، N من T» or «<short>، N، بلا هدف». The hint under the controls reads «اضغط في أي مكان
  من البطاقة للعدّ».
- The controls: «تراجع» (`tasbih.undo`, spoken «تراجع عن العدّة الأخيرة»), the total «اليوم: N» (`tasbih.total`,
  spoken «مجموع المسبحة اليوم: N») and «↻ إعادة» (`tasbih.reset`, spoken «إعادة عدّ <short> إلى الصفر»). «تراجع» and
  «إعادة» are disabled at zero.
- `<short>` is the phrase without tashkeel (`tasbihPhrase`).

## 2. Counting

- **Add** (`addTasbihCount`): one more for the phrase on screen. At 99,999 (`tasbihMaxCount`) nothing is counted,
  and «بلغت الحد الأقصى للعدّ» is announced once, until the count is below the cap again or another phrase is shown.
- **Target T.** Counting continues past T in laps. Every multiple of T plays the haptic (when the haptics setting
  is on), makes the count breathe, and is announced at once: «بلغت الهدف: T، <short>» at T, «اكتملت الدورة K» at
  K × T. Any other count is announced once taps pause for a second: «N من T», or «N» without a target.
- **Ring.** The fraction of the current lap, ((N − 1) mod T + 1) / T, so a whole lap is a full ring. The tap after a
  full lap sets the ring at once, never sweeping back; with Reduce Motion it never animates. Without a target the
  ring stays empty.
- **Status** (`tasbihStatusText`): «الهدف T» at zero, «N من T» below T, «بلغت الهدف ✓» at T, «الدورة K: R من T»
  within lap K, «اكتملت الدورة K ✓» at its end; «بلا هدف» without a target.
- **Undo** (`undoTasbihCount`): one less, «تراجع، العدد N»; nothing at zero.
- **«إعادة»** (`requestTasbihReset`) always asks: «إعادة عدّ <short>؟» / «سيعود عدّ هذا الذكر اليوم من N إلى الصفر،
  ويُنقص من مجموع اليوم.», with «إعادة» and «إلغاء». Confirmed, today's count of the phrase is zero and «أُعيد عدّ
  <short> إلى الصفر» is announced; other phrases keep theirs.
- **The day's order.** A phrase's first count of the day puts it last (`firstUse`). A count back at zero removes the
  phrase from the day, so its next count puts it last again.

## 3. Phrases («اختيار الذكر»)

- «أذكار مقترحة»: the eight presets (`tasbihPresets`), in this order and with these stored IDs: `subhan`, `hamd`,
  `takbir`, `tahlil`, `istighfar`, `subhan-bihamdih`, `hawqala`, `salawat` (`tasbih.preset.<id>`).
- «عباراتك»: the saved phrases, newest first, each with «×» (`tasbih.custom.<n>`, `tasbih.custom.<n>.delete`,
  spoken «حذف العبارة: <phrase>»).
- A row shows today's count when it is not zero and is spoken «<short>، اليوم N»; the phrase counted is selected.
- «عبارة جديدة»: «اكتب الذكر» (`tasbih.custom.input`, at most 60 UTF-16 code units), «إضافة»
  (`tasbih.custom.add`, disabled until the text cleans to something) and «تُحفظ العبارة على هذا الجهاز لتختارها
  لاحقًا.». With eight saved, «يمكن حفظ ٨ عبارات. احذف واحدة لإضافة غيرها.» (`tasbih.custom.limit`) replaces it.
- **Choosing** (`selectTasbihPhrase`) stores the phrase and announces «الذكر: <short>، العدد N». Choosing or adding
  closes the sheet; deleting keeps it open.
- **Adding** (`addTasbihPhrase`) saves the cleaned spelling (`cleanTasbihPhrase`). A phrase that names a preset or a
  saved phrase (`findTasbihPhrase`) chooses it instead. A new one is saved first and chosen, and «أُضيفت العبارة:
  <phrase>» is announced.
- **Deleting** (`deleteTasbihPhrase`) removes the phrase from the list only: its counts, today and before, stay in
  the totals and come back if it is saved again. When it was the phrase counted, «سبحان الله» is. «حُذفت العبارة:
  <phrase>» is announced.

## 4. Target («الهدف»)

«يتواصل العدّ بعد بلوغ الهدف.», then «بلا هدف» (`tasbih.target.none`), ٣٣, ١٠٠ (`tasbih.target.33`, `.100`) and
«عدد آخر» (`tasbih.target.custom`): a number from 1 to 9999 in Arabic-Indic, Persian or Latin digits
(`parseTasbihTarget`, at most five characters, `tasbih.target.input` and «حفظ» `tasbih.target.save`). Anything else
shows and announces «أدخل عددًا من ١ إلى ٩٩٩٩.» (`tasbih.target.error`). «إلغاء» (`tasbih.target.cancel`) closes
it. A new target never changes a count and plays no haptic; «الهدف: T» or «بلا هدف» is announced.

## 5. Day

- The counter rolls with the decks (deck-definition §9): the new day shows that day's counts, and the phrase,
  target and saved phrases stay.
- A tap after midnight first rolls, then counts on the new day, as the PWA's `ensureCurrentDay` runs before
  `addTasbihCount`. The decks ignore that tap instead, because it belongs to the previous day's card; the counter
  has no card. A new day that cannot be read is not shown and the tap is not counted: the counter keeps its day
  until a later roll reads it.

## 6. Scoped reset

The header's «⋯» → «إعادة» resets «مسبحة» alone, as each deck resets alone (deck-definition §8). It is enabled
when a phrase is counted today or an earlier day has a count (`tasbihHasResettableState`).

| Choice | «مسبحة» | Asks first |
| --- | --- | --- |
| «تقدم اليوم» | No phrase is counted today (`resetTasbihProgress`). | No |
| «هذا الأسبوع» | The day reset, plus the counts dated in the last 7 local dates (`deleteTasbihHistory`). | Yes |
| «كل شيء» | The day reset, plus every count. | Yes |

The confirmations count the earlier days with a count (`tasbihState.history`). The phrase counted, the target and
the saved phrases are preferences: no reset changes them.

## 7. Native differences

- **Storage.** Each date keeps its own rows, and nothing is trimmed (`schema.md`); there are no reset epochs and no
  transfer. Backup envelope v1 does not carry `athkar-tasbih-v1` (NATIVE_APP_PLAN.md §10.4), so nothing is imported.
- **Clock moved back.** The PWA sums the counts of a later stored date, and of later history days, into today
  (`rollTasbihStateToDate`). The native counter shows each date's own rows.
- **Spellings.** The PWA merges the keys of one phrase (`tasbihIdentity`) each time it loads
  (`canonicalTasbihDays`). Native stores only the spelling it saved, and when a phrase is added, the counts an
  earlier spelling kept move to it on every date, summed up to 99,999 with the earlier first use. A date never holds
  two keys for one phrase.
- **Keys** compare as UTF-16 code units, as JavaScript compares them. Swift's `==` would also equate two spellings
  whose tashkeel is only ordered differently, which the PWA keeps apart.
- **The 60-unit cut.** Where it would split a surrogate pair, the PWA keeps the pair's first half alone; native
  drops it, so no saved phrase holds a lone surrogate.
- **The header reset** resets «مسبحة» alone; the PWA's clears every store at once.

## 8. Tests

- Linux: `TasbihTextTests` (the fixture), `TasbihModelTests`, `TasbihPersistenceTests` (real SQLite failures),
  `DayRolloverTests`; in AthkarCore, `StorageRepositoryTests`, `StorageMigrationTests` and `StorageSchemaTests`.
- Mac only: `TasbihUITests`. `tools/ios-mac-run.sh` selects it when the files it checks change.
