import AthkarCore
import Foundation
import Testing

/// `spec/night/fixtures/night.json`: the PWA's `fridayPhase` and `tonightLastThird` on the same Maghrib and Fajr.
struct NightTimesTests {
    private struct Fixture: Decodable {
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }

    private struct Input: Decodable {
        let function: String
        let timeZone: String
        let now: String
        let times: [String: Times?]
    }

    private struct Times: Decodable {
        let fajr: String?
        let maghrib: String?
    }

    /// `"night"`, `"day"`, `{start, end}` or `null`.
    private enum Expected: Decodable {
        case phase(String)
        case third(start: String, end: String)
        case none

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .none
            } else if let phase = try? container.decode(String.self) {
                self = .phase(phase)
            } else {
                let third = try container.decode([String: String].self)
                self = .third(start: third["start"] ?? "", end: third["end"] ?? "")
            }
        }
    }

    /// `<repo>/spec/night/fixtures/night.json`, found from this file's location
    /// (`<repo>/ios/AthkarCore/Tests/AthkarCoreTests/PrayerTimes/`).
    private static func cases() throws -> [Case] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appending(path: "spec/night/fixtures/night.json"))
        return try JSONDecoder().decode(Fixture.self, from: data).cases
    }

    private static func instant(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: text), "\(text)")
    }

    private static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    @Test func matchesThePWAOnEveryFixtureCase() throws {
        let cases = try Self.cases()
        #expect(cases.count > 20)
        for fixture in cases {
            let input = fixture.input
            let zone = try #require(TimeZone(identifier: input.timeZone))
            let now = try Self.instant(input.now)
            var table: [String: NightTimes] = [:]
            for (date, times) in input.times {
                guard let times else { continue }
                table[date] = NightTimes(fajr: try times.fajr.map(Self.instant),
                                         maghrib: try times.maghrib.map(Self.instant))
            }
            let lookup = { (date: String) in table[date] }
            switch input.function {
            case "fridayPhase":
                let phase = FridayPhase.at(now, in: zone, times: lookup)
                switch fixture.expected {
                case let .phase(expected): #expect(phase?.rawValue == expected, "\(fixture.name)")
                case .none: #expect(phase == nil, "\(fixture.name)")
                case .third: Issue.record("\(fixture.name): a third for fridayPhase")
                }
            case "tonightLastThird":
                let third = LastThird.tonight(at: now, in: zone, times: lookup)
                switch fixture.expected {
                case let .third(start, end):
                    #expect(third.map { Self.milliseconds($0.start) } == Self.milliseconds(try Self.instant(start)),
                            "\(fixture.name)")
                    #expect(third.map { Self.milliseconds($0.end) } == Self.milliseconds(try Self.instant(end)),
                            "\(fixture.name)")
                case .none: #expect(third == nil, "\(fixture.name)")
                case .phase: Issue.record("\(fixture.name): a phase for tonightLastThird")
                }
            default:
                Issue.record("\(fixture.name): unknown function \(input.function)")
            }
        }
    }

    @Test func theNightAfterADayRunsFromItsMaghribToTheNextFajr() {
        let maghrib = Date(timeIntervalSince1970: 15 * 3600)
        let fajr = Date(timeIntervalSince1970: 27 * 3600)
        let times = ["2026-11-12": NightTimes(fajr: nil, maghrib: maghrib),
                     "2026-11-13": NightTimes(fajr: fajr, maghrib: nil)]
        let third = LastThird.night(after: "2026-11-12") { times[$0] }
        #expect(third?.start == Date(timeIntervalSince1970: 23 * 3600))
        #expect(third?.end == fajr)
        #expect(third?.contains(Date(timeIntervalSince1970: 23 * 3600)) == true)
        #expect(third?.contains(fajr) == false)
        #expect(LastThird.night(after: "2026-11-13") { times[$0] } == nil)
    }
}
