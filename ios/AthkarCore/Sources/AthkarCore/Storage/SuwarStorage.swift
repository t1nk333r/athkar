import Foundation
import GRDB

/// One page of «سور» marked read on one local date (the athkar PWA's `athkar-suwar-v1.read[sura][page]`). Page IDs
/// are unique across the pack, so the page alone keys the row; `sura_id` names the sura it belongs to.
public struct SuwarPageRead: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "suwar_page_reads"

    public var localDate: String
    public var suraId: String
    public var pageId: String
    public var readAt: Date

    public init(localDate: String, suraId: String, pageId: String, readAt: Date) {
        self.localDate = localDate
        self.suraId = suraId
        self.pageId = pageId
        self.readAt = readAt
    }
}

/// One sura of «سور» completed on one local date (`athkar-suwar-v1`: `completedAt` for today, `history` for earlier
/// days). The row keeps when the sura's last page was read; unmarking a page or a scoped reset removes it, as the
/// PWA's `resetSuraPage` and `resetSuwarProgress` clear `completedAt`.
public struct SuwarSuraDay: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "suwar_sura_days"

    public var localDate: String
    /// The pack's sura ID: `kahf`, `yasin`, `saffat`, `waqiah`, `mulk`.
    public var suraId: String
    public var completedAt: Date

    public init(localDate: String, suraId: String, completedAt: Date) {
        self.localDate = localDate
        self.suraId = suraId
        self.completedAt = completedAt
    }
}

public struct SuwarRepository: Sendable {
    let writer: any DatabaseWriter

    /// The IDs of the pages read on `localDate`.
    public func readPages(on localDate: String) throws -> Set<String> {
        try writer.read { db in
            try SuwarPageRead.select(Column("page_id"), as: String.self)
                .filter(Column("local_date") == localDate)
                .fetchSet(db)
        }
    }

    /// Sura ID → when it was completed on `localDate` (`athkar-suwar-v1.completedAt`).
    public func suraDays(on localDate: String) throws -> [String: Date] {
        try writer.read { db in
            let rows = try SuwarSuraDay.filter(Column("local_date") == localDate).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.suraId, $0.completedAt) })
        }
    }

    /// `markPageRead`: records one page read, in one transaction with what it completes. With `completingSura`,
    /// also records the sura complete at `now`. Each row is inserted only when it is not already there: the first
    /// time is kept.
    public func markRead(_ pageId: String, of suraId: String, on localDate: String, completingSura: Bool = false,
                         at now: Date = Date()) throws {
        try writer.write { db in
            if try SuwarPageRead.fetchOne(db, key: ["local_date": localDate, "page_id": pageId]) == nil {
                try SuwarPageRead(localDate: localDate, suraId: suraId, pageId: pageId, readAt: now).insert(db)
            }
            if completingSura,
               try SuwarSuraDay.fetchOne(db, key: ["local_date": localDate, "sura_id": suraId]) == nil {
                try SuwarSuraDay(localDate: localDate, suraId: suraId, completedAt: now).insert(db)
            }
        }
    }

    /// `resetSuraPage`: the page is no longer read on `localDate` and its sura no longer complete, in one
    /// transaction.
    public func unmarkRead(_ pageId: String, of suraId: String, on localDate: String) throws {
        try writer.write { db in
            _ = try SuwarPageRead.deleteOne(db, key: ["local_date": localDate, "page_id": pageId])
            _ = try SuwarSuraDay.deleteOne(db, key: ["local_date": localDate, "sura_id": suraId])
        }
    }

    /// How many recorded days `removal` covers, as the athkar PWA's reset confirmations count `suwarState.history`:
    /// the distinct dates before `today` with a completed sura. Today's completed suras are today's progress.
    public func recordedDayCount(_ removal: HistoryRemoval, before today: String) throws -> Int {
        try writer.read { db in
            try SuwarSuraDay.select(Column("local_date"), as: String.self)
                .filter(removal.covers() && Column("local_date") < today)
                .fetchSet(db)
                .count
        }
    }

    /// The athkar PWA's scoped reset in one transaction: no page of `localDate` is read and no sura complete any
    /// more (`resetSuwarProgress`), and the pages and completed suras `removal` covers are deleted
    /// (`deleteSuwarHistory`). Without a removal, earlier days keep their records.
    public func reset(on localDate: String, removing removal: HistoryRemoval? = nil) throws {
        try writer.write { db in
            try SuwarPageRead.filter(Column("local_date") == localDate).deleteAll(db)
            try SuwarSuraDay.filter(Column("local_date") == localDate).deleteAll(db)
            if let removal {
                try SuwarPageRead.filter(removal.covers()).deleteAll(db)
                try SuwarSuraDay.filter(removal.covers()).deleteAll(db)
            }
        }
    }
}
