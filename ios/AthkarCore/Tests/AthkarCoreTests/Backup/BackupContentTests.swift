import AthkarCore
import Foundation
import Testing

struct BackupContentTests {
    let content: ContentPacks

    init() throws {
        content = try RepoFile.content
    }

    func example(_ path: String) throws -> BackupEnvelope {
        try BackupEnvelope.decode(try RepoFile.data(path))
    }

    @Test func packsDecodeTheFieldsTheRulesRead() {
        let morning20 = content.adhkar.morning.first { $0.id == "morning-20" }
        #expect(morning20 == SessionItem(id: "morning-20", targetOptions: [1, 10, 100], defaultTarget: 100))
        #expect(content.adhkar.morning.first == SessionItem(id: "morning-01"))
        #expect(content.adhkar.morning.count == 26 && content.adhkar.evening.count == 24)
        #expect(content.ruqyahSegments.count == 15)
        #expect(content.ruqyahSegments.first == RuqyahSegment(id: "qaf-1-8", repeatCount: 1))
        #expect(content.ruqyahSegments.last == RuqyahSegment(id: "nas-1-6", repeatCount: 7))
    }

    @Test func packFieldMustMatch() throws {
        #expect(throws: ContentPackError.wrongPack(expected: "adhkar", found: "ruqyah")) {
            try ContentPacks.adhkar(from: try RepoFile.data("content/ruqyah.v1.json"))
        }
    }

    @Test func completedAtWithIncompleteCountersRecordsNoCompletion() throws {
        var envelope = try example("spec/backup/examples/athkar-pwa.athkarbackup")
        envelope.adhkar!.today.completedAt.morning = Instant.at("2026-09-23T06:00:00.000Z")
        let database = try AppDatabase.inMemory()
        try BackupImporter(database: database, content: content).importEnvelope(envelope)

        let morning = try database.adhkar.session(on: "2026-09-23", period: .morning)
        #expect(morning.completion == nil)
        #expect(morning.progress == ["morning-01": 1, "morning-02": 3, "morning-20": 250])
        let exported = try BackupExporter(database: database).export(
            app: .athkarPWA, today: "2026-09-23", timeZone: "Asia/Riyadh")
        #expect(exported.adhkar?.today.completedAt.morning == nil)
    }

    @Test func completeCountersWithoutCompletedAtRecordCounterCompletion() throws {
        var envelope = try example("spec/backup/examples/athkar-pwa.athkarbackup")
        // Every morning item at its target; morning-20 at its chosen target 10 rather than the default 100.
        var progress: [String: Double] = [:]
        for item in content.adhkar.morning {
            progress[item.id] = Double(item.id == "morning-20" ? 10 : item.count ?? 1)
        }
        envelope.adhkar!.today.progress.morning = progress
        envelope.adhkar!.today.completedAt.morning = nil

        let database = try AppDatabase.inMemory()
        try BackupImporter(database: database, content: content).importEnvelope(envelope)
        #expect(try database.adhkar.session(on: "2026-09-23", period: .morning).completion
                == AdhkarDay(localDate: "2026-09-23", period: .morning, completedAt: nil, completionOrigin: .counters))

        // One tap short of the chosen target: not complete.
        progress["morning-20"] = 9
        envelope.adhkar!.today.progress.morning = progress
        let short = try AppDatabase.inMemory()
        try BackupImporter(database: short, content: content).importEnvelope(envelope)
        #expect(try short.adhkar.session(on: "2026-09-23", period: .morning).completion == nil)
    }

    @Test func ruqyahCountsAreClampedToRepeatAndUnknownSegmentsDropped() throws {
        var envelope = try example("spec/backup/examples/ruqyah-pwa.athkarbackup")
        envelope.ruqyah!.today.counts["qaf-1-8"] = 999
        envelope.ruqyah!.today.counts["kafirun-1-6"] = 999
        envelope.ruqyah!.today.counts["retired-segment"] = 2
        let database = try AppDatabase.inMemory()
        try BackupImporter(database: database, content: content).importEnvelope(envelope)

        let counts = try database.ruqyah.counts(on: "2026-09-23")
        #expect(counts["qaf-1-8"] == 1)
        #expect(counts["kafirun-1-6"] == 7)
        #expect(counts["retired-segment"] == nil)
        #expect(counts.count == 15)
    }
}
