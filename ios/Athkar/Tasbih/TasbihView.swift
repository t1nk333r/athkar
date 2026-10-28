import SwiftUI

/// «مسبحة» (the athkar PWA's tasbih tab): the phrase and target chips, the card that counts a tap anywhere on it with
/// the phrase, ring, count and status, then «تراجع», today's total and «إعادة». The count is spoken once taps pause
/// for a second; every multiple of the target plays the haptic and is spoken at once.
struct TasbihView: View {
    let model: TasbihModel
    let haptics: Bool
    /// The day rollover; `true` when «مسبحة» shows today, so a change may apply (`addTasbihCount` counts on the new
    /// day after midnight).
    let ensureToday: () -> Bool

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var surfaceFocused: Bool
    /// The ring as drawn, which follows the model with the change's animation.
    @State private var shownFraction: Double
    /// Bumped when a multiple of the target is reached: the count breathes and the status fades in.
    @State private var reached = 0
    @State private var announceTask: Task<Void, Never>?
    @State private var pendingReset: DeckConfirmation?
    @State private var sheet: Sheet?
    @State private var isPressed = false

    private enum Sheet: String, Identifiable {
        case phrase, target

        var id: String { rawValue }
    }

    init(model: TasbihModel, haptics: Bool, ensureToday: @escaping () -> Bool) {
        self.model = model
        self.haptics = haptics
        self.ensureToday = ensureToday
        _shownFraction = State(initialValue: model.ringFraction)
    }

    var body: some View {
        VStack(spacing: 0) {
            chips
                .padding(.top, 5.6)
                .padding(.bottom, 12)
            card
            controls
                .padding(.top, 12)
            Text("اضغط في أي مكان من البطاقة للعدّ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityIdentifier("tasbih.hint")
        }
        // Another change (a rollover, a reset from «⋯», a new target) sets the ring at once.
        .onChange(of: model.ringFraction) { _, fraction in
            if shownFraction != fraction { shownFraction = fraction }
        }
        .onDisappear { announceTask?.cancel() }
        .alert(pendingReset?.title ?? "", isPresented: Binding(
            get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }), presenting: pendingReset
        ) { confirmation in
            Button(confirmation.confirmTitle, role: .destructive) { resetCount() }
            Button("إلغاء", role: .cancel) { surfaceFocused = true }
        } message: { confirmation in
            Text(confirmation.message)
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .phrase:
                TasbihPhraseSheet(model: model, apply: apply)
                    .environment(\.palette, palette)
            case .target:
                TasbihTargetSheet(model: model, apply: apply)
                    .environment(\.palette, palette)
            }
        }
    }

    // MARK: Chips (`.tasbih-picker`)

    private var chips: some View {
        HStack(spacing: 4.8) {
            chip(identifier: "tasbih.phrase", label: model.phraseButtonLabel) {
                Text("اختيار الذكر")
            } action: {
                _ = ensureToday()
                sheet = .phrase
            }
            .frame(maxWidth: .infinity)
            chip(identifier: "tasbih.target", label: model.targetButtonLabel) {
                Text(model.targetChipText)
            } action: {
                sheet = .target
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func chip(identifier: String, label: String, @ViewBuilder title: () -> some View,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                title()
                Text("▾").accessibilityHidden(true)
            }
            .font(.footnote.weight(.heavy))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12.8)
            .frame(maxWidth: .infinity, minHeight: 36.8)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Card (`.tasbih-card`)

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return ZStack {
            Button(action: add) {
                Color.clear.contentShape(shape)
            }
            .buttonStyle(PressTrackingStyle(isPressed: $isPressed))
            .accessibilityLabel("أضف واحدًا")
            .accessibilityValue(model.summaryLabel)
            .accessibilityIdentifier("tasbih.surface")
            .accessibilityFocused($surfaceFocused)
            .accessibilitySortPriority(1)

            VStack(spacing: 12) {
                Text(model.phrase.label)
                    .font(ReadingFont.quran(metrics.dhikrText))
                    .foregroundStyle(palette.accentStrong)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
                ring
                status
            }
            .padding(min(max(18.4, metrics.viewportWidth * 0.04), 28))
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(palette.surface)
                .overlay(shape.strokeBorder(palette.border))
                .shadow(color: .black.opacity(0.06), radius: 11, y: 6)
        }
        .scaleEffect(isPressed ? 0.993 : 1)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .accessibilityElement(children: .contain)
    }

    /// A dial like a clock face: it starts at 12 o'clock and runs clockwise, never mirrored right to left.
    private var ring: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.03
            ZStack {
                Circle()
                    .stroke(palette.border, lineWidth: line)
                Circle()
                    .trim(from: 0, to: shownFraction)
                    .stroke(model.isReached ? palette.completed : palette.accent,
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(ArabicFormat.number(model.count))
                    .font(.system(size: side * Self.numberScale(model.count), weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(model.count == 0 ? palette.textSecondary
                                     : model.isLap ? palette.completed : palette.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                    .keyframeAnimator(initialValue: 1.0, trigger: reached) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        CubicKeyframe(1.04, duration: 0.13)
                        CubicKeyframe(1, duration: 0.13)
                    }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("tasbih.count")
            }
            .padding(side * 0.04)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 288, maxHeight: 288)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// `30cqi`, and `23cqi` / `18cqi` for four and five digits.
    private static func numberScale(_ count: Int) -> CGFloat {
        switch String(count).count {
        case 5...: 0.18
        case 4: 0.23
        default: 0.30
        }
    }

    private var status: some View {
        let status = model.status
        return HStack(spacing: 4) {
            if status.check {
                Text("✓").accessibilityHidden(true)
            }
            Text(status.text)
        }
        .font(.subheadline.weight(.heavy))
        .foregroundStyle(model.isReached ? palette.completed : palette.textSecondary)
        .keyframeAnimator(initialValue: 1.0, trigger: reached) { content, opacity in
            content.opacity(opacity)
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tasbih.status")
    }

    // MARK: Controls (`.deck-navigation`)

    private var controls: some View {
        let empty = model.count == 0
        return HStack(spacing: 12) {
            controlButton(identifier: "tasbih.undo", enabled: !empty) {
                Text("تراجع")
            } action: {
                undo()
            }
            .accessibilityLabel("تراجع عن العدّة الأخيرة")
            Spacer(minLength: 0)
            Text(model.totalText)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(model.totalLabel)
                .accessibilityIdentifier("tasbih.total")
            Spacer(minLength: 0)
            controlButton(identifier: "tasbih.reset", enabled: !empty) {
                HStack(spacing: 5) {
                    Text("↻").accessibilityHidden(true)
                    Text("إعادة")
                }
            } action: {
                requestReset()
            }
            .accessibilityLabel(model.resetLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("أدوات المسبحة")
    }

    private func controlButton(identifier: String, enabled: Bool, @ViewBuilder title: () -> some View,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title()
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

    private func add() {
        guard ensureToday(), let change = model.add() else { return }
        apply(change)
    }

    /// `undoTasbihCount`: with nothing left to undo, the card takes the focus.
    private func undo() {
        if ensureToday(), let change = model.undo() { apply(change) }
        if model.count == 0 { surfaceFocused = true }
    }

    /// `requestTasbihReset`: asked first; with nothing to reset, the card takes the focus.
    private func requestReset() {
        _ = ensureToday()
        if let confirmation = model.resetConfirmation() {
            pendingReset = confirmation
        } else {
            surfaceFocused = true
        }
    }

    /// Run when the question is confirmed, which may be after midnight: the new day's count of the phrase is reset.
    private func resetCount() {
        if ensureToday(), let change = model.resetCount() { apply(change) }
        surfaceFocused = true
    }

    private func apply(_ change: TasbihModel.Change) {
        if change.haptic, haptics { Haptics.shared.playCompletion() }
        if let ring = change.ring { move(ring) }
        if change.reached, !reduceMotion { reached += 1 }
        switch change.announcement {
        case let .now(text)?: announce(text)
        case .countAfterPause?: announceCountAfterPause()
        case nil: break
        }
    }

    /// The ring moves over 160 ms, retracts over 220 ms, or is set at once after a full lap and with Reduce Motion.
    private func move(_ ring: TasbihModel.Change.Ring) {
        let fraction = model.ringFraction
        guard !reduceMotion, ring != .jump else {
            shownFraction = fraction
            return
        }
        withAnimation(.easeOut(duration: ring == .reset ? 0.22 : 0.16)) { shownFraction = fraction }
    }

    /// `announceTasbih`: every message spoken at once cancels a count announcement still waiting.
    private func announce(_ text: String) {
        announceTask?.cancel()
        announceTask = nil
        AccessibilityNotification.Announcement(text).post()
    }

    /// `scheduleTasbihCountAnnouncement`: the count once taps have paused for a second, so a burst of taps is one
    /// announcement.
    private func announceCountAfterPause() {
        announceTask?.cancel()
        announceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(model.countAnnouncement).post()
        }
    }
}

/// Reports the tap target's pressed state, so the whole card scales (`.tasbih-card:active`).
private struct PressTrackingStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
    }
}
