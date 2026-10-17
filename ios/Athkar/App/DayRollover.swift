import AthkarCore
import Foundation

/// The day rollover of the three decks (`ensureCurrentDay`), apart from the clock: both sessions move to a local
/// date, and the decks whose day changed are named, so a tap, reset, target change or index choice made on them is
/// dropped as belonging to the day before.
@MainActor
struct DayRollover {
    let adhkar: AdhkarSessionModel
    let ruqyah: RuqyahDeckModel

    /// Rolls both sessions to `today` and returns the decks whose day changed.
    func roll(to today: String) -> Set<DeckID> {
        guard today != adhkar.state.date || today != ruqyah.progress.date else { return [] }
        adhkar.roll(to: today)
        ruqyah.roll(to: today)
        return Set(DeckID.allCases)
    }
}
