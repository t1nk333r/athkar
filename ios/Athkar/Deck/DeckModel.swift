import AthkarCore
import Foundation

/// The three decks of the أذكار screen (the PWA's `tabOrder`).
enum DeckID: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, ruqyah

    var id: String { rawValue }
}

/// What distinguishes one deck from another beyond its cards: its names and wording. Counting, navigation and
/// completion rules live behind ``DeckModel``; ``DeckView`` renders any deck from these two.
struct DeckDefinition: Sendable {
    var id: DeckID
    /// `sectionNames[period]`, or the ruqyah deck's name.
    var title: String
    /// How the position is spoken: «الذكر ٢ من ٢٦», «المقطع ٢ من ١٥».
    var cardNoun: String
    /// The card list's accessibility name (`list` `aria-label` in the PWAs).
    var cardsLabel: String
    var navigationLabel: String
    var hint: String

    static let morning = adhkar(.morning, "أذكار الصباح")
    static let evening = adhkar(.evening, "أذكار المساء")
    static let ruqyah = DeckDefinition(
        id: .ruqyah, title: "رقية القرين", cardNoun: "المقطع", cardsLabel: "مقاطع رقية القرين",
        navigationLabel: "التنقل بين مقاطع الرقية", hint: "اضغط على البطاقة بعد كل قراءة؛ واسحب للتنقل بين المقاطع.")

    private static func adhkar(_ period: Period, _ title: String) -> DeckDefinition {
        DeckDefinition(id: period == .morning ? .morning : .evening, title: title, cardNoun: "الذكر",
                       cardsLabel: "بطاقات \(title)", navigationLabel: "التنقل بين بطاقات الأذكار",
                       hint: "اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال.")
    }
}

/// A card as ``DeckView`` shows it: its content, counter state and spoken labels.
struct DeckCard: Identifiable, Equatable {
    enum Content: Equatable {
        case dhikr(AdhkarItemContent)
        case ruqyah(RuqyahSegmentContent)
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
    /// The ruqyah deck's today line («رقية اليوم لم تكتمل بعد.»).
    var status: String?
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
    /// A tap brought the card to its target (the 45 ms haptic).
    var completedCard = false
    /// The session just became complete by its counters: open the completion dialog.
    var completedDeck = false
    /// Move to the next card after the auto-advance delay.
    var advance = false
}

/// The completion dialog of a deck.
struct DeckCompletion: Equatable {
    enum Primary: Equatable {
        case open(DeckID)
        case restart
    }

    var title: String
    var message: String
    var time: String?
    var dismissTitle: String
    var primaryTitle: String
    var primary: Primary
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
    func reset(_ scope: ResetScope)
}

extension DeckModel {
    func positionLabel(_ index: Int) -> String {
        "\(ArabicFormat.number(index + 1)) من \(ArabicFormat.number(cards.count))"
    }

    func spokenPosition(_ index: Int) -> String {
        "\(definition.cardNoun) \(positionLabel(index))"
    }
}
