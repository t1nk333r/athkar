import AthkarCore
import Foundation

/// The decks of the أذكار screen: the PWA's `tabOrder`, the ruqyah, and «سور».
enum DeckID: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, ruqyah, suwar

    var id: String { rawValue }
}

/// What distinguishes one deck from another beyond its cards: its names and wording. Counting, navigation and
/// completion rules live behind ``DeckModel``; ``DeckView`` renders any deck from these two.
struct DeckDefinition: Sendable {
    var id: DeckID
    /// `sectionNames[period]`, or the ruqyah or «سور» deck's name.
    var title: String
    /// How the position is spoken: «الذكر ٢ من ٢٦», «المقطع ٢ من ١٥».
    var cardNoun: String
    /// The card list's accessibility name (`list` `aria-label` in the PWAs).
    var cardsLabel: String
    var navigationLabel: String
    var hint: String
    /// The quick index's title, and the position button's hint that opens it.
    var indexTitle: String
    var indexHint: String
    /// Section chips start from their content's width and share the rest of the row (the ruqyah PWA's `.sura-chip`,
    /// `flex: 1 1 auto`, since «ق» and «الكافرون ✓» differ so much); otherwise they take equal shares (`flex: 1 1 0`).
    var chipsGrowFromContent = false

    static let morning = adhkar(.morning, "أذكار الصباح")
    static let evening = adhkar(.evening, "أذكار المساء")
    static let ruqyah = DeckDefinition(
        id: .ruqyah, title: "رقية القرين", cardNoun: "المقطع", cardsLabel: "مقاطع رقية القرين",
        navigationLabel: "التنقل بين مقاطع الرقية", hint: "اضغط على البطاقة بعد كل قراءة؛ واسحب للتنقل بين المقاطع.",
        indexTitle: "فهرس الرقية", indexHint: "يعرض فهرس الرقية للانتقال إلى مقطع", chipsGrowFromContent: true)
    /// The athkar PWA's «سور» tab, which keeps the adhkar decks' navigation label and hint. Its chips take equal
    /// shares, as the athkar PWA's `.sura-chip` does (`flex: 1 1 0`).
    static let suwar = DeckDefinition(
        id: .suwar, title: "سور", cardNoun: "الصفحة", cardsLabel: "صفحات السور",
        navigationLabel: "التنقل بين بطاقات الأذكار", hint: "اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال.",
        indexTitle: "فهرس السورة", indexHint: "يعرض فهرس السورة للانتقال إلى صفحة")

    private static func adhkar(_ period: Period, _ title: String) -> DeckDefinition {
        DeckDefinition(id: period == .morning ? .morning : .evening, title: title, cardNoun: "الذكر",
                       cardsLabel: "بطاقات \(title)", navigationLabel: "التنقل بين بطاقات الأذكار",
                       hint: "اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال.",
                       indexTitle: "فهرس الورد", indexHint: "يعرض فهرس الورد للانتقال إلى ذكر")
    }
}

/// One part of a deck the reader picks with a chip (`.sura-chip` in both PWAs): a sura of the ruqyah or of «سور».
struct DeckSection: Identifiable, Equatable {
    var id: String
    /// The chip's text: the sura's name without «سورة ».
    var title: String
    /// Complete today (the chip's «✓»).
    var isComplete: Bool
    /// «سورة ق», or «سورة ق، مكتملة اليوم».
    var accessibilityLabel: String
}

/// A card as ``DeckView`` shows it: its content, counter state and spoken labels.
struct DeckCard: Identifiable, Equatable {
    enum Content: Equatable {
        case dhikr(AdhkarItemContent)
        case ruqyah(RuqyahSegmentContent)
        /// A «سور» page of `surah`, with the basmala above a sura's first page only.
        case page(SuwarPageContent, surah: String, basmala: String?)
    }

    enum Status: Equatable {
        /// `count/target`, written left to right as in the PWAs.
        case numeric
        /// A phrase in place of numbers («اضغط بعد القراءة», «تمت القراءة»).
        case text(String)
    }

    var id: String
    /// Position in content order, 1-based: the card's number, which long-order never changes.
    var number: Int
    var content: Content
    var count: Int
    var target: Int
    /// «ثلاث مرات», «مرة واحدة», «٧ مرات».
    var requirement: String
    /// Targets the reader may choose (`targetOptions`), for the «الهدف» picker.
    var targetOptions: [Int]?
    var status: Status
    /// Review items are shown but never counted.
    var isReview: Bool
    /// The counter's spoken state (`progressLabel` / `segmentLabel`).
    var progressLabel: String
    /// The card tap target's spoken name.
    var tapLabel: String
    var resetLabel: String
    var targetLabel: String

    var isComplete: Bool { isReview || count >= target }
}

/// The session summary above a deck.
struct DeckSummary: Equatable {
    var copy: String
    var value: Int
    var total: Int
    var isComplete: Bool
    var accessibilityLabel: String
    /// The ruqyah deck's today line («رقية اليوم: ٣ من ٣٣ تكرارًا»), which keeps the whole day while the row above
    /// follows the shown sura.
    var status: String?
    /// Whether the today line reads as complete.
    var statusIsComplete = false
}

/// A question asked before a destructive change.
struct DeckConfirmation: Equatable, Identifiable {
    var title: String
    var message: String
    var confirmTitle = "إعادة"

    var id: String { title + message }
}

/// What a counter change did, so the view can play the haptic, advance, or open the completion dialog.
struct DeckChange: Equatable {
    /// A tap brought the card to its target.
    var completedCard = false
    /// The session, or the section on screen, just became complete by its counters: open the completion dialog.
    var completedDeck = false
    /// Move to the next card after the auto-advance delay.
    var advance = false
    /// Play the 45 ms completion haptic (when the haptics setting is on). Each deck decides when.
    var haptic = false
}

/// The completion dialog of a deck.
struct DeckCompletion: Equatable {
    enum Primary: Equatable {
        case open(DeckID)
        case restart
        /// Another section of the same deck (the ruqyah PWA's «الانتقال إلى …» to the next incomplete sura).
        case openSection(String)
    }

    let title: String
    let message: String
    let time: String?
    let dismissTitle: String
    /// The second button's title and action, set together; a dialog without one has «تم» only (the «سور» sura dialog
    /// hides `completionSwitch`).
    let primaryTitle: String?
    let primary: Primary?

    init(title: String, message: String, time: String?, dismissTitle: String,
         primary: (title: String, action: Primary)?) {
        self.title = title
        self.message = message
        self.time = time
        self.dismissTitle = dismissTitle
        primaryTitle = primary?.title
        self.primary = primary?.action
    }
}

/// The scoped reset picker's three choices (`resetDayProgress`, `resetWeek`, `resetEverything`).
enum ResetScope: CaseIterable, Identifiable {
    case day, week, everything

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "تقدم اليوم"
        case .week: "هذا الأسبوع"
        case .everything: "كل شيء"
        }
    }

    var detail: String {
        switch self {
        case .day: "إعادة عدادات اليوم فقط مع بقاء السجل كما هو."
        case .week: "إعادة عدادات اليوم وحذف سجل آخر سبعة أيام."
        case .everything: "إعادة العدادات وحذف السجل كاملًا."
        }
    }

    /// What the PWAs announce once the reset is done.
    var announcement: String {
        switch self {
        case .day: "أُعيدت عدادات اليوم"
        case .week: "حُذف سجل آخر سبعة أيام"
        case .everything: "حُذف السجل كاملًا"
        }
    }

    /// `resetWeek` / `resetEverything` confirmation copy, from the number of recorded days they delete.
    func confirmation(recordedDays: Int) -> DeckConfirmation? {
        switch self {
        case .day:
            nil
        case .week:
            DeckConfirmation(
                title: "حذف سجل هذا الأسبوع؟",
                message: "ستُعاد عدادات اليوم، وسيُحذف "
                    + (recordedDays > 0 ? "سجل \(ArabicFormat.dayCount(recordedDays)) من آخر أسبوع" : "سجل آخر سبعة أيام")
                    + ". لا يمكن التراجع.")
        case .everything:
            DeckConfirmation(
                title: "حذف كل شيء؟",
                message: "ستُعاد العدادات وسيُحذف السجل كاملًا"
                    + (recordedDays > 0 ? " (\(ArabicFormat.dayCount(recordedDays)))" : "") + ". لا يمكن التراجع.")
        }
    }
}

/// A deck's state and rules, as ``DeckView`` drives them. The adhkar decks share one session (resets and manual
/// completion span both periods, as in the PWA); the ruqyah deck has its own.
@MainActor
protocol DeckModel: AnyObject {
    var definition: DeckDefinition { get }
    /// In deck order.
    var cards: [DeckCard] { get }
    var currentIndex: Int { get }
    var summary: DeckSummary { get }
    /// Today's session is complete (the tab's ✓).
    var isComplete: Bool { get }
    var completion: DeckCompletion { get }

    func show(_ index: Int)
    /// Whether «التالي» and a forward swipe may leave the card at `index` (the adhkar deck waits for it to be
    /// read unless the session was marked complete manually).
    func canMoveForward(from index: Int) -> Bool
    /// One tap on the card: `nil` when nothing was counted.
    func tap(cardAt index: Int) -> DeckChange?
    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange?
    /// The question to ask before resetting the card's counter, or `nil` to reset at once.
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation?
    func resetCard(at index: Int)

    /// Whether the scoped reset has anything to reset (`hasResettableState`).
    var canReset: Bool { get }
    /// The question to ask before a scoped reset, or `nil` to reset at once.
    func confirmation(for scope: ResetScope) -> DeckConfirmation?
    /// Whether the reset was stored: `false` when it was refused and changed nothing, so it is not announced.
    @discardableResult
    func reset(_ scope: ResetScope) -> Bool

    /// The chips above the summary; empty for a deck without sections. ``cards``, ``summary``, ``isComplete`` and
    /// ``completion`` then describe the selected section.
    var sections: [DeckSection] { get }
    var selectedSectionID: String? { get }
    func selectSection(_ id: String)
    /// The card list's spoken name: ``DeckDefinition/cardsLabel``, or the selected section's («مقاطع سورة ق»).
    var cardsLabel: String { get }
    /// The whole deck's summary and completion, for the أخرى list: ``summary`` and ``isComplete`` unless the deck
    /// has sections.
    var listSummary: DeckSummary { get }
    var isDayComplete: Bool { get }
}

extension DeckModel {
    var sections: [DeckSection] { [] }
    var selectedSectionID: String? { nil }
    func selectSection(_ id: String) {}
    var cardsLabel: String { definition.cardsLabel }
    var listSummary: DeckSummary { summary }
    var isDayComplete: Bool { isComplete }
}

/// A card chosen in the quick index, with the deck as the reader saw it when choosing.
struct DeckIndexChoice: Equatable {
    var cardID: String
    var cards: [DeckCard]
    var currentIndex: Int
}

extension DeckModel {
    func positionLabel(_ index: Int) -> String {
        "\(ArabicFormat.number(index + 1)) من \(ArabicFormat.number(cards.count))"
    }

    func spokenPosition(_ index: Int) -> String {
        "\(definition.cardNoun) \(positionLabel(index))"
    }

    /// Whether the quick index may open the card at `index`: only a card «السابق» and «التالي» could reach from the
    /// current one. Earlier cards always; a later card only when every card from the current one up to it may be
    /// left forward, so the adhkar lock holds until the period is marked complete manually, and the ruqyah lock until
    /// each segment is read.
    func canReach(_ index: Int) -> Bool {
        guard cards.indices.contains(index) else { return false }
        return index <= currentIndex || (currentIndex..<index).allSatisfy { canMoveForward(from: $0) }
    }

    func indexChoice(of cardID: String) -> DeckIndexChoice {
        DeckIndexChoice(cardID: cardID, cards: cards, currentIndex: currentIndex)
    }

    /// Where a quick-index choice leads once the sheet has closed: the chosen card's index, or `nil` to stay on the
    /// current card when the deck changed after the choice (a day rollover) or the card can no longer be reached.
    func destination(of choice: DeckIndexChoice) -> Int? {
        guard cards == choice.cards, currentIndex == choice.currentIndex,
              let index = cards.firstIndex(where: { $0.id == choice.cardID }), canReach(index)
        else { return nil }
        return index
    }
}
