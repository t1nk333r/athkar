# Research reports

Each report answers one research ticket and records what was true on the day it was written. Its `index.html` line
numbers and statements about shipped behaviour are a snapshot. Later decisions supersede parts of them:

| Report | Ticket | Written | Superseded by |
| --- | --- | --- | --- |
| [`ios-version-floor.md`](ios-version-floor.md) | #5 | 2026-09-23 | The app ships with `deploymentTarget: iOS 17.0` (`ios/project.yml`), the floor `NATIVE_APP_PLAN.md` §11 item 3 recommends; decided in #6. |
| [`prayer-authority-tables.md`](prayer-authority-tables.md) | #9 | 2026-09-23 | The default method for an unset choice is Umm al-Qura below 48° and MWL beyond (`spec/prayer-times/README.md`, "Default method", 2026-09-26). Launch regions remain open in #10. |
| [`adhkar-quran-edition.md`](adhkar-quran-edition.md) | #11 | 2026-09-23 | The adhkar Quran items moved to the Uthmani edition in adhkar 1.1.0 (`content/REVIEW.md` R6, `NATIVE_APP_PLAN.md` §11 item 8; decided in #12). R5 and R6 fixed both Ayat al-Kursi points the report found (#15): the shipped text no longer contains «يَؤُودُهُ». |
