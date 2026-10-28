import AthkarCore
import Foundation
import Observation

/// «سور», one section per sura as the athkar PWA's «سور» tab shows it: today's pages read
/// (`athkar-suwar-v1.read`), the suras completed today (`completedAt`) and the sura on screen (`selected`), as stored
/// in `suwar_page_reads`, `suwar_sura_days` and the `suwar_selected_sura` setting. A page is one card read once. A
/// change is shown only once its transaction is stored, and a day only once it has been read.
@MainActor
@Observable
final class SuwarDeckModel: DeckModel {
    let definition = DeckDefinition.suwar
    /// The selected sura's pages.
    private(set) var cards: [DeckCard] = []
    /// The shown page's position in the selected sura.
    private(set) var currentIndex = 0
    /// The local date the deck shows.
    private(set) var date: String
    /// Today's `suwar_page_reads` page IDs.
    private(set) var readPages: Set<String>
    /// Today's `suwar_sura_days` rows: sura ID → when it was completed.
    private(set) var completedSuwar: [String: Date]
    private(set) var hasHistory: Bool
    /// The sura on screen (`suwarState.selected`), kept across launches.
    private(set) var selectedSuraID: String

    @ObservationIgnored private let content: SuwarContent
    @ObservationIgnored private let repository: SuwarRepository
    @ObservationIgnored private let settings: SettingsRepository
    @ObservationIgnored private let report: (any Error) -> Void
    /// The page each sura showed last since the deck opened (`suwarIndices`); a sura without one opens on its first
    /// unread page, or its last page when every page is read.
    @ObservationIgnored private var suraIndices: [String: Int] = [:]

    init(database: AppDatabase, content: BundledContent, today: String, report: @escaping (any Error) -> Void) throws {
        self.content = content.suwar
        repository = database.suwar
        settings = database.settings
        self.report = report
        date = today
        readPages = try repository.readPages(on: today)
        completedSuwar = try repository.suraDays(on: today)
        hasHistory = try repository.recordedDayCount(.all, before: today) > 0
        // A stored sura the pack no longer has reads as its first sura (`normalizeSuwarState`).
        let stored = try settings.value(for: .suwarSelectedSura)
        selectedSuraID = self.content.suwar.contains { $0.id == stored } ? stored : self.content.suwar.first?.id ?? ""
        currentIndex = openingIndex(of: selectedSura)
        refresh()
    }

    /// `ensureCurrentDay`: a new day starts with that day's pages, and every sura reopens on its first unread page. A
    /// day that cannot be read is not shown: the deck keeps its day, so the next `ensureCurrentDay` tries again.
    func roll(to today: String) {
        guard today != date else { return }
        do {
            let pages = try repository.readPages(on: today)
            let suraDays = try repository.suraDays(on: today)
            let hasHistory = try repository.recordedDayCount(.all, before: today) > 0
            date = today
            readPages = pages
            completedSuwar = suraDays
            self.hasHistory = hasHistory
        } catch {
            report(error)
            return
        }
        suraIndices = [:]
        currentIndex = openingIndex(of: selectedSura)
        refresh()
    }

    // MARK: Sections

    var sections: [DeckSection] {
        content.suwar.map { sura in
            let complete = isComplete(sura)
            return DeckSection(id: sura.id, title: sura.shortName, isComplete: complete,
                               accessibilityLabel: complete ? "\(sura.surah)، مكتملة اليوم" : sura.surah)
        }
    }

    var selectedSectionID: String? { selectedSuraID }

    /// `selectSura`: the choice is stored, then the sura opens where it was left, or on its opening page. A choice
    /// that is not stored is not shown.
    func selectSection(_ id: String) {
        guard id != selectedSuraID, let sura = content.suwar.first(where: { $0.id == id }) else { return }
        do {
            try settings.set(sura.id, for: .suwarSelectedSura)
        } catch {
            report(error)
            return
        }
        suraIndices[selectedSuraID] = currentIndex
        selectedSuraID = sura.id
        currentIndex = suraIndices[sura.id] ?? openingIndex(of: sura)
        refresh()
    }

    /// `updateDeckNavigation`: «صفحات سورة الكهف».
    var cardsLabel: String { "صفحات \(selectedSura.surah)" }

    // MARK: Summary

    /// `updateSuraProgress`: the shown sura's pages.
    var summary: DeckSummary {
        let sura = selectedSura
        let read = pagesRead(in: sura)
        let total = sura.pages.count
        let counted = "\(ArabicFormat.number(read)) من \(ArabicFormat.number(total)) صفحة"
        let complete = isComplete(sura)
        return DeckSummary(copy: complete ? "اكتملت \(sura.surah) اليوم" : counted, value: read, total: total,
                           isComplete: complete, accessibilityLabel: "\(sura.surah): \(counted) مقروءة")
    }

    /// The suras completed today, for the أخرى list (native: the PWA has no such line).
    var listSummary: DeckSummary {
        let done = content.suwar.filter { isComplete($0) }.count
        let copy = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(content.suwar.count)) سور"
        return DeckSummary(copy: copy, value: done, total: content.suwar.count, isComplete: isDayComplete,
                           accessibilityLabel: "سور اليوم: \(copy) مكتملة")
    }

    /// The selected sura is complete today (the summary's colour).
    var isComplete: Bool { isComplete(selectedSura) }

    /// Every sura is complete today (the أخرى cell's ✓).
    var isDayComplete: Bool { !content.suwar.isEmpty && content.suwar.allSatisfy { isComplete($0) } }

    /// `openSuraCompletionDialog`: «تم» alone (`completionSwitch.hidden`).
    var completion: DeckCompletion {
        let sura = selectedSura
        return DeckCompletion(title: "اكتملت قراءة \(sura.surah) بحمد الله",
                              message: "تم حفظ إكمال اليوم محليًا على هذا الجهاز.",
                              time: completedSuwar[sura.id].map { "وقت الإكمال: \(ArabicFormat.time($0))" },
                              dismissTitle: "تم", primary: nil)
    }

    // MARK: Cards

    func show(_ index: Int) {
        currentIndex = max(0, min(index, cards.count - 1))
    }

    /// `updateDeckNavigation`: «التالي» and a forward swipe wait until the shown page is read.
    func canMoveForward(from index: Int) -> Bool {
        guard index < cards.count - 1, let page = selectedSura.pages[safe: index] else { return false }
        return readPages.contains(page.id)
    }

    /// `markPageRead`: plays the haptic, records the page, and when it completes the sura records that (once) and
    /// opens the sura's dialog; otherwise the deck moves on. A read page counts nothing more, and a read that is not
    /// stored is not shown: `nil` either way.
    func tap(cardAt index: Int) -> DeckChange? {
        let sura = selectedSura
        guard let page = sura.pages[safe: index], !readPages.contains(page.id) else { return nil }
        let completesSura = sura.pages.allSatisfy { $0.id == page.id || readPages.contains($0.id) }
        let now = Date()
        do {
            try repository.markRead(page.id, of: sura.id, on: date, completingSura: completesSura, at: now)
        } catch {
            report(error)
            return nil
        }
        readPages.insert(page.id)
        // The same transaction inserted the row; an existing row keeps its first time.
        if completesSura, completedSuwar[sura.id] == nil { completedSuwar[sura.id] = now }
        refresh()
        return DeckChange(completedCard: true, completedDeck: completesSura, advance: !completesSura, haptic: true)
    }

    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange? { nil }

    /// `resetSuraPage` asks nothing.
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation? { nil }

    /// `resetSuraPage`: the page is unread again and its sura no longer complete today.
    func resetCard(at index: Int) {
        let sura = selectedSura
        guard let page = sura.pages[safe: index], readPages.contains(page.id) else { return }
        do {
            try repository.unmarkRead(page.id, of: sura.id, on: date)
        } catch {
            report(error)
            return
        }
        readPages.remove(page.id)
        completedSuwar[sura.id] = nil
        refresh()
    }

    // MARK: Scoped reset

    /// `suwarHasResettableState`.
    var canReset: Bool { !readPages.isEmpty || !completedSuwar.isEmpty || hasHistory }

    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let removal: HistoryRemoval
        switch scope {
        case .day: return nil
        case .week: removal = .week(endingAt: Date(), in: .current)
        case .everything: removal = .all
        }
        return scope.confirmation(recordedDays: (try? repository.recordedDayCount(removal, before: date)) ?? 0)
    }

    /// `resetSuwarProgress` and `deleteSuwarHistory`: today's pages and completions are cleared, and every sura reopens
    /// on its first page; the selected sura stays. A reset that is not stored changes nothing and returns `false`.
    @discardableResult
    func reset(_ scope: ResetScope) -> Bool {
        let removal: HistoryRemoval? = switch scope {
        case .day: nil
        case .week: .week(endingAt: Date(), in: .current)
        case .everything: .all
        }
        let keepsHistory: Bool
        do {
            // Read first, so that once the transaction is stored nothing is left to fail.
            keepsHistory = try removal.map {
                try repository.recordedDayCount(.all, before: date) > repository.recordedDayCount($0, before: date)
            } ?? hasHistory
            try repository.reset(on: date, removing: removal)
        } catch {
            report(error)
            return false
        }
        readPages = []
        completedSuwar = [:]
        hasHistory = keepsHistory
        suraIndices = [:]
        currentIndex = 0
        refresh()
        return true
    }

    // MARK: Private

    private var selectedSura: SuwarSura {
        content.suwar.first { $0.id == selectedSuraID } ?? SuwarSura(id: "", surah: "", surahNumber: 0, pages: [])
    }

    /// `suraIsComplete`: every page read today.
    private func isComplete(_ sura: SuwarSura) -> Bool {
        !sura.pages.isEmpty && sura.pages.allSatisfy { readPages.contains($0.id) }
    }

    private func pagesRead(in sura: SuwarSura) -> Int {
        sura.pages.filter { readPages.contains($0.id) }.count
    }

    /// `renderSuraPages`: the first unread page, or the last when every page is read.
    private func openingIndex(of sura: SuwarSura) -> Int {
        sura.pages.firstIndex { !readPages.contains($0.id) } ?? max(0, sura.pages.count - 1)
    }

    /// `suraPageMarkup` and `updateSuraPage` for the selected sura's pages.
    private func refresh() {
        let sura = selectedSura
        cards = sura.pages.enumerated().map { index, page in
            let n = ArabicFormat.number(index + 1)
            let read = readPages.contains(page.id)
            let label = "الصفحة \(n) من \(sura.surah)، \(page.range)، \(read ? "تمت قراءتها" : "لم تُعلَّم كمقروءة")"
            return DeckCard(
                id: page.id, number: index + 1,
                content: .page(page, surah: sura.surah, basmala: index == 0 ? content.basmala : nil),
                count: read ? 1 : 0, target: 1, requirement: page.range, targetOptions: nil,
                status: .text(read ? "تمت القراءة" : "اضغط بعد القراءة"), isReview: false, progressLabel: label,
                tapLabel: "\(read ? "اكتملت" : "تحديد كمقروءة")، \(label)", resetLabel: "إعادة الصفحة \(n)",
                targetLabel: "")
        }
        currentIndex = max(0, min(currentIndex, cards.count - 1))
    }
}
