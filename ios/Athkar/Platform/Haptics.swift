import CoreHaptics
import UIKit

/// The PWAs' completion vibration (`navigator.vibrate(hapticDurationMs)`, 45 ms): a 45 ms continuous haptic event
/// through Core Haptics, or an impact tap on hardware without it.
@MainActor
final class Haptics {
    static let shared = Haptics()
    static let durationMs = 45

    private var engine: CHHapticEngine?
    private lazy var fallback = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
    }

    func playCompletion() {
        guard let engine else {
            fallback.impactOccurred()
            return
        }
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                             CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                relativeTime: 0, duration: Double(Self.durationMs) / 1000)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback.impactOccurred()
        }
    }
}
