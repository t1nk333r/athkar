import AthkarCore
import Foundation

/// The day rollover of the three decks (`ensureCurrentDay`), apart from the clock: both sessions move to a local
/// date, and each deck's gate answers for its own session only. The morning and evening decks follow the adhkar
/// session and the ruqyah deck its own, so a day one session cannot read never holds up the other's decks.
@MainActor
struct DayRollover {
    let adhkar: AdhkarSessionModel
    let ruqyah: RuqyahDeckModel

    /// Rolls both sessions to `today` and returns the decks whose day changed or still cannot be read: a tap, reset,
    /// target change or index choice made on them belongs to the day before and is dropped.
    ///
    /// Both rolls always run. A session already on `today` returns at once, and the adhkar roll is also what ends a
    /// load still pending for a later date once the clock is back on the day shown.
    func roll(to today: String) -> Set<DeckID> {
        var stale: Set<DeckID> = []
        if adhkar.state.date != today { stale.formUnion([.morning, .evening]) }
        if ruqyah.progress.date != today { stale.insert(.ruqyah) }
        adhkar.roll(to: today)
        ruqyah.roll(to: today)
        return stale
    }
}
