import SwiftUI

/// The one card-deck component (NATIVE_APP_PLAN.md §3.2): shows the current card of any ``DeckModel`` and
/// reproduces the PWAs' deck behaviour — tap to count, the 45 ms haptic on completing a card, auto-advance
/// 320 ms later (20 ms and unanimated with Reduce Motion), swipe with axis lock (a rightward swipe moves forward,
/// as in the RTL PWAs), «السابق» / «التالي» with the position, and the counter reset.
struct DeckView<Model: DeckModel>: View {
    let model: Model
    let haptics: Bool
    /// Runs the day rollover; `true` means the day changed and the tap, reset or target change must not apply.
    let ensureCurrentDay: () -> Bool
    let onDeckCompleted: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag = DragState()
    @State private var advanceTask: Task<Void, Never>?
    @State private var direction = Direction.forward
    @State private var pendingReset: PendingReset?
    @State private var sourceItem: SourceItem?

    enum Direction { case forward, back }

    private struct DragState {
        var offset: CGFloat = 0
        /// Whether a touch is down on the deck (`swipeGesture` exists).
        var isTracking = false
        var axis: Axis?
        /// Touch-down time, the base of the average velocity (the PWA's `pointerdown`).
        var startedAt = Date.distantPast
        /// `suppressCardClicksUntil`: a tap that ends a horizontal swipe does not count.
        var suppressTapsUntil = Date.distantPast
    }

    private struct PendingReset: Identifiable {
        var index: Int
        var confirmation: DeckConfirmation
        var id: String { confirmation.id }
    }

    struct SourceItem: Identifiable {
        var number: Int
        var item: AdhkarItemContent
        var id: String { item.id }
    }

    var body: some View {
        let cards = model.cards
        let index = model.currentIndex
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    stackDecoration
                    if let card = cards[safe: index] {
                        DeckCardView(
                            card: card,
                            onTap: { tap(index) },
                            onReset: { requestReset(index) },
                            onTarget: { setTarget($0, index) },
                            onSource: {
                                if case let .dhikr(item) = card.content {
                                    sourceItem = SourceItem(number: card.number, item: item)
                                }
                            })
                        .padding(.bottom, 16)
                        .id(card.id)
                        .transition(cardTransition)
                        .offset(x: visualOffset)
                        .opacity(1 - min(abs(drag.offset) / max(1, proxy.size.width) * 0.18, 0.18))
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(swipe(width: proxy.size.width))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(model.definition.cardsLabel)، \(model.spokenPosition(index))")

            navigation(index: index, count: cards.count)
        }
        .onDisappear { advanceTask?.cancel() }
        .alert(pendingReset?.confirmation.title ?? "", isPresented: Binding(
            get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }), presenting: pendingReset
        ) { pending in
            Button(pending.confirmation.confirmTitle, role: .destructive) { resetCard(pending.index) }
            Button("إلغاء", role: .cancel) {}
        } message: { pending in
            Text(pending.confirmation.message)
        }
        .sheet(item: $sourceItem) { source in
            SourceSheet(number: source.number, item: source.item)
        }
    }

    // MARK: Layout

    /// `.athkar-list::before` / `::after`: two paler cards peeking under the current one.
    private var stackDecoration: some View {
        let fill = palette.surface.mixed(0.82, with: palette.background)
        return ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.border))
                .padding(EdgeInsets(top: 16, leading: 18.4, bottom: 1.6, trailing: 18.4))
                .opacity(0.48)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.border))
                .padding(EdgeInsets(top: 8.8, leading: 9.3, bottom: 8.8, trailing: 9.3))
                .opacity(0.72)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// `card-forward` enters from 1rem to the physical left, `card-back` from the right.
    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let dx: CGFloat = direction == .forward ? -16 : 16
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.988)).combined(with: .offset(x: physical(dx))),
            removal: .identity)
    }

    /// Offsets are laid out in the RTL coordinate space; swipes are measured on screen.
    private func physical(_ dx: CGFloat) -> CGFloat { -dx }

    private var visualOffset: CGFloat { physical(drag.offset) }

    private func navigation(index: Int, count: Int) -> some View {
        let canGoBack = index > 0
        let canGoForward = index < count - 1 && model.canMoveForward(from: index)
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                navigationButton("السابق", arrow: "→", arrowFirst: true, enabled: canGoBack,
                                 identifier: "deck.previous") {
                    show(index - 1, .back, announce: true)
                }
                Spacer(minLength: 0)
                Text(model.positionLabel(index))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 72)
                    .accessibilityLabel(model.spokenPosition(index))
                    .accessibilityIdentifier("deck.position")
                Spacer(minLength: 0)
                navigationButton("التالي", arrow: "←", arrowFirst: false, enabled: canGoForward,
                                 identifier: "deck.next") {
                    show(index + 1, .forward, announce: true)
                }
            }
            Text(model.definition.hint)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.definition.navigationLabel)
    }

    private func navigationButton(_ title: String, arrow: String, arrowFirst: Bool, enabled: Bool,
                                  identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if arrowFirst { Text(arrow).accessibilityHidden(true) }
                Text(title)
                if !arrowFirst { Text(arrow).accessibilityHidden(true) }
            }
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(minWidth: 99, minHeight: 44)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.border))
            .shadow(color: .black.opacity(0.06), radius: 11, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(DeckButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.34)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Actions

    private func show(_ target: Int, _ newDirection: Direction, announce: Bool) {
        advanceTask?.cancel()
        direction = newDirection
        if reduceMotion {
            model.show(target)
        } else {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.15)) { model.show(target) }
        }
        if announce { Self.announce(model.spokenPosition(model.currentIndex)) }
    }

    private func tap(_ index: Int) {
        guard Date() >= drag.suppressTapsUntil, !ensureCurrentDay(), let change = model.tap(cardAt: index) else {
            return
        }
        if change.completedCard, haptics { Haptics.shared.playCompletion() }
        if let card = model.cards[safe: index] { Self.announce(card.progressLabel) }
        handle(change, at: index)
    }

    private func setTarget(_ target: Int, _ index: Int) {
        guard !ensureCurrentDay(), let change = model.setTarget(target, forCardAt: index) else { return }
        if let card = model.cards[safe: model.currentIndex] { Self.announce(card.progressLabel) }
        handle(change, at: index)
    }

    private func handle(_ change: DeckChange, at index: Int) {
        if change.completedDeck {
            advanceTask?.cancel()
            onDeckCompleted()
        } else if change.advance {
            scheduleAdvance(from: index)
        }
    }

    /// `scheduleAdvance`: moves on only if the reader is still on that card and it is still complete.
    private func scheduleAdvance(from index: Int) {
        guard index < model.cards.count - 1 else { return }
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(TestHooks.advanceDelayMs ?? (reduceMotion ? 20 : 320)))
            guard !Task.isCancelled, model.currentIndex == index, model.cards[safe: index]?.isComplete == true
            else { return }
            show(index + 1, .forward, announce: true)
        }
    }

    private func requestReset(_ index: Int) {
        guard !ensureCurrentDay() else { return }
        if let confirmation = model.resetConfirmation(forCardAt: index) {
            pendingReset = PendingReset(index: index, confirmation: confirmation)
        } else {
            resetCard(index)
        }
    }

    /// Also run when the question is confirmed, which may be after midnight.
    private func resetCard(_ index: Int) {
        guard !ensureCurrentDay() else { return }
        model.resetCard(at: index)
        if let card = model.cards[safe: index] { Self.announce(card.progressLabel) }
    }

    // MARK: Swipe (`beginCardSwipe` … `finishCardSwipe`)

    /// Recognised from touch-down (the PWA's `pointerdown`), so the swipe's duration starts there; the axis is
    /// decided after 8 points, as in `moveCardSwipe`.
    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !drag.isTracking {
                    drag.isTracking = true
                    drag.startedAt = value.time
                }
                let dx = value.translation.width
                let dy = value.translation.height
                if drag.axis == nil {
                    // Axis lock: the first 8 points decide; a vertical start leaves the gesture to scrolling.
                    guard max(abs(dx), abs(dy)) >= 8 else { return }
                    drag.axis = abs(dy) >= abs(dx) ? .vertical : .horizontal
                }
                guard drag.axis == .horizontal else { return }
                drag.suppressTapsUntil = Date().addingTimeInterval(0.45)
                drag.offset = canNavigate(forward: dx > 0) ? dx : dx * 0.2
            }
            .onEnded { value in
                let axis = drag.axis
                drag.axis = nil
                drag.isTracking = false
                guard axis == .horizontal else {
                    drag.offset = 0
                    return
                }
                drag.suppressTapsUntil = Date().addingTimeInterval(0.45)
                let dx = value.translation.width
                let dy = value.translation.height
                let distance = abs(dx)
                let duration = max(1, value.time.timeIntervalSince(drag.startedAt) * 1000)
                let averageVelocity = abs(dx) / duration
                let recent = value.velocity.width / 1000
                let velocity = (recent > 0) == (dx > 0) ? max(abs(recent), averageVelocity) : averageVelocity
                let threshold = max(32, min(52, width * 0.1))
                let isFlick = distance >= 18 && velocity >= 0.35
                let horizontal = distance > abs(dy) * 0.75
                let forward = dx > 0
                guard horizontal, distance >= threshold || isFlick, canNavigate(forward: forward) else {
                    if reduceMotion {
                        drag.offset = 0
                    } else {
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)) { drag.offset = 0 }
                    }
                    return
                }
                drag.offset = 0
                let index = model.currentIndex
                show(forward ? index + 1 : index - 1, forward ? .forward : .back, announce: true)
            }
    }

    private func canNavigate(forward: Bool) -> Bool {
        let index = model.currentIndex
        return forward ? index < model.cards.count - 1 && model.canMoveForward(from: index) : index > 0
    }

    private static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// `.deck-button:active { transform: scale(0.97) }`.
private struct DeckButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
