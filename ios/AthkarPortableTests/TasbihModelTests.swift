import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

private typealias Change = TasbihModel.Change

/// «مسبحة» as the athkar PWA counts: today's count of each phrase, laps past the target, the saved phrases and the
/// target, and the scoped resets.
final class TasbihModelTests: XCTestCase {
    /// `defaultTasbihState`: «سبحان الله», a target of ٣٣, no saved phrase and nothing counted.
    @MainActor
    func testANewCounterStartsAtZero() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertEqual(model.date, support.today)
        XCTAssertEqual(model.counts, [])
        XCTAssertEqual(model.selected, "subhan")
        XCTAssertEqual(model.target, 33)
        XCTAssertEqual(model.custom, [])
        XCTAssertFalse(model.hasHistory)
        XCTAssertFalse(model.canReset)
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.dayTotal, 0)
        XCTAssertEqual(model.status.text, "الهدف ٣٣")
        XCTAssertFalse(model.status.check)
        XCTAssertEqual(model.ringFraction, 0)
        XCTAssertFalse(model.isReached)
        XCTAssertFalse(model.isLap)
        XCTAssertEqual(model.summaryLabel, "سبحان الله، ٠ من ٣٣")
        XCTAssertEqual(model.countAnnouncement, "٠ من ٣٣")
        XCTAssertEqual(model.totalText, "اليوم: ٠")
        XCTAssertEqual(model.totalLabel, "مجموع المسبحة اليوم: ٠")
        XCTAssertEqual(model.phraseButtonLabel, "اختيار الذكر، الحالي: سبحان الله")
        XCTAssertEqual(model.targetChipText, "الهدف: ٣٣")
        XCTAssertEqual(model.targetButtonLabel, "تغيير الهدف، الحالي: ٣٣")
        XCTAssertEqual(model.resetLabel, "إعادة عدّ سبحان الله إلى الصفر")
        XCTAssertEqual(model.presetOptions.map(\.key), TasbihText.presets.map(\.id))
        XCTAssertEqual(model.presetOptions.filter(\.isSelected).map(\.key), ["subhan"])
        XCTAssertEqual(model.presetOptions[0].accessibilityLabel, "سبحان الله")
        XCTAssertEqual(model.customOptions, [])
        XCTAssertTrue(model.canAddPhrase)
        XCTAssertNil(model.resetConfirmation())
        XCTAssertNil(model.undo(), "nothing to undo at zero")
        XCTAssertTrue(try support.database.tasbih.counts(on: support.today).isEmpty)
    }

    /// `addTasbihCount`: every multiple of the target plays the haptic and is announced at once, the ring is full at
    /// each lap and starts the next one without sweeping back; other counts are announced once taps pause.
    @MainActor
    func testCountingContinuesInLapsPastTheTarget() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertEqual(model.setTarget(3), Change(ring: .step, announcement: .now("الهدف: ٣")))

        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .countAfterPause))
        XCTAssertEqual(model.ringFraction, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(model.status.text, "١ من ٣")
        XCTAssertEqual(model.countAnnouncement, "١ من ٣")
        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .countAfterPause))
        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .now("بلغت الهدف: ٣، سبحان الله"),
                                           haptic: true, reached: true))
        XCTAssertEqual(model.ringFraction, 1)
        XCTAssertTrue(model.isReached)
        XCTAssertTrue(model.isLap)
        XCTAssertEqual(model.status.text, "بلغت الهدف")
        XCTAssertTrue(model.status.check)

        XCTAssertEqual(model.add(), Change(ring: .jump, announcement: .countAfterPause), "the next lap starts at once")
        XCTAssertEqual(model.ringFraction, 1.0 / 3, accuracy: 1e-9)
        XCTAssertTrue(model.isReached)
        XCTAssertFalse(model.isLap)
        XCTAssertEqual(model.status.text, "الدورة ٢: ١ من ٣")
        XCTAssertFalse(model.status.check)
        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .countAfterPause))
        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .now("اكتملت الدورة ٢"),
                                           haptic: true, reached: true))
        XCTAssertEqual(model.status.text, "اكتملت الدورة ٢")
        XCTAssertTrue(model.status.check)

        XCTAssertEqual(model.count, 6)
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "subhan", count: 6)])
        XCTAssertEqual(model.summaryLabel, "سبحان الله، ٦ من ٣")
        XCTAssertEqual(model.totalText, "اليوم: ٦")
        XCTAssertTrue(model.canReset)
        let stored = try support.database.tasbih.counts(on: support.today)
        XCTAssertEqual(stored.map(\.phraseKey), ["subhan"])
        XCTAssertEqual(stored.map(\.count), [6])
        XCTAssertEqual(try support.makeTasbih().count, 6)
    }

    /// `undoTasbihCount`: back to a whole lap, the ring is full at once; back to zero, the phrase's row goes, so its
    /// next count puts it last in the day's order.
    @MainActor
    func testUndoStepsBackAndZeroRemovesThePhraseFromTheDay() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertNotNil(model.setTarget(3))
        for _ in 0..<4 { XCTAssertNotNil(model.add()) }

        XCTAssertEqual(model.undo(), Change(ring: .jump, announcement: .now("تراجع، العدد ٣")))
        XCTAssertEqual(model.ringFraction, 1)
        XCTAssertEqual(model.undo(), Change(ring: .step, announcement: .now("تراجع، العدد ٢")))
        XCTAssertNotNil(model.undo())
        XCTAssertEqual(model.undo(), Change(ring: .step, announcement: .now("تراجع، العدد ٠")))
        XCTAssertNil(model.undo())
        XCTAssertEqual(model.counts, [])
        XCTAssertFalse(model.canReset)
        XCTAssertTrue(try support.database.tasbih.counts(on: support.today).isEmpty)

        XCTAssertNotNil(model.select("hamd"))
        XCTAssertNotNil(model.add())
        XCTAssertNotNil(model.select("subhan"))
        XCTAssertNotNil(model.add())
        XCTAssertEqual(model.counts.map(\.key), ["hamd", "subhan"])
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.phraseKey), ["hamd", "subhan"])
    }

    /// «بلا هدف»: an open count with no ring, no lap and no haptic; stored as a target of zero.
    @MainActor
    func testWithoutATargetTheCountIsOpen() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertEqual(model.setTarget(nil), Change(ring: .step, announcement: .now("بلا هدف")))
        XCTAssertEqual(try support.database.settings.value(for: .tasbihTarget), 0)
        for _ in 0..<33 {
            XCTAssertEqual(model.add(), Change(ring: .step, announcement: .countAfterPause))
        }
        XCTAssertEqual(model.ringFraction, 0)
        XCTAssertFalse(model.isReached)
        XCTAssertFalse(model.isLap)
        XCTAssertEqual(model.status.text, "بلا هدف")
        XCTAssertFalse(model.status.check)
        XCTAssertEqual(model.summaryLabel, "سبحان الله، ٣٣، بلا هدف")
        XCTAssertEqual(model.countAnnouncement, "٣٣")
        XCTAssertEqual(model.targetChipText, "بلا هدف")
        XCTAssertEqual(model.targetButtonLabel, "تغيير الهدف، الحالي: بلا هدف")
        XCTAssertNil(try support.makeTasbih().target)
    }

    /// `setTasbihTarget`: counts stay, and a count already at a lap shows it without a haptic. A target outside
    /// 1–9999 changes nothing.
    @MainActor
    func testChangingTheTargetKeepsTheCount() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        for _ in 0..<5 { XCTAssertNotNil(model.add()) }
        XCTAssertEqual(model.setTarget(5), Change(ring: .step, announcement: .now("الهدف: ٥")))
        XCTAssertEqual(model.count, 5)
        XCTAssertTrue(model.isLap)
        XCTAssertEqual(model.status.text, "بلغت الهدف")
        XCTAssertNil(model.setTarget(0))
        XCTAssertNil(model.setTarget(10_000))
        XCTAssertEqual(model.target, 5)
        XCTAssertEqual(try support.database.settings.value(for: .tasbihTarget), 5)
        XCTAssertEqual(model.setTarget(9999), Change(ring: .step, announcement: .now("الهدف: ٩٩٩٩")))
        XCTAssertEqual(try support.makeTasbih().target, 9999)
    }

    /// `tasbihMaxCount`: past 99,999 nothing is counted, and the cap is announced once until the count is below it
    /// again or another phrase is shown.
    @MainActor
    func testTheCapIsAnnouncedOnce() throws {
        let support = try PortableTestSupport()
        try support.database.tasbih.setCount(TasbihCount.maxCount - 1, for: "subhan", on: support.today)
        let model = try support.makeTasbih()
        let cap = Change(announcement: .now("بلغت الحد الأقصى للعدّ"))
        XCTAssertEqual(model.add(), Change(ring: .step, announcement: .countAfterPause))
        XCTAssertEqual(model.count, TasbihCount.maxCount)
        XCTAssertEqual(model.add(), cap)
        XCTAssertNil(model.add())
        XCTAssertEqual(model.count, TasbihCount.maxCount)

        XCTAssertNotNil(model.undo())
        XCTAssertNotNil(model.add())
        XCTAssertEqual(model.add(), cap, "below the cap, it is announced again")
        XCTAssertNotNil(model.select("hamd"))
        XCTAssertNotNil(model.select("subhan"))
        XCTAssertEqual(model.add(), cap, "showing another phrase announces it again")
        XCTAssertNil(model.add())
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.count), [TasbihCount.maxCount])
    }

    /// `requestTasbihReset`: always confirmed; the reset zeroes the phrase on screen only.
    @MainActor
    func testResettingTheCountAsksFirstAndKeepsOtherPhrases() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        for _ in 0..<3 { XCTAssertNotNil(model.add()) }
        XCTAssertNotNil(model.select("hamd"))
        for _ in 0..<2 { XCTAssertNotNil(model.add()) }
        XCTAssertNotNil(model.select("subhan"))

        let confirmation = try XCTUnwrap(model.resetConfirmation())
        XCTAssertEqual(confirmation, DeckConfirmation(
            title: "إعادة عدّ سبحان الله؟",
            message: "سيعود عدّ هذا الذكر اليوم من ٣ إلى الصفر، ويُنقص من مجموع اليوم."))
        XCTAssertEqual(confirmation.confirmTitle, "إعادة")
        XCTAssertEqual(model.resetCount(), Change(ring: .reset, announcement: .now("أُعيد عدّ سبحان الله إلى الصفر")))
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.dayTotal, 2)
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "hamd", count: 2)])
        XCTAssertNil(model.resetConfirmation())
        XCTAssertNotNil(model.add())
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.phraseKey), ["hamd", "subhan"])
    }

    /// `selectTasbihPhrase`: stored, announced with today's count, and kept across launches. A key that is neither a
    /// preset nor saved changes nothing.
    @MainActor
    func testSelectingAPhraseIsStored() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertEqual(model.select("hamd"), Change(ring: .step, announcement: .now("الذكر: الحمد لله، العدد ٠")))
        for _ in 0..<2 { XCTAssertNotNil(model.add()) }
        XCTAssertEqual(model.presetOptions[1], TasbihModel.Option(key: "hamd", label: "الْحَمْدُ لِلَّهِ", count: 2,
                                                                  isSelected: true,
                                                                  accessibilityLabel: "الحمد لله، اليوم ٢"))
        XCTAssertFalse(model.presetOptions[0].isSelected)
        XCTAssertNotNil(model.select("subhan"))
        XCTAssertEqual(model.select("hamd"), Change(ring: .step, announcement: .now("الذكر: الحمد لله، العدد ٢")))

        XCTAssertNil(model.select("unknown"))
        XCTAssertNil(model.select("c:يا رب"), "not saved")
        XCTAssertEqual(model.selected, "hamd")
        XCTAssertEqual(try support.database.settings.value(for: .tasbihSelected), "hamd")
        XCTAssertEqual(try support.makeTasbih().selected, "hamd")
    }

    /// `addTasbihPhrase`: a new phrase is cleaned, saved first and selected; one that names a preset or a saved phrase
    /// selects it; eight phrases at most.
    @MainActor
    func testAddingPhrases() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertEqual(model.addPhrase("  يا\u{200F}   رب "),
                       Change(ring: .step, announcement: .now("أُضيفت العبارة: يا رب")))
        XCTAssertEqual(model.custom, ["يا رب"])
        XCTAssertEqual(model.selected, "c:يا رب")
        XCTAssertEqual(model.phrase.short, "يا رب")
        XCTAssertEqual(model.customOptions.map(\.key), ["c:يا رب"])
        XCTAssertTrue(model.customOptions[0].isSelected)
        XCTAssertEqual(try support.database.settings.value(for: .tasbihCustomPhrases), ["يا رب"])
        XCTAssertEqual(try support.database.settings.value(for: .tasbihSelected), "c:يا رب")

        XCTAssertEqual(model.addPhrase("سُبْحَانَ ٱللَّه"), Change(ring: .step,
                                                                  announcement: .now("الذكر: سبحان الله، العدد ٠")))
        XCTAssertEqual(model.addPhrase("يَا رَبّ"),
                       Change(ring: .step, announcement: .now("الذكر: يا رب، العدد ٠")), "the saved spelling is kept")
        XCTAssertEqual(model.custom, ["يا رب"])
        XCTAssertNil(model.addPhrase("ـــ \u{064E}"), "nothing left to save")

        let phrases = ["ربنا آتنا", "حسبي الله", "يا حي يا قيوم", "رضيت بالله ربا", "اللهم اغفر لي", "رب زدني علما",
                       "اللهم أعني"]
        for phrase in phrases { XCTAssertNotNil(model.addPhrase(phrase), phrase) }
        XCTAssertEqual(model.custom, phrases.reversed() + ["يا رب"], "newest first")
        XCTAssertFalse(model.canAddPhrase)
        XCTAssertNil(model.addPhrase("سبحان ربي العظيم"))
        XCTAssertEqual(model.custom.count, 8)
        XCTAssertEqual(model.selected, "c:اللهم أعني")
        XCTAssertNotNil(model.addPhrase("يا رب"), "a saved phrase is still chosen")
        XCTAssertEqual(model.selected, "c:يا رب")
        XCTAssertEqual(try support.makeTasbih().custom, model.custom)
    }

    /// `deleteTasbihPhrase`: the phrase leaves the list, its counts stay in the day's total, and saving it again
    /// shows them.
    @MainActor
    func testDeletingAPhraseKeepsItsCounts() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        XCTAssertNotNil(model.addPhrase("حسبي الله"))
        XCTAssertNotNil(model.addPhrase("يا رب"))
        for _ in 0..<2 { XCTAssertNotNil(model.add()) }

        XCTAssertEqual(model.deletePhrase("حسبي الله"), Change(ring: .step,
                                                              announcement: .now("حُذفت العبارة: حسبي الله")))
        XCTAssertEqual(model.selected, "c:يا رب", "another phrase stays selected")
        XCTAssertEqual(model.deletePhrase("يا رب"), Change(ring: .step, announcement: .now("حُذفت العبارة: يا رب")))
        XCTAssertEqual(model.selected, "subhan")
        XCTAssertEqual(model.custom, [])
        XCTAssertNil(model.deletePhrase("يا رب"))
        XCTAssertEqual(model.dayTotal, 2)
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.phraseKey), ["c:يا رب"])
        XCTAssertEqual(try support.database.settings.value(for: .tasbihSelected), "subhan")
        XCTAssertEqual(try support.database.settings.value(for: .tasbihCustomPhrases), [])

        XCTAssertNotNil(model.addPhrase("يا رب"))
        XCTAssertEqual(model.count, 2)
    }

    /// `canonicalTasbihDays`: a phrase saved again in another spelling takes the counts its earlier spelling kept,
    /// today and before; a day that counted both sums them and keeps the earlier first use.
    @MainActor
    func testAddingAPhraseAdoptsTheCountsOfAnEarlierSpelling() throws {
        let support = try PortableTestSupport()
        let tasbih = support.database.tasbih
        let earlierDay = "2026-10-10"
        try tasbih.setCount(1, for: "hamd", on: earlierDay)
        try tasbih.setCount(2, for: "c:يَا رَبّ", on: earlierDay)
        try tasbih.setCount(3, for: "c:يَا رَبّ", on: support.today)
        try tasbih.setCount(1, for: "subhan", on: support.today)
        try tasbih.setCount(4, for: "c:يا رب", on: support.today)
        let model = try support.makeTasbih()
        XCTAssertEqual(model.dayTotal, 8)

        XCTAssertEqual(model.addPhrase("يا رب"), Change(ring: .step, announcement: .now("أُضيفت العبارة: يا رب")))
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "c:يا رب", count: 7),
                                      TasbihModel.PhraseCount(key: "subhan", count: 1)])
        XCTAssertEqual(model.count, 7)
        XCTAssertEqual(model.dayTotal, 8)
        let today = try tasbih.counts(on: support.today)
        XCTAssertEqual(today.map(\.phraseKey), ["c:يا رب", "subhan"])
        XCTAssertEqual(today.map(\.firstUse), [1, 2])
        let earlier = try tasbih.counts(on: earlierDay)
        XCTAssertEqual(earlier.map(\.phraseKey), ["hamd", "c:يا رب"])
        XCTAssertEqual(earlier.map(\.count), [1, 2])
        XCTAssertEqual(try tasbih.phraseKeys(), ["c:يا رب", "hamd", "subhan"])
        XCTAssertEqual(try support.makeTasbih().counts, model.counts)
    }

    /// Two spellings whose tashkeel is only ordered differently are equal to Swift's `==` and two phrases to the PWA:
    /// saving one takes the other's counts, and the counter shows one phrase.
    @MainActor
    func testSpellingsThatDifferOnlyInTashkeelOrderAreMerged() throws {
        let support = try PortableTestSupport()
        let saved = "رب\u{0651}\u{064E}"
        let earlier = "رب\u{064E}\u{0651}"
        XCTAssertEqual(saved, earlier)
        try support.database.tasbih.setCount(5, for: TasbihText.customKey(earlier), on: support.today)
        let model = try support.makeTasbih()

        XCTAssertNotNil(model.addPhrase(saved))
        XCTAssertEqual(Array(model.selected.utf16), Array(TasbihText.customKey(saved).utf16))
        XCTAssertEqual(model.counts.count, 1)
        XCTAssertEqual(Array(model.counts[0].key.utf16), Array(model.selected.utf16))
        XCTAssertEqual(model.count, 5)
        let stored = try support.database.tasbih.counts(on: support.today)
        XCTAssertEqual(stored.map { Array($0.phraseKey.utf16) }, [Array(TasbihText.customKey(saved).utf16)])
        XCTAssertEqual(stored.map(\.count), [5])
    }

    /// `normalizeTasbihState`: saved phrases are cleaned, and one that names a preset or an earlier phrase, or is past
    /// the eighth, is dropped; a target out of range reads as ٣٣; a selection that is not available reads as
    /// «سبحان الله», and a saved phrase's other spelling as the saved one.
    @MainActor
    func testLoadingNormalizesTheStoredPreferences() throws {
        let support = try PortableTestSupport()
        let settings = support.database.settings
        let extra = ["حسبي الله", "يا حي يا قيوم", "رضيت بالله ربا", "اللهم اغفر لي", "رب زدني علما", "اللهم أعني",
                     "ربنا آتنا", "سبحان ربي العظيم"]
        try settings.set(["  يا   رب ", "يَا رَبّ", "سبحان الله", "", "ـــ"] + extra, for: .tasbihCustomPhrases)
        try settings.set("c:يَا رَبّ", for: .tasbihSelected)
        try settings.set(10_000, for: .tasbihTarget)
        var model = try support.makeTasbih()
        XCTAssertEqual(model.custom, ["يا رب"] + extra.prefix(7))
        XCTAssertEqual(model.selected, "c:يا رب")
        XCTAssertEqual(model.target, 33)

        for (stored, target) in [(-5, 33), (0, nil), (250, 250), (9999, 9999)] as [(Int, Int?)] {
            try settings.set(stored, for: .tasbihTarget)
            XCTAssertEqual(try support.makeTasbih().target, target, "\(stored)")
        }
        for (stored, selected) in [("c:سبحان ربي العظيم", "subhan"), ("takbir", "takbir"), ("c:", "subhan"),
                                   ("gone", "subhan")] {
            try settings.set(stored, for: .tasbihSelected)
            model = try support.makeTasbih()
            XCTAssertEqual(model.selected, selected, stored)
        }
    }

    /// `resetTasbihProgress` and `deleteTasbihHistory`: no phrase is counted today, and the history the scope covers
    /// goes; the phrase, target and saved phrases stay. The confirmations count the earlier days with a count;
    /// «تقدم اليوم» asks only while a phrase is counted today (`resetDayButton`).
    @MainActor
    func testScopedResetsKeepThePreferences() throws {
        let support = try PortableTestSupport()
        try support.database.tasbih.setCount(4, for: "subhan", on: "2026-10-10")
        let model = try support.makeTasbih()
        XCTAssertTrue(model.hasHistory)
        XCTAssertTrue(model.canReset, "history alone is resettable")
        XCTAssertNil(model.confirmation(for: .day))
        XCTAssertEqual(model.confirmation(for: .everything), DeckConfirmation(
            title: "حذف كل شيء؟", message: "ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع."))

        for _ in 0..<2 { XCTAssertNotNil(model.add()) }
        XCTAssertNotNil(model.setTarget(100))
        XCTAssertNotNil(model.addPhrase("يا رب"))
        XCTAssertNotNil(model.add())
        XCTAssertEqual(model.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع.",
                       "today's counts are today's progress")
        XCTAssertEqual(model.confirmation(for: .day), DeckConfirmation(
            title: "إعادة تقدم اليوم؟",
            message: "ستُعاد عدادات المسبحة اليوم (٣)، مع بقاء السجل كما هو. لا يمكن التراجع."))

        XCTAssertTrue(model.reset(.day))
        XCTAssertNil(model.confirmation(for: .day), "nothing counted today")
        XCTAssertEqual(model.counts, [])
        XCTAssertEqual(model.dayTotal, 0)
        XCTAssertTrue(model.hasHistory)
        XCTAssertTrue(model.canReset)
        XCTAssertEqual(model.selected, "c:يا رب")
        XCTAssertEqual(model.target, 100)
        XCTAssertEqual(model.custom, ["يا رب"])
        XCTAssertTrue(try support.database.tasbih.counts(on: support.today).isEmpty)
        XCTAssertEqual(try support.database.tasbih.counts(on: "2026-10-10").map(\.count), [4])

        XCTAssertNotNil(model.add())
        XCTAssertTrue(model.reset(.everything))
        XCTAssertEqual(model.counts, [])
        XCTAssertFalse(model.hasHistory)
        XCTAssertFalse(model.canReset)
        XCTAssertEqual(try support.database.tasbih.phraseKeys(), [])
        XCTAssertEqual(model.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا. لا يمكن التراجع.")
        XCTAssertEqual(model.selected, "c:يا رب")
        XCTAssertEqual(model.target, 100)

        XCTAssertNotNil(model.add())
        XCTAssertTrue(model.reset(.week))
        XCTAssertEqual(model.counts, [])
        XCTAssertFalse(model.canReset)
        XCTAssertTrue(try support.database.tasbih.counts(on: support.today).isEmpty)
    }

    /// `ensureCurrentDay`: a new day shows that day's counts and keeps the phrase and target; the day before becomes
    /// history. A clock moved back shows the earlier date's own counts.
    @MainActor
    func testRollingShowsEachDaysOwnCounts() throws {
        let support = try PortableTestSupport()
        let model = try support.makeTasbih()
        for _ in 0..<3 { XCTAssertNotNil(model.add()) }
        XCTAssertNotNil(model.setTarget(100))
        let next = "2026-10-15"
        try support.database.tasbih.setCount(2, for: "hamd", on: next)

        model.roll(to: next)
        XCTAssertEqual(model.date, next)
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "hamd", count: 2)])
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.dayTotal, 2)
        XCTAssertTrue(model.hasHistory)
        XCTAssertEqual(model.selected, "subhan")
        XCTAssertEqual(model.target, 100)
        XCTAssertNotNil(model.add())
        XCTAssertEqual(try support.database.tasbih.counts(on: next).map(\.phraseKey), ["hamd", "subhan"])
        model.roll(to: next)
        XCTAssertEqual(model.count, 1, "the same day does not roll")

        model.roll(to: support.today)
        XCTAssertEqual(model.date, support.today)
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "subhan", count: 3)])
        XCTAssertFalse(model.hasHistory, "no day before it has a count")
    }
}
