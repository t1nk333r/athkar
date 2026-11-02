import Foundation
import GRDB

extension BackupExporter {
    /// The native app's own backup (envelope format 2): every row of every user table, in one read. The location is
    /// written only with `includeLocation`, the per-export opt-in (NATIVE_APP_PLAN.md §11 item 12).
    public func exportNative(timeZone: String, exportedAt: Date = Date(),
                             includeLocation: Bool = false) throws -> NativeBackup {
        let backup = try database.writer.read { db in
            NativeBackup(
                meta: .init(exportedAt: exportedAt, timeZone: timeZone),
                preferences: try Tables.preferences(in: db),
                prayerSettings: try Tables.prayerSettings(in: db),
                adhkar: try Tables.adhkar(in: db),
                ruqyah: try Tables.ruqyah(in: db),
                suwar: try Tables.suwar(in: db),
                tasbih: try Tables.tasbih(in: db),
                prayers: try Tables.prayers(in: db),
                reminders: try Tables.reminders(in: db, includeLocation: includeLocation))
        }
        try backup.validate()
        return backup
    }
}

/// Each section of format 2, read from its tables.
private enum Tables {
    /// The stored value, or `nil` when the user never set it.
    static func stored<Value>(_ key: SettingKey<Value>, in db: Database) throws -> Value? {
        try SettingsRepository.value(in: db, for: key)
    }

    static func preferences(in db: Database) throws -> NativeBackup.Preferences {
        NativeBackup.Preferences(
            theme: try stored(.theme, in: db),
            textSize: try stored(.textSize, in: db),
            lineSpacing: try stored(.lineSpacing, in: db),
            haptics: try stored(.haptics, in: db),
            longOrder: try stored(.longOrder, in: db),
            longOrderPromptAnswered: try stored(.longOrderPromptAnswered, in: db),
            homePrayerRow: try stored(.homePrayerRow, in: db))
    }

    static func prayerSettings(in db: Database) throws -> NativeBackup.PrayerSettings {
        NativeBackup.PrayerSettings(
            calculationMethod: try stored(.calculationMethod, in: db),
            asrSchool: try stored(.asrSchool, in: db),
            highLatitudeRule: try stored(.highLatitudeRule, in: db),
            adjustments: try stored(.prayerAdjustments, in: db),
            hijriOffset: try stored(.hijriOffset, in: db),
            iqamaDelays: try stored(.iqamaDelays, in: db))
    }

    static func adhkar(in db: Database) throws -> NativeBackup.Adhkar {
        let days = try AdhkarDay.order(Column("local_date"), Column("period")).fetchAll(db)
        let items = try AdhkarItemProgress.order(Column("local_date"), Column("period"), Column("item_id")).fetchAll(db)
        return NativeBackup.Adhkar(
            days: days.map {
                .init(date: $0.localDate, period: $0.period, completedAt: $0.completedAt, origin: $0.completionOrigin)
            },
            items: items.map {
                .init(date: $0.localDate, period: $0.period, itemId: $0.itemId, count: $0.count, target: $0.target)
            })
    }

    static func ruqyah(in db: Database) throws -> NativeBackup.Ruqyah {
        NativeBackup.Ruqyah(
            days: try RuqyahDay.order(Column("local_date")).fetchAll(db).map {
                .init(date: $0.localDate, completedAt: $0.completedAt, origin: $0.completionOrigin)
            },
            segments: try RuqyahSegmentProgress.order(Column("local_date"), Column("segment_id")).fetchAll(db).map {
                .init(date: $0.localDate, segmentId: $0.segmentId, count: $0.count)
            },
            suras: try RuqyahSuraDay.order(Column("local_date"), Column("sura_id")).fetchAll(db).map {
                .init(date: $0.localDate, suraId: $0.suraId, completedAt: $0.completedAt)
            })
    }

    static func suwar(in db: Database) throws -> NativeBackup.Suwar {
        NativeBackup.Suwar(
            selected: try stored(.suwarSelectedSura, in: db),
            pages: try SuwarPageRead.order(Column("local_date"), Column("page_id")).fetchAll(db).map {
                .init(date: $0.localDate, suraId: $0.suraId, pageId: $0.pageId, readAt: $0.readAt)
            },
            suras: try SuwarSuraDay.order(Column("local_date"), Column("sura_id")).fetchAll(db).map {
                .init(date: $0.localDate, suraId: $0.suraId, completedAt: $0.completedAt)
            })
    }

    static func tasbih(in db: Database) throws -> NativeBackup.Tasbih {
        NativeBackup.Tasbih(
            selected: try stored(.tasbihSelected, in: db),
            target: try stored(.tasbihTarget, in: db),
            phrases: try stored(.tasbihCustomPhrases, in: db),
            counts: try TasbihCount.order(Column("local_date"), Column("first_use")).fetchAll(db).map {
                .init(date: $0.localDate, phrase: $0.phraseKey, count: $0.count, firstUse: $0.firstUse)
            })
    }

    static func prayers(in db: Database) throws -> NativeBackup.Prayers {
        // Fajr … Isha within a date, as the day lists them.
        let records = try PrayerRecord.order(Column("calculation_date")).fetchAll(db).sorted {
            ($0.calculationDate, ObligatoryPrayer.allCases.firstIndex(of: $0.prayerKey) ?? 0)
                < ($1.calculationDate, ObligatoryPrayer.allCases.firstIndex(of: $1.prayerKey) ?? 0)
        }
        return NativeBackup.Prayers(records: records.map {
            .init(date: $0.calculationDate, prayer: $0.prayerKey, zone: $0.zoneId, scheduledAt: $0.scheduledAt,
                  profile: $0.profileVersion, state: $0.state, timing: $0.timing, noonPrayer: $0.noonPrayer,
                  loggedAt: $0.loggedAt)
        })
    }

    static func reminders(in db: Database, includeLocation: Bool) throws -> NativeBackup.Reminders {
        let rules = try ReminderRule.order(Column("id")).fetchAll(db)
        let shown = try ReminderState.fetchAll(db)
        let location = includeLocation ? try LocationProfile.fetchOne(db) : nil
        return NativeBackup.Reminders(
            rules: rules.map {
                .init(id: $0.id, kind: $0.kind, prayer: $0.prayerKey, offsetMinutes: $0.offsetMinutes,
                      localTime: $0.localTime, weekdays: $0.weekdayMask, enabled: $0.enabled)
            },
            lastShown: Dictionary(uniqueKeysWithValues: shown.map { ($0.ruleId, $0.lastShownLocalDate) }),
            location: location.map {
                .init(latitude: $0.latitude, longitude: $0.longitude, label: $0.label, zoneId: $0.zoneId,
                      updatedAt: $0.updatedAt)
            })
    }
}
