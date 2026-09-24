import Foundation

/// Controls for the UI tests, honoured in Debug builds only; Release builds use the real clock and the PWA timings.
enum TestHooks {
    /// Whole days added to today's date, read on every call from the file named by `ATHKAR_UITEST_DAY_OFFSET_FILE`,
    /// so a test can move the running app to the next day without touching the simulator's clock.
    static var dayOffset: Int {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["ATHKAR_UITEST_DAY_OFFSET_FILE"],
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        #else
        return 0
        #endif
    }

    /// Replaces the auto-advance delay (`ATHKAR_UITEST_ADVANCE_DELAY_MS`), so a test can act while an advance is
    /// pending.
    static var advanceDelayMs: Int? {
        #if DEBUG
        ProcessInfo.processInfo.environment["ATHKAR_UITEST_ADVANCE_DELAY_MS"].flatMap { Int($0) }
        #else
        nil
        #endif
    }
}
