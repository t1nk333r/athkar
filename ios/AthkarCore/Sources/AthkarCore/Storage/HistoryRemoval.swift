import Foundation
import GRDB

/// The records a scoped reset deletes along with today's counters: the PWAs' `resetWeek` (a range of local
/// dates) and `resetEverything` (all of them).
public enum HistoryRemoval: Sendable, Equatable {
    /// Records with `from <= local_date <= through`.
    case dates(from: String, through: String)
    /// Every record.
    case all

    /// The last seven local dates of `now` (today inclusive), as `resetWeek` removes them (`recentDates(7)`).
    public static func week(endingAt now: Date, in timeZone: TimeZone) -> HistoryRemoval {
        let window = SessionCalendar.recentDates(7, endingAt: now, in: timeZone)
        return .dates(from: window[window.count - 1], through: window[0])
    }

    /// Rows of a table keyed by `local_date` that this removal covers.
    func covers(_ column: Column = Column("local_date")) -> SQLExpression {
        switch self {
        case let .dates(from, through): column >= from && column <= through
        case .all: true.sqlExpression
        }
    }
}
