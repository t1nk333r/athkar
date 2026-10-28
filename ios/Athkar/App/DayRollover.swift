import AthkarCore
import Foundation

/// The day rollover of the decks (`ensureCurrentDay`), apart from the clock: every session moves to a local date, and
/// each deck's gate answers for its own session only. The morning and evening decks follow the adhkar session, and
/// the ruqyah and «سور» decks their own, so a day one session cannot read never holds up the others' decks. «مسبحة»,
/// which is no deck, rolls too; its gate is whether it shows today once rolled (``AppModel/ensureTasbihDay()``).
@MainActor
struct DayRollover {
    let adhkar: AdhkarSessionModel
    let ruqyah: RuqyahDeckModel
    let suwar: SuwarDeckModel
    let tasbih: TasbihModel

    /// Rolls every session to `today` and returns the decks whose day changed or still cannot be read: a tap, reset,
    /// target change or index choice made on them belongs to the day before and is dropped.
    ///
    /// Every roll always runs. A session already on `today` returns at once, and the adhkar roll is also what ends a
    /// load still pending for a later date once the clock is back on the day shown.
    func roll(to today: String) -> Set<DeckID> {
        var stale: Set<DeckID> = []
        if adhkar.state.date != today { stale.formUnion([.morning, .evening]) }
        if ruqyah.progress.date != today { stale.insert(.ruqyah) }
        if suwar.date != today { stale.insert(.suwar) }
        adhkar.roll(to: today)
        ruqyah.roll(to: today)
        suwar.roll(to: today)
        tasbih.roll(to: today)
        return stale
    }
}
