import AthkarCore
import Foundation
import GRDB
import Testing

struct StorageRepositoryTests {
    let database: AppDatabase
    let t0 = Instant.at("2026-09-23T05:00:00.000Z")
    let t1 = Instant.at("2026-09-23T05:10:00.250Z")

    init() throws {
        database = try AppDatabase.inMemory()
    }

    @Test func adhkarSessionKeepsRawCountsTargetsAndCompletion() throws {
        let adhkar = database.adhkar
        try adhkar.setCount(250, for: "morning-20", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.setTarget(10, for: "morning-20", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.setTarget(33, for: "morning-21", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.setCount(3, for: "evening-02", on: "2026-09-23", period: .evening, at: t0)
        try adhkar.markComplete(on: "2026-09-23", period: .morning, origin: .manual, completedAt: t1)

        let morning = try adhkar.session(on: "2026-09-23", period: .morning)
        #expect(morning.progress == ["morning-20": 250])
        #expect(morning.targets == ["morning-20": 10, "morning-21": 33])
        #expect(morning.completion == AdhkarDay(localDate: "2026-09-23", period: .morning, completedAt: t1,
                                                completionOrigin: .manual))
        #expect(!morning.isEmpty)
        let evening = try adhkar.session(on: "2026-09-23", period: .evening)
        #expect(evening.progress == ["evening-02": 3])
        #expect(evening.completion == nil)
        #expect(try adhkar.session(on: "2026-09-24", period: .morning) == AdhkarSession(localDate: "2026-09-24",
                                                                                       period: .morning))

        // Clearing the only thing a row holds removes the row; clearing a target keeps the count.
        try adhkar.setTarget(nil, for: "morning-21", on: "2026-09-23", period: .morning, at: t1)
        try adhkar.setTarget(nil, for: "morning-20", on: "2026-09-23", period: .morning, at: t1)
        let cleared = try adhkar.session(on: "2026-09-23", period: .morning)
        #expect(cleared.progress == ["morning-20": 250])
        #expect(cleared.targets == [:])

        try adhkar.clearCompletion(on: "2026-09-23", period: .morning)
        #expect(try adhkar.days(from: "2026-09-01", through: "2026-09-30") == [])
    }

    @Test func adhkarResetProgressKeepsTargetsLikeThePWA() throws {
        let adhkar = database.adhkar
        try adhkar.setCount(2, for: "morning-01", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.setCount(5, for: "morning-20", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.setTarget(10, for: "morning-20", on: "2026-09-23", period: .morning, at: t0)
        try adhkar.markComplete(on: "2026-09-23", period: .evening, origin: .manual, completedAt: nil)
        try adhkar.markComplete(on: "2026-09-22", period: .evening, origin: .counters, completedAt: t0)

        try adhkar.resetProgress(on: "2026-09-23", at: t1)

        let morning = try adhkar.session(on: "2026-09-23", period: .morning)
        #expect(morning.progress == [:])
        #expect(morning.targets == ["morning-20": 10])
        #expect(morning.isEmpty)
        #expect(try adhkar.days(from: "2026-09-01", through: "2026-09-30").map(\.localDate) == ["2026-09-22"])
    }

    @Test func adhkarDaysAreMorningFirstAndDeleteRecordsHonourTheDateRange() throws {
        let adhkar = database.adhkar
        // Evening written first on purpose: the order must come from the period, not insertion or the alphabet.
        for date in ["2026-09-20", "2026-09-21", "2026-09-22"] {
            try adhkar.markComplete(on: date, period: .evening, origin: .counters, completedAt: t0)
            try adhkar.markComplete(on: date, period: .morning, origin: .counters, completedAt: t0)
            try adhkar.setCount(1, for: "morning-01", on: date, period: .morning, at: t0)
        }
        #expect(try adhkar.days(from: "2026-09-21", through: "2026-09-22").map { "\($0.localDate) \($0.period)" }
                == ["2026-09-21 morning", "2026-09-21 evening", "2026-09-22 morning", "2026-09-22 evening"])

        try adhkar.deleteRecords(from: "2026-09-21", through: "2026-09-22")
        #expect(try adhkar.days(from: "2026-09-01", through: "2026-09-30").map(\.localDate)
                == ["2026-09-20", "2026-09-20"])
        #expect(try adhkar.session(on: "2026-09-21", period: .morning).isEmpty)
        #expect(try adhkar.session(on: "2026-09-20", period: .morning).progress == ["morning-01": 1])
    }

    @Test func ruqyahCountsAndCompletion() throws {
        let ruqyah = database.ruqyah
        try ruqyah.setCount(1, for: "qaf-1-8", on: "2026-09-23", at: t0)
        try ruqyah.setCount(0, for: "nas-1-6", on: "2026-09-23", at: t0)
        try ruqyah.setCount(3, for: "qaf-1-8", on: "2026-09-23", at: t1)
        #expect(try ruqyah.counts(on: "2026-09-23") == ["qaf-1-8": 3, "nas-1-6": 0])
        #expect(try ruqyah.counts(on: "2026-09-22") == [:])

        try ruqyah.markComplete(on: "2026-09-23", completedAt: t1)
        #expect(try ruqyah.days(from: "2026-09-23", through: "2026-09-23")
                == [RuqyahDay(localDate: "2026-09-23", completedAt: t1, completionOrigin: .counters)])
        try ruqyah.clearCompletion(on: "2026-09-23")
        #expect(try ruqyah.days(from: "2026-09-01", through: "2026-09-30") == [])
    }

    /// The ruqyah PWA's `recordToday`: the first completion time of a day is kept.
    @Test func ruqyahCompletingReadingRecordsTheDayOnce() throws {
        let ruqyah = database.ruqyah
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-23", completingDayAt: t0, at: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-23", completingDayAt: t1, at: t1)
        #expect(try ruqyah.day(on: "2026-09-23")?.completedAt == t0)
        #expect(try ruqyah.day(on: "2026-09-22") == nil)
    }

    /// Day reset keeps today's completion (the PWA's "بدء رقية جديدة" and تقدم اليوم); week and everything remove
    /// completed days in their scope, today included.
    @Test func ruqyahScopedResets() throws {
        let ruqyah = database.ruqyah
        for day in ["2026-09-10", "2026-09-17", "2026-09-22", "2026-09-23"] {
            try ruqyah.markComplete(on: day, completedAt: t0)
        }
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-23", at: t0)
        try ruqyah.setCount(1, for: "qaf-1-8", on: "2026-09-22", at: t0)

        try ruqyah.resetCounts(on: "2026-09-23", at: t1)
        #expect(try ruqyah.counts(on: "2026-09-23") == ["nas-1-6": 0])
        #expect(try ruqyah.counts(on: "2026-09-22") == ["qaf-1-8": 1])
        #expect(try ruqyah.dayCount(.all) == 4)

        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        #expect(week == .dates(from: "2026-09-17", through: "2026-09-23"))
        #expect(try ruqyah.dayCount(week) == 3)
        try ruqyah.resetCounts(on: "2026-09-23", removing: week, at: t1)
        #expect(try ruqyah.days(from: "2026-09-01", through: "2026-09-30").map(\.localDate) == ["2026-09-10"])

        try ruqyah.resetCounts(on: "2026-09-23", removing: .all, at: t1)
        #expect(try ruqyah.dayCount(.all) == 0)
    }

    /// The ruqyah PWA's `applyOp`: a reading that completes a sura records it, once; the day is recorded only with
    /// `completingDayAt`, and each keeps its first time.
    @Test func ruqyahSuraCompletionIsRecordedOnceWithItsReading() throws {
        let ruqyah = database.ruqyah
        try ruqyah.setCount(7, for: "kafirun-1-6", on: "2026-09-23", completingSura: "kafirun", at: t0)
        try ruqyah.setCount(7, for: "kafirun-1-6", on: "2026-09-23", completingSura: "kafirun", at: t1)
        #expect(try ruqyah.suraDays(on: "2026-09-23") == ["kafirun": t0])
        #expect(try ruqyah.day(on: "2026-09-23") == nil)
        #expect(try ruqyah.suraDays(on: "2026-09-22") == [:])

        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-23", completingSura: "nas", completingDayAt: t1, at: t1)
        #expect(try ruqyah.suraDays(on: "2026-09-23") == ["kafirun": t0, "nas": t1])
        #expect(try ruqyah.day(on: "2026-09-23")?.completedAt == t1)
        #expect(try ruqyah.counts(on: "2026-09-23") == ["kafirun-1-6": 7, "nas-1-6": 7])
    }

    /// `resetSegment`: the counter returns to 0 and its sura is no longer complete that day; other suras, other days
    /// and the day's record stay.
    @Test func ruqyahSegmentResetClearsOnlyItsSura() throws {
        let ruqyah = database.ruqyah
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-22", completingSura: "nas", at: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-23", completingSura: "nas", at: t0)
        try ruqyah.setCount(7, for: "kafirun-1-6", on: "2026-09-23", completingSura: "kafirun",
                            completingDayAt: t0, at: t0)
        try ruqyah.resetSegment("nas-1-6", of: "nas", on: "2026-09-23", at: t1)
        #expect(try ruqyah.counts(on: "2026-09-23") == ["kafirun-1-6": 7, "nas-1-6": 0])
        #expect(try ruqyah.suraDays(on: "2026-09-23") == ["kafirun": t0])
        #expect(try ruqyah.suraDays(on: "2026-09-22") == ["nas": t0])
        #expect(try ruqyah.day(on: "2026-09-23")?.completedAt == t0)

        // A segment never read gets its zero row; a sura with no record has nothing to delete.
        try ruqyah.resetSegment("jinn-1-7", of: "jinn", on: "2026-09-23", at: t1)
        #expect(try ruqyah.counts(on: "2026-09-23")["jinn-1-7"] == 0)
    }

    /// The day reset clears today's sura completions and keeps the day's record (`clearDay`); week and everything
    /// delete the sura completions in their scope as well.
    @Test func ruqyahScopedResetsClearSuraCompletions() throws {
        let ruqyah = database.ruqyah
        for day in ["2026-09-10", "2026-09-17", "2026-09-22", "2026-09-23"] {
            try ruqyah.setCount(7, for: "nas-1-6", on: day, completingSura: "nas", at: t0)
        }
        try ruqyah.markComplete(on: "2026-09-23", completedAt: t0)

        try ruqyah.resetCounts(on: "2026-09-23", at: t1)
        #expect(try ruqyah.suraDays(on: "2026-09-23") == [:])
        #expect(try ruqyah.suraDays(on: "2026-09-22") == ["nas": t0])
        #expect(try ruqyah.day(on: "2026-09-23") != nil)

        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        try ruqyah.resetCounts(on: "2026-09-23", removing: week, at: t1)
        #expect(try ruqyah.suraDays(on: "2026-09-22") == [:])
        #expect(try ruqyah.suraDays(on: "2026-09-17") == [:])
        #expect(try ruqyah.suraDays(on: "2026-09-10") == ["nas": t0])
        #expect(try ruqyah.day(on: "2026-09-23") == nil)

        try ruqyah.resetCounts(on: "2026-09-23", removing: .all, at: t1)
        #expect(try ruqyah.suraDays(on: "2026-09-10") == [:])
    }

    /// The PWA's `historyDates`: completed days in scope, today included, and earlier days in scope with a completed
    /// sura, each date once.
    @Test func ruqyahRecordedDayCountUnitesDaysAndEarlierSuras() throws {
        let ruqyah = database.ruqyah
        try ruqyah.markComplete(on: "2026-09-23", completedAt: t0)
        try ruqyah.markComplete(on: "2026-09-20", completedAt: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-20", completingSura: "nas", at: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-21", completingSura: "nas", at: t0)
        try ruqyah.setCount(7, for: "kafirun-1-6", on: "2026-09-21", completingSura: "kafirun", at: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-10", completingSura: "nas", at: t0)
        try ruqyah.setCount(7, for: "nas-1-6", on: "2026-09-24", completingSura: "nas", at: t0)

        #expect(try ruqyah.recordedDayCount(.all, before: "2026-09-23") == 4)
        #expect(try ruqyah.recordedDayCount(.all, before: "2026-09-25") == 5)
        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        #expect(try ruqyah.recordedDayCount(week, before: "2026-09-23") == 3)
        #expect(try ruqyah.dayCount(.all) == 2, "completed days alone")
    }

    /// The athkar PWA's `markPageRead`: a page is read once, and the reading that completes a sura records it, once,
    /// keeping the first time.
    @Test func suwarReadsAndSuraCompletionAreRecordedOnce() throws {
        let suwar = database.suwar
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-23", at: t0)
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-23", at: t1)
        try suwar.markRead("mulk-5-8", of: "mulk", on: "2026-09-23", completingSura: true, at: t0)
        try suwar.markRead("mulk-5-8", of: "mulk", on: "2026-09-23", completingSura: true, at: t1)
        #expect(try suwar.readPages(on: "2026-09-23") == ["mulk-1-4", "mulk-5-8"])
        #expect(try suwar.suraDays(on: "2026-09-23") == ["mulk": t0])
        #expect(try suwar.readPages(on: "2026-09-22") == [])
        #expect(try suwar.suraDays(on: "2026-09-22") == [:])
        let readAt = try database.reader.read { db in
            try SuwarPageRead.filter(GRDB.Column("local_date") == "2026-09-23").order(GRDB.Column("page_id"))
                .fetchAll(db)
        }
        #expect(readAt == [
            SuwarPageRead(localDate: "2026-09-23", suraId: "mulk", pageId: "mulk-1-4", readAt: t0),
            SuwarPageRead(localDate: "2026-09-23", suraId: "mulk", pageId: "mulk-5-8", readAt: t0),
        ])
    }

    /// `resetSuraPage`: the page is unread and its sura no longer complete that day; other days and suras keep theirs.
    @Test func suwarUnmarkClearsOnlyThatPageAndItsSura() throws {
        let suwar = database.suwar
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-22", completingSura: true, at: t0)
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-23", completingSura: true, at: t0)
        try suwar.markRead("waqiah-1-11", of: "waqiah", on: "2026-09-23", completingSura: true, at: t0)
        try suwar.unmarkRead("mulk-1-4", of: "mulk", on: "2026-09-23")
        #expect(try suwar.readPages(on: "2026-09-23") == ["waqiah-1-11"])
        #expect(try suwar.suraDays(on: "2026-09-23") == ["waqiah": t0])
        #expect(try suwar.readPages(on: "2026-09-22") == ["mulk-1-4"])
        #expect(try suwar.suraDays(on: "2026-09-22") == ["mulk": t0])

        // A page never read has nothing to delete.
        try suwar.unmarkRead("kahf-1-4", of: "kahf", on: "2026-09-23")
        #expect(try suwar.readPages(on: "2026-09-23") == ["waqiah-1-11"])
    }

    /// `resetSuwarProgress` clears today and keeps earlier days; `deleteSuwarHistory` deletes the days in scope.
    @Test func suwarScopedResets() throws {
        let suwar = database.suwar
        for day in ["2026-09-10", "2026-09-17", "2026-09-22", "2026-09-23"] {
            try suwar.markRead("mulk-1-4", of: "mulk", on: day, completingSura: true, at: t0)
            try suwar.markRead("kahf-1-4", of: "kahf", on: day, at: t0)
        }

        try suwar.reset(on: "2026-09-23")
        #expect(try suwar.readPages(on: "2026-09-23") == [])
        #expect(try suwar.suraDays(on: "2026-09-23") == [:])
        #expect(try suwar.readPages(on: "2026-09-22") == ["kahf-1-4", "mulk-1-4"])
        #expect(try suwar.suraDays(on: "2026-09-22") == ["mulk": t0])

        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        try suwar.reset(on: "2026-09-23", removing: week)
        for day in ["2026-09-17", "2026-09-22"] {
            #expect(try suwar.readPages(on: day) == [], "\(day)")
            #expect(try suwar.suraDays(on: day) == [:], "\(day)")
        }
        #expect(try suwar.readPages(on: "2026-09-10") == ["kahf-1-4", "mulk-1-4"])
        #expect(try suwar.suraDays(on: "2026-09-10") == ["mulk": t0])

        try suwar.reset(on: "2026-09-23", removing: .all)
        #expect(try suwar.readPages(on: "2026-09-10") == [])
        #expect(try suwar.suraDays(on: "2026-09-10") == [:])
    }

    /// The PWA counts `suwarState.history`: earlier dates with a completed sura, each once. Pages read without a
    /// completed sura, and today's completions, are not history.
    @Test func suwarRecordedDayCountIsEarlierDatesWithACompletedSura() throws {
        let suwar = database.suwar
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-10", completingSura: true, at: t0)
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-20", completingSura: true, at: t0)
        try suwar.markRead("waqiah-1-11", of: "waqiah", on: "2026-09-20", completingSura: true, at: t0)
        try suwar.markRead("kahf-1-4", of: "kahf", on: "2026-09-21", at: t0)
        try suwar.markRead("mulk-1-4", of: "mulk", on: "2026-09-23", completingSura: true, at: t0)

        #expect(try suwar.recordedDayCount(.all, before: "2026-09-23") == 2)
        #expect(try suwar.recordedDayCount(.all, before: "2026-09-24") == 3)
        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        #expect(try suwar.recordedDayCount(week, before: "2026-09-23") == 1)
    }

    /// `setTasbihCount`: a phrase's first count of the day goes last in the day's order, a later count keeps its place,
    /// and zero deletes the row, so the phrase's next count goes last again.
    @Test func tasbihCountsKeepTheDaysFirstUseOrder() throws {
        let tasbih = database.tasbih
        try tasbih.setCount(1, for: "hamd", on: "2026-09-23", at: t0)
        try tasbih.setCount(1, for: "c:يا رب", on: "2026-09-23", at: t0)
        try tasbih.setCount(1, for: "subhan", on: "2026-09-23", at: t0)
        try tasbih.setCount(2, for: "hamd", on: "2026-09-23", at: t1)
        try tasbih.setCount(7, for: "subhan", on: "2026-09-22", at: t0)
        #expect(try tasbih.counts(on: "2026-09-23") == [
            TasbihCount(localDate: "2026-09-23", phraseKey: "hamd", count: 2, firstUse: 1, updatedAt: t1),
            TasbihCount(localDate: "2026-09-23", phraseKey: "c:يا رب", count: 1, firstUse: 2, updatedAt: t0),
            TasbihCount(localDate: "2026-09-23", phraseKey: "subhan", count: 1, firstUse: 3, updatedAt: t0),
        ])

        try tasbih.setCount(0, for: "hamd", on: "2026-09-23", at: t1)
        try tasbih.setCount(0, for: "takbir", on: "2026-09-23", at: t1)
        #expect(try tasbih.counts(on: "2026-09-23").map(\.phraseKey) == ["c:يا رب", "subhan"])
        try tasbih.setCount(1, for: "hamd", on: "2026-09-23", at: t1)
        #expect(try tasbih.counts(on: "2026-09-23").map(\.phraseKey) == ["c:يا رب", "subhan", "hamd"])
        #expect(try tasbih.counts(on: "2026-09-23").map(\.firstUse) == [2, 3, 4])
        #expect(try tasbih.counts(on: "2026-09-22").map(\.count) == [7])
        #expect(try tasbih.phraseKeys() == ["c:يا رب", "hamd", "subhan"])

        try tasbih.setCount(TasbihCount.maxCount, for: "hamd", on: "2026-09-23", at: t1)
        #expect(throws: DatabaseError.self) {
            try tasbih.setCount(TasbihCount.maxCount + 1, for: "hamd", on: "2026-09-23", at: t1)
        }
        #expect(try tasbih.counts(on: "2026-09-23").last?.count == TasbihCount.maxCount)
    }

    /// The saved phrases and the phrase counted are stored together; an adopted spelling's counts move to the phrase
    /// on every date, summed and capped where that date already counts it, with the earlier first use.
    @Test func tasbihPhrasesSaveTogetherAndAdoptAnEarlierSpelling() throws {
        let tasbih = database.tasbih
        try tasbih.setCount(5, for: "c:يا رب", on: "2026-09-22", at: t0)
        try tasbih.setCount(3, for: "subhan", on: "2026-09-23", at: t0)
        try tasbih.setCount(4, for: "c:يا رب", on: "2026-09-23", at: t0)
        try tasbih.setCount(99_990, for: "c:يَا رَبّ", on: "2026-09-21", at: t0)
        try tasbih.setCount(20, for: "c:يا ربّ", on: "2026-09-21", at: t1)

        try tasbih.savePhrases(["يَا رَبّ", "حسبي الله"], selected: "c:يَا رَبّ", adopting: ["c:يا رب", "c:يا ربّ"],
                               at: t1)
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == ["يَا رَبّ", "حسبي الله"])
        #expect(try database.settings.value(for: .tasbihSelected) == "c:يَا رَبّ")
        #expect(try tasbih.counts(on: "2026-09-23") == [
            TasbihCount(localDate: "2026-09-23", phraseKey: "subhan", count: 3, firstUse: 1, updatedAt: t0),
            TasbihCount(localDate: "2026-09-23", phraseKey: "c:يَا رَبّ", count: 4, firstUse: 2, updatedAt: t0),
        ])
        #expect(try tasbih.counts(on: "2026-09-22").map(\.phraseKey) == ["c:يَا رَبّ"])
        #expect(try tasbih.counts(on: "2026-09-21") == [
            TasbihCount(localDate: "2026-09-21", phraseKey: "c:يَا رَبّ", count: TasbihCount.maxCount, firstUse: 1,
                        updatedAt: t1),
        ])
        #expect(try tasbih.phraseKeys() == ["c:يَا رَبّ", "subhan"])

        // Without adoptions only the preferences change.
        try tasbih.savePhrases([], selected: "hamd", at: t1)
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == [])
        #expect(try database.settings.value(for: .tasbihSelected) == "hamd")
        #expect(try tasbih.phraseKeys() == ["c:يَا رَبّ", "subhan"])
    }

    /// Keys are code units, as in the PWA's `counts` object: a spelling whose tashkeel is only ordered differently is
    /// its own row, listed and adopted, though Swift's `==` equates the two.
    @Test func tasbihKeysThatDifferOnlyInTashkeelOrderAreTwoRows() throws {
        let tasbih = database.tasbih
        let saved = "c:رب\u{0651}\u{064E}"
        let earlier = "c:رب\u{064E}\u{0651}"
        #expect(saved == earlier)
        try tasbih.setCount(3, for: saved, on: "2026-09-23", at: t0)
        try tasbih.setCount(2, for: earlier, on: "2026-09-23", at: t1)
        let keys = try tasbih.phraseKeys()
        #expect(keys.count == 2)
        #expect(Set(keys.map { Array($0.utf16) }) == [Array(saved.utf16), Array(earlier.utf16)])

        try tasbih.savePhrases(["رب\u{0651}\u{064E}"], selected: saved, adopting: [earlier], at: t1)
        let rows = try tasbih.counts(on: "2026-09-23")
        #expect(rows.count == 1)
        #expect(rows.first.map { Array($0.phraseKey.utf16) } == Array(saved.utf16))
        #expect(rows.first?.count == 5)
        #expect(rows.first?.firstUse == 1)
    }

    @Test func tasbihPhrasesAreSavedWithTheirAdoptionsOrNotAtAll() throws {
        let tasbih = database.tasbih
        try tasbih.setCount(4, for: "c:يا رب", on: "2026-09-23", at: t0)
        try database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_adoption BEFORE INSERT ON tasbih_counts
                WHEN NEW.phrase_key = 'c:يَا رَبّ' BEGIN SELECT RAISE(ABORT, 'test rejects the adoption'); END
                """)
        }
        #expect(throws: DatabaseError.self) {
            try tasbih.savePhrases(["يَا رَبّ"], selected: "c:يَا رَبّ", adopting: ["c:يا رب"], at: t1)
        }
        #expect(try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } == 0)
        #expect(try tasbih.counts(on: "2026-09-23").map(\.phraseKey) == ["c:يا رب"])
    }

    @Test func tasbihScopedResetsKeepThePreferences() throws {
        let tasbih = database.tasbih
        for day in ["2026-09-10", "2026-09-20", "2026-09-22", "2026-09-23"] {
            try tasbih.setCount(3, for: "subhan", on: day, at: t0)
        }
        try tasbih.savePhrases(["يا رب"], selected: "c:يا رب", at: t0)
        try database.settings.set(100, for: .tasbihTarget, at: t0)

        try tasbih.reset(on: "2026-09-23")
        #expect(try tasbih.counts(on: "2026-09-23") == [])
        #expect(try tasbih.counts(on: "2026-09-22").count == 1)

        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        try tasbih.reset(on: "2026-09-23", removing: week)
        #expect(try tasbih.counts(on: "2026-09-22") == [])
        #expect(try tasbih.counts(on: "2026-09-20") == [])
        #expect(try tasbih.counts(on: "2026-09-10").count == 1)

        try tasbih.reset(on: "2026-09-23", removing: .all)
        #expect(try tasbih.phraseKeys() == [])
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == ["يا رب"])
        #expect(try database.settings.value(for: .tasbihSelected) == "c:يا رب")
        #expect(try database.settings.value(for: .tasbihTarget) == 100)
    }

    /// The PWA counts `tasbihState.history`: earlier dates with a count, each once. Today's counts are not history.
    @Test func tasbihRecordedDayCountIsEarlierDatesWithACount() throws {
        let tasbih = database.tasbih
        try tasbih.setCount(1, for: "subhan", on: "2026-09-10", at: t0)
        try tasbih.setCount(1, for: "subhan", on: "2026-09-20", at: t0)
        try tasbih.setCount(2, for: "hamd", on: "2026-09-20", at: t0)
        try tasbih.setCount(1, for: "subhan", on: "2026-09-23", at: t0)

        #expect(try tasbih.recordedDayCount(.all, before: "2026-09-23") == 2)
        #expect(try tasbih.recordedDayCount(.all, before: "2026-09-24") == 3)
        let week = HistoryRemoval.week(endingAt: Instant.at("2026-09-23T12:00:00.000Z"), in: .gmt)
        #expect(try tasbih.recordedDayCount(week, before: "2026-09-23") == 1)
    }

    @Test func adhkarCompletedDayCountIsDistinctEarlierDates() throws {
        let adhkar = database.adhkar
        for date in ["2026-09-15", "2026-09-20", "2026-09-22", "2026-09-23"] {
            try adhkar.markComplete(on: date, period: .morning, origin: .counters, completedAt: t0)
            try adhkar.markComplete(on: date, period: .evening, origin: .manual, completedAt: nil)
        }
        try adhkar.setCount(1, for: "morning-01", on: "2026-09-21", period: .morning, at: t0)
        #expect(try adhkar.completedDayCount(.all, before: "2026-09-23") == 3)
        #expect(try adhkar.completedDayCount(.dates(from: "2026-09-17", through: "2026-09-23"),
                                             before: "2026-09-23") == 2)
    }

    @Test func reminderRulesAndShownState() throws {
        let reminders = database.reminders
        let morning = ReminderRule.adhkar(.morning, enabled: true, updatedAt: t0)
        #expect(morning.id == "adhkar_morning")
        #expect(morning.prayerKey == .fajr && morning.offsetMinutes == 60 && morning.weekdayMask == 127)
        try reminders.save(morning)
        try reminders.save(ReminderRule.adhkar(.evening, enabled: false, updatedAt: t0))
        try reminders.setLastShown("2026-09-22", ruleId: morning.id)
        try reminders.setLastShown("2026-09-23", ruleId: morning.id)

        #expect(try reminders.rules().map(\.id) == ["adhkar_evening", "adhkar_morning"])
        #expect(try reminders.rule(id: morning.id) == morning)
        #expect(try reminders.lastShown(ruleId: morning.id) == "2026-09-23")
        #expect(try reminders.lastShown(ruleId: "adhkar_evening") == nil)

        // Shown state cannot outlive its rule, nor exist without one.
        try reminders.deleteRule(id: morning.id)
        #expect(try reminders.lastShown(ruleId: morning.id) == nil)
        #expect(throws: DatabaseError.self) { try reminders.setLastShown("2026-09-23", ruleId: "missing") }
    }

    @Test func settingsReturnDefaultsUntilSet() throws {
        let settings = database.settings
        #expect(try settings.value(for: .theme) == .system)
        #expect(try settings.value(for: .haptics) == true)
        #expect(try settings.value(for: .calculationMethod) == .mwl)

        try settings.set(.ummAlQura, for: .calculationMethod, at: t0)
        try settings.set(false, for: .haptics, at: t0)
        #expect(try settings.value(for: .calculationMethod) == .ummAlQura)
        #expect(try settings.value(for: .haptics) == false)
        let stored = try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT value_json FROM settings WHERE key = 'calculation_method'")
        }
        #expect(stored == #""umm-al-qura""#)

        try settings.removeValue(for: .haptics)
        #expect(try settings.value(for: .haptics) == true)
    }

    /// Reading the profile invents no rows; each chosen field lands in its own key and reads back.
    @Test func calculationSettingsReadEachKeyAndInventNothing() throws {
        let settings = database.settings
        // The defaults in spec/schema.md: the PWA's behaviour, no adjustments, no Hijri offset.
        #expect(try settings.calculationSettings()
                == CalculationSettings(method: .mwl, asrSchool: .standard, highLatitudeRule: .twilightAngle,
                                       adjustments: PrayerAdjustments(), hijriOffset: 0))
        #expect(try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } == 0)

        let chosen = CalculationSettings(method: .tehran, asrSchool: .hanafi, highLatitudeRule: .seventhOfTheNight,
                                         adjustments: PrayerAdjustments(fajr: -2, sunrise: 1, dhuhr: 3, asr: -4,
                                                                        maghrib: 5, isha: 6),
                                         hijriOffset: 2)
        try settings.set(chosen.method, for: .calculationMethod, at: t0)
        try settings.set(chosen.asrSchool, for: .asrSchool, at: t0)
        try settings.set(chosen.highLatitudeRule, for: .highLatitudeRule, at: t0)
        try settings.set(chosen.adjustments, for: .prayerAdjustments, at: t0)
        try settings.set(chosen.hijriOffset, for: .hijriOffset, at: t0)
        #expect(try settings.calculationSettings() == chosen)
        let rows = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value_json FROM settings ORDER BY key").map {
                [$0["key"] as String, $0["value_json"] as String]
            }
        }
        #expect(rows == [["asr_school", #""hanafi""#],
                         ["calculation_method", #""tehran""#],
                         ["high_latitude_rule", #""seventh-of-the-night""#],
                         ["hijri_offset", "2"],
                         ["prayer_adjustments", #"{"asr":-4,"dhuhr":3,"fajr":-2,"isha":6,"maghrib":5,"sunrise":1}"#]])
    }

    @Test func locationIsASingleProfileRoundedToTwoDecimals() throws {
        let location = database.location
        try location.save(LocationProfile(latitude: 21.4225, longitude: -39.8262, source: .device, updatedAt: t0))
        try location.save(LocationProfile(latitude: -33.86785, longitude: 151.20732, source: .manual, updatedAt: nil))

        let profile = try #require(try location.profile())
        #expect(profile.latitude == -33.87)
        #expect(profile.longitude == 151.21)
        #expect(profile.source == .manual)
        #expect(try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM location_profiles") } == 1)
        try location.delete()
        #expect(try location.profile() == nil)
    }

    /// Expected values are what `node -e 'Math.round(x * 100) / 100'` prints: halves go toward +∞, so the sign
    /// matters (Swift's `.rounded()` would give -33.87 and -12.35).
    @Test(arguments: [(-33.865, -33.86), (33.865, 33.87), (-12.345, -12.34), (12.345, 12.35),
                      (21.4225, 21.42), (39.8262, 39.83)])
    func locationRoundingMatchesJavaScriptMathRound(input: Double, expected: Double) {
        let profile = LocationProfile(latitude: input, longitude: input, source: .manual, updatedAt: nil)
        #expect(profile.latitude == expected)
        #expect(profile.longitude == expected)
    }

    @Test func contentInstallRecordsTheCurrentVersionPerPack() throws {
        let installs = database.contentInstalls
        try installs.record(ContentInstall(packId: "adhkar", version: "1.0.0", checksum: "d5f1", installedAt: t0))
        try installs.record(ContentInstall(packId: "ruqyah", version: "1.0.0", checksum: "a7a3", installedAt: t0))
        try installs.record(ContentInstall(packId: "adhkar", version: "1.0.1", checksum: "e6a2", installedAt: t1))
        #expect(try installs.installs() == [
            ContentInstall(packId: "adhkar", version: "1.0.1", checksum: "e6a2", installedAt: t1),
            ContentInstall(packId: "ruqyah", version: "1.0.0", checksum: "a7a3", installedAt: t0),
        ])
    }

    @Test func contentInstallBatchRecordsEveryRowOrNone() throws {
        let installs = database.contentInstalls
        try installs.record(ContentInstall(packId: "adhkar", version: "1.0.0", checksum: "d5f1", installedAt: t0))
        let recorded = [ContentInstall(packId: "adhkar", version: "1.0.1", checksum: "e6a2", installedAt: t1),
                        ContentInstall(packId: "ruqyah", version: "1.0.0", checksum: "a7a3", installedAt: t1)]
        try installs.record(recorded)
        #expect(try installs.installs() == recorded)

        // SQLite refuses the second row, as a full or failing disk would: a test-only trigger on this private database.
        try database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_suwar BEFORE INSERT ON content_installs
                WHEN NEW.pack_id = 'suwar' BEGIN SELECT RAISE(ABORT, 'test rejects suwar'); END
                """)
        }
        let error = #expect(throws: DatabaseError.self) {
            try installs.record([ContentInstall(packId: "adhkar", version: "1.0.2", checksum: "f0b4", installedAt: t1),
                                 ContentInstall(packId: "suwar", version: "1.0.0", checksum: "c3d9", installedAt: t1)])
        }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_TRIGGER)
        #expect(try installs.installs() == recorded)
    }
}
