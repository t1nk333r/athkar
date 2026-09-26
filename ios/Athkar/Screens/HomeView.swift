import AthkarCore
import SwiftUI

/// The أذكار screen: header (reset and settings), the الصباح / المساء / أخرى switch, the session summary and the
/// deck; the أخرى tab lists its sections first (``OtherSectionsView``). Laid out like the PWAs' phone layout (`max-width: 45rem` portrait), which fits one screen without
/// scrolling.
struct HomeView: View {
    let app: AppModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSettings = false
    @State private var showsResetScope = false
    /// A week/everything reset chosen in the picker, confirmed once the picker has closed.
    @State private var chosenScope: ResetScope?
    @State private var scopeConfirmation: ScopeConfirmation?
    @State private var completedDeck: DeckID?
    @State private var showsLongOrderPrompt = false

    private struct ScopeConfirmation {
        var scope: ResetScope
        var confirmation: DeckConfirmation
    }

    var body: some View {
        GeometryReader { proxy in
            let palette = Palette.resolve(app.selection, colorScheme)
            let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            content(palette: palette, width: width)
                .environment(\.palette, palette)
                .environment(\.readingMetrics, ReadingMetrics(
                    viewportWidth: width, textSize: app.settings.textSize, lineSpacing: app.settings.lineSpacing,
                    typeScale: ReadingMetrics.typeScale(for: dynamicTypeSize)))
        }
    }

    private func content(palette: Palette, width: CGFloat) -> some View {
        let deck = app.deck(app.selection)
        return VStack(spacing: 0) {
            header(deck, palette: palette)
            tabs(palette: palette)
            if app.showsOtherList {
                OtherSectionsView(app: app)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .prayerTimes {
                PrayerTimesView(model: app.prayer)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                summary(deck.summary, palette: palette)
                    .padding(.top, 5.6)
                    .padding(.bottom, 8)
                deckView
            }
        }
        .padding(.horizontal, min(max(10, width * 0.028), 13.6))
        .padding(.top, 4)
        .padding(.bottom, 6)
        // Controls stop growing at the largest standard size so the one-screen layout holds; the reading text keeps
        // following every size, accessibility sizes included, through `typeScale`. Sheets below are not capped.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background {
            ZStack {
                palette.background
                RadialGradient(colors: [palette.backgroundGlow, palette.background.opacity(0)],
                               center: UnitPoint(x: 0.5, y: -0.25), startRadius: 0, endRadius: 544)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(app: app)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showsResetScope, onDismiss: confirmChosenScope) {
            ResetScopeSheet { scope in
                if scope == .day {
                    deck.reset(.day)
                    AccessibilityNotification.Announcement(scope.announcement).post()
                } else {
                    chosenScope = scope
                }
                showsResetScope = false
            }
            .environment(\.palette, palette)
        }
        .sheet(item: $completedDeck) { id in
            CompletionSheet(completion: app.deck(id).completion) {
                completedDeck = nil
                switch app.deck(id).completion.primary {
                case let .open(other): app.selection = other
                case .restart: app.deck(id).reset(.day)
                }
            }
            .environment(\.palette, palette)
        }
        .alert(scopeConfirmation?.confirmation.title ?? "", isPresented: Binding(
            get: { scopeConfirmation != nil }, set: { if !$0 { scopeConfirmation = nil } }),
            presenting: scopeConfirmation
        ) { pending in
            Button(pending.confirmation.confirmTitle, role: .destructive) {
                deck.reset(pending.scope)
                AccessibilityNotification.Announcement(pending.scope.announcement).post()
            }
            Button("إلغاء", role: .cancel) {}
        } message: { pending in
            Text(pending.confirmation.message)
        }
        .alert("تأجيل الأذكار الطويلة؟", isPresented: $showsLongOrderPrompt) {
            Button("لا، أبقِ الترتيب") { app.answerLongOrderPrompt(moveLongLast: false) }
            Button("نعم، أخّرها") { app.answerLongOrderPrompt(moveLongLast: true) }
        } message: {
            Text("بعض الأذكار تُكرَّر عشر مرات فأكثر، مثل التهليل والتسبيح والاستغفار. هل تفضّل قراءتها في آخر الورد قبل الذكر الأخير؟ يمكنك تغيير ذلك لاحقًا من الإعدادات.")
        }
        .alert("تعذّر الحفظ", isPresented: Binding(get: { app.failure != nil }, set: { if !$0 { app.failure = nil } })) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(app.failure ?? "")
        }
        .task { await promptForLongOrder() }
    }

    // MARK: Header (`.brand-row`)

    private func header(_ deck: any DeckModel, palette: Palette) -> some View {
        let canReset = app.showsDeck && deck.canReset
        return HStack(spacing: 9.6) {
            if let section = app.otherSection, app.tab == .other {
                // A section of أخرى: its title leads back to the list, in the title's place so the page keeps its height.
                Button {
                    app.otherSection = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward").font(.body.weight(.bold))
                        Text(section.title)
                            .font(.title3.weight(.heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(palette.textPrimary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("رجوع إلى أخرى")
                .accessibilityValue(section.title)
                .accessibilityIdentifier("header.back")
            } else {
                Text("بكرة وأصيلا")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("title")
            }
            Spacer(minLength: 0)
            Button {
                app.ensureCurrentDay()
                if app.deck(app.selection).canReset { showsResetScope = true }
            } label: {
                HStack(spacing: 4) {
                    Text("↻").accessibilityHidden(true)
                    Text("إعادة")
                }
                .font(.footnote.weight(.heavy))
                .headerButton(palette)
            }
            .buttonStyle(.plain)
            .disabled(!canReset)
            .opacity(canReset ? 1 : 0.4)
            .accessibilityLabel("خيارات الإعادة")
            .accessibilityIdentifier("header.reset")
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .headerButton(palette)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("فتح الإعدادات")
            .accessibilityIdentifier("header.settings")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8.8)
    }

    // MARK: Tabs (`.period-tabs`)

    private func tabs(palette: Palette) -> some View {
        HStack(spacing: 4) {
            ForEach(HomeTab.allCases) { id in
                let selected = app.tab == id
                let complete = Self.deck(id).map { app.deck($0).isComplete } ?? false
                Button {
                    if app.tab == id {
                        // Tapping أخرى again goes back to its list.
                        if id == .other { app.otherSection = nil }
                        return
                    }
                    app.ensureCurrentDay()
                    switch id {
                    case .morning: app.selection = .morning
                    case .evening: app.selection = .evening
                    case .other: app.tab = .other
                    }
                } label: {
                    HStack(spacing: 6.4) {
                        Image(systemName: Self.icon(id)).imageScale(.small)
                        Text(Self.tabTitle(id))
                        if complete {
                            Text("✓").foregroundStyle(palette.completed)
                        }
                    }
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(selected ? palette.accentStrong : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(selected ? palette.accentSoft : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.tabLabel(id) + (complete ? "، مكتملة اليوم" : ""))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("tab.\(id.rawValue)")
            }
        }
        .padding(4)
        .background(Capsule().fill(palette.surfaceRaised.opacity(0.92)))
        .overlay(Capsule().strokeBorder(palette.border))
        .shadow(color: .black.opacity(0.08), radius: 19, y: 14)
    }

    private static func icon(_ id: HomeTab) -> String {
        switch id {
        case .morning: "sun.max"
        case .evening: "moon"
        case .other: "square.grid.2x2"
        }
    }

    private static func tabTitle(_ id: HomeTab) -> String {
        switch id {
        case .morning: "الصباح"
        case .evening: "المساء"
        case .other: "أخرى"
        }
    }

    private static func tabLabel(_ id: HomeTab) -> String {
        switch id {
        case .morning: DeckDefinition.morning.title
        case .evening: DeckDefinition.evening.title
        case .other: "أخرى"
        }
    }

    /// The deck whose completion the tab's ✓ shows; أخرى shows it per section instead.
    private static func deck(_ id: HomeTab) -> DeckID? {
        switch id {
        case .morning: .morning
        case .evening: .evening
        case .other: nil
        }
    }

    // MARK: Summary (`.session-summary`)

    private func summary(_ summary: DeckSummary, palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9.6) {
                Text(summary.copy)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(summary.isComplete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("summary.copy")
                ProgressView(value: Double(summary.value), total: Double(max(1, summary.total)))
                    .tint(summary.isComplete ? palette.completed : palette.accent)
                    .accessibilityLabel(summary.accessibilityLabel)
                    .accessibilityValue("")
            }
            if let status = summary.status {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(summary.isComplete ? palette.completed : palette.textSecondary)
                    .accessibilityIdentifier("summary.status")
            }
        }
        .padding(.horizontal, 10.4)
        .padding(.vertical, 6.7)
        .background(RoundedRectangle(cornerRadius: 14.4, style: .continuous).fill(palette.surface.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14.4, style: .continuous).strokeBorder(palette.border))
    }

    // MARK: Deck

    @ViewBuilder
    private var deckView: some View {
        let haptics = app.settings.haptics
        switch app.selection {
        case .morning:
            DeckView(model: app.morning, haptics: haptics, ensureCurrentDay: app.ensureCurrentDay,
                     onDeckCompleted: { completedDeck = .morning })
            .id(DeckID.morning)
        case .evening:
            DeckView(model: app.evening, haptics: haptics, ensureCurrentDay: app.ensureCurrentDay,
                     onDeckCompleted: { completedDeck = .evening })
            .id(DeckID.evening)
        case .ruqyah:
            DeckView(model: app.ruqyah, haptics: haptics, ensureCurrentDay: app.ensureCurrentDay,
                     onDeckCompleted: { completedDeck = .ruqyah })
            .id(DeckID.ruqyah)
        }
    }

    // MARK: Flows

    private func confirmChosenScope() {
        guard let scope = chosenScope else { return }
        chosenScope = nil
        if let confirmation = app.deck(app.selection).confirmation(for: scope) {
            scopeConfirmation = ScopeConfirmation(scope: scope, confirmation: confirmation)
        }
    }

    /// `scheduleLongOrderPrompt`: asked once, 0.7 s after launch, and put off while another dialog is open — this
    /// screen's sheets and alerts, or anything else on screen (the source sheet, a card-reset question, the save
    /// failure), which would keep the alert from presenting.
    private func promptForLongOrder() async {
        guard !app.settings.longOrderPromptAnswered else { return }
        try? await Task.sleep(for: .milliseconds(700))
        while !app.settings.longOrderPromptAnswered, !Task.isCancelled {
            let busy = showsSettings || showsResetScope || completedDeck != nil || scopeConfirmation != nil
                || app.failure != nil || Self.isPresenting
            if !busy {
                showsLongOrderPrompt = true
                return
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }

    /// Whether any window is showing a sheet or alert over its content.
    private static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}

private extension View {
    /// `.session-reset`, `.settings-button`.
    func headerButton(_ palette: Palette) -> some View {
        foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.border))
            .contentShape(Capsule())
    }
}
