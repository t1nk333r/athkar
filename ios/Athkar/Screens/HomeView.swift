import AthkarCore
import SwiftUI

/// The أذكار screen: header (the prayer row or the title), the الصباح / المساء / أخرى switch, the session summary with
/// the «⋯» menu (the أخرى layout, إعادة, الإعدادات) and the
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
    /// «استيراد من تطبيق الويب» for a file opened in the app.
    @State private var openedTransfer: TransferImportModel?

    private struct ScopeConfirmation {
        var scope: ResetScope
        var confirmation: DeckConfirmation
    }

    var body: some View {
        GeometryReader { proxy in
            let palette = Palette.resolve(colorScheme)
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
            header(palette: palette)
            // A section of أخرى leads back through its title, so the switch shows only on the two decks and the list.
            if app.tab != .other || app.otherSection == nil {
                tabs(palette: palette)
            }
            if app.showsOtherList {
                OtherSectionsView(app: app)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .prayerTimes {
                PrayerTimesView(model: app.prayer, reminders: app.reminders) { app.otherSection = .today }
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .salawat {
                SalawatView(app: app)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .sleep {
                SleepView(content: app.sleep)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .today {
                TodayView(app: app)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .calendar {
                TrackerCalendarView(app: app)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.tab == .other, app.otherSection == .qibla {
                QiblaView(prayer: app.prayer, haptics: app.settings.haptics) { app.otherSection = .prayerTimes }
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if app.showsTasbih {
                // The PWA hides the summary row here: the chips sit above the card.
                TasbihView(model: app.tasbih, haptics: app.settings.haptics, ensureToday: { app.ensureTasbihDay() })
                    .frame(maxHeight: .infinity)
            } else {
                summary(deck, palette: palette)
                    .padding(.top, 5.6)
                    .padding(.bottom, 16)
                deckView
            }
        }
        .padding(.horizontal, min(max(10, width * 0.028), 13.6))
        .padding(.top, 4)
        .padding(.bottom, 6)
        // Controls stop growing at the largest standard size so the one-screen layout holds; the reading text keeps
        // following every size, accessibility sizes included, through `typeScale`. Sheets below are not capped.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(palette.background.ignoresSafeArea())
        .sheet(isPresented: $showsSettings) {
            SettingsView(app: app)
                .environment(\.palette, palette)
        }
        .sheet(item: $openedTransfer) { model in
            TransferImportView(model: model)
                .environment(\.palette, palette)
        }
        .task(id: app.pendingTransferFile?.id) { await presentOpenedFile() }
        // A route opened from outside (a URL, a quick action, a reminder): the place it opens shows, not a sheet.
        .onChange(of: app.routesOpened) { closeSheets() }
        .sheet(isPresented: $showsResetScope, onDismiss: confirmChosenScope) {
            ResetScopeSheet { scope in
                // A scope with a question asks once this sheet is gone; a deck's «تقدم اليوم» resets at once.
                if scope == .day, app.resettable?.confirmation(for: .day) == nil {
                    if app.resettable?.reset(.day) == true {
                        AccessibilityNotification.Announcement(scope.announcement).post()
                    }
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
                case let .openSection(section): app.deck(id).selectSection(section)
                case nil: break
                }
            }
            .environment(\.palette, palette)
        }
        .alert(scopeConfirmation?.confirmation.title ?? "", isPresented: Binding(
            get: { scopeConfirmation != nil }, set: { if !$0 { scopeConfirmation = nil } }),
            presenting: scopeConfirmation
        ) { pending in
            Button(pending.confirmation.confirmTitle, role: .destructive) {
                // A refused reset changed nothing, so there is nothing to announce.
                if app.resettable?.reset(pending.scope) == true {
                    AccessibilityNotification.Announcement(pending.scope.announcement).post()
                }
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

    private func header(palette: Palette) -> some View {
        HStack(spacing: 9.6) {
            if let section = app.otherSection, app.tab == .other {
                // A section of أخرى: its title leads back to the list, in the title's place so the page keeps its height.
                Button {
                    app.otherSection = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                        Text(section.title)
                            .font(.title3.weight(.bold))
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
            } else if app.settings.homePrayerRow {
                HomePrayerRow(prayer: app.prayer) {
                    app.tab = .other
                    app.otherSection = .prayerTimes
                }
            } else {
                Text("بكرة وأصيلا")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("title")
            }
            // With a deck on screen the «⋯» menu sits in the summary bar; elsewhere (أخرى's list, «مسبحة», أوقات
            // الصلاة) here.
            if !app.showsDeck {
                Spacer(minLength: 0)
                moreMenu(palette: palette)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 8.8)
    }

    /// «⋯»: on the أخرى list, «قائمة» or «شبكة» for its layout; then إعادة (the scope picker for the deck or «مسبحة»
    /// on screen) and الإعدادات.
    private func moreMenu(palette: Palette) -> some View {
        Menu {
            if app.showsOtherList {
                Picker("عرض الأقسام", selection: Binding(get: { app.otherLayout }, set: { app.otherLayout = $0 })) {
                    ForEach(OtherLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.systemImage).tag(layout)
                    }
                }
                .pickerStyle(.inline)
            }
            Button {
                app.ensureCurrentDay()
                if app.resettable?.canReset == true { showsResetScope = true }
            } label: {
                Label("إعادة", systemImage: "arrow.counterclockwise")
            }
            .disabled(app.resettable?.canReset != true)
            .accessibilityIdentifier("header.reset")
            Button {
                showsSettings = true
            } label: {
                Label("الإعدادات", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("header.settings")
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(app.showsOtherList ? "المزيد: العرض وإعادة والإعدادات" : "المزيد: إعادة والإعدادات")
        .accessibilityIdentifier("header.more")
    }

    // MARK: Tabs (`.period-tabs`)

    /// The tab titles on a rule, the selected one in ink and underlined in the accent.
    private func tabs(palette: Palette) -> some View {
        HStack(spacing: 24) {
            ForEach(HomeTab.allCases) { id in
                let selected = app.tab == id
                let complete = Self.deck(id).map { app.deck($0).isComplete } ?? false
                Button {
                    // The selected tab does nothing: a section of أخرى hides the switch and leads back through
                    // its title.
                    if app.tab == id { return }
                    app.ensureCurrentDay()
                    switch id {
                    case .morning: app.selection = .morning
                    case .evening: app.selection = .evening
                    case .other: app.tab = .other
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.tabTitle(id))
                        if complete {
                            Text("✓").foregroundStyle(palette.completed)
                        }
                    }
                    .font(.body.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if selected { Rectangle().fill(palette.accent).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.tabLabel(id) + (complete ? "، مكتملة اليوم" : ""))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("tab.\(id.rawValue)")
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rule() }
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

    /// The deck's section chips, if it has sections, above its summary line and today line: plain text on the page.
    private func summary(_ deck: any DeckModel, palette: Palette) -> some View {
        let summary = deck.summary
        return VStack(alignment: .leading, spacing: 2) {
            if !deck.sections.isEmpty {
                SectionChips(model: deck)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 10) {
                Text(summary.copy)
                    .font(.footnote)
                    .foregroundStyle(summary.isComplete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("summary.copy")
                ProgressLine(value: Double(summary.value), total: Double(summary.total),
                             tint: summary.isComplete ? palette.completed : palette.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary.accessibilityLabel)
                moreMenu(palette: palette)
                    .padding(.vertical, -8)
                    .padding(.trailing, -10)
            }
            if let status = summary.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(summary.statusIsComplete ? palette.completed : palette.textSecondary)
                    .accessibilityIdentifier("summary.status")
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Deck

    @ViewBuilder
    private var deckView: some View {
        let haptics = app.settings.haptics
        switch app.selection {
        case .morning:
            DeckView(model: app.morning, haptics: haptics, ensureCurrentDay: { app.ensureCurrentDay(for: .morning) },
                     onDeckCompleted: { completedDeck = .morning })
            .id(DeckID.morning)
        case .evening:
            DeckView(model: app.evening, haptics: haptics, ensureCurrentDay: { app.ensureCurrentDay(for: .evening) },
                     onDeckCompleted: { completedDeck = .evening })
            .id(DeckID.evening)
        case .ruqyah:
            DeckView(model: app.ruqyah, haptics: haptics, ensureCurrentDay: { app.ensureCurrentDay(for: .ruqyah) },
                     onDeckCompleted: { completedDeck = .ruqyah })
            // One deck view per sura, so a chip switch also cancels a pending auto-advance.
            .id("\(DeckID.ruqyah.rawValue).\(app.ruqyah.selectedSuraID)")
        case .suwar:
            DeckView(model: app.suwar, haptics: haptics, ensureCurrentDay: { app.ensureCurrentDay(for: .suwar) },
                     onDeckCompleted: { completedDeck = .suwar })
            .id("\(DeckID.suwar.rawValue).\(app.suwar.selectedSuraID)")
        }
    }

    // MARK: Flows

    private func confirmChosenScope() {
        guard let scope = chosenScope else { return }
        chosenScope = nil
        if let confirmation = app.resettable?.confirmation(for: scope) {
            scopeConfirmation = ScopeConfirmation(scope: scope, confirmation: confirmation)
        } else if app.resettable?.reset(scope) == true {
            // Nothing left to ask about (a new day rolled while the sheet was open): reset as chosen.
            AccessibilityNotification.Announcement(scope.announcement).post()
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

    /// A file opened in the app (Files, the share sheet, AirDrop) opens «استيراد من تطبيق الويب» on its review. This
    /// screen's sheets close first; anything else on screen is waited for.
    private func presentOpenedFile() async {
        guard let file = app.pendingTransferFile else { return }
        closeSheets(keepingTransfer: true)
        try? await Task.sleep(for: .milliseconds(400))
        while Self.isPresenting, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(400)) }
        guard !Task.isCancelled, app.pendingTransferFile?.id == file.id else { return }
        app.pendingTransferFile = nil
        let model = app.makeTransferImport()
        model.open(fileData: file.data)
        openedTransfer = model
    }

    /// Closes this screen's sheets and alerts (the settings with everything opened from them).
    private func closeSheets(keepingTransfer: Bool = false) {
        showsSettings = false
        showsResetScope = false
        chosenScope = nil
        scopeConfirmation = nil
        completedDeck = nil
        showsLongOrderPrompt = false
        if !keepingTransfer { openedTransfer = nil }
    }

    /// Whether any window is showing a sheet or alert over its content.
    private static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}

