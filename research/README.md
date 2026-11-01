# Research reports

Each report answers one research ticket and records what was true on the day it was written. Its `index.html` line
numbers and statements about shipped behaviour are a snapshot. Later decisions supersede parts of them:

| Report | Ticket | Written | Superseded by |
| --- | --- | --- | --- |
| [`ios-version-floor.md`](ios-version-floor.md) | #5 | 2026-09-23 | The app ships with `deploymentTarget: iOS 17.0` (`ios/project.yml`), the floor `NATIVE_APP_PLAN.md` §11 item 3 recommends; #6 closed it as settled in practice, and the plan item still reads as a recommendation. |
| [`prayer-authority-tables.md`](prayer-authority-tables.md) | #9 | 2026-09-23 | The default method for an unset choice is Umm al-Qura below 48° and MWL beyond (`spec/prayer-times/README.md`, "Default method", 2026-09-26). Launch regions remain open in #10. |
| [`adhkar-quran-edition.md`](adhkar-quran-edition.md) | #11 | 2026-09-23 | R6 (adhkar 1.1.0) moved the ten Quran items to the Uthmani edition (`content/REVIEW.md`, `NATIVE_APP_PLAN.md` §11 item 8; decided in #12); R7 (adhkar 1.1.1) returned the al-Baqarah 201 dua (`morning-26`, `evening-24`) to the simplified text, so today eight of the ten are Uthmani. R5 corrected the hamza of «يَؤُودُهُ» and R6 fixed both Ayat al-Kursi points the report found, restoring the ۚ mark (#15). |
